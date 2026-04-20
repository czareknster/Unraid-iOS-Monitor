import type { UnraidClient, UnraidSnapshot } from "../unraidClient.js";
import type { HwmonCollector, HwmonReading } from "./hwmon.js";
import type { GpuCollector, GpuReading } from "./gpu.js";
import type { SystemCollector, SystemReading } from "./system.js";

export interface AggregateSnapshot {
  ts: string;
  unraid: UnraidSnapshot | null;
  hwmon: HwmonReading | null;
  gpu: GpuReading | null;
  system: SystemReading | null;
  errors: Record<string, string>;
}

export class SnapshotAggregator {
  constructor(
    private readonly unraid: UnraidClient,
    private readonly hwmon: HwmonCollector,
    private readonly gpu: GpuCollector,
    private readonly system: SystemCollector,
  ) {}

  async collect(): Promise<AggregateSnapshot> {
    const errors: Record<string, string> = {};

    const settle = async <T>(key: string, p: Promise<T>): Promise<T | null> => {
      try {
        return await p;
      } catch (err) {
        errors[key] = (err as Error).message;
        return null;
      }
    };

    const [unraid, hwmon, gpu, system] = await Promise.all([
      settle("unraid", this.unraid.snapshot()),
      settle("hwmon", this.hwmon.read()),
      settle("gpu", this.gpu.read()),
      settle("system", this.system.read()),
    ]);

    return {
      ts: new Date().toISOString(),
      unraid,
      hwmon,
      gpu,
      system,
      errors,
    };
  }
}
