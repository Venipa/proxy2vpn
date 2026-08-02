#!/bin/bash
set -euo pipefail

STATUS_FILE=/tmp/vpn-status
HTTP_PROXY_PORT=8888

if [[ ! -f "$STATUS_FILE" ]] || [[ "$(head -n 1 "$STATUS_FILE")" != "up" ]]; then
  echo "vpn down"
  exit 1
fi

if ! pgrep -x tinyproxy >/dev/null; then
  echo "tinyproxy down"
  exit 1
fi

if ! pgrep -x microsocks >/dev/null && ! pgrep -f '[m]icrosocks' >/dev/null; then
  echo "microsocks down"
  exit 1
fi

# Optional external IP check through the HTTP proxy path
if ! curl -fsS --max-time 8 -x "http://127.0.0.1:${HTTP_PROXY_PORT}" "https://ifconfig.me/ip" >/dev/null; then
  echo "proxy egress check failed"
  exit 1
fi

exit 0
