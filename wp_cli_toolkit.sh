#!/bin/bash

# CyberPanel WP-CLI Toolkit
# Interactive utility for common WordPress maintenance tasks.
# Developed by KloudBoy | https://kloudboy.com
# Version 1.0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SELECTED_CONFIG=""
SITE_ROOT=""
SITE_USER=""
SITE_DOMAIN=""

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "##      ## ########           ######  ##       #### ########  #######   #######  ##       ##    ## #### ########"
    echo "##  ##  ## ##     ##         ##    ## ##        ##     ##    ##     ## ##     ## ##       ##   ##   ##     ##"
    echo "##  ##  ## ##     ##         ##       ##        ##     ##    ##     ## ##     ## ##       ##  ##    ##     ##"
    echo "##  ##  ## ########  ####### ##       ##        ##     ##    ##     ## ##     ## ##       #####     ##     ##"
    echo "##  ##  ## ##                ##       ##        ##     ##    ##     ## ##     ## ##       ##  ##    ##     ##"
    echo "##  ##  ## ##                ##    ## ##        ##     ##    ##     ## ##     ## ##       ##   ##   ##     ##"
    echo " ###  ###  ##                 ######  ######## ####    ##     #######   #######  ######## ##    ## ####    ##"
    echo -e "${NC}"
    echo -e "${BLUE}   WP-CLI Toolkit for CyberPanel${NC}"
    echo -e "${YELLOW}   Website-first selection with useful daily maintenance commands${NC}"
    echo -e "${YELLOW}   Developed by KloudBoy | https://kloudboy.com${NC}"
    echo ""
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root so it can manage all websites safely.${NC}"
        exit 1
    fi
}

check_prereqs() {
    if ! command -v wp >/dev/null 2>&1; then
        echo -e "${RED}WP-CLI is not installed or not in PATH.${NC}"
        echo -e "${YELLOW}Install WP-CLI first, then rerun this script.${NC}"
        exit 1
    fi
}

