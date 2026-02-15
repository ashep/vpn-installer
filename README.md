# Shadowsocks + v2ray-plugin + Caddy Installer

A one-command installer that sets up a [Shadowsocks](https://shadowsocks.org/) proxy with [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin) websocket transport and a [Caddy](https://caddyserver.com/) reverse proxy on a fresh Ubuntu server.

Traffic is disguised as regular HTTPS to a normal website, making it resistant to deep packet inspection and active probing.

## How It Works

```
Client ──TLS──▶ Caddy (:443) ──websocket──▶ ssserver (localhost)
Browser ──TLS──▶ Caddy (:443) ──▶ static decoy page
```

- **Caddy** listens on port 443, terminates TLS (automatic Let's Encrypt), and serves a static "Under Construction" page to regular visitors.
- Requests to a secret randomized websocket path are proxied to **ssserver** on localhost.
- **ssserver** (shadowsocks-rust) handles the SOCKS5 proxy with the `chacha20-ietf-poly1305` cipher (Shadowsocks 2022 protocol).
- **v2ray-plugin** provides the websocket transport layer between client and server.

Anyone inspecting the server sees a valid HTTPS website. The proxy traffic blends in as normal websocket connections.

## Prerequisites

- A fresh **Ubuntu 22.04 or 24.04** server (x86_64 or aarch64)
- A **domain name** with a DNS A record already pointing to the server's IP
- **Root access**
- Ports **80** and **443** must be open and not in use (Caddy needs both for ACME certificate issuance)

## Installation

### 1. Point your domain to the server

Create a DNS A record for your domain (e.g., `proxy.example.com`) pointing to your server's public IP address. Wait for DNS propagation (usually a few minutes).

Verify it resolves correctly:

```bash
dig +short proxy.example.com
# Should return your server's IP
```

### 2. Run the installer

The quickest way — run it directly on the server without downloading anything first:

```bash
ssh root@your-server
bash <(curl -fsSL https://raw.githubusercontent.com/ashep/vpn-installer/main/install.sh)
```

Alternatively, download and run it in two steps:

```bash
scp install.sh root@your-server:~
ssh root@your-server
bash install.sh
```

The script will:

1. Ask for your domain name
2. Install dependencies and Caddy
3. Download the latest shadowsocks-rust and v2ray-plugin from GitHub
4. Generate a random password, local port, and websocket path
5. Configure everything and start the services
6. Print your connection details

### 3. Save the output

At the end, the script prints everything you need to configure your client:

```
════════════════════════════════════════════════════════════
  Shadowsocks + v2ray-plugin setup complete
════════════════════════════════════════════════════════════

  Server:       proxy.example.com
  Port:         443
  Password:     <random base64 string>
  Cipher:       chacha20-ietf-poly1305
  Plugin:       v2ray-plugin
  Plugin opts:  tls;host=proxy.example.com;path=/ws-<random>

  ss:// URI (for client import):
  ss://...@proxy.example.com:443/?plugin=...#proxy.example.com

════════════════════════════════════════════════════════════
```

Save this information securely. The password is stored on the server in `/etc/shadowsocks-rust/config.json` (readable only by the `shadowsocks` user).

## Client Setup

Use the `ss://` URI printed by the installer to import the server into your client. Alternatively, configure it manually with the values from the output.

### Shadowsocks clients with v2ray-plugin support

| Platform | Client |
|----------|--------|
| Windows | [Shadowsocks for Windows](https://github.com/shadowsocks/shadowsocks-windows) + [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin/releases) |
| macOS | [ShadowsocksX-NG](https://github.com/shadowsocks/ShadowsocksX-NG) |
| Linux | [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust) (`sslocal`) + [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin/releases) |
| Android | [Shadowsocks Android](https://github.com/shadowsocks/shadowsocks-android) + [v2ray-plugin Android](https://github.com/nicxlau/nicxlau.github.io/tree/master) |
| iOS | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) (paid) or [Potatso Lite](https://apps.apple.com/app/potatso-lite/id1239860606) |

### Manual client configuration

If your client doesn't support `ss://` URI import, enter these settings manually:

| Field | Value |
|-------|-------|
| Server | Your domain (e.g., `proxy.example.com`) |
| Port | `443` |
| Password | The password from the installer output |
| Cipher / Encryption | `chacha20-ietf-poly1305` |
| Plugin | `v2ray-plugin` |
| Plugin Options | `tls;host=<your-domain>;path=<your-ws-path>` |

### Linux client example (sslocal)

```bash
# Install shadowsocks-rust and v2ray-plugin on your local machine,
# then create a local config:

cat > ~/ss-local.json <<EOF
{
    "server": "proxy.example.com",
    "server_port": 443,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "YOUR_PASSWORD_HERE",
    "method": "chacha20-ietf-poly1305",
    "plugin": "v2ray-plugin",
    "plugin_opts": "tls;host=proxy.example.com;path=/ws-YOUR_PATH_HERE"
}
EOF

sslocal -c ~/ss-local.json
```

This starts a local SOCKS5 proxy on `127.0.0.1:1080`. Configure your browser or system to use it.

## Server Management

### Service commands

```bash
# Check status
systemctl status shadowsocks-rust
systemctl status caddy

# View logs
journalctl -u shadowsocks-rust -f
journalctl -u caddy -f

# Restart services
systemctl restart shadowsocks-rust
systemctl restart caddy

# Stop services
systemctl stop shadowsocks-rust
systemctl stop caddy
```

### Configuration files

| File | Purpose |
|------|---------|
| `/etc/shadowsocks-rust/config.json` | Shadowsocks server config (password, port, cipher) |
| `/etc/caddy/Caddyfile` | Caddy reverse proxy and decoy site config |
| `/var/www/html/index.html` | Decoy website page |
| `/etc/systemd/system/shadowsocks-rust.service` | systemd unit for ssserver |

### Changing the password

```bash
# Generate a new random password
NEW_PASS=$(openssl rand -base64 32)
echo "New password: $NEW_PASS"

# Edit the config
nano /etc/shadowsocks-rust/config.json
# Replace the "password" value

# Restart
systemctl restart shadowsocks-rust
```

Update your client with the new password.

### Customizing the decoy page

Edit `/var/www/html/index.html` with any static HTML you like. No restart needed — Caddy serves it directly.

For a more convincing decoy, consider copying a simple template from a real website.

### Updating binaries

To update shadowsocks-rust and v2ray-plugin to the latest versions, re-run the installer. It will download the latest releases and overwrite the existing binaries. The config files will also be regenerated (new password/port/path), so save the new output and update your clients.

## Troubleshooting

### Caddy fails to start / certificate errors

- Verify your domain's DNS A record points to the server: `dig +short yourdomain.com`
- Make sure ports 80 and 443 are not blocked by a firewall or used by another service: `ss -tlnp | grep -E ':80|:443'`
- Check Caddy logs: `journalctl -u caddy --no-pager -n 50`

### Shadowsocks won't start

- Check logs: `journalctl -u shadowsocks-rust --no-pager -n 50`
- Verify the config is valid JSON: `jq . /etc/shadowsocks-rust/config.json`
- Make sure v2ray-plugin is in PATH: `which v2ray-plugin`

### Can connect but no internet access

- The server may need IP forwarding and NAT. This is usually already configured on VPS providers, but if not:

```bash
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

Replace `eth0` with your server's main network interface (check with `ip route show default`).

### Client connects but immediately disconnects

- Make sure the cipher on the client matches exactly: `chacha20-ietf-poly1305`
- Make sure the password is copied exactly (no trailing spaces)
- Verify the plugin options include `tls`, the correct `host`, and the correct `path`

## Security Notes

- The config file at `/etc/shadowsocks-rust/config.json` is readable only by the `shadowsocks` user (mode 600).
- ssserver runs as a dedicated `shadowsocks` system user with no login shell and no home directory.
- ssserver only binds to `127.0.0.1` — it is not directly reachable from the internet. All external traffic goes through Caddy.
- TLS certificates are automatically obtained and renewed by Caddy.
- The script does **not** configure a firewall. You should set one up yourself (e.g., UFW) allowing ports 22, 80, and 443.

## What Gets Installed

| Component | Source | Location |
|-----------|--------|----------|
| shadowsocks-rust (`ssserver`) | [GitHub releases](https://github.com/shadowsocks/shadowsocks-rust/releases) | `/usr/local/bin/ssserver` |
| v2ray-plugin | [GitHub releases](https://github.com/shadowsocks/v2ray-plugin/releases) | `/usr/local/bin/v2ray-plugin` |
| Caddy | [Official apt repo](https://caddyserver.com/docs/install#debian-ubuntu-raspbian) | System package |

System packages installed: `curl`, `tar`, `jq`, `debian-keyring`, `debian-archive-keyring`, `apt-transport-https`.
