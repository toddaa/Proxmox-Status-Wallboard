# Proxmox Wallboard

A Matrix-themed monitoring wallboard for Proxmox VE, built with Next.js / TypeScript / React. Designed to run on a Raspberry Pi connected to a vertical display on the same network as your homelab.

![Matrix green aesthetic with digital rain, ring gauges for host metrics, and rotating guest cards]

## Architecture

```
┌─────────────────────────────────────────────┐
│  Raspberry Pi                               │
│  ┌───────────────────────────────────────┐   │
│  │  Next.js App (port 3000)              │   │
│  │  ┌─────────────┐  ┌───────────────┐   │   │
│  │  │  React UI   │  │  /api/proxmox │──────── Proxmox API (:8006)
│  │  │  (client)   │──│  (server)     │   │   │
│  │  └─────────────┘  └───────────────┘   │   │
│  └───────────────────────────────────────┘   │
│  Chromium Kiosk → http://localhost:3000      │
└─────────────────────────────────────────────┘
```

The Next.js API route (`/api/proxmox`) proxies all Proxmox API calls server-side, so:
- No CORS issues (browser only talks to localhost)
- Self-signed cert handling via `NODE_TLS_REJECT_UNAUTHORIZED=0`
- API credentials stay server-side, never exposed to the browser

## Quick Start

### 1. Create a Proxmox API Token

On your Proxmox host:

```bash
# Create a dedicated user
pveum user add wallboard@pve

# Grant read-only access
pveum aclmod / -user wallboard@pve -role PVEAuditor

# Create API token (save the output!)
pveum user token add wallboard@pve wallboard --privsep 0
```

### 2. Setup on Raspberry Pi

```bash
# Install Node.js 20+
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs

# Clone and install
git clone <your-repo> proxmox-wallboard
cd proxmox-wallboard
npm install

# Configure
cp .env.example .env.local
nano .env.local
# Fill in your PVE_HOST, PVE_NODE, PVE_TOKEN_ID, PVE_TOKEN_SECRET

# Build and run
npm run build
npm run start
```

### 3. Auto-Start on Boot

Create a systemd service:

```bash
sudo tee /etc/systemd/system/wallboard.service << 'EOF'
[Unit]
Description=Proxmox Wallboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/proxmox-wallboard
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable wallboard
sudo systemctl start wallboard
```

### 4. Chromium Kiosk Mode

Create `/home/pi/start-kiosk.sh`:

```bash
#!/bin/bash
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.5 -root &

# Wait for wallboard to be ready
until curl -s http://localhost:3000 > /dev/null 2>&1; do
  sleep 2
done

chromium-browser \
  --noerrors \
  --disable-infobars \
  --kiosk \
  --incognito \
  --disable-translate \
  --no-first-run \
  --disable-features=TranslateUI \
  --disk-cache-dir=/dev/null \
  http://localhost:3000
```

Add to your desktop autostart (for Raspberry Pi OS with desktop):

```bash
# For LXDE (Bullseye)
echo '@bash /home/pi/start-kiosk.sh' >> ~/.config/lxsession/LXDE-pi/autostart

# For labwc/Wayland (Bookworm)
echo 'bash /home/pi/start-kiosk.sh &' >> ~/.config/labwc/autostart
```

Install unclutter to hide the cursor:

```bash
sudo apt install unclutter
```

## Project Structure

```
src/
├── app/
│   ├── api/proxmox/route.ts   # Server-side Proxmox API proxy
│   ├── globals.css             # Matrix theme & all styling
│   ├── layout.tsx              # Root layout
│   └── page.tsx                # Main wallboard page
├── components/
│   ├── MatrixRain.tsx          # Digital rain canvas background
│   ├── HostPanel.tsx           # Host metrics with ring gauges
│   ├── GuestGrid.tsx           # Rotating VM/container grid
│   ├── GuestCard.tsx           # Individual guest card
│   ├── RingGauge.tsx           # SVG ring gauge component
│   └── Clock.tsx               # Live clock
├── lib/
│   ├── format.ts               # Formatting utilities
│   └── usePveData.ts           # Polling hook
└── types/
    └── proxmox.ts              # TypeScript types
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PVE_HOST` | Proxmox IP/hostname | `localhost` |
| `PVE_PORT` | Proxmox API port | `8006` |
| `PVE_NODE` | Proxmox node name | `pve` |
| `PVE_AUTH_METHOD` | `token` or `password` | `token` |
| `PVE_TOKEN_ID` | API token ID | — |
| `PVE_TOKEN_SECRET` | API token secret | — |
| `PVE_USER` | Username (password auth) | — |
| `PVE_PASS` | Password (password auth) | — |
| `NEXT_PUBLIC_TITLE` | Custom Title | `Proxmox Wallboard` |
| `NEXT_PUBLIC_POLL_INTERVAL` | API poll interval (seconds) | `10` |
| `NEXT_PUBLIC_ROTATE_INTERVAL` | Guest page rotation (seconds) | `8` |

## Display Orientation

For a vertical wallboard, set your Pi's display rotation:

```bash
# /boot/config.txt (or /boot/firmware/config.txt on Bookworm)
display_rotate=1  # 90 degrees clockwise
# or
display_rotate=3  # 90 degrees counter-clockwise
```

## License

MIT