pause_screen() {
    echo ""
    read -r -p "Press Enter to continue..." _
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

prompt_required() {
    local prompt="$1"
    local input=""

    while true; do
        read -r -p "$prompt" input
        if [[ -n "${input// }" ]]; then
            echo "$input"
            return 0
        fi
        echo -e "${YELLOW}Input cannot be empty.${NC}"
    done
}

discover_sites() {
    mapfile -t WP_CONFIGS < <(find /home -maxdepth 6 -name "wp-config.php" 2>/dev/null | sort)
}

select_site() {
    discover_sites

    if [ ${#WP_CONFIGS[@]} -eq 0 ]; then
        echo -e "${RED}No WordPress installations found under /home.${NC}"
        return 1
    fi

    echo -e "${BLUE}Select Website:${NC}"
    local i=1
    local config=""
    for config in "${WP_CONFIGS[@]}"; do
        echo " [$i] $(dirname "$config")"
        ((i++))
    done
    echo " [$i] Exit"
    echo ""

    local site_num
    site_num=$(prompt_for_number "Select a website (1-${i}): " 1 "$i")
    if [ "$site_num" -eq "$i" ]; then
        return 1
    fi

    SELECTED_CONFIG="${WP_CONFIGS[$((site_num-1))]}"
    SITE_ROOT="$(dirname "$SELECTED_CONFIG")"
    SITE_USER="$(stat -c '%U' "$SELECTED_CONFIG")"
    SITE_DOMAIN="$(awk -F/ '{print $3}' <<< "$SITE_ROOT")"
    if [[ -z "$SITE_DOMAIN" ]]; then
        SITE_DOMAIN="$(basename "$SITE_ROOT")"
    fi

    if ! run_wp core is-installed >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: WP-CLI could not verify WordPress install for ${SITE_ROOT}.${NC}"
        if ! confirm_action "Use this path anyway"; then
            return 1
        fi
    fi

    return 0
}

run_wp() {
    local args=("$@")

    if [[ "$SITE_USER" == "root" ]]; then
        wp --allow-root --path="$SITE_ROOT" "${args[@]}"
        return $?
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo -u "$SITE_USER" wp --path="$SITE_ROOT" "${args[@]}"
        return $?
    fi

    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$SITE_USER" -- wp --path="$SITE_ROOT" "${args[@]}"
        return $?
    fi

    local cmd
    printf -v cmd "%q " wp "--path=$SITE_ROOT" "${args[@]}"
    su -s /bin/bash "$SITE_USER" -c "$cmd"
}

run_wp_status() {
    local description="$1"
    shift
    echo -e "${BLUE}${description}${NC}"
    if run_wp "$@"; then
        echo -e "${GREEN}Done.${NC}"
    else
        echo -e "${RED}Command failed.${NC}"
    fi
}

create_pre_update_backup() {
    local backup_dir="/home/${SITE_DOMAIN}/backup"
    mkdir -p "$backup_dir"
    chown "$SITE_USER":"$SITE_USER" "$backup_dir" 2>/dev/null || true

    local backup_file="${backup_dir}/wpdb-${SITE_DOMAIN}-$(date +%F_%H-%M-%S).sql"
    echo -e "${BLUE}Creating DB backup:${NC} ${backup_file}"
    if run_wp db export "$backup_file"; then
        echo -e "${GREEN}Backup created.${NC}"
        return 0
    fi

    echo -e "${YELLOW}Backup failed. Proceed with operation anyway?${NC}"
    confirm_action "Continue without backup"
}

show_site_context() {
    echo -e "${BLUE}Current Website:${NC}"
    echo " Path:   $SITE_ROOT"
    echo " User:   $SITE_USER"
    echo " Domain: $SITE_DOMAIN"
    echo ""
}

site_summary() {
    show_site_context
    run_wp core version
    run_wp option get siteurl 2>/dev/null || true
    run_wp option get home 2>/dev/null || true
    echo ""
    run_wp plugin list --fields=name,status,update,version --format=table
}

core_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}Core Management${NC}"
        echo " [1] Show WordPress version"
        echo " [2] Check core updates"
        echo " [3] Update WordPress core"
        echo " [4] Run core DB upgrades"
        echo " [5] Verify core checksums"
        echo " [6] Enable maintenance mode"
        echo " [7] Disable maintenance mode"
        echo " [8] Show site URL settings"
        echo " [9] Update site URL + home URL"
        echo " [10] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 10)
        echo ""

        case "$choice" in
            1) run_wp_status "WordPress Version" core version ;;
            2) run_wp_status "Core Updates" core check-update ;;
            3)
                if confirm_action "Create DB backup before core update"; then
                    create_pre_update_backup || { pause_screen; continue; }
                fi
                run_wp_status "Updating WordPress Core" core update
                ;;
            4) run_wp_status "Running Core DB Upgrade" core update-db ;;
            5) run_wp_status "Verifying Checksums" core verify-checksums ;;
            6) run_wp_status "Enabling Maintenance Mode" maintenance-mode activate ;;
            7) run_wp_status "Disabling Maintenance Mode" maintenance-mode deactivate ;;
            8)
                run_wp option get siteurl
                run_wp option get home
                ;;
            9)
                local new_url
                new_url=$(prompt_required "New URL (example https://example.com): ")
                if confirm_action "Update both siteurl and home to ${new_url}"; then
                    run_wp_status "Updating siteurl" option update siteurl "$new_url"
                    run_wp_status "Updating home" option update home "$new_url"
                fi
                ;;
            10) return ;;
        esac

        pause_screen
    done
}

