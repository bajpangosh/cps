#!/bin/bash

# CyberPanel Backup Manager
# Wrapper around CyberPanel's native backup/restore CLI with safety helpers.
# Version 1.0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_TAG="cps-backup-manager"
ROOT_BACKUP_DIR="/home/backup"

print_banner() {
    clear
    echo -e "${CYAN}"
    echo " ######  ##    ## ########  ######## ########  ########     ###    ##    ## ######## ##"
    echo "##    ##  ##  ##  ##     ## ##       ##     ## ##     ##   ## ##   ###   ## ##       ##"
    echo "##         ####   ##     ## ##       ##     ## ##     ##  ##   ##  ####  ## ##       ##"
    echo "##          ##    ########  ######   ########  ########  ##     ## ## ## ## ######   ##"
    echo "##          ##    ##     ## ##       ##   ##   ##        ######### ##  #### ##       ##"
    echo "##    ##    ##    ##     ## ##       ##    ##  ##        ##     ## ##   ### ##       ##"
    echo " ######     ##    ########  ######## ##     ## ##        ##     ## ##    ## ######## ########"
    echo -e "${NC}"
    echo -e "${BLUE}   CyberPanel Backup Manager${NC}"
    echo -e "${YELLOW}   Native backup/restore wrapper + retention + verification${NC}"
    echo ""
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root.${NC}"
        exit 1
    fi
}

check_prereqs() {
    if ! command -v cyberpanel >/dev/null 2>&1; then
        echo -e "${RED}cyberpanel CLI command not found.${NC}"
        echo -e "${YELLOW}Install/repair CyberPanel CLI first, then rerun this tool.${NC}"
        exit 1
    fi

    mkdir -p "$ROOT_BACKUP_DIR"
}

ensure_crontab_available() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo -e "${RED}crontab command not found. Install cron package and retry.${NC}"
        return 1
    fi
    return 0
}

confirm_action() {
    local prompt="$1"
    local answer=""
    read -r -p "$prompt [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_for_number() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local input=""

    while true; do
        read -r -p "$prompt" input
        if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge "$min" ] && [ "$input" -le "$max" ]; then
            echo "$input"
            return 0
        fi
        echo -e "${YELLOW}Please enter a number between ${min} and ${max}.${NC}"
    done
}

prompt_for_default_number() {
    local prompt="$1"
    local default_value="$2"
    local min="$3"
    local max="$4"
    local input=""

    while true; do
        read -r -p "$prompt [$default_value]: " input
        input=${input:-$default_value}
        if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge "$min" ] && [ "$input" -le "$max" ]; then
            echo "$input"
            return 0
        fi
        echo -e "${YELLOW}Please enter a number between ${min} and ${max}.${NC}"
    done
}

discover_domains() {
    mapfile -t DOMAINS < <(find /home -mindepth 2 -maxdepth 2 -type d -name public_html -printf '%h\n' 2>/dev/null | awk -F/ '{print $3}' | sort -u)
}

