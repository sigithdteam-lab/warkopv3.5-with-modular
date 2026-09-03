auto_tune_webserver() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Proceed with auto-tuning webserver on selected servers? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

# Detect CPU cores
CPU=$(nproc 2>/dev/null || echo 1)
# Detect total RAM in MB
MEM=$(free -m | awk '/Mem:/{print $2}')
[ -z "$MEM" ] && MEM=1024

# Detect webserver: nginx or apache
if command -v nginx >/dev/null 2>&1 && systemctl is-active nginx >/dev/null 2>&1; then
    echo "Detected Nginx. Tuning..."
    if [ -f /etc/nginx/nginx.conf ]; then
        $SUDO cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)
        # worker_processes = CPU cores
        $SUDO sed -i "s/^worker_processes .*/worker_processes $CPU;/" /etc/nginx/nginx.conf
        # worker_connections = CPU * 1024 (adjust based on memory)
        CONN=$((CPU * 1024))
        $SUDO sed -i "s/^worker_connections .*/worker_connections $CONN;/" /etc/nginx/nginx.conf
        # Optional: increase client_max_body_size if not set
        if ! grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
            $SUDO sed -i "/http {/a \    client_max_body_size 100M;" /etc/nginx/nginx.conf
        fi
        $SUDO systemctl restart nginx
        echo "Nginx tuned: worker_processes=$CPU, worker_connections=$CONN"
    else
        echo "nginx.conf not found at /etc/nginx/nginx.conf"
    fi
elif command -v apache2 >/dev/null 2>&1 && systemctl is-active apache2 >/dev/null 2>&1; then
    echo "Detected Apache2 (Debian/Ubuntu). Tuning..."
    CONF="/etc/apache2/apache2.conf"
    if [ -f "$CONF" ]; then
        $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
        # Determine MPM: prefork or event/worker
        if grep -q "mpm_prefork" /etc/apache2/mods-enabled/*.conf 2>/dev/null; then
            # Prefork: set MaxRequestWorkers based on RAM (approx 2MB per worker)
            MAX_WORKERS=$(( MEM / 2 ))
            [ $MAX_WORKERS -lt 50 ] && MAX_WORKERS=50
            [ $MAX_WORKERS -gt 1000 ] && MAX_WORKERS=1000
            $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/apache2/mods-available/mpm_prefork.conf
            $SUDO sed -i "s/^[ ]*StartServers .*/StartServers $(( CPU * 2 ))/" /etc/apache2/mods-available/mpm_prefork.conf
            $SUDO sed -i "s/^[ ]*MinSpareServers .*/MinSpareServers $(( CPU * 2 ))/" /etc/apache2/mods-available/mpm_prefork.conf
            $SUDO sed -i "s/^[ ]*MaxSpareServers .*/MaxSpareServers $(( CPU * 4 ))/" /etc/apache2/mods-available/mpm_prefork.conf
            echo "Apache prefork tuned: MaxRequestWorkers=$MAX_WORKERS"
        else
            # event or worker: adjust threads/connections
            MAX_WORKERS=$(( MEM / 4 ))
            [ $MAX_WORKERS -lt 50 ] && MAX_WORKERS=50
            [ $MAX_WORKERS -gt 2000 ] && MAX_WORKERS=2000
            $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/apache2/mods-available/mpm_event.conf 2>/dev/null || \
            $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/apache2/mods-available/mpm_worker.conf 2>/dev/null
            echo "Apache event/worker tuned: MaxRequestWorkers=$MAX_WORKERS"
        fi
        $SUDO systemctl restart apache2
    else
        echo "Apache2 config not found at $CONF"
    fi
elif command -v httpd >/dev/null 2>&1 && systemctl is-active httpd >/dev/null 2>&1; then
    echo "Detected Apache (RHEL/CentOS). Tuning..."
    CONF="/etc/httpd/conf/httpd.conf"
    if [ -f "$CONF" ]; then
        $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
        # Similar tuning for prefork or event
        MAX_WORKERS=$(( MEM / 2 ))
        [ $MAX_WORKERS -lt 50 ] && MAX_WORKERS=50
        [ $MAX_WORKERS -gt 1000 ] && MAX_WORKERS=1000
        $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/httpd/conf/httpd.conf
        $SUDO sed -i "s/^[ ]*StartServers .*/StartServers $(( CPU * 2 ))/" /etc/httpd/conf/httpd.conf
        $SUDO sed -i "s/^[ ]*MinSpareServers .*/MinSpareServers $(( CPU * 2 ))/" /etc/httpd/conf/httpd.conf
        $SUDO sed -i "s/^[ ]*MaxSpareServers .*/MaxSpareServers $(( CPU * 4 ))/" /etc/httpd/conf/httpd.conf
        $SUDO systemctl restart httpd
        echo "Apache (httpd) tuned: MaxRequestWorkers=$MAX_WORKERS"
    else
        echo "httpd.conf not found at $CONF"
    fi
else
    echo "No supported webserver (nginx/apache) found running."
