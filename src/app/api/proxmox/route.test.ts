import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";

// Minimal fake Proxmox responses
const NODE_STATUS = {
  cpu: 0.25,
  wait: 0.01,
  uptime: 12345,
  kversion: "Linux 6.5.0",
  pveversion: "pve-manager/8.1/abc",
  loadavg: ["0.5", "0.6", "0.7"],
  cpuinfo: { model: "Intel(R) Xeon(R) CPU @ 2.40GHz", cpus: 8, sockets: 1, cores: 4, mhz: "2400" },
  memory: { total: 16 * 1024 ** 3, used: 4 * 1024 ** 3, free: 12 * 1024 ** 3 },
  swap: { total: 2 * 1024 ** 3, used: 0, free: 2 * 1024 ** 3 },
  rootfs: { total: 100 * 1024 ** 3, used: 20 * 1024 ** 3, free: 80 * 1024 ** 3, avail: 80 * 1024 ** 3 },
};

const QEMU_LIST = [
  {
    vmid: 101,
    name: "web",
    status: "running",
    cpus: 2,
    cpu: 0.1,
    maxcpu: 2,
    mem: 1024 ** 3,
    maxmem: 4 * 1024 ** 3,
    disk: 0,
    maxdisk: 32 * 1024 ** 3,
    netin: 1000,
    netout: 2000,
    uptime: 500,
  },
];

const LXC_LIST = [
  {
    vmid: 200,
    name: "db",
    status: "stopped",
    cpus: 1,
    cpu: 0,
    maxcpu: 1,
    mem: 0,
    maxmem: 1024 ** 3,
    disk: 0,
    maxdisk: 8 * 1024 ** 3,
    netin: 0,
    netout: 0,
    uptime: 0,
  },
];

function mockProxmoxFetch() {
  return vi.fn(async (url: string) => {
    if (url.includes("/status")) {
      return { ok: true, status: 200, json: async () => ({ data: NODE_STATUS }) } as Response;
    }
    if (url.includes("/qemu")) {
      return { ok: true, status: 200, json: async () => ({ data: QEMU_LIST }) } as Response;
    }
    if (url.includes("/lxc")) {
      return { ok: true, status: 200, json: async () => ({ data: LXC_LIST }) } as Response;
    }
    throw new Error("Unexpected URL: " + url);
  });
}

describe("GET /api/proxmox", () => {
  beforeEach(() => {
    process.env.PVE_HOST = "10.0.0.1";
    process.env.PVE_PORT = "8006";
    process.env.PVE_NODE = "pve";
    process.env.PVE_AUTH_METHOD = "token";
    process.env.PVE_TOKEN_ID = "test@pve!tok";
    process.env.PVE_TOKEN_SECRET = "secret";
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("normalizes host and guest data from Proxmox", async () => {
    vi.stubGlobal("fetch", mockProxmoxFetch());

    const { GET } = await import("./route");
    const req = new NextRequest("http://localhost/api/proxmox");
    const resp = await GET(req);
    const body = await resp.json();

    expect(resp.status).toBe(200);
    expect(body.host.name).toBe("pve");
    expect(body.host.cpuCores).toBe(8);
    expect(body.host.cpuUsage).toBeCloseTo(25);
    expect(body.host.memTotal).toBe(16 * 1024 ** 3);

    // Running guests sort before stopped
    expect(body.guests).toHaveLength(2);
    expect(body.guests[0].vmid).toBe(101);
    expect(body.guests[0].type).toBe("qemu");
    expect(body.guests[0].status).toBe("running");
    expect(body.guests[0].cpu).toBeCloseTo(10);
    expect(body.guests[1].vmid).toBe(200);
    expect(body.guests[1].type).toBe("lxc");
  });

  it("includes the Authorization header for token auth", async () => {
    const fn = mockProxmoxFetch();
    vi.stubGlobal("fetch", fn);

    const { GET } = await import("./route");
    const req = new NextRequest("http://localhost/api/proxmox");
    await GET(req);

    expect(fn).toHaveBeenCalled();
    const callArgs = fn.mock.calls[0];
    const init = callArgs[1] as RequestInit;
    const headers = init.headers as Record<string, string>;
    expect(headers.Authorization).toBe("PVEAPIToken=test@pve!tok=secret");
  });

  it("returns 502 when the Proxmox API errors", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        return {
          ok: false,
          status: 500,
          statusText: "Internal Server Error",
          json: async () => ({}),
        } as Response;
      })
    );

    const { GET } = await import("./route");
    const req = new NextRequest("http://localhost/api/proxmox");
    const resp = await GET(req);
    expect(resp.status).toBe(502);
  });
});
