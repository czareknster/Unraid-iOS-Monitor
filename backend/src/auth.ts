import type { FastifyInstance, FastifyRequest, FastifyReply } from "fastify";
import { timingSafeEqual } from "node:crypto";

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

export function registerAuth(app: FastifyInstance, token: string) {
  app.addHook("onRequest", async (req: FastifyRequest, reply: FastifyReply) => {
    if (req.url === "/healthz") return;

    const header = req.headers.authorization;
    if (!header || !header.startsWith("Bearer ")) {
      reply.code(401).send({ error: "unauthorized" });
      return reply;
    }
    const presented = header.slice("Bearer ".length).trim();
    if (!safeEqual(presented, token)) {
      reply.code(401).send({ error: "unauthorized" });
      return reply;
    }
  });
}
