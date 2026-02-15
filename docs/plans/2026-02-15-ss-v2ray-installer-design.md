# Shadowsocks + v2ray-plugin + Caddy Installer — Design

## Overview

Single `install.sh` bash script for fresh Ubuntu (22.04/24.04) servers.

## Stack

- **shadowsocks-rust** (`ssserver`) — SS2022 proxy, binds `127.0.0.1:<random-port>`
- **v2ray-plugin** — websocket transport (plain, no TLS on server side)
- **Caddy** — TLS termination (auto Let's Encrypt), decoy website, reverse proxy

## Traffic Flow

```
Client --TLS--> Caddy:443 --WS--> ssserver:localhost
Browser --TLS--> Caddy:443 ---> static decoy page
```

## Decisions

| Choice | Value |
|--------|-------|
| SS implementation | shadowsocks-rust (GitHub releases) |
| Cipher | 2022-blake3-aes-128-gcm |
| TLS | Caddy (auto ACME) |
| Credentials | Auto-generated |
| Firewall | Not managed by script |
| Decoy | Simple static page via Caddy |

## Script Flow

1. Check root, detect arch (x86_64/aarch64)
2. Prompt for domain name
3. Install deps + Caddy (official apt repo)
4. Download ssserver + v2ray-plugin from GitHub
5. Generate password (16-byte base64), random local port, random WS path
6. Write config, Caddyfile, decoy page, systemd unit
7. Start services
8. Print connection summary + ss:// URI
