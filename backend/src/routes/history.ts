import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Storage } from "../storage/db.js";

const HistoryQuery = z.object({
  metric: z.string().min(1).max(100),
  from: z.coerce.number().int().nonnegative().optional(),
  to: z.coerce.number().int().nonnegative().optional(),
  range: z.enum(["1h", "6h", "24h", "7d"]).optional(),
  bucketMs: z.coerce.number().int().positive().optional(),
});

const RANGE_MS: Record<"1h" | "6h" | "24h" | "7d", number> = {
  "1h": 60 * 60 * 1000,
  "6h": 6 * 60 * 60 * 1000,
  "24h": 24 * 60 * 60 * 1000,
  "7d": 7 * 24 * 60 * 60 * 1000,
};

// Default bucket sizes keep chart series to roughly 300-600 points per request.
const DEFAULT_BUCKET_MS: Record<"1h" | "6h" | "24h" | "7d", number> = {
  "1h": 10_000, // raw
  "6h": 60_000, // 1 min
  "24h": 5 * 60_000, // 5 min
  "7d": 15 * 60_000, // 15 min
};

export function registerHistoryRoute(app: FastifyInstance, storage: Storage) {
  app.get("/api/history", async (req, reply) => {
    const parsed = HistoryQuery.safeParse(req.query);
    if (!parsed.success) {
      reply.code(400);
      return { error: "invalid_query", issues: parsed.error.issues };
    }
    const { metric, range } = parsed.data;
    const now = Date.now();
    const rangeKey = range ?? "1h";
    const from = parsed.data.from ?? now - RANGE_MS[rangeKey];
    const to = parsed.data.to ?? now;
    const bucketMs = parsed.data.bucketMs ?? DEFAULT_BUCKET_MS[rangeKey];

    const points = storage.querySamples(metric, from, to, bucketMs);
    return { metric, from, to, bucketMs, points };
  });
}