fi
EOF
)
    run_action_on_servers_sudo "$script" "Auto-tune webserver"
}

auto_tune_database() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Proceed with auto-tuning database on selected servers? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

# Detect database: MySQL/MariaDB or PostgreSQL
if command -v mysql >/dev/null 2>&1 && systemctl is-active mysql >/dev/null 2>&1; then
    DB="mysql"
elif command -v mariadb >/dev/null 2>&1 && systemctl is-active mariadb >/dev/null 2>&1; then
    DB="mariadb"
elif command -v postgres >/dev/null 2>&1 && systemctl is-active postgresql >/dev/null 2>&1; then
    DB="postgres"
else
    echo "No supported database (MySQL/MariaDB/PostgreSQL) found running."
    exit 1
fi

# Get total RAM in MB
MEM=$(free -m | awk '/Mem:/{print $2}')
[ -z "$MEM" ] && MEM=1024
# Calculate buffer pool size: 70% of RAM for dedicated, 50% for shared (adjust)
# We assume dedicated server; reduce if other services run.
BUFFER_SIZE=$(( MEM * 70 / 100 ))
[ $BUFFER_SIZE -lt 256 ] && BUFFER_SIZE=256
[ $BUFFER_SIZE -gt 8192 ] && BUFFER_SIZE=8192   # cap at 8GB to avoid over-allocation

case $DB in
    mysql|mariadb)
        CONF="/etc/mysql/my.cnf"
        [ ! -f "$CONF" ] && CONF="/etc/my.cnf"
        if [ -f "$CONF" ]; then
            $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
            # Remove existing innodb_buffer_pool_size lines
            $SUDO sed -i '/^innodb_buffer_pool_size/d' "$CONF"
            $SUDO sed -i '/^query_cache_size/d' "$CONF"
            $SUDO sed -i '/^max_connections/d' "$CONF"
            # Add new settings under [mysqld] section (or create if missing)
            if grep -q "\[mysqld\]" "$CONF"; then
                $SUDO sed -i "/\[mysqld\]/a innodb_buffer_pool_size = ${BUFFER_SIZE}M\nquery_cache_size = ${BUFFER_SIZE}M\nmax_connections = $(( MEM / 2 ))" "$CONF"
            else
                echo -e "\n[mysqld]\ninnodb_buffer_pool_size = ${BUFFER_SIZE}M\nquery_cache_size = ${BUFFER_SIZE}M\nmax_connections = $(( MEM / 2 ))" | $SUDO tee -a "$CONF"
            fi
            $SUDO systemctl restart mysql || $SUDO systemctl restart mariadb
            echo "MySQL/MariaDB tuned: innodb_buffer_pool_size=${BUFFER_SIZE}M, max_connections=$(( MEM / 2 ))"
        else
            echo "MySQL config file not found."
        fi
        ;;
    postgres)
        CONF="/etc/postgresql/*/main/postgresql.conf"  # version specific
        # Simplify: find latest version
        CONF=$(ls /etc/postgresql/*/main/postgresql.conf 2>/dev/null | head -1)
        if [ -f "$CONF" ]; then
            $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
            # Set shared_buffers to 25% of RAM (PostgreSQL recommendation)
            SHARED=$(( MEM * 25 / 100 ))
            [ $SHARED -lt 128 ] && SHARED=128
            [ $SHARED -gt 8192 ] && SHARED=8192
            $SUDO sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED}MB/" "$CONF"
            $SUDO sed -i "s/^max_connections = .*/max_connections = $(( MEM / 4 ))/" "$CONF"
            $SUDO systemctl restart postgresql
            echo "PostgreSQL tuned: shared_buffers=${SHARED}MB, max_connections=$(( MEM / 4 ))"
        else
            echo "PostgreSQL config not found."
        fi
        ;;
esac
EOF
)
    run_action_on_servers_sudo "$script" "Auto-tune database"
}

database_repair() {
    read_servers
    if ! select_servers; then return; fi
    echo "Select database repair action:"
    echo "1) Optimize tables (mysqlcheck -o)"
    echo "2) Repair tables (mysqlcheck -r)"
    echo "3) Optimize and repair (mysqlcheck -o -r)"
    read -p "Choose (1-3): " action
    case $action in
        1) repair_opt="--optimize" ;;
        2) repair_opt="--repair" ;;
        3) repair_opt="--optimize --repair" ;;
        *) warn "Invalid choice."; return ;;
    esac

    read -p "Proceed with database repair/optimize on selected servers? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

# Detect MySQL/MariaDB and run mysqlcheck
if command -v mysql >/dev/null 2>&1; then
    DB="mysql"
elif command -v mariadb >/dev/null 2>&1; then
    DB="mariadb"
else
    echo "MySQL/MariaDB not found."
    exit 1
fi

# Get mysql credentials (assume root with no password or from /root/.my.cnf)
# Try to use debian-sys-maint if available
if [ -f /etc/mysql/debian.cnf ]; then
    USER=$(grep "^user" /etc/mysql/debian.cnf | head -1 | awk '{print $3}')
    PASS=$(grep "^password" /etc/mysql/debian.cnf | head -1 | awk '{print $3}')
    HOST="localhost"
