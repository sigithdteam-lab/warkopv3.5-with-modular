# ======================================================================
# OS Detection & Command Abstraction
# ======================================================================

# Local OS profile. Remote scripts use the same logic through
# warkop_remote_os_prelude().
detect_local_os() {
    local id="unknown" version="" name="" family="unknown"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-unknown}"
        version="${VERSION_ID:-}"
        name="${PRETTY_NAME:-${NAME:-$id}}"
    fi
    case "$id" in
        ubuntu|debian|linuxmint|pop|raspbian|kali) family="debian" ;;
        rhel|centos|rocky|almalinux|fedora|ol|amzn|amazon) family="rhel" ;;
        opensuse*|sles|suse) family="suse" ;;
        alpine) family="alpine" ;;
        arch|manjaro|endeavouros) family="arch" ;;
        *) family="unknown" ;;
    esac
    OS_ID="$id"
    OS_VERSION="$version"
    OS_NAME="$name"
    OS_FAMILY="$family"
    export OS_ID OS_VERSION OS_NAME OS_FAMILY
}

local_pkg_manager() {
    detect_local_os >/dev/null
    case "$OS_FAMILY" in
        debian) echo apt-get ;;
        rhel) if command_exists dnf; then echo dnf; else echo yum; fi ;;
        suse) echo zypper ;;
        alpine) echo apk ;;
        arch) echo pacman ;;
        *) echo unknown ;;
    esac
}

local_service_manager() {
    if command_exists systemctl; then echo systemd
    elif command_exists rc-service; then echo openrc
    elif command_exists service; then echo sysv
    else echo unknown
    fi
}

show_os_command_profile() {
    # This menu is executed on the machine running Warkop (controller).
    # When Warkop is launched from Git Bash/MSYS on Windows, /etc/os-release
    # may not exist, so use uname as a fallback instead of reporting "unknown".
    local kernel="$(uname -s 2>/dev/null || printf 'unknown')"
    local machine="$(uname -m 2>/dev/null || printf 'unknown')"

    detect_local_os

    if [[ "$OS_FAMILY" == "unknown" ]]; then
        case "$kernel" in
            MINGW*|MSYS*|CYGWIN*)
                OS_ID="windows"
                OS_NAME="Windows (Git Bash/MSYS/Cygwin)"
                OS_VERSION="$(cmd.exe /c ver 2>/dev/null | tr -d '\r' | sed 's/^.*\[Version /Version /; s/\]$//' || true)"
                OS_FAMILY="windows"
                ;;
            Darwin*)
                OS_ID="macos"
                OS_NAME="macOS"
                OS_VERSION="$(sw_vers -productVersion 2>/dev/null || true)"
                OS_FAMILY="macos"
                ;;
            *)
                : # Keep detect_local_os result.
                ;;
        esac
    fi

    local pkg="$(local_pkg_manager)"
    local init="$(local_service_manager)"

    echo
    echo "===== Warkop OS & Command Profile ====="
    printf 'Controller OS : %s\n' "$OS_NAME"
    printf 'OS ID         : %s\n' "$OS_ID"
    printf 'OS Version    : %s\n' "${OS_VERSION:-unknown}"
    printf 'OS Family     : %s\n' "$OS_FAMILY"
    printf 'Kernel        : %s\n' "$kernel"
    printf 'Architecture  : %s\n' "$machine"
    printf 'Package Mgr   : %s\n' "$pkg"
    printf 'Service Mgr   : %s\n' "$init"

    if [[ "$OS_FAMILY" == "windows" ]]; then
        echo
        echo "[INFO] Warkop is running from Windows shell."
        echo "[INFO] OS-specific server commands are detected on the REMOTE Linux server."
        echo "[INFO] Use SSH/server operations to apply apt/dnf/yum/apk/pacman/zypper commands remotely."
    fi
}

show_local_os_profile() {
    detect_local_os
    printf 'OS       : %s\n' "$OS_NAME"
    printf 'ID       : %s\n' "$OS_ID"
    printf 'Version  : %s\n' "${OS_VERSION:-unknown}"
    printf 'Family   : %s\n' "$OS_FAMILY"
    printf 'Package  : %s\n' "$(local_pkg_manager)"
    printf 'Service  : %s\n' "$(local_service_manager)"
}

# Emit a portable shell prelude. It is prepended to every script sent to a
# remote server, so all remote operations have a consistent OS profile.
warkop_remote_os_prelude() {
    cat <<'REMOTE_OS_PRELUDE'
# ---- Warkop OS adapter (v3.5) ----
set -o pipefail

warkop_detect_os() {
    OS_ID=unknown OS_VERSION= OS_NAME= OS_FAMILY=unknown
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-}"
        OS_NAME="${PRETTY_NAME:-${NAME:-$OS_ID}}"
    fi
    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop|raspbian|kali) OS_FAMILY=debian ;;
        rhel|centos|rocky|almalinux|fedora|ol|amzn|amazon) OS_FAMILY=rhel ;;
        opensuse*|sles|suse) OS_FAMILY=suse ;;
        alpine) OS_FAMILY=alpine ;;
        arch|manjaro|endeavouros) OS_FAMILY=arch ;;
        *) OS_FAMILY=unknown ;;
    esac
    export OS_ID OS_VERSION OS_NAME OS_FAMILY
}

warkop_sudo() {
    if [ "$(id -u)" -eq 0 ]; then printf ''
    elif command -v sudo >/dev/null 2>&1; then printf 'sudo'
    else return 1
    fi
}

