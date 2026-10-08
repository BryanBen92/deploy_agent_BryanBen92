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

