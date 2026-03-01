#!/bin/bash

# CyberPanel Service & Maintenance Manager
# Developed for operational management of CyberPanel stacks.
# Version 1.0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

UNIT_CACHE=""

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
    echo -e "${BLUE}   CyberPanel Manager${NC}"
    echo -e "${YELLOW}   Service control, health snapshot, and official maintenance actions${NC}"
    echo ""
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root.${NC}"
        exit 1
    fi
}

check_prereqs() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${RED}systemctl command not found. This manager currently supports systemd-based servers only.${NC}"
        exit 1
    fi
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

refresh_unit_cache() {
    UNIT_CACHE=$(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null | awk '{print $1}')
}

service_exists() {
    local svc="$1"
    grep -qx "${svc}.service" <<< "$UNIT_CACHE"
}

service_status_text() {
    local svc="$1"

    if ! service_exists "$svc"; then
        echo "Not installed"
        return
    fi

    if systemctl is-active --quiet "$svc"; then
        echo "Running"
    elif systemctl is-failed --quiet "$svc"; then
        echo "Failed"
    else
        echo "Stopped"
    fi
}

print_service_row() {
    local svc="$1"
    local label="$2"
    local status
    status=$(service_status_text "$svc")

    case "$status" in
        Running)
            printf " - %-20s : ${GREEN}%s${NC}\n" "$label" "$status"
            ;;
        Failed)
            printf " - %-20s : ${RED}%s${NC}\n" "$label" "$status"
            ;;
        Stopped)
            printf " - %-20s : ${YELLOW}%s${NC}\n" "$label" "$status"
            ;;
        *)
            printf " - %-20s : ${YELLOW}%s${NC}\n" "$label" "$status"
            ;;
    esac
}

detect_db_service() {
    if service_exists "mariadb"; then
        echo "mariadb"
        return
    fi

    if service_exists "mysql"; then
        echo "mysql"
        return
    fi

    echo ""
}

run_remote_script() {
    local url="$1"
    local tmp_file
    tmp_file=$(mktemp)

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$url" -o "$tmp_file"; then
            echo -e "${RED}Failed to download script from ${url}${NC}"
            rm -f "$tmp_file"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$tmp_file" "$url"; then
            echo -e "${RED}Failed to download script from ${url}${NC}"
            rm -f "$tmp_file"
            return 1
        fi
    else
        echo -e "${RED}Neither curl nor wget is installed. Cannot fetch official script.${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    bash "$tmp_file"
    local rc=$?
    rm -f "$tmp_file"
    return "$rc"
}

get_cyberpanel_version() {
    if [[ -f "/usr/local/CyberCP/version.txt" ]]; then
        head -n 1 /usr/local/CyberCP/version.txt
        return
    fi

    if [[ -f "/usr/local/CyberCP/version" ]]; then
        head -n 1 /usr/local/CyberCP/version
        return
    fi

    echo "Unknown"
}

run_health_snapshot() {
    local db_service="$1"

    echo -e "${BLUE}=== CyberPanel Health Snapshot ===${NC}"
    echo "Hostname:            $(hostname)"
    echo "Date:                $(date)"
    echo "Uptime:              $(uptime -p 2>/dev/null || uptime)"
    echo "CyberPanel Version:  $(get_cyberpanel_version)"
    echo ""

    echo -e "${BLUE}Service Status:${NC}"
    print_service_row "lscpd" "CyberPanel API"
    print_service_row "lsws" "LiteSpeed Web Server"
    if [[ -n "$db_service" ]]; then
        if [[ "$db_service" == "mariadb" ]]; then
            print_service_row "mariadb" "MariaDB"
        else
            print_service_row "mysql" "MySQL"
        fi
    else
        echo -e " - Database             : ${YELLOW}No mysql/mariadb unit detected${NC}"
    fi
    print_service_row "redis" "Redis"
    print_service_row "memcached" "Memcached"
    print_service_row "postfix" "Postfix"
    print_service_row "dovecot" "Dovecot"
    echo ""

    echo -e "${BLUE}Memory:${NC}"
    free -h 2>/dev/null || cat /proc/meminfo | head -n 5
    echo ""

    echo -e "${BLUE}Disk:${NC}"
    df -h / /home 2>/dev/null | awk 'NR==1 || !seen[$6]++'
    echo ""
}

