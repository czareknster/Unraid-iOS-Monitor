import { EventEmitter } from "node:events";
import type { FastifyBaseLogger } from "fastify";
import type { UnraidClient, UnraidNotification } from "../unraidClient.js";
import type { Storage } from "../storage/db.js";
import type { ApnsService, AppNotification } from "../apns.js";

export interface NewNotificationEvent {
  notification: UnraidNotification;
  app: AppNotification;
}

export class NotificationsPoller {
  readonly events = new EventEmitter();
  private timer: NodeJS.Timeout | null = null;
  private running = false;

  constructor(
    private readonly unraid: UnraidClient,
    private readonly storage: Storage,
    private readonly apns: ApnsService | null,
    private readonly log: FastifyBaseLogger,
    private readonly intervalMs: number,
  ) {}

  start(): void {
    if (this.timer) return;
    void this.tick(); // initial
    this.timer = setInterval(() => void this.tick(), this.intervalMs);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private async tick(): Promise<void> {
    if (this.running) return; // prevent overlap if a poll takes longer than the interval
    this.running = true;
    try {
      const unread = await this.unraid.listUnreadNotifications(50);
      const fresh = unread.filter((n) => !this.storage.isSeen(n.id));
      if (fresh.length === 0) return;

      // Chronological oldest-first so the newest ends up on top of the lock screen.
      fresh.reverse();
      for (const n of fresh) {
        const app = toAppNotification(n);
        this.events.emit("new", { notification: n, app } satisfies NewNotificationEvent);
        if (this.apns) {
          await this.apns.broadcast(app);
        }
      }
      this.storage.markSeen(fresh.map((n) => n.id));
      this.storage.pruneSeen();
      this.log.info({ count: fresh.length }, "notifications: pushed new batch");
    } catch (err) {
      this.log.warn({ err: (err as Error).message }, "notifications poll failed");
    } finally {
      this.running = false;
    }
  }
}

function toAppNotification(n: UnraidNotification): AppNotification {
  const thread = categorize(n);
  return {
    id: n.id,
    title: `${emojiFor(n.importance)} ${n.title || n.subject}`.trim(),
    body: n.description || n.subject || n.title,
    threadId: thread,
    importance: n.importance,
    route: routeFor(thread),
  };
}

function emojiFor(imp: UnraidNotification["importance"]): string {
  switch (imp) {
    case "ALERT": return "🚨";
    case "WARNING": return "⚠️";
    case "INFO": return "ℹ️";
  }
}

function categorize(n: UnraidNotification): string {
  const hay = `${n.title} ${n.subject} ${n.description}`.toLowerCase();
  if (hay.includes("parity")) return "parity";
  if (hay.includes("disk") || hay.includes("array")) return "array";
  if (hay.includes("docker") || hay.includes("container")) return "docker";
  if (hay.includes("cpu") || hay.includes("fan") || hay.includes("temperature")) return "system";
  return "system";
}

function routeFor(thread: string): string {
  switch (thread) {
    case "parity":
    case "array": return "/dashboard/array";
    case "docker": return "/dashboard/containers";
    default: return "/dashboard";
  }
}
