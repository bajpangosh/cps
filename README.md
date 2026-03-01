# CyberPanel Optimization Suite by KloudBoy
Official website: https://kloudboy.com

A collection of robust, safety-first optimization scripts designed specifically for **CyberPanel** environments running **high-traffic WooCommerce** sites.

## 🚀 Included Tools

### 1. MariaDB Tuneup (`mariadb_tuneup.sh`)
Automatically optimizes MariaDB configuration based on your server's available RAM.
*   **Dynamic RAM Scaling**: Adjusts `innodb_buffer_pool_size`, `max_connections`, etc.
*   **Safe**: Creates override configs instead of editing main files.
*   **WooCommerce Ready**: Tuned for complex queries and high write throughput.

### 2. WordPress & Woo Optimizer (`wp_woo_optimize.sh`)
Interactive tool to optimize individual WordPress installations.
*   **Config Tuning**: Increases Memory Limits (`WP_MEMORY_LIMIT`) in `wp-config.php`.
*   **Cron Management**: Disables `WP_CRON` and sets up a system-level cron job.
*   **DB Cleanup**: Uses `wp-cli` to clear transients and optimize tables.

### 3. Server Audit (`cyberpanel_audit.sh`)
A diagnostic health checker for your CyberPanel server.
*   **MariaDB Audit**: Checks Buffer Pool usage and connection limits.
*   **PHP Audit**: Scans active LSPHP versions for memory limits and opcache status.
*   **LiteSpeed Check**: Verifies GZIP, KeepAlive, and service status.

### 4. CyberPanel Manager (`cyberpanel_manager.sh`)
Interactive control center for daily CyberPanel operations.
*   **Service Control**: Health snapshot, core restarts, and single-service actions.
*   **Official Maintenance Hooks**: Runs CyberPanel official `preUpgrade.sh` and `watchdog.sh`.
*   **Bandwidth Reset**: Executes `/usr/local/CyberCP/scripts/reset_bandwidth.sh` when available.

### 5. CyberPanel Backup Manager (`cyberpanel_backup_manager.sh`)
Backup and restore control plane built on CyberPanel native CLI commands.
*   **Native Backup/Restore**: Uses `cyberpanel createBackup` and `cyberpanel restoreBackup`.
*   **Backup Pool Management**: Works with `/home/<domain>/backup` and `/home/backup`.
*   **Operations**: Retention cleanup, archive verification, and backup scheduling.

### 6. WP-CLI Toolkit (`wp_cli_toolkit.sh`)
Interactive WP-CLI command center with website-first workflow.
*   **Website First**: Selects the target WordPress installation before any action.
*   **Useful Command Groups**: Core, plugins, themes, database, cache, users, search/replace, and cron.
*   **Safety Layer**: Built-in confirmations and optional DB backup before heavy operations.

### 7. Main Launcher (`cps.sh`)
All-in-one entry point for this toolkit.
*   **Single Menu**: Launches all CPS scripts from one place.
*   **Flexible**: Runs local scripts if present, or downloads missing tools from the repo.
*   **Operator Friendly**: Includes unattended MariaDB option and clear menu flow.

---

## ⚡ Quick Execution (One-Liners)

Run these commands directly on your server to execute the tools without manually downloading them.

### 🔹 1. MariaDB Tuneup
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/mariadb_tuneup.sh)
```

### 🔹 2. WordPress & Woo Optimizer
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/wp_woo_optimize.sh)
```

### 🔹 3. Server Audit
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/cyberpanel_audit.sh)
```

### 🔹 4. CyberPanel Manager
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/cyberpanel_manager.sh)
```

### 🔹 5. CyberPanel Backup Manager
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/cyberpanel_backup_manager.sh)
```

### 🔹 6. WP-CLI Toolkit
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/wp_cli_toolkit.sh)
```

### 🔹 7. Main Launcher (Recommended)
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/cps.sh)
```

---

## 📦 Manual Installation & Usage

You can clone the repo or download scripts individually.

```bash
git clone https://github.com/bajpangosh/cps.git
cd cps
chmod +x *.sh
```

### 🔹 Run MariaDB Tuneup
```bash
sudo ./mariadb_tuneup.sh
```
*   **Unattended mode**: `sudo ./mariadb_tuneup.sh -y`

### 🔹 Run WordPress Optimizer
```bash
sudo ./wp_woo_optimize.sh
```
*   This will scan `/home` and present a menu of sites to optimize.

### 🔹 Run Server Audit
```bash
sudo ./cyberpanel_audit.sh
```
*   Gives you an instant "Pass/Fail" style report on your configuration.

### 🔹 Run CyberPanel Manager
```bash
sudo ./cyberpanel_manager.sh
```
*   Includes service restart/status control, official upgrade trigger, watchdog run, and quick logs.

### 🔹 Run CyberPanel Backup Manager
```bash
sudo ./cyberpanel_backup_manager.sh
```
*   Includes native backup/restore, file verification, retention pruning, and daily cron scheduling.

### 🔹 Run WP-CLI Toolkit
```bash
sudo ./wp_cli_toolkit.sh
```
*   First selects a website, then opens command menus for core/plugins/themes/DB/cache/users/cron/search-replace.

### 🔹 Run Main Launcher (Recommended)
```bash
sudo ./cps.sh
```
*   One menu for audit, MariaDB tuneup, WP optimizer, CyberPanel manager, backup manager, and WP-CLI toolkit.

### 🔹 Git Push Utility
For developers maintaining this repo:
```bash
./githpush.sh "Commit message"
```
*   You can also run `./githpush.sh` and enter the message interactively.
*   Script now exits cleanly when there are no changes to commit.

---

## ⚙️ Details

### MariaDB Logic
*   **<2GB RAM**: Disables `performance_schema` to save ~400MB RAM.
*   **Buffers**: Sets `innodb_buffer_pool_size` to 40-65% of total RAM.
*   **Safety**: Validates config syntax before restarting. Auto-reverts on failure.

### WordPress Logic
*   **Memory**: Sets `WC_MEMORY_LIMIT` to 1024M for heavy backend operations.
*   **Cron**: Replaces visitor-based triggers with reliable system cron (every 5 mins).

### CyberPanel Manager Logic
*   **Core Services**: Detects and manages `lscpd`, `lsws`, and active DB service (`mariadb`/`mysql`).
*   **Official Scripts**: Pulls upgrade/watchdog scripts from the official CyberPanel repo.
*   **Operational Safety**: Confirms before restarts/upgrades and avoids duplicate cron/log actions.

### CyberPanel Backup Manager Logic
*   **Native CLI Integration**: Executes backup and restore through CyberPanel official CLI.
*   **Path Compatibility**: Handles site backups under `/home/<domain>/backup` and global pool `/home/backup`.
*   **Backup Hygiene**: Adds verification checks and time-based cleanup to reduce stale backup buildup.

### WP-CLI Toolkit Logic
*   **Website Context**: All WP-CLI commands run against the selected `--path`.
*   **Ownership Safety**: Executes commands as the website owner where possible.
*   **Operational Coverage**: Covers frequent day-to-day WP admin tasks without remembering raw CLI syntax.

### Main Launcher Logic
*   **Central Control**: Exposes every toolkit script in a single operations menu.
*   **Execution Fallback**: Uses local scripts first, then fetches from GitHub if missing.
*   **Simple Operations**: Reduces operator mistakes by avoiding manual script-name entry.

## ⚠️ Disclaimer
Always backup your data before applying major configuration changes. These scripts are designed to be safe (with backup logic included), but every server environment is unique.