restart_core_stack() {
    local db_service="$1"
    local services=()
    local svc=""

    for svc in "lscpd" "lsws"; do
        if service_exists "$svc"; then
            services+=("$svc")
        fi
    done

    if [[ -n "$db_service" ]]; then
        services+=("$db_service")
    fi

    if [ ${#services[@]} -eq 0 ]; then
        echo -e "${YELLOW}No core services were detected on this server.${NC}"
        return
    fi

    echo -e "${BLUE}Core services to restart:${NC} ${services[*]}"
    if ! confirm_action "Proceed with restart"; then
        echo "Cancelled."
        return
    fi

    for svc in "${services[@]}"; do
        echo -ne "Restarting ${svc}... "
        if systemctl restart "$svc"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    done
    echo ""
}

manage_single_service() {
    local service_candidates=("lscpd" "lsws" "mariadb" "mysql" "redis" "memcached" "pdns" "postfix" "dovecot" "pure-ftpd" "crond" "cron")
    local available=()
    local svc=""
    local idx=1

    for svc in "${service_candidates[@]}"; do
        if service_exists "$svc"; then
            available+=("$svc")
        fi
    done

    if [ ${#available[@]} -eq 0 ]; then
        echo -e "${YELLOW}No known CyberPanel-related services found.${NC}"
        return
    fi

    echo -e "${BLUE}Available Services:${NC}"
    for svc in "${available[@]}"; do
        echo " [$idx] $svc ($(service_status_text "$svc"))"
        ((idx++))
    done
    echo " [$idx] Back"

    local selection
    selection=$(prompt_for_number "Select service: " 1 "$idx")
    if [ "$selection" -eq "$idx" ]; then
        return
    fi

    local chosen="${available[$((selection-1))]}"
    echo ""
    echo "Selected: $chosen"
    echo " [1] Status"
    echo " [2] Start"
    echo " [3] Stop"
    echo " [4] Restart"
    echo " [5] Show last 80 logs"
    echo " [6] Back"

    local action
    action=$(prompt_for_number "Select action: " 1 6)
    case "$action" in
        1)
            systemctl status "$chosen" --no-pager
            ;;
        2)
            systemctl start "$chosen" && echo -e "${GREEN}Started ${chosen}.${NC}" || echo -e "${RED}Failed to start ${chosen}.${NC}"
            ;;
        3)
            if confirm_action "Stop ${chosen}"; then
                systemctl stop "$chosen" && echo -e "${GREEN}Stopped ${chosen}.${NC}" || echo -e "${RED}Failed to stop ${chosen}.${NC}"
            fi
            ;;
        4)
            systemctl restart "$chosen" && echo -e "${GREEN}Restarted ${chosen}.${NC}" || echo -e "${RED}Failed to restart ${chosen}.${NC}"
            ;;
        5)
            if command -v journalctl >/dev/null 2>&1; then
                journalctl -u "$chosen" -n 80 --no-pager
            else
                systemctl status "$chosen" --no-pager
            fi
            ;;
        *)
            ;;
    esac
    echo ""
}

run_official_upgrade() {
    local upgrade_url="https://raw.githubusercontent.com/usmannasir/cyberpanel/stable/preUpgrade.sh"

    echo -e "${YELLOW}This runs CyberPanel's official upgrade script from:${NC}"
    echo "$upgrade_url"
    if ! confirm_action "Run official CyberPanel upgrade now"; then
        echo "Cancelled."
        return
    fi

    if ! run_remote_script "$upgrade_url"; then
        echo -e "${RED}Official upgrade script failed.${NC}"
    fi
}

