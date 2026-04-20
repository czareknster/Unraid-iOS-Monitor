import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Storage } from "../storage/db.js";

const RegisterBody = z.object({
  deviceToken: z.string().regex(/^[0-9a-fA-F]{64}$/, "expected 64-char hex APNs device token"),
  environment: z.enum(["sandbox", "production"]),
  name: z.string().max(100).optional(),
  appVersion: z.string().max(50).optional(),
});

export function registerDeviceRoutes(app: FastifyInstance, storage: Storage) {
  app.post("/api/devices", async (req, reply) => {
    const parsed = RegisterBody.safeParse(req.body);
    if (!parsed.success) {
      reply.code(400);
      return { error: "invalid_body", issues: parsed.error.issues };
    }
    storage.upsertDevice({
      deviceToken: parsed.data.deviceToken,
      environment: parsed.data.environment,
      name: parsed.data.name ?? null,
      appVersion: parsed.data.appVersion ?? null,
    });
    return { ok: true };
  });

  app.delete<{ Params: { token: string } }>("/api/devices/:token", async (req) => {
    const removed = storage.deleteDevice(req.params.token);
    return { ok: removed };
  });
}
