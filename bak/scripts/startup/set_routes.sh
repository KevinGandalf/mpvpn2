#!/bin/bash

source /opt/mpvpn/globals.conf

STATUSFILE="/opt/mpvpn2/logs/setroutes.log"

add_routes_per_table() {
    echo "==== $(date '+%Y-%m-%d %H:%M:%S') ====" > "$STATUSFILE"
    echo "📦 Setze Routingtabellen..." >> "$STATUSFILE"

    # LAN-Gateway ermitteln
    LAN_GW=$(ip -4 addr show dev "$DEFAULT_LANIF" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [[ -z "$LAN_GW" ]]; then
        echo "❌ Kein Gateway auf $DEFAULT_LANIF gefunden." >> "$STATUSFILE"
        exit 1
    fi

    # 1. Tabellen 100–400 → LAN
    for entry in "${EXTRA_RT_TABLES[@]}"; do
        IFS=' ' read -r mark table <<< "$entry"

        if [[ "$table" -ge 100 && "$table" -le 400 ]]; then
            echo "[+] Tabelle $table: Setze Default-Route über LAN ($LAN_GW)"
            ip route flush table "$table"
            ip route add default via "$LAN_GW" dev "$DEFAULT_LANIF" table "$table"
            echo "    ➜ default via $LAN_GW dev $DEFAULT_LANIF" >> "$STATUSFILE"
        fi
    done

    # 2. Tabelle 500 (catchall) → VPN-Only
    echo "[🌐] Tabelle 500: Default-Routen über VPN setzen..."
    ip route flush table 500

    # WireGuard
    for vpn in "${WGVPN_LIST[@]}"; do
        if ip link show "$vpn" >/dev/null 2>&1; then
            echo "➕ WG: $vpn → dev $vpn in Tabelle 500"
            ip route add default dev "$vpn" table 500
            echo "    ➜ default dev $vpn" >> "$STATUSFILE"
        else
            echo "⚠️  WG-Interface $vpn nicht verfügbar." >> "$STATUSFILE"
        fi
    done

    # OpenVPN
    if [[ "$ENABLE_OVPN" == true ]]; then
        for vpn in "${OVPN_LIST[@]}"; do
            pid=$(pgrep -f "openvpn --config.*$vpn\.conf" | head -n1)

            if [[ -n "$pid" ]]; then
                tun_dev=$(ls -l /proc/$pid/fd 2>/dev/null | grep /dev/net/tun | awk -F'/' '{print $NF}' | head -n1)
                [[ -z "$tun_dev" ]] && tun_dev=$(ip -o link show | awk -F': ' '/tun[0-9]+/ {print $2}' | grep -v lo | head -n1)

                gw_ip=$(ip route | grep "$tun_dev" | grep -oP 'via \K[0-9.]+' | head -n1)

                if [[ -n "$tun_dev" && -n "$gw_ip" ]]; then
                    echo "➕ OVPN: $vpn → via $gw_ip dev $tun_dev in Tabelle 500"
                    ip route add default via "$gw_ip" dev "$tun_dev" table 500
                    echo "    ➜ default via $gw_ip dev $tun_dev" >> "$STATUSFILE"
                else
                    echo "⚠️  $vpn → Kein gültiges Gateway/Device – übersprungen." >> "$STATUSFILE"
                fi
            else
                echo "⚠️  $vpn → Kein aktiver OpenVPN-Prozess." >> "$STATUSFILE"
            fi
        done
    else
        echo "🔒 OpenVPN deaktiviert – überspringe." >> "$STATUSFILE"
    fi

    echo "✅ Routingtabellen vollständig gesetzt." >> "$STATUSFILE"
}

# Ausführen
add_routes_per_table
