#!/bin/bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

log "VPN tunnel down — stopping proxies"

pkill -f '/etc/openvpn/port-forward.sh' 2>/dev/null || true
rm -f /tmp/port-forward.pid /tmp/forwarded_port

pkill tinyproxy 2>/dev/null || true
if [[ -f /tmp/microsocks.pid ]]; then
  kill "$(cat /tmp/microsocks.pid)" 2>/dev/null || true
  rm -f /tmp/microsocks.pid
fi
pkill microsocks 2>/dev/null || true

echo "down" > /tmp/vpn-status

# Harden OUTPUT while disconnected (allow DNS + VPN reconnect)
iptables -F OUTPUT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
if [[ -n "${trusted_ip:-}" ]]; then
  iptables -A OUTPUT -d "${trusted_ip}" -j ACCEPT
fi
# UDP/TCP OpenVPN common ports for reconnect
iptables -A OUTPUT -p udp -m multiport --dports 1194,80,443,4569,5060,51820 -j ACCEPT
iptables -A OUTPUT -p tcp -m multiport --dports 1194,80,443,4569,5060,51820 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -j DROP

log "Proxies stopped; waiting for OpenVPN reconnect"
