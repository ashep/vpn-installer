#!/usr/bin/env bash
set -euo pipefail

# ─── Shadowsocks-rust + v2ray-plugin + Caddy installer ──────────────────────
# Tested on Ubuntu 22.04 / 24.04 (x86_64 and aarch64).
# Run as root on a fresh server whose domain already points to its IP.
# ─────────────────────────────────────────────────────────────────────────────

# ── Helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Pre-flight checks ───────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] || error "This script must be run as root."

case "$(uname -m)" in
    x86_64)  SS_ARCH="x86_64-unknown-linux-gnu"; V2RAY_ARCH="linux-amd64"; V2RAY_BIN="linux_amd64" ;;
    aarch64) SS_ARCH="aarch64-unknown-linux-gnu"; V2RAY_ARCH="linux-arm64"; V2RAY_BIN="linux_arm64" ;;
    *)       error "Unsupported architecture: $(uname -m)" ;;
esac

# ── Domain name ──────────────────────────────────────────────────────────────

read -rp "Enter the domain name (must already point to this server): " DOMAIN
[[ -n "$DOMAIN" ]] || error "Domain name cannot be empty."

# ── Install dependencies ────────────────────────────────────────────────────

info "Installing base packages..."
apt-get update -qq
apt-get install -y -qq curl tar jq debian-keyring debian-archive-keyring apt-transport-https > /dev/null

# ── Install Caddy ────────────────────────────────────────────────────────────

if ! command -v caddy &> /dev/null; then
    info "Installing Caddy..."
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
        > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y -qq caddy > /dev/null
else
    info "Caddy already installed, skipping."
fi

# ── Download shadowsocks-rust ────────────────────────────────────────────────

info "Fetching latest shadowsocks-rust release..."
SS_VERSION=$(curl -fsSL https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | jq -r '.tag_name')
SS_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_VERSION}/shadowsocks-${SS_VERSION}.${SS_ARCH}.tar.xz"

info "Downloading shadowsocks-rust ${SS_VERSION} (${SS_ARCH})..."
TMP_SS=$(mktemp -d)
curl -fsSL "$SS_URL" | tar -xJ -C "$TMP_SS"
install -m 755 "$TMP_SS/ssserver" /usr/local/bin/ssserver
rm -rf "$TMP_SS"
info "ssserver installed to /usr/local/bin/ssserver"

# ── Download v2ray-plugin ───────────────────────────────────────────────────

info "Fetching latest v2ray-plugin release..."
V2RAY_VERSION=$(curl -fsSL https://api.github.com/repos/shadowsocks/v2ray-plugin/releases/latest | jq -r '.tag_name')
V2RAY_URL="https://github.com/shadowsocks/v2ray-plugin/releases/download/${V2RAY_VERSION}/v2ray-plugin-${V2RAY_ARCH}-${V2RAY_VERSION}.tar.gz"

info "Downloading v2ray-plugin ${V2RAY_VERSION} (${V2RAY_ARCH})..."
TMP_V2=$(mktemp -d)
curl -fsSL "$V2RAY_URL" | tar -xz -C "$TMP_V2"
install -m 755 "$TMP_V2/v2ray-plugin_${V2RAY_BIN}" /usr/local/bin/v2ray-plugin
rm -rf "$TMP_V2"
info "v2ray-plugin installed to /usr/local/bin/v2ray-plugin"

# ── Generate credentials ────────────────────────────────────────────────────

PASSWORD=$(openssl rand -base64 32)
LOCAL_PORT=$(shuf -i 10000-60000 -n 1)
WS_PATH="/ws-$(openssl rand -hex 8)"

# ── Create system user ──────────────────────────────────────────────────────

if ! id shadowsocks &> /dev/null; then
    useradd -r -s /usr/sbin/nologin -M shadowsocks
    info "Created system user: shadowsocks"
fi

# ── Write shadowsocks config ────────────────────────────────────────────────

mkdir -p /etc/shadowsocks-rust
cat > /etc/shadowsocks-rust/config.json <<EOF
{
    "server": "127.0.0.1",
    "server_port": ${LOCAL_PORT},
    "password": "${PASSWORD}",
    "method": "chacha20-ietf-poly1305",
    "plugin": "v2ray-plugin",
    "plugin_opts": "server;path=${WS_PATH}"
}
EOF
chmod 600 /etc/shadowsocks-rust/config.json
chown shadowsocks:shadowsocks /etc/shadowsocks-rust/config.json
info "Shadowsocks config written to /etc/shadowsocks-rust/config.json"

# ── Write Caddyfile ──────────────────────────────────────────────────────────

cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    handle ${WS_PATH} {
        reverse_proxy localhost:${LOCAL_PORT}
    }

    handle {
        root * /var/www/html
        file_server
    }
}
EOF
info "Caddyfile written to /etc/caddy/Caddyfile"