run_watchdog_once() {
    local watchdog_url="https://raw.githubusercontent.com/usmannasir/cyberpanel/main/tools/scripts/watchdog.sh"

    echo -e "${YELLOW}This runs CyberPanel's official watchdog script from:${NC}"
    echo "$watchdog_url"
    if ! confirm_action "Run watchdog scan now"; then
        echo "Cancelled."
        return
    fi

    if ! run_remote_script "$watchdog_url"; then
        echo -e "${RED}Official watchdog script failed.${NC}"
    fi
}

run_bandwidth_reset() {
    local reset_script="/usr/local/CyberCP/scripts/reset_bandwidth.sh"

    if [[ ! -x "$reset_script" ]]; then
        echo -e "${YELLOW}${reset_script} is missing or not executable.${NC}"
        echo -e "${YELLOW}Tip: upgrade CyberPanel first, then rerun this action.${NC}"
        return
    fi

    if ! confirm_action "Reset monthly bandwidth counters now"; then
        echo "Cancelled."
        return
    fi

    "$reset_script"
}

show_quick_logs() {
    local db_service="$1"

    echo -e "${BLUE}Quick Logs:${NC}"
    echo " [1] CyberPanel API (lscpd)"
    echo " [2] LiteSpeed Web Server (lsws)"
    echo " [3] Database (${db_service:-not-detected})"
    echo " [4] Mail (postfix)"
    echo " [5] Back"

    local log_choice
    log_choice=$(prompt_for_number "Select log target: " 1 5)
    case "$log_choice" in
        1)
            if command -v journalctl >/dev/null 2>&1; then
                journalctl -u lscpd -n 80 --no-pager
            else
                systemctl status lscpd --no-pager
            fi
            ;;
        2)
            if command -v journalctl >/dev/null 2>&1 && service_exists "lsws"; then
                journalctl -u lsws -n 80 --no-pager
            elif [[ -f "/usr/local/lsws/logs/error.log" ]]; then
                tail -n 80 /usr/local/lsws/logs/error.log
            else
                echo -e "${YELLOW}LiteSpeed log not found.${NC}"
            fi
            ;;
        3)
            if [[ -n "$db_service" ]]; then
                if command -v journalctl >/dev/null 2>&1; then
                    journalctl -u "$db_service" -n 80 --no-pager
                else
                    systemctl status "$db_service" --no-pager
                fi
            else
                echo -e "${YELLOW}No database service detected.${NC}"
            fi
            ;;
        4)
            if service_exists "postfix"; then
                if command -v journalctl >/dev/null 2>&1; then
                    journalctl -u postfix -n 80 --no-pager
                else
                    systemctl status postfix --no-pager
                fi
            else
                echo -e "${YELLOW}postfix service not detected.${NC}"
            fi
            ;;
        *)
            ;;
    esac
    echo ""
}

main() {
    require_root
    check_prereqs
    refresh_unit_cache

    while true; do
        local db_service
        db_service=$(detect_db_service)

        print_banner
        echo -e "${BLUE}Choose an action:${NC}"
        echo " [1] Health snapshot"
        echo " [2] Restart core CyberPanel services"
        echo " [3] Manage one service"
        echo " [4] Run official CyberPanel upgrade script"
        echo " [5] Run official CyberPanel watchdog script"
        echo " [6] Reset CyberPanel bandwidth counters"
        echo " [7] Show quick logs"
        echo " [8] Exit"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 8)
        echo ""

        case "$choice" in
            1) run_health_snapshot "$db_service" ;;
            2) restart_core_stack "$db_service" ;;
            3) manage_single_service ;;
            4) run_official_upgrade ;;
            5) run_watchdog_once ;;
            6) run_bandwidth_reset ;;
            7) show_quick_logs "$db_service" ;;
            8)
                echo -e "${GREEN}Goodbye.${NC}"
                exit 0
                ;;
        esac

        refresh_unit_cache
        read -r -p "Press Enter to continue..." _
    done
}

main
