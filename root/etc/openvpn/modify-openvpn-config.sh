#!/bin/bash
set -euo pipefail

CONFIG_FILE="${1:?config path required}"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config not found: $CONFIG_FILE"
  exit 1
fi

# Drop conflicting directives that fight container networking / DNS
sed -i \
  -e '/^[[:space:]]*up[[:space:]]/d' \
  -e '/^[[:space:]]*down[[:space:]]/d' \
  -e '/^[[:space:]]*script-security[[:space:]]/d' \
  -e '/^[[:space:]]*auth-user-pass[[:space:]]/d' \
  -e '/^[[:space:]]*user[[:space:]]/d' \
  -e '/^[[:space:]]*group[[:space:]]/d' \
  -e '/^[[:space:]]*resolv-retry[[:space:]]/d' \
  -e '/^[[:space:]]*ping[[:space:]]/d' \
  -e '/^[[:space:]]*ping-restart[[:space:]]/d' \
  "$CONFIG_FILE"

{
  echo ""
  echo "# --- injected by proxy2vpn-tunnel ---"
  echo "auth-user-pass /config/openvpn-credentials.txt"
  echo "script-security 2"
  echo "resolv-retry infinite"
  echo "ping 10"
  echo "ping-restart 60"
  echo "pull-filter ignore \"route-ipv6\""
  echo "pull-filter ignore \"ifconfig-ipv6\""
  echo "pull-filter ignore redirect-gateway"
  echo "redirect-gateway def1"
} >> "$CONFIG_FILE"

log "Modified OpenVPN config: $CONFIG_FILE"
