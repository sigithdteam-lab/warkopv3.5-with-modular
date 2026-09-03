run_user_command() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

user_list() {
    local script=$(cat <<'EOF'
#!/bin/bash
if [ -f /etc/debian_version ]; then
    echo "Human users (uid>=1000):"
    getent passwd | awk -F: '$3>=1000 {print $1}' | sort
    echo "--- System users (uid<1000) ---"
    getent passwd | awk -F: '$3<1000 {print $1}' | head -20
else
    echo "Human users (uid>=1000):"
    getent passwd | awk -F: '$3>=1000 {print $1}' | sort
    echo "--- System users (uid<1000) ---"
    getent passwd | awk -F: '$3<1000 {print $1}' | head -20
fi
EOF
)
    run_user_command "$script" "User list"
}

user_add() {
    read -p "Enter username to add: " username
    if [[ -z "$username" || ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        error "Invalid username. Use lowercase letters, numbers, _ or - (max 32 chars)."
        return
    fi
    read -s -p "Enter password for $username: " password
    echo
    read -s -p "Confirm password: " password2
    echo
    if [[ "$password" != "$password2" ]]; then
        error "Passwords do not match."
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

if id "$username" &>/dev/null; then
    echo "User $username already exists."
    exit 1
fi
if [ -f /etc/debian_version ]; then
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
else
    useradd -m -s /bin/bash "$username"
    echo "$password" | passwd --stdin "$username"
fi
if [ $? -eq 0 ]; then
    echo "User $username created successfully."
else
    echo "Failed to create user $username."
    exit 1
fi
EOF
)
    password_b64="$(printf %s "$password" | base64 | tr -d "\n")"
    script="${script//\$password/$password_b64}"
    script="${script//\$username/$username}"
    run_user_command "$script" "Add user $username"
}

user_delete() {
    read -p "Enter username to delete: " username
    if [[ -z "$username" ]]; then
        error "Username cannot be empty."
        return
    fi
    read -p "Remove home directory? (y/N): " remove_home
    local home_flag=""
    if [[ $remove_home =~ ^[Yy]$ ]]; then
        home_flag="-r"
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

if ! id "$username" &>/dev/null; then
    echo "User $username does not exist."
    exit 1
fi
userdel $home_flag "$username"
if [ $? -eq 0 ]; then
    echo "User $username deleted successfully."
else
    echo "Failed to delete user $username."
    exit 1
fi
EOF
)
    script=$(echo "$script" | sed "s/\$username/$username/g")
    run_user_command "$script" "Delete user $username"
}

user_change_password() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Fetching user list from $server ..."
        ssh_to_server "$server" "getent passwd | awk -F: '\$3>=1000 {print \$1}' | sort" 2>/dev/null
        echo "----------------------------------------"
    done
    read -p "Enter username to change password: " username
    if [[ -z "$username" ]]; then
        error "Username cannot be empty."
        return
    fi
    read -s -p "Enter current password (press Enter to skip): " oldpass
    echo
    read -s -p "Enter new password: " newpass1
    echo
    read -s -p "Confirm new password: " newpass2
    echo
    if [[ "$newpass1" != "$newpass2" ]]; then
        error "Passwords do not match."
        return
    fi
    if [[ -z "$newpass1" ]]; then
        error "Password cannot be empty."
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

if ! id "$username" &>/dev/null; then
    echo "User $username does not exist."
    exit 1
fi
echo "$username:$newpass" | chpasswd
if [ $? -eq 0 ]; then
    echo "Password for $username changed successfully."
else
    echo "Failed to change password for $username."
    exit 1
fi
EOF
)
    newpass_b64="$(printf %s "$newpass1" | base64 | tr -d "\n")"
    script="${script//\$newpass/$newpass_b64}"
    script="${script//\$username/$username}"
    run_user_command "$script" "Change password for $username"
}

# ======================================================================
# 6. Security Management (with sudo -i)
# ======================================================================