# ── Write decoy page ────────────────────────────────────────────────────────

mkdir -p /var/www/html
cat > /var/www/html/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Daniel Morgan</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: Georgia, "Times New Roman", serif;
            min-height: 100vh; background: #fafaf8; color: #2c2c2c;
            display: flex; justify-content: center;
            padding: 4rem 1.5rem;
        }
        .page { max-width: 600px; width: 100%; }
        .avatar {
            width: 88px; height: 88px; border-radius: 50%;
            background: #b8c4b8; margin-bottom: 1.5rem;
            display: flex; align-items: center; justify-content: center;
            font-size: 2rem; color: #fff; font-family: sans-serif;
        }
        h1 { font-size: 1.6rem; font-weight: 600; margin-bottom: 0.3rem; }
        .subtitle { color: #777; font-size: 0.95rem; margin-bottom: 2rem; }
        .bio {
            line-height: 1.75; color: #444; margin-bottom: 2.5rem;
            font-size: 0.95rem;
        }
        .bio p { margin-bottom: 1rem; }
        .links { list-style: none; }
        .links li { margin-bottom: 0.6rem; }
        .links a {
            color: #4a6741; text-decoration: none;
            border-bottom: 1px solid #ccc;
            padding-bottom: 1px; font-size: 0.95rem;
        }
        .links a:hover { border-color: #4a6741; }
        footer {
            margin-top: 3rem; padding-top: 1.5rem;
            border-top: 1px solid #e8e8e4;
            color: #aaa; font-size: 0.8rem;
        }
    </style>
</head>
<body>
    <div class="page">
        <div class="avatar">DM</div>
        <h1>Daniel Morgan</h1>
        <p class="subtitle">Landscape photographer &amp; occasional writer</p>
        <div class="bio">
            <p>I spend most of my time outdoors with a camera, chasing light
            across mountain ridges and quiet valleys. Based in Colorado,
            though rarely home for long.</p>
            <p>Sometimes I write about the places I visit and the people I
            meet along the way. Nothing fancy, just notes from the road.</p>
        </div>
        <ul class="links">
            <li><a href="#">Selected photographs</a></li>
            <li><a href="#">Travel notes</a></li>
            <li><a href="#">Get in touch</a></li>
        </ul>
        <footer>&copy; 2025 Daniel Morgan</footer>
    </div>
</body>
</html>
HTMLEOF
info "Decoy page written to /var/www/html/index.html"

# ── Create systemd service ──────────────────────────────────────────────────

cat > /etc/systemd/system/shadowsocks-rust.service <<EOF
[Unit]
Description=Shadowsocks-rust Server
After=network.target

[Service]
Type=simple
User=shadowsocks
Group=shadowsocks
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
info "systemd service created: shadowsocks-rust.service"

# ── Start services ───────────────────────────────────────────────────────────

systemctl enable --now shadowsocks-rust
systemctl restart caddy
info "Services started."

# ── Print summary ────────────────────────────────────────────────────────────

CLIENT_PLUGIN_OPTS="tls;host=${DOMAIN};path=${WS_PATH}"
SS_USERINFO=$(python3 -c "import urllib.parse; print(urllib.parse.quote('chacha20-ietf-poly1305') + ':' + urllib.parse.quote('${PASSWORD}'))")
SS_URI="ss://${SS_USERINFO}@${DOMAIN}:443/?plugin=$(python3 -c "import urllib.parse; print(urllib.parse.quote('v2ray-plugin;${CLIENT_PLUGIN_OPTS}'))")#${DOMAIN}"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Shadowsocks + v2ray-plugin setup complete${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Server:       ${GREEN}${DOMAIN}${NC}"
echo -e "  Port:         ${GREEN}443${NC}"
echo -e "  Password:     ${GREEN}${PASSWORD}${NC}"
echo -e "  Cipher:       ${GREEN}chacha20-ietf-poly1305${NC}"
echo -e "  Plugin:       ${GREEN}v2ray-plugin${NC}"
echo -e "  Plugin opts:  ${GREEN}${CLIENT_PLUGIN_OPTS}${NC}"
echo ""
echo -e "  ${YELLOW}ss:// URI (for client import):${NC}"
echo -e "  ${GREEN}${SS_URI}${NC}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
