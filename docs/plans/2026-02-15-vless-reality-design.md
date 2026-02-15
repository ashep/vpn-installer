# VLESS + Reality + XTLS Vision Installer — Design

## Overview

Replace the current Shadowsocks + v2ray-plugin + Caddy stack with a single xray-core binary running VLESS protocol with Reality transport and XTLS Vision flow. Designed to bypass Russian TSPU deep packet inspection.

## Architecture

```
Client ──Reality TLS──▶ Xray (:443) ──VLESS──▶ Internet
Probe  ──TLS hello──▶  Xray (:443) ──forward──▶ www.microsoft.com (real site)
```

Single binary, single service, single config. No Caddy, no Shadowsocks, no v2ray-plugin, no domain required.

## Why Reality beats the current setup

The current Shadowsocks + WebSocket + TLS setup is detectable because:
- The WebSocket upgrade inside TLS is a known fingerprint
- Active probing can confirm the proxy by connecting to the WS path
- The TLS certificate is self-issued (Let's Encrypt), linking the domain to the server

Reality solves all three:
- No WebSocket — plain TCP with Reality TLS handshake
- Active probes are forwarded to the real destination site (e.g. microsoft.com)
- No certificate at all — the server impersonates another site's TLS
- XTLS Vision flow prevents length-based traffic pattern analysis

## Stack

| Component | Role |
|-----------|------|
| xray-core | VLESS proxy + Reality TLS + XTLS Vision |

### Removed components

- shadowsocks-rust — replaced by VLESS
- v2ray-plugin — not needed, Reality is built into xray-core
- Caddy — not needed, Reality handles TLS impersonation

## Decisions

| Choice | Value | Reason |
|--------|-------|--------|
| Protocol | VLESS | Required for Reality transport |
| Transport | TCP + Reality | Best anti-detection against Russian DPI |
| Flow | xtls-rpc-vision | Prevents length-based traffic analysis |
| Dest site | www.microsoft.com | TLS 1.3, H2, not blocked in Russia, consistent behavior |
| Port | 443 | Standard HTTPS, expected by DPI |
| Domain | Not required | Reality connects by server IP |
| Binary source | GitHub releases (XTLS/Xray-core) | Official distribution |

## Server config

```json
{
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "<UUID>", "flow": "xtls-rpc-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "www.microsoft.com:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "<PRIVATE_KEY>",
        "shortIds": ["<SHORT_ID>"]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
```

## Share link format

```
vless://<UUID>@<SERVER_IP>:443?encryption=none&flow=xtls-rpc-vision&type=tcp&security=reality&sni=www.microsoft.com&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>#<label>
```

Compatible with: V2rayNG, Nekoray, Streisand, Shadowrocket, V2Box, V2rayN.

## Script flow

1. Check root, detect arch (amd64/arm64)
2. Install minimal deps (curl, unzip, jq)
3. Download latest xray-core from GitHub releases
4. Generate credentials via xray binary (UUID, x25519 keypair, short ID)
5. Write config to `/usr/local/etc/xray/config.json`
6. Create systemd service
7. Start service
8. Print connection summary + vless:// share link

## Files on server

| File | Purpose |
|------|---------|
| `/usr/local/bin/xray` | Xray binary |
| `/usr/local/etc/xray/config.json` | Server config (mode 600) |
| `/etc/systemd/system/xray.service` | systemd unit |