elif [ -f /root/.my.cnf ]; then
    USER=$(grep "^user" /root/.my.cnf | head -1 | awk '{print $3}')
    PASS=$(grep "^password" /root/.my.cnf | head -1 | awk '{print $3}')
    HOST=$(grep "^host" /root/.my.cnf | head -1 | awk '{print $3}')
    [ -z "$HOST" ] && HOST="localhost"
else
    # Fallback: try root without password
    USER="root"
    PASS=""
    HOST="localhost"
fi

if [ -z "$USER" ]; then
    USER="root"
fi

MYSQL_CMD="mysql -h $HOST -u $USER"
[ -n "$PASS" ] && MYSQL_CMD="$MYSQL_CMD -p$PASS"

# Check if we can connect
if ! $MYSQL_CMD -e "exit" 2>/dev/null; then
    echo "Cannot connect to MySQL/MariaDB. Skipping."
    exit 1
fi

echo "Running mysqlcheck $repair_opt --all-databases ..."
$SUDO mysqlcheck $repair_opt --all-databases -h $HOST -u $USER $([ -n "$PASS" ] && echo "-p$PASS") 2>&1
if [ $? -eq 0 ]; then
    echo "Database repair/optimize completed successfully."
else
    echo "mysqlcheck completed with warnings/errors (check output)."
fi
EOF
)
    script=$(echo "$script" | sed "s/\\\$repair_opt/$repair_opt/g")
    run_action_on_servers_sudo "$script" "Database repair/optimize"
}


# ======================================================================
# 11. Server Installation Management
# ======================================================================

run_install_script() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

# ----------------------------------------------------------------------
# Instalasi Komponen Tunggal
# ----------------------------------------------------------------------
install_apache_php() {
    echo "Akan menginstal: Apache2 + PHP (mod_php) + ekstensi umum."
    echo "Paket: apache2, php, libapache2-mod-php, php-mysql, php-pgsql, php-cli, php-curl, php-zip, php-gd, php-mbstring, php-xml"
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y apache2 php libapache2-mod-php php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable apache2
    $SUDO systemctl start apache2
    echo "Apache status:"
    $SUDO systemctl status apache2 --no-pager | head -5
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y httpd php php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable httpd
    $SUDO systemctl start httpd
    echo "Apache status:"
    $SUDO systemctl status httpd --no-pager | head -5
else
    echo "Unsupported OS"
    exit 1
fi
php -v | head -1
echo "Apache + PHP installed successfully."
EOF
)
    run_install_script "$script" "Install Apache + PHP"
    echo "========================================="
    echo "Instalasi selesai. File konfigurasi:"
    echo "  Apache: /etc/apache2/apache2.conf (Debian/Ubuntu) atau /etc/httpd/conf/httpd.conf (RHEL)"
    echo "  PHP: /etc/php/*/cli/php.ini dan /etc/php/*/apache2/php.ini"
    echo "  VirtualHost: /etc/apache2/sites-available/ (Debian) atau /etc/httpd/conf.d/ (RHEL)"
    echo "Untuk mengedit manual: nano /path/file"
    echo "Restart service setelah perubahan: systemctl restart apache2 (atau httpd)"
}

install_nginx_php() {
    echo "Akan menginstal: Nginx + PHP-FPM + ekstensi PHP."
    echo "Paket: nginx, php-fpm, php-mysql, php-pgsql, php-cli, php-curl, php-zip, php-gd, php-mbstring, php-xml"
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    echo "Nginx status:"
    $SUDO systemctl status nginx --no-pager | head -5
    echo "PHP-FPM status:"
    $SUDO systemctl status php-fpm --no-pager | head -5
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    echo "Nginx status:"
    $SUDO systemctl status nginx --no-pager | head -5
    echo "PHP-FPM status:"
    $SUDO systemctl status php-fpm --no-pager | head -5
else
    echo "Unsupported OS"
    exit 1
fi
php -v | head -1
echo "Nginx + PHP-FPM installed successfully."
EOF
)
    run_install_script "$script" "Install Nginx + PHP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Nginx: /etc/nginx/nginx.conf"
    echo "  PHP-FPM: /etc/php/*/fpm/php.ini dan /etc/php/*/fpm/pool.d/www.conf"
    echo "  VirtualHost: /etc/nginx/sites-available/ (Debian) atau /etc/nginx/conf.d/ (RHEL)"
    echo "Restart service setelah perubahan: systemctl restart nginx php-fpm"
}

install_mariadb() {
    echo "Akan menginstal: MariaDB Server + Client."
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y mariadb-server mariadb-client
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y mariadb-server mariadb
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
$SUDO systemctl status mariadb --no-pager | head -5
mysql --version
echo "MariaDB installed and started."
EOF
)
    run_install_script "$script" "Install MariaDB"
    echo "========================================="
    echo "File konfigurasi: /etc/mysql/my.cnf (Debian) atau /etc/my.cnf (RHEL)"
    echo "Setelah instalasi, jalankan 'mysql_secure_installation' untuk keamanan."
    echo "Untuk mengedit: nano /etc/mysql/my.cnf"
    echo "Restart: systemctl restart mariadb"
}

