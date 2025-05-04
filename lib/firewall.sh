#!/bin/bash
# MPVPN2 Firewall with NFTables Round-Robin

configure_nftables_round_robin() {
    local active_vpns=("$@")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Configuring NFTables for Round-Robin"
    
    # NFTables-Regeln für Verbindungs-Tracking
    nft flush ruleset 2>/dev/null
    
    cat <<EOF | nft -f -
table ip mpvpn {
    set vpn_ifaces {
        type ifname
        elements = { $(printf '"%s",' "${active_vpns[@]}" | sed 's/,$//') }
    }

    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        meta mark set ct mark
        ct mark set jhash ip daddr . tcp dport mod ${#active_vpns[@]} seed 0xdeadbeef
        meta oifname @vpn_ifaces ct mark set 0
    }
}
EOF
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] NFTables configured for ${#active_vpns[@]} VPNs"
}

initialize_ipsets() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initializing ipsets"
    
    declare -A IPSETS=(
        ["cleardomains"]="hash:ip family inet timeout 300"
        ["mirrordomains"]="hash:ip family inet timeout 300"
        ["mailservers"]="hash:ip family inet timeout 300"
        ["servicetags"]="hash:ip family inet timeout 300"
    )

    for setname in "${!IPSETS[@]}"; do
        if ! ipset list "$setname" &>/dev/null; then
            ipset create "$setname" ${IPSETS[$setname]}
        else
            ipset flush "$setname"
        fi
    done

    for domain in "${CLEARDOMAINS[@]}"; do
        ipset add cleardomains "$domain" 2>/dev/null || true
    done
    
    for domain in "${MIRRORDOMAINS[@]}"; do
        ipset add mirrordomains "$domain" 2>/dev/null || true
    done
    
    for domain in "${MAIL_SERVERS[@]}"; do
        ipset add mailservers "$domain" 2>/dev/null || true
    done
    
    for domain in "${!SERVICE_TAGS[@]}"; do
        ipset add servicetags "$domain" 2>/dev/null || true
    done
}

configure_firewall() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Configuring firewall rules"
    
    # Standardrichtlinien
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Basisregeln
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    # LAN-Regeln
    iptables -A INPUT -i "$DEFAULT_LANIF" -s "$DEFAULT_SUBNET" -j ACCEPT
    iptables -A OUTPUT -o "$DEFAULT_LANIF" -d "$DEFAULT_SUBNET" -j ACCEPT
    
    # Erlaubte Ports
    for port in "${ALLOWED_PORTS_TCP[@]}"; do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    done
    
    for port in "${ALLOWED_PORTS_UDP[@]}"; do
        iptables -A INPUT -p udp --dport "$port" -j ACCEPT
    done
    
    # VPN-Regeln
    for iface in "${VPN_INTERFACES[@]}"; do
        iptables -A INPUT -i "$iface" -j ACCEPT
        iptables -A FORWARD -i "$iface" -j ACCEPT
    done
    
    # Cross-VPN-Verkehr verhindern
    for src in "${VPN_INTERFACES[@]}"; do
        for dst in "${VPN_INTERFACES[@]}"; do
            [[ "$src" != "$dst" ]] && \
                iptables -A FORWARD -i "$src" -o "$dst" -j REJECT \
                --reject-with icmp-port-unreachable
        done
    done
    
    # NAT-Regeln
    iptables -t nat -A POSTROUTING -o "$DEFAULT_LANIF" -j MASQUERADE
    for iface in "${VPN_INTERFACES[@]}"; do
        iptables -t nat -A POSTROUTING -o "$iface" -j MASQUERADE
    done
    
    # Traffic-Markierung
    iptables -t mangle -A PREROUTING -m set --match-set cleardomains dst -j MARK --set-mark 100
    iptables -t mangle -A PREROUTING -m set --match-set mirrordomains dst -j MARK --set-mark 200
    iptables -t mangle -A PREROUTING -m set --match-set mailservers dst -j MARK --set-mark 300
    iptables -t mangle -A PREROUTING -m set --match-set servicetags dst -j MARK --set-mark 400
    
    # Non-VPN-Clients
    for client in "${NON_VPN_CLIENTS[@]}"; do
        iptables -t mangle -A PREROUTING -s "$client" -j MARK --set-mark 0
    done
    
    # Spezialregeln für deubau
    iptables -A FORWARD -i deubau -o "$DEFAULT_LANIF" -j ACCEPT
    iptables -A FORWARD -i "$DEFAULT_LANIF" -o deubau -j ACCEPT
    iptables -A FORWARD -i deubau -j REJECT --reject-with icmp-port-unreachable
    iptables -t nat -A POSTROUTING -s "$DEFAULT_SUBNET" -d 192.168.88.0/24 -o deubau -j MASQUERADE
    
    # Logging
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FW-Dropped: " --log-level 4
    iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "FW-Forward-Dropped: " --log-level 4
}

flush_firewall() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Flushing firewall rules"
    
    for table in filter nat mangle; do
        iptables -t "$table" -F
        iptables -t "$table" -X
    done
    
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    nft flush ruleset 2>/dev/null
}
