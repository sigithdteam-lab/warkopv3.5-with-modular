show_server_info() {
    local server="$1"
    info "System Information for $server"
    echo "----------------------------------------"
    ssh_to_server "$server" "bash -s" <<'EOF'
#!/bin/bash
# =============================================================================
# System Monitor Script (Remote) - Enhanced Version
# =============================================================================

set -euo pipefail 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Check if running as root
# -----------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Warning: Some information may require root privileges${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Display Date/Time
# -----------------------------------------------------------------------------
show_datetime() {
    echo -e "${CYAN}▶ Date/Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
}

# -----------------------------------------------------------------------------
# Check internet connection
# -----------------------------------------------------------------------------
check_internet() {
    echo -e "${CYAN}▶ Internet Status:${NC}"
    if ping -c 1 google.com &>/dev/null || ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "  ${GREEN}✓ Connected${NC}"
    else
        echo -e "  ${RED}✗ Disconnected${NC}"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Display OS information
# -----------------------------------------------------------------------------
show_os_info() {
    echo -e "${CYAN}▶ Operating System:${NC}"
    
    # OS Type
    os_type=$(uname -o 2>/dev/null || echo "Unknown")
    echo -e "  ${BOLD}Type:${NC} $os_type"
    
    # OS Name and Version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release 2>/dev/null || true
        echo -e "  ${BOLD}Name:${NC} ${NAME:-Unknown}"
        echo -e "  ${BOLD}Version:${NC} ${VERSION:-Unknown}"
    elif [[ -f /etc/redhat-release ]]; then
        echo -e "  ${BOLD}Name:${NC} $(cat /etc/redhat-release)"
    else
        echo -e "  ${YELLOW}Name: Could not determine${NC}"
    fi
    
    # Architecture
    arch=$(uname -m)
    echo -e "  ${BOLD}Architecture:${NC} $arch"
    
    # Kernel
    kernel=$(uname -r)
    echo -e "  ${BOLD}Kernel:${NC} $kernel"
    
    # Hostname
    hostname=$(hostname 2>/dev/null || echo "Unknown")
    echo -e "  ${BOLD}Hostname:${NC} $hostname"
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display network information
# -----------------------------------------------------------------------------

show_os_command_profile() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server="${SERVERS_CACHED[$idx]}"
        info "OS/command profile: $server"
        run_remote_script "$server" "printf 'OS=%s\nID=%s\nVERSION=%s\nFAMILY=%s\nPACKAGE_MANAGER=%s\nWEB=%s\nDB=%s\nFIREWALL=%s\n' "\$OS_NAME" "\$OS_ID" "\${OS_VERSION:-unknown}" "\$OS_FAMILY" "\$(warkop_pkg_manager)" "\$(warkop_detect_webserver)" "\$(warkop_detect_database)" "\$(warkop_firewall)""
    done
}

show_network() {
    echo -e "${CYAN}▶ Network Information:${NC}"
    
    # Internal IP
    internal_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -n "$internal_ip" ]]; then
        echo -e "  ${BOLD}Internal IP:${NC} $internal_ip"
    else
        echo -e "  ${YELLOW}Internal IP: Not available${NC}"
    fi
    
    # DNS Servers
    if [[ -f /etc/resolv.conf ]]; then
        dns=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
        echo -e "  ${BOLD}DNS Servers:${NC} ${dns:-Not configured}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display logged in users
# -----------------------------------------------------------------------------
show_users() {
    echo -e "${CYAN}▶ Logged In Users:${NC}"
    if command -v who &>/dev/null; then
        who | while read -r line; do
            echo "  $line"
        done
    else
        echo "  ${YELLOW}Command 'who' not available${NC}"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Display memory usage
# -----------------------------------------------------------------------------
show_memory() {
    echo -e "${CYAN}▶ Memory Usage:${NC}"
    
    if command -v free &>/dev/null; then
        # RAM
        echo -e "  ${BOLD}RAM:${NC}"
        free -h | grep -E '^Mem:' | while read -r line; do
            total=$(echo "$line" | awk '{print $2}')
            used=$(echo "$line" | awk '{print $3}')
            free=$(echo "$line" | awk '{print $4}')
            available=$(echo "$line" | awk '{print $7}')
            echo -e "    Total: ${GREEN}$total${NC} | Used: ${YELLOW}$used${NC} | Free: ${BLUE}$free${NC} | Available: ${GREEN}$available${NC}"
        done
        
        # Swap
        echo -e "  ${BOLD}Swap:${NC}"
        free -h | grep -E '^Swap:' | while read -r line; do
            total=$(echo "$line" | awk '{print $2}')
            used=$(echo "$line" | awk '{print $3}')
            free=$(echo "$line" | awk '{print $4}')
            echo -e "    Total: ${GREEN}$total${NC} | Used: ${YELLOW}$used${NC} | Free: ${BLUE}$free${NC}"
        done
    else
        echo -e "  ${YELLOW}Memory info not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display disk usage
# -----------------------------------------------------------------------------
show_disk() {
    echo -e "${CYAN}▶ Disk Usage:${NC}"
    
    if command -v df &>/dev/null; then
        df -h | grep -E '^(Filesystem|/dev/)' | while read -r line; do
            if [[ "$line" == Filesystem* ]]; then
                echo "  $line"
            else
                # Ekstrak persentase penggunaan
                usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
                # Tentukan warna berdasarkan persentase
                if [[ $usage -gt 90 ]]; then
                    color="$RED"
                elif [[ $usage -gt 75 ]]; then
                    color="$YELLOW"
                else
                    color="$GREEN"
                fi
                # Tampilkan baris dengan warna pada persentase saja
                # Gunakan awk untuk membangun ulang baris dengan warna
                size=$(echo "$line" | awk '{print $2}')
                used=$(echo "$line" | awk '{print $3}')
                avail=$(echo "$line" | awk '{print $4}')
                mount=$(echo "$line" | awk '{print $6}')
                echo -e "  $size  $used  $avail  ${color}${usage}%${NC}  $mount"
            fi
        done
    else
        echo -e "  ${YELLOW}Disk info not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display load average
# -----------------------------------------------------------------------------
show_load() {
    echo -e "${CYAN}▶ Load Average:${NC}"
    
    if command -v uptime &>/dev/null; then
        load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')
        echo "  $load"
        
        # Interpret load
        cpu_cores=$(nproc 2>/dev/null || echo 1)
        load_1min=$(echo "$load" | awk '{print $1}' | sed 's/,//')
        if command -v bc &>/dev/null && (( $(echo "$load_1min > $cpu_cores" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "  ${YELLOW}⚠️  Load is high (${cpu_cores} cores available)${NC}"
        else
            echo -e "  ${GREEN}✓ Load is normal${NC}"
        fi
    else
        echo -e "  ${YELLOW}Load average not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display uptime
# -----------------------------------------------------------------------------
show_uptime() {
    echo -e "${CYAN}▶ System Uptime:${NC}"
    
    if command -v uptime &>/dev/null; then
        uptime -p 2>/dev/null || uptime | awk '{print $3,$4,$5}' | sed 's/,//'
    else
        echo -e "  ${YELLOW}Uptime not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display top processes
# -----------------------------------------------------------------------------
show_processes() {
    echo -e "${CYAN}▶ Top 5 CPU Processes:${NC}"
    
    if command -v ps &>/dev/null; then
        ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | while read -r line; do
            cpu=$(echo "$line" | awk '{print $3}')
            mem=$(echo "$line" | awk '{print $4}')
            cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-50)
            echo -e "  CPU: ${GREEN}${cpu}%${NC} MEM: ${BLUE}${mem}%${NC} CMD: ${cmd}"
        done
    else
        echo -e "  ${YELLOW}Process info not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display service status
# -----------------------------------------------------------------------------
show_services() {
    echo -e "${CYAN}▶ Critical Services:${NC}"
    
    services=("nginx" "apache2" "httpd" "mysql" "mysqld" "php-fpm" "redis" "ssh" "docker")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        elif systemctl is-active --quiet "$service.service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        elif pgrep -x "$service" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        fi
    done
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display last logins
# -----------------------------------------------------------------------------
show_last_logins() {
    echo -e "${CYAN}▶ Recent Logins (last 5):${NC}"
    
    if command -v last &>/dev/null; then
        last -n 5 2>/dev/null | head -5 | while read -r line; do
            echo "  $line"
        done
    else
        echo -e "  ${YELLOW}Login history not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Main function
# -----------------------------------------------------------------------------
main() {
    check_root
    show_datetime
    check_internet
    show_os_info
    show_network
    show_users
    show_memory
    show_disk
    show_load
    show_uptime
    show_processes
    show_services
    show_last_logins
}

main
EOF
    echo "----------------------------------------"
}

info_server() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        show_server_info "$server"
    done
}

info_partition_disk() {
    run_info_command_sudo "fdisk -l 2>/dev/null || echo 'fdisk not available or permission denied'" "Check partition disk"
}

info_disk_structure() {
    run_info_command "lsblk -f 2>/dev/null || echo 'lsblk not available'" "Check disk structure (filesystem)"
}

info_uuid_fstype() {
    run_info_command_sudo "blkid 2>/dev/null || echo 'blkid not available or permission denied'" "Check UUID & filesystem type"
}

# ======================================================================
# 5. User Management
# ======================================================================

