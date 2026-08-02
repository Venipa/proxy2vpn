#!/bin/bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

# Kill OpenVPN (PID 1 after exec) so Docker marks container stopped/restarted
stop_container() {
  log "ERROR: $*"
  log "Stopping container (+pmp requires working Proton NAT-PMP)"
  kill -TERM 1 2>/dev/null || true
  sleep 1
  kill -KILL 1 2>/dev/null || true
  exit 1
}

OVPN_USER="$(head -n1 /config/openvpn-credentials.txt 2>/dev/null || true)"
if [[ "${OVPN_USER}" != *"+pmp"* ]]; then
  exit 0
fi

VPN_PROVIDER="${OPENVPN_PROVIDER:-protonvpn}"
VPN_PROVIDER="${VPN_PROVIDER,,}"

if [[ "${VPN_PROVIDER}" != "protonvpn" ]]; then
  stop_container "Username has +pmp but provider '${VPN_PROVIDER}' is not supported (only protonvpn)"
fi

if ! command -v natpmpc >/dev/null 2>&1; then
  stop_container "natpmpc missing — cannot enable port forwarding"
fi

DEV="${dev:-tun0}"
GATEWAY="${NATPMP_GATEWAY:-}"
if [[ -z "${GATEWAY}" ]]; then
  GATEWAY="$(ip -4 route show default dev "${DEV}" 2>/dev/null | awk '{print $3; exit}' || true)"
fi
GATEWAY="${GATEWAY:-10.2.0.1}"

PORT_FILE="${PORT_FORWARD_FILE:-/config/forwarded_port}"
mkdir -p "$(dirname "${PORT_FILE}")"

request_port() {
  local out
  # UDP then TCP mapping (Proton: same public port). Lease 60s, renew ~45s.
  timeout 10 natpmpc -a 1 0 udp 60 -g "${GATEWAY}" >/dev/null 2>&1 || return 1
  out="$(timeout 10 natpmpc -a 1 0 tcp 60 -g "${GATEWAY}" 2>/dev/null || true)"
  echo "${out}" | sed -nr 's/.*Mapped public port ([0-9]{2,5}).*/\1/p' | head -n1
}

log "Port forward (+pmp) — NAT-PMP gateway ${GATEWAY} (dev ${DEV})"

PF_PORT=""
for attempt in 1 2 3 4 5; do
  PF_PORT="$(request_port || true)"
  if [[ "${PF_PORT}" =~ ^[0-9]+$ ]] && [[ "${PF_PORT}" -gt 0 ]]; then
    break
  fi
  log "NAT-PMP attempt ${attempt}/5 failed (server may lack P2P/PF)"
  sleep 3
done

if [[ ! "${PF_PORT}" =~ ^[0-9]+$ ]] || [[ "${PF_PORT}" -le 0 ]]; then
  stop_container "NAT-PMP port forward failed. Use a Proton P2P server and paid plan with PF"
fi

echo "${PF_PORT}" > "${PORT_FILE}"
echo "${PF_PORT}" > /tmp/forwarded_port
log "ProtonVPN forwarded port: ${PF_PORT} (saved ${PORT_FILE})"

# Renew lease until tunnel dies
LAST_PORT="${PF_PORT}"
while true; do
  sleep 45
  NEW_PORT="$(request_port || true)"
  if [[ ! "${NEW_PORT}" =~ ^[0-9]+$ ]] || [[ "${NEW_PORT}" -le 0 ]]; then
    stop_container "NAT-PMP renew failed — port forwarding lost"
  fi
  if [[ "${NEW_PORT}" != "${LAST_PORT}" ]]; then
    echo "${NEW_PORT}" > "${PORT_FILE}"
    echo "${NEW_PORT}" > /tmp/forwarded_port
    log "ProtonVPN forwarded port changed: ${LAST_PORT} → ${NEW_PORT}"
    LAST_PORT="${NEW_PORT}"
  else
    log "NAT-PMP lease renewed — port ${LAST_PORT}"
  fi
done
