#!/usr/bin/env bash
#
# Proxmox Wallboard — Raspberry Pi installer
#
# Fully automated setup: after this script finishes and the Pi reboots,
# the wallboard service starts, Chromium opens in kiosk mode, and you're
# looking at your wallboard.
#
# Usage:
#   cd Proxmox-Status-Wallboard && sudo bash scripts/install-pi.sh
#

set -euo pipefail

# ─── Colors / helpers ─────────────────────────────────────────────────────────
C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_CYAN=$'\033[36m'
C_DIM=$'\033[2m'
C_BOLD=$'\033[1m'

info()  { echo "${C_GREEN}  ✓${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}  !${C_RESET} $*"; }
error() { echo "${C_RED}  ✗${C_RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# ─── Progress display helpers ─────────────────────────────────────────────────

# Prints a numbered step header with a box drawing border
STEP_NUM=0
TOTAL_STEPS=9
step() {
  STEP_NUM=$((STEP_NUM + 1))
  echo
  echo "${C_BOLD}${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
  echo "${C_BOLD}${C_CYAN}│  Step ${STEP_NUM}/${TOTAL_STEPS}: $*$(printf '%*s' $((43 - ${#1})) '')│${C_RESET}"
  echo "${C_BOLD}${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
}

# Spinner: run a command in the background and show a spinner + message
# Usage: spin "message" command arg1 arg2 ...
spin() {
  local msg="$1"; shift
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local pid logfile
  logfile=$(mktemp /tmp/wallboard-install-XXXXXX.log)

  "$@" > "$logfile" 2>&1 &
  pid=$!

  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${C_CYAN}%s${C_RESET} %s" "${frames[$((i % ${#frames[@]}))]}" "$msg"
    sleep 0.1
    i=$((i + 1))
  done

  wait "$pid"
  local exit_code=$?
  printf "\r"

  if [[ $exit_code -eq 0 ]]; then
    info "$msg"
  else
    error "$msg — failed (see log below)"
    echo "${C_DIM}"
    tail -20 "$logfile"
    echo "${C_RESET}"
    rm -f "$logfile"
    exit $exit_code
  fi
  rm -f "$logfile"
}

# Progress bar using whiptail gauge
# Pipe percentages to it: (echo 50; echo 100) | gauge "title"
gauge() {
  whiptail --title "$1" --gauge "" 7 70 0
}

# ─── Preflight ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  die "This script must be run with sudo."
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

clear
echo
echo "${C_BOLD}${C_GREEN}  ╔═══════════════════════════════════════════════════════════╗${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ║          Proxmox Wallboard — Pi Installer                ║${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ╚═══════════════════════════════════════════════════════════╝${C_RESET}"
echo
echo "  ${C_DIM}Project dir :${C_RESET} $PROJECT_DIR"
echo "  ${C_DIM}Install user:${C_RESET} $REAL_USER ($REAL_HOME)"
echo "  ${C_DIM}Steps       :${C_RESET} $TOTAL_STEPS"
echo

if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
  die "Could not find package.json in $PROJECT_DIR — run this from the cloned repo."
fi

sleep 1

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: System packages
# ═══════════════════════════════════════════════════════════════════════════════
step "Installing system packages"

export DEBIAN_FRONTEND=noninteractive

echo "  ${C_DIM}Updating package lists...${C_RESET}"
spin "Updating apt package lists" apt-get update -qq

# Install packages one group at a time for clear progress
{
  echo "10"; echo "# Installing core tools (curl, git, build-essential)..."
  apt-get install -y -qq curl ca-certificates git build-essential whiptail >/dev/null 2>&1

  echo "40"; echo "# Installing vim..."
  apt-get install -y -qq vim >/dev/null 2>&1

  echo "55"; echo "# Installing unclutter (hides mouse cursor)..."
  apt-get install -y -qq unclutter >/dev/null 2>&1

  echo "75"; echo "# Installing Chromium browser..."
  apt-get install -y -qq chromium-browser >/dev/null 2>&1 || \
    apt-get install -y -qq chromium >/dev/null 2>&1 || true

  echo "100"; echo "# Done!"
} | gauge "Installing system packages"

info "Installed: curl, git, build-essential, vim, unclutter, chromium"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Node.js
# ═══════════════════════════════════════════════════════════════════════════════
step "Installing Node.js"

if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -c2- | cut -d. -f1)" -lt 22 ]]; then
  {
    echo "20"; echo "# Adding NodeSource repository..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1

    echo "60"; echo "# Installing Node.js 22..."
    apt-get install -y -qq nodejs >/dev/null 2>&1

    echo "100"; echo "# Done!"
  } | gauge "Installing Node.js 22"
  info "Installed Node.js 22 via NodeSource"
else
  info "Node.js $(node -v) already installed — skipping"
fi

echo "  ${C_DIM}Node: $(node -v)  npm: $(npm -v)${C_RESET}"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Wallboard configuration (interactive prompts)
# ═══════════════════════════════════════════════════════════════════════════════
step "Wallboard configuration"

echo "  ${C_DIM}You'll now be asked a series of questions to configure the wallboard.${C_RESET}"
echo "  ${C_DIM}Press Cancel at any prompt to abort the installer.${C_RESET}"
sleep 1

ENV_FILE="$PROJECT_DIR/.env.local"

# Load existing values as defaults so re-running the installer preserves config
default() {
  local key="$1" fallback="$2"
  if [[ -f "$ENV_FILE" ]]; then
    local v
    v=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true)
    if [[ -n "$v" ]]; then echo "$v"; return; fi
  fi
  echo "$fallback"
}

PVE_HOST=$(whiptail --title "Step 3a: Proxmox Host" --inputbox \
  "Proxmox VE hostname or IP address:" 10 70 "$(default PVE_HOST "192.168.1.100")" \
  3>&1 1>&2 2>&3) || die "Cancelled by user"
info "Proxmox host: $PVE_HOST"

PVE_PORT=$(whiptail --title "Step 3b: Proxmox Port" --inputbox \
  "Proxmox VE API port:" 10 70 "$(default PVE_PORT "8006")" \
  3>&1 1>&2 2>&3) || die "Cancelled by user"
info "Proxmox port: $PVE_PORT"

PVE_NODE=$(whiptail --title "Step 3c: Proxmox Node" --inputbox \
  "Node name (as shown in the PVE web UI):" 10 70 "$(default PVE_NODE "pve")" \
  3>&1 1>&2 2>&3) || die "Cancelled by user"
info "Proxmox node: $PVE_NODE"

AUTH_METHOD=$(whiptail --title "Step 3d: Authentication" --menu \
  "How should the wallboard authenticate to Proxmox?" 12 70 2 \
  "token"    "API token (recommended)" \
  "password" "Username + password" \
  3>&1 1>&2 2>&3) || die "Cancelled by user"
info "Auth method: $AUTH_METHOD"

if [[ "$AUTH_METHOD" == "token" ]]; then
  PVE_TOKEN_ID=$(whiptail --title "Step 3e: Token ID" --inputbox \
    "API token ID (e.g. wallboard@pve!wallboard):" 10 70 \
    "$(default PVE_TOKEN_ID "wallboard@pve!wallboard")" \
    3>&1 1>&2 2>&3) || die "Cancelled by user"
  info "Token ID: $PVE_TOKEN_ID"

  PVE_TOKEN_SECRET=$(whiptail --title "Step 3f: Token Secret" --passwordbox \
    "API token secret (UUID):" 10 70 "" \
    3>&1 1>&2 2>&3) || die "Cancelled by user"
  info "Token secret: (saved)"
else
  PVE_USER=$(whiptail --title "Step 3e: PVE User" --inputbox \
    "Proxmox user (e.g. root@pam):" 10 70 \
    "$(default PVE_USER "root@pam")" 3>&1 1>&2 2>&3) || die "Cancelled by user"
  info "PVE user: $PVE_USER"

  PVE_PASS=$(whiptail --title "Step 3f: PVE Password" --passwordbox \
    "Password:" 10 70 "" 3>&1 1>&2 2>&3) || die "Cancelled by user"
  info "PVE password: (saved)"
fi

TITLE=$(whiptail --title "Step 3g: Wallboard Title" --inputbox \
  "Title shown in the header:" 10 70 \
  "$(default NEXT_PUBLIC_TITLE "Proxmox Wallboard")" 3>&1 1>&2 2>&3) || die "Cancelled by user"
info "Title: $TITLE"

POLL_INTERVAL=$(whiptail --title "Step 3h: Poll Interval" --inputbox \
  "How often to refresh Proxmox data (seconds):" 10 70 \
  "$(default NEXT_PUBLIC_POLL_INTERVAL "10")" 3>&1 1>&2 2>&3) || die "Cancelled by user"
info "Poll interval: ${POLL_INTERVAL}s"

ROTATE_INTERVAL=$(whiptail --title "Step 3i: Rotate Interval" --inputbox \
  "How often to rotate guest cards (seconds):" 10 70 \
  "$(default NEXT_PUBLIC_ROTATE_INTERVAL "8")" 3>&1 1>&2 2>&3) || die "Cancelled by user"
info "Rotate interval: ${ROTATE_INTERVAL}s"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: Display orientation
# ═══════════════════════════════════════════════════════════════════════════════
step "Display orientation"

ROTATION=$(whiptail --title "Step 4: Screen Orientation" --menu \
  "Pick display rotation:" 15 70 4 \
  "0" "Normal (landscape)" \
  "1" "90°  — rotated right (portrait)" \
  "2" "180° — upside down" \
  "3" "270° — rotated left (portrait)" \
  3>&1 1>&2 2>&3) || die "Cancelled by user"

CONFIG_TXT="/boot/firmware/config.txt"
[[ -f "$CONFIG_TXT" ]] || CONFIG_TXT="/boot/config.txt"

if [[ -f "$CONFIG_TXT" ]]; then
  sed -i '/^display_hdmi_rotate=/d; /^display_lcd_rotate=/d' "$CONFIG_TXT"
  echo "display_hdmi_rotate=$ROTATION" >> "$CONFIG_TXT"
  info "Display rotation: $ROTATION (in $CONFIG_TXT)"
else
  warn "Could not find config.txt — skipping display rotation"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: Write .env.local
# ═══════════════════════════════════════════════════════════════════════════════
step "Writing .env.local"

echo "  ${C_DIM}Writing configuration to $ENV_FILE${C_RESET}"

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
info "Wrote $ENV_FILE (permissions: 600)"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Install npm packages + build
# ═══════════════════════════════════════════════════════════════════════════════
step "Installing npm packages and building"

echo "  ${C_DIM}This may take a few minutes on a Raspberry Pi...${C_RESET}"

if [[ -f "$PROJECT_DIR/package-lock.json" ]]; then
  spin "Installing npm packages (npm ci)" \
    sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm ci --loglevel=error"
else
  spin "Installing npm packages (npm install)" \
    sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm install --loglevel=error"
fi

spin "Building Next.js production bundle" \
  sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm run build"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: Systemd service
# ═══════════════════════════════════════════════════════════════════════════════
step "Creating systemd service"

echo "  ${C_DIM}Writing proxmox-wallboard.service${C_RESET}"

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
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

spin "Reloading systemd daemon" systemctl daemon-reload
spin "Enabling proxmox-wallboard.service" systemctl enable proxmox-wallboard.service
info "Service will start automatically on boot"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Chromium kiosk autostart
# ═══════════════════════════════════════════════════════════════════════════════
step "Configuring Chromium kiosk mode"

# Detect chromium binary name (Bookworm = "chromium", older = "chromium-browser")
if command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium"
else
  warn "Chromium not found — kiosk autostart may need manual adjustment"
  CHROMIUM_BIN="chromium-browser"
fi
info "Chromium binary: $CHROMIUM_BIN"

# Create a launcher script that waits for the wallboard server before opening Chromium
echo "  ${C_DIM}Creating kiosk launcher script...${C_RESET}"
KIOSK_SCRIPT="$REAL_HOME/start-wallboard-kiosk.sh"
cat > "$KIOSK_SCRIPT" <<KIOSK
#!/usr/bin/env bash
#
# Wait for the wallboard server to be ready, then launch Chromium in kiosk mode.
# This script is started automatically on desktop login.
#

# Hide the mouse cursor
unclutter -idle 0.5 -root &

# Disable screen blanking / power management
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Wait for the wallboard server (up to 120 seconds)
echo "Waiting for wallboard server..."
TRIES=0
MAX_TRIES=60
until curl -sf http://localhost:3000 > /dev/null 2>&1; do
  TRIES=\$((TRIES + 1))
  if [[ \$TRIES -ge \$MAX_TRIES ]]; then
    echo "Wallboard server did not start in time. Launching browser anyway."
    break
  fi
  sleep 2
done
echo "Server is ready — launching kiosk."

# Launch Chromium in kiosk mode
exec $CHROMIUM_BIN \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-translate \\
  --no-first-run \\
  --disable-features=TranslateUI \\
  --check-for-update-interval=31536000 \\
  --kiosk \\
  http://localhost:3000
KIOSK

chmod +x "$KIOSK_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$KIOSK_SCRIPT"
info "Created kiosk launcher: $KIOSK_SCRIPT"

# --- Autostart entries (cover Bookworm labwc, Bullseye LXDE, and XDG) ---

echo "  ${C_DIM}Writing desktop autostart entries...${C_RESET}"

# XDG autostart (works on LXDE/Bullseye and many other DEs)
XDG_AUTOSTART_DIR="$REAL_HOME/.config/autostart"
sudo -u "$REAL_USER" mkdir -p "$XDG_AUTOSTART_DIR"
cat > "$XDG_AUTOSTART_DIR/proxmox-wallboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Proxmox Wallboard Kiosk
Exec=bash $KIOSK_SCRIPT
X-GNOME-Autostart-enabled=true
EOF
chown "$REAL_USER:$REAL_USER" "$XDG_AUTOSTART_DIR/proxmox-wallboard.desktop"
info "Added XDG autostart entry"

# labwc autostart (Bookworm with Wayland)
LABWC_AUTOSTART="$REAL_HOME/.config/labwc/autostart"
if [[ -d "$REAL_HOME/.config/labwc" ]] || [[ -d "/etc/xdg/labwc" ]]; then
  sudo -u "$REAL_USER" mkdir -p "$(dirname "$LABWC_AUTOSTART")"
  if ! grep -qF "start-wallboard-kiosk" "$LABWC_AUTOSTART" 2>/dev/null; then
    echo "bash $KIOSK_SCRIPT &" >> "$LABWC_AUTOSTART"
    chown "$REAL_USER:$REAL_USER" "$LABWC_AUTOSTART"
    info "Added labwc autostart entry"
  fi
fi

# LXDE autostart (Bullseye fallback)
LXDE_AUTOSTART="$REAL_HOME/.config/lxsession/LXDE-pi/autostart"
if [[ -d "$REAL_HOME/.config/lxsession/LXDE-pi" ]]; then
  if ! grep -qF "start-wallboard-kiosk" "$LXDE_AUTOSTART" 2>/dev/null; then
    echo "@bash $KIOSK_SCRIPT" >> "$LXDE_AUTOSTART"
    chown "$REAL_USER:$REAL_USER" "$LXDE_AUTOSTART"
    info "Added LXDE autostart entry"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 9: Auto-login + screen blanking + reboot
# ═══════════════════════════════════════════════════════════════════════════════
step "Finalizing system settings"

echo "  ${C_DIM}Configuring auto-login and display settings...${C_RESET}"

if command -v raspi-config >/dev/null 2>&1; then
  spin "Enabling desktop auto-login" raspi-config nonint do_boot_behaviour B4
  spin "Disabling screen blanking" raspi-config nonint do_blanking 1
else
  warn "raspi-config not found — please enable desktop auto-login manually"
fi

# ─── Summary + reboot ────────────────────────────────────────────────────────
echo
echo "${C_BOLD}${C_GREEN}  ╔═══════════════════════════════════════════════════════════╗${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ║                    Install Complete!                      ║${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ╠═══════════════════════════════════════════════════════════╣${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ System packages   ${C_DIM}node, vim, unclutter, chromium${C_RESET}       ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Configuration     ${C_DIM}.env.local written${C_RESET}                   ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ App built         ${C_DIM}Next.js production bundle${C_RESET}            ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Systemd service   ${C_DIM}proxmox-wallboard.service${C_RESET}            ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Kiosk mode        ${C_DIM}Chromium fullscreen on boot${C_RESET}          ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Auto-login        ${C_DIM}desktop login on boot${C_RESET}                ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Display           ${C_DIM}rotation=$ROTATION, blanking off${C_RESET}              ${C_GREEN}║${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ╚═══════════════════════════════════════════════════════════╝${C_RESET}"
echo
echo "  ${C_BOLD}After reboot the wallboard will start automatically.${C_RESET}"
echo

# Countdown to reboot
for i in 10 9 8 7 6 5 4 3 2 1; do
  printf "\r  ${C_YELLOW}Rebooting in %2d seconds... (Ctrl+C to cancel)${C_RESET}" "$i"
  sleep 1
done
echo
echo
echo "  ${C_BOLD}Rebooting now...${C_RESET}"
reboot
