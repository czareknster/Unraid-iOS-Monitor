import { readFile } from "node:fs/promises";
import { join } from "node:path";

export interface SystemReading {
  uptimeSec: number | null;
  loadavg: { oneMin: number; fiveMin: number; fifteenMin: number } | null;
  memory: {
    totalKB: number;
    freeKB: number;
    availableKB: number;
    buffersKB: number;
    cachedKB: number;
    swapTotalKB: number;
    swapFreeKB: number;
  } | null;
}

export class SystemCollector {
  constructor(private readonly procRoot: string = "/proc") {}

  async read(): Promise<SystemReading> {
    const [uptime, loadavg, memory] = await Promise.all([
      this.readUptime(),
      this.readLoadavg(),
      this.readMeminfo(),
    ]);
    return { uptimeSec: uptime, loadavg, memory };
  }

  private async readUptime(): Promise<number | null> {
    try {
      const s = await readFile(join(this.procRoot, "uptime"), "utf8");
      const n = Number(s.trim().split(/\s+/)[0]);
      return Number.isFinite(n) ? n : null;
    } catch {
      return null;
    }
  }

  private async readLoadavg(): Promise<SystemReading["loadavg"]> {
    try {
      const s = await readFile(join(this.procRoot, "loadavg"), "utf8");
      const parts = s.trim().split(/\s+/);
      const one = Number(parts[0]);
      const five = Number(parts[1]);
      const fifteen = Number(parts[2]);
      if (![one, five, fifteen].every(Number.isFinite)) return null;
      return { oneMin: one, fiveMin: five, fifteenMin: fifteen };
    } catch {
      return null;
    }
  }

  private async readMeminfo(): Promise<SystemReading["memory"]> {
    try {
      const s = await readFile(join(this.procRoot, "meminfo"), "utf8");
      const map = new Map<string, number>();
      for (const line of s.split("\n")) {
        const m = line.match(/^(\w+):\s+(\d+)\s*kB/);
        if (m) map.set(m[1]!, Number(m[2]));
      }
      const pick = (k: string) => map.get(k) ?? 0;
      return {
        totalKB: pick("MemTotal"),
        freeKB: pick("MemFree"),
        availableKB: pick("MemAvailable"),
        buffersKB: pick("Buffers"),
        cachedKB: pick("Cached"),
        swapTotalKB: pick("SwapTotal"),
        swapFreeKB: pick("SwapFree"),
      };
    } catch {
      return null;
    }
  }
}
