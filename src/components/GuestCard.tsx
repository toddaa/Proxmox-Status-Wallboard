"use client";

import type { GuestData } from "@/types/proxmox";
import { formatBytes, formatRate, formatUptime } from "@/lib/format";
import { healthColor } from "@/lib/health";
import RingGauge from "./RingGauge";

interface GuestCardProps {
  guest: GuestData;
}

// Per-guest network gauge is scaled to 1 Gbit/s (~125 MB/s) of in+out throughput,
// matching the host-level NET gauge for consistency.
const NET_SCALE_BPS = 125 * 1024 * 1024;

export default function GuestCard({ guest: g }: GuestCardProps) {
  const isUp = g.status === "running";
  const cpuPct = isUp ? g.cpu : 0;
  const memPct = isUp ? (g.mem.used / g.mem.total) * 100 : 0;
  const diskPct =
    isUp && g.disk.total > 0 ? (g.disk.used / g.disk.total) * 100 : 0;
  const netPct = Math.min(
    ((g.netInRate + g.netOutRate) / NET_SCALE_BPS) * 100,
    100
  );
  const cpuColor = healthColor(cpuPct, "var(--accent-cpu)");
  const memColor = healthColor(memPct, "var(--accent-mem)");
  const diskColor = healthColor(diskPct, "var(--accent-disk)");
  const typeLabel = g.type === "qemu" ? "VM" : "LXC";

  return (
    <div className="guest-card">
      <div className="guest-card-header">
        <div className="guest-card-info">
          <span className={`guest-type-badge ${g.type}`}>{typeLabel}</span>
          <div>
            <div className="guest-card-name">{g.name}</div>
            <div className="guest-vmid font-mono">
              VMID {g.vmid} · {g.cpus} vCPU
            </div>
          </div>
        </div>
        <div className={`guest-status-dot ${g.status}`} />
      </div>

      <div className="guest-metrics-grid">
        {/* CPU */}
        <div className="guest-metric-cell">
          <RingGauge
            percent={cpuPct}
            color={cpuColor}
            value={`${cpuPct.toFixed(0)}%`}
            unit=""
            size={78}
          />
          <div className="metric-label" style={{ color: cpuColor }}>
            CPU
          </div>
        </div>

        {/* MEM */}
        <div className="guest-metric-cell">
          <RingGauge
            percent={memPct}
            color={memColor}
            value={`${memPct.toFixed(0)}%`}
            unit=""
            size={78}
          />
          <div className="metric-label" style={{ color: memColor }}>
            MEM
          </div>
          <div className="metric-detail font-mono">
            {formatBytes(g.mem.used)} / {formatBytes(g.mem.total)}
          </div>
        </div>

        {/* DISK */}
        <div className="guest-metric-cell">
          <RingGauge
            percent={diskPct}
            color={diskColor}
            value={`${diskPct.toFixed(0)}%`}
            unit=""
            size={78}
          />
          <div className="metric-label" style={{ color: diskColor }}>
            DISK
          </div>
          <div className="metric-detail font-mono">
            {formatBytes(g.disk.used)} / {formatBytes(g.disk.total)}
          </div>
        </div>

        {/* NET */}
        <div className="guest-metric-cell">
          <RingGauge
            percent={netPct}
            color="var(--accent-net)"
            value=""
            unit=""
            size={78}
          />
          <div className="metric-label" style={{ color: "var(--accent-net)" }}>
            NET
          </div>
          <div className="metric-detail font-mono" style={{ lineHeight: 1.4 }}>
            <span style={{ color: "var(--accent-net)" }}>
              ↓{formatRate(g.netInRate)}
            </span>
            {"  "}
            <span style={{ color: "var(--accent-cpu)" }}>
              ↑{formatRate(g.netOutRate)}
            </span>
          </div>
        </div>
      </div>

      <div className="guest-footer">
        <div className="guest-uptime font-mono">
          {isUp ? `⏱ ${formatUptime(g.uptime)}` : g.status.toUpperCase()}
        </div>
      </div>
    </div>
  );
}
