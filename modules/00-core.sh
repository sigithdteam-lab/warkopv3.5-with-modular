# ============================================================
# Multi-server SSH Key & Connection Management Script V-3.5
# Supports multiple OS (Debian/Ubuntu, RHEL/CentOS, etc.)
# Copyright (C) 2026 sigithdteam-lab
# GNU General Public License v3.0
# Versi dioptimalkan: caching, paralelisasi, perbaikan performa,
# penanganan sudo otomatis berdasarkan deteksi user root.
# ============================================================

# Configuration
SERVER_LIST="${SERVER_LIST:-$BASE_DIR/listserver.txt}"
SSH_DIR="${WARKOP_SSH_DIR:-$HOME/.ssh}"
KNOWN_HOSTS="$SSH_DIR/known_hosts"
WARKOP_LOG_DIR="${WARKOP_LOG_DIR:-$BASE_DIR/logs}"
WARKOP_LOCK_FILE="${WARKOP_LOCK_FILE:-$BASE_DIR/.warkop.lock}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"
SSH_SERVER_ALIVE_INTERVAL="${SSH_SERVER_ALIVE_INTERVAL:-15}"
SSH_SERVER_ALIVE_COUNT_MAX="${SSH_SERVER_ALIVE_COUNT_MAX:-2}"
SSH_RETRIES="${SSH_RETRIES:-2}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Global cache
SERVERS_CACHED=()
SERVERS_LOADED=false
SELECTED_INDICES=()

# ----------------------------------------------------------------------
# Helper Functions
# ----------------------------------------------------------------------

info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_package_manager() {
    if command_exists apt-get; then echo "apt-get"
    elif command_exists dnf; then echo "dnf"
    elif command_exists yum; then echo "yum"
    elif command_exists zypper; then echo "zypper"
    else echo "unknown"; fi
}

run_privileged_local() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"
    elif command_exists sudo; then sudo "$@"
    else error "Root privileges or sudo are required: $*"; return 1; fi
}

package_for_command() {
    case "$1" in
        ssh|ssh-keygen|ssh-copy-id) echo openssh-client ;;
        dig|nslookup) echo dnsutils ;;
        traceroute) echo traceroute ;;
        netstat) echo net-tools ;;
        whois) echo whois ;;
        nmap) echo nmap ;;
        *) echo "$1" ;;
    esac
}

install_package_if_missing() {
    local cmd="$1" pkg pm
    command_exists "$cmd" && return 0
    pkg="$(package_for_command "$cmd")"
    warn "Command '$cmd' not found. Package: $pkg"
    read -r -p "Do you want to install it now? (y/N): " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { warn "Skipping installation."; return 1; }
    pm="$(detect_package_manager)"
    case "$pm" in
        apt-get) run_privileged_local apt-get update && run_privileged_local apt-get install -y "$pkg" ;;
        dnf) run_privileged_local dnf install -y "$pkg" ;;
        yum) run_privileged_local yum install -y "$pkg" ;;
        zypper) run_privileged_local zypper install -y "$pkg" ;;
        *) error "Unsupported package manager. Install '$pkg' manually."; return 1 ;;
    esac
    command_exists "$cmd"
}

install_package_local() { install_package_if_missing "$1"; }

ensure_base_packages() {
    local missing=0
    install_package_if_missing ssh || ((missing++))
    install_package_if_missing ssh-keygen || ((missing++))
    install_package_if_missing ssh-copy-id || ((missing++))
    return "$missing"
}