plugin_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}Plugin Toolkit${NC}"
        echo " [1] List all plugins"
        echo " [2] List active plugins"
        echo " [3] Update all plugins"
        echo " [4] Update one plugin"
        echo " [5] Install + activate plugin"
        echo " [6] Activate plugin"
        echo " [7] Deactivate plugin"
        echo " [8] Delete plugin"
        echo " [9] Enable plugin auto-updates"
        echo " [10] Disable plugin auto-updates"
        echo " [11] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 11)
        echo ""

        case "$choice" in
            1) run_wp plugin list --fields=name,status,update,version --format=table ;;
            2) run_wp plugin list --status=active --fields=name,status,version --format=table ;;
            3)
                if confirm_action "Create DB backup before updating all plugins"; then
                    create_pre_update_backup || { pause_screen; continue; }
                fi
                run_wp_status "Updating All Plugins" plugin update --all
                ;;
            4)
                local plugin_slug
                plugin_slug=$(prompt_required "Plugin slug: ")
                run_wp_status "Updating Plugin ${plugin_slug}" plugin update "$plugin_slug"
                ;;
            5)
                local install_slug
                install_slug=$(prompt_required "Plugin slug to install: ")
                run_wp_status "Installing + Activating ${install_slug}" plugin install "$install_slug" --activate
                ;;
            6)
                local activate_slug
                activate_slug=$(prompt_required "Plugin slug to activate: ")
                run_wp_status "Activating ${activate_slug}" plugin activate "$activate_slug"
                ;;
            7)
                local deactivate_slug
                deactivate_slug=$(prompt_required "Plugin slug to deactivate: ")
                run_wp_status "Deactivating ${deactivate_slug}" plugin deactivate "$deactivate_slug"
                ;;
            8)
                local delete_slug
                delete_slug=$(prompt_required "Plugin slug to delete: ")
                if confirm_action "Delete plugin ${delete_slug}"; then
                    run_wp_status "Deleting ${delete_slug}" plugin delete "$delete_slug"
                fi
                ;;
            9)
                local auto_on_slug
                auto_on_slug=$(prompt_required "Plugin slug: ")
                run_wp_status "Enabling Auto-Updates for ${auto_on_slug}" plugin auto-updates enable "$auto_on_slug"
                ;;
            10)
                local auto_off_slug
                auto_off_slug=$(prompt_required "Plugin slug: ")
                run_wp_status "Disabling Auto-Updates for ${auto_off_slug}" plugin auto-updates disable "$auto_off_slug"
                ;;
            11) return ;;
        esac

        pause_screen
    done
}

theme_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}Theme Toolkit${NC}"
        echo " [1] List themes"
        echo " [2] Update all themes"
        echo " [3] Update one theme"
        echo " [4] Install theme"
        echo " [5] Activate theme"
        echo " [6] Delete theme"
        echo " [7] Enable theme auto-updates"
        echo " [8] Disable theme auto-updates"
        echo " [9] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 9)
        echo ""

        case "$choice" in
            1) run_wp theme list --fields=name,status,update,version --format=table ;;
            2)
                if confirm_action "Create DB backup before updating all themes"; then
                    create_pre_update_backup || { pause_screen; continue; }
                fi
                run_wp_status "Updating All Themes" theme update --all
                ;;
            3)
                local theme_slug
                theme_slug=$(prompt_required "Theme slug: ")
                run_wp_status "Updating Theme ${theme_slug}" theme update "$theme_slug"
                ;;
            4)
                local install_theme
                install_theme=$(prompt_required "Theme slug to install: ")
                run_wp_status "Installing Theme ${install_theme}" theme install "$install_theme"
                ;;
            5)
                local activate_theme
                activate_theme=$(prompt_required "Theme slug to activate: ")
                run_wp_status "Activating Theme ${activate_theme}" theme activate "$activate_theme"
                ;;
            6)
                local delete_theme
                delete_theme=$(prompt_required "Theme slug to delete: ")
                if confirm_action "Delete theme ${delete_theme}"; then
                    run_wp_status "Deleting Theme ${delete_theme}" theme delete "$delete_theme"
                fi
                ;;
            7)
                local auto_on_theme
                auto_on_theme=$(prompt_required "Theme slug: ")
                run_wp_status "Enabling Auto-Updates for ${auto_on_theme}" theme auto-updates enable "$auto_on_theme"
                ;;
            8)
                local auto_off_theme
                auto_off_theme=$(prompt_required "Theme slug: ")
                run_wp_status "Disabling Auto-Updates for ${auto_off_theme}" theme auto-updates disable "$auto_off_theme"
                ;;
            9) return ;;
        esac

        pause_screen
    done
}

