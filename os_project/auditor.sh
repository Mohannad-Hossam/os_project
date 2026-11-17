#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

TARGET_DIR="${1:-.}"
ACTION="${2:-}"
LOG_FILE="$SCRIPT_DIR/auditor.log"
BACKUP_DIR="$TARGET_DIR/backups"

# Scan the selected directory and count files and folders.
scan_directory() {
    local dir="$1"
    local file_count=0
    local folder_count=0
    local item
    local name

    log_action "scan_directory: $dir" "$LOG_FILE"

    while IFS= read -r -d '' item; do
        name="$(basename "$item")"

        if [[ -f "$item" ]]; then
            echo "[file] $name"
            ((file_count++))
        elif [[ -d "$item" ]]; then
            echo "[dir ] $name"
            ((folder_count++))
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 | sort -z)

    echo
    echo "Files: $file_count     Folders: $folder_count"
}

# Audit read, write, and execute permissions for every regular file.
permission_audit() {
    local dir="$1"
    local file
    local permissions
    local unreadable=0
    local executable=0

    log_action "permission_audit: $dir" "$LOG_FILE"

    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            permissions="---"

            if [[ -r "$file" ]]; then
                permissions="r--"
            fi

            if [[ -w "$file" ]]; then
                if [[ "$permissions" == "r--" ]]; then
                    permissions="rw-"
                else
                    permissions="-w-"
                fi
            fi

            if [[ -x "$file" ]]; then
                if [[ "$permissions" == "---" ]]; then
                    permissions="--x"
                elif [[ "$permissions" == "r--" ]]; then
                    permissions="r-x"
                elif [[ "$permissions" == "-w-" ]]; then
                    permissions="-wx"
                elif [[ "$permissions" == "rw-" ]]; then
                    permissions="rwx"
                fi

                ((executable++))
            fi

            if [[ ! -r "$file" ]]; then
                ((unreadable++))
            fi

            printf "%-4s %s\n" "$permissions" "$(basename "$file")"
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)

    echo
    echo "Unreadable files: $unreadable       Executable files: $executable"
}

# Count files by extension using an associative array.
extension_report() {
    local dir="$1"
    local file
    local filename
    local extension

    declare -A extension_count

    extension_count[txt]=0
    extension_count[log]=0
    extension_count[sh]=0
    extension_count[jpg]=0
    extension_count[other]=0

    log_action "extension_report: $dir" "$LOG_FILE"

    while IFS= read -r -d '' file; do
        filename="$(basename "$file")"

        if [[ "$filename" == *.* ]]; then
            extension="${filename##*.}"
        else
            extension="other"
        fi

        if [[ "$extension" == "txt" ]]; then
            ((extension_count[txt]++))
        elif [[ "$extension" == "log" ]]; then
            ((extension_count[log]++))
        elif [[ "$extension" == "sh" ]]; then
            ((extension_count[sh]++))
        elif [[ "$extension" == "jpg" ]]; then
            ((extension_count[jpg]++))
        else
            ((extension_count[other]++))
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0)

    echo "jpg : ${extension_count[jpg]}"
    echo "log : ${extension_count[log]}"
    echo "other : ${extension_count[other]}"
    echo "sh : ${extension_count[sh]}"
    echo "txt : ${extension_count[txt]}"
}

# Search for files whose names contain text entered by the user.
search_file() {
    local dir="$1"
    local search_text
    local file
    local found=0

    log_action "search_file: $dir" "$LOG_FILE"

    read -r -p "Enter text to search for: " search_text

    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            if [[ "$(basename "$file")" == *"$search_text"* ]]; then
                echo "$(basename "$file")"
                found=1
            fi
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0)

    if [[ "$found" -eq 0 ]]; then
        echo "No files matched."
    fi
}

