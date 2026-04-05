import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import GuestGrid from "./GuestGrid";
import type { GuestData } from "@/types/proxmox";

function makeGuests(count: number): GuestData[] {
  return Array.from({ length: count }, (_, i) => ({
    vmid: 100 + i,
    name: `guest-${i}`,
    type: "lxc" as const,
    status: "running",
    cpus: 1,
    cpu: 0,
    mem: { used: 0, total: 1 },
    disk: { used: 0, total: 1 },
    netIn: 0,
    netOut: 0,
    netInRate: 0,
    netOutRate: 0,
    uptime: 0,
  }));
}

describe("GuestGrid", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("renders all guests statically when the count is <= visibleCount", () => {
    render(
      <GuestGrid guests={makeGuests(3)} visibleCount={3} rotateInterval={8} />
    );
    expect(screen.getByText("guest-0")).toBeInTheDocument();
    expect(screen.getByText("guest-1")).toBeInTheDocument();
    expect(screen.getByText("guest-2")).toBeInTheDocument();
    // No rotation badge shown
    expect(screen.queryByText(/guests$/)).not.toBeInTheDocument();
  });

  it("shows the rotation count when more guests than visible slots", () => {
    render(
      <GuestGrid guests={makeGuests(5)} visibleCount={3} rotateInterval={8} />
    );
    expect(screen.getByText(/5 guests/)).toBeInTheDocument();
  });

  it("rotates one card forward after the interval elapses", () => {
    render(
      <GuestGrid guests={makeGuests(5)} visibleCount={3} rotateInterval={8} />
    );

    // Initially the window is [0,1,2] plus a peeked [3]
    expect(screen.getByText("guest-0")).toBeInTheDocument();

    // Advance one rotation interval + the slide transition
    act(() => {
      vi.advanceTimersByTime(8000);
      vi.advanceTimersByTime(500);
    });

    // After one rotation, guest-0 should have rotated off, window starts at 1
    expect(screen.queryByText("guest-0")).not.toBeInTheDocument();
    expect(screen.getByText("guest-1")).toBeInTheDocument();
    expect(screen.getByText("guest-3")).toBeInTheDocument();
  });

  it("renders the empty state when there are no guests", () => {
    render(<GuestGrid guests={[]} visibleCount={3} rotateInterval={8} />);
    expect(screen.getByText(/No guests found/)).toBeInTheDocument();
  });
});
