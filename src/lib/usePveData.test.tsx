import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import { usePveData } from "./usePveData";
import type { WallboardData } from "@/types/proxmox";

function sample(overrides: Partial<WallboardData> = {}): WallboardData {
  return {
    host: {
      name: "pve",
      cpuModel: "Test CPU",
      cpuCores: 4,
      cpuSockets: 1,
      cpuUsage: 12,
      memUsed: 1024,
      memTotal: 8192,
      swapUsed: 0,
      swapTotal: 0,
      rootUsed: 10,
      rootTotal: 100,
      uptime: 1000,
      ioWait: 0,
      kversion: "6.0",
      pveversion: "pve-manager/8.0",
      loadavg: ["0.1", "0.2", "0.3"],
    },
    guests: [],
    timestamp: new Date().toISOString(),
    ...overrides,
  };
}

function guest(vmid: number, netIn: number, netOut: number, uptime = 100) {
  return {
    vmid,
    name: `g${vmid}`,
    type: "lxc" as const,
    status: "running",
    cpus: 1,
    cpu: 0,
    mem: { used: 100, total: 1000 },
    disk: { used: 10, total: 100 },
    netIn,
    netOut,
    netInRate: 0,
    netOutRate: 0,
    uptime,
  };
}

function mockFetchSequence(responses: unknown[]) {
  const fn = vi.fn();
  for (const r of responses) {
    fn.mockResolvedValueOnce({
      ok: true,
      json: async () => r,
    } as Response);
  }
  vi.stubGlobal("fetch", fn);
  return fn;
}

describe("usePveData", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("fetches on mount and transitions to connected", async () => {
    mockFetchSequence([sample()]);

    const { result } = renderHook(() => usePveData({ pollInterval: 10 }));

    await vi.waitFor(() => {
      expect(result.current.status).toBe("connected");
    });
    expect(result.current.data?.host.name).toBe("pve");
    expect(result.current.error).toBeNull();
    expect(result.current.lastUpdated).toBeInstanceOf(Date);
  });

  it("sets error status when the API fails", async () => {
    const fn = vi.fn().mockResolvedValue({
      ok: false,
      status: 502,
      json: async () => ({ error: "boom" }),
    } as Response);
    vi.stubGlobal("fetch", fn);

    const { result } = renderHook(() => usePveData({ pollInterval: 10 }));

    await vi.waitFor(() => {
      expect(result.current.status).toBe("error");
    });
    expect(result.current.error).toBe("boom");
    expect(result.current.consecutiveErrors).toBeGreaterThanOrEqual(1);
  });

  it("polls on the configured interval", async () => {
    const fn = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => sample(),
    } as Response);
    vi.stubGlobal("fetch", fn);

    renderHook(() => usePveData({ pollInterval: 10 }));

    // First call happens immediately on mount
    await vi.waitFor(() => expect(fn).toHaveBeenCalledTimes(1));

    // Advance 10 seconds → should trigger second fetch
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10_000);
    });
    expect(fn).toHaveBeenCalledTimes(2);

    // Another 10 seconds → third fetch
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10_000);
    });
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("computes network rates from successive samples", async () => {
    // Two polls 10 seconds apart: guest 100 sent 10 MB, received 5 MB in between
    const TEN_MB = 10 * 1024 * 1024;
    const FIVE_MB = 5 * 1024 * 1024;

    const fn = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => sample({ guests: [guest(100, 0, 0, 100)] }),
      } as Response)
      .mockResolvedValueOnce({
        ok: true,
        json: async () =>
          sample({ guests: [guest(100, FIVE_MB, TEN_MB, 110)] }),
      } as Response);
    vi.stubGlobal("fetch", fn);

    const { result } = renderHook(() => usePveData({ pollInterval: 10 }));

    // First sample — no rate yet (no baseline)
    await vi.waitFor(() => expect(result.current.data).not.toBeNull());
    expect(result.current.data?.guests[0].netInRate).toBe(0);
    expect(result.current.data?.guests[0].netOutRate).toBe(0);

    // Advance 10s → second fetch with deltas
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10_000);
    });

    await vi.waitFor(() => {
      const g = result.current.data?.guests[0];
      expect(g?.netIn).toBe(FIVE_MB);
    });

    const g = result.current.data!.guests[0];
    // dt is ~10s — allow a tiny bit of slop for timer scheduling
    expect(g.netInRate).toBeGreaterThan(FIVE_MB / 11);
    expect(g.netInRate).toBeLessThan(FIVE_MB / 9);
    expect(g.netOutRate).toBeGreaterThan(TEN_MB / 11);
    expect(g.netOutRate).toBeLessThan(TEN_MB / 9);
  });

  it("does not compute a rate if uptime decreased (guest restart)", async () => {
    const fn = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => sample({ guests: [guest(100, 1_000_000, 0, 500)] }),
      } as Response)
      .mockResolvedValueOnce({
        ok: true,
        // Uptime dropped → restart → counters reset; we must NOT produce a negative/garbage rate
        json: async () => sample({ guests: [guest(100, 100, 0, 10)] }),
      } as Response);
    vi.stubGlobal("fetch", fn);

    const { result } = renderHook(() => usePveData({ pollInterval: 10 }));
    await vi.waitFor(() => expect(result.current.data).not.toBeNull());

    await act(async () => {
      await vi.advanceTimersByTimeAsync(10_000);
    });
    await vi.waitFor(() => {
      expect(result.current.data?.guests[0].netIn).toBe(100);
    });

    expect(result.current.data!.guests[0].netInRate).toBe(0);
    expect(result.current.data!.guests[0].netOutRate).toBe(0);
  });
});
