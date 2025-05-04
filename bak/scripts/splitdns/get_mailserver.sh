#!/bin/bash
#!/bin/bash
source /opt/mpvpn2/globals.conf

# === Variablen ===
LOGFILE="/opt/mpvpn2/logs/splitdns/mailserver.log"
STATUS_FILE="/opt/mpvp2/logs/splitdns/splitdnsstatus.log"

# Finde den Tabellennamen und die ID für SMTP
for entry in "${EXTRA_RT_TABLES[@]}"; do
  id=$(echo "$entry" | awk '{print $1}')
  name=$(echo "$entry" | awk '{print $2}')
  if [[ "$name" == "smtp" ]]; then
    MARK="$id"
    TABLE="$name"
    break
  fi
done

# Sanity Check
if [[ -z "$MARK" || -z "$TABLE" ]]; then
  echo "❌ SMTP Routing-Tabelle nicht in EXTRA_RT_TABLES gefunden!"
  exit 1
fi

# Netzwerkschnittstelle und Gateway aus globals
#INTERFACE="$DEFAULT_LANIF"
#GATEWAY="DEFAULT_WANGW"

echo "⚙️  Verwende Table '$TABLE' mit Mark '$MARK' über Interface '$DEFAULT_LANIF' via '$DEFAULT_WANGW'"

# Routing-Tabelle leeren oder anlegen
ip route flush table "$TABLE" 2>/dev/null
ip rule add fwmark "$MARK" table "$TABLE" 2>/dev/null || true

# Mailserver-Routing
for SERVER in "${MAIL_SERVERS[@]}"; do
  echo "🔍 Resolving $SERVER..."
  IPS=$(dig +short A "$SERVER" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
  if [[ -z "$IPS" ]]; then
    echo "⚠️  Keine IPs gefunden für $SERVER – übersprungen"
    continue
  fi

  for IP in $IPS; do
    echo "➕ Route für $IP via $DEFAULT_WANGW ($DEFAULT_LANIF) in Table $TABLE"
    ip route add "$IP" via "$DEFAULT_WANGW" dev "$DEFAULT_LANIF" table "$TABLE"
    iptables -t mangle -A PREROUTING -d "$IP" -j MARK --set-mark "$MARK"
  done
done

# Default-Route und Regeln setzen
ip route add default via "$DEFAULT_WANGW" dev "$DEFAULT_LANIF" table "$TABLE"
ip rule add ipproto tcp dport 25 table "$TABLE" 2>/dev/null || true
ip rule add ipproto tcp dport 465 table "$TABLE" 2>/dev/null || true
ip rule add ipproto tcp dport 587 table "$TABLE" 2>/dev/null || true

echo "✅ SMTP-Routing für Table '$TABLE' abgeschlossen."
