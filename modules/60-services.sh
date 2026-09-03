run_service_command() {
    local cmd="$1"
    local desc="$2"
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server="${SERVERS_CACHED[$idx]}"
        info "$desc on $server"
        run_remote_script "$server" "warkop_service $cmd || echo 'Service action failed or unsupported'" 2>&1
        echo "----------------------------------------"
    done
}

service_status() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Show all services? (y/n, default y): " show_all
    for idx in "${SELECTED_INDICES[@]}"; do
        local server="${SERVERS_CACHED[$idx]}"
        if [[ -z "$show_all" || "$show_all" =~ ^[Yy]$ ]]; then
            info "All services on $server"
            run_remote_script "$server" "if command -v systemctl >/dev/null 2>&1; then systemctl list-units --type=service --all; elif command -v rc-status >/dev/null 2>&1; then rc-status -a; elif command -v service >/dev/null 2>&1; then service --status-all 2>&1; else echo 'No supported service manager'; fi" 2>&1
        else
            read -r -p "Enter service name: " svc
            [[ -n "$svc" ]] || { warn "No service name."; continue; }
            run_remote_script "$server" "warkop_service status '$svc' || echo 'Service not found or unsupported'" 2>&1
        fi
    done
}

service_stop() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to stop: " svc
    if [[ -z "$svc" ]]; then warn "No service name."; return; fi
    run_service_command "stop $svc" "Stopping $svc"
}

service_start() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to start: " svc
    if [[ -z "$svc" ]]; then warn "No service name."; return; fi
    run_service_command "start $svc" "Starting $svc"
}

service_restart() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to restart: " svc
    if [[ -z "$svc" ]]; then warn "No service name."; return; fi
    run_service_command "restart $svc" "Restarting $svc"
}

service_auto_start() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to auto-start if down: " svc
    [[ -n "$svc" ]] || { warn "No service name."; return; }
    for idx in "${SELECTED_INDICES[@]}"; do
        local server="${SERVERS_CACHED[$idx]}"
        info "Checking $svc on $server"
        run_remote_script "$server" "if warkop_service_active '$svc'; then echo '$svc is already running.'; else warkop_service start '$svc' && warkop_service_enable '$svc'; fi" 2>&1
        echo "----------------------------------------"
    done
}
