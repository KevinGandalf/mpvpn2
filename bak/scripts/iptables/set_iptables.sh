#!/bin/bash
source /opt/mpvpn2/globals.conf

# Ensure root execution
[[ $EUID -ne 0 ]] && { echo "Dieses Skript muss als Root ausgeführt werden."; exit 1; }

VPN_INTERFACES=("${WGVPN_LIST[@]}" "${OVPN_LIST[@]}")

# Clear existing rules
for table in filter nat mangle; do
    iptables -t "$table" -F
    iptables -t "$table" -X
done

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

### Filter Table ###
# Allow localhost traffic
iptables -A INPUT -i lo -j ACCEPT
# Allow established and related connections
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# Allow ICMP echo requests (ping)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
# Allow certain TCP ports (SSH, HTTP, HTTPS)
iptables -A INPUT -p tcp -m multiport --dports "${ALLOWED_PORTS_TCP[@]}" \
    -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# Allow DNS queries from the local network
iptables -A INPUT -i "$DEFAULT_LANIF" -p udp --dport 53 -s "$DEFAULT_SUBNET" -j ACCEPT
iptables -A INPUT -i "$DEFAULT_LANIF" -p tcp --dport 53 -s "$DEFAULT_SUBNET" -j ACCEPT
# Allow DNS responses from public resolvers
for dns_ip in "${PUBLIC_DNS[@]}"; do
    iptables -A INPUT -i "$DEFAULT_LANIF" -p udp --sport 53 -s "$dns_ip" -j ACCEPT
    iptables -A INPUT -i "$DEFAULT_LANIF" -p tcp --sport 53 -s "$dns_ip" -j ACCEPT
done
# Log dropped packets (limit to 5 per minute)
iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "IPTables-DROP: " --log-level 4
# Drop all other inbound traffic
iptables -A INPUT -j DROP

# Prevent cross-VPN traffic
for src in "${VPN_INTERFACES[@]}"; do
    for dst in "${VPN_INTERFACES[@]}"; do
        [[ "$src" != "$dst" ]] && \
            iptables -A FORWARD -i "$src" -o "$dst" -j REJECT \
            --reject-with icmp-port-unreachable
    done
done

### NAT Rules ###
# Default NAT for outgoing traffic
iptables -t nat -A POSTROUTING -o "$DEFAULT_LANIF" -j ACCEPT
# NAT for VPN interfaces
for iface in "${VPN_INTERFACES[@]}"; do
    iptables -t nat -A POSTROUTING -o "$iface" -j MASQUERADE
done

# Special case for deubau
iptables -A FORWARD -i deubau -o "$DEFAULT_LANIF" -j ACCEPT
iptables -A FORWARD -i "$DEFAULT_LANIF" -o deubau -j ACCEPT
iptables -A FORWARD -i deubau -j REJECT --reject-with icmp-port-unreachable
iptables -t nat -A POSTROUTING -s "$DEFAULT_SUBNET" -d 192.168.88.0/24 -o deubau -j MASQUERADE

# Save rules
iptables-save > /etc/sysconfig/iptables

echo "iptables-Regeln wurden erfolgreich optimiert und gespeichert."
