import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { UnraidClient } from "../unraidClient.js";

const ListQuery = z.object({
  type: z.enum(["UNREAD", "ARCHIVE"]).default("UNREAD"),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

export function registerNotificationsListRoute(app: FastifyInstance, unraid: UnraidClient) {
  app.get("/api/notifications", async (req, reply) => {
    const parsed = ListQuery.safeParse(req.query);
    if (!parsed.success) {
      reply.code(400);
      return { error: "invalid_query", issues: parsed.error.issues };
    }
    try {
      const list = await unraid.listNotifications(parsed.data.type, parsed.data.limit, parsed.data.offset);
      return { list };
    } catch (err) {
      app.log.error({ err }, "notifications list failed");
      reply.code(502);
      return { error: "upstream_failed", message: (err as Error).message };
    }
  });

  app.post<{ Params: { id: string } }>("/api/notifications/:id/archive", async (req, reply) => {
    const id = decodeURIComponent(req.params.id);
    try {
      await unraid.archiveNotification(id);
      return { ok: true };
    } catch (err) {
      app.log.error({ err, id }, "archive notification failed");
      reply.code(502);
      return { error: "upstream_failed", message: (err as Error).message };
    }
  });

  app.post<{ Params: { id: string } }>("/api/notifications/:id/unarchive", async (req, reply) => {
    const id = decodeURIComponent(req.params.id);
    try {
      await unraid.unarchiveNotifications([id]);
      return { ok: true };
    } catch (err) {
      app.log.error({ err, id }, "unarchive notification failed");
      reply.code(502);
      return { error: "upstream_failed", message: (err as Error).message };
    }
  });

  app.post("/api/notifications/archive-all", async (_req, reply) => {
    try {
      const result = await unraid.archiveAll();
      return { ok: true, result };
    } catch (err) {
      app.log.error({ err }, "archive-all failed");
      reply.code(502);
      return { error: "upstream_failed", message: (err as Error).message };
    }
  });
}