database_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}Database Toolkit${NC}"
        echo " [1] DB check"
        echo " [2] DB optimize"
        echo " [3] DB repair"
        echo " [4] Export DB backup"
        echo " [5] Import SQL backup"
        echo " [6] Reset DB (destructive)"
        echo " [7] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 7)
        echo ""

        case "$choice" in
            1) run_wp_status "Database Check" db check ;;
            2) run_wp_status "Database Optimize" db optimize ;;
            3) run_wp_status "Database Repair" db repair ;;
            4) create_pre_update_backup ;;
            5)
                local import_file
                import_file=$(prompt_required "Absolute path to .sql file: ")
                if [[ ! -f "$import_file" ]]; then
                    echo -e "${RED}File not found: ${import_file}${NC}"
                elif confirm_action "Import ${import_file} into this website database"; then
                    run_wp_status "Importing SQL Backup" db import "$import_file"
                fi
                ;;
            6)
                echo -e "${RED}Warning: This wipes all database tables for this WordPress site.${NC}"
                if confirm_action "Reset database now"; then
                    run_wp_status "Resetting Database" db reset --yes
                fi
                ;;
            7) return ;;
        esac

        pause_screen
    done
}

cache_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}Cache and Performance Toolkit${NC}"
        echo " [1] Flush object cache"
        echo " [2] Delete all transients"
        echo " [3] Flush rewrite rules"
        echo " [4] Run due cron events now"
        echo " [5] Regenerate media thumbnails"
        echo " [6] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 6)
        echo ""

        case "$choice" in
            1) run_wp_status "Flushing Cache" cache flush ;;
            2) run_wp_status "Deleting All Transients" transient delete --all ;;
            3) run_wp_status "Flushing Rewrite Rules" rewrite flush --hard ;;
            4) run_wp_status "Running Due Cron Events" cron event run --due-now ;;
            5) run_wp_status "Regenerating Thumbnails" media regenerate --yes ;;
            6) return ;;
        esac

        pause_screen
    done
}

user_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}User Toolkit${NC}"
        echo " [1] List users"
        echo " [2] Create user"
        echo " [3] Reset user password"
        echo " [4] Change user role"
        echo " [5] Delete user"
        echo " [6] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 6)
        echo ""

        case "$choice" in
            1) run_wp user list --fields=ID,user_login,user_email,roles --format=table ;;
            2)
                local new_user new_email new_role new_pass generated_pass="false"
                new_user=$(prompt_required "Username: ")
                new_email=$(prompt_required "Email: ")
                read -r -p "Role [subscriber]: " new_role
                new_role=${new_role:-subscriber}
                read -r -p "Password (leave blank to auto-generate): " new_pass
                if [[ -z "$new_pass" ]]; then
                    if command -v openssl >/dev/null 2>&1; then
                        new_pass=$(openssl rand -base64 18 | tr -d '/+= ' | cut -c1-16)
                    else
                        new_pass="TempPass$(date +%s)"
                    fi
                    generated_pass="true"
                fi
                if run_wp user create "$new_user" "$new_email" --role="$new_role" --user_pass="$new_pass"; then
                    echo -e "${GREEN}User created.${NC}"
                    if [[ "$generated_pass" == "true" ]]; then
                        echo -e "${YELLOW}Generated password:${NC} ${new_pass}"
                    fi
                else
                    echo -e "${RED}User creation failed.${NC}"
                fi
                ;;
            3)
                local reset_user reset_pass
                reset_user=$(prompt_required "Username or user ID: ")
                reset_pass=$(prompt_required "New password: ")
                run_wp_status "Updating Password" user update "$reset_user" --user_pass="$reset_pass"
                ;;
            4)
                local role_user role_name
                role_user=$(prompt_required "Username or user ID: ")
                role_name=$(prompt_required "New role (administrator/editor/author/subscriber/shop_manager): ")
                run_wp_status "Updating User Role" user set-role "$role_user" "$role_name"
                ;;
            5)
                local delete_user reassign_user
                delete_user=$(prompt_required "Username or user ID to delete: ")
                read -r -p "Reassign posts to user ID (optional): " reassign_user
                if confirm_action "Delete user ${delete_user}"; then
                    if [[ -n "$reassign_user" ]]; then
                        run_wp_status "Deleting User with Reassign" user delete "$delete_user" --reassign="$reassign_user"
                    else
                        run_wp_status "Deleting User" user delete "$delete_user"
                    fi
                fi
                ;;
            6) return ;;
        esac

        pause_screen
    done
}