install_postgresql() {
    echo "Akan menginstal: PostgreSQL Server + kontribusi."
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y postgresql postgresql-contrib
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y postgresql-server postgresql-contrib
    $SUDO postgresql-setup initdb
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
$SUDO systemctl status postgresql --no-pager | head -5
psql --version
echo "PostgreSQL installed and started."
EOF
)
    run_install_script "$script" "Install PostgreSQL"
    echo "========================================="
    echo "File konfigurasi: /etc/postgresql/*/main/postgresql.conf (Debian) atau /var/lib/pgsql/data/postgresql.conf (RHEL)"
    echo "File hba: /etc/postgresql/*/main/pg_hba.conf"
    echo "Untuk mengedit: nano /path/postgresql.conf"
    echo "Restart: systemctl restart postgresql"
}

# ----------------------------------------------------------------------
# Stack Lengkap
# ----------------------------------------------------------------------
install_lamp() {
    echo "Akan menginstal LAMP (Apache + PHP + MariaDB) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y apache2 php libapache2-mod-php php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable apache2
    $SUDO systemctl start apache2
    $SUDO apt-get install -y mariadb-server mariadb-client
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y httpd php php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable httpd
    $SUDO systemctl start httpd
    $SUDO yum install -y mariadb-server mariadb
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status apache2 --no-pager | head -3 2>/dev/null || $SUDO systemctl status httpd --no-pager | head -3
$SUDO systemctl status mariadb --no-pager | head -3
echo "LAMP installed successfully."
EOF
)
    run_install_script "$script" "Install LAMP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Apache: /etc/apache2/apache2.conf atau /etc/httpd/conf/httpd.conf"
    echo "  PHP: /etc/php/*/apache2/php.ini"
    echo "  MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
    echo "Jangan lupa jalankan mysql_secure_installation."
}

install_lapp() {
    echo "Akan menginstal LAPP (Apache + PHP + PostgreSQL) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y apache2 php libapache2-mod-php php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable apache2
    $SUDO systemctl start apache2
    $SUDO apt-get install -y postgresql postgresql-contrib
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y httpd php php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable httpd
    $SUDO systemctl start httpd
    $SUDO yum install -y postgresql-server postgresql-contrib
    $SUDO postgresql-setup initdb
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status apache2 --no-pager | head -3 2>/dev/null || $SUDO systemctl status httpd --no-pager | head -3
$SUDO systemctl status postgresql --no-pager | head -3
echo "LAPP installed successfully."
EOF
)
    run_install_script "$script" "Install LAPP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Apache: /etc/apache2/apache2.conf atau /etc/httpd/conf/httpd.conf"
    echo "  PHP: /etc/php/*/apache2/php.ini"
    echo "  PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
}

install_lemp() {
    echo "Akan menginstal LEMP (Nginx + PHP-FPM + MariaDB) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO apt-get install -y mariadb-server mariadb-client
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO yum install -y mariadb-server mariadb
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status nginx --no-pager | head -3
$SUDO systemctl status php-fpm --no-pager | head -3 2>/dev/null
$SUDO systemctl status mariadb --no-pager | head -3
echo "LEMP installed successfully."
EOF
)
    run_install_script "$script" "Install LEMP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Nginx: /etc/nginx/nginx.conf"
    echo "  PHP-FPM: /etc/php/*/fpm/php.ini"
    echo "  MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
}

install_lepp() {
    echo "Akan menginstal LEPP (Nginx + PHP-FPM + PostgreSQL) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO apt-get install -y postgresql postgresql-contrib
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO yum install -y postgresql-server postgresql-contrib
    $SUDO postgresql-setup initdb
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status nginx --no-pager | head -3
$SUDO systemctl status php-fpm --no-pager | head -3 2>/dev/null
$SUDO systemctl status postgresql --no-pager | head -3
echo "LEPP installed successfully."
EOF
)
    run_install_script "$script" "Install LEPP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Nginx: /etc/nginx/nginx.conf"
    echo "  PHP-FPM: /etc/php/*/fpm/php.ini"
    echo "  PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
}

