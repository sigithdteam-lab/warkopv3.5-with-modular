generate_ssh_key() {
    info "Generating SSH key pair locally..."
    if [[ -f "$SSH_DIR/id_rsa" ]]; then
        warn "Existing key found. Overwrite? (y/N): "
        read -r -n 1 ans
        echo
        if [[ ! $ans =~ ^[Yy]$ ]]; then
            info "Aborted."
            return
        fi
    fi
    ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/id_rsa" -N ""
    if [[ $? -eq 0 ]]; then
        info "SSH key generated."
    else
        error "Key generation failed."
    fi
}

import_public_key() {
    ensure_base_packages || return 1
    if [[ ! -f "$SSH_DIR/id_rsa.pub" ]]; then
        error "Local public key not found. Generate one first (option 4 in SSH Key Management)."
        return 1
    fi
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Copying public key to $server ..."
        ssh_copy_id_to_server "$server"
        if [[ $? -eq 0 ]]; then
            info "Key copied successfully to $server."
        else
            error "Failed to copy key to $server."
        fi
    done
}

test_passwordless() {
    ensure_base_packages || return 1
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Testing passwordless SSH to $server ..."
        ssh_to_server "$server" "echo 'OK'" -o BatchMode=yes -o ConnectTimeout=5
        if [[ $? -eq 0 ]]; then
            info "Passwordless SSH to $server: SUCCESS"
        else
            warn "Passwordless SSH to $server: FAILED"
        fi
    done
}

repair_ssh_key() {
    info "Repairing local SSH configuration..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    [[ -f "$SSH_DIR/id_rsa" ]] && chmod 600 "$SSH_DIR/id_rsa"
    [[ -f "$SSH_DIR/id_rsa.pub" ]] && chmod 644 "$SSH_DIR/id_rsa.pub"
    [[ -f "$KNOWN_HOSTS" ]] && chmod 644 "$KNOWN_HOSTS"
    info "Local SSH permissions repaired."
    read_servers
    if select_servers; then
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            local host=$(get_host_from_server "$server")
            if [[ -n "$host" ]]; then
                ssh-keygen -R "$host" 2>/dev/null
                info "Removed $host from known_hosts."
            fi
        done
    fi
}

remove_ssh_key() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Removing local public key from $server ..."
        if [[ ! -f "$SSH_DIR/id_rsa.pub" ]]; then
            error "Local public key not found."
            continue
        fi
        local pubkey=$(cat "$SSH_DIR/id_rsa.pub")
        local escaped_pubkey=$(printf '%s\n' "$pubkey" | sed -e 's/[\/&]/\\&/g')
        ssh_to_server "$server" "sed -i '/$escaped_pubkey/d' ~/.ssh/authorized_keys" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            info "Key removed from $server."
        else
            warn "Failed to remove key from $server."
        fi
    done
}

regenerate_ssh_key() {
    if [[ -f "$SSH_DIR/id_rsa" ]]; then
        warn "Existing key found. Delete and generate new? (y/N): "
        read -r -n 1 ans
        echo
        if [[ ! $ans =~ ^[Yy]$ ]]; then
            info "Aborted."
            return
        fi
        rm -f "$SSH_DIR/id_rsa" "$SSH_DIR/id_rsa.pub"
    fi
    generate_ssh_key
    echo "Do you want to copy the new key to remote servers? (y/N): "
    read -r -n 1 ans
    echo
    if [[ $ans =~ ^[Yy]$ ]]; then
        import_public_key
    fi
}

# ======================================================================
# 2. SSH Management
# ======================================================================

