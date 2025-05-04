#!/bin/bash
# MPVPN2 Routing Configuration with Equal-Weight Round-Robin

init_routing_tables() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initializing routing tables"
    
    # Standardrouting-Tabellen
    while read -r line; do
        table_id=$(echo "$line" | awk '{print $1}')
        table_name=$(echo "$line" | awk '{print $2}')
        
        if ! grep -q "^$table_id" /etc/iproute2/rt_tables; then
            echo "$table_id $table_name" >> /etc/iproute2/rt_tables
        fi
    done <<< "$(printf '%s\n' "${EXTRA_RT_TABLES[@]}")"
    
    # Basisrouting
    ip route add default via "$DEFAULT_WANGW" dev "$DEFAULT_LANIF" table main
    
    # IPSets für spezielle Domains
    for domain in "${CLEARDOMAINS[@]}"; do
        ipset add cleardomains "$domain" 2>/dev/null || true
    done
    
    for domain in "${MIRRORDOMAINS[@]}"; do
        ipset add mirrordomains "$domain" 2>/dev/null || true
    done
    
    # Policy Routing
    for vpn in "${!VPN_CONFIG[@]}"; do
        IFS=':' read -r mark table <<< "${VPN_CONFIG[$vpn]}"
        ip rule add fwmark "$mark" table "$table"
    done
    
    # Round-Robin für nicht spezifizierten Traffic
    configure_round_robin
}

configure_round_robin() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Configuring Round-Robin VPN routing"
    
    # Flush existing catchall table
    ip route flush table 500 2>/dev/null
    
    # Aktive VPNs ermitteln
    local active_vpns=()
    for vpn in "${VPN_INTERFACES[@]}"; do
        if ip link show "$vpn" &>/dev/null; then
            active_vpns+=("$vpn")
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] VPN active: $vpn"
        fi
    done
    
    if [ ${#active_vpns[@]} -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No active VPNs - using default gateway"
        ip route add default via "$DEFAULT_WANGW" dev "$DEFAULT_LANIF" table 500
        return
    fi
    
    # Equal-Cost Multi-Path Routing (alle Gewichte = 1)
    local cmd="ip route add default table 500"
    for vpn in "${active_vpns[@]}"; do
        local gw=$(get_vpn_gateway "$vpn")
        if [ -n "$gw" ]; then
            cmd+=" nexthop via $gw dev $vpn weight 1"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding VPN route: $vpn (GW: $gw)"
        fi
    done
    
    eval "$cmd" 2>/dev/null
    
    # NFTables für Verbindungsverfolgung
    configure_nftables_round_robin "${active_vpns[@]}"
    
    # Default Policy
    ip rule add from all fwmark 0 table 500 priority 200
}

get_vpn_gateway() {
    local iface=$1
    # WireGuard
    if [[ " ${WGVPN_LIST[@]} " =~ " $iface " ]]; then
        ip -4 route show dev "$iface" | awk '/default via/ {print $3}' | head -n1
    # OpenVPN
    else
        ip -4 route show dev "$iface" | awk '/via/ {print $3}' | head -n1
    fi
}

flush_routing() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Flushing routing tables"
    
    ip rule del from all table main 2>/dev/null
    ip rule del from all fwmark 0 table 500 2>/dev/null
    
    for vpn in "${!VPN_CONFIG[@]}"; do
        IFS=':' read -r mark table <<< "${VPN_CONFIG[$vpn]}"
        ip rule del fwmark "$mark" table "$table" 2>/dev/null
    done
    
    for table in "${EXTRA_RT_TABLES[@]}"; do
        table_id=$(echo "$table" | awk '{print $1}')
        ip route flush table "$table_id" 2>/dev/null
    done
}
