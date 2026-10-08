#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "ERROR: cannot enter $SCRIPT_DIR" >&2; exit 1; }

TEMPLATES_DIR="templates"
PREFIX="attendance_tracker_"

TARGET_DIR=""
OWNED=0
BACKUP_DIR=""
SELECTED=""

msg() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

ask() {
    IFS= read -r -p "$2" "$1" || return 1
    return 0
}

ask_yes_no() {
    local reply
    while true; do
        ask reply "$1" || return 1
        case "$reply" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No|"") return 1 ;;
            *) msg "  Please answer y or n." ;;
        esac
    done
}

ask_int() {
    local __v
    while true; do
        ask __v "$2" || return 1
        if [[ "$__v" =~ ^[0-9]+$ ]] && (( 10#$__v >= $3 && 10#$__v <= $4 )); then
            printf -v "$1" '%d' "$((10#$__v))"
            return 0
        fi
        msg "  Invalid input. Enter a whole number from $3 to $4."
    done
}

ask_threshold() {
    local __v
    while true; do
        ask __v "$2" || return 1
        if [[ -z "$__v" ]]; then
            printf -v "$1" '%d' "$3"
            return 0
        fi
        if [[ "$__v" =~ ^[0-9]+$ ]] && (( 10#$__v >= 0 && 10#$__v <= 100 )); then
            printf -v "$1" '%d' "$((10#$__v))"
            return 0
        fi
        msg "  Invalid input. Enter a whole number from 0 to 100 (or press Enter for $3)."
    done
}

sed_inplace() {
    sed -i.bak -E "$1" "$2" && rm -f "$2.bak"
}

step() {
    "$@" || { err "Command failed: $*"; return 1; }
}

restore_backup() {
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" && -n "$TARGET_DIR" ]]; then
        if mv "$BACKUP_DIR" "$TARGET_DIR"; then
            msg "Restored your previous '$TARGET_DIR'."
        else
            err "Could not restore backup; it is still at '$BACKUP_DIR'."
        fi
    fi
    BACKUP_DIR=""
}

rollback() {
    if (( OWNED )) && [[ -d "$TARGET_DIR" ]]; then
        rm -rf "$TARGET_DIR" && msg "Removed incomplete '$TARGET_DIR'."
    fi
    OWNED=0
    restore_backup
}

on_interrupt() {
    local sig="$1" zipname
    trap '' INT TSTP
    echo
    echo "!! Deployment interrupted by $sig."

    if (( OWNED )) && [[ -d "$TARGET_DIR" ]]; then
        zipname="${TARGET_DIR}_archive.zip"
        rm -f "$zipname"
        if zip -rq "$zipname" "$TARGET_DIR"; then
            echo "   Archived the incomplete project to: $zipname"
            if rm -rf "$TARGET_DIR"; then
                echo "   Removed the incomplete directory: $TARGET_DIR"
            else
                echo "   Could not remove $TARGET_DIR (check permissions)." >&2
            fi
        else
            echo "   zip failed, so '$TARGET_DIR' was kept to avoid losing work." >&2
        fi
    else
        echo "   Nothing had been created yet, so there is nothing to archive."
    fi

    OWNED=0
    restore_backup
    echo "   Session closed cleanly."
    exit 130
}

enable_traps()  { trap 'on_interrupt SIGINT' INT; trap 'on_interrupt SIGTSTP' TSTP; }
disable_traps() { trap - INT TSTP; }

preflight() {
    local tool f ok=1
    msg "Running pre-flight checks..."
    for tool in python3 zip; do
        if command -v "$tool" >/dev/null 2>&1; then
            msg "  [ok] $tool found"
        else
            err "$tool is not installed or not on your PATH. Install it and try again."
            ok=0
        fi
    done
    (( ok )) || return 1

    if ! python3 --version >/dev/null 2>&1; then
        err "python3 was found but 'python3 --version' failed."
        return 1
    fi
    msg "  [ok] $(python3 --version 2>&1)"

    for f in attendance_checker.py assets.csv config.json; do
        if [[ ! -f "$TEMPLATES_DIR/$f" ]]; then
            err "Missing template: $TEMPLATES_DIR/$f"
            return 1
        fi
    done
    msg "  [ok] templates found"
    return 0
}

generate_roster() {
    local n="$1" file="$2" i f l email
    local FIRST=(Alice Bob Carol David Emma Frank Grace Henry Irene James)
    local LAST=(Johnson Smith Williams Brown Jones Garcia Miller Davis Mugabo Uwase)
    {
        echo "Email,Names,Attendance Count,Absence Count"
        for ((i = 0; i < n; i++)); do
            f="${FIRST[i % 10]}"
            l="${LAST[(i / 10 + i % 10) % 10]}"
            email="$(printf '%s.%s@example.com' "$f" "$l" | tr 'A-Z' 'a-z')"
            echo "$email,$f $l,0,0"
        done
    } > "$file"
}

build_roster() {
    local choice n available
    local assets="$TARGET_DIR/Helpers/assets.csv"
    local config="$TARGET_DIR/Helpers/config.json"

    while true; do
        msg ""
        msg "How should the student roster be built?"
        msg "  A) Copy rows from templates/assets.csv (4 prior sessions each)"
        msg "  B) Generate a fresh roster (all counts start at 0)"
        ask choice "Choose A or B: " || return 1
        case "$choice" in
            a|A)
                available="$(awk 'END{print NR-1}' "$TEMPLATES_DIR/assets.csv")"
                ask_int n "How many students to copy (1-$available)? " 1 "$available" || return 1
                step head -n "$((n + 1))" "$TEMPLATES_DIR/assets.csv" > "$assets" || return 1
                msg "  Copied $n student(s). total_sessions stays at 5 (4 prior + today)."
                return 0
                ;;
            b|B)
                ask_int n "How many students to generate (1-100)? " 1 100 || return 1
                generate_roster "$n" "$assets" || { err "Could not write $assets"; return 1; }
                step sed_inplace 's/("total_sessions": *)[0-9]+/\11/' "$config" || return 1
                msg "  Generated $n student(s). total_sessions set to 1 (first session)."
                return 0
                ;;
            *) msg "  Please enter A or B." ;;
        esac
    done
}

configure_thresholds() {
    local config="$TARGET_DIR/Helpers/config.json" w f
    msg ""
    ask_yes_no "Update the attendance alert thresholds? [y/N]: " || {
        msg "  Keeping thresholds from the template (warning 75, failure 50)."
        return 0
    }
    while true; do
        ask_threshold w "  New warning threshold [75]: " 75 || return 1
        ask_threshold f "  New failure threshold [50]: " 50 || return 1
        if (( w > f )); then break; fi
        msg "  The warning threshold ($w) must be higher than the failure threshold ($f). Try again."
    done
    step sed_inplace 's/("warning": *)[0-9]+/\1'"$w"'/' "$config" || return 1
    step sed_inplace 's/("failure": *)[0-9]+/\1'"$f"'/' "$config" || return 1
    msg "  Updated config.json:"
    grep -E '"(warning|failure|total_sessions)"' "$config" | sed 's/^/    /'
    return 0
}

build_project() {
    step mkdir -p "$TARGET_DIR/Helpers" "$TARGET_DIR/reports" || return 1
    step cp "$TEMPLATES_DIR/attendance_checker.py" "$TARGET_DIR/attendance_checker.py" || return 1
    step cp "$TEMPLATES_DIR/config.json" "$TARGET_DIR/Helpers/config.json" || return 1
    build_roster || return 1

    step chmod +x "$TARGET_DIR/attendance_checker.py" || return 1
    step chmod 600 "$TARGET_DIR/Helpers/config.json" || return 1
    msg ""
    msg "Permissions set:"
    ls -l "$TARGET_DIR/attendance_checker.py" "$TARGET_DIR/Helpers/config.json" |
        awk '{print "  " $1 "  " $NF}'

    configure_thresholds || return 1
    return 0
}

deploy_project() {
    local name rc
    TARGET_DIR=""; OWNED=0; BACKUP_DIR=""

    enable_traps

    if ! preflight; then disable_traps; return 1; fi

    msg ""
    while true; do
        ask name "Project name (creates ${PREFIX}<name>): " || { disable_traps; return 1; }
        if [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then break; fi
        msg "  Use letters, digits, '_' or '-' only (no spaces or empty names)."
    done
    TARGET_DIR="${PREFIX}${name}"

    if [[ -e "$TARGET_DIR" ]]; then
        err "'$TARGET_DIR' already exists."
        if ask_yes_no "Overwrite it? Your old copy is kept until the new deploy succeeds [y/N]: "; then
            BACKUP_DIR="${TARGET_DIR}.bak.$$"
            if ! mv "$TARGET_DIR" "$BACKUP_DIR"; then
                err "Could not move the existing project aside (permission denied?). Aborting."
                BACKUP_DIR=""; TARGET_DIR=""; disable_traps; return 1
            fi
        else
            msg "Aborted. Nothing was changed."
            TARGET_DIR=""; disable_traps; return 1
        fi
    fi

    OWNED=1
    if ! build_project; then
        err "Deployment failed. Rolling back."
        rollback
        disable_traps
        return 1
    fi

    if [[ -n "$BACKUP_DIR" ]]; then rm -rf "$BACKUP_DIR"; BACKUP_DIR=""; fi
    OWNED=0
    disable_traps

    msg ""
    msg "Deployment of '$TARGET_DIR' complete. Verifying by starting the app..."
    run_app "$TARGET_DIR"; rc=$?
    if (( rc == 0 || rc == 130 )); then
        msg "Verification passed: the application started and read its roster and config."
    else
        err "The application exited with code $rc. Check the messages above."
        return 1
    fi
    return 0
}

run_app() {
    local dir="$1"
    if [[ ! -f "$dir/attendance_checker.py" ]]; then
        err "'$dir' does not look like a deployed project."
        return 1
    fi
    ( cd "$dir" && python3 attendance_checker.py )
}

choose_project() {
    local dirs=() d i pick
    for d in "${PREFIX}"*; do
        [[ -d "$d" && "$d" != *.bak.* ]] && dirs+=("$d")
    done
    if (( ${#dirs[@]} == 0 )); then
        err "No deployed projects found here. Run Deploy (option 1) first."
        return 1
    fi
    msg "Deployed projects:"
    for i in "${!dirs[@]}"; do msg "  $((i + 1))) ${dirs[$i]}"; done
    while true; do
        ask pick "Choose a number or type the project name: " || return 1
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#dirs[@]} )); then
            SELECTED="${dirs[$((pick - 1))]}"; return 0
        fi
        for d in "${dirs[@]}"; do
            if [[ "$pick" == "$d" || "${PREFIX}${pick}" == "$d" ]]; then
                SELECTED="$d"; return 0
            fi
        done
        msg "  Not recognised. Try again."
    done
}

run_feature() {
    choose_project || return 1
    run_app "$SELECTED"
}

archive_logs() {
    local dir ts kind src dest_dir dest n archived=0 skipped=0
    choose_project || return 1
    dir="$SELECTED"
    ts="$(date +%Y%m%d_%H%M%S)"

    msg "Archiving logs from '$dir' (timestamp $ts)..."
    for kind in attendance absent; do
        src="$dir/reports/${kind}.log"
        dest_dir="$dir/archives/${kind}"
        dest="$dest_dir/${kind}_${ts}.log"
        if [[ ! -f "$src" ]]; then
            msg "  - ${kind}.log not found (nothing to archive; skipped)"
            skipped=$((skipped + 1))
            continue
        fi
        n=1
        while [[ -e "$dest" ]]; do
            dest="$dest_dir/${kind}_${ts}_${n}.log"; n=$((n + 1))
        done
        if mkdir -p "$dest_dir" && cp "$src" "$dest"; then
            msg "  + archived ${kind}.log -> $dest"
            archived=$((archived + 1))
        else
            err "Could not archive $src (permission denied?)"
        fi
    done
    msg "Done: $archived archived, $skipped skipped."
    (( archived > 0 ))
}

show_menu() {
    msg ""
    msg "=============================================="
    msg "  deploy_agent: Attendance Tracker Bootstrapper"
    msg "=============================================="
    msg "  1) Deploy a new project"
    msg "  2) Run the application on a deployed project"
    msg "  3) Archive logs of a deployed project"
    msg "  4) Exit"
}

main() {
    local choice
    case "${1:-}" in
        deploy)  deploy_project;  exit $? ;;
        run)     run_feature;     exit $? ;;
        archive) archive_logs;    exit $? ;;
        "")      ;;
        *) err "Unknown option '$1'. Use: deploy | run | archive (or no argument for the menu)."; exit 2 ;;
    esac

    while true; do
        show_menu
        ask choice "Select an option [1-4]: " || { echo; exit 0; }
        case "$choice" in
            1) deploy_project ;;
            2) run_feature ;;
            3) archive_logs ;;
            4) msg "Goodbye."; exit 0 ;;
            *) msg "Please enter 1, 2, 3 or 4." ;;
        esac
    done
}

main "$@"
