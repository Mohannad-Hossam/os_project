#!/bin/bash

log_info() {
    local message="$1"
    echo "[INFO] $message"
}

log_error() {
    local message="$1"
    echo "[ERROR] $message" >&2
}

log_action() {
    local action="$1"
    local logfile="$2"

    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$action" >> "$logfile"
}

require_dir() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log_error "Directory does not exist: $dir"
        return 1
    fi

    return 0
}

