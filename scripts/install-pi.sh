#!/usr/bin/env bash
#
# Proxmox Wallboard — Raspberry Pi installer
#
# Interactive installer that:
#   1. Installs system dependencies (Node.js 22, git, build tools, whiptail)
#   2. Installs npm packages and builds the app
#   3. Prompts for Proxmox connection + wallboard settings and writes .env.local
#   4. Configures display orientation via /boot/firmware/config.txt
#   5. Optionally creates a systemd service to auto-start the wallboard
#   6. Optionally configures Chromium kiosk autostart
#
# Usage:
#   curl -fsSL ... | bash          (not supported — needs a TTY)
#   cd proxmox-wallboard && sudo bash scripts/install-pi.sh
#

set -euo pipefail

# ─── Colors / helpers ─────────────────────────────────────────────────────────
C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BOLD=$'\033[1m'

info()  { echo "${C_GREEN}[✓]${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}[!]${C_RESET} $*"; }
error() { echo "${C_RED}[✗]${C_RESET} $*" >&2; }
step()  { echo; echo "${C_BOLD}── $* ──${C_RESET}"; }

die() { error "$*"; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run with sudo (installs packages + edits /boot/firmware/config.txt)."
  fi
}

# The user who invoked sudo — we want npm / the app to live in their home, not root's
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Resolve the project directory (the parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Preflight ────────────────────────────────────────────────────────────────
require_root

step "Proxmox Wallboard — Pi Installer"
info "Project dir: $PROJECT_DIR"
info "Install user: $REAL_USER ($REAL_HOME)"

if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
  die "Could not find package.json in $PROJECT_DIR — run this from the cloned repo."
fi

# ─── System packages ──────────────────────────────────────────────────────────
step "Installing system dependencies"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  curl \
  ca-certificates \
  git \
  build-essential \
  whiptail >/dev/null

# Node.js 22 (NodeSource)
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -c2- | cut -d. -f1)" -lt 22 ]]; then
  info "Installing Node.js 22 via NodeSource"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
else
  info "Node.js $(node -v) already installed"
fi

info "Node: $(node -v)  npm: $(npm -v)"

# ─── Interactive config prompts ───────────────────────────────────────────────
step "Wallboard configuration"

ENV_FILE="$PROJECT_DIR/.env.local"

# Load existing values (if any) as defaults, so re-running the installer doesn't nuke config
default() {
  local key="$1" fallback="$2"
  if [[ -f "$ENV_FILE" ]]; then
    local v
    v=$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)
    if [[ -n "$v" ]]; then echo "$v"; return; fi
  fi
  echo "$fallback"
}

PVE_HOST=$(whiptail --title "Proxmox Host" --inputbox \
  "Proxmox VE hostname or IP address:" 10 70 "$(default PVE_HOST "192.168.1.100")" \
  3>&1 1>&2 2>&3)

PVE_PORT=$(whiptail --title "Proxmox Port" --inputbox \
  "Proxmox VE API port:" 10 70 "$(default PVE_PORT "8006")" \
  3>&1 1>&2 2>&3)

PVE_NODE=$(whiptail --title "Proxmox Node" --inputbox \
  "Node name (as shown in the PVE web UI):" 10 70 "$(default PVE_NODE "pve")" \
  3>&1 1>&2 2>&3)

AUTH_METHOD=$(whiptail --title "Authentication" --menu \
  "How should the wallboard authenticate to Proxmox?" 12 70 2 \
  "token"    "API token (recommended)" \
  "password" "Username + password" \
  3>&1 1>&2 2>&3)

if [[ "$AUTH_METHOD" == "token" ]]; then
  PVE_TOKEN_ID=$(whiptail --title "Token ID" --inputbox \
    "API token ID (e.g. wallboard@pve!wallboard):" 10 70 \
    "$(default PVE_TOKEN_ID "wallboard@pve!wallboard")" \
    3>&1 1>&2 2>&3)
  PVE_TOKEN_SECRET=$(whiptail --title "Token Secret" --passwordbox \
    "API token secret (UUID):" 10 70 "" \
    3>&1 1>&2 2>&3)
else
  PVE_USER=$(whiptail --title "PVE User" --inputbox \
    "Proxmox user (e.g. root@pam):" 10 70 \
    "$(default PVE_USER "root@pam")" 3>&1 1>&2 2>&3)
  PVE_PASS=$(whiptail --title "PVE Password" --passwordbox \
    "Password:" 10 70 "" 3>&1 1>&2 2>&3)
fi

TITLE=$(whiptail --title "Wallboard Title" --inputbox \
  "Title shown in the header:" 10 70 \
  "$(default NEXT_PUBLIC_TITLE "Proxmox Wallboard")" 3>&1 1>&2 2>&3)

POLL_INTERVAL=$(whiptail --title "Poll Interval" --inputbox \
  "How often to refresh Proxmox data (seconds):" 10 70 \
  "$(default NEXT_PUBLIC_POLL_INTERVAL "10")" 3>&1 1>&2 2>&3)

ROTATE_INTERVAL=$(whiptail --title "Rotate Interval" --inputbox \
  "How often to rotate guest cards (seconds):" 10 70 \
  "$(default NEXT_PUBLIC_ROTATE_INTERVAL "8")" 3>&1 1>&2 2>&3)

