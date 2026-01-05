#!/bin/bash

# CyberPanel WP & Woo Optimizer Script
# Developed by KloudBoy
# Version 1.0

# ----------------------------------------------------------------------
# COLORS
# ----------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------
# BANNER
# ----------------------------------------------------------------------
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "##      ## ########  #######  ########  ########  ######## ########"
    echo "##  ##  ## ##     ## ##     ## ##     ## ##     ## ##       ##     "
    echo "##  ##  ## ##     ## ##     ## ##     ## ##     ## ##       ##     "
    echo "##  ##  ## ########  ########  ########  ########  ######   ###### "
    echo "##  ##  ## ##        ##   ##   ##        ##   ##   ##       ##     "
    echo "##  ##  ## ##        ##    ##  ##        ##    ##  ##       ##     "
    echo " ###  ###  ##        ##     ## ##        ##     ## ######## ########"
    echo -e "${NC}"
    echo -e "${BLUE}   WordPress & WooCommerce Optimizer for CyberPanel${NC}"
    echo -e "${YELLOW}   Automated Tuning & Cron Management${NC}"
    echo -e "   --------------------------------------------------"
    echo ""
}
print_banner

# ----------------------------------------------------------------------
# CHECK ROOT
# ----------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root.${NC}"
   exit 1
fi

# ----------------------------------------------------------------------
# FUNCTIONS
# ----------------------------------------------------------------------

# Function to detect PHP version from .htaccess or default to 8.1
get_php_binary() {
    local site_path="$1"
    local htaccess="$site_path/.htaccess"
    local php_ver=""

    if [[ -f "$htaccess" ]]; then
        # Look for AddHandler application/x-httpd-lsphpXX
        # Extract the number (e.g., 74, 80, 81)
        php_ver=$(grep -oE "application/x-httpd-lsphp[0-9]+" "$htaccess" | head -n 1 | grep -oE "[0-9]+")
    fi

    # Fallback/Default detection
    if [[ -z "$php_ver" ]]; then
        # Try to guess or default to a common version like 8.1 (lsphp81)
        php_ver="81"
        if [[ -f "/usr/local/lsws/lsphp74/bin/php" ]]; then php_ver="74"; fi
        if [[ -f "/usr/local/lsws/lsphp80/bin/php" ]]; then php_ver="80"; fi
        if [[ -f "/usr/local/lsws/lsphp81/bin/php" ]]; then php_ver="81"; fi
        if [[ -f "/usr/local/lsws/lsphp82/bin/php" ]]; then php_ver="82"; fi
    fi

    echo "/usr/local/lsws/lsphp${php_ver}/bin/php"
}

# ----------------------------------------------------------------------
# SCAN FOR WORDPRESS SITES
# ----------------------------------------------------------------------
echo -e "${BLUE}Scanning for WordPress installations in /home/...${NC}"

# Find wp-config.php files max depth 4 to avoid deep scan, assuming standard structure
# /home/domain.com/public_html/wp-config.php
mapfile -t WP_CONFIGS < <(find /home -maxdepth 4 -name "wp-config.php" 2>/dev/null)

