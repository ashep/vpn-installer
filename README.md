# VLESS + Reality + XTLS Vision Installer

A one-command installer for [xray-core](https://github.com/XTLS/Xray-core) with VLESS + Reality + XTLS Vision on a fresh Ubuntu server. Designed to bypass deep packet inspection. No domain or TLS certificate required — connect by server IP.

## How It Works

```
Client ──Reality TLS──▶ Xray (:443) ──VLESS──▶ Internet
Probe  ──TLS hello──▶  Xray (:443) ──forward──▶ www.microsoft.com (real cert)
```

- Xray listens on port 443 and performs a Reality TLS handshake, impersonating www.microsoft.com.
- Only clients with the correct UUID, public key, and short ID can authenticate.
- Active probes are forwarded to the real microsoft.com and see its real TLS certificate.
- XTLS Vision flow prevents length-based traffic analysis.
- No domain or TLS certificate required — connect by server IP.

## Prerequisites

- Fresh **Ubuntu 22.04 or 24.04** (x86_64 or aarch64)
- **Root access**
- Port **443** must be open and not in use
- **No domain required**

## Installation

One-liner:

```bash
ssh root@your-server
bash <(curl -fsSL https://raw.githubusercontent.com/ashep/vpn-installer/main/install.sh)
```

Or download and run:

```bash
scp install.sh root@your-server:~
ssh root@your-server
bash install.sh
```

What the script does:

1. Detects architecture
2. Installs dependencies and downloads latest xray-core
3. Generates UUID, x25519 keypair, and short ID
4. Configures VLESS + Reality + XTLS Vision
5. Starts the xray service
6. Prints connection details and share link

Example output:

```
════════════════════════════════════════════════════════════
  VLESS + Reality + XTLS Vision setup complete
════════════════════════════════════════════════════════════

  Server:       203.0.113.1
  Port:         443
  Protocol:     VLESS
  UUID:         <random uuid>
  Flow:         xtls-rprx-vision
  Security:     Reality
  SNI:          www.microsoft.com
  Public Key:   <random key>
  Short ID:     <random hex>
  Fingerprint:  chrome

  vless:// share link:
  vless://...

════════════════════════════════════════════════════════════
```

## Client Setup

Use the `vless://` share link printed by the installer. Most clients can import it directly.

### Recommended clients

| Platform | Client |
|----------|--------|
| iOS | [Streisand](https://apps.apple.com/app/streisand/id6450534064), [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) (paid), [V2Box](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) |
| Android | [V2rayNG](https://github.com/2dust/v2rayNG), [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) |
| Windows | [V2rayN](https://github.com/2dust/v2rayN), [Nekoray](https://github.com/MatsuriDayo/nekoray) |
| macOS | [V2rayU](https://github.com/yanue/V2rayU), [Nekoray](https://github.com/MatsuriDayo/nekoray) |
| Linux | [Nekoray](https://github.com/MatsuriDayo/nekoray), or xray-core directly |

### Manual client configuration

If a client doesn't support share link import, enter these settings manually:

| Field | Value |
|-------|-------|
| Address | Your server IP |
| Port | 443 |
| UUID | From installer output |
| Flow | xtls-rprx-vision |
| Encryption | none |
| Network | tcp |
| Security | reality |
| SNI | www.microsoft.com |
| Fingerprint | chrome |
| Public Key | From installer output |
| Short ID | From installer output |

### Linux command-line example

```bash
# Install xray-core on your local machine, then create config:
cat > ~/xray-client.json <<EOF
{
    "inbounds": [{
        "listen": "127.0.0.1",
        "port": 1080,
        "protocol": "socks"
    }],
    "outbounds": [{
        "protocol": "vless",
        "settings": {
            "vnext": [{
                "address": "YOUR_SERVER_IP",
                "port": 443,
                "users": [{
                    "id": "YOUR_UUID",
                    "flow": "xtls-rprx-vision",
                    "encryption": "none"
                }]
            }]
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "serverName": "www.microsoft.com",
                "fingerprint": "chrome",
                "publicKey": "YOUR_PUBLIC_KEY",
                "shortId": "YOUR_SHORT_ID"
            }
        }
    }]
}
EOF

xray run -c ~/xray-client.json
```

This starts a local SOCKS5 proxy on `127.0.0.1:1080`.

## Server Management

### Service commands

```bash
systemctl status xray
systemctl restart xray
systemctl stop xray
journalctl -u xray -f
```

### Verifying the server

```bash
# Check service is active
systemctl is-active xray

# Verify xray is listening on 443
ss -tlnp | grep xray

# Test that probes see microsoft.com (from another machine)
curl -vI --resolve www.microsoft.com:443:YOUR_SERVER_IP https://www.microsoft.com 2>&1 | grep "subject:"
# Should show Microsoft's real certificate
```

### Configuration files

| File | Purpose |
|------|---------|
| `/usr/local/bin/xray` | Xray binary |
| `/usr/local/etc/xray/config.json` | Server config (UUID, keys) |
| `/etc/systemd/system/xray.service` | systemd unit |

### Updating xray-core

Re-run the installer. It will download the latest version and regenerate credentials.

## Troubleshooting

### Xray won't start

- Check logs: `journalctl -u xray --no-pager -n 50`
- Verify config is valid JSON: `jq . /usr/local/etc/xray/config.json`
- Make sure port 443 is not in use: `ss -tlnp | grep :443`

### Client connects but no internet

- Check xray logs for errors: `journalctl -u xray --no-pager -n 50`
- Verify DNS works on the server: `dig example.com`
- Make sure the server itself has internet access: `curl -I https://example.com`
- Some networks block outgoing traffic from VPS — check with your hosting provider

### Client can't connect at all

- Verify server IP is correct
- Make sure port 443 is not blocked by firewall
- Check UUID, public key, and short ID match exactly
- Ensure flow is set to `xtls-rprx-vision`
- Ensure fingerprint is set to `chrome`

## Security Notes

- Config file at `/usr/local/etc/xray/config.json` is mode 600 (root only).
- Xray runs as root (required for port 443 binding).
- No TLS certificate stored on server — Reality impersonates the destination site.
- The script does not configure a firewall. Set one up yourself (e.g., UFW) allowing ports 22 and 443.

## What Gets Installed

| Component | Source | Location |
|-----------|--------|----------|
| xray-core | [GitHub releases](https://github.com/XTLS/Xray-core/releases) | `/usr/local/bin/xray` |

System packages installed: `curl`, `unzip`, `jq`.