# Back up every readable regular file with a timestamped name.
backup_all() {
    local dir="$1"
    local backup_dir="$2"
    local file
    local filename
    local timestamp
    local saved=0
    local skipped=0

    log_action "backup_all: $dir" "$LOG_FILE"

    mkdir -p "$backup_dir"

    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            filename="$(basename "$file")"

            if [[ -r "$file" ]]; then
                timestamp="$(date '+%Y%m%d_%H%M%S')"
                cp "$file" "$backup_dir/${filename}_${timestamp}.bak"
                ((saved++))
            else
                log_error "Skipping unreadable file: $filename"
                ((skipped++))
            fi
        fi
    done < <(
        find "$dir" \
            -mindepth 1 \
            -maxdepth 1 \
            -type f \
            -print0
    )

    echo "Files saved: $saved"
    echo "Files skipped: $skipped"
}

# List the names of all saved backup files.
list_backups() {
    local backup_dir="$1"
    local backup

    log_action "list_backups: $backup_dir" "$LOG_FILE"

    if [[ ! -d "$backup_dir" ]]; then
        echo "(no backups yet)"
        return 0
    fi

    if ! find "$backup_dir" -maxdepth 1 -type f -name "*.bak" -print -quit | grep -q .; then
        echo "(no backups yet)"
        return 0
    fi

    while IFS= read -r -d '' backup; do
        basename "$backup"
    done < <(
        find "$backup_dir" \
            -maxdepth 1 \
            -type f \
            -name "*.bak" \
            -print0 | sort -z
    )
}

# Restore a selected backup without overwriting an original file.
restore_backup() {
    local dir="$1"
    local backup_dir="$2"
    local backup_name
    local backup_path
    local restored_name

    log_action "restore_backup: $dir" "$LOG_FILE"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory does not exist."
        return 1
    fi

    read -r -p "Enter backup name to restore: " backup_name

    backup_path="$backup_dir/$backup_name"

    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup does not exist: $backup_name"
        return 1
    fi

    restored_name="restored_$backup_name"

    if [[ -e "$dir/$restored_name" ]]; then
        log_error "Restore target already exists: $restored_name"
        return 1
    fi

    cp "$backup_path" "$dir/$restored_name"

    echo "Restored as: $restored_name"
}

# Display the menu and continue until the user chooses Exit.
show_menu() {
    local choice

    while true; do
        echo
        echo "================================"
        echo "       FILE AUDITOR & BACKUP"
        echo "================================"
        echo "1. Scan directory"
        echo "2. Permission audit"
        echo "3. Extension report"
        echo "4. Search for a file"
        echo "5. Backup all readable files"
        echo "6. List backups"
        echo "7. Restore backup"
        echo "8. Exit"
        echo "================================"

        read -r -p "Enter your choice: " choice

        if [[ "$choice" == "1" ]]; then
            scan_directory "$TARGET_DIR"
        elif [[ "$choice" == "2" ]]; then
            permission_audit "$TARGET_DIR"
        elif [[ "$choice" == "3" ]]; then
            extension_report "$TARGET_DIR"
        elif [[ "$choice" == "4" ]]; then
            search_file "$TARGET_DIR"
        elif [[ "$choice" == "5" ]]; then
            backup_all "$TARGET_DIR" "$BACKUP_DIR"
        elif [[ "$choice" == "6" ]]; then
            list_backups "$BACKUP_DIR"
        elif [[ "$choice" == "7" ]]; then
            restore_backup "$TARGET_DIR" "$BACKUP_DIR"
        elif [[ "$choice" == "8" ]]; then
            echo "Exiting..."
            break
        else
            log_error "Invalid choice."
        fi
    done
}

# Validate the directory and run the requested command-line action.
main() {
    if ! require_dir "$TARGET_DIR"; then
        exit 1
    fi

    if [[ -z "$ACTION" ]]; then
        show_menu
    elif [[ "$ACTION" == "scan" ]]; then
        scan_directory "$TARGET_DIR"
    elif [[ "$ACTION" == "perms" ]]; then
        permission_audit "$TARGET_DIR"
    elif [[ "$ACTION" == "ext" ]]; then
        extension_report "$TARGET_DIR"
    elif [[ "$ACTION" == "backup" ]]; then
        backup_all "$TARGET_DIR" "$BACKUP_DIR"
    else
        log_error "Unknown action: $ACTION"
        echo "Valid actions: scan | perms | ext | backup"
        return 1
    fi
}

main

