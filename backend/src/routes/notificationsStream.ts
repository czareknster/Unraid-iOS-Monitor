import type { FastifyInstance } from "fastify";
import type { NotificationsPoller, NewNotificationEvent } from "../worker/notificationsPoller.js";

export function registerNotificationsStream(app: FastifyInstance, poller: NotificationsPoller) {
  app.get("/api/notifications/stream", async (req, reply) => {
    reply.hijack();
    const raw = reply.raw;

    raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    raw.write(`: connected\n\n`);

    const onNew = (ev: NewNotificationEvent) => {
      raw.write(`event: notification\n`);
      raw.write(`data: ${JSON.stringify(ev.notification)}\n\n`);
    };

    const heartbeat = setInterval(() => {
      raw.write(`: ping ${Date.now()}\n\n`);
    }, 25_000);

    poller.events.on("new", onNew);

    const close = () => {
      clearInterval(heartbeat);
      poller.events.off("new", onNew);
      try {
        raw.end();
      } catch {
        /* ignore */
      }
    };

    req.raw.on("close", close);
    req.raw.on("error", close);
  });
}
