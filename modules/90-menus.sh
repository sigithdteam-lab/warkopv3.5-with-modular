ssh_key_management_menu() {
    while true; do
        echo
        echo "===== SSH Key Management ====="
        echo "1. Add new server + import SSH key"
        echo "2. Test Passwordless SSH"
        echo "3. Import Public Key (to remote server)"
        echo "4. Generate SSH Key (local)"
        echo "5. Repair SSH Key (local & known_hosts)"
        echo "6. Remove SSH Key (from remote server)"
        echo "7. Regenerate SSH Key"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) add_new_server ;;
            2) test_passwordless ;;
            3) import_public_key ;;
            4) generate_ssh_key ;;
            5) repair_ssh_key ;;
            6) remove_ssh_key ;;
            7) regenerate_ssh_key ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

ssh_management_menu() {
    while true; do
        echo
        echo "===== SSH Management ====="
        echo "1. Remote SSH (manual input)"
        echo "2. Remote SSH (from server list)"
        echo "3. Change IP address (network configuration)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) remote_ssh_manual ;;
            2) remote_ssh_from_list ;;
            3) change_ip ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

server_maintainer_menu() {
    while true; do
        echo
        echo "===== Server Maintainer ====="
        echo "1. Update package lists"
        echo "2. Upgrade packages"
        echo "3. Update & Upgrade"
        echo "4. Clean cache & clear memory"
        echo "5. Clean system logs"
        echo "6. Repair package management"
        echo "7. Check pending updates"
        echo "8. Check pending reboot"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) maintain_update ;;
            2) maintain_upgrade ;;
            3) maintain_update_upgrade ;;
            4) maintain_clean_cache_memory ;;
            5) maintain_clean_logs ;;
            6) maintain_repair_packages ;;
            7) maintain_pending_updates ;;
            8) maintain_check_reboot ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

server_information_menu() {
    while true; do
        echo
        echo "===== Server Information ====="
        echo "1. Info Server (Full System Monitor)"
        echo "2. Detect OS & command profile"
        echo "3. Check partition disk (fdisk)"
        echo "4. Check disk structure (lsblk)"
        echo "5. Check UUID & filesystem type (blkid)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) info_server ;;
            2) show_os_command_profile ;;
            3) info_partition_disk ;;
            4) info_disk_structure ;;
            5) info_uuid_fstype ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

user_management_menu() {
    while true; do
        echo
        echo "===== User Management ====="
        echo "1. User List"
        echo "2. Add new user"
        echo "3. Delete user"
        echo "4. Change user password"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) user_list ;;
            2) user_add ;;
            3) user_delete ;;
            4) user_change_password ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

security_management_menu() {
    while true; do
        echo
        echo "===== Security Management ====="
        echo "1. Firewall status"
        echo "2. Firewall service (start/stop/restart)"
        echo "3. Firewall add rule (allow port / drop/reject IP)"
        echo "4. Virus scan (folder scan)"
        echo "5. Check failed logins"
        echo "6. Check open ports"
        echo "7. SSL Certificate Management (Let's Encrypt)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) sec_firewall_status ;;
            2) sec_firewall_service ;;
            3) sec_firewall_add_rule ;;
            4) sec_virus_scan ;;
            5) sec_failed_logins ;;
            6) sec_open_ports ;;
            7) sec_ssl_menu ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

service_management_menu() {
    while true; do
        echo
        echo "===== Service Server Management ====="
        echo "1. Service status"
        echo "2. Service stop (stop running service)"
        echo "3. Service start (start stopped service)"
        echo "4. Service restart"
        echo "5. Auto service start (start if down)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) service_status ;;
            2) service_stop ;;
            3) service_start ;;
            4) service_restart ;;
            5) service_auto_start ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# Server Management (Tuning & Repair)
# ======================================================================

server_management_menu() {
    while true; do
        echo
        echo "===== Server Management ====="
        echo "1. Auto tuning webserver based on resource"
        echo "2. Auto tuning database based on resource"
        echo "3. Database repair / optimize"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) auto_tune_webserver ;;
            2) auto_tune_database ;;
            3) database_repair ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

