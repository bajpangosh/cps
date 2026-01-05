#!/bin/bash

# CyberPanel Configuration Audit & Optimizer Checker
# Checks MariaDB, PHP, and LiteSpeed settings against best practices.
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
    echo " #######  ########  #######  ######## #### ##     ## #### ######## ######## ######## "
    echo "##     ## ##     ##    ##       ##     ##  ###   ###  ##       ##  ##       ##     ##"
    echo "##     ## ##     ##    ##       ##     ##  #### ####  ##      ##   ##       ##     ##"
    echo "##     ## ########     ##       ##     ##  ## ### ##  ##     ##    ######   ######## "
    echo "##     ## ##           ##       ##     ##  ##     ##  ##    ##     ##       ##   ##  "
    echo "##     ## ##           ##       ##     ##  ##     ##  ##   ##      ##       ##    ## "
    echo " #######  ##           ##       ##    #### ##     ## #### ######## ######## ##     ##"
    echo -e "${NC}"
    echo -e "${BLUE}   CyberPanel Performance Audit Tool${NC}"
    echo -e "${YELLOW}   Checks MariaDB, PHP (LSPHP), and LiteSpeed Settings${NC}"
    echo -e "   --------------------------------------------------"
    echo ""
}
print_banner

# ----------------------------------------------------------------------
# ROOT CHECK
# ----------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root to access configuration files.${NC}"
   exit 1
fi

# ----------------------------------------------------------------------
# SYSTEM INFO
# ----------------------------------------------------------------------
echo -e "${BLUE}=== System Resources ===${NC}"
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
TOTAL_RAM_GB=$(awk "BEGIN {print $TOTAL_RAM_MB / 1024}")
CORES=$(nproc)

echo -e "CPU Cores: ${GREEN}${CORES}${NC}"
echo -e "Total RAM: ${GREEN}${TOTAL_RAM_MB} MB (${TOTAL_RAM_GB} GB)${NC}"
echo ""

# ----------------------------------------------------------------------
# MARIADB CHECKS
# ----------------------------------------------------------------------
echo -e "${BLUE}=== MariaDB Audit ===${NC}"

MYSQL_PASS_FILE="/etc/cyberpanel/mysqlPassword"
if [[ -f "$MYSQL_PASS_FILE" ]]; then
    DB_PASS=$(cat "$MYSQL_PASS_FILE")
    # Verify Connection
    if ! mysql -u root -p"$DB_PASS" -e "SELECT 1;" &>/dev/null; then
        echo -e "${RED}Failed to connect to MariaDB with credentials in $MYSQL_PASS_FILE.${NC}"
        DB_CONNECTED=false
    else
        DB_CONNECTED=true
    fi
else
    # Try passwordless
    if mysql -u root -e "SELECT 1;" &>/dev/null; then
        DB_CONNECTED=true
        DB_PASS="" # Socket auth
    else
        echo -e "${RED}Could not find password file and socket auth failed.${NC}"
        DB_CONNECTED=false
    fi
fi

if [ "$DB_CONNECTED" = true ]; then
    # Helper to get variable
    get_db_var() {
        if [[ -n "$DB_PASS" ]]; then
            mysql -u root -p"$DB_PASS" -N -e "SHOW VARIABLES LIKE '$1';" | awk '{print $2}'
        else
            mysql -u root -N -e "SHOW VARIABLES LIKE '$1';" | awk '{print $2}'
        fi
    }

    # Fetch Variables
    BUFFER_POOL=$(get_db_var "innodb_buffer_pool_size")
    BUFFER_POOL_MB=$((BUFFER_POOL / 1024 / 1024))
    MAX_CONNS=$(get_db_var "max_connections")
    LOG_FILE_SIZE=$(get_db_var "innodb_log_file_size")
    LOG_FILE_SIZE_MB=$((LOG_FILE_SIZE / 1024 / 1024))
    QUERY_CACHE_TYPE=$(get_db_var "query_cache_type") # ON/OFF or 0/1
    SLOW_QUERY_LOG=$(get_db_var "slow_query_log")

    # Analyze
    echo -e "Status: ${GREEN}Connected${NC}"
    
    # 1. Buffer Pool Check
    echo -ne "InnoDB Buffer Pool ($BUFFER_POOL_MB MB): "
    # Ideal: 50-70% of RAM for dedicated, 30-50% for shared
    PERCENT_RAM=$((BUFFER_POOL_MB * 100 / TOTAL_RAM_MB))
    if [ $PERCENT_RAM -lt 20 ]; then
        echo -e "${YELLOW}WARNING (Low - ${PERCENT_RAM}% of RAM)${NC}"
        echo -e "  -> Recommendation: Increase to 40-50% of available RAM if you have free memory."
    elif [ $PERCENT_RAM -gt 80 ]; then
        echo -e "${RED}CRITICAL (High - ${PERCENT_RAM}% of RAM)${NC}"
        echo -e "  -> Warning: Risk of OOM killer. Lower this value."
    else
        echo -e "${GREEN}OK (${PERCENT_RAM}% of RAM)${NC}"
    fi

    # 2. Max Connections
    echo -ne "Max Connections ($MAX_CONNS): "
    if [ "$MAX_CONNS" -lt 150 ]; then
         echo -e "${YELLOW}LOW${NC} (Default is often 151, consider raising for traffic spikes)"
    else
         echo -e "${GREEN}OK${NC}"
    fi

    # 3. Log File Size
    echo -ne "InnoDB Log File Size ($LOG_FILE_SIZE_MB MB): "
    if [ "$LOG_FILE_SIZE_MB" -lt 64 ]; then
        echo -e "${YELLOW}LOW${NC} -> Consider increasing to 128M or 256M for better write performance."
    else
        echo -e "${GREEN}OK${NC}"
    fi

    # 4. Slow Query Log
    echo -ne "Slow Query Log: "
    if [ "$SLOW_QUERY_LOG" == "ON" ]; then
        echo -e "${YELLOW}ENABLED${NC} (Good for debugging, disable for max performance if not needed)"
    else
        echo -e "${GREEN}DISABLED${NC}"
    fi