# ----------------------------------------------------------------------
# Auto Tuning
# ----------------------------------------------------------------------
auto_tune_apache() {
    echo "Akan melakukan auto-tuning Apache berdasarkan resource server (RAM & CPU)."
    echo "Perubahan akan diterapkan pada konfigurasi MPM prefork."
    if ! confirm_action "Lanjutkan tuning?"; then
        info "Tuning dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
if [ -f /etc/apache2/apache2.conf ] || [ -f /etc/httpd/conf/httpd.conf ]; then
    if [ -f /etc/apache2/apache2.conf ]; then
        CONF="/etc/apache2/apache2.conf"
        MODS_DIR="/etc/apache2/mods-available"
    else
        CONF="/etc/httpd/conf/httpd.conf"
        MODS_DIR="/etc/httpd/conf.modules.d"
    fi
    if [ -f /etc/apache2/mods-available/mpm_prefork.conf ]; then
        a2enmod mpm_prefork 2>/dev/null
    fi
    max_workers=$(( (mem_total * 80 / 100) / 15 ))
    [ $max_workers -lt 5 ] && max_workers=5
    max_workers=$(( max_workers < (cpu_cores * 20) ? max_workers : cpu_cores * 20 ))
    start_servers=$(( cpu_cores * 2 ))
    [ $start_servers -lt 3 ] && start_servers=3
    min_spare=$(( cpu_cores * 2 ))
    max_spare=$(( cpu_cores * 4 ))
    [ $max_spare -lt 5 ] && max_spare=5
    cat <<EOT > /tmp/apache_tuning.conf
<IfModule mpm_prefork_module>
    StartServers          $start_servers
    MinSpareServers       $min_spare
    MaxSpareServers       $max_spare
    MaxRequestWorkers     $max_workers
    MaxConnectionsPerChild 10000
</IfModule>
EOT
    if [ -f /etc/apache2/mods-available/mpm_prefork.conf ]; then
        $SUDO cp /tmp/apache_tuning.conf /etc/apache2/mods-available/mpm_prefork.conf
        $SUDO systemctl restart apache2
    elif [ -f /etc/httpd/conf.modules.d/mpm_prefork.conf ]; then
        $SUDO cp /tmp/apache_tuning.conf /etc/httpd/conf.modules.d/mpm_prefork.conf
        $SUDO systemctl restart httpd
    else
        $SUDO cat /tmp/apache_tuning.conf >> $CONF
        $SUDO systemctl restart apache2 2>/dev/null || $SUDO systemctl restart httpd
    fi
    echo "Apache tuning applied. Values: StartServers=$start_servers, MaxWorkers=$max_workers, MinSpare=$min_spare, MaxSpare=$max_spare"
else
    echo "Apache not found."
fi
EOF
)
    run_install_script "$script" "Auto Tuning Apache"
    echo "========================================="
    echo "Tuning selesai. File konfigurasi yang diubah:"
    echo "  - /etc/apache2/mods-available/mpm_prefork.conf (Debian)"
    echo "  - /etc/httpd/conf.modules.d/mpm_prefork.conf (RHEL) atau /etc/httpd/conf/httpd.conf"
    echo "Periksa nilai yang diterapkan di file tersebut."
    echo "Restart Apache untuk menerapkan: systemctl restart apache2 (atau httpd)"
}

auto_tune_nginx() {
    echo "Akan melakukan auto-tuning Nginx berdasarkan resource server."
    if ! confirm_action "Lanjutkan tuning?"; then
        info "Tuning dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
if [ -f /etc/nginx/nginx.conf ]; then
    worker_proc=$cpu_cores
    [ $worker_proc -lt 1 ] && worker_proc=1
    max_conn=$(( (mem_total * 1024) / 512 ))
    [ $max_conn -lt 1024 ] && max_conn=1024
    [ $max_conn -gt 65536 ] && max_conn=65536
    $SUDO sed -i "s/^worker_processes.*/worker_processes $worker_proc;/" /etc/nginx/nginx.conf
    $SUDO sed -i "s/^worker_connections.*/worker_connections $max_conn;/" /etc/nginx/nginx.conf
    echo "fs.file-max = 65535" | $SUDO tee -a /etc/sysctl.conf
    $SUDO sysctl -p
    $SUDO systemctl restart nginx
    echo "Nginx tuned: worker_processes=$worker_proc, worker_connections=$max_conn"
else
    echo "Nginx not found."
fi
EOF
)
    run_install_script "$script" "Auto Tuning Nginx"
    echo "========================================="
    echo "Tuning selesai. File yang diubah: /etc/nginx/nginx.conf"
    echo "Periksa nilai worker_processes dan worker_connections."
    echo "Restart Nginx: systemctl restart nginx"
}

