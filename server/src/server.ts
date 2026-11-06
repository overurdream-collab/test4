import { pathToFileURL } from "node:url";
import Fastify, { type FastifyInstance } from "fastify";
import pg from "pg";
import {
  createSessionPrincipalResolver,
  registerIdentityApi,
  type OtpDeliveryAdapter
} from "./identity-api.js";
import { registerSyncApi } from "./sync-api.js";
import { registerApprovalApi } from "./approval-api.js";
import { registerAdminApi } from "./admin-api.js";

type Environment = Record<string, string | undefined>;

function required(env: Environment, name: string): string {
  const value = env[name]?.trim();
  if (!value) throw new Error(name + " is required");
  return value;
}

function bytes(env: Environment, name: string, fallback?: string): string {
  const value = env[name]?.trim() || fallback;
  if (!value) throw new Error(name + " is required");
  if (Buffer.byteLength(value, "utf8") < 32) {
    throw new Error(name + " must be at least 32 bytes");
  }
  return value;
}

export function createOtpDelivery(env: Environment): OtpDeliveryAdapter {
  const webhookUrl = env.OTP_WEBHOOK_URL?.trim();
  const webhookToken = env.OTP_WEBHOOK_TOKEN?.trim();
  if (webhookUrl) {
    return {
      async sendCode(phoneE164, code, expiresAt) {
        const response = await fetch(webhookUrl, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            ...(webhookToken ? { authorization: "Bearer " + webhookToken } : {})
          },
          body: JSON.stringify({ phoneE164, code, expiresAt: expiresAt.toISOString() })
        });
        if (!response.ok) {
          throw new Error("OTP delivery webhook returned " + response.status);
        }
      }
    };
  }
  if (env.NODE_ENV === "production") {
    throw new Error("OTP_WEBHOOK_URL is required in production");
  }
  return {
    async sendCode(phoneE164, code, expiresAt) {
      process.stderr.write(
        "[dev-otp] " + phoneE164 + " code=" + code + " expires=" + expiresAt.toISOString() + "\n"
      );
    }
  };
}

export function createServer(env: Environment = process.env): FastifyInstance {
  const pool = new pg.Pool({
    connectionString: required(env, "DATABASE_URL"),
    max: Number(env.DATABASE_POOL_MAX ?? "10")
  });
  const accessTokenSecret = bytes(env, "ACCESS_TOKEN_SECRET");
  const otpPepper = bytes(env, "OTP_PEPPER");
  const refreshTokenPepper = bytes(env, "REFRESH_TOKEN_PEPPER", accessTokenSecret);
  const allowedOrigins = new Set(
    (env.CORS_ALLOWED_ORIGINS ?? "")
      .split(",")
      .map(value => value.trim())
      .filter(Boolean)
  );

  const app = Fastify({ logger: env.NODE_ENV !== "test" });
  const resolvePrincipal = createSessionPrincipalResolver(pool, accessTokenSecret);

  app.addHook("onRequest", async (request, reply) => {
    const origin = request.headers.origin;
    if (typeof origin === "string" && allowedOrigins.has(origin)) {
      reply.header("Access-Control-Allow-Origin", origin);
      reply.header("Vary", "Origin");
      reply.header("Access-Control-Allow-Headers", "Authorization, Content-Type, Idempotency-Key");
      reply.header("Access-Control-Allow-Methods", "GET,POST,PATCH,OPTIONS");
      reply.header("Access-Control-Max-Age", "600");
    }
    if (request.method === "OPTIONS") {
      return reply.code(204).send();
    }
  });

  app.get("/health", async () => {
    const result = await pool.query<{ ok: boolean }>("SELECT true AS ok");
    return { status: result.rows[0]?.ok === true ? "ok" : "degraded" };
  });

  const otpDelivery = createOtpDelivery(env);
  app.register(async scope => {
    registerIdentityApi(scope, {
      pool,
      otpDelivery,
      otpPepper,
      accessTokenSecret,
      refreshTokenPepper
    });
  });
  app.register(async scope => {
    registerSyncApi(scope, { pool, resolvePrincipal });
  });
  app.register(async scope => {
    registerApprovalApi(scope, { pool, resolvePrincipal });
  });
  app.register(async scope => {
    registerAdminApi(scope, { pool, resolvePrincipal });
  });

  app.addHook("onClose", async () => {
    await pool.end();
  });

  return app;
}

async function start(): Promise<void> {
  const app = createServer();
  const port = Number(process.env.PORT ?? "8080");
  const host = process.env.HOST ?? "0.0.0.0";
  const shutdown = async () => {
    await app.close();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
  await app.listen({ port, host });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  start().catch(error => {
    process.stderr.write(String(error instanceof Error ? error.stack ?? error.message : error) + "\n");
    process.exit(1);
  });
}
