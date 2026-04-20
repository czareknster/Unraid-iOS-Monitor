import type { FastifyBaseLogger } from "fastify";
import type { SnapshotAggregator } from "../collectors/snapshot.js";
import type { Storage } from "../storage/db.js";

const RETENTION_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

/**
 * Periodically runs a snapshot, extracts numeric metrics, persists them to
 * `samples` table, and prunes anything older than retention.
 */
export class MetricsSampler {
  private timer: NodeJS.Timeout | null = null;
  private pruneTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly aggregator: SnapshotAggregator,
    private readonly storage: Storage,
    private readonly log: FastifyBaseLogger,
    private readonly intervalMs: number,
  ) {}

  start(): void {
    if (this.timer) return;
    void this.tick();
    this.timer = setInterval(() => void this.tick(), this.intervalMs);
    // Prune hourly.
    this.pruneTimer = setInterval(() => this.prune(), 60 * 60 * 1000);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    if (this.pruneTimer) clearInterval(this.pruneTimer);
    this.timer = null;
    this.pruneTimer = null;
  }

  private async tick(): Promise<void> {
    try {
      const snap = await this.aggregator.collect();
      const ts = Date.now();
      const values = extractMetrics(snap);
      if (Object.keys(values).length === 0) return;
      this.storage.insertSamples(ts, values);
    } catch (err) {
      this.log.warn({ err: (err as Error).message }, "sampler tick failed");
    }
  }

  private prune(): void {
    try {
      const cutoff = Date.now() - RETENTION_MS;
      const removed = this.storage.pruneSamples(cutoff);
      if (removed > 0) this.log.info({ removed }, "pruned old samples");
    } catch (err) {
      this.log.warn({ err: (err as Error).message }, "sampler prune failed");
    }
  }
}

function extractMetrics(snap: Awaited<ReturnType<SnapshotAggregator["collect"]>>): Record<string, number> {
  const out: Record<string, number> = {};
  const put = (key: string, v: number | null | undefined) => {
    if (typeof v === "number" && Number.isFinite(v)) out[key] = v;
  };

  // Unraid-side metrics
  put("cpu.loadPercent", snap.unraid?.metrics.cpu.percentTotal);
  const cpus = snap.unraid?.metrics.cpu.cpus ?? [];
  cpus.forEach((c, i) => put(`cpu.thread${i}.loadPercent`, c.percentTotal));
  put("memory.percent", snap.unraid?.metrics.memory.percentTotal);
  put("memory.used", snap.unraid?.metrics.memory.used);

  // Array usage (bytes used = total - free, in KB — store as MB to keep numbers smaller)
  const totalKb = Number(snap.unraid?.array.capacity.kilobytes.total);
  const freeKb = Number(snap.unraid?.array.capacity.kilobytes.free);
  if (Number.isFinite(totalKb) && Number.isFinite(freeKb)) {
    put("array.usedMB", (totalKb - freeKb) / 1024);
  }

  // Per-disk temps
  for (const d of snap.unraid?.array.parities ?? []) put(`disk.${d.name}.tempC`, d.temp ?? null);
  for (const d of snap.unraid?.array.disks ?? []) put(`disk.${d.name}.tempC`, d.temp ?? null);
  for (const d of snap.unraid?.array.caches ?? []) put(`disk.${d.name}.tempC`, d.temp ?? null);

  // Hwmon
  put("cpu.packageC", snap.hwmon?.cpu.packageC);
  const cores = snap.hwmon?.cpu.cores ?? [];
  if (cores.length > 0) {
    const temps = cores.map((c) => c.tempC);
    put("cpu.coreMaxC", Math.max(...temps));
    put("cpu.coreAvgC", temps.reduce((a, b) => a + b, 0) / temps.length);
  }
  put("mb.tempC", snap.hwmon?.motherboard.tempC);
  for (const f of snap.hwmon?.fans ?? []) put(`fan.${f.name}.rpm`, f.rpm);

  // GPU
  put("gpu.busyPercent", snap.gpu?.busyPercent);
  put("gpu.rc6Percent", snap.gpu?.rc6Percent);
  put("gpu.powerW", snap.gpu?.powerW);
  put("gpu.tempC", snap.gpu?.tempC);

  // System
  put("system.loadavg1", snap.system?.loadavg?.oneMin);

  return out;
}
