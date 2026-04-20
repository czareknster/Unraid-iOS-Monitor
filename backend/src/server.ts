import Fastify from "fastify";
import sensible from "@fastify/sensible";
import { loadConfig } from "./config.js";
import { registerAuth } from "./auth.js";
import { UnraidClient } from "./unraidClient.js";
import { HwmonCollector } from "./collectors/hwmon.js";
import { GpuCollector } from "./collectors/gpu.js";
import { SystemCollector } from "./collectors/system.js";
import { SnapshotAggregator } from "./collectors/snapshot.js";
import { registerSnapshotRoute } from "./routes/snapshot.js";
import { Storage } from "./storage/db.js";
import { ApnsService } from "./apns.js";
import { NotificationsPoller } from "./worker/notificationsPoller.js";
import { registerDeviceRoutes } from "./routes/devices.js";
import { registerNotificationsStream } from "./routes/notificationsStream.js";
import { registerActionRoutes } from "./routes/actions.js";
import { registerHistoryRoute } from "./routes/history.js";
import { registerNotificationsListRoute } from "./routes/notifications.js";
import { MetricsSampler } from "./worker/sampler.js";

async function main() {
  const cfg = loadConfig();

  const app = Fastify({
    logger: {
      level: cfg.LOG_LEVEL,
      transport: process.env.NODE_ENV === "production" ? undefined : { target: "pino-pretty" },
    },
    trustProxy: true,
  });

  await app.register(sensible);

  app.get("/healthz", async () => ({ ok: true }));

  registerAuth(app, cfg.APP_TOKEN);

  const unraid = new UnraidClient(cfg.UNRAID_API_URL, cfg.UNRAID_API_KEY);
  const hwmon = new HwmonCollector(cfg.HOST_SYS);
  const gpu = new GpuCollector(cfg.HOST_SYS);
  const system = new SystemCollector(cfg.HOST_PROC);
  const aggregator = new SnapshotAggregator(unraid, hwmon, gpu, system);
  const storage = new Storage(cfg.DATA_DIR);

  let apns: ApnsService | null = null;
  const hasApnsCreds = cfg.APNS_TEAM_ID && cfg.APNS_KEY_ID && cfg.APNS_KEY_PATH && cfg.APNS_BUNDLE_ID;
  if (hasApnsCreds) {
    apns = new ApnsService(
      {
        teamId: cfg.APNS_TEAM_ID!,
        keyId: cfg.APNS_KEY_ID!,
        keyPath: cfg.APNS_KEY_PATH!,
        bundleId: cfg.APNS_BUNDLE_ID!,
      },
      storage,
      app.log,
    );
    try {
      await apns.init();
      app.log.info({ bundleId: cfg.APNS_BUNDLE_ID }, "APNs ready");
    } catch (err) {
      app.log.error({ err }, "APNs init failed — push disabled");
      apns = null;
    }
  } else {
    app.log.warn("APNs credentials not set — push notifications disabled (SSE still works)");
  }

  const poller = new NotificationsPoller(unraid, storage, apns, app.log, cfg.NOTIFICATIONS_POLL_INTERVAL_MS);

  app.get("/api/ping", async () => ({
    pong: true,
    ts: new Date().toISOString(),
    apns: Boolean(apns),
  }));

  registerSnapshotRoute(app, aggregator);
  registerDeviceRoutes(app, storage);
  registerNotificationsStream(app, poller);
  registerActionRoutes(app, unraid);
  registerHistoryRoute(app, storage);
  registerNotificationsListRoute(app, unraid);

  const sampler = new MetricsSampler(aggregator, storage, app.log, cfg.SAMPLER_INTERVAL_MS);
  poller.start();
  sampler.start();

  const shutdown = async (signal: string) => {
    app.log.info({ signal }, "shutting down");
    try {
      poller.stop();
      sampler.stop();
      await apns?.close();
      await app.close();
      storage.close();
      process.exit(0);
    } catch (err) {
      app.log.error({ err }, "shutdown error");
      process.exit(1);
    }
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));

  try {
    await app.listen({ port: cfg.PORT, host: cfg.HOST });
  } catch (err) {
    app.log.error({ err }, "listen failed");
    process.exit(1);
  }
}

main();