select_domain() {
    discover_domains

    if [ ${#DOMAINS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No domains with /home/<domain>/public_html found.${NC}"
        return 1
    fi

    echo -e "${BLUE}Available Domains:${NC}"
    local i=1
    for domain in "${DOMAINS[@]}"; do
        echo " [$i] $domain"
        ((i++))
    done
    echo " [$i] Back"

    local selection
    selection=$(prompt_for_number "Select domain: " 1 "$i")
    if [ "$selection" -eq "$i" ]; then
        return 1
    fi

    SELECTED_DOMAIN="${DOMAINS[$((selection-1))]}"
    return 0
}

discover_backup_files() {
    local tmp_file
    tmp_file=$(mktemp)

    if [[ -d "$ROOT_BACKUP_DIR" ]]; then
        find "$ROOT_BACKUP_DIR" -maxdepth 2 -type f \( -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" \) -print 2>/dev/null >> "$tmp_file"
    fi

    find /home -mindepth 3 -maxdepth 3 -type f -path "/home/*/backup/*" \( -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" \) -print 2>/dev/null >> "$tmp_file"

    mapfile -t BACKUP_FILES < <(sort -u "$tmp_file")
    rm -f "$tmp_file"
}

select_backup_file() {
    discover_backup_files

    if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No backup files found in /home/*/backup or /home/backup.${NC}"
        return 1
    fi

    echo -e "${BLUE}Available Backup Files:${NC}"
    local idx=1
    local file=""
    for file in "${BACKUP_FILES[@]}"; do
        local size
        size=$(du -h "$file" 2>/dev/null | awk '{print $1}')
        local mtime
        mtime=$(date -r "$file" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$file" 2>/dev/null | cut -d'.' -f1)
        printf " [%d] %s | %s | %s\n" "$idx" "${size:-?}" "${mtime:-?}" "$file"
        ((idx++))
    done
    echo " [$idx] Back"

    local selection
    selection=$(prompt_for_number "Select backup file: " 1 "$idx")
    if [ "$selection" -eq "$idx" ]; then
        return 1
    fi

    SELECTED_BACKUP_FILE="${BACKUP_FILES[$((selection-1))]}"
    return 0
}

create_backup_for_domain() {
    if ! select_domain; then
        return
    fi

    echo -e "${BLUE}Running backup for domain:${NC} ${GREEN}${SELECTED_DOMAIN}${NC}"
    echo -e "${YELLOW}This uses native CyberPanel CLI: cyberpanel createBackup --domainName ${SELECTED_DOMAIN}${NC}"

    if ! cyberpanel createBackup --domainName "$SELECTED_DOMAIN"; then
        echo -e "${RED}Backup command failed.${NC}"
        return
    fi

    local domain_backup_dir="/home/${SELECTED_DOMAIN}/backup"
    if [[ -d "$domain_backup_dir" ]]; then
        local latest_backup
        latest_backup=$(find "$domain_backup_dir" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | awk '{print $2}')
        if [[ -n "$latest_backup" ]]; then
            echo -e "${GREEN}Backup completed:${NC} $latest_backup"
            if confirm_action "Copy latest backup into ${ROOT_BACKUP_DIR} for easier restore discovery"; then
                cp -f "$latest_backup" "$ROOT_BACKUP_DIR/"
                echo -e "${GREEN}Copied to ${ROOT_BACKUP_DIR}/$(basename "$latest_backup")${NC}"
            fi
        fi
    fi
}

restore_backup_file() {
    if ! select_backup_file; then
        return
    fi

    echo -e "${YELLOW}Restore target:${NC} ${SELECTED_BACKUP_FILE}"
    echo -e "${RED}Restore may overwrite site files and databases.${NC}"
    if ! confirm_action "Proceed with restore"; then
        echo "Cancelled."
        return
    fi

    local restore_arg
    if [[ "$SELECTED_BACKUP_FILE" == "${ROOT_BACKUP_DIR}/"* ]]; then
        restore_arg="$(basename "$SELECTED_BACKUP_FILE")"
    else
        restore_arg="$(basename "$SELECTED_BACKUP_FILE")"
        local pooled_file="${ROOT_BACKUP_DIR}/${restore_arg}"
        echo -e "${YELLOW}Copying selected backup into ${ROOT_BACKUP_DIR} for restore compatibility...${NC}"
        if ! cp -f "$SELECTED_BACKUP_FILE" "$pooled_file"; then
            echo -e "${RED}Failed to copy backup into ${ROOT_BACKUP_DIR}. Restore aborted.${NC}"
            return
        fi
        echo -e "${GREEN}Copied:${NC} ${pooled_file}"
    fi

    cyberpanel restoreBackup --fileName "$restore_arg"
}

copy_backup_to_root_pool() {
    if ! select_backup_file; then
        return
    fi

    local dst="${ROOT_BACKUP_DIR}/$(basename "$SELECTED_BACKUP_FILE")"
    if [[ "$SELECTED_BACKUP_FILE" == "$dst" ]]; then
        echo -e "${GREEN}File is already in ${ROOT_BACKUP_DIR}.${NC}"
        return
    fi

    cp -f "$SELECTED_BACKUP_FILE" "$dst"
    echo -e "${GREEN}Copied:${NC} $dst"
}

list_backup_inventory() {
    discover_backup_files
    if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No backups found.${NC}"
        return
    fi

    echo -e "${BLUE}Backup Inventory:${NC}"
    local total_bytes=0
    local file=""
    for file in "${BACKUP_FILES[@]}"; do
        local size_bytes=0
        size_bytes=$(stat -c '%s' "$file" 2>/dev/null || echo 0)
        total_bytes=$((total_bytes + size_bytes))
        local size_h
        size_h=$(du -h "$file" 2>/dev/null | awk '{print $1}')
        local mtime
        mtime=$(date -r "$file" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$file" 2>/dev/null | cut -d'.' -f1)
        printf " - %-10s | %-16s | %s\n" "${size_h:-?}" "${mtime:-?}" "$file"
    done

    local total_h
    total_h=$(numfmt --to=iec --suffix=B "$total_bytes" 2>/dev/null || echo "${total_bytes}B")
    echo ""
    echo -e "${GREEN}Total backups:${NC} ${#BACKUP_FILES[@]}"
    echo -e "${GREEN}Total size:${NC} ${total_h}"
}

verify_backup_file() {
    if ! select_backup_file; then
        return
    fi

    local file="$SELECTED_BACKUP_FILE"
    echo -e "${BLUE}Verifying archive:${NC} $file"

    case "$file" in
        *.tar.gz|*.tgz)
            if tar -tzf "$file" >/dev/null 2>&1; then
                echo -e "${GREEN}Archive verification passed.${NC}"
            else
                echo -e "${RED}Archive verification failed.${NC}"
            fi
            ;;
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                if unzip -t "$file" >/dev/null 2>&1; then
                    echo -e "${GREEN}Archive verification passed.${NC}"
                else
                    echo -e "${RED}Archive verification failed.${NC}"
                fi
            else
                echo -e "${YELLOW}unzip command not found. Cannot verify .zip files.${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}Unsupported file extension for verification.${NC}"
            ;;
    esac
}

prune_old_backups() {
    local days
    days=$(prompt_for_default_number "Delete backups older than how many days?" 14 1 3650)

    mapfile -t OLD_FILES < <(
        {
            find "$ROOT_BACKUP_DIR" -maxdepth 2 -type f \( -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" \) -mtime +"$days" -print 2>/dev/null
            find /home -mindepth 3 -maxdepth 3 -type f -path "/home/*/backup/*" \( -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" \) -mtime +"$days" -print 2>/dev/null
        } | sort -u
    )

    if [ ${#OLD_FILES[@]} -eq 0 ]; then
        echo -e "${GREEN}No backup files older than ${days} days were found.${NC}"
        return
    fi

    echo -e "${YELLOW}Backups older than ${days} days:${NC}"
    local file=""
    for file in "${OLD_FILES[@]}"; do
        echo " - $file"
    done

    if ! confirm_action "Delete ${#OLD_FILES[@]} file(s)"; then
        echo "Cancelled."
        return
    fi

    local deleted=0
    for file in "${OLD_FILES[@]}"; do
        if rm -f "$file"; then
            ((deleted++))
        fi
    done

    echo -e "${GREEN}Deleted ${deleted} backup file(s).${NC}"
}

show_backup_cron_jobs() {
    if ! ensure_crontab_available; then
        return
    fi

    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$tmp_cron" || true

    if ! grep -Fq "$SCRIPT_TAG" "$tmp_cron"; then
        echo -e "${YELLOW}No ${SCRIPT_TAG} cron jobs found for root.${NC}"
        rm -f "$tmp_cron"
        return
    fi

    echo -e "${BLUE}Scheduled Backup Jobs:${NC}"
    grep -F "$SCRIPT_TAG" "$tmp_cron"
    rm -f "$tmp_cron"
}

schedule_backup_job() {
    if ! ensure_crontab_available; then
        return
    fi

    if ! select_domain; then
        return
    fi

    local hour
    local minute
    hour=$(prompt_for_default_number "Hour (0-23)" 2 0 23)
    minute=$(prompt_for_default_number "Minute (0-59)" 30 0 59)

    local cron_tag="${SCRIPT_TAG}:${SELECTED_DOMAIN}"
    local cron_cmd="/usr/local/bin/cyberpanel createBackup --domainName ${SELECTED_DOMAIN} >> /var/log/cps-backup-${SELECTED_DOMAIN}.log 2>&1 # ${cron_tag}"
    if ! command -v /usr/local/bin/cyberpanel >/dev/null 2>&1; then
        cron_cmd="cyberpanel createBackup --domainName ${SELECTED_DOMAIN} >> /var/log/cps-backup-${SELECTED_DOMAIN}.log 2>&1 # ${cron_tag}"
    fi
    local cron_line="${minute} ${hour} * * * ${cron_cmd}"

    local tmp_current
    local tmp_new
    tmp_current=$(mktemp)
    tmp_new=$(mktemp)

    crontab -l 2>/dev/null > "$tmp_current" || true
    grep -Fv "$cron_tag" "$tmp_current" > "$tmp_new"
    echo "$cron_line" >> "$tmp_new"
    if ! crontab "$tmp_new"; then
        echo -e "${RED}Failed to install crontab entry for ${SELECTED_DOMAIN}.${NC}"
        rm -f "$tmp_current" "$tmp_new"
        return
    fi

    rm -f "$tmp_current" "$tmp_new"
    echo -e "${GREEN}Scheduled daily backup for ${SELECTED_DOMAIN} at ${hour}:${minute}.${NC}"
}

remove_scheduled_job() {
    if ! ensure_crontab_available; then
        return
    fi

    if ! select_domain; then
        return
    fi

    local tmp_current
    local tmp_new
    tmp_current=$(mktemp)
    tmp_new=$(mktemp)
    crontab -l 2>/dev/null > "$tmp_current" || true

    local cron_tag="${SCRIPT_TAG}:${SELECTED_DOMAIN}"

    if ! grep -Fq "$cron_tag" "$tmp_current"; then
        echo -e "${YELLOW}No scheduled job found for ${SELECTED_DOMAIN}.${NC}"
        rm -f "$tmp_current" "$tmp_new"
        return
    fi

    grep -Fv "$cron_tag" "$tmp_current" > "$tmp_new"
    if ! crontab "$tmp_new"; then
        echo -e "${RED}Failed to update crontab while removing ${SELECTED_DOMAIN}.${NC}"
        rm -f "$tmp_current" "$tmp_new"
        return
    fi
    rm -f "$tmp_current" "$tmp_new"
    echo -e "${GREEN}Removed scheduled backup job for ${SELECTED_DOMAIN}.${NC}"
}

main() {
    require_root
    check_prereqs

    while true; do
        print_banner
        echo -e "${BLUE}Choose an action:${NC}"
        echo " [1] Create website backup (native CyberPanel CLI)"
        echo " [2] Restore backup file (native CyberPanel CLI)"
        echo " [3] Copy backup into /home/backup (GUI restore pool)"
        echo " [4] List backup inventory"
        echo " [5] Verify backup archive integrity"
        echo " [6] Prune old backups"
        echo " [7] Schedule daily domain backup (cron)"
        echo " [8] Show scheduled backup jobs"
        echo " [9] Remove scheduled domain backup"
        echo " [10] Exit"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 10)
        echo ""

        case "$choice" in
            1) create_backup_for_domain ;;
            2) restore_backup_file ;;
            3) copy_backup_to_root_pool ;;
            4) list_backup_inventory ;;
            5) verify_backup_file ;;
            6) prune_old_backups ;;
            7) schedule_backup_job ;;
            8) show_backup_cron_jobs ;;
            9) remove_scheduled_job ;;
            10)
                echo -e "${GREEN}Goodbye.${NC}"
                exit 0
                ;;
        esac

        echo ""
        read -r -p "Press Enter to continue..." _
    done
}

main
