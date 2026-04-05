// ── Proxmox API response types ──

export interface PveNodeStatus {
  cpu: number;
  wait: number;
  uptime: number;
  kversion: string;
  pveversion: string;
  loadavg: [string, string, string];
  cpuinfo: {
    model: string;
    cpus: number;
    sockets: number;
    cores: number;
    mhz: string;
  };
  memory: {
    total: number;
    used: number;
    free: number;
  };
  swap: {
    total: number;
    used: number;
    free: number;
  };
  rootfs: {
    total: number;
    used: number;
    free: number;
    avail: number;
  };
}

export interface PveGuest {
  vmid: number;
  name: string;
  status: string;
  type: "qemu" | "lxc";
  cpus: number;
  cpu: number;
  maxcpu: number;
  mem: number;
  maxmem: number;
  disk: number;
  maxdisk: number;
  netin: number;
  netout: number;
  uptime: number;
}

// ── Normalized app types ──

export interface HostData {
  name: string;
  cpuModel: string;
  cpuCores: number;
  cpuSockets: number;
  cpuUsage: number;
  memUsed: number;
  memTotal: number;
  swapUsed: number;
  swapTotal: number;
  rootUsed: number;
  rootTotal: number;
  uptime: number;
  ioWait: number;
  kversion: string;
  pveversion: string;
  loadavg: string[];
}

export interface GuestData {
  vmid: number;
  name: string;
  type: "qemu" | "lxc";
  status: string;
  cpus: number;
  cpu: number;
  mem: { used: number; total: number };
  disk: { used: number; total: number };
  netIn: number;
  netOut: number;
  netInRate: number; // bytes/sec, computed client-side from successive samples
  netOutRate: number; // bytes/sec, computed client-side from successive samples
  uptime: number;
}

export interface WallboardData {
  host: HostData;
  guests: GuestData[];
  timestamp: string;
}

export interface WallboardConfig {
  host: string;
  port: string;
  node: string;
  authMethod: "token" | "password";
  tokenId: string;
  secret: string;
  user: string;
  pass: string;
  pollInterval: number;
  rotateInterval: number;
}
