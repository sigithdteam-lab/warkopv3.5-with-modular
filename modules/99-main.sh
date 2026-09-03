instalasi_server_menu() {
    while true; do
        echo
        echo "===== Instalasi Server Management ====="
        echo "1. Install Web Server Apache + PHP"
        echo "2. Install Web Server Nginx + PHP"
        echo "3. Install Database MariaDB"
        echo "4. Install Database PostgreSQL"
        echo "5. Install Apache + PHP + MariaDB (LAMP)"
        echo "6. Install Apache + PHP + PostgreSQL (LAPP)"
        echo "7. Install Nginx + PHP + MariaDB (LEMP)"
        echo "8. Install Nginx + PHP + PostgreSQL (LEPP)"
        echo "9. Auto Tuning Apache2"
        echo "10. Auto Tuning Nginx"
        echo "11. Auto Tuning MariaDB/PostgreSQL"
        echo "12. Tampilkan Rekomendasi Terbaik"
        echo "13. Instalasi Farm Server (Load Balancer/HA)"
        echo "0. Kembali ke Menu Utama"
        echo -n "Pilih opsi: "
        read -r choice
        case $choice in
            1) install_apache_php ;;
            2) install_nginx_php ;;
            3) install_mariadb ;;
            4) install_postgresql ;;
            5) install_lamp ;;
            6) install_lapp ;;
            7) install_lemp ;;
            8) install_lepp ;;
            9) auto_tune_apache ;;
            10) auto_tune_nginx ;;
            11) auto_tune_db ;;
            12) show_recommendations ;;
            13) install_farm_server ;;
            0) break ;;
            *) warn "Pilihan tidak valid." ;;
        esac
    done
}

# ======================================================================
# Main Menu
# ======================================================================

main_menu() {
    while true; do
        echo
        echo "============ Main Menu  ============"
        echo "======== ManageServer V-3.5 ========"
        echo "1. SSH Key Management"
        echo "2. SSH Management"
        echo "3. Server Maintainer"
        echo "4. Server Information"
        echo "5. User Management"
        echo "6. Security Management"
        echo "7. Service Server Management"
        echo "8. Mailserver Management"
        echo "9. Network Tools"
        echo "10. APNIC Tools"
        echo "11. Server Management"
        echo "12. Instalasi Server Management"
        echo "13. Exit"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) ssh_key_management_menu ;;
            2) ssh_management_menu ;;
            3) server_maintainer_menu ;;
            4) server_information_menu ;;
            5) user_management_menu ;;
            6) security_management_menu ;;
            7) service_management_menu ;;
            8) mail_menu ;;
            9) network_tools_menu ;;
            10) apnic_tools_menu ;;
            11) server_management_menu ;;
            12) instalasi_server_menu ;;
            13) echo "Bye!"; exit 0 ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ----------------------------------------------------------------------
# Initialization
# ----------------------------------------------------------------------

initialize_warkop() {
    acquire_warkop_lock || exit 1
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    ensure_base_packages || warn "Some packages missing."
    read_servers
}

main() {
    initialize_warkop
    main_menu
}
