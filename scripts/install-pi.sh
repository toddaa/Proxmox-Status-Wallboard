#!/usr/bin/env bash
#
# Proxmox Wallboard — Raspberry Pi installer
#
# Targets: Raspbian/Raspberry Pi OS 13 (Trixie) — Wayland/labwc
# Also works on Bookworm (12) and Bullseye (11) with graceful fallbacks.
#
# Fully automated setup: after this script finishes and the Pi reboots,
# the wallboard service starts, Chromium opens in kiosk mode, and you're
# looking at your wallboard.
#
# Usage:
#   cd Proxmox-Status-Wallboard && sudo bash scripts/install-pi.sh
#

# NOTE: We intentionally do NOT use `set -euo pipefail` here. It causes
# silent deaths on low-level commands (swap setup, apt fallbacks, etc.)
# that we want to handle gracefully. Instead, we check critical commands
# explicitly with || die/|| warn and use a trap for unexpected crashes.
set -u  # Catch undefined variables, but don't exit on errors

trap 'error "Script failed unexpectedly at line $LINENO (exit code $?)"; error "Please report this issue with the output above."; exit 1' ERR

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

STEP_NUM=0
TOTAL_STEPS=9
step() {
  STEP_NUM=$((STEP_NUM + 1))
  local label="$1"
  local pad_len=$((43 - ${#label}))
  [[ $pad_len -lt 0 ]] && pad_len=0
  local pad
  pad=$(printf '%*s' "$pad_len" '')
  echo
  echo "${C_BOLD}${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
  echo "${C_BOLD}${C_CYAN}│  Step ${STEP_NUM}/${TOTAL_STEPS}: ${label}${pad}│${C_RESET}"
  echo "${C_BOLD}${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
}

# Spinner: run a command in the background and show a spinner + message
# On failure, shows the last 20 lines of output and exits.
spin() {
  local msg="$1"; shift
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local logfile
  logfile=$(mktemp /var/tmp/wallboard-install-XXXXXX.log)

  # Run in background — disable ERR trap in child so we can handle it
  ( trap - ERR; "$@" ) > "$logfile" 2>&1 &
  local pid=$!

  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${C_CYAN}%s${C_RESET} %s" "${frames[$((i % ${#frames[@]}))]}" "$msg"
    sleep 0.1
    i=$((i + 1))
  done

  wait "$pid"
  local exit_code=$?
  printf "\r  \033[K"

  if [[ $exit_code -eq 0 ]]; then
    info "$msg"
  else
    error "$msg — failed (exit code $exit_code, log below)"
    echo "${C_DIM}"
    tail -20 "$logfile"
    echo "${C_RESET}"
    rm -f "$logfile"
    die "Build/install step failed. Fix the issue above and re-run the installer."
  fi
  rm -f "$logfile"
}

# Progress bar via whiptail gauge
gauge() {
  whiptail --title "$1" --gauge "" 7 70 0
}

# ─── Detect OS ────────────────────────────────────────────────────────────────
OS_CODENAME="unknown"
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_CODENAME="${VERSION_CODENAME:-unknown}"
fi

# ─── Preflight ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  die "This script must be run with sudo."
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

clear
echo
echo "${C_BOLD}${C_GREEN}  ╔═══════════════════════════════════════════════════════════╗${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ║          Proxmox Wallboard — Pi Installer                ║${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ╚═══════════════════════════════════════════════════════════╝${C_RESET}"
echo
echo "  ${C_DIM}Project dir :${C_RESET} $PROJECT_DIR"
echo "  ${C_DIM}Install user:${C_RESET} $REAL_USER ($REAL_HOME)"
echo "  ${C_DIM}OS codename :${C_RESET} $OS_CODENAME"
echo "  ${C_DIM}Architecture:${C_RESET} $ARCH"
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

# Install packages via gauge progress bar. Each apt-get has || true so
# failures in optional packages (chromium name varies, wlr-randr) don't
# halt the installer.
(
  echo "10"; echo "# Installing core tools (curl, git, build-essential)..."
  apt-get install -y -qq curl ca-certificates git build-essential whiptail >/dev/null 2>&1 || true

  echo "35"; echo "# Installing vim..."
  apt-get install -y -qq vim >/dev/null 2>&1 || true

  echo "45"; echo "# Installing labwc (Wayland compositor)..."
  apt-get install -y -qq labwc >/dev/null 2>&1 || true

  echo "55"; echo "# Installing unclutter (hides mouse cursor)..."
  apt-get install -y -qq unclutter >/dev/null 2>&1 || true

  echo "70"; echo "# Installing Chromium browser..."
  apt-get install -y -qq chromium >/dev/null 2>&1 || \
    apt-get install -y -qq chromium-browser >/dev/null 2>&1 || true

  echo "85"; echo "# Installing wlr-randr (Wayland display control)..."
  apt-get install -y -qq wlr-randr >/dev/null 2>&1 || true

  echo "100"; echo "# Done!"
) | gauge "Installing system packages"

# Verify critical packages installed
for cmd in curl git vim labwc; do
  command -v "$cmd" >/dev/null 2>&1 || die "Failed to install $cmd — check your apt sources"
done

info "Installed: curl, git, build-essential, vim, labwc, unclutter, chromium, wlr-randr"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Node.js
# ═══════════════════════════════════════════════════════════════════════════════
step "Installing Node.js"

NODE_MIN=20

node_version_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local ver
  ver=$(node -v 2>/dev/null | cut -c2- | cut -d. -f1)
  [[ "$ver" -ge $NODE_MIN ]] 2>/dev/null
}

if ! node_version_ok; then
  echo "  ${C_DIM}Trying system repos first (apt install nodejs npm)...${C_RESET}"
  apt-get install -y -qq nodejs npm >/dev/null 2>&1 || true

  if ! node_version_ok; then
    echo "  ${C_DIM}System repo didn't provide Node ${NODE_MIN}+, trying NodeSource...${C_RESET}"
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MIN}.x" 2>/dev/null | bash - >/dev/null 2>&1 || true
    apt-get install -y -qq nodejs >/dev/null 2>&1 || true
  fi

  if ! node_version_ok; then
    echo "  ${C_DIM}NodeSource not available, downloading official binary...${C_RESET}"
    local_arch="linux-arm64"
    [[ "$ARCH" == "armhf" ]] && local_arch="linux-armv7l"
    [[ "$ARCH" == "amd64" ]] && local_arch="linux-x64"
    node_ver="v20.19.2"
    tarball="node-${node_ver}-${local_arch}.tar.xz"
    url="https://nodejs.org/dist/${node_ver}/${tarball}"
    curl -fsSL "$url" -o "/tmp/$tarball" || die "Failed to download Node.js binary from $url"
    tar -xJf "/tmp/$tarball" -C /usr/local --strip-components=1
    rm -f "/tmp/$tarball"
  fi

  node_version_ok || die "Failed to install Node.js ${NODE_MIN}+. Please install manually and re-run."
  info "Installed Node.js $(node -v)"
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

# Map numeric choice to wlr-randr transform names
case "$ROTATION" in
  0) WLR_TRANSFORM="normal" ;;
  1) WLR_TRANSFORM="90" ;;
  2) WLR_TRANSFORM="180" ;;
  3) WLR_TRANSFORM="270" ;;
  *) WLR_TRANSFORM="normal" ;;
esac

# Apply rotation via KMS config.txt (takes effect at boot)
CONFIG_TXT="/boot/firmware/config.txt"
[[ -f "$CONFIG_TXT" ]] || CONFIG_TXT="/boot/config.txt"

if [[ -f "$CONFIG_TXT" ]]; then
  sed -i '/^display_hdmi_rotate=/d; /^display_lcd_rotate=/d' "$CONFIG_TXT"
  if [[ "$ROTATION" != "0" ]]; then
    echo "display_hdmi_rotate=$ROTATION" >> "$CONFIG_TXT"
  fi
  info "KMS rotation: display_hdmi_rotate=$ROTATION (in $CONFIG_TXT)"
else
  warn "Could not find config.txt — skipping KMS rotation"
fi

info "Wayland rotation: wlr-randr --transform $WLR_TRANSFORM (applied at login)"

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

echo "  ${C_DIM}This may take several minutes on a Raspberry Pi...${C_RESET}"

# --- Ensure enough memory for the build ---
TOTAL_MEM_MB=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
CURRENT_SWAP_MB=$(awk '/SwapTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
SWAP_INCREASED=false

echo "  ${C_DIM}Memory: ${TOTAL_MEM_MB}MB RAM + ${CURRENT_SWAP_MB}MB swap${C_RESET}"

if [[ $((TOTAL_MEM_MB + CURRENT_SWAP_MB)) -lt 1024 ]]; then
  echo "  ${C_DIM}Low memory — increasing swap to 2GB for the build...${C_RESET}"

  # Try dphys-swapfile first, then raw fallocate
  if command -v dphys-swapfile >/dev/null 2>&1 && [[ -f /etc/dphys-swapfile ]]; then
    ORIG_SWAP=$(grep -E '^CONF_SWAPSIZE=' /etc/dphys-swapfile 2>/dev/null | cut -d= -f2 || echo "100")
    dphys-swapfile swapoff >/dev/null 2>&1 || true
    sed -i "s/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/" /etc/dphys-swapfile
    if dphys-swapfile setup >/dev/null 2>&1 && dphys-swapfile swapon >/dev/null 2>&1; then
      SWAP_INCREASED=true
      info "Swap increased to 2GB via dphys-swapfile"
    else
      warn "dphys-swapfile failed, trying fallocate..."
    fi
  fi

  if [[ "$SWAP_INCREASED" == false ]]; then
    # Fallback: create a swap file directly
    SWAP_FILE="/var/tmp/wallboard-build-swap"
    rm -f "$SWAP_FILE"
    if dd if=/dev/zero of="$SWAP_FILE" bs=1M count=2048 status=progress 2>/dev/null && \
       chmod 600 "$SWAP_FILE" && \
       mkswap "$SWAP_FILE" >/dev/null 2>&1 && \
       swapon "$SWAP_FILE" 2>/dev/null; then
      SWAP_INCREASED=true
      info "Swap increased to 2GB via swap file"
    else
      warn "Could not increase swap"
      warn "If the build fails with OOM, run: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
    fi
  fi

  # Show new memory status
  NEW_SWAP_MB=$(awk '/SwapTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
  echo "  ${C_DIM}Memory now: ${TOTAL_MEM_MB}MB RAM + ${NEW_SWAP_MB}MB swap${C_RESET}"
fi

# --- Install packages ---
if [[ -f "$PROJECT_DIR/package-lock.json" ]]; then
  spin "Installing npm packages (npm ci)" \
    sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm ci --loglevel=error"
else
  spin "Installing npm packages (npm install)" \
    sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && npm install --loglevel=error"
fi

# --- Build ---
BUILD_CMD="npm run build"
NODE_OPTS=""
if [[ "$ARCH" == "armhf" || "$ARCH" == "armv7l" ]]; then
  # Turbopack doesn't support 32-bit ARM; use Webpack instead
  BUILD_CMD="npx next build --webpack"
  # Give Node more heap space on memory-constrained 32-bit systems
  NODE_OPTS="--max-old-space-size=512"
  echo "  ${C_DIM}32-bit ARM detected — using Webpack + 512MB heap limit${C_RESET}"
fi

spin "Building Next.js production bundle (this takes several minutes on a Pi)" \
  sudo -u "$REAL_USER" bash -c "cd '$PROJECT_DIR' && NODE_OPTIONS='$NODE_OPTS' $BUILD_CMD"

# --- Restore swap ---
if [[ "$SWAP_INCREASED" == true ]]; then
  echo "  ${C_DIM}Restoring original swap...${C_RESET}"
  if command -v dphys-swapfile >/dev/null 2>&1 && [[ -f /etc/dphys-swapfile ]]; then
    dphys-swapfile swapoff >/dev/null 2>&1 || true
    sed -i "s/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=${ORIG_SWAP:-100}/" /etc/dphys-swapfile 2>/dev/null || true
    dphys-swapfile setup >/dev/null 2>&1 || true
    dphys-swapfile swapon >/dev/null 2>&1 || true
  fi
  if [[ -f "/var/tmp/wallboard-build-swap" ]]; then
    swapoff /var/tmp/wallboard-build-swap 2>/dev/null || true
    rm -f /var/tmp/wallboard-build-swap
  fi
  info "Swap restored"
fi

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

systemctl daemon-reload || warn "systemctl daemon-reload failed"
systemctl enable proxmox-wallboard.service >/dev/null 2>&1 || warn "Could not enable service"
info "proxmox-wallboard.service enabled (starts on boot)"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Chromium kiosk autostart
# ═══════════════════════════════════════════════════════════════════════════════
step "Configuring Chromium kiosk mode"

# Detect chromium binary: Trixie/Bookworm = "chromium", Bullseye = "chromium-browser"
if command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium"
elif command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium-browser"
else
  warn "Chromium not found — kiosk autostart may need manual adjustment"
  CHROMIUM_BIN="chromium"
fi
info "Chromium binary: $CHROMIUM_BIN"

# --- Create kiosk launcher script ---
echo "  ${C_DIM}Creating kiosk launcher script...${C_RESET}"
KIOSK_SCRIPT="$REAL_HOME/start-wallboard-kiosk.sh"
cat > "$KIOSK_SCRIPT" <<KIOSK
#!/usr/bin/env bash
#
# Proxmox Wallboard — Kiosk launcher
# Runs at desktop login. Waits for the wallboard server, hides the cursor,
# applies display rotation, disables screen blanking, and opens Chromium.
#

# ── Apply display rotation (Wayland via wlr-randr) ──
if command -v wlr-randr >/dev/null 2>&1 && [[ -n "\${WAYLAND_DISPLAY:-}" ]]; then
  sleep 2
  wlr-randr --transform $WLR_TRANSFORM 2>/dev/null && \\
    echo "Applied Wayland rotation: $WLR_TRANSFORM"
fi

# ── Hide the mouse cursor ──
if command -v unclutter >/dev/null 2>&1; then
  unclutter -idle 0.5 -root &
  echo "Cursor hidden via unclutter"
fi

# ── Disable screen blanking ──
if [[ -n "\${DISPLAY:-}" ]]; then
  xset s off 2>/dev/null || true
  xset -dpms 2>/dev/null || true
  xset s noblank 2>/dev/null || true
fi

# ── Wait for the wallboard server (up to 120 seconds) ──
echo "Waiting for wallboard server on http://localhost:3000 ..."
TRIES=0
MAX_TRIES=60
until curl -sf http://localhost:3000 > /dev/null 2>&1; do
  TRIES=\$((TRIES + 1))
  if [[ \$TRIES -ge \$MAX_TRIES ]]; then
    echo "Server did not respond after 120s — launching browser anyway."
    break
  fi
  sleep 2
done
echo "Server is ready — launching kiosk."

# ── Launch Chromium in kiosk mode ──
exec $CHROMIUM_BIN \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-translate \\
  --no-first-run \\
  --disable-features=TranslateUI \\
  --check-for-update-interval=31536000 \\
  --ozone-platform-hint=auto \\
  --kiosk \\
  http://localhost:3000
KIOSK

chmod +x "$KIOSK_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$KIOSK_SCRIPT"
info "Created kiosk launcher: $KIOSK_SCRIPT"

# --- Write autostart entries ---
echo "  ${C_DIM}Writing desktop autostart entries...${C_RESET}"

# labwc autostart (Trixie + Bookworm — primary)
LABWC_DIR="$REAL_HOME/.config/labwc"
LABWC_AUTOSTART="$LABWC_DIR/autostart"
sudo -u "$REAL_USER" mkdir -p "$LABWC_DIR"
if ! grep -qF "start-wallboard-kiosk" "$LABWC_AUTOSTART" 2>/dev/null; then
  echo "bash $KIOSK_SCRIPT &" >> "$LABWC_AUTOSTART"
  chown "$REAL_USER:$REAL_USER" "$LABWC_AUTOSTART"
fi
info "Added labwc autostart entry"

# Disable labwc screen blanking
LABWC_RC="$LABWC_DIR/rc.xml"
if [[ ! -f "$LABWC_RC" ]] || ! grep -qF "<screenBlankTimeout>" "$LABWC_RC" 2>/dev/null; then
  if [[ -f "$LABWC_RC" ]] && grep -qF "</labwc>" "$LABWC_RC"; then
    sed -i 's|</labwc>|  <screenBlankTimeout>0</screenBlankTimeout>\n</labwc>|' "$LABWC_RC"
  else
    cat > "$LABWC_RC" <<RCXML
<?xml version="1.0"?>
<labwc_config>
  <screenBlankTimeout>0</screenBlankTimeout>
</labwc_config>
RCXML
    chown "$REAL_USER:$REAL_USER" "$LABWC_RC"
  fi
  info "Disabled labwc screen blanking (rc.xml)"
fi

# XDG autostart (fallback for other DEs)
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
info "Added XDG autostart entry (fallback)"

# LXDE autostart (Bullseye only)
LXDE_AUTOSTART="$REAL_HOME/.config/lxsession/LXDE-pi/autostart"
if [[ -d "$REAL_HOME/.config/lxsession/LXDE-pi" ]]; then
  if ! grep -qF "start-wallboard-kiosk" "$LXDE_AUTOSTART" 2>/dev/null; then
    echo "@bash $KIOSK_SCRIPT" >> "$LXDE_AUTOSTART"
    chown "$REAL_USER:$REAL_USER" "$LXDE_AUTOSTART"
    info "Added LXDE autostart entry (Bullseye)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 9: Auto-login + system settings + reboot
# ═══════════════════════════════════════════════════════════════════════════════
step "Finalizing system settings"

echo "  ${C_DIM}Configuring auto-login and display settings...${C_RESET}"

# --- Console auto-login ---
# Ensure getty on tty1 auto-logs in the wallboard user
GETTY_OVERRIDE="/etc/systemd/system/getty@tty1.service.d/autologin.conf"
mkdir -p "$(dirname "$GETTY_OVERRIDE")"
cat > "$GETTY_OVERRIDE" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $REAL_USER --noclear %I \$TERM
EOF
info "Console auto-login configured for $REAL_USER"

# --- Auto-start labwc from console login ---
# Add labwc launch to .bash_profile so it starts the Wayland compositor
# when logging in on tty1 (physical console), but not on SSH sessions.
PROFILE_FILE="$REAL_HOME/.bash_profile"
LABWC_LAUNCH_MARKER="# >>> proxmox-wallboard labwc autostart >>>"

if ! grep -qF "$LABWC_LAUNCH_MARKER" "$PROFILE_FILE" 2>/dev/null; then
  cat >> "$PROFILE_FILE" <<'LABWC_PROFILE'

# >>> proxmox-wallboard labwc autostart >>>
# Auto-start labwc on tty1 (console login only, not SSH)
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  export XDG_SESSION_TYPE=wayland
  exec labwc
fi
# <<< proxmox-wallboard labwc autostart <<<
LABWC_PROFILE
  chown "$REAL_USER:$REAL_USER" "$PROFILE_FILE"
  info "labwc auto-start added to .bash_profile (tty1 only)"
else
  info "labwc auto-start already in .bash_profile — skipping"
fi

# --- raspi-config settings ---
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_blanking 1 2>/dev/null && \
    info "Disabled screen blanking (raspi-config)" || \
    warn "Could not disable screen blanking via raspi-config"
else
  warn "raspi-config not found"
fi

# ─── Summary + reboot ────────────────────────────────────────────────────────
echo
echo "${C_BOLD}${C_GREEN}  ╔═══════════════════════════════════════════════════════════╗${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ║                    Install Complete!                      ║${C_RESET}"
echo "${C_BOLD}${C_GREEN}  ╠═══════════════════════════════════════════════════════════╣${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ System packages   ${C_DIM}node, vim, labwc, chromium${C_RESET}           ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Configuration     ${C_DIM}.env.local written${C_RESET}                   ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ App built         ${C_DIM}Next.js production bundle${C_RESET}            ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Systemd service   ${C_DIM}proxmox-wallboard.service${C_RESET}            ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Kiosk mode        ${C_DIM}Chromium fullscreen on boot${C_RESET}          ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Auto-login        ${C_DIM}desktop login on boot${C_RESET}                ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ Display           ${C_DIM}rotation=${WLR_TRANSFORM}, blanking off${C_RESET}        ${C_GREEN}║${C_RESET}"
echo "${C_GREEN}  ║${C_RESET}  ✓ OS                ${C_DIM}${OS_CODENAME} (${ARCH})${C_RESET}                        ${C_GREEN}║${C_RESET}"
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
