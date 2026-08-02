#!/bin/bash
set -euo pipefail

VPN_PROVIDER="${OPENVPN_PROVIDER:-protonvpn}"
VPN_PROVIDER="${VPN_PROVIDER,,}"
VPN_PROVIDER_HOME="/etc/openvpn/${VPN_PROVIDER}"
GITHUB_CONFIG_SOURCE_REPO="${VPN_CONFIG_SOURCE_REPO:-haugene/vpn-configs-contrib}"
GITHUB_CONFIG_SOURCE_REVISION="${VPN_CONFIG_SOURCE_REVISION:-main}"
CONFIG_REPO="/config/vpn-configs-contrib"
GITHUB_CONFIG_REPO_URL="https://github.com/${GITHUB_CONFIG_SOURCE_REPO}.git"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

mkdir -p /config
git config --global --add safe.directory "${CONFIG_REPO}" || true

if [[ -d "${CONFIG_REPO}/.git" ]]; then
  LOCAL_REPO="$(git -C "${CONFIG_REPO}" remote get-url origin 2>/dev/null | sed -e 's#https://github.com/##' -e 's#\.git$##' || true)"
  if [[ "${LOCAL_REPO}" == "${GITHUB_CONFIG_SOURCE_REPO}" ]]; then
    log "Updating configs from ${GITHUB_CONFIG_REPO_URL}"
    if git -C "${CONFIG_REPO}" fetch origin; then
      git -C "${CONFIG_REPO}" reset --hard "origin/${GITHUB_CONFIG_SOURCE_REVISION}"
      git -C "${CONFIG_REPO}" clean -fd
    else
      log "WARNING: fetch failed; using existing local configs"
    fi
  else
    log "Different repo cached; recloning ${GITHUB_CONFIG_REPO_URL}"
    rm -rf "${CONFIG_REPO}"
    git clone -b "${GITHUB_CONFIG_SOURCE_REVISION}" --depth 1 "${GITHUB_CONFIG_REPO_URL}" "${CONFIG_REPO}"
  fi
else
  log "Cloning ${GITHUB_CONFIG_REPO_URL}"
  rm -rf "${CONFIG_REPO}"
  git clone -b "${GITHUB_CONFIG_SOURCE_REVISION}" --depth 1 "${GITHUB_CONFIG_REPO_URL}" "${CONFIG_REPO}"
fi

PROVIDER_CONFIGS="$(find "${CONFIG_REPO}/openvpn" -type d -name "${VPN_PROVIDER}" | head -n 1)"
if [[ -z "${PROVIDER_CONFIGS}" ]]; then
  echo "ERROR: no configs for provider ${VPN_PROVIDER} in ${GITHUB_CONFIG_SOURCE_REPO}"
  exit 1
fi

log "Installing ${VPN_PROVIDER} configs into ${VPN_PROVIDER_HOME}"
rm -rf "${VPN_PROVIDER_HOME}"
mkdir -p "$(dirname "${VPN_PROVIDER_HOME}")"
cp -a "${PROVIDER_CONFIGS}" "${VPN_PROVIDER_HOME}"