# ─── Display orientation ──────────────────────────────────────────────────────
step "Display orientation"

ROTATION=$(whiptail --title "Screen Orientation" --menu \
  "Pick display rotation (applied at the KMS level via /boot/firmware/config.txt):" 15 70 4 \
  "0" "Normal (landscape)" \
  "1" "90°  — rotated right (portrait)" \
  "2" "180° — upside down" \
  "3" "270° — rotated left (portrait)" \
  3>&1 1>&2 2>&3)

CONFIG_TXT="/boot/firmware/config.txt"
[[ -f "$CONFIG_TXT" ]] || CONFIG_TXT="/boot/config.txt"

if [[ -f "$CONFIG_TXT" ]]; then
  # Remove any existing display_hdmi_rotate / display_lcd_rotate lines, then append fresh one
  sed -i '/^display_hdmi_rotate=/d; /^display_lcd_rotate=/d' "$CONFIG_TXT"
  echo "display_hdmi_rotate=$ROTATION" >> "$CONFIG_TXT"
  info "Set display_hdmi_rotate=$ROTATION in $CONFIG_TXT (takes effect on next reboot)"
else
  warn "Could not find $CONFIG_TXT — skipping display rotation (not a Raspberry Pi?)"
fi

# ─── Write .env.local ─────────────────────────────────────────────────────────
step "Writing .env.local"

cat > "$ENV_FILE" <<EOF
# ── Proxmox Connection ──
PVE_HOST=$PVE_HOST
PVE_PORT=$PVE_PORT
PVE_NODE=$PVE_NODE

PVE_AUTH_METHOD=$AUTH_METHOD
EOF

if [[ "$AUTH_METHOD" == "token" ]]; then
  cat >> "$ENV_FILE" <<EOF
PVE_TOKEN_ID=$PVE_TOKEN_ID
PVE_TOKEN_SECRET=$PVE_TOKEN_SECRET
EOF
else
  cat >> "$ENV_FILE" <<EOF
PVE_USER=$PVE_USER
PVE_PASS=$PVE_PASS
EOF
fi

cat >> "$ENV_FILE" <<EOF

# ── Wallboard Settings ──
NEXT_PUBLIC_TITLE=$TITLE
NEXT_PUBLIC_POLL_INTERVAL=$POLL_INTERVAL
NEXT_PUBLIC_ROTATE_INTERVAL=$ROTATE_INTERVAL

# Allow self-signed certs from Proxmox
NODE_TLS_REJECT_UNAUTHORIZED=0
EOF

chown "$REAL_USER:$REAL_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"
info "Wrote $ENV_FILE"

# ─── Install + build ──────────────────────────────────────────────────────────
step "Installing npm packages and building"

# Run as the real user so node_modules and .next aren't owned by root
if [[ -f "$PROJECT_DIR/package-lock.json" ]]; then
  sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm ci"
else
  sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm install"
fi
sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm run build"

# ─── Optional: systemd service ────────────────────────────────────────────────
if whiptail --title "Auto-start" --yesno \
  "Create a systemd service to run the wallboard on boot?" 10 70; then

  SERVICE_FILE="/etc/systemd/system/proxmox-wallboard.service"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Proxmox Wallboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$REAL_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable proxmox-wallboard.service >/dev/null
  systemctl restart proxmox-wallboard.service
  info "Installed and started proxmox-wallboard.service"
fi

# ─── Optional: Chromium kiosk autostart ───────────────────────────────────────
if whiptail --title "Kiosk mode" --yesno \
  "Configure Chromium to launch in kiosk mode at login and display the wallboard?\n\n(Requires Raspberry Pi OS with a desktop and auto-login enabled.)" 12 70; then

  # Bookworm uses labwc/wayfire; Bullseye uses LXDE. Cover both by writing a
  # desktop autostart entry in the user's ~/.config/autostart — most DEs honor it.
  AUTOSTART_DIR="$REAL_HOME/.config/autostart"
  sudo -u "$REAL_USER" mkdir -p "$AUTOSTART_DIR"

  cat > "$AUTOSTART_DIR/proxmox-wallboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Proxmox Wallboard Kiosk
Exec=sh -c 'sleep 10 && chromium-browser --noerrdialogs --disable-infobars --kiosk http://localhost:3000'
X-GNOME-Autostart-enabled=true
EOF

  chown -R "$REAL_USER:$REAL_USER" "$AUTOSTART_DIR"
  info "Configured Chromium kiosk autostart at $AUTOSTART_DIR/proxmox-wallboard.desktop"

  # Disable screen blanking — annoying for a wallboard
  if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_blanking 1 || true
    info "Disabled screen blanking via raspi-config"
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
step "Install complete"
cat <<EOF

  ${C_GREEN}✓${C_RESET} Dependencies installed
  ${C_GREEN}✓${C_RESET} .env.local written to $ENV_FILE
  ${C_GREEN}✓${C_RESET} App built

  Start manually:   cd $PROJECT_DIR && npm start
  Or via service:   sudo systemctl status proxmox-wallboard

  ${C_YELLOW}Reboot required${C_RESET} for the display rotation change to take effect:
    sudo reboot

EOF
