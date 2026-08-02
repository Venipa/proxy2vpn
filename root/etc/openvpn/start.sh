#!/bin/bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

fatal() {
  log "ERROR: $*"
  exit 1
}

VPN_PROVIDER="${OPENVPN_PROVIDER:-protonvpn}"
VPN_PROVIDER="${VPN_PROVIDER,,}"
VPN_PROVIDER_HOME="/etc/openvpn/${VPN_PROVIDER}"
mkdir -p "$VPN_PROVIDER_HOME" /config /dev/net

# Haugene-style TUN handling:
# - Mount host /dev/net/tun via devices: → leave CREATE_TUN_DEVICE=false
# - Or set CREATE_TUN_DEVICE=true to mknod inside the container (no device mount)
CREATE_TUN_DEVICE="${CREATE_TUN_DEVICE:-true}"
if [[ -c /dev/net/tun ]]; then
  log "TUN device already present at /dev/net/tun (skip create)"
elif [[ "${CREATE_TUN_DEVICE,,}" == "true" ]]; then
  log "Creating TUN device /dev/net/tun"
  if [[ -e /dev/net/tun ]]; then
    if ! rm -f /dev/net/tun 2>/dev/null; then
      fatal "/dev/net/tun exists but is busy and not a usable char device. Unmount devices:/dev/net/tun or set CREATE_TUN_DEVICE=false"
    fi
  fi
  mknod /dev/net/tun c 10 200
  chmod 0666 /dev/net/tun
  log "TUN device created"
else
  fatal "No /dev/net/tun found. Mount devices: [/dev/net/tun] or set CREATE_TUN_DEVICE=true"
fi

if [[ -f /run/secrets/openvpn_creds ]]; then
  ln -fs /run/secrets/openvpn_creds /config/openvpn-credentials.txt
elif [[ -n "${OPENVPN_USERNAME:-}" && -n "${OPENVPN_PASSWORD:-}" ]]; then
  printf '%s\n%s\n' "$OPENVPN_USERNAME" "$OPENVPN_PASSWORD" > /config/openvpn-credentials.txt
  chmod 600 /config/openvpn-credentials.txt
elif [[ ! -f /config/openvpn-credentials.txt ]]; then
  fatal "OpenVPN credentials missing. Set OPENVPN_USERNAME/OPENVPN_PASSWORD or mount /config/openvpn-credentials.txt"
fi

# Proton port forward: enabled when OpenVPN username contains +pmp
OVPN_USER="$(head -n1 /config/openvpn-credentials.txt 2>/dev/null || true)"
if [[ "${OVPN_USER}" == *"+pmp"* ]]; then
  if [[ "${VPN_PROVIDER}" != "protonvpn" ]]; then
    fatal "Username has +pmp but OPENVPN_PROVIDER=${VPN_PROVIDER} (only protonvpn supported for port forward)"
  fi
  if ! command -v natpmpc >/dev/null 2>&1; then
    fatal "Username has +pmp but natpmpc not installed — cannot enable port forwarding"
  fi
  log "Detected +pmp in username — will request Proton NAT-PMP after tunnel up (or stop container on failure)"
fi

if [[ "$VPN_PROVIDER" == "custom" ]]; then
  if [[ ! -d "$VPN_PROVIDER_HOME" ]] || [[ -z "$(find "$VPN_PROVIDER_HOME" -name '*.ovpn' -print -quit)" ]]; then
    fatal "custom provider needs .ovpn files mounted at $VPN_PROVIDER_HOME"
  fi
else
  /etc/openvpn/fetch-configs.sh
fi

CHOSEN_OPENVPN_CONFIG=""

if [[ -n "${OPENVPN_CONFIG_URL:-}" ]]; then
  CHOSEN_OPENVPN_CONFIG="${VPN_PROVIDER_HOME}/downloaded_config.ovpn"
  log "Downloading config from OPENVPN_CONFIG_URL"
  curl -fsSL -o "$CHOSEN_OPENVPN_CONFIG" "$OPENVPN_CONFIG_URL"
elif [[ -n "${OPENVPN_CONFIG:-}" ]]; then
  IFS=',' read -r -a CONFIG_ARRAY <<< "$OPENVPN_CONFIG"
  for i in "${!CONFIG_ARRAY[@]}"; do
    CONFIG_ARRAY[$i]="$(echo "${CONFIG_ARRAY[$i]}" | xargs)"
  done

  if (( ${#CONFIG_ARRAY[@]} > 1 )); then
    PICK=$((RANDOM % ${#CONFIG_ARRAY[@]}))
    log "${#CONFIG_ARRAY[@]} configs listed; picked ${CONFIG_ARRAY[$PICK]}"
    SELECTED="${CONFIG_ARRAY[$PICK]}"
  else
    SELECTED="${CONFIG_ARRAY[0]}"
  fi

  if [[ -f "${VPN_PROVIDER_HOME}/${SELECTED}.ovpn" ]]; then
    CHOSEN_OPENVPN_CONFIG="${VPN_PROVIDER_HOME}/${SELECTED}.ovpn"
  else
    log "Config ${SELECTED}.ovpn not found. Available:"
    find "$VPN_PROVIDER_HOME" -maxdepth 1 -name '*.ovpn' -printf '%f\n' | sed 's/\.ovpn$//' | sort
    fatal "Supplied config ${SELECTED}.ovpn missing"
  fi
elif [[ -f "${VPN_PROVIDER_HOME}/default.ovpn" ]]; then
  CHOSEN_OPENVPN_CONFIG="${VPN_PROVIDER_HOME}/default.ovpn"
else
  fatal "No OPENVPN_CONFIG set and no default.ovpn present"
fi

log "Using OpenVPN config: ${CHOSEN_OPENVPN_CONFIG}"
/etc/openvpn/modify-openvpn-config.sh "$CHOSEN_OPENVPN_CONFIG"

# Kill switch baseline: allow established, loopback, DNS during bootstrap; drop other outbound later in tunnelUp
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

if [[ -n "${LOCAL_NETWORK:-}" ]]; then
  eval "$(ip route list match 0.0.0.0 | awk '{if($5!="tun0"){print "GW="$3"\nINT="$5; exit}}')"
  if [[ -n "${GW:-}" && -n "${INT:-}" ]]; then
    for net in ${LOCAL_NETWORK//,/ }; do
      log "Route local network ${net} via ${GW} dev ${INT}"
      ip route replace "${net}" via "${GW}" dev "${INT}"
      iptables -A INPUT -s "${net}" -j ACCEPT
    done
  else
    log "WARNING: LOCAL_NETWORK set but default gateway not detected yet"
  fi
fi

CONTROL_OPTS="--script-security 2 --up /etc/openvpn/tunnelUp.sh --down /etc/openvpn/tunnelDown.sh --up-restart"

log "Starting OpenVPN"
# shellcheck disable=SC2086
exec openvpn ${CONTROL_OPTS} ${OPENVPN_OPTS:-} --config "${CHOSEN_OPENVPN_CONFIG}"
