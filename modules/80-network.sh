run_local_net_tool() {
    local cmd="$1"
    local args="$2"
    local desc="$3"
    if ! install_package_local "$cmd"; then
        warn "Skipping $desc"
        return 1
    fi
    echo "--- $desc ---"
    read -r -a _net_args <<< "$args"; "$cmd" "${_net_args[@]}"
    echo "--- Done ---"
}

net_ping_subnet() {
    read -p "Enter subnet (e.g., 192.168.1.0/24): " subnet
    if [[ -z "$subnet" ]]; then
        error "Subnet required."
        return
    fi
    if ! install_package_local "nmap"; then
        warn "nmap required for ping subnet scan."
        return
    fi
    echo "Scanning subnet $subnet (ping sweep)..."
    sudo nmap -sn "$subnet" | grep -E "Nmap scan|Host" | grep -v "Host is up" 2>/dev/null || \
    nmap -sn "$subnet" | grep -E "Nmap scan|Host" | grep -v "Host is up"
}

net_traceroute() {
    read -p "Enter destination (IP or domain): " dest
    if [[ -z "$dest" ]]; then
        error "Destination required."
        return
    fi
    run_local_net_tool "traceroute" "$dest" "Traceroute to $dest"
}

net_dig() {
    read -p "Enter domain to dig: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    run_local_net_tool "dig" "$domain any" "Dig $domain (ANY)"
}

net_nslookup() {
    read -p "Enter domain/IP to nslookup: " target
    if [[ -z "$target" ]]; then
        error "Target required."
        return
    fi
    run_local_net_tool "nslookup" "$target" "nslookup $target"
}

net_netstat() {
    run_local_net_tool "netstat" "-tulpn" "Netstat listening ports"
}

net_mx_check() {
    read -p "Enter domain to check MX: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    run_local_net_tool "dig" "$domain MX +short" "MX record for $domain"
}

net_ptr_check() {
    read -p "Enter IP to check PTR: " ip
    if [[ -z "$ip" ]]; then
        error "IP required."
        return
    fi
    run_local_net_tool "dig" "-x $ip +short" "PTR record for $ip"
}

net_nslookup_interactive() {
    run_local_net_tool "nslookup" "" "nslookup (interactive - enter commands, Ctrl+D to exit)"
}

net_whois() {
    read -p "Enter IP or domain to whois: " target
    if [[ -z "$target" ]]; then
        error "Target required."
        return
    fi
    run_local_net_tool "whois" "$target" "whois $target"
}

network_tools_menu() {
    while true; do
        echo
        echo "===== Network Tools (Local) ====="
        echo " 1. Ping subnet (nmap ping sweep)"
        echo " 2. Traceroute"
        echo " 3. dig (DNS lookup)"
        echo " 4. nslookup"
        echo " 5. netstat (listening ports)"
        echo " 6. MX check (dig MX)"
        echo " 7. PTR check (reverse DNS)"
        echo " 8. nslookup (interactive)"
        echo " 9. whois IP/domain"
        echo " 0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) net_ping_subnet ;;
            2) net_traceroute ;;
            3) net_dig ;;
            4) net_nslookup ;;
            5) net_netstat ;;
            6) net_mx_check ;;
            7) net_ptr_check ;;
            8) net_nslookup_interactive ;;
            9) net_whois ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# 10. APNIC Tools (Local)
# ======================================================================

apnic_install_packages() {
    install_package_local "whois"
    install_package_local "dig"
}

apnic_prefix_whois() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    [[ -z "$prefix" ]] && { error "Prefix required."; return; }
    apnic_install_packages
    echo "--- Prefix Whois for $prefix ---"
    whois -h whois.apnic.net "$prefix" 2>/dev/null || whois "$prefix"
}

apnic_route_object() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    [[ -z "$prefix" ]] && { error "Prefix required."; return; }
    apnic_install_packages
    echo "--- Route Object for $prefix (from RADB) ---"
    whois -h whois.radb.net "$prefix" 2>/dev/null || echo "No route object found or RADB unreachable."
}

