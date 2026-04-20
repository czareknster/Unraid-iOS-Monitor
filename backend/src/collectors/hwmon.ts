import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

// On ASRock B760M, nct6798 exposes many phantom sensors at 110+°C (unconnected
// thermistors) and AUXTIN pins reading -1°C. Only CPUTIN (temp2) and PECI (temp7)
// are meaningful. Filter anything out of this plausible range.
const MIN_PLAUSIBLE_C = 0;
const MAX_PLAUSIBLE_C = 105;

function parseMilliC(raw: string): number | null {
  const n = Number(raw.trim());
  if (!Number.isFinite(n)) return null;
  const c = n / 1000;
  if (c < MIN_PLAUSIBLE_C || c > MAX_PLAUSIBLE_C) return null;
  return Math.round(c * 10) / 10;
}

async function readTrim(path: string): Promise<string | null> {
  try {
    return (await readFile(path, "utf8")).trim();
  } catch {
    return null;
  }
}

async function readNumberFile(path: string): Promise<number | null> {
  const s = await readTrim(path);
  if (s === null) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

export interface HwmonReading {
  cpu: {
    packageC: number | null;
    cores: Array<{ label: string; tempC: number }>;
  };
  motherboard: {
    tempC: number | null; // CPUTIN from nct67xx
    pchC: number | null; // PCH/PECI if available
  };
  fans: Array<{ name: string; rpm: number }>;
  sources: string[]; // debugging — which hwmon devices contributed
}

export class HwmonCollector {
  constructor(private readonly sysRoot: string = "/sys") {}

  async read(): Promise<HwmonReading> {
    const result: HwmonReading = {
      cpu: { packageC: null, cores: [] },
      motherboard: { tempC: null, pchC: null },
      fans: [],
      sources: [],
    };

    const hwmonDir = join(this.sysRoot, "class", "hwmon");
    let entries: string[];
    try {
      entries = await readdir(hwmonDir);
    } catch {
      return result;
    }

    for (const entry of entries) {
      const dir = join(hwmonDir, entry);
      const name = (await readTrim(join(dir, "name")))?.toLowerCase();
      if (!name) continue;

      if (name === "coretemp") {
        await this.readCoretemp(dir, result);
        result.sources.push(`${entry}:coretemp`);
      } else if (name.startsWith("nct6") || name.startsWith("it87") || name.startsWith("k10temp")) {
        await this.readSuperIO(dir, result);
        result.sources.push(`${entry}:${name}`);
      }
    }

    // Sort cores by the numeric part of the label for stable UI
    result.cpu.cores.sort((a, b) => {
      const ai = Number(a.label.match(/\d+/)?.[0] ?? 0);
      const bi = Number(b.label.match(/\d+/)?.[0] ?? 0);
      return ai - bi;
    });

    return result;
  }

  private async readCoretemp(dir: string, out: HwmonReading): Promise<void> {
    const files = await readdir(dir);
    const labels = files.filter((f) => /^temp\d+_label$/.test(f));

    for (const labelFile of labels) {
      const idx = labelFile.match(/^temp(\d+)_label$/)?.[1];
      if (!idx) continue;
      const label = await readTrim(join(dir, labelFile));
      const tempRaw = await readTrim(join(dir, `temp${idx}_input`));
      if (!label || !tempRaw) continue;
      const tempC = parseMilliC(tempRaw);
      if (tempC === null) continue;

      if (label.startsWith("Package")) {
        out.cpu.packageC = tempC;
      } else if (label.startsWith("Core")) {
        out.cpu.cores.push({ label, tempC });
      }
    }
  }

  private async readSuperIO(dir: string, out: HwmonReading): Promise<void> {
    const files = await readdir(dir);

    // Temperatures: only pick CPUTIN (motherboard proxy) and PECI Agent (CPU via PECI)
    const tempLabels = files.filter((f) => /^temp\d+_label$/.test(f));
    for (const labelFile of tempLabels) {
      const idx = labelFile.match(/^temp(\d+)_label$/)?.[1];
      if (!idx) continue;
      const label = await readTrim(join(dir, labelFile));
      if (!label) continue;
      const tempC = parseMilliC((await readTrim(join(dir, `temp${idx}_input`))) ?? "");

      if (label === "CPUTIN" && tempC !== null && out.motherboard.tempC === null) {
        out.motherboard.tempC = tempC;
      } else if (label.startsWith("PECI") && tempC !== null && out.motherboard.pchC === null) {
        out.motherboard.pchC = tempC;
      }
    }

    // Fans: only report non-zero readings
    const fanInputs = files.filter((f) => /^fan\d+_input$/.test(f));
    for (const fanFile of fanInputs) {
      const idx = fanFile.match(/^fan(\d+)_input$/)?.[1];
      if (!idx) continue;
      const rpm = await readNumberFile(join(dir, fanFile));
      if (rpm === null || rpm <= 0) continue;
      const label = (await readTrim(join(dir, `fan${idx}_label`))) || `fan${idx}`;
      out.fans.push({ name: label, rpm });
    }
  }
}
