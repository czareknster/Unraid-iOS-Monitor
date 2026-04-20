import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { join } from "node:path";

export type Environment = "sandbox" | "production";

export interface DeviceRow {
  deviceToken: string;
  environment: Environment;
  name: string | null;
  appVersion: string | null;
  createdAt: number;
  updatedAt: number;
}

export class Storage {
  private db: Database.Database;

  constructor(dataDir: string) {
    mkdirSync(dataDir, { recursive: true });
    this.db = new Database(join(dataDir, "unraid-monitor.db"));
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("foreign_keys = ON");
    this.migrate();
  }

  private migrate(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS devices (
        deviceToken TEXT PRIMARY KEY,
        environment TEXT NOT NULL CHECK(environment IN ('sandbox','production')),
        name        TEXT,
        appVersion  TEXT,
        createdAt   INTEGER NOT NULL,
        updatedAt   INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS seen_notifications (
        id        TEXT PRIMARY KEY,
        seenAt    INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_seen_notifications_seenAt
        ON seen_notifications(seenAt);

      CREATE TABLE IF NOT EXISTS samples (
        ts     INTEGER NOT NULL,
        metric TEXT    NOT NULL,
        value  REAL    NOT NULL,
        PRIMARY KEY (metric, ts)
      ) WITHOUT ROWID;
    `);
  }

  insertSamples(ts: number, values: Record<string, number>): void {
    const stmt = this.db.prepare(`INSERT OR REPLACE INTO samples (ts, metric, value) VALUES (?, ?, ?)`);
    const tx = this.db.transaction((entries: Array<[string, number]>) => {
      for (const [metric, value] of entries) stmt.run(ts, metric, value);
    });
    tx(Object.entries(values));
  }

  querySamples(
    metric: string,
    fromTs: number,
    toTs: number,
    bucketMs: number,
  ): Array<{ ts: number; value: number }> {
    // Downsample by averaging within buckets. Bucket key = floor(ts / bucketMs).
    const rows = this.db
      .prepare(
        // CAST ... AS INTEGER keeps bucketStart as a true int — without it, SQLite's
        // `ts / bucketMs` widens to a float and JSON emits e.g. 1776607736883.0002
        // which iOS then fails to decode as Int.
        `SELECT CAST(ts / ? AS INTEGER) * ? AS bucketStart, AVG(value) AS value
         FROM samples
         WHERE metric = ? AND ts >= ? AND ts <= ?
         GROUP BY bucketStart
         ORDER BY bucketStart ASC`,
      )
      .all(bucketMs, bucketMs, metric, fromTs, toTs) as Array<{ bucketStart: number; value: number }>;
    return rows.map((r) => ({ ts: r.bucketStart, value: r.value }));
  }

  pruneSamples(olderThanTs: number): number {
    const info = this.db.prepare(`DELETE FROM samples WHERE ts < ?`).run(olderThanTs);
    return info.changes;
  }

  upsertDevice(input: Omit<DeviceRow, "createdAt" | "updatedAt">): void {
    const now = Date.now();
    this.db
      .prepare(
        `INSERT INTO devices (deviceToken, environment, name, appVersion, createdAt, updatedAt)
         VALUES (@deviceToken, @environment, @name, @appVersion, @now, @now)
         ON CONFLICT(deviceToken) DO UPDATE SET
           environment = excluded.environment,
           name        = excluded.name,
           appVersion  = excluded.appVersion,
           updatedAt   = excluded.updatedAt`,
      )
      .run({ ...input, now });
  }

  deleteDevice(deviceToken: string): boolean {
    const info = this.db.prepare(`DELETE FROM devices WHERE deviceToken = ?`).run(deviceToken);
    return info.changes > 0;
  }

  allDevices(): DeviceRow[] {
    return this.db.prepare(`SELECT * FROM devices`).all() as DeviceRow[];
  }

  isSeen(id: string): boolean {
    return !!this.db.prepare(`SELECT 1 FROM seen_notifications WHERE id = ?`).get(id);
  }

  markSeen(ids: string[]): void {
    if (ids.length === 0) return;
    const now = Date.now();
    const stmt = this.db.prepare(
      `INSERT OR IGNORE INTO seen_notifications (id, seenAt) VALUES (?, ?)`,
    );
    const tx = this.db.transaction((batch: string[]) => {
      for (const id of batch) stmt.run(id, now);
    });
    tx(ids);
  }

  /** Keep only the most recent N seen records to cap growth. */
  pruneSeen(keep = 500): void {
    this.db
      .prepare(
        `DELETE FROM seen_notifications
         WHERE id NOT IN (
           SELECT id FROM seen_notifications ORDER BY seenAt DESC LIMIT ?
         )`,
      )
      .run(keep);
  }

  close(): void {
    this.db.close();
  }
}
