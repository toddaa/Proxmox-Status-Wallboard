import { describe, it, expect } from "vitest";
import {
  formatBytes,
  formatTraffic,
  formatRate,
  formatUptime,
  clamp,
} from "./format";

describe("formatBytes", () => {
  it("returns 0 B for zero and falsy values", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(NaN)).toBe("0 B");
    expect(formatBytes(undefined as unknown as number)).toBe("0 B");
  });

  it("formats bytes through TB", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(2048)).toBe("2 KB");
    expect(formatBytes(5 * 1024 * 1024)).toBe("5 MB");
    expect(formatBytes(3 * 1024 ** 3)).toBe("3.0 GB");
    expect(formatBytes(1.5 * 1024 ** 4)).toBe("1.5 TB");
  });
});

describe("formatTraffic", () => {
  it("handles small byte counts", () => {
    expect(formatTraffic(0)).toBe("0 B");
    expect(formatTraffic(512)).toBe("512 B");
  });

  it("formats KB / MB / GB", () => {
    expect(formatTraffic(2048)).toBe("2.0 KB");
    expect(formatTraffic(5 * 1024 * 1024)).toBe("5.0 MB");
    expect(formatTraffic(2.5 * 1024 ** 3)).toBe("2.50 GB");
  });
});

describe("formatRate", () => {
  it("shows B/s for tiny throughput", () => {
    expect(formatRate(0)).toBe("0 B/s");
    expect(formatRate(800)).toBe("800 B/s");
  });

  it("scales to KB/s, MB/s, GB/s", () => {
    expect(formatRate(2048)).toBe("2.0 KB/s");
    expect(formatRate(5 * 1024 ** 2)).toBe("5.0 MB/s");
    expect(formatRate(1.5 * 1024 ** 3)).toBe("1.50 GB/s");
  });

  it("treats undefined as 0", () => {
    expect(formatRate(undefined as unknown as number)).toBe("0 B/s");
  });
});

describe("formatUptime", () => {
  it("returns em-dash for invalid uptime", () => {
    expect(formatUptime(0)).toBe("—");
    expect(formatUptime(-1)).toBe("—");
  });

  it("formats minutes, hours, and days", () => {
    expect(formatUptime(5 * 60)).toBe("5m");
    expect(formatUptime(3600 + 5 * 60)).toBe("1h 5m");
    expect(formatUptime(2 * 86400 + 3 * 3600 + 10 * 60)).toBe("2d 3h 10m");
  });
});

describe("clamp", () => {
  it("clamps below min and above max", () => {
    expect(clamp(-5, 0, 10)).toBe(0);
    expect(clamp(15, 0, 10)).toBe(10);
    expect(clamp(5, 0, 10)).toBe(5);
  });
});
