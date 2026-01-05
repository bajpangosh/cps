# CyberPanel MariaDB Tuneup Script by KloudBoy

A robust, safety-first MariaDB configuration optimizer designed specifically for **CyberPanel** environments running **high-traffic WooCommerce** sites.

## Features

- **🛡️ Safe & Reversible**: 
  - Creates a dedicated override file (`kloudboy-tuneup.cnf`) instead of messing with your main configs.
  - Automatically backups existing configurations before applying changes.
  - **Syntax Validation**: Checks configuration syntax before restarting to prevent downtime.
  - **Auto-Revert**: If the service fails to restart, it automatically reverts changes.

- **🚀 Smart Optimization**:
  - **Dynamic RAM Scaling**: Automatically calculates optimal `innodb_buffer_pool_size`, `max_connections`, and `innodb_log_file_size` based on total server RAM (supports <2GB to 32GB+).
  - **Low-RAM Efficiency**: Automatically disables `performance_schema` on servers with <2GB RAM to save memory (~400MB).
  - **WooCommerce Tuned**: Specific optimizations for complex queries (`tmp_table_size`, `max_heap_table_size`) and high write throughput (`O_DIRECT`, `innodb_flush_log_at_trx_commit=2`).

- **🔧 Compatibility**:
  - Automatically detects **MariaDB** or **MySQL** service names.
  - Works seamlessly with standard CyberPanel file paths.

---

## ⚡ One-Line Installation

You can run this script directly on your server with a single command. 

### Option 1: Curl (Recommended)
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/mariadb_tuneup.sh)
```

### Option 2: Wget
```bash
wget -qO- https://raw.githubusercontent.com/bajpangosh/cps/main/mariadb_tuneup.sh | bash
```

### Option 3: Non-Interactive (Auto-Approve)
Great for automation scripts.
```bash
bash <(curl -sSL https://raw.githubusercontent.com/bajpangosh/cps/main/mariadb_tuneup.sh) -y
```

---

## 🛠️ Manual Usage

1. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/bajpangosh/cps/main/mariadb_tuneup.sh
   ```
2. Make it executable:
   ```bash
   chmod +x mariadb_tuneup.sh
   ```
3. Run it as root:
   ```bash
   sudo ./mariadb_tuneup.sh
   ```

## ⚙️ What It Changes

The script calculates values based on your RAM and writes/appends to an override file (usually `/etc/mysql/mariadb.conf.d/kloudboy-tuneup.cnf`). 

Key settings adjusted:
- `innodb_buffer_pool_size`: 40-65% of RAM
- `max_connections`: Scaled 80 - 1200
- `query_cache_type`: 0 (Disabled for high concurrency)
- `innodb_flush_log_at_trx_commit`: 2 (Balanced performance/safety)
- `performance_schema`: OFF (Only for <2GB RAM nodes)

## ⚠️ Disclaimer
Always backup your databases before applying major configuration changes. While this script includes revert logic, individual server environments can vary.