add_new_server() {
    ensure_base_packages || return 1
    echo "Enter new server details (format: user@host[:port] or host[:port]): "
    read -r new_server
    new_server=$(echo "$new_server" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$new_server" ]]; then
        error "No input provided."
        return
    fi
    read_servers
    for s in "${SERVERS_CACHED[@]}"; do
        if [[ "$s" == "$new_server" ]]; then
            warn "Server '$new_server' already exists in list."
            return
        fi
    done
    if [[ -s "$SERVER_LIST" ]] && [[ "$(tail -c1 "$SERVER_LIST")" != "" ]]; then
        echo "" >> "$SERVER_LIST"
    fi
    echo "$new_server" >> "$SERVER_LIST"
    refresh_servers
    info "Added server: $new_server"
    if [[ -f "$SSH_DIR/id_rsa.pub" ]]; then
        echo "Do you want to copy your public key to this server now? (Y/n): "
        read -r -n 1 ans
        echo
        if [[ ! $ans =~ ^[Nn]$ ]]; then
            ssh_copy_id_to_server "$new_server"
            if [[ $? -eq 0 ]]; then
                info "Key copied to $new_server."
            else
                error "Failed to copy key."
            fi
        fi
    else
        warn "No local public key found. Generate one first (option 4 in SSH Key Management)."
    fi
}

remote_ssh_manual() {
    echo "Enter server (format: user@host[:port] or host[:port]): "
    read -r server_input
    server_input=$(echo "$server_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$server_input" ]]; then
        error "No input."
        return
    fi
    ssh_to_server "$server_input"
}

remote_ssh_from_list() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Connecting to $server ..."
        ssh_to_server "$server"
        echo "--- Disconnected from $server ---"
    done
}

change_ip() {
    read_servers
    if ! select_servers; then return; fi

    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Current network configuration on $server:"
        ssh_to_server "$server" "ip addr show | grep -E 'inet ' | grep -v '127.0.0.1'; ip route | grep default; cat /etc/resolv.conf | grep nameserver" 2>/dev/null
        echo "----------------------------------------"
    done

    read -p "Enter new IP address (e.g., 192.168.1.100): " new_ip
    read -p "Enter new netmask (e.g., 255.255.255.0): " new_netmask
    read -p "Enter new gateway: " new_gateway
    read -p "Enter primary DNS (DNS1): " dns1
    read -p "Enter secondary DNS (DNS2): " dns2
    if [[ -z "$new_ip" || -z "$new_netmask" || -z "$new_gateway" ]]; then
        error "IP, netmask, and gateway are required."
        return
    fi

    warn "This will change the network configuration and may disconnect your SSH session."
    read -p "Are you sure you want to proceed? (y/N): " confirm
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

if [ -f /etc/debian_version ]; then
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$IFACE" ]; then
        IFACE=$(ip addr show | grep -E '^[0-9]+: ' | grep -v lo | awk -F': ' '{print $2}' | head -1)
    fi
    echo "Using interface: $IFACE"
    $SUDO cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)
    $SUDO tee /etc/network/interfaces <<EOL
auto lo
iface lo inet loopback
auto $IFACE
iface $IFACE inet static
    address $new_ip
    netmask $new_netmask
    gateway $new_gateway
    dns-nameservers $dns1 $dns2
EOL
    $SUDO systemctl restart networking || $SUDO service networking restart
elif [ -f /etc/redhat-release ] || [ -f /etc/SuSE-release ]; then
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$IFACE" ]; then
        IFACE=$(ip addr show | grep -E '^[0-9]+: ' | grep -v lo | awk -F': ' '{print $2}' | head -1)
    fi
    echo "Using interface: $IFACE"
    $SUDO cp /etc/sysconfig/network-scripts/ifcfg-$IFACE /etc/sysconfig/network-scripts/ifcfg-$IFACE.bak.$(date +%Y%m%d%H%M%S)
    $SUDO tee /etc/sysconfig/network-scripts/ifcfg-$IFACE <<EOL
DEVICE=$IFACE
BOOTPROTO=none
ONBOOT=yes
IPADDR=$new_ip
NETMASK=$new_netmask
GATEWAY=$new_gateway
DNS1=$dns1
DNS2=$dns2
EOL
    $SUDO systemctl restart network || $SUDO service network restart
else
    echo "Unsupported OS for automatic network configuration."
    exit 1
fi
echo "nameserver $dns1" | $SUDO tee /etc/resolv.conf
echo "nameserver $dns2" | $SUDO tee -a /etc/resolv.conf
echo "Network configuration updated."
EOF
)
    # Ganti variabel di dalam skrip
    script=$(echo "$script" | sed "s/\$new_ip/$new_ip/g; s/\$new_netmask/$new_netmask/g; s/\$new_gateway/$new_gateway/g; s/\$dns1/$dns1/g; s/\$dns2/$dns2/g")

    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Applying new IP configuration on $server ..."
        run_remote_script "$server" "$script"
        echo "----------------------------------------"
    done
}

# ======================================================================
# 3. Server Maintainer Functions (with sudo -i for root actions)
# ======================================================================

