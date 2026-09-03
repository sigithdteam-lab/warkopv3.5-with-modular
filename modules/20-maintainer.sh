build_maintenance_script() {
    local action="$1"
    cat <<EOF
#!/bin/bash
echo "OS: \$OS_NAME (\$OS_ID \$OS_VERSION), family=\$OS_FAMILY, package=\$(warkop_pkg_manager)"
case "$action" in
  update) warkop_pkg_update ;;
  upgrade) warkop_pkg_upgrade ;;
  update_upgrade) warkop_pkg_update && warkop_pkg_upgrade ;;
  clean) warkop_pkg_clean ;;
  *) echo "Unknown maintenance action: $action" >&2; exit 2 ;;
esac
EOF
}

maintain_update() {
    local script=$(build_maintenance_script update)
    run_action_on_servers_sudo "$script" "Update package lists"
}

maintain_upgrade() {
    local script=$(build_maintenance_script upgrade)
    run_action_on_servers_sudo "$script" "Upgrade packages"
}

maintain_update_upgrade() {
    local script=$(build_maintenance_script update_upgrade)
    run_action_on_servers_sudo "$script" "Update & Upgrade"
}

# ======================================================================
# Clean cache & clear memory (gabungan)
# ======================================================================
maintain_clean_cache_memory() {
    local script=$(cat <<'EOF'
#!/bin/bash
echo "Cleaning package cache using: $(warkop_pkg_manager)"
warkop_pkg_clean || echo "Package cache cleanup is not supported on this OS."
if [ "$(id -u)" -eq 0 ]; then
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
elif command -v sudo >/dev/null 2>&1; then
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
fi
echo "Cache and memory cleanup completed."
EOF
)
    run_action_on_servers_sudo "$script" "Clean cache & clear memory"
}

# ======================================================================
# Clean logs – langsung jalankan pembersihan umum (tanpa pilihan)
# ======================================================================
maintain_clean_logs() {
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

echo "Cleaning system logs and archives..."

# Kumpulkan direktori yang akan dibersihkan
log_dirs=()
[ -d /var/log ] && log_dirs+=("/var/log")
[ -d /var/backups ] && log_dirs+=("/var/backups")
[ -d /usr/local/cpanel/logs ] && log_dirs+=("/usr/local/cpanel/logs")
for home_dir in /home/*; do
    [ -d "$home_dir/logs" ] && log_dirs+=("$home_dir/logs")
done

# Fungsi menghitung total ukuran (dalam bytes) dari semua direktori
get_total_size() {
    local sum=0
    for d in "${log_dirs[@]}"; do
        if [ -d "$d" ]; then
            size=$(du -sb "$d" 2>/dev/null | awk '{print $1}')
            sum=$((sum + size))
        fi
    done
    echo $sum
}

# Fungsi menghitung jumlah file .gz
count_gz_files() {
    local count=0
    for d in "${log_dirs[@]}"; do
        if [ -d "$d" ]; then
            c=$(find "$d" -type f -name "*.gz" 2>/dev/null | wc -l)
            count=$((count + c))
        fi
    done
    echo $count
}

# Catat ukuran dan jumlah file sebelum pembersihan
initial_size=$(get_total_size)
initial_gz=$(count_gz_files)

# --- Proses pembersihan ---
# 1. Hapus semua file .gz
for d in "${log_dirs[@]}"; do
    find "$d" -type f -name "*.gz" -delete 2>/dev/null
done

# 2. Kosongkan file log (*_log dan *.log)
for d in "${log_dirs[@]}"; do
    find "$d" -type f \( -name "*_log" -o -name "*.log" \) -exec truncate -s 0 {} + 2>/dev/null
done

# 3. Hapus file log lama (> 14 hari) di /var/log
find /var/log -name '*.log' -type f -mtime +14 -delete 2>/dev/null || true

# 4. Vacuum journal (batasi ukuran 100M) – butuh sudo
$SUDO journalctl --vacuum-size=100M 2>/dev/null || true

# --- Catat ukuran dan jumlah file setelah pembersihan ---
final_size=$(get_total_size)
final_gz=$(count_gz_files)

# Hitung selisih
freed=$((initial_size - final_size))
gz_removed=$((initial_gz - final_gz))

# Fungsi konversi byte ke format human-readable (jika numfmt tidak tersedia)
format_size() {
    local bytes=$1
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec "$bytes" 2>/dev/null || echo "${bytes} B"
    else
        if [ $bytes -ge 1073741824 ]; then
            echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
        elif [ $bytes -ge 1048576 ]; then
            echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
        elif [ $bytes -ge 1024 ]; then
            echo "$(echo "scale=2; $bytes/1024" | bc) KB"
        else
            echo "${bytes} B"
        fi
    fi
}

# Tampilkan ringkasan
echo "========================================="
echo "           CLEANUP SUMMARY"
echo "========================================="
echo "  Directories cleaned : ${#log_dirs[@]}"
echo "  .gz files removed   : $gz_removed"
echo "  Total space freed   : $(format_size $freed)"
echo "  Initial total size  : $(format_size $initial_size)"
echo "  Final total size    : $(format_size $final_size)"
echo "========================================="
EOF
)
    run_action_on_servers_sudo "$script" "Clean system logs"
}

maintain_repair_packages() {
    local script=$(build_maintenance_script \
        "sudo dpkg --configure -a; sudo apt --fix-broken install -y; sudo apt autoremove -y; sudo apt autoclean" \
        "sudo rpm --rebuilddb; sudo yum clean all; sudo package-cleanup --cleandupes 2>/dev/null || true; sudo yum-complete-transaction 2>/dev/null || true")
    run_action_on_servers_sudo "$script" "Repair package management"
}

maintain_pending_updates() {
    local script=$(build_maintenance_script \
        "sudo apt-get update 2>/dev/null; sudo apt-get --just-print upgrade | grep -E '^Inst' || echo 'No pending updates'" \
        "sudo yum check-update | grep -E '^[a-zA-Z0-9]' || echo 'No pending updates'")
    run_action_on_servers_sudo "$script" "Check pending updates"
}

maintain_check_reboot() {
    local script=$(cat <<'EOF'
#!/bin/bash
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required (Debian/Ubuntu)."
elif [ -f /boot/grub/grub.conf ] && [ -f /var/run/reboot-required ]; then
    echo "Reboot required (RHEL)."
else
    echo "No reboot pending."
fi
if [ -f /proc/version ] && [ -f /boot/vmlinuz-* ]; then
    current=$(uname -r)
    latest=$(ls -t /boot/vmlinuz-* | head -1 | sed 's/.*vmlinuz-//')
    if [ "$current" != "$latest" ]; then
        echo "A newer kernel is installed, reboot may be needed to use it."
    fi
fi
EOF
)
    run_action_on_servers "$script" "Check pending reboot"
}

# ======================================================================
# 4. Server Information
# ======================================================================

# Fungsi untuk menampilkan informasi server menggunakan tecmint_monitor style