confirm_action() {
    local msg="$1"
    echo -n "$msg (y/N): "
    read -r ans
    case "$ans" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

warkop_log() {
    mkdir -p "$WARKOP_LOG_DIR" 2>/dev/null || true
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$WARKOP_LOG_DIR/warkop.log" 2>/dev/null || true
}

acquire_warkop_lock() {
    if command_exists flock; then
        exec 9>"$WARKOP_LOCK_FILE"
        flock -n 9 || { error "Warkop is already running."; return 1; }
    fi
}

_build_ssh_args() {
    local server_str="$1" user host port
    read -r user host port <<< "$(parse_server_string "$server_str")" || return 1
    SSH_BUILT_ARGS=(-o "ConnectTimeout=$SSH_CONNECT_TIMEOUT" -o "ServerAliveInterval=$SSH_SERVER_ALIVE_INTERVAL" -o "ServerAliveCountMax=$SSH_SERVER_ALIVE_COUNT_MAX" -p "$port")
    if [[ "$host" == *:* ]]; then
        SSH_BUILT_ARGS+=("${user:+$user@}[$host]")
    else
        SSH_BUILT_ARGS+=("${user:+$user@}$host")
    fi
}

run_ssh_with_retry() {
    local server_str="$1"; shift
    local attempt=1
    _build_ssh_args "$server_str" || return 1
    while (( attempt <= SSH_RETRIES )); do
        warkop_log "SSH attempt=$attempt server=$server_str"
        if ssh "${SSH_BUILT_ARGS[@]}" "$@"; then return 0; fi
        ((attempt++))
        (( attempt <= SSH_RETRIES )) && sleep 1
    done
    return 1
}

run_script_on_server() {
    local server_str="$1" script="$2"
    run_ssh_with_retry "$server_str" "bash -s" <<< "$script"
}

# ----------------------------------------------------------------------
# Server String Parsing & SSH Wrappers (optimized)
# ----------------------------------------------------------------------

parse_server_string() {
    local server_str="$1"
    local user="" host="" port="22" host_port=""

    server_str="${server_str//$'\r'/}"
    server_str="${server_str##+([[:space:]])}"
    server_str="${server_str%%+([[:space:]])}"

    if [[ "$server_str" == *"@"* ]]; then
        user="${server_str%%@*}"
        host_port="${server_str#*@}"
    else
        host_port="$server_str"
    fi

    # IPv6 in bracket notation: [2001:db8::10]:2222
    # Also supports user@[2001:db8::10]:2222.
    if [[ "$host_port" =~ ^\[([^]]+)\](:([0-9]+))?$ ]]; then
        host="${BASH_REMATCH[1]}"
        [[ -n "${BASH_REMATCH[3]}" ]] && port="${BASH_REMATCH[3]}"
    elif [[ "$host_port" =~ ^([^:]+):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif [[ "$host_port" == *:* ]]; then
        # Bare IPv6 defaults to port 22.
        host="$host_port"
    else
        host="$host_port"
    fi

    if [[ -z "$host" || ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]]; then
        return 1
    fi

    printf '%s %s %s\n' "$user" "$host" "$port"
}

ssh_to_server() {
    local server_str="$1" cmd="$2"; shift 2
    _build_ssh_args "$server_str" || return 1
    if [[ -z "$cmd" ]]; then run_ssh_with_retry "$server_str" "$@"; else run_ssh_with_retry "$server_str" "$cmd" "$@"; fi
}

run_remote_script() {
    local server_str="$1" script="$2"
    local prelude=""
    if declare -F warkop_remote_os_prelude >/dev/null 2>&1; then
        prelude="$(warkop_remote_os_prelude)"
    fi
    run_ssh_with_retry "$server_str" "bash -s" <<< "${prelude}
${script}"
}

run_remote_script_sudo() {
    local server_str="$1"
    local script="$2"
    # Kita tidak membungkus dengan sudo di luar, tetapi kita tambahkan deteksi di dalam skrip
    # Jadi kita panggil run_remote_script biasa, tapi skrip sudah mengandung logika sudo
    run_remote_script "$server_str" "$script"
}

ssh_copy_id_to_server() {
    local server_str="$1"
    _build_ssh_args "$server_str" || return 1
    ssh-copy-id "${SSH_BUILT_ARGS[@]}"
}

get_host_from_server() {
    local server_str="$1"
    local user host port
    read user host port <<< $(parse_server_string "$server_str")
    echo "$host"
}

# ----------------------------------------------------------------------
# Server List Management (with caching)
# ----------------------------------------------------------------------

read_servers() {
    if [[ "$SERVERS_LOADED" == "true" ]]; then
        return 0
    fi
    if [[ ! -f "$SERVER_LIST" ]]; then
        touch "$SERVER_LIST"
        info "Created empty server list: $SERVER_LIST"
    fi
    mapfile -t SERVERS_CACHED < <(grep -v '^[[:space:]]*$' "$SERVER_LIST" | grep -v '^[[:space:]]*#' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    SERVERS_LOADED=true
}

refresh_servers() {
    SERVERS_LOADED=false
    read_servers
}

display_servers() {
    if [[ ${#SERVERS_CACHED[@]} -eq 0 ]]; then
        echo "No servers in list."
        return 1
    fi
    echo "Available servers:"
    for i in "${!SERVERS_CACHED[@]}"; do
        echo "  $((i+1))) ${SERVERS_CACHED[$i]}"
    done
    return 0
}

select_servers() {
    SELECTED_INDICES=()
    if [[ ${#SERVERS_CACHED[@]} -eq 0 ]]; then
        warn "No servers available."
        return 1
    fi
    display_servers
    echo "Enter server numbers (e.g., 1,2,3 or 1-3 or 'all'): "
    read -r selection
    selection=$(echo "$selection" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$selection" ]]; then
        warn "No input provided."
        return 1
    fi
    if [[ "$selection" == "all" ]]; then
        for i in "${!SERVERS_CACHED[@]}"; do
            SELECTED_INDICES+=("$((i+1))")
        done
    else
        IFS=',' read -ra parts <<< "$selection"
        for part in "${parts[@]}"; do
            part=$(echo "$part" | tr -d '[:space:]')
            if [[ "$part" =~ ^[0-9]+$ ]]; then
                SELECTED_INDICES+=("$part")
            elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start="${BASH_REMATCH[1]}"
                end="${BASH_REMATCH[2]}"
                if (( start <= end )); then
                    for ((i=start; i<=end; i++)); do
                        SELECTED_INDICES+=("$i")
                    done
                else
                    warn "Invalid range: $part (start > end)"
                fi
            else
                warn "Invalid selection: $part"
            fi
        done
    fi
    if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
        warn "No servers selected."
        return 1
    fi
    local sorted_unique=()
    while IFS= read -r num; do
        sorted_unique+=("$num")
    done < <(printf '%s\n' "${SELECTED_INDICES[@]}" | sort -nu)
    SELECTED_INDICES=("${sorted_unique[@]}")
    local max=${#SERVERS_CACHED[@]}
    local valid=()
    for idx in "${SELECTED_INDICES[@]}"; do
        if (( idx >= 1 && idx <= max )); then
            valid+=("$idx")
        else
            warn "Index $idx out of range (1..$max)"
        fi
    done
    SELECTED_INDICES=("${valid[@]}")
    if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
        warn "No valid servers selected."
        return 1
    fi
    return 0
}

get_server_by_index() {
    local idx=$1
    if (( idx >= 1 && idx <= ${#SERVERS_CACHED[@]} )); then
        echo "${SERVERS_CACHED[$((idx-1))]}"
    else
        echo ""
    fi
}

# ----------------------------------------------------------------------
# Parallel execution helper (optional, set PARALLEL=true to enable)
# ----------------------------------------------------------------------

PARALLEL=${PARALLEL:-false}

run_action_on_servers() {
    local script="$1"
    local task_name="$2"
    read_servers
    if ! select_servers; then return; fi

    local pids=()
    if [[ "$PARALLEL" == "true" ]]; then
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            (
                info "Running $task_name on $server ..."
                echo "----------------------------------------"
                run_remote_script "$server" "$script"
                echo "----------------------------------------"
            ) &
            pids+=($!)
        done
        wait "${pids[@]}"
    else
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            info "Running $task_name on $server ..."
            echo "----------------------------------------"
            run_remote_script "$server" "$script"
            echo "----------------------------------------"
        done
    fi
}

run_action_on_servers_sudo() {
    local script="$1"
    local task_name="$2"
    read_servers
    if ! select_servers; then return; fi

    local pids=()
    if [[ "$PARALLEL" == "true" ]]; then
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            (
                info "Running $task_name on $server (with sudo if needed) ..."
                echo "----------------------------------------"
                run_remote_script "$server" "$script"
                echo "----------------------------------------"
            ) &
            pids+=($!)
        done
        wait "${pids[@]}"
    else
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            info "Running $task_name on $server (with sudo if needed) ..."
            echo "----------------------------------------"
            run_remote_script "$server" "$script"
            echo "----------------------------------------"
        done
    fi
}

run_info_command() {
    local cmd="$1"
    local desc="$2"
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "$desc on $server"
        echo "----------------------------------------"
        ssh_to_server "$server" "$cmd" 2>&1
        echo "----------------------------------------"
    done
}

run_info_command_sudo() {
    local cmd="$1"
    local desc="$2"
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "$desc on $server (may require sudo)"
        echo "----------------------------------------"
        # Kita jalankan dengan bash -c agar deteksi sudo terjadi
        ssh_to_server "$server" "bash -c 'if [ \$(id -u) -eq 0 ]; then SUDO=\"\"; else SUDO=\"sudo\"; fi; \$SUDO $cmd'" 2>&1
        echo "----------------------------------------"
    done
}

# ======================================================================
# 1. SSH Key Management
# ======================================================================

