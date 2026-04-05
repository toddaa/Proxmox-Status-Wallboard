"use client";

import type { GuestData } from "@/types/proxmox";
import { formatBytes, formatRate, formatUptime } from "@/lib/format";

interface GuestCardProps {
  guest: GuestData;
}

function MiniBar({
  label,
  percent,
  color,
}: {
  label: string;
  percent: number;
  color: string;
}) {
  const pct = Math.max(0, Math.min(100, percent || 0));
  return (
    <div className="mini-metric">
      <div className="mini-metric-header">
        <span className="mini-metric-label">{label}</span>
        <span className="mini-metric-value font-mono" style={{ color }}>
          {pct.toFixed(0)}%
        </span>
      </div>
      <div className="mini-bar-track">
        <div
          className="mini-bar-fill"
          style={{
            width: `${pct}%`,
            background: color,
            boxShadow: `0 0 4px ${color}44`,
          }}
        />
      </div>
    </div>
  );
}

export default function GuestCard({ guest: g }: GuestCardProps) {
  const isUp = g.status === "running";
  const cpuPct = isUp ? g.cpu : 0;
  const memPct = isUp ? (g.mem.used / g.mem.total) * 100 : 0;
  const diskPct =
    isUp && g.disk.total > 0 ? (g.disk.used / g.disk.total) * 100 : 0;
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
        <MiniBar label="CPU" percent={cpuPct} color="var(--accent-cpu)" />
        <MiniBar label="MEM" percent={memPct} color="var(--accent-mem)" />
        <MiniBar label="DISK" percent={diskPct} color="var(--accent-disk)" />
        <div className="mini-metric">
          <div className="mini-metric-header">
            <span className="mini-metric-label">NET</span>
            <span
              className="mini-metric-value font-mono"
              style={{ color: "var(--accent-net)" }}
            >
              ↓↑
            </span>
          </div>
          <div className="net-detail font-mono">
            <span style={{ color: "var(--accent-net)" }}>
              ↓{formatRate(g.netInRate)}
            </span>
            <br />
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
        <div className="guest-mem-detail font-mono">
          {formatBytes(g.mem.used)} / {formatBytes(g.mem.total)}
        </div>
      </div>
    </div>
  );
}