auto_tune_db() {
    echo "Akan melakukan auto-tuning database (MariaDB/PostgreSQL) berdasarkan resource."
    if ! confirm_action "Lanjutkan tuning?"; then
        info "Tuning dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
if command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1; then
    innodb_pool=$(( mem_total * 70 / 100 ))
    [ $innodb_pool -lt 128 ] && innodb_pool=128
    if [ -f /etc/mysql/my.cnf ]; then
        $SUDO sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${innodb_pool}M/" /etc/mysql/my.cnf
        grep -q "innodb_log_file_size" /etc/mysql/my.cnf || echo "innodb_log_file_size = 256M" | $SUDO tee -a /etc/mysql/my.cnf
        grep -q "max_connections" /etc/mysql/my.cnf || echo "max_connections = 200" | $SUDO tee -a /etc/mysql/my.cnf
        $SUDO systemctl restart mariadb || $SUDO systemctl restart mysql
        echo "MariaDB/MySQL tuned: innodb_buffer_pool_size=${innodb_pool}M"
    elif [ -f /etc/my.cnf ]; then
        $SUDO sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${innodb_pool}M/" /etc/my.cnf
        grep -q "innodb_log_file_size" /etc/my.cnf || echo "innodb_log_file_size = 256M" | $SUDO tee -a /etc/my.cnf
        grep -q "max_connections" /etc/my.cnf || echo "max_connections = 200" | $SUDO tee -a /etc/my.cnf
        $SUDO systemctl restart mariadb || $SUDO systemctl restart mysql
        echo "MariaDB/MySQL tuned: innodb_buffer_pool_size=${innodb_pool}M"
    else
        echo "MySQL config not found."
    fi
elif command -v psql >/dev/null 2>&1; then
    shared_buf=$(( mem_total * 25 / 100 ))
    [ $shared_buf -lt 128 ] && shared_buf=128
    eff_cache=$(( mem_total * 50 / 100 ))
    work_mem=$(( (mem_total * 25 / 100) / 100 ))
    [ $work_mem -lt 4 ] && work_mem=4
    if [ -f /etc/postgresql/*/main/postgresql.conf ]; then
        CONF=$(ls /etc/postgresql/*/main/postgresql.conf | head -1)
    elif [ -f /var/lib/pgsql/data/postgresql.conf ]; then
        CONF=/var/lib/pgsql/data/postgresql.conf
    else
        echo "PostgreSQL config not found."
        exit 1
    fi
    $SUDO sed -i "s/^shared_buffers.*/shared_buffers = ${shared_buf}MB/" $CONF
    $SUDO sed -i "s/^effective_cache_size.*/effective_cache_size = ${eff_cache}MB/" $CONF
    $SUDO sed -i "s/^work_mem.*/work_mem = ${work_mem}MB/" $CONF
    $SUDO systemctl restart postgresql
    echo "PostgreSQL tuned: shared_buffers=${shared_buf}MB, work_mem=${work_mem}MB"
else
    echo "No database found."
fi
EOF
)
    run_install_script "$script" "Auto Tuning Database"
    echo "========================================="
    echo "Tuning selesai. File yang diubah:"
    echo "  MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
    echo "  PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
    echo "Restart service database setelah perubahan."
}

# ----------------------------------------------------------------------
# Rekomendasi Terbaik
# ----------------------------------------------------------------------
show_recommendations() {
    echo "Menampilkan rekomendasi terbaik untuk server web & database."
    if ! confirm_action "Lanjutkan?"; then
        info "Dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo (tidak diperlukan untuk rekomendasi, tapi konsisten)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
echo "========== BEST PRACTICE RECOMMENDATIONS =========="
echo "Server specs: Memory=${mem_total}MB, CPU cores=$cpu_cores"
echo ""
echo "1. For Web Server (Apache/Nginx):"
echo "   - Use PHP-FPM instead of mod_php (Apache) for better performance."
echo "   - Enable opcache and set recommended values:"
echo "       opcache.memory_consumption=128"
echo "       opcache.max_accelerated_files=4000"
echo "   - For high traffic, use Nginx as reverse proxy + Apache/php-fpm."
echo "   - Enable Gzip compression and caching headers."
echo ""
echo "2. For Database (MySQL/MariaDB):"
echo "   - innodb_buffer_pool_size: 70-80% of RAM for dedicated DB."
echo "   - innodb_log_file_size: 256MB-1GB depending on writes."
echo "   - max_connections: adjust based on traffic; start with 200."
echo "   - Query cache: disable for high-write workloads."
echo ""
echo "3. For PostgreSQL:"
echo "   - shared_buffers: 25% of RAM."
echo "   - effective_cache_size: 50% of RAM."
echo "   - work_mem: (RAM * 0.25) / max_connections."
echo "   - Enable autovacuum and tune thresholds."
echo ""
echo "4. System-level:"
echo "   - Increase file descriptor limits (fs.file-max)."
echo "   - Use TCP tweaks: net.ipv4.tcp_tw_reuse, net.ipv4.tcp_fin_timeout."
echo "   - Keep OS updated and use a firewall."
echo ""
echo "5. Monitoring:"
echo "   - Install monitoring tools (htop, iotop, netstat)."
echo "   - Set up log rotation to avoid disk full."
echo ""
echo "Based on your current resources, consider:"
if [ $mem_total -lt 2048 ]; then
    echo "   - Low memory (<2GB): Use Nginx + PHP-FPM with small child limits."
    echo "   - Use MariaDB with small buffer pool."
elif [ $mem_total -lt 4096 ]; then
    echo "   - Medium memory (2-4GB): Apache + PHP-FPM or Nginx."
    echo "   - Database buffer pool: 1-2GB."
else
    echo "   - High memory (>4GB): Tune aggressively, use caching (Redis/Memcached)."
fi
echo "===================================================="
EOF
)
    run_install_script "$script" "Best Recommendations"
    echo "========================================="
    echo "Untuk mengimplementasikan rekomendasi, edit file konfigurasi:"
    echo "  - Apache: /etc/apache2/apache2.conf atau /etc/httpd/conf/httpd.conf"
    echo "  - Nginx: /etc/nginx/nginx.conf"
    echo "  - PHP: /etc/php/*/cli/php.ini dan /etc/php/*/fpm/php.ini (jika pakai FPM)"
    echo "  - MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
    echo "  - PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
    echo "Setelah mengedit, restart service terkait."
}

