#!/bin/bash
source /opt/mpvpn2/globals.conf

for entry in "${EXTRA_RT_TABLES[@]}"; do
  IFS=' ' read -r mark table <<< "$entry"
  echo "[+] Setze ip rule für Mark $mark, Tabelle $table"
  
  ip rule add fwmark "$mark" table "$table"
done
