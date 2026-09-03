run_mail_command() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

mail_check_mx() {
    read -p "Enter domain to check MX record (e.g., example.com): " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo (tidak diperlukan untuk dig/nslookup, tapi kita sertakan)
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

if command -v dig >/dev/null 2>&1; then
    dig $domain MX +short
elif command -v nslookup >/dev/null 2>&1; then
    nslookup -type=MX $domain 2>/dev/null | grep 'mail exchanger'
else
    echo "Neither dig nor nslookup found. Please install dnsutils."
    exit 1
fi
EOF
)
    run_mail_command "$script" "Check MX record for $domain"
}

mail_check_ptr() {
    read -p "Enter IP address to check PTR: " ip
    if [[ -z "$ip" ]]; then
        error "IP required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
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

if command -v dig >/dev/null 2>&1; then
    dig -x $ip +short
elif command -v nslookup >/dev/null 2>&1; then
    nslookup $ip 2>/dev/null | grep 'name ='
else
    echo "Neither dig nor nslookup found."
    exit 1
fi
EOF
)
    run_mail_command "$script" "Check PTR record for $ip"
}

mail_dkim() {
    read -p "Enter domain for DKIM: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    read -p "Enter selector (default: default): " selector
    [[ -z "$selector" ]] && selector="default"
    local script=$(cat <<EOF
#!/bin/bash
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

if command -v opendkim-genkey >/dev/null 2>&1; then
    if [ -f /etc/opendkim/keys/$domain/$selector.txt ]; then
        echo "DKIM key already exists for $domain (selector $selector):"
        cat /etc/opendkim/keys/$domain/$selector.txt
        echo "---"
        echo "Do you want to regenerate? (y/N): "
        read -r ans
        if [[ ! \$ans =~ ^[Yy]$ ]]; then
            echo "Skipping regeneration."
            exit 0
        fi
    fi
    echo "Generating DKIM key for $domain with selector $selector ..."
    mkdir -p /etc/opendkim/keys/$domain
    opendkim-genkey -D /etc/opendkim/keys/$domain -d $domain -s $selector
    chown opendkim:opendkim /etc/opendkim/keys/$domain/*
    echo "DKIM key generated:"
    cat /etc/opendkim/keys/$domain/$selector.txt
    echo "---"
    echo "Add this TXT record to your DNS."
elif command -v rspamadm >/dev/null 2>&1; then
    echo "Using rspamd to generate DKIM key..."
    rspamadm dkim_keygen -d $domain -s $selector
else
    echo "No DKIM generation tool found. Please install opendkim-tools or rspamd."
    echo "Try: apt-get install opendkim-tools (Debian) or yum install opendkim-tools (RHEL)"
    exit 1
fi
EOF
)
    run_mail_command "$script" "DKIM check/generate for $domain"
}

mail_spf() {
    read -p "Enter domain for SPF: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
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

if command -v dig >/dev/null 2>&1; then
    current=\$(dig $domain TXT +short | grep -i 'v=spf1')
    if [ -n "\$current" ]; then
        echo "Current SPF record:"
        echo "\$current"
    else
        echo "No SPF record found."
    fi
    echo "---"
    echo "Recommended SPF record (adjust IPs/mail servers):"
    echo "v=spf1 mx ~all"
    echo "Or more specific: v=spf1 ip4:YOUR_IP include:spf.example.com ~all"
    echo "You can add this as a TXT record for domain $domain."
else
    echo "dig not found."
fi
EOF
)
    run_mail_command "$script" "SPF check/generate for $domain"
}

mail_dmarc() {
    read -p "Enter domain for DMARC: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
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

if command -v dig >/dev/null 2>&1; then
    current=\$(dig _dmarc.$domain TXT +short | grep -i 'v=DMARC1')
    if [ -n "\$current" ]; then
        echo "Current DMARC record:"
        echo "\$current"
    else
        echo "No DMARC record found."
    fi
    echo "---"
    echo "Recommended DMARC record (adjust policy):"
    echo "v=DMARC1; p=none; rua=mailto:dmarc-reports@$domain; ruf=mailto:dmarc-forensic@$domain; sp=none"
    echo "You can add this as a TXT record for _dmarc.$domain."
else
    echo "dig not found."
fi
EOF
)
    run_mail_command "$script" "DMARC check/generate for $domain"
}

mail_menu() {
    while true; do
        echo
        echo "===== Mailserver Management ====="
        echo "1. Check MX record"
        echo "2. Check PTR record (reverse DNS)"
        echo "3. Check DKIM key & generate (if missing)"
        echo "4. Check SPF key & generate (if missing)"
        echo "5. Check DMARC key & generate (if missing)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) mail_check_mx ;;
            2) mail_check_ptr ;;
            3) mail_dkim ;;
            4) mail_spf ;;
            5) mail_dmarc ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# 9. Network Tools (Local)
# ======================================================================

