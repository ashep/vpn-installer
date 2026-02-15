# VLESS + Reality + XTLS Vision Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Shadowsocks + v2ray-plugin + Caddy installer with a single xray-core VLESS + Reality + XTLS Vision installer for bypassing Russian DPI.

**Architecture:** Single `install.sh` bash script that downloads xray-core, generates credentials (UUID, x25519 keypair, short ID), writes a VLESS+Reality config, creates a systemd service, and prints a `vless://` share link. No domain required — connects by server IP.

**Tech Stack:** Bash, xray-core (from GitHub releases), systemd

---

### Task 1: Rewrite install.sh — header, pre-flight, and architecture detection

**Files:**
- Modify: `install.sh` (full rewrite)

**Step 1: Replace the entire install.sh with the new header and pre-flight section**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─── VLESS + Reality + XTLS Vision (xray-core) installer ────────────────────
# Tested on Ubuntu 22.04 / 24.04 (x86_64 and aarch64).
# Run as root on a fresh server. No domain required.
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
    x86_64)  XRAY_ARCH="Xray-linux-64" ;;
    aarch64) XRAY_ARCH="Xray-linux-arm64-v8a" ;;
    *)       error "Unsupported architecture: $(uname -m)" ;;
esac
```

**Step 2: Verify syntax**

Run: `bash -n install.sh`
Expected: no output (clean parse)

**Step 3: Commit**

```bash
git add install.sh
git commit -m "Replace install.sh header with VLESS+Reality setup"
```

---

### Task 2: Add dependency installation and xray-core download

**Files:**
- Modify: `install.sh` (append after pre-flight section)

**Step 1: Add dependency install + xray download sections**

Append after the architecture detection:

```bash
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
```

**Step 2: Verify syntax**

Run: `bash -n install.sh`
Expected: no output (clean parse)

**Step 3: Commit**

```bash
git add install.sh
git commit -m "Add xray-core download and dependency installation"
```

---

### Task 3: Add credential generation

**Files:**
- Modify: `install.sh` (append after download section)

**Step 1: Add credential generation section**

```bash
# ── Generate credentials ────────────────────────────────────────────────────

info "Generating credentials..."
UUID=$(/usr/local/bin/xray uuid)
KEY_PAIR=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

DEST="www.microsoft.com"
SERVER_IP=$(curl -fsSL https://ifconfig.me)
```

**Step 2: Verify syntax**

Run: `bash -n install.sh`
Expected: no output

**Step 3: Commit**

```bash
git add install.sh
git commit -m "Add credential generation (UUID, x25519, shortId)"
```

---

### Task 4: Add xray config, systemd service, and service start

**Files:**
- Modify: `install.sh` (append after credentials section)

**Step 1: Add config, systemd unit, and service start**

```bash
# ── Create system user ──────────────────────────────────────────────────────

if ! id xray &> /dev/null; then
    useradd -r -s /usr/sbin/nologin -M xray
    info "Created system user: xray"
fi

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
info "systemd service created: xray.service"

# ── Start service ───────────────────────────────────────────────────────────

systemctl enable --now xray
info "Xray service started."
```

Note: Xray runs as root because it needs to bind to port 443. The config file is mode 600 to protect the private key.

**Step 2: Verify syntax**

Run: `bash -n install.sh`
Expected: no output

**Step 3: Commit**

```bash
git add install.sh
git commit -m "Add xray config, systemd service, and service start"
```

---

### Task 5: Add connection summary and vless:// share link

**Files:**
- Modify: `install.sh` (append after service start)

**Step 1: Add the summary output**

```bash
# ── Print summary ────────────────────────────────────────────────────────────

VLESS_LINK="vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rpc-vision&type=tcp&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#vless-reality"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  VLESS + Reality + XTLS Vision setup complete${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Server IP:    ${GREEN}${SERVER_IP}${NC}"
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
echo -e "  ${YELLOW}vless:// share link (for client import):${NC}"
echo -e "  ${GREEN}${VLESS_LINK}${NC}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
```

**Step 2: Verify syntax**

Run: `bash -n install.sh`
Expected: no output

**Step 3: Commit**

```bash
git add install.sh
git commit -m "Add connection summary and vless:// share link output"
```

---

### Task 6: Rewrite README.md

**Files:**
- Modify: `README.md` (full rewrite)

**Step 1: Replace README.md with updated documentation**

Full content for README.md covering:

- Title: VLESS + Reality + XTLS Vision Installer
- How it works (Reality explanation, traffic flow diagram)
- Prerequisites (fresh Ubuntu, root, port 443 — no domain needed)
- Installation (one-liner from GitHub)
- Client setup for all platforms:
  - iOS: Streisand, Shadowrocket, V2Box
  - Android: V2rayNG, NekoBox
  - Desktop: Nekoray (Win/Mac/Linux), V2rayN (Windows)
  - All use the vless:// share link
- Manual client config table (server IP, port, UUID, flow, security, SNI, public key, short ID, fingerprint)
- Server management (systemctl commands, journalctl)
- Troubleshooting (port in use, xray won't start, client connects but no internet)
- Security notes
- What gets installed table

**Step 2: Commit**

```bash
git add README.md
git commit -m "Rewrite README for VLESS + Reality + XTLS Vision"
```

---

### Task 7: Final review and cleanup

**Step 1: Review the complete install.sh for correctness**

Read through the full script and verify:
- All variable references are correct
- No leftover Shadowsocks/Caddy references
- Bash syntax is clean

**Step 2: Verify the old design doc is still present (for history) and new one is committed**

**Step 3: Final commit if any fixes needed**
