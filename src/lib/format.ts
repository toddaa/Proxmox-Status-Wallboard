export function formatBytes(bytes: number): string {
  if (!bytes || bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(i > 2 ? 1 : 0) + " " + units[i];
}

export function formatTraffic(bytes: number): string {
  if (!bytes || bytes < 1024) return (bytes || 0).toFixed(0) + " B";
  if (bytes < 1024 ** 2) return (bytes / 1024).toFixed(1) + " KB";
  if (bytes < 1024 ** 3) return (bytes / 1024 ** 2).toFixed(1) + " MB";
  return (bytes / 1024 ** 3).toFixed(2) + " GB";
}

export function formatRate(bytesPerSec: number): string {
  const bps = bytesPerSec || 0;
  if (bps < 1024) return bps.toFixed(0) + " B/s";
  if (bps < 1024 ** 2) return (bps / 1024).toFixed(1) + " KB/s";
  if (bps < 1024 ** 3) return (bps / 1024 ** 2).toFixed(1) + " MB/s";
  return (bps / 1024 ** 3).toFixed(2) + " GB/s";
}

export function formatUptime(seconds: number): string {
  if (!seconds || seconds <= 0) return "—";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

export function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}