search_replace_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}Search and Replace Toolkit${NC}"
        echo " [1] Dry run search-replace"
        echo " [2] Execute search-replace"
        echo " [3] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 3)
        echo ""

        case "$choice" in
            1|2)
                local find_text replace_text
                find_text=$(prompt_required "Find text: ")
                replace_text=$(prompt_required "Replace with: ")
                if [[ "$choice" -eq 1 ]]; then
                    run_wp_status "Running Dry-Run Search Replace" search-replace "$find_text" "$replace_text" --all-tables-with-prefix --skip-columns=guid --precise --report-changed-only --dry-run
                else
                    echo -e "${RED}This writes changes directly to the database.${NC}"
                    if confirm_action "Create DB backup before running search-replace"; then
                        create_pre_update_backup || { pause_screen; continue; }
                    fi
                    if confirm_action "Execute search-replace now"; then
                        run_wp_status "Executing Search Replace" search-replace "$find_text" "$replace_text" --all-tables-with-prefix --skip-columns=guid --precise --report-changed-only
                    fi
                fi
                ;;
            3) return ;;
        esac

        pause_screen
    done
}

cron_menu() {
    while true; do
        clear
        show_site_context
        echo -e "${BLUE}WP-Cron Toolkit${NC}"
        echo " [1] List cron events"
        echo " [2] Run due cron events now"
        echo " [3] Run specific cron hook"
        echo " [4] Delete specific cron hook"
        echo " [5] Back"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 5)
        echo ""

        case "$choice" in
            1) run_wp cron event list --fields=hook,next_run,recurrence --format=table ;;
            2) run_wp_status "Running Due Cron Events" cron event run --due-now ;;
            3)
                local run_hook
                run_hook=$(prompt_required "Hook name to run: ")
                run_wp_status "Running Hook ${run_hook}" cron event run "$run_hook"
                ;;
            4)
                local delete_hook
                delete_hook=$(prompt_required "Hook name to delete: ")
                if confirm_action "Delete hook ${delete_hook}"; then
                    run_wp_status "Deleting Hook ${delete_hook}" cron event delete "$delete_hook"
                fi
                ;;
            5) return ;;
        esac

        pause_screen
    done
}

main_menu() {
    while true; do
        print_banner
        show_site_context
        echo -e "${BLUE}Main Menu${NC}"
        echo " [1] Site summary"
        echo " [2] Core management"
        echo " [3] Plugin toolkit"
        echo " [4] Theme toolkit"
        echo " [5] Database toolkit"
        echo " [6] Cache and performance toolkit"
        echo " [7] User toolkit"
        echo " [8] Search and replace toolkit"
        echo " [9] WP-Cron toolkit"
        echo " [10] Switch website"
        echo " [11] Exit"
        echo ""

        local choice
        choice=$(prompt_for_number "Select option: " 1 11)
        echo ""

        case "$choice" in
            1) site_summary; pause_screen ;;
            2) core_menu ;;
            3) plugin_menu ;;
            4) theme_menu ;;
            5) database_menu ;;
            6) cache_menu ;;
            7) user_menu ;;
            8) search_replace_menu ;;
            9) cron_menu ;;
            10)
                if ! select_site; then
                    echo -e "${YELLOW}Website selection cancelled.${NC}"
                    pause_screen
                fi
                ;;
            11)
                echo -e "${GREEN}Goodbye.${NC}"
                exit 0
                ;;
        esac
    done
}

main() {
    require_root
    check_prereqs
    print_banner

    echo -e "${BLUE}Step 1: Select which website you want to manage.${NC}"
    echo ""
    if ! select_site; then
        echo -e "${YELLOW}No website selected. Exiting.${NC}"
        exit 0
    fi

    main_menu
}

main
