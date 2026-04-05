import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import HostPanel from "./HostPanel";
import type { HostData, GuestData } from "@/types/proxmox";

const host: HostData = {
  name: "pve-lab",
  cpuModel: "Intel(R) Xeon(R) CPU E5-2670 @ 2.60GHz",
  cpuCores: 16,
  cpuSockets: 2,
  cpuUsage: 37.5,
  memUsed: 8 * 1024 ** 3,
  memTotal: 32 * 1024 ** 3,
  swapUsed: 0,
  swapTotal: 4 * 1024 ** 3,
  rootUsed: 50 * 1024 ** 3,
  rootTotal: 200 * 1024 ** 3,
  uptime: 100000,
  ioWait: 1.2,
  kversion: "Linux 6.5.0-pve #1",
  pveversion: "pve-manager/8.1.4",
  loadavg: ["0.50", "0.75", "1.00"],
};

const guests: GuestData[] = [
  {
    vmid: 1,
    name: "a",
    type: "qemu",
    status: "running",
    cpus: 1,
    cpu: 0,
    mem: { used: 0, total: 1 },
    disk: { used: 0, total: 1 },
    netIn: 0,
    netOut: 0,
    netInRate: 1024 * 1024, // 1 MB/s
    netOutRate: 2 * 1024 * 1024, // 2 MB/s
    uptime: 0,
  },
  {
    vmid: 2,
    name: "b",
    type: "lxc",
    status: "running",
    cpus: 1,
    cpu: 0,
    mem: { used: 0, total: 1 },
    disk: { used: 0, total: 1 },
    netIn: 0,
    netOut: 0,
    netInRate: 512 * 1024, // 0.5 MB/s
    netOutRate: 0,
    uptime: 0,
  },
];

describe("HostPanel", () => {
  it("renders the host name and VM / LXC counts", () => {
    render(<HostPanel host={host} guests={guests} />);
    expect(screen.getByText("pve-lab")).toBeInTheDocument();
    expect(screen.getByText(/1 VMs · 1 LXC/)).toBeInTheDocument();
  });

  it("shows CPU usage percentage", () => {
    render(<HostPanel host={host} guests={guests} />);
    expect(screen.getByText("37.5")).toBeInTheDocument();
  });

  it("sums current network rates across guests (in bytes/sec, not cumulative)", () => {
    render(<HostPanel host={host} guests={guests} />);
    // total in = 1 MB/s + 0.5 MB/s = 1.5 MB/s
    expect(screen.getByText(/↓ 1\.5 MB\/s/)).toBeInTheDocument();
    // total out = 2 MB/s + 0 = 2 MB/s
    expect(screen.getByText(/↑ 2\.0 MB\/s/)).toBeInTheDocument();
  });

  it("shows the sockets multiplier for multi-socket hosts", () => {
    render(<HostPanel host={host} guests={guests} />);
    expect(screen.getByText(/2×/)).toBeInTheDocument();
  });
});
