#!/bin/bash

# Globale Variablen und Funktionen
source /opt/mpvpn2/globals.conf

# Debug-Modus (set -x für detaillierte Ausgabe)
DEBUG=false
$DEBUG && set -x

# Funktionen
clean_ipsets_and_iptables() {
    echo "[*] Cleaning existing iptables mangle rules for to_table_*"
    # Effizientere Methode zum Löschen von Regeln
    iptables -t mangle -S | awk '/to_table_/ {print "-D " substr($0, 3)}' | xargs -r -L1 iptables -t mangle
    
    echo "[*] Removing all to_table_* ipsets"
    ipset list -n | grep '^to_table_' | while read -r set; do
        ipset destroy "$set" 2>/dev/null
    done
}

validate_environment() {
    # Essential variables check
    local required_vars=("DEFAULT_SUBNET" "DEFAULT_LANIF" "DEFAULT_LANIP" "DEFAULT_WANGW")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Error: Missing required variable $var in globals.sh"
            exit 1
        fi
    done
    
    # Interface check
    ip link show "$DEFAULT_LANIF" >/dev/null 2>&1 || {
        echo "Error: Interface $DEFAULT_LANIF not found"
        exit 1
    }
}

setup_routing() {
    # Clean existing rules first
    clean_ipsets_and_iptables
    
    # Process each routing table
    for entry in "${EXTRA_RT_TABLES[@]}"; do
        local table_id table_name ipset_name
        table_id=$(echo "$entry" | awk '{print $1}')
        table_name=$(echo "$entry" | awk '{print $2}')
        ipset_name="to_table_${table_id}"
        
        echo "[+] Processing table $table_id ($table_name) → ipset: $ipset_name"
        
        # Create or flush ipset
        if ipset list -n | grep -q "^${ipset_name}$"; then
            ipset flush "$ipset_name"
        else
            ipset create "$ipset_name" hash:net family inet hashsize 1024 maxelem 65536 2>/dev/null
        fi
        
        # Add routes to ipset (more robust parsing)
        ip route show table "$table_id" | awk '/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}' | while read -r ip; do
            ipset add "$ipset_name" "$ip" 2>/dev/null || echo "Warning: Failed to add $ip to $ipset_name"
        done
        
        # Add iptables rules
        iptables -t mangle -A PREROUTING -m set --match-set "$ipset_name" dst -j MARK --set-mark "$table_id"
        iptables -t mangle -A OUTPUT -m set --match-set "$ipset_name" dst -j MARK --set-mark "$table_id"
        
        echo "[✓] Added rules for $ipset_name → MARK $table_id"
    done
}


# Main execution
validate_environment

case "$1" in
    --reset)
        clean_ipsets_and_iptables
        echo "[✓] Reset complete"
        ;;
    --setup)
        setup_routing
        ;;
    *)
        echo "Usage: $0 [--reset|--setup]"
        echo "  --reset   Clean all rules and ipsets"
        echo "  --setup   Configure routing rules"
        exit 1
        ;;
esac
