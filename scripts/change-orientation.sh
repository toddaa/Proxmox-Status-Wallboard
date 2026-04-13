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

# ─── Update KMS rotation in config.txt ────────────────────────────────────────
if [[ -n "$CONFIG_TXT" ]]; then
  sed -i '/^display_hdmi_rotate=/d; /^display_lcd_rotate=/d' "$CONFIG_TXT"
  if [[ "$ROTATION" != "0" ]]; then
    echo "display_hdmi_rotate=$ROTATION" >> "$CONFIG_TXT"
  fi
  info "KMS rotation updated: display_hdmi_rotate=$ROTATION (in $CONFIG_TXT)"
fi

# ─── Update Wayland rotation in kiosk launcher ────────────────────────────────
# The installer writes these two lines:
#   wlr-randr --transform <value> 2>/dev/null && \
#     echo "Applied Wayland rotation: <value>"
# Rewrite both in-place.
if grep -q 'wlr-randr --transform' "$KIOSK_SCRIPT"; then
  sed -i -E \
    -e "s|(wlr-randr --transform )[A-Za-z0-9_-]+( 2>/dev/null.*)|\1${WLR_TRANSFORM}\2|" \
    -e "s|(Applied Wayland rotation: )[A-Za-z0-9_-]+(\")|\1${WLR_TRANSFORM}\2|" \
    "$KIOSK_SCRIPT"
  info "Wayland rotation updated in $KIOSK_SCRIPT"
else
  warn "Kiosk script has no wlr-randr line — skipping Wayland update"
fi

# ─── Optionally apply live ────────────────────────────────────────────────────
echo
read -rp "Apply rotation now via wlr-randr (no reboot)? [y/N] " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  # wlr-randr needs to run as the user owning the Wayland session
  if sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
       WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" \
       wlr-randr --transform "$WLR_TRANSFORM" 2>/dev/null; then
    info "Applied live: wlr-randr --transform $WLR_TRANSFORM"
  else
    warn "Live apply failed (no Wayland session?). Will take effect after reboot."
  fi
fi

echo
echo "${C_BOLD}${C_GREEN}Done.${C_RESET} Reboot for the KMS change to take effect:"
echo "  sudo reboot"
echo
