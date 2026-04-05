import { NextResponse } from "next/server";
import type {
  GuestData,
  HostData,
  PveGuest,
  PveNodeStatus,
  WallboardData,
} from "@/types/proxmox";

// Disable Next.js route caching so every request hits Proxmox live
export const dynamic = "force-dynamic";

// Proxmox connection config — set via environment variables
// PVE_HOST=192.168.1.100
// PVE_PORT=8006
// PVE_NODE=pve
// PVE_TOKEN_ID=user@pam!wallboard
// PVE_TOKEN_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
// (or for password auth:)
// PVE_AUTH_METHOD=password
// PVE_USER=root@pam
// PVE_PASS=yourpassword

function getConfig() {
  return {
    host: process.env.PVE_HOST || "localhost",
    port: process.env.PVE_PORT || "8006",
    node: process.env.PVE_NODE || "pve",
    authMethod: (process.env.PVE_AUTH_METHOD as "token" | "password") || "token",
    tokenId: process.env.PVE_TOKEN_ID || "",
    secret: process.env.PVE_TOKEN_SECRET || "",
    user: process.env.PVE_USER || "",
    pass: process.env.PVE_PASS || "",
  };
}

let cachedTicket: string | null = null;
let cachedCsrf: string | null = null;

async function pveRequest(path: string): Promise<unknown> {
  const cfg = getConfig();
  const url = `https://${cfg.host}:${cfg.port}/api2/json${path}`;
  const headers: Record<string, string> = { Accept: "application/json" };

  if (cfg.authMethod === "token") {
    headers["Authorization"] = `PVEAPIToken=${cfg.tokenId}=${cfg.secret}`;
  } else {
    if (!cachedTicket) {
      const ticketResp = await fetch(
        `https://${cfg.host}:${cfg.port}/api2/json/access/ticket`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            username: cfg.user,
            password: cfg.pass,
          }),
          cache: "no-store",
          // @ts-expect-error — Node 18+ supports this for self-signed certs
          rejectUnauthorized: false,
        }
      );
      if (!ticketResp.ok) throw new Error("PVE auth failed");
      const ticketData = await ticketResp.json();
      cachedTicket = ticketData.data.ticket;
      cachedCsrf = ticketData.data.CSRFPreventionToken;
    }
    headers["Cookie"] = `PVEAuthCookie=${cachedTicket}`;
    if (cachedCsrf) headers["CSRFPreventionToken"] = cachedCsrf;
  }

  // Node.js fetch with self-signed cert support
  const resp = await fetch(url, {
    headers,
    cache: "no-store",
    // @ts-expect-error — Node 18+ supports this for self-signed certs
    rejectUnauthorized: false,
  });

  if (resp.status === 401) {
    cachedTicket = null;
    cachedCsrf = null;
    throw new Error("PVE authentication failed — check credentials");
  }

  if (!resp.ok) {
    throw new Error(`PVE API ${resp.status}: ${resp.statusText}`);
  }

  const json = await resp.json();
  return json.data;
}

export async function GET() {
  try {
    const cfg = getConfig();

    if (!cfg.host || !cfg.node) {
      return NextResponse.json(
        { error: "PVE_HOST and PVE_NODE env vars required" },
        { status: 500 }
      );
    }

    const [nodeStatus, qemuList, lxcList] = (await Promise.all([
      pveRequest(`/nodes/${cfg.node}/status`),
      pveRequest(`/nodes/${cfg.node}/qemu`),
      pveRequest(`/nodes/${cfg.node}/lxc`),
    ])) as [PveNodeStatus, PveGuest[], PveGuest[]];

    const host: HostData = {
      name: cfg.node,
      cpuModel: nodeStatus.cpuinfo?.model || "Unknown CPU",
      cpuCores: nodeStatus.cpuinfo?.cpus || 0,
      cpuSockets: nodeStatus.cpuinfo?.sockets || 1,
      cpuUsage: (nodeStatus.cpu || 0) * 100,
      memUsed: nodeStatus.memory?.used || 0,
      memTotal: nodeStatus.memory?.total || 1,
      swapUsed: nodeStatus.swap?.used || 0,
      swapTotal: nodeStatus.swap?.total || 1,
      rootUsed: nodeStatus.rootfs?.used || 0,
      rootTotal: nodeStatus.rootfs?.total || 1,
      uptime: nodeStatus.uptime || 0,
      ioWait: (nodeStatus.wait || 0) * 100,
      kversion: nodeStatus.kversion || "—",
      pveversion: nodeStatus.pveversion || "",
      loadavg: nodeStatus.loadavg || ["0", "0", "0"],
    };

    const guests: GuestData[] = [];

    for (const vm of qemuList || []) {
      guests.push({
        vmid: vm.vmid,
        name: vm.name || `VM ${vm.vmid}`,
        type: "qemu",
        status: vm.status || "unknown",
        cpus: vm.cpus || vm.maxcpu || 1,
        cpu: (vm.cpu || 0) * 100,
        mem: { used: vm.mem || 0, total: vm.maxmem || 1 },
        disk: { used: vm.disk || 0, total: vm.maxdisk || 1 },
        netIn: vm.netin || 0,
        netOut: vm.netout || 0,
        netInRate: 0,
        netOutRate: 0,
        uptime: vm.uptime || 0,
      });
    }

    for (const ct of lxcList || []) {
      guests.push({
        vmid: ct.vmid,
        name: ct.name || `CT ${ct.vmid}`,
        type: "lxc",
        status: ct.status || "unknown",
        cpus: ct.cpus || ct.maxcpu || 1,
        cpu: (ct.cpu || 0) * 100,
        mem: { used: ct.mem || 0, total: ct.maxmem || 1 },
        disk: { used: ct.disk || 0, total: ct.maxdisk || 1 },
        netIn: ct.netin || 0,
        netOut: ct.netout || 0,
        netInRate: 0,
        netOutRate: 0,
        uptime: ct.uptime || 0,
      });
    }

    // Sort: running first, then by VMID
    guests.sort((a, b) => {
      if (a.status === "running" && b.status !== "running") return -1;
      if (a.status !== "running" && b.status === "running") return 1;
      return a.vmid - b.vmid;
    });

    const data: WallboardData = {
      host,
      guests,
      timestamp: new Date().toISOString(),
    };

    return NextResponse.json(data);
  } catch (err: unknown) {
    console.error("Proxmox API error:", err);
    const message =
      err instanceof Error ? err.message : "Failed to fetch Proxmox data";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
