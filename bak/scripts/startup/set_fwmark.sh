#!/bin/bash
source /opt/mpvpn2/globals.conf

# Prüfen, ob VPN-Interfaces definiert sind
if [ ${#VPN_INTERFACES[@]} -eq 0 ]; then
    echo "Fehler: Keine VPN-Interfaces definiert!"
    exit 1
fi

# FWMARKs für die Routingtabellen 100-400 direkt auf $DEFAULT_LANIF
for entry in "${EXTRA_RT_TABLES[@]}"; do
    IFS=' ' read -r mark table <<< "$entry"

    if [[ "$table" -ge 100 && "$table" -le 400 ]]; then
        # Tabellen 100-400 (Domains) direkt über $DEFAULT_LANIF (enp1s0)
        echo "[+] Setze FWMARK für Tabelle $table direkt auf $DEFAULT_LANIF"
        iptables -t mangle -A PREROUTING -i "$DEFAULT_LANIF" -m mark --mark $mark -j ACCEPT
    else
        # Alle anderen Tabellen (außer 100-400) werden über VPN-Interfaces geroutet
        echo "[+] Setze FWMARK für Tabelle $table, routing über VPN-Interfaces"
        for vpn_iface in "${VPN_INTERFACES[@]}"; do
            iptables -t mangle -A PREROUTING -i "$vpn_iface" -m mark --mark $mark -j ACCEPT
            echo "[+] Regel für $vpn_iface hinzugefügt"
        done
    fi
done

# Alles, was nicht in den Routingtabellen 100-400 definiert ist, soll über VPN-Interfaces laufen
echo "[+] Setze Catchall Regel für alles, was nicht in den Routingtabellen definiert ist, über VPN-Interfaces"

# Catchall für nicht definierte Tabellen (alle, die nicht in den Tabellen 100-400 sind)
for vpn_iface in "${VPN_INTERFACES[@]}"; do
    iptables -t mangle -A PREROUTING -i "$vpn_iface" -j ACCEPT
    echo "[+] Catchall Regel für $vpn_iface hinzugefügt"
done

echo "[+] Alle FWMARK-Regeln wurden erfolgreich gesetzt."
