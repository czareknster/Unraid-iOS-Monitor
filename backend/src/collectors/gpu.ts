import { spawn } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

export interface GpuReading {
  present: boolean;
  tempC: number | null;
  rc6Percent: number | null; // idle residency (100 = fully idle)
  busyPercent: number | null; // highest engine usage (approximation of "GPU load")
  frequencyMhz: number | null;
  powerW: number | null;
  engines: Record<string, number> | null; // per-engine busy%
  error?: string;
}

const MAX_PLAUSIBLE_TEMP_C = 110;

export class GpuCollector {
  constructor(private readonly sysRoot: string = "/sys") {}

  async read(): Promise<GpuReading> {
    const out: GpuReading = {
      present: false,
      tempC: null,
      rc6Percent: null,
      busyPercent: null,
      frequencyMhz: null,
      powerW: null,
      engines: null,
    };

    await this.readDrmTemp(out);
    await this.readIntelGpuTop(out);

    return out;
  }

  private async readDrmTemp(out: GpuReading): Promise<void> {
    const drmDir = join(this.sysRoot, "class", "drm");
    let cards: string[];
    try {
      cards = (await readdir(drmDir)).filter((e) => /^card\d+$/.test(e));
    } catch {
      return;
    }
    if (cards.length > 0) out.present = true;

    for (const card of cards) {
      const hwmonBase = join(drmDir, card, "device", "hwmon");
      let entries: string[] = [];
      try {
        entries = await readdir(hwmonBase);
      } catch {
        continue;
      }
      for (const entry of entries) {
        try {
          const raw = await readFile(join(hwmonBase, entry, "temp1_input"), "utf8");
          const c = Number(raw.trim()) / 1000;
          if (Number.isFinite(c) && c > 0 && c < MAX_PLAUSIBLE_TEMP_C) {
            out.tempC = Math.round(c * 10) / 10;
            return;
          }
        } catch {
          // no temp exposed (typical for Intel iGPU Alder/Raptor Lake)
        }
      }
    }
  }

  /**
   * Spawns `intel_gpu_top -J -s 500` for ~1.3s, captures 2+ samples,
   * parses the last complete JSON object (the streaming output is a
   * bare sequence of concatenated objects, not a valid JSON document).
   */
  private async readIntelGpuTop(out: GpuReading): Promise<void> {
    const sample = await spawnIntelGpuTop(1300);
    if (!sample) return;

    try {
      const freq = sample.frequency?.actual;
      if (typeof freq === "number" && freq > 0) out.frequencyMhz = Math.round(freq);

      const rc6 = sample.rc6?.value;
      if (typeof rc6 === "number") out.rc6Percent = Math.round(rc6 * 10) / 10;

      const powerGpu = sample.power?.GPU;
      const powerPkg = sample.power?.Package;
      const power = typeof powerGpu === "number" && powerGpu > 0 ? powerGpu : powerPkg;
      if (typeof power === "number") out.powerW = Math.round(power * 10) / 10;

      if (sample.engines && typeof sample.engines === "object") {
        const engines: Record<string, number> = {};
        let maxBusy = 0;
        for (const [name, data] of Object.entries(sample.engines as Record<string, { busy?: number }>)) {
          const busy = data?.busy;
          if (typeof busy === "number") {
            engines[name] = Math.round(busy * 10) / 10;
            if (busy > maxBusy) maxBusy = busy;
          }
        }
        out.engines = engines;
        out.busyPercent = Math.round(maxBusy * 10) / 10;
      }
      out.present = true;
    } catch (err) {
      out.error = (err as Error).message;
    }
  }
}

interface GpuTopSample {
  frequency?: { actual?: number; requested?: number };
  rc6?: { value?: number };
  power?: { GPU?: number; Package?: number };
  engines?: Record<string, { busy?: number }>;
}

function spawnIntelGpuTop(timeoutMs: number): Promise<GpuTopSample | null> {
  return new Promise((resolve) => {
    let proc: ReturnType<typeof spawn>;
    try {
      proc = spawn("intel_gpu_top", ["-J", "-s", "500"], { stdio: ["ignore", "pipe", "ignore"] });
    } catch {
      resolve(null);
      return;
    }

    let buf = "";
    let resolved = false;

    const finish = (sample: GpuTopSample | null) => {
      if (resolved) return;
      resolved = true;
      try {
        proc.kill("SIGTERM");
      } catch {
        /* ignore */
      }
      resolve(sample);
    };

    proc.stdout?.on("data", (chunk: Buffer) => {
      buf += chunk.toString("utf8");
    });
    proc.on("error", () => finish(null));
    proc.on("exit", () => {
      if (!resolved) finish(parseLastObject(buf));
    });
    setTimeout(() => finish(parseLastObject(buf)), timeoutMs);
  });
}

function parseLastObject(buf: string): GpuTopSample | null {
  // Output format: `[\n{...},\n{...},\n` — we want the last balanced {...} block.
  let depth = 0;
  let start = -1;
  let lastComplete: string | null = null;
  for (let i = 0; i < buf.length; i++) {
    const ch = buf[i];
    if (ch === "{") {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0 && start >= 0) {
        lastComplete = buf.slice(start, i + 1);
        start = -1;
      }
    }
  }
  if (!lastComplete) return null;
  try {
    return JSON.parse(lastComplete) as GpuTopSample;
  } catch {
    return null;
  }
}