if [ ${#WP_CONFIGS[@]} -eq 0 ]; then
    echo -e "${RED}No WordPress installations found in /home.${NC}"
    exit 1
fi

echo -e "${GREEN}Found ${#WP_CONFIGS[@]} WordPress sites:${NC}"
echo ""

# Display Menu
i=1
for config in "${WP_CONFIGS[@]}"; do
    # Extract domain from path typically: /home/DOMAIN/public_html/...
    # Cut helps show relevant part
    dir_path=$(dirname "$config")
    echo -e " [$i] ${YELLOW}$dir_path${NC}"
    ((i++))
done

echo ""
read -p "Select a site to optimize (1-${#WP_CONFIGS[@]}): " SITE_NUM

# Validate Input
if ! [[ "$SITE_NUM" =~ ^[0-9]+$ ]] || [ "$SITE_NUM" -lt 1 ] || [ "$SITE_NUM" -gt "${#WP_CONFIGS[@]}" ]; then
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi

# Get Selected Config
SELECTED_CONFIG="${WP_CONFIGS[$((SITE_NUM-1))]}"
SITE_ROOT=$(dirname "$SELECTED_CONFIG")
SITE_USER=$(stat -c '%U' "$SELECTED_CONFIG")

echo -e ""
echo -e "${BLUE}Selected: ${SITE_ROOT}${NC}"
echo -e "${BLUE}Owner:    ${SITE_USER}${NC}"

# ----------------------------------------------------------------------
# OPTIMIZE WP-CONFIG.PHP
# ----------------------------------------------------------------------
echo -e ""
echo -e "${BLUE}Preparing to optimize wp-config.php...${NC}"

# Backup
cp "$SELECTED_CONFIG" "${SELECTED_CONFIG}.backup.$(date +%F_%T)"
echo -e "${GREEN}Backup created: ${SELECTED_CONFIG}.backup.$(date +%F_%T)${NC}"

# Helper to add or update define
# Arguments: $1 = KEY, $2 = VALUE, $3 = FILE
update_config_define() {
    local key="$1"
    local val="$2"
    local file="$3"
    
    # Check if exists
    if grep -q "$key" "$file"; then
        # Replace existing
        # Using sed with different delimiter to handle complex chars if needed
        # We assume simple 'define('KEY', ...)' structure
        echo -e " - Updating $key to $val"
        sed -i "s|define(.*['\"]$key['\"].*);|define( '$key', $val );|g" "$file"
    else
        # Append before "That's all" or at end
        echo -e " - Adding $key = $val"
        if grep -q "That's all, stop editing" "$file"; then
             sed -i "/That's all, stop editing/i define( '$key', $val );" "$file"
        else
             # Append to end if standard line not found (unlikely but safe)
             echo "define( '$key', $val );" >> "$file"
        fi
    fi
}

# 1. Memory Limits (High for Woo)
update_config_define "WP_MEMORY_LIMIT" "'512M'" "$SELECTED_CONFIG"
update_config_define "WP_MAX_MEMORY_LIMIT" "'1024M'" "$SELECTED_CONFIG"
update_config_define "WC_MEMORY_LIMIT" "'1024M'" "$SELECTED_CONFIG"

# 2. Disable WP Cron (We will substitute with Server Cron)
update_config_define "DISABLE_WP_CRON" "true" "$SELECTED_CONFIG"

# 3. Misc Woo Performance
# update_config_define "WP_AUTO_UPDATE_CORE" "false" "$SELECTED_CONFIG" # Optional, maybe controversial

echo -e "${GREEN}wp-config.php updated.${NC}"

# ----------------------------------------------------------------------
# SETUP SERVER-SIDE CRON
# ----------------------------------------------------------------------
echo -e ""
echo -e "${BLUE}Setting up Server-Side Cron...${NC}"

PHP_BIN=$(get_php_binary "$SITE_ROOT")
echo -e "Detected PHP Binary: ${YELLOW}$PHP_BIN${NC}"

CRON_CMD="$PHP_BIN $SITE_ROOT/wp-cron.php >/dev/null 2>&1"
CRON_JOB="*/5 * * * * $CRON_CMD"

# Check if cron already exists for this user
# We need to act as the user to modify their crontab, or edit /var/spool/cron/crontabs/$SITE_USER
if crontab -u "$SITE_USER" -l 2>/dev/null | grep -Fq "wp-cron.php"; then
    echo -e "${YELLOW}Cron job for wp-cron.php already exists for user $SITE_USER.${NC}"
    # Optional: Update it? For now, we assume if it's there, it's fine, or we can prompt.
    echo -e "Existing cron: $(crontab -u "$SITE_USER" -l | grep wp-cron.php)"
else
    # Append new cron
    # Handle empty crontab case
    (crontab -u "$SITE_USER" -l 2>/dev/null; echo "$CRON_JOB") | crontab -u "$SITE_USER" -
    echo -e "${GREEN}Added Cron Job:${NC}"
    echo -e " ${CRON_JOB}"
fi

# ----------------------------------------------------------------------
# WOOCOMMERCE DATABASE OPTIMIZATION (WP-CLI)
# ----------------------------------------------------------------------
# Check if WP-CLI is available
if command -v wp &> /dev/null; then
    echo -e ""
    echo -e "${BLUE}Running WooCommerce Database Optimizations via WP-CLI...${NC}"
    
    # Run as user
    # 1. Clear Transients
    echo " - Clearing transients..."
    sudo -u "$SITE_USER" wp transient delete --all --path="$SITE_ROOT" --skip-plugins --skip-themes &>/dev/null
    
    # 2. Regenerate Thumbnails (optional, heavy, maybe skip)
    # 3. Optimize Database Tables
    # echo " - optimizing database tables..."
    # sudo -u "$SITE_USER" wp db optimize --path="$SITE_ROOT" &>/dev/null
    
    echo -e "${GREEN}Done.${NC}"
else
    echo -e "${YELLOW}WP-CLI not found. Skipping DB specific tasks.${NC}"
fi

echo -e ""
echo -e "${GREEN}--------------------------------------------------${NC}"
echo -e "${GREEN}Optimization Complete for $(basename "$SITE_ROOT")!${NC}"
echo -e "${GREEN}--------------------------------------------------${NC}"