apnic_roa() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    [[ -z "$prefix" ]] && { error "Prefix required."; return; }
    apnic_install_packages
    echo "--- ROA for $prefix (via RPKI) ---"
    if command -v rpki-client >/dev/null 2>&1; then
        rpki-client -s "$prefix" 2>/dev/null || echo "No ROA data or rpki-client error."
    else
        warn "rpki-client not installed. Attempting to install..."
        sudo apt-get update && sudo apt-get install -y rpki-client 2>/dev/null || sudo yum install -y rpki-client 2>/dev/null
        if command -v rpki-client >/dev/null 2>&1; then
            rpki-client -s "$prefix" 2>/dev/null || echo "No ROA data."
        else
            echo "Cannot install rpki-client. Using whois --show-roa (limited)."
            whois -h whois.apnic.net --show-roa "$prefix" 2>/dev/null || echo "No ROA found via whois."
        fi
    fi
}

apnic_asn_info() {
    read -p "Enter AS number (e.g., 13335): " asn
    [[ -z "$asn" ]] && { error "AS number required."; return; }
    apnic_install_packages
    echo "--- ASN Info for AS$asn ---"
    whois -h whois.apnic.net "AS$asn" 2>/dev/null || whois "AS$asn"
}

apnic_rpki_validation() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    read -p "Enter AS number (e.g., 13335): " asn
    [[ -z "$prefix" || -z "$asn" ]] && { error "Prefix and ASN required."; return; }
    echo "--- RPKI Validation for $prefix with AS$asn ---"
    if command -v rpki-client >/dev/null 2>&1; then
        rpki-client -s "$prefix" -a "$asn" 2>/dev/null || echo "Validation failed or no data."
    else
        warn "rpki-client not installed. Trying to install..."
        sudo apt-get update && sudo apt-get install -y rpki-client 2>/dev/null || sudo yum install -y rpki-client 2>/dev/null
        if command -v rpki-client >/dev/null 2>&1; then
            rpki-client -s "$prefix" -a "$asn" 2>/dev/null || echo "Validation failed or no data."
        else
            echo "rpki-client unavailable. Using whois --show-roa to check ROA."
            whois -h whois.apnic.net --show-roa "$prefix" 2>/dev/null | grep -i "$asn" || echo "No ROA found for this ASN/prefix."
        fi
    fi
}

apnic_asn_validation() {
    read -p "Enter AS number (e.g., 13335): " asn
    [[ -z "$asn" ]] && { error "AS number required."; return; }
    apnic_install_packages
    echo "--- ASN Validation for AS$asn ---"
    whois -h whois.apnic.net "AS$asn" 2>/dev/null | grep -i "aut-num" && echo "✓ ASN exists (valid)." || echo "✗ ASN not found or invalid."
}

apnic_ipv6() {
    read -p "Enter IPv6 address (e.g., 2001:db8::1): " ipv6
    [[ -z "$ipv6" ]] && { error "IPv6 address required."; return; }
    apnic_install_packages
    echo "--- IPv6 Info for $ipv6 ---"
    whois -h whois.apnic.net "$ipv6" 2>/dev/null || whois "$ipv6"
}

apnic_tools_menu() {
    while true; do
        echo
        echo "===== APNIC Tools (Local) ====="
        echo "1. Prefix Whois"
        echo "2. Route Object"
        echo "3. ROA (RPKI)"
        echo "4. AS Number Info"
        echo "5. RPKI Validation (prefix + ASN)"
        echo "6. AS Number Validation"
        echo "7. IPv6 Whois"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) apnic_prefix_whois ;;
            2) apnic_route_object ;;
            3) apnic_roa ;;
            4) apnic_asn_info ;;
            5) apnic_rpki_validation ;;
            6) apnic_asn_validation ;;
            7) apnic_ipv6 ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# Menus
# ======================================================================

