import type { FastifyInstance } from "fastify";
import type { SnapshotAggregator } from "../collectors/snapshot.js";

export function registerSnapshotRoute(app: FastifyInstance, aggregator: SnapshotAggregator) {
  app.get("/api/snapshot", async (_req) => {
    return aggregator.collect();
  });
}
