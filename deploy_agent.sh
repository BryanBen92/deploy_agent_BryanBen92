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

