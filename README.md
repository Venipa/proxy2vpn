# proxy2vpn-tunnel

**Author:** Venipa

OpenVPN (ProtonVPN via [vpn-configs-contrib](https://github.com/haugene/vpn-configs-contrib/tree/main/openvpn/protonvpn)) + HTTP/SOCKS5 proxy. Proxy runs only while VPN is up.

## Quick start

```bash
cp .env.example .env
# OPENVPN_USERNAME / OPENVPN_PASSWORD + OPENVPN_CONFIG
# PROXY_SOCKS_PORT=7888 (host port; container stays 1080)

docker compose up -d --build
```

```bash
curl -x socks5h://127.0.0.1:7888 https://ifconfig.me
curl -x http://127.0.0.1:8888 https://ifconfig.me
```

## Ports

| Env | Maps to | Default |
|-----|---------|---------|
| `PROXY_HTTP_PORT` | host → `:8888/tcp` | `8888` |
| `PROXY_SOCKS_PORT` | host → `:1080/tcp` + `:1080/udp` | `1080` |

Dokploy / Traefik: no host ports — target **`proxy2vpn:8888`** (HTTP) or **`proxy2vpn:1080`** (SOCKS).

## Compose

| File | Use |
|------|-----|
| `docker-compose.yml` | Local — publishes `PROXY_*_PORT` |
| `docker-compose.dokploy.yml` | Dokploy — Traefik to container ports |

## Client

After logs show `Proxies ready`:

```text
SOCKS5  <host-ip>:<PROXY_SOCKS_PORT>   e.g. 192.168.0.124:7888
HTTP    <host-ip>:<PROXY_HTTP_PORT>    e.g. 192.168.0.124:8888
```

Set `LOCAL_NETWORK` to your LAN (e.g. `192.168.0.0/16`).

## TUN

- `CREATE_TUN_DEVICE=false` + `devices: [/dev/net/tun]` (default), or
- `CREATE_TUN_DEVICE=true` and remove the device mount

## Port forwarding (ProtonVPN)

Put `+pmp` on the OpenVPN username (P2P server + paid PF plan):

```env
OPENVPN_USERNAME=xxxx+pmp
OPENVPN_PROVIDER=protonvpn
OPENVPN_CONFIG=nl.protonvpn.udp
```

- Detects `+pmp` → NAT-PMP after tunnel up; renews ~45s
- Logs `ProtonVPN forwarded port: NNNNN` → `/config/forwarded_port`
- If NAT-PMP fails → **container stops**
- No `+pmp` → port forward off
