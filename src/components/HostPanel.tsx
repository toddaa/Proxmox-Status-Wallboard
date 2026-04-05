"use client";

import type { HostData, GuestData } from "@/types/proxmox";
import { formatBytes, formatRate, formatUptime } from "@/lib/format";
import RingGauge from "./RingGauge";

interface HostPanelProps {
  host: HostData;
  guests: GuestData[];
}

export default function HostPanel({ host, guests }: HostPanelProps) {
  const cpuPct = host.cpuUsage.toFixed(1);
  const memPct = ((host.memUsed / host.memTotal) * 100).toFixed(1);
  const swapPct =
    host.swapTotal > 0
      ? ((host.swapUsed / host.swapTotal) * 100).toFixed(1)
      : "0.0";
  const diskPct = ((host.rootUsed / host.rootTotal) * 100).toFixed(1);
  const iowPct = host.ioWait.toFixed(1);
  const loadStr = Array.isArray(host.loadavg)
    ? host.loadavg.map((l) => parseFloat(l).toFixed(2)).join("  ")
    : "—";
  // Current (not cumulative) network throughput across all guests, bytes/sec
  const totalInRate = guests.reduce((s, g) => s + (g.netInRate || 0), 0);
  const totalOutRate = guests.reduce((s, g) => s + (g.netOutRate || 0), 0);
  // Gauge scaled to 1 Gbit/s (~125 MB/s) of aggregate in+out throughput
  const NET_SCALE_BPS = 125 * 1024 * 1024;
  const netPct = Math.min(
    ((totalInRate + totalOutRate) / NET_SCALE_BPS) * 100,
    100
  );

  const vmCount = guests.filter((g) => g.type === "qemu").length;
  const lxcCount = guests.filter((g) => g.type === "lxc").length;
  const cpuLabel = host.cpuModel
    .replace(/\(R\)|\(TM\)/g, "")
    .replace(/CPU\s*@.*/, "")
    .trim();
  const memGB = Math.round(host.memTotal / 1024 ** 3);

  return (
    <div className="host-section">
      {/* Top glow bar */}
      <div className="host-glow-bar" />

      <div className="host-header">
        <div className="host-name-area">
          <div className="host-icon">
            <svg viewBox="0 0 24 24" width={22} height={22}>
              <rect
                x="2"
                y="3"
                width="20"
                height="6"
                rx="1.5"
                fill="none"
                stroke="currentColor"
                strokeWidth={1.5}
              />
              <rect
                x="2"
                y="13"
                width="20"
                height="6"
                rx="1.5"
                fill="none"
                stroke="currentColor"
                strokeWidth={1.5}
              />
              <circle cx="6" cy="6" r="1" fill="currentColor" />
              <circle cx="6" cy="16" r="1" fill="currentColor" />
              <line
                x1="10"
                y1="6"
                x2="18"
                y2="6"
                stroke="currentColor"
                strokeWidth={1.5}
              />
              <line
                x1="10"
                y1="16"
                x2="18"
                y2="16"
                stroke="currentColor"
                strokeWidth={1.5}
              />
            </svg>
          </div>
          <div>
            <div className="host-label">{host.name}</div>
            <div className="host-specs font-mono">
              {host.cpuSockets > 1 ? `${host.cpuSockets}× ` : ""}
              {cpuLabel} · {memGB} GB · {host.pveversion || "PVE"}
            </div>
          </div>
        </div>

        <div className="status-pills">
          <div className="status-pill">
            <span className="pulse-dot" />
            ONLINE
          </div>
          <div className="status-pill">
            {vmCount} VMs · {lxcCount} LXC
          </div>
          <div className="status-pill">
            {(host.kversion || "").split(" ")[0] || "—"}
          </div>
        </div>
      </div>

      <div className="host-metrics-grid">
        {/* CPU */}
        <div className="metric-card">
          <RingGauge
            percent={parseFloat(cpuPct)}
            color="var(--accent-cpu)"
            value={cpuPct}
            unit={`% of ${host.cpuCores} threads`}
          />
          <div className="metric-label" style={{ color: "var(--accent-cpu)" }}>
            CPU
          </div>
          <div className="metric-detail">Load: {loadStr}</div>
        </div>

        {/* Memory */}
        <div className="metric-card">
          <RingGauge
            percent={parseFloat(memPct)}
            color="var(--accent-mem)"
            value={memPct}
            unit={`${formatBytes(host.memUsed)} / ${formatBytes(host.memTotal)}`}
          />
          <div className="metric-label" style={{ color: "var(--accent-mem)" }}>
            Memory
          </div>
          <div className="metric-detail">
            Free: {formatBytes(host.memTotal - host.memUsed)}
          </div>
        </div>

        {/* Swap */}
        <div className="metric-card">
          <RingGauge
            percent={parseFloat(swapPct)}
            color="var(--accent-swap)"
            value={swapPct}
            unit={`${formatBytes(host.swapUsed)} / ${formatBytes(host.swapTotal)}`}
          />
          <div className="metric-label" style={{ color: "var(--accent-swap)" }}>
            Swap
          </div>
        </div>

        {/* Root FS */}
        <div className="metric-card">
          <RingGauge
            percent={parseFloat(diskPct)}
            color="var(--accent-disk)"
            value={diskPct}
            unit={`${formatBytes(host.rootUsed)} / ${formatBytes(host.rootTotal)}`}
          />
          <div className="metric-label" style={{ color: "var(--accent-disk)" }}>
            Root FS
          </div>
          <div className="metric-detail">
            Free: {formatBytes(host.rootTotal - host.rootUsed)}
          </div>
        </div>

        {/* IO Wait */}
        <div className="metric-card">
          <RingGauge
            percent={parseFloat(iowPct)}
            color="var(--accent-iowait)"
            value={iowPct}
            unit="%"
          />
          <div
            className="metric-label"
            style={{ color: "var(--accent-iowait)" }}
          >
            IO Wait
          </div>
        </div>

        {/* Network */}
        <div className="metric-card">
          <RingGauge
            percent={netPct}
            color="var(--accent-net)"
            value=""
            unit=""
          />
          <div className="metric-label" style={{ color: "var(--accent-net)" }}>
            Network
          </div>
          <div className="metric-detail" style={{ color: "var(--accent-net)" }}>
            ↓ {formatRate(totalInRate)}
          </div>
          <div className="metric-detail" style={{ color: "var(--accent-cpu)" }}>
            ↑ {formatRate(totalOutRate)}
          </div>
        </div>
      </div>
    </div>
  );
}
