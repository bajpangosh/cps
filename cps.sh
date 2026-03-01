#!/bin/bash

# CyberPanel Optimization Suite Launcher
# All-in-one menu to run toolkit scripts from one entry point.
# Version 1.0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

RAW_BASE_URL="https://raw.githubusercontent.com/bajpangosh/cps/main"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_banner() {
    clear
    echo -e "${CYAN}"
    echo " ######  ########   ######"
    echo "##    ## ##     ## ##    ##"
    echo "##       ##     ## ##"
    echo "##       ########   ######"
    echo "##       ##              ##"
    echo "##    ## ##        ##    ##"
    echo " ######  ##         ######"
    echo -e "${NC}"
    echo -e "${BLUE}CyberPanel Optimization Suite (Main Launcher)${NC}"
    echo -e "${YELLOW}Run all toolkit scripts from one menu${NC}"
    echo ""
}

pause_screen() {
    echo ""
    read -r -p "Press Enter to continue..." _
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

download_to_file() {
    local url="$1"
    local destination="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$destination"
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$destination" "$url"
        return $?
    fi

    echo -e "${RED}Neither curl nor wget is installed.${NC}"
    return 1
}

run_script_file() {
    local file_path="$1"
    local need_root="$2"
    shift 2
    local args=("$@")

    if [[ "$need_root" == "yes" && $EUID -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo bash "$file_path" "${args[@]}"
            return $?
        fi
        echo -e "${RED}Root access required but sudo is not available.${NC}"
        return 1
    fi

    bash "$file_path" "${args[@]}"
}

run_tool() {
    local script_name="$1"
    local need_root="$2"
    shift 2
    local args=("$@")
    local local_path="${BASE_DIR}/${script_name}"

    if [[ -f "$local_path" ]]; then
        run_script_file "$local_path" "$need_root" "${args[@]}"
        return $?
    fi

    local tmp_file
    tmp_file=$(mktemp)
    local url="${RAW_BASE_URL}/${script_name}"

    echo -e "${YELLOW}Local script not found. Downloading ${script_name} from GitHub...${NC}"
    if ! download_to_file "$url" "$tmp_file"; then
        echo -e "${RED}Failed to download ${script_name}.${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    if ! run_script_file "$tmp_file" "$need_root" "${args[@]}"; then
        rm -f "$tmp_file"
        return 1
    fi

    rm -f "$tmp_file"
}

run_menu() {
    while true; do
        print_banner
        echo -e "${BLUE}Select Tool:${NC}"
        echo " [1] Server Audit"
        echo " [2] MariaDB Tuneup (interactive)"
        echo " [3] MariaDB Tuneup (unattended -y)"
        echo " [4] WordPress & Woo Optimizer"
        echo " [5] CyberPanel Manager"
        echo " [6] CyberPanel Backup Manager"
        echo " [7] WP-CLI Toolkit"
        echo " [8] Exit"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 8)
        echo ""

        case "$choice" in
            1) run_tool "cyberpanel_audit.sh" "yes" ;;
            2) run_tool "mariadb_tuneup.sh" "yes" ;;
            3) run_tool "mariadb_tuneup.sh" "yes" "-y" ;;
            4) run_tool "wp_woo_optimize.sh" "yes" ;;
            5) run_tool "cyberpanel_manager.sh" "yes" ;;
            6) run_tool "cyberpanel_backup_manager.sh" "yes" ;;
            7) run_tool "wp_cli_toolkit.sh" "yes" ;;
            8)
                echo -e "${GREEN}Goodbye.${NC}"
                exit 0
                ;;
        esac

        pause_screen
    done
}

run_menu