# ----------------------------------------------------------------------
# Instalasi Farm Server (Load Balancer/HA)
# ----------------------------------------------------------------------
install_farm_server() {
    echo "========================================="
    echo "  INSTALASI FARM SERVER (LOAD BALANCER/HA)"
    echo "========================================="
    echo "Arsitektur yang akan dibuat:"
    echo "  - 1 Load Balancer (HAProxy) - IP publik"
    echo "  - 2 Web Server (Nginx + PHP-FPM) - IP internal"
    echo "  - 1 Database Server (MariaDB atau PostgreSQL) - IP internal"
    echo "  - 1 File Server (NFS) - IP internal"
    echo ""
    echo "Pastikan semua server sudah memiliki SSH key dan akses sudo."
    if ! confirm_action "Lanjutkan instalasi farm server?"; then
        info "Dibatalkan."
        return
    fi

    # Kumpulkan IP
    echo "Masukkan alamat IP untuk masing-masing server (format: user@ip atau ip saja):"
    read -p "Load Balancer (HAProxy)   : " lb_ip
    read -p "Web Server 1              : " web1_ip
    read -p "Web Server 2              : " web2_ip
    read -p "Database Server           : " db_ip
    read -p "File Server (NFS)         : " fs_ip

    # Validasi sederhana
    if [[ -z "$lb_ip" || -z "$web1_ip" || -z "$web2_ip" || -z "$db_ip" || -z "$fs_ip" ]]; then
        error "Semua IP harus diisi."
        return
    fi

    # Pilih jenis database
    echo "Pilih jenis database:"
    echo "1) MariaDB"
    echo "2) PostgreSQL"
    read -p "Pilihan (1/2): " db_choice
    case $db_choice in
        1) DB_TYPE="mariadb" ;;
        2) DB_TYPE="postgresql" ;;
        *) error "Pilihan tidak valid."; return ;;
    esac

    echo "========================================="
    echo "Ringkasan konfigurasi:"
    echo "  LB       : $lb_ip"
    echo "  Web1     : $web1_ip"
    echo "  Web2     : $web2_ip"
    echo "  DB       : $db_ip ($DB_TYPE)"
    echo "  File     : $fs_ip"
    if ! confirm_action "Apakah konfigurasi sudah benar?"; then
        info "Dibatalkan."
        return
    fi

    info "Memulai instalasi Farm Server..."

    # ------------------------------------------------------------------
    # 1. Install dan konfigurasi File Server (NFS)
    # ------------------------------------------------------------------
    info "Menginstal File Server di $fs_ip ..."
    local fs_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
echo "Installing NFS server..."
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y nfs-kernel-server
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y nfs-utils
    \$SUDO systemctl enable nfs-server
    \$SUDO systemctl start nfs-server
else
    echo "Unsupported OS"
    exit 1
fi
# Buat direktori share
mkdir -p /srv/nfs/shared
chown nobody:nogroup /srv/nfs/shared
chmod 755 /srv/nfs/shared
# Konfigurasi exports (untuk web1 dan web2)
cat <<EOT | \$SUDO tee /etc/exports
/srv/nfs/shared $web1_ip(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/shared $web2_ip(rw,sync,no_subtree_check,no_root_squash)
EOT
\$SUDO exportfs -a
\$SUDO systemctl restart nfs-server 2>/dev/null || \$SUDO systemctl restart nfs-kernel-server
echo "NFS server configured. Shared directory: /srv/nfs/shared"
EOF
)
    run_script_on_server "$fs_ip" "$fs_script"
    echo "File Server selesai."

    # ------------------------------------------------------------------
    # 2. Install Database Server
    # ------------------------------------------------------------------
    info "Menginstal Database Server di $db_ip ($DB_TYPE) ..."
    local db_script
    if [[ "$DB_TYPE" == "mariadb" ]]; then
        db_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y mariadb-server mariadb-client
    \$SUDO systemctl enable mariadb
    \$SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y mariadb-server mariadb
    \$SUDO systemctl enable mariadb
    \$SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
# Set root password dan secure (opsional, bisa diatur manual)
# Buat database dan user untuk aplikasi (contoh)
mysql -e "CREATE DATABASE IF NOT EXISTS appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'securepassword';"
mysql -e "GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';"
mysql -e "FLUSH PRIVILEGES;"
# Ubah bind-address agar bisa diakses dari web server
\$SUDO sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null || \$SUDO sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/my.cnf
\$SUDO systemctl restart mariadb
echo "MariaDB installed and configured. Database: appdb, User: appuser"
EOF
)
    else
        db_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y postgresql postgresql-contrib
    \$SUDO systemctl enable postgresql
    \$SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y postgresql-server postgresql-contrib
    \$SUDO postgresql-setup initdb
    \$SUDO systemctl enable postgresql
    \$SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
