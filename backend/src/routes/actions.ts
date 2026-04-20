import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { UnraidClient } from "../unraidClient.js";

const DockerAction = z.enum(["start", "stop", "restart"]);
const ParityAction = z.enum(["pause", "resume", "cancel"]);

export function registerActionRoutes(app: FastifyInstance, unraid: UnraidClient) {
  app.post<{ Params: { id: string; action: string } }>(
    "/api/actions/docker/:id/:action",
    async (req, reply) => {
      const parsed = DockerAction.safeParse(req.params.action);
      if (!parsed.success) {
        reply.code(400);
        return { error: "invalid_action", allowed: DockerAction.options };
      }
      const id = decodeURIComponent(req.params.id);
      try {
        switch (parsed.data) {
          case "start":
            return { ok: true, container: await unraid.dockerStart(id) };
          case "stop":
            return { ok: true, container: await unraid.dockerStop(id) };
          case "restart": {
            // Unraid API has no restart mutation — stop then start.
            await unraid.dockerStop(id);
            // Wait briefly so the daemon releases the container state before starting.
            await new Promise((r) => setTimeout(r, 500));
            return { ok: true, container: await unraid.dockerStart(id) };
          }
        }
      } catch (err) {
        app.log.error({ err, id, action: parsed.data }, "docker action failed");
        reply.code(502);
        return { error: "upstream_failed", message: (err as Error).message };
      }
    },
  );

  app.post<{ Params: { action: string } }>("/api/actions/parity/:action", async (req, reply) => {
    const parsed = ParityAction.safeParse(req.params.action);
    if (!parsed.success) {
      reply.code(400);
      return { error: "invalid_action", allowed: ParityAction.options };
    }
    try {
      switch (parsed.data) {
        case "pause":
          return { ok: true, result: await unraid.parityPause() };
        case "resume":
          return { ok: true, result: await unraid.parityResume() };
        case "cancel":
          return { ok: true, result: await unraid.parityCancel() };
      }
    } catch (err) {
      app.log.error({ err, action: parsed.data }, "parity action failed");
      reply.code(502);
      return { error: "upstream_failed", message: (err as Error).message };
    }
  });
}
