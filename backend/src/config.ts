import { z } from "zod";

const schema = z.object({
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default("0.0.0.0"),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"]).default("info"),

  APP_TOKEN: z.string().min(32, "APP_TOKEN must be at least 32 chars (use: openssl rand -hex 32)"),

  // Unraid API is served by nginx on the main webUI port (not port 3001)
  UNRAID_API_URL: z.string().url().default("http://localhost/graphql"),
  UNRAID_API_KEY: z.string().min(1),

  HOST_SYS: z.string().default("/host/sys"),
  HOST_PROC: z.string().default("/host/proc"),

  DATA_DIR: z.string().default("/data"),

  // APNs (token-based auth). All optional — if any missing, push is disabled
  // but the poller still runs and SSE still works.
  APNS_TEAM_ID: z.string().optional(),
  APNS_KEY_ID: z.string().optional(),
  APNS_KEY_PATH: z.string().optional(),
  APNS_BUNDLE_ID: z.string().optional(),

  NOTIFICATIONS_POLL_INTERVAL_MS: z.coerce.number().int().positive().default(30_000),
  SAMPLER_INTERVAL_MS: z.coerce.number().int().positive().default(10_000),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(): Config {
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    console.error("Invalid environment configuration:");
    for (const issue of parsed.error.issues) {
      console.error(`  ${issue.path.join(".")}: ${issue.message}`);
    }
    process.exit(1);
  }
  return parsed.data;
}
