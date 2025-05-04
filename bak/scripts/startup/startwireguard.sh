#!/bin/sh

source /opt/mpvpn2/globals.conf

echo "Starte Wireguard Verbindungen..."
start_all_wgvpns() {
    for vpn in "${WGVPN_LIST[@]}"; do
        echo "Starte $vpn..."
        wg-quick up "$vpn"
    done
}
start_all_wgvpns
