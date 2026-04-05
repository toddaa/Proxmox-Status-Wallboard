"use client";

import { usePveData } from "@/lib/usePveData";
import { formatUptime } from "@/lib/format";
import MatrixRain from "@/components/MatrixRain";
import HostPanel from "@/components/HostPanel";
import GuestGrid from "@/components/GuestGrid";
import Clock from "@/components/Clock";

const POLL_INTERVAL = parseInt(process.env.NEXT_PUBLIC_POLL_INTERVAL || "10");
const ROTATE_INTERVAL = parseInt(
  process.env.NEXT_PUBLIC_ROTATE_INTERVAL || "8"
);
const TITLE = process.env.NEXT_PUBLIC_TITLE || "Proxmox Wallboard";

export default function WallboardPage() {
  const { data, error, status, lastUpdated, consecutiveErrors } = usePveData({
    pollInterval: POLL_INTERVAL,
  });

  const connDotClass =
    status === "connected"
      ? "connected"
      : status === "error"
        ? "error"
        : "connecting";

  const connLabel =
    status === "connected"
      ? "CONNECTED"
      : status === "error"
        ? `ERROR${consecutiveErrors > 1 ? " ×" + consecutiveErrors : ""}`
        : "CONNECTING";

  return (
    <>
      <MatrixRain />
      <div className="wallboard">
        {/* Header */}
        <div className="header">
          <div className="header-left">
            <div className="pve-logo">PVE</div>
            <div>
              <div className="header-title">{TITLE}</div>
              <div className="header-subtitle font-mono">
                {data ? `proxmox ve · ${data.host.name}` : "connecting…"}
              </div>
            </div>
          </div>

          <div className="header-right">
            <div className="conn-badge">
              <span className={`conn-dot ${connDotClass}`} />
              <span>{connLabel}</span>
            </div>

            {lastUpdated && (
              <div className="last-updated-badge font-mono">
                UPDATED{" "}
                {lastUpdated.toLocaleTimeString("en-US", {
                  hour12: false,
                  hour: "2-digit",
                  minute: "2-digit",
                  second: "2-digit",
                })}
              </div>
            )}

            <div className="uptime-badge">
              UPTIME {data ? formatUptime(data.host.uptime) : "—"}
            </div>

            <Clock />
          </div>
        </div>

        {/* Error banner */}
        {status === "error" && !data && (
          <div className="error-banner">
            CONNECTION FAILED: {error}
            <br />
            Check PVE_HOST, PVE_NODE, and auth env vars in .env.local
          </div>
        )}

        {/* Host Panel */}
        {data && <HostPanel host={data.host} guests={data.guests} />}

        {/* Guest Grid */}
        {data && (
          <GuestGrid
            guests={data.guests}
            visibleCount={3}
            rotateInterval={ROTATE_INTERVAL}
          />
        )}
      </div>
    </>
  );
}
