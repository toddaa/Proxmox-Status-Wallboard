"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import type { WallboardData } from "@/types/proxmox";

interface UsePveDataOptions {
  pollInterval?: number; // seconds
}

interface UsePveDataResult {
  data: WallboardData | null;
  error: string | null;
  status: "connecting" | "connected" | "error";
  lastUpdated: Date | null;
  consecutiveErrors: number;
}

export function usePveData({
  pollInterval = 10,
}: UsePveDataOptions = {}): UsePveDataResult {
  const [data, setData] = useState<WallboardData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<"connecting" | "connected" | "error">(
    "connecting"
  );
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const errCount = useRef(0);
  const [consecutiveErrors, setConsecutiveErrors] = useState(0);
  // Previous sample for computing network rate (bytes/sec) from cumulative counters
  const prevSample = useRef<{
    ts: number;
    byVmid: Map<number, { netIn: number; netOut: number; uptime: number }>;
  } | null>(null);

  const fetchData = useCallback(async () => {
    try {
      const resp = await fetch("/api/proxmox");
      if (!resp.ok) {
        const body = await resp.json().catch(() => ({}));
        throw new Error(body.error || `HTTP ${resp.status}`);
      }
      const json: WallboardData = await resp.json();

      // Compute per-guest network rates from the delta between successive samples.
      // Proxmox reports netin/netout as cumulative bytes since guest start, so we
      // subtract the previous reading and divide by elapsed wall-clock time.
      const nowMs = Date.now();
      const prev = prevSample.current;
      if (prev) {
        const dtSec = (nowMs - prev.ts) / 1000;
        if (dtSec > 0) {
          for (const g of json.guests) {
            const p = prev.byVmid.get(g.vmid);
            // Only compute a rate if we have a prior sample AND the uptime didn't
            // reset (guest restart would make counters drop and produce garbage).
            if (p && g.uptime >= p.uptime) {
              const dIn = g.netIn - p.netIn;
              const dOut = g.netOut - p.netOut;
              g.netInRate = dIn > 0 ? dIn / dtSec : 0;
              g.netOutRate = dOut > 0 ? dOut / dtSec : 0;
            }
          }
        }
      }
      const byVmid = new Map<
        number,
        { netIn: number; netOut: number; uptime: number }
      >();
      for (const g of json.guests) {
        byVmid.set(g.vmid, {
          netIn: g.netIn,
          netOut: g.netOut,
          uptime: g.uptime,
        });
      }
      prevSample.current = { ts: nowMs, byVmid };

      setData(json);
      setError(null);
      setStatus("connected");
      setLastUpdated(new Date());
      errCount.current = 0;
      setConsecutiveErrors(0);
    } catch (err: unknown) {
      errCount.current++;
      setConsecutiveErrors(errCount.current);
      setError(err instanceof Error ? err.message : "Connection failed");
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    fetchData();
    const timer = setInterval(fetchData, pollInterval * 1000);
    return () => clearInterval(timer);
  }, [fetchData, pollInterval]);

  return { data, error, status, lastUpdated, consecutiveErrors };
}
