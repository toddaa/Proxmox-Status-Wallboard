import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import GuestCard from "./GuestCard";
import type { GuestData } from "@/types/proxmox";

function makeGuest(overrides: Partial<GuestData> = {}): GuestData {
  return {
    vmid: 101,
    name: "web-server",
    type: "qemu",
    status: "running",
    cpus: 4,
    cpu: 35,
    mem: { used: 2 * 1024 ** 3, total: 8 * 1024 ** 3 },
    disk: { used: 10 * 1024 ** 3, total: 100 * 1024 ** 3 },
    netIn: 0,
    netOut: 0,
    netInRate: 2 * 1024 * 1024,
    netOutRate: 512 * 1024,
    uptime: 3600,
    ...overrides,
  };
}

describe("GuestCard", () => {
  it("shows name, VMID, and type badge for a running guest", () => {
    render(<GuestCard guest={makeGuest()} />);
    expect(screen.getByText("web-server")).toBeInTheDocument();
    expect(screen.getByText(/VMID 101/)).toBeInTheDocument();
    expect(screen.getByText(/4 vCPU/)).toBeInTheDocument();
    expect(screen.getByText("VM")).toBeInTheDocument();
  });

  it("labels LXC guests correctly", () => {
    render(<GuestCard guest={makeGuest({ type: "lxc" })} />);
    expect(screen.getByText("LXC")).toBeInTheDocument();
  });

  it("shows CPU percentage for running guests", () => {
    render(<GuestCard guest={makeGuest({ cpu: 42 })} />);
    expect(screen.getByText("42%")).toBeInTheDocument();
  });

  it("shows 0% usage when stopped", () => {
    render(
      <GuestCard
        guest={makeGuest({ status: "stopped", cpu: 100, netInRate: 0, netOutRate: 0 })}
      />
    );
    // CPU, MEM, and DISK mini-bars all show 0%
    const zeros = screen.getAllByText("0%");
    expect(zeros.length).toBeGreaterThanOrEqual(3);
    expect(screen.getByText("STOPPED")).toBeInTheDocument();
  });

  it("shows current network rates (not cumulative bytes)", () => {
    render(<GuestCard guest={makeGuest()} />);
    // 2 MB/s in, 512 KB/s out
    expect(screen.getByText(/↓2\.0 MB\/s/)).toBeInTheDocument();
    expect(screen.getByText(/↑512\.0 KB\/s/)).toBeInTheDocument();
  });
});
