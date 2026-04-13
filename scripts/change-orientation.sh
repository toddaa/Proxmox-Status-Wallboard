#!/usr/bin/env bash
#
# Proxmox Wallboard — Change screen orientation
#
# Updates both rotation settings the installer configures:
#   1. KMS rotation in /boot/firmware/config.txt (applied at boot)
#   2. Wayland rotation in ~/start-wallboard-kiosk.sh (applied at login)
#
# Optionally applies the new rotation live via wlr-randr so you can see
# the result without rebooting.
#
# Usage:
#   sudo bash scripts/change-orientation.sh
#

set -u
trap 'error "Script failed unexpectedly at line $LINENO (exit code $?)"; exit 1' ERR

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

# ─── Must be root (to edit /boot/firmware/config.txt) ─────────────────────────
if [[ $EUID -ne 0 ]]; then
  die "Please run with sudo: sudo bash scripts/change-orientation.sh"
fi

# ─── Resolve the real (non-root) user so we can find their kiosk script ──────
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" == "root" ]]; then
  die "Cannot determine the original user. Re-run via 'sudo bash ...' as your normal user."
fi
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
[[ -n "$REAL_HOME" && -d "$REAL_HOME" ]] || die "Could not resolve home directory for $REAL_USER"

KIOSK_SCRIPT="$REAL_HOME/start-wallboard-kiosk.sh"
[[ -f "$KIOSK_SCRIPT" ]] || die "Kiosk script not found at $KIOSK_SCRIPT — has the installer been run?"

# ─── Locate config.txt ────────────────────────────────────────────────────────
CONFIG_TXT="/boot/firmware/config.txt"
[[ -f "$CONFIG_TXT" ]] || CONFIG_TXT="/boot/config.txt"
if [[ ! -f "$CONFIG_TXT" ]]; then
  warn "Could not find config.txt — KMS rotation will not be updated"
  CONFIG_TXT=""
fi

# ─── Prompt for orientation ───────────────────────────────────────────────────
echo "${C_BOLD}${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo "${C_BOLD}${C_CYAN}│  Proxmox Wallboard — Change screen orientation              │${C_RESET}"
echo "${C_BOLD}${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
echo

if command -v whiptail >/dev/null 2>&1; then
  ROTATION=$(whiptail --title "Screen Orientation" --menu \
    "Pick display rotation:" 15 70 4 \
    "0" "Normal (landscape)" \
    "1" "90°  — rotated right (portrait)" \
    "2" "180° — upside down" \
    "3" "270° — rotated left (portrait)" \
    3>&1 1>&2 2>&3) || die "Cancelled by user"
else
  echo "Pick display rotation:"
  echo "  0) Normal (landscape)"
  echo "  1) 90°  — rotated right (portrait)"
  echo "  2) 180° — upside down"
  echo "  3) 270° — rotated left (portrait)"
  read -rp "Choice [0-3]: " ROTATION
fi

case "$ROTATION" in
  0) WLR_TRANSFORM="normal" ;;
  1) WLR_TRANSFORM="90" ;;
  2) WLR_TRANSFORM="180" ;;
  3) WLR_TRANSFORM="270" ;;
  *) die "Invalid choice: $ROTATION" ;;
esac

info "Selected: rotation=$ROTATION (wlr-randr transform=$WLR_TRANSFORM)"

# ─── Clean up legacy display_hdmi_rotate entries ──────────────────────────────
# display_hdmi_rotate is ignored by the KMS driver on Trixie/Bookworm. We
# strip any leftover lines so they don't mislead future debugging. Rotation
# is now handled entirely by wlr-randr in the kiosk launcher.
if [[ -n "$CONFIG_TXT" ]] && grep -qE '^(display_hdmi_rotate|display_lcd_rotate)=' "$CONFIG_TXT"; then
  sed -i '/^display_hdmi_rotate=/d; /^display_lcd_rotate=/d' "$CONFIG_TXT"
  info "Removed legacy display_*_rotate lines from $CONFIG_TXT (ignored by KMS)"
fi

# ─── Update Wayland rotation in kiosk launcher ────────────────────────────────
# Replace the entire rotation block (bounded by the "Apply display rotation"
# comment and the next lone `fi`). This works whether the kiosk script is
# the old single-line format or the new auto-detecting format.
if grep -q '# ── Apply display rotation' "$KIOSK_SCRIPT"; then
  NEW_BLOCK=$(cat <<EOF
# ── Apply display rotation (Wayland via wlr-randr) ──
# Auto-detects the output name and waits for it to appear.
if command -v wlr-randr >/dev/null 2>&1 && [[ -n "\${WAYLAND_DISPLAY:-}" ]]; then
  ROT_OUTPUT=""
  for _i in \$(seq 1 20); do
    ROT_OUTPUT=\$(wlr-randr 2>/dev/null | awk 'NR==1 && /^[A-Za-z]/ {print \$1; exit}')
    [[ -n "\$ROT_OUTPUT" ]] && break
    sleep 0.5
  done
  if [[ -n "\$ROT_OUTPUT" ]]; then
    wlr-randr --output "\$ROT_OUTPUT" --transform ${WLR_TRANSFORM} && \\
      echo "Applied Wayland rotation: ${WLR_TRANSFORM} on \$ROT_OUTPUT"
  else
    echo "No Wayland output detected — rotation skipped"
  fi
fi
EOF
)
  awk -v new="$NEW_BLOCK" '
    /# ── Apply display rotation/ { print new; in_block=1; next }
    in_block && /^fi$/            { in_block=0; next }
    !in_block                     { print }
  ' "$KIOSK_SCRIPT" > "$KIOSK_SCRIPT.tmp" && mv "$KIOSK_SCRIPT.tmp" "$KIOSK_SCRIPT"
  chown "$REAL_USER:$REAL_USER" "$KIOSK_SCRIPT"
  chmod +x "$KIOSK_SCRIPT"
  info "Wayland rotation block rewritten in $KIOSK_SCRIPT"
else
  warn "Kiosk script has no rotation block — skipping Wayland update"
fi

# ─── Optionally apply live ────────────────────────────────────────────────────
echo
read -rp "Apply rotation now via wlr-randr (no reboot)? [y/N] " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  # wlr-randr must run as the user owning the Wayland session. Detect the
  # output name the same way the kiosk launcher does.
  UID_NUM=$(id -u "$REAL_USER")
  RUN_AS_USER=(sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$UID_NUM" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}")
  LIVE_OUTPUT=$("${RUN_AS_USER[@]}" wlr-randr 2>/dev/null | awk 'NR==1 && /^[A-Za-z]/ {print $1; exit}') || true
  if [[ -n "$LIVE_OUTPUT" ]]; then
    if "${RUN_AS_USER[@]}" wlr-randr --output "$LIVE_OUTPUT" --transform "$WLR_TRANSFORM"; then
      info "Applied live: $LIVE_OUTPUT → $WLR_TRANSFORM"
    else
      warn "wlr-randr reported an error — change will still take effect at next login"
    fi
  else
    warn "Could not reach the Wayland session (run this from the Pi's desktop, or just reboot)"
  fi
fi

echo
echo "${C_BOLD}${C_GREEN}Done.${C_RESET} Reboot or log out/in to apply:"
echo "  sudo reboot"
echo
