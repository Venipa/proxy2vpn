FROM alpine:3.21 AS microsocks-build
RUN apk add --no-cache build-base git \
    && git clone --depth 1 https://github.com/rofl0r/microsocks.git /src \
    && make -C /src

FROM alpine:3.21

RUN apk add --no-cache \
    bash \
    curl \
    git \
    iptables \
    iproute2 \
    openvpn \
    tinyproxy \
    libnatpmp \
    bind-tools \
    ca-certificates \
    coreutils \
    findutils \
    && mkdir -p /etc/openvpn /config /var/log/tinyproxy \
    && mkdir -p /usr/share/tinyproxy \
    && touch /usr/share/tinyproxy/default.html /usr/share/tinyproxy/stats.html

COPY --from=microsocks-build /src/microsocks /usr/local/bin/microsocks
COPY root/ /

RUN find /etc/openvpn /etc/tinyproxy -type f \( -name '*.sh' -o -name '*.tmpl' \) -exec sed -i 's/\r$//' {} + \
    && chmod +x /etc/openvpn/*.sh

ENV OPENVPN_PROVIDER=protonvpn \
    OPENVPN_CONFIG=nl.protonvpn.udp \
    VPN_CONFIG_SOURCE_REPO=haugene/vpn-configs-contrib \
    VPN_CONFIG_SOURCE_REVISION=main \
    CREATE_TUN_DEVICE=false \
    HEALTH_CHECK_HOST=1.1.1.1

EXPOSE 8888 1080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /etc/openvpn/healthcheck.sh

ENTRYPOINT ["/etc/openvpn/start.sh"]