else
    echo -e "${RED}Skipping MariaDB specific checks due to connection failure.${NC}"
fi
echo ""

# ----------------------------------------------------------------------
# PHP CHECKS (LSPHP)
# ----------------------------------------------------------------------
echo -e "${BLUE}=== PHP (LSPHP) Audit ===${NC}"

# Define list of PHP versions to check
PHP_VERSIONS=("74" "80" "81" "82" "83")

for ver in "${PHP_VERSIONS[@]}"; do
    INI_FILE="/usr/local/lsws/lsphp${ver}/etc/php.ini"
    
    if [[ -f "$INI_FILE" ]]; then
        echo -e "${CYAN}Checking LSPHP ${ver}...${NC}"
        
        # Read Values using grep/awk
        MEM_LIMIT=$(grep -E "^memory_limit" "$INI_FILE" |  awk -F "=" '{print $2}' | tr -d ' "')
        EXEC_TIME=$(grep -E "^max_execution_time" "$INI_FILE" |  awk -F "=" '{print $2}' | tr -d ' "')
        UPLOAD_MAX=$(grep -E "^upload_max_filesize" "$INI_FILE" |  awk -F "=" '{print $2}' | tr -d ' "')
        OPCACHE=$(grep -E "^opcache.enable" "$INI_FILE" | awk -F "=" '{print $2}' | tr -d ' "')

        # Memory Limit Analysis
        # Basic parsing of M/G
        MEM_VAL=${MEM_LIMIT//M/}
        MEM_VAL=${MEM_VAL//G/000} # Rough conversion G -> M
        
        echo -ne "  Memory Limit ($MEM_LIMIT): "
        if [[ "$MEM_VAL" -lt 128 ]]; then
            echo -e "${RED}LOW${NC} -> WP/Woo needs at least 256M, preferably 512M."
        elif [[ "$MEM_VAL" -lt 512 ]]; then
             echo -e "${YELLOW}MODERATE${NC} -> 512M+ recommended for WooCommerce."
        else
            echo -e "${GREEN}OK${NC}"
        fi

        echo -e "  Max Execution Time: ${GREEN}$EXEC_TIME${NC}"
        echo -e "  Upload Max Size: ${GREEN}$UPLOAD_MAX${NC}"
        
        # OpCode Cache
        echo -ne "  Opcache Enabled: "
        if [[ "$OPCACHE" == "1" || "$OPCACHE" == "On" ]]; then
             echo -e "${GREEN}YES${NC}"
        else
             echo -e "${RED}NO${NC} -> Enable opcache for significantly better performance."
        fi
        
    fi
done
echo ""

# ----------------------------------------------------------------------
# LITESPEED CHECKS
# ----------------------------------------------------------------------
echo -e "${BLUE}=== LiteSpeed Web Server Audit ===${NC}"

# Check Service
if systemctl is-active --quiet lsws; then
    echo -e "Service Status: ${GREEN}Running${NC}"
elif systemctl is-active --quiet lshttpd; then
    echo -e "Service Status: ${GREEN}Running (lshttpd)${NC}" # For OLS
else
    echo -e "Service Status: ${RED}NOT RUNNING${NC}"
fi

# Check Configuration File for some basics
# OLS Config often at /usr/local/lsws/conf/httpd_config.conf
OLS_CONF="/usr/local/lsws/conf/httpd_config.conf"

if [[ -f "$OLS_CONF" ]]; then
    # Check GZIP/Brotli
    # This is a basic grep check, structure varies
    echo -ne "GZIP Compression: "
    if grep -iq "enableGzip" "$OLS_CONF"; then
         # Check if 1
         if grep -i "enableGzip" "$OLS_CONF" | grep -q "1"; then
             echo -e "${GREEN}Enabled${NC}"
         else
             echo -e "${YELLOW}Disabled or check config${NC}"
         fi
    else
         echo -e "${YELLOW}Not explicitly found in main config (Check WebAdmin)${NC}"
    fi
    
    # Check KeepAlive
    echo -ne "Keep-Alive: "
    if grep -iq "keepAlive" "$OLS_CONF"; then
        if grep -i "keepAlive" "$OLS_CONF" | grep -q "1"; then
             echo -e "${GREEN}Enabled${NC}"
        else
             echo -e "${YELLOW}Disabled${NC}"
        fi
    else
        echo -e "${YELLOW}Not Found${NC}"
    fi

else
    echo -e "${YELLOW}Config file not found at $OLS_CONF${NC}"
fi

echo ""
echo -e "${GREEN}Audit Complete.${NC}"
echo -e "Use the 'mariadb_tuneup.sh' or 'wp_woo_optimize.sh' scripts to apply fixes."
