import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { ApnsClient, ApnsError, Notification, Host, Priority } from "apns2";
import type { FastifyBaseLogger } from "fastify";
import type { Environment, Storage } from "./storage/db.js";

/**
 * APNs collapse-id is capped at 64 bytes. Unraid notification IDs are long
 * (`<parent>:Unraid_Status_<ts>.notify`), so hash to fit the limit deterministically.
 */
function collapseIdFor(notificationId: string): string {
  return createHash("sha1").update(notificationId).digest("hex");
}

export interface ApnsConfig {
  teamId: string;
  keyId: string;
  keyPath: string;
  bundleId: string;
}

export interface AppNotification {
  id: string;
  title: string;
  body: string;
  threadId?: string; // grouping on lock screen (array/docker/system)
  importance: "INFO" | "WARNING" | "ALERT";
  route?: string; // deep link path inside the app
}

type ClientCache = Partial<Record<Environment, ApnsClient>>;

export class ApnsService {
  private clients: ClientCache = {};
  private signingKey: string | null = null;

  constructor(
    private readonly cfg: ApnsConfig,
    private readonly storage: Storage,
    private readonly log: FastifyBaseLogger,
  ) {}

  async init(): Promise<void> {
    this.signingKey = await readFile(this.cfg.keyPath, "utf8");
  }

  private clientFor(env: Environment): ApnsClient {
    const existing = this.clients[env];
    if (existing) return existing;
    if (!this.signingKey) throw new Error("APNs signing key not loaded");
    const client = new ApnsClient({
      team: this.cfg.teamId,
      keyId: this.cfg.keyId,
      signingKey: this.signingKey,
      defaultTopic: this.cfg.bundleId,
      host: env === "production" ? Host.production : Host.development,
    });
    this.clients[env] = client;
    return client;
  }

  async broadcast(notification: AppNotification): Promise<void> {
    const devices = this.storage.allDevices();
    if (devices.length === 0) return;

    const priority = notification.importance === "ALERT" ? Priority.immediate : Priority.throttled;
    const interruptionLevel = ({
      ALERT: "time-sensitive",
      WARNING: "active",
      INFO: "passive",
    } as const)[notification.importance];

    const byEnv: Record<Environment, Notification[]> = { sandbox: [], production: [] };
    for (const d of devices) {
      const n = new Notification(d.deviceToken, {
        alert: { title: notification.title, body: notification.body },
        sound: notification.importance === "INFO" ? undefined : "default",
        threadId: notification.threadId,
        category: notification.threadId,
        priority,
        topic: this.cfg.bundleId,
        collapseId: collapseIdFor(notification.id),
        aps: {
          "interruption-level": interruptionLevel,
        },
        data: {
          notificationId: notification.id,
          route: notification.route ?? null,
          importance: notification.importance,
        },
      });
      byEnv[d.environment].push(n);
    }

    for (const env of ["sandbox", "production"] as const) {
      const batch = byEnv[env];
      if (batch.length === 0) continue;
      try {
        const results = await this.clientFor(env).sendMany(batch);
        const isFailure = (r: Notification | { error: ApnsError }): r is { error: ApnsError } =>
          "error" in r;
        const failures = results.filter(isFailure);
        if (failures.length > 0) {
          this.log.warn(
            { env, total: batch.length, failed: failures.length, sample: failures[0]?.error?.reason },
            "APNs delivery partial failure",
          );
          // BadDeviceToken / Unregistered → drop the device so we stop pinging dead tokens
          for (let i = 0; i < results.length; i++) {
            const r = results[i]!;
            if (isFailure(r)) {
              const reason = r.error.reason ?? r.error.message;
              if (reason === "BadDeviceToken" || reason === "Unregistered") {
                const token = batch[i]!.deviceToken;
                this.storage.deleteDevice(token);
                this.log.info({ env, token: token.slice(0, 8) + "…", reason }, "dropped unregistered device");
              }
            }
          }
        }
      } catch (err) {
        this.log.error({ err, env }, "APNs sendMany failed");
      }
    }
  }

  async close(): Promise<void> {
    await Promise.all(Object.values(this.clients).map((c) => c?.close().catch(() => {})));
  }
}
