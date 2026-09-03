run_security_command_sudo() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

sec_firewall_status() {
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

if command -v ufw >/dev/null 2>&1; then
    if systemctl is-active --quiet ufw; then
        echo "UFW is running."
    else
        echo "UFW is installed but not running (or inactive)."
    fi
    $SUDO ufw status verbose 2>/dev/null || echo "UFW status: could not retrieve."
elif command -v firewall-cmd >/dev/null 2>&1; then
    if systemctl is-active --quiet firewalld; then
        echo "firewalld is running."
        $SUDO firewall-cmd --state 2>/dev/null || echo "firewalld state unknown."
    else
        echo "firewalld is installed but not running."
    fi
else
    echo "No known firewall (UFW or firewalld) found."
fi
EOF
)
    run_security_command_sudo "$script" "Firewall status"
}

sec_firewall_service() {
    echo "Select action:"
    echo "1) Start firewall"
    echo "2) Stop firewall"
    echo "3) Restart firewall"
    read -p "Choose (1-3): " action
    local cmd=""
    case $action in
        1) cmd="start" ;;
        2) cmd="stop" ;;
        3) cmd="restart" ;;
        *) warn "Invalid choice."; return ;;
    esac
    local script=$(cat <<EOF
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

if command -v ufw >/dev/null 2>&1; then
    echo "Using UFW..."
    \$SUDO systemctl $cmd ufw
    if [ \$? -eq 0 ]; then
        echo "UFW $cmd successful."
    else
        echo "UFW $cmd failed."
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo "Using firewalld..."
    \$SUDO systemctl $cmd firewalld
    if [ \$? -eq 0 ]; then
        echo "firewalld $cmd successful."
    else
        echo "firewalld $cmd failed."
    fi
else
    echo "No known firewall found."
fi
EOF
)
    run_security_command_sudo "$script" "Firewall $cmd"
}

sec_firewall_add_rule() {
    echo "Select rule type:"
    echo "1) Allow port (TCP/UDP)"
    echo "2) Drop IP"
    echo "3) Reject IP"
    read -p "Choose (1-3): " rule_type
    case $rule_type in
        1)
            read -p "Enter port number: " port
            read -p "Protocol (tcp/udp): " proto
            if [[ -z "$port" || -z "$proto" ]]; then
                error "Port and protocol required."
                return
            fi
            local script=$(cat <<EOF
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

if command -v ufw >/dev/null 2>&1; then
    \$SUDO ufw allow $port/$proto
    if [ \$? -eq 0 ]; then
        echo "UFW rule added: allow $port/$proto"
    else
        echo "Failed to add UFW rule."
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    \$SUDO firewall-cmd --add-port=$port/$proto --permanent
    if [ \$? -eq 0 ]; then
        \$SUDO firewall-cmd --reload
        echo "firewalld rule added: allow $port/$proto (permanent)"
    else
        echo "Failed to add firewalld rule."
    fi
else
    echo "No known firewall found."
fi
EOF
)
            run_security_command_sudo "$script" "Allow port $port/$proto"
            ;;
        2|3)
            read -p "Enter IP address: " ip
            if [[ -z "$ip" ]]; then
                error "IP address required."
                return
            fi
            local action_word=$([ $rule_type -eq 2 ] && echo "drop" || echo "reject")
            local script=$(cat <<EOF
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

if command -v ufw >/dev/null 2>&1; then
    \$SUDO ufw $action_word from $ip
    if [ \$? -eq 0 ]; then
        echo "UFW rule added: $action_word from $ip"
    else
        echo "Failed to add UFW rule."
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    \$SUDO firewall-cmd --direct --add-rule ipv4 filter INPUT 0 -s $ip -j $action_word
    if [ \$? -eq 0 ]; then
        \$SUDO firewall-cmd --direct --add-rule ipv6 filter INPUT 0 -s $ip -j $action_word 2>/dev/null
        \$SUDO firewall-cmd --runtime-to-permanent
        echo "firewalld rule added: $action_word from $ip (direct)"
    else
        echo "Failed to add firewalld rule."
    fi
else
    echo "No known firewall found."
fi
EOF
)
            run_security_command_sudo "$script" "$action_word IP $ip"
            ;;
        *) warn "Invalid choice."; return ;;
    esac
}

sec_virus_scan() {
    read -p "Enter folder path to scan (default /home): " folder
    [[ -z "$folder" ]] && folder="/home"
    local scan_script=$(cat <<EOF
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

if ! command -v clamscan >/dev/null 2>&1; then
    echo "clamscan not found. Installing..."
    if [ -f /etc/debian_version ]; then
        \$SUDO apt-get update && \$SUDO apt-get install -y clamav clamav-daemon
    elif [ -f /etc/redhat-release ]; then
        \$SUDO yum install -y epel-release && \$SUDO yum install -y clamav clamav-update
    else
        echo "Unsupported OS. Cannot install clamav automatically."
        exit 1
    fi
    if command -v freshclam >/dev/null 2>&1; then
        \$SUDO freshclam
    fi
fi
if command -v clamscan >/dev/null 2>&1; then
    echo "Starting virus scan on $folder (this may take a while)..."
    \$SUDO clamscan -r --bell -i "$folder" 2>&1
    echo "Scan completed."
else
    echo "clamscan still not available. Aborting scan."
    exit 1
fi
EOF
)
    scan_script=$(echo "$scan_script" | sed "s|\$folder|$folder|g")
    run_security_command_sudo "$scan_script" "Virus scan on $folder"
}

sec_failed_logins() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo (untuk lastb)
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