# Ubah konfigurasi agar bisa diakses dari web server
\$SUDO sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf 2>/dev/null || \$SUDO sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
# Tambahkan rule di pg_hba.conf untuk web server
echo "host    all             all             $web1_ip/32            md5" | \$SUDO tee -a /var/lib/pgsql/data/pg_hba.conf 2>/dev/null || echo "host    all             all             $web1_ip/32            md5" | \$SUDO tee -a /etc/postgresql/*/main/pg_hba.conf
echo "host    all             all             $web2_ip/32            md5" | \$SUDO tee -a /var/lib/pgsql/data/pg_hba.conf 2>/dev/null || echo "host    all             all             $web2_ip/32            md5" | \$SUDO tee -a /etc/postgresql/*/main/pg_hba.conf
\$SUDO systemctl restart postgresql
# Buat user dan database
sudo -u postgres psql -c "CREATE USER appuser WITH PASSWORD 'securepassword';"
sudo -u postgres psql -c "CREATE DATABASE appdb OWNER appuser;"
echo "PostgreSQL installed and configured. Database: appdb, User: appuser"
EOF
)
    fi
    run_script_on_server "$db_ip" "$db_script"
    echo "Database Server selesai."

    # ------------------------------------------------------------------
    # 3. Install Web Server 1 & 2 (Nginx + PHP-FPM) + mount NFS
    # ------------------------------------------------------------------
    for web_server in "$web1_ip" "$web2_ip"; do
        info "Menginstal Web Server di $web_server ..."
        local web_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
# Install Nginx + PHP-FPM
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    \$SUDO systemctl enable nginx php-fpm
    \$SUDO systemctl start nginx php-fpm
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y epel-release
    \$SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    \$SUDO systemctl enable nginx php-fpm
    \$SUDO systemctl start nginx php-fpm
else
    echo "Unsupported OS"
    exit 1
fi
# Mount NFS dari fileserver
mkdir -p /var/www/html
# Tambahkan ke fstab agar mount otomatis
echo "$fs_ip:/srv/nfs/shared /var/www/html nfs defaults 0 0" | \$SUDO tee -a /etc/fstab
\$SUDO mount -a
# Konfigurasi Nginx virtual host sederhana
cat <<EOT | \$SUDO tee /etc/nginx/sites-available/default 2>/dev/null || \$SUDO tee /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php*-fpm.sock 2>/dev/null || fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOT
# Aktifkan site jika Debian/Ubuntu
if [ -f /etc/nginx/sites-available/default ]; then
    \$SUDO ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
fi
# Buat file test
echo "<?php phpinfo(); ?>" | \$SUDO tee /var/www/html/info.php
# Restart nginx
\$SUDO systemctl restart nginx
echo "Web server installed. NFS mounted at /var/www/html"
EOF
)
        run_script_on_server "$web_server" "$web_script"
        echo "Web Server $web_server selesai."
    done

    # ------------------------------------------------------------------
    # 4. Install Load Balancer (HAProxy)
    # ------------------------------------------------------------------
    info "Menginstal Load Balancer di $lb_ip ..."
    local lb_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y haproxy
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y haproxy
else
    echo "Unsupported OS"
    exit 1
fi
# Konfigurasi HAProxy
cat <<EOT | \$SUDO tee /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy

defaults
    log global
    mode http
    option httplog
    option dontlognull
    retries 3
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend http-in
    bind *:80
    default_backend web_servers

backend web_servers
    balance roundrobin
    server web1 $web1_ip:80 check
    server web2 $web2_ip:80 check
EOT
\$SUDO systemctl enable haproxy
\$SUDO systemctl restart haproxy
echo "HAProxy installed and configured. Load balancing to $web1_ip and $web2_ip"
EOF
)
    run_script_on_server "$lb_ip" "$lb_script"
    echo "Load Balancer selesai."

    echo "========================================="
    echo "INSTALASI FARM SERVER SELESAI!"
    echo "Ringkasan:"
    echo "  - Load Balancer : $lb_ip (akses via http)"
    echo "  - Web Server 1  : $web1_ip"
    echo "  - Web Server 2  : $web2_ip"
    echo "  - Database      : $db_ip ($DB_TYPE)"
    echo "  - File Server   : $fs_ip (NFS share: /srv/nfs/shared)"
    echo ""
    echo "Langkah selanjutnya:"
    echo "  1. Upload aplikasi web ke /var/www/html di web server (melalui NFS)."
    echo "  2. Sesuaikan konfigurasi database di aplikasi (host=$db_ip, user=appuser, password=securepassword, db=appdb)."
    echo "  3. Uji akses melalui Load Balancer."
    echo "  4. Jangan lupa mengganti password default dan mengamankan konfigurasi."
}

