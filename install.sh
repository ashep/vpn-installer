#!/usr/bin/env bash
set -euo pipefail

# ─── VLESS + Reality + XTLS Vision (xray-core) installer ────────────────────
# Tested on Ubuntu 22.04 / 24.04 (x86_64 and aarch64).
# Run as root on a fresh server. No domain required.
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "This script must be run as root."

case "$(uname -m)" in
    x86_64)  XRAY_ARCH="Xray-linux-64" ;;
    aarch64) XRAY_ARCH="Xray-linux-arm64-v8a" ;;
    *)       error "Unsupported architecture: $(uname -m)" ;;
esac

# ── Install dependencies ────────────────────────────────────────────────────

info "Installing base packages..."
apt-get update -qq
apt-get install -y -qq curl unzip jq > /dev/null

# ── Download xray-core ──────────────────────────────────────────────────────

info "Fetching latest xray-core release..."
XRAY_VERSION=$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${XRAY_ARCH}.zip"

info "Downloading xray-core ${XRAY_VERSION} (${XRAY_ARCH})..."
TMP_XRAY=$(mktemp -d)
curl -fsSL "$XRAY_URL" -o "${TMP_XRAY}/xray.zip"
unzip -q "${TMP_XRAY}/xray.zip" -d "$TMP_XRAY"
install -m 755 "$TMP_XRAY/xray" /usr/local/bin/xray
rm -rf "$TMP_XRAY"
info "xray installed to /usr/local/bin/xray"

# ── Generate credentials ────────────────────────────────────────────────────

info "Generating credentials..."
UUID=$(/usr/local/bin/xray uuid)
KEY_PAIR=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

DEST="www.microsoft.com"
SERVER_IP=$(curl -fsSL https://ifconfig.me)

# ── Write xray config ──────────────────────────────────────────────────────

mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rpc-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "${DEST}:443",
                    "serverNames": [
                        "${DEST}"
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "${SHORT_ID}"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom"
        }
    ]
}
EOF
chmod 600 /usr/local/etc/xray/config.json
info "Xray config written to /usr/local/etc/xray/config.json"

# ── Create systemd service ──────────────────────────────────────────────────

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -c /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xray
info "Xray service started."

# ── Print summary ────────────────────────────────────────────────────────────

VLESS_URI="vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rpc-vision&type=tcp&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#vless-reality"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  VLESS + Reality + XTLS Vision setup complete${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Server:       ${GREEN}${SERVER_IP}${NC}"
echo -e "  Port:         ${GREEN}443${NC}"
echo -e "  Protocol:     ${GREEN}VLESS${NC}"
echo -e "  UUID:         ${GREEN}${UUID}${NC}"
echo -e "  Flow:         ${GREEN}xtls-rpc-vision${NC}"
echo -e "  Security:     ${GREEN}Reality${NC}"
echo -e "  SNI:          ${GREEN}${DEST}${NC}"
echo -e "  Public Key:   ${GREEN}${PUBLIC_KEY}${NC}"
echo -e "  Short ID:     ${GREEN}${SHORT_ID}${NC}"
echo -e "  Fingerprint:  ${GREEN}chrome${NC}"
echo ""
echo -e "  ${YELLOW}vless:// share link:${NC}"
echo -e "  ${GREEN}${VLESS_URI}${NC}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
