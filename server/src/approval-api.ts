import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import type { Pool } from "pg";

export type AuthenticatedPrincipal = {
  userId: string;
  deviceId: string;
};

export type PrincipalResolver = (
  request: FastifyRequest
) => Promise<AuthenticatedPrincipal | null>;

type Dependencies = {
  pool: Pick<Pool, "query">;
  resolvePrincipal: PrincipalResolver;
};

type DecisionParams = { relationshipId: string; operationId: string };
type DecisionBody = {
  decision: "approved" | "rejected";
  expectedVersion: number;
  reason?: string;
};

declare module "fastify" {
  interface FastifyRequest {
    principal: AuthenticatedPrincipal | null;
  }
}

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function statusForDatabaseError(code: string | undefined): number {
  switch (code) {
    case "42501": return 403;
    case "23503": return 404;
    case "40001":
    case "55000":
    case "23505": return 409;
    case "22023":
    case "23514": return 422;
    default: return 500;
  }
}

export function buildApprovalApi({
  pool,
  resolvePrincipal
}: Dependencies): FastifyInstance {
  const app = Fastify({ logger: false });
  app.decorateRequest("principal", null);

  app.addHook("preHandler", async (request, reply) => {
    try {
      const principal = await resolvePrincipal(request);
      if (!principal || !UUID.test(principal.userId) || !UUID.test(principal.deviceId)) {
        return reply.code(401).send({ error: "unauthorized" });
      }
      request.principal = principal;
    } catch {
      return reply.code(401).send({ error: "unauthorized" });
    }
  });

  app.post<{ Params: DecisionParams; Body: DecisionBody }>(
    "/v1/relationships/:relationshipId/operations/:operationId/decision",
    {
      schema: {
        params: {
          type: "object",
          required: ["relationshipId", "operationId"],
          properties: {
            relationshipId: { type: "string", format: "uuid" },
            operationId: { type: "string", format: "uuid" }
          }
        },
        headers: {
          type: "object",
          required: ["idempotency-key"],
          properties: {
            "idempotency-key": { type: "string", format: "uuid" }
          }
        },
        body: {
          type: "object",
          additionalProperties: false,
          required: ["decision", "expectedVersion"],
          properties: {
            decision: { type: "string", enum: ["approved", "rejected"] },
            expectedVersion: { type: "integer", minimum: 1 },
            reason: { type: "string", maxLength: 1000 }
          }
        }
      }
    },
    async (request, reply) => {
      const idempotencyKey = request.headers["idempotency-key"];
      if (typeof idempotencyKey !== "string" || !UUID.test(idempotencyKey)) {
        return reply.code(400).send({ error: "invalid_idempotency_key" });
      }

      const principal = request.principal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });

      try {
        const result = await pool.query<{ server_version: string | number }>(
          "SELECT ledger.decide_operation(" +
            "$1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::bigint, $6::text, $7::text" +
          ") AS server_version",
          [
            idempotencyKey,
            request.params.relationshipId,
            request.params.operationId,
            principal.userId,
            request.body.expectedVersion,
            request.body.decision,
            request.body.reason ?? null
          ]
        );

        const serverVersion = Number(result.rows[0]?.server_version);
        if (!Number.isSafeInteger(serverVersion) || serverVersion < 1) {
          request.log.error("Approval database function returned an invalid version");
          return reply.code(500).send({ error: "internal_error" });
        }

        return reply.code(200).send({
          status: "accepted",
          decisionId: idempotencyKey,
          businessState: request.body.decision,
          serverVersion
        });
      } catch (error) {
        const code =
          typeof error === "object" && error !== null && "code" in error
            ? String((error as { code: unknown }).code)
            : undefined;
        const status = statusForDatabaseError(code);
        if (status === 500) {
          request.log.error({ err: error }, "Approval decision failed");
          return reply.code(500).send({ error: "internal_error" });
        }
        const errorCode =
          status === 403 ? "forbidden" :
          status === 404 ? "not_found" :
          status === 409 ? "conflict" : "validation_error";
        return reply.code(status).send({ error: errorCode });
      }
    }
  );

  return app;
}