warkop_pkg_manager() {
    case "$OS_FAMILY" in
        debian) echo apt-get ;;
        rhel) command -v dnf >/dev/null 2>&1 && echo dnf || echo yum ;;
        suse) echo zypper ;;
        alpine) echo apk ;;
        arch) echo pacman ;;
        *) echo unknown ;;
    esac
}

warkop_pkg_update() {
    case "$(warkop_pkg_manager)" in
        apt-get) $(warkop_sudo) apt-get update ;;
        dnf) $(warkop_sudo) dnf makecache ;;
        yum) $(warkop_sudo) yum makecache ;;
        zypper) $(warkop_sudo) zypper refresh ;;
        apk) $(warkop_sudo) apk update ;;
        pacman) $(warkop_sudo) pacman -Sy --noconfirm ;;
        *) echo "Unsupported OS: $OS_NAME" >&2; return 1 ;;
    esac
}

warkop_pkg_upgrade() {
    case "$(warkop_pkg_manager)" in
        apt-get) $(warkop_sudo) apt-get upgrade -y ;;
        dnf) $(warkop_sudo) dnf upgrade -y ;;
        yum) $(warkop_sudo) yum update -y ;;
        zypper) $(warkop_sudo) zypper update -y ;;
        apk) $(warkop_sudo) apk upgrade ;;
        pacman) $(warkop_sudo) pacman -Syu --noconfirm ;;
        *) echo "Unsupported OS: $OS_NAME" >&2; return 1 ;;
    esac
}

warkop_pkg_clean() {
    case "$(warkop_pkg_manager)" in
        apt-get) $(warkop_sudo) apt-get clean; $(warkop_sudo) apt-get autoclean ;;
        dnf) $(warkop_sudo) dnf clean all ;;
        yum) $(warkop_sudo) yum clean all ;;
        zypper) $(warkop_sudo) zypper clean --all ;;
        apk) $(warkop_sudo) apk cache clean 2>/dev/null || true ;;
        pacman) $(warkop_sudo) pacman -Sc --noconfirm ;;
        *) return 1 ;;
    esac
}

warkop_pkg_install() {
    case "$(warkop_pkg_manager)" in
        apt-get) $(warkop_sudo) apt-get install -y "$@" ;;
        dnf) $(warkop_sudo) dnf install -y "$@" ;;
        yum) $(warkop_sudo) yum install -y "$@" ;;
        zypper) $(warkop_sudo) zypper install -y "$@" ;;
        apk) $(warkop_sudo) apk add "$@" ;;
        pacman) $(warkop_sudo) pacman -S --noconfirm "$@" ;;
        *) return 1 ;;
    esac
}

warkop_service() {
    local action="$1"; shift
    if command -v systemctl >/dev/null 2>&1; then
        $(warkop_sudo) systemctl "$action" "$@"
    elif command -v rc-service >/dev/null 2>&1; then
        case "$action" in start) rc-service "$1" start ;; stop) rc-service "$1" stop ;; restart) rc-service "$1" restart ;; status) rc-service "$1" status ;; *) return 2 ;; esac
    elif command -v service >/dev/null 2>&1; then
        $(warkop_sudo) service "$@"
    else
        return 127
    fi
}

warkop_service_enable() {
    local svc="$1"
    if command -v systemctl >/dev/null 2>&1; then
        $(warkop_sudo) systemctl enable "$svc"
    elif command -v rc-update >/dev/null 2>&1; then
        $(warkop_sudo) rc-update add "$svc" default
    else
        echo "Service enable is not supported by this init system: $svc" >&2
        return 1
    fi
}

warkop_service_active() {
    local svc="$1"
    if command -v systemctl >/dev/null 2>&1; then systemctl is-active --quiet "$svc"
    elif command -v rc-service >/dev/null 2>&1; then rc-service "$svc" status >/dev/null 2>&1
    else service "$svc" status >/dev/null 2>&1
    fi
}

warkop_detect_webserver() {
    if command -v nginx >/dev/null 2>&1; then echo nginx
    elif command -v apache2 >/dev/null 2>&1; then echo apache2
    elif command -v httpd >/dev/null 2>&1; then echo httpd
    else echo none
    fi
}

warkop_detect_php_fpm_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-unit-files --type=service 2>/dev/null | awk '/php([0-9.]+-)?fpm\.service/{print $1; exit}'
    fi
}

warkop_detect_database() {
    if command -v mariadb >/dev/null 2>&1; then echo mariadb
    elif command -v mysql >/dev/null 2>&1; then echo mysql
    elif command -v psql >/dev/null 2>&1; then echo postgresql
    else echo none
    fi
}

warkop_firewall() {
    if command -v ufw >/dev/null 2>&1; then echo ufw
    elif command -v firewall-cmd >/dev/null 2>&1; then echo firewalld
    elif command -v nft >/dev/null 2>&1; then echo nftables
    elif command -v iptables >/dev/null 2>&1; then echo iptables
    else echo none
    fi
}

warkop_detect_os
if command -v systemctl >/dev/null 2>&1; then
    WARKOP_INIT=systemd
elif command -v rc-service >/dev/null 2>&1; then
    WARKOP_INIT=openrc
elif command -v service >/dev/null 2>&1; then
    WARKOP_INIT=sysv
else
    WARKOP_INIT=unknown
fi
printf '[WARKOP-OS] %s | id=%s | version=%s | family=%s | package=%s | init=%s | firewall=%s\n' \
  "$OS_NAME" "$OS_ID" "${OS_VERSION:-unknown}" "$OS_FAMILY" "$(warkop_pkg_manager)" \
  "$WARKOP_INIT" "$(warkop_firewall)"
# ---- End Warkop OS adapter ----
REMOTE_OS_PRELUDE
}
