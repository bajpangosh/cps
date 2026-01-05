# CyberPanel Optimization Suite by KloudBoy

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

### 🔹 Git Push Utility
For developers maintaining this repo:
```bash
./githpush.sh "Commit message"
```

---

## ⚙️ Details

### MariaDB Logic
*   **<2GB RAM**: Disables `performance_schema` to save ~400MB RAM.
*   **Buffers**: Sets `innodb_buffer_pool_size` to 40-65% of total RAM.
*   **Safety**: Validates config syntax before restarting. Auto-reverts on failure.

### WordPress Logic
*   **Memory**: Sets `WC_MEMORY_LIMIT` to 1024M for heavy backend operations.
*   **Cron**: Replaces visitor-based triggers with reliable system cron (every 5 mins).

## ⚠️ Disclaimer
Always backup your data before applying major configuration changes. These scripts are designed to be safe (with backup logic included), but every server environment is unique.
