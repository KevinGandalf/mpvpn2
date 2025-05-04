#!/bin/bash
# VPN management for MPVPN2

init_vpn_connections() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initializing VPN connections"
    
    # Initialize WireGuard connections
    for vpn in "${WGVPN_LIST[@]}"; do
        if [[ -f "${WG_CONF_DIR}/${vpn}.conf" ]]; then
            wg-quick down "${WG_CONF_DIR}/${vpn}.conf" 2>/dev/null
            wg-quick up "${WG_CONF_DIR}/${vpn}.conf"
        fi
    done
    
    # Initialize OpenVPN connections if enabled
    if [[ "$ENABLE_OVPN" == "true" ]]; then
        for vpn in "${OVPN_LIST[@]}"; do
            if [[ -f "${OVPN_CONF_DIR}/${vpn}.conf" ]]; then
                systemctl stop "openvpn@${vpn}" 2>/dev/null
                systemctl start "openvpn@${vpn}"
            fi
        done
    fi
}

start_vpn_connections() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting VPN connections"
    
    for vpn in "${WGVPN_LIST[@]}"; do
        if [[ -f "${WG_CONF_DIR}/${vpn}.conf" ]]; then
            wg-quick up "${WG_CONF_DIR}/${vpn}.conf"
        fi
    done
    
    if [[ "$ENABLE_OVPN" == "true" ]]; then
        for vpn in "${OVPN_LIST[@]}"; do
            if [[ -f "${OVPN_CONF_DIR}/${vpn}.conf" ]]; then
                systemctl start "openvpn@${vpn}"
            fi
        done
    fi
}

stop_vpn_connections() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping VPN connections"
    
    for vpn in "${WGVPN_LIST[@]}"; do
        if [[ -f "${WG_CONF_DIR}/${vpn}.conf" ]]; then
            wg-quick down "${WG_CONF_DIR}/${vpn}.conf"
        fi
    done
    
    if [[ "$ENABLE_OVPN" == "true" ]]; then
        for vpn in "${OVPN_LIST[@]}"; do
            if [[ -f "${OVPN_CONF_DIR}/${vpn}.conf" ]]; then
                systemctl stop "openvpn@${vpn}"
            fi
        done
    fi
}