echo "Recent failed login attempts (last 20):"
$SUDO lastb -n 20 2>/dev/null || echo "lastb command not available or permission denied."
echo "---"
echo "Failed SSH authentication attempts from /var/log/auth.log (last 10):"
if [ -f /var/log/auth.log ]; then
    grep "Failed password" /var/log/auth.log | tail -10
elif [ -f /var/log/secure ]; then
    grep "Failed password" /var/log/secure | tail -10
else
    echo "No auth log found."
fi
EOF
)
    run_security_command_sudo "$script" "Check failed logins"
}

sec_open_ports() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo (untuk netstat/ss)
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

echo "Listening ports and associated services:"
$SUDO ss -tulpn | grep LISTEN 2>/dev/null || $SUDO netstat -tulpn | grep LISTEN 2>/dev/null || echo "ss/netstat not available."
EOF
)
    run_security_command_sudo "$script" "Check open ports"
}

# ----------------------------------------------------------------------
# SSL Certificate Management
# ----------------------------------------------------------------------

sec_ssl_install_certbot() {
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

if command -v certbot >/dev/null 2>&1; then
    echo "Certbot already installed: $(certbot --version 2>/dev/null)"
    return 0
fi
echo "Certbot not found. Installing..."
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y certbot python3-certbot-nginx python3-certbot-apache
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y certbot python3-certbot-nginx python3-certbot-apache
elif [ -f /etc/SuSE-release ]; then
    $SUDO zypper install -y certbot python3-certbot-nginx python3-certbot-apache
else
    echo "Unsupported OS. Please install certbot manually."
    exit 1
fi
if command -v certbot >/dev/null 2>&1; then
    echo "Certbot installed successfully."
else
    echo "Certbot installation failed."
    exit 1
fi
EOF
)
    run_security_command_sudo "$script" "Install Certbot (Let's Encrypt)"
}

sec_ssl_get_cert() {
    read -p "Enter domain name (e.g., example.com): " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    read -p "Enter email address for notifications: " email
    if [[ -z "$email" ]]; then
        error "Email required."
        return
    fi
    read -p "Choose web server type (nginx/apache/standalone) [nginx]: " webserver
    [[ -z "$webserver" ]] && webserver="nginx"
    local script=$(cat <<EOF
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

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed. Please install first (option 1)."
    exit 1
fi
if [ "$webserver" == "standalone" ]; then
    \$SUDO systemctl stop nginx 2>/dev/null || \$SUDO systemctl stop apache2 2>/dev/null || true
fi
echo "Obtaining certificate for $domain ..."
\$SUDO certbot certonly --$webserver -d $domain --non-interactive --agree-tos -m $email
if [ \$? -eq 0 ]; then
    echo "Certificate obtained successfully."
    echo "Files: /etc/letsencrypt/live/$domain/"
    if [ "$webserver" == "standalone" ]; then
        \$SUDO systemctl start nginx 2>/dev/null || \$SUDO systemctl start apache2 2>/dev/null || true
    fi
else
    echo "Failed to obtain certificate."
    exit 1
fi
EOF
)
    run_security_command_sudo "$script" "Get Let's Encrypt certificate for $domain"
}

sec_ssl_renew_cert() {
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

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed. Please install first."
    exit 1
fi
$SUDO certbot renew --quiet
if [ $? -eq 0 ]; then
    echo "Certificates renewed successfully (if any were due)."
else
    echo "Renewal failed or no certificates to renew."
fi
EOF
)
    run_security_command_sudo "$script" "Renew Let's Encrypt certificates"
}

sec_ssl_check_expiry() {
    read -p "Enter domain to check (or leave empty to check all): " domain
    local script
    if [[ -z "$domain" ]]; then
        script=$(cat <<'EOF'
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

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
$SUDO certbot certificates 2>/dev/null | grep -E "Domain:|Expiry Date:" || echo "No certificates found or certbot error."
EOF
)
    else
        script=$(cat <<EOF
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

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
\$SUDO certbot certificates 2>/dev/null | grep -A 10 "Domain: $domain" || echo "Certificate for $domain not found."
EOF
)
    fi
    run_security_command_sudo "$script" "Check certificate expiry"
}

sec_ssl_list_certs() {
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

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
$SUDO certbot certificates 2>/dev/null || echo "No certificates found."
EOF
)
    run_security_command_sudo "$script" "List all SSL certificates"
}

sec_ssl_auto_renew() {
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

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
(crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 0,12 * * * /usr/bin/certbot renew --quiet") | $SUDO crontab -
if [ $? -eq 0 ]; then
    echo "Cron job added for automatic renewal (twice daily)."
else
    echo "Failed to add cron job."
fi
EOF
)
    run_security_command_sudo "$script" "Setup auto-renewal (cron job)"
}

sec_ssl_menu() {
    while true; do
        echo
        echo "===== SSL Certificate Management (Let's Encrypt) ====="
        echo "1. Install Certbot (Let's Encrypt client)"
        echo "2. Get new certificate for domain"
        echo "3. Renew all certificates"
        echo "4. Check certificate expiry"
        echo "5. List all certificates"
        echo "6. Setup auto-renewal (cron job)"
        echo "0. Back to Security Management"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) sec_ssl_install_certbot ;;
            2) sec_ssl_get_cert ;;
            3) sec_ssl_renew_cert ;;
            4) sec_ssl_check_expiry ;;
            5) sec_ssl_list_certs ;;
            6) sec_ssl_auto_renew ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# 7. Service Management
# ======================================================================

