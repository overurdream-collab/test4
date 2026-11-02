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

  app.post<{ Params: { relationshipId: string } }>(
    "/v1/relationships/:relationshipId/settlement-reset-requests",
    {
      schema: {
        params: {
          type: "object",
          required: ["relationshipId"],
          properties: { relationshipId: { type: "string", format: "uuid" } }
        },
        headers: {
          type: "object",
          required: ["idempotency-key"],
          properties: { "idempotency-key": { type: "string", format: "uuid" } }
        },
        body: { type: "object", additionalProperties: false }
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
        const result = await pool.query<{ request_id: string }>(
          "SELECT ledger.request_settlement_reset($1::uuid,$2::uuid,$3::uuid) AS request_id",
          [idempotencyKey, request.params.relationshipId, principal.userId]
        );
        const requestId = result.rows[0]?.request_id;
        if (requestId !== idempotencyKey) {
          request.log.error("Settlement request function returned an unexpected request ID");
          return reply.code(500).send({ error: "internal_error" });
        }
        return reply.code(201).send({ status: "requested", requestId });
      } catch (error) {
        const code =
          typeof error === "object" && error !== null && "code" in error
            ? String((error as { code: unknown }).code)
            : undefined;
        if (code === "23514") {
          return reply.code(409).send({ error: "settlement_not_complete" });
        }
        const status = statusForDatabaseError(code);
        if (status === 500) {
          request.log.error({ err: error }, "Settlement reset request failed");
          return reply.code(500).send({ error: "internal_error" });
        }
        const errorCode = status === 403 ? "forbidden" : status === 404 ? "not_found" :
          status === 409 ? "conflict" : "validation_error";
        return reply.code(status).send({ error: errorCode });
      }
    }
  );


  app.get<{ Params: { relationshipId: string } }>(
    "/v1/relationships/:relationshipId/settlement-reset-requests/pending",
    {
      schema: {
        params: {
          type: "object",
          required: ["relationshipId"],
          properties: { relationshipId: { type: "string", format: "uuid" } }
        }
      }
    },
    async (request, reply) => {
      const principal = request.principal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      try {
        const result = await pool.query<{
          authorized: boolean;
          request_id: string | null;
          requested_by_user_id: string | null;
          requested_at: Date | string | null;
        }>(
          "WITH auth AS (" +
            " SELECT EXISTS (SELECT 1 FROM ledger.relationship_members" +
            " WHERE relationship_id=$1::uuid AND user_id=$2::uuid AND status='active') AS authorized" +
          ") SELECT auth.authorized, sr.id AS request_id, sr.requested_by_user_id, sr.requested_at" +
          " FROM auth LEFT JOIN LATERAL (" +
            " SELECT sr.id, sr.requested_by_user_id, sr.requested_at" +
            " FROM ledger.settlement_requests sr" +
            " LEFT JOIN ledger.settlement_decisions sd ON sd.request_id=sr.id" +
            " WHERE sr.relationship_id=$1::uuid AND sd.request_id IS NULL" +
            " ORDER BY sr.requested_at DESC LIMIT 1" +
          ") sr ON auth.authorized",
          [request.params.relationshipId, principal.userId]
        );
        const row = result.rows[0];
        if (!row?.authorized) return reply.code(403).send({ error: "forbidden" });
        return reply.code(200).send({
          request: row.request_id ? {
            requestId: row.request_id,
            requestedByUserId: row.requested_by_user_id,
            requestedAt: row.requested_at
          } : null
        });
      } catch (error) {
        request.log.error({ err: error }, "Pending settlement request lookup failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.post<{
    Params: { relationshipId: string; requestId: string };
    Body: { decision: "approved" | "rejected"; reason?: string };
  }>(
    "/v1/relationships/:relationshipId/settlement-reset-requests/:requestId/decision",
    {
      schema: {
        params: {
          type: "object",
          required: ["relationshipId", "requestId"],
          properties: {
            relationshipId: { type: "string", format: "uuid" },
            requestId: { type: "string", format: "uuid" }
          }
        },
        headers: {
          type: "object",
          required: ["idempotency-key"],
          properties: { "idempotency-key": { type: "string", format: "uuid" } }
        },
        body: {
          type: "object",
          additionalProperties: false,
          required: ["decision"],
          properties: {
            decision: { type: "string", enum: ["approved", "rejected"] },
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
        const result = await pool.query<{ decision: string }>(
          "SELECT ledger.decide_settlement_reset($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::text) AS decision",
          [
            idempotencyKey,
            request.params.relationshipId,
            request.params.requestId,
            principal.userId,
            request.body.decision,
            request.body.reason ?? null
          ]
        );
        const decision = result.rows[0]?.decision;
        if (decision !== request.body.decision) {
          request.log.error("Settlement decision function returned an unexpected decision");
          return reply.code(500).send({ error: "internal_error" });
        }
        return reply.code(200).send({
          status: "decided",
          requestId: request.params.requestId,
          decision,
          relationshipStatus: "active",
          cycleReset: decision === "approved"
        });
      } catch (error) {
        const code =
          typeof error === "object" && error !== null && "code" in error
            ? String((error as { code: unknown }).code)
            : undefined;
        if (code === "23514") {
          return reply.code(409).send({ error: "settlement_not_complete" });
        }
        const status = statusForDatabaseError(code);
        if (status === 500) {
          request.log.error({ err: error }, "Settlement reset decision failed");
          return reply.code(500).send({ error: "internal_error" });
        }
        const errorCode = status === 403 ? "forbidden" : status === 404 ? "not_found" :
          status === 409 ? "conflict" : "validation_error";
        return reply.code(status).send({ error: errorCode });
      }
    }
  );

  // Relationship members can inspect the current and archived account cycles.
  // Balances are reported per owner and currency using debit-minus-credit
  // minor units; the API deliberately does not label this as "owed"/"owing".
  app.get<{ Params: { relationshipId: string } }>(
    "/v1/relationships/:relationshipId/account-cycles",
    {
      schema: {
        params: {
          type: "object",
          required: ["relationshipId"],
          properties: { relationshipId: { type: "string", format: "uuid" } }
        }
      }
    },
    async (request, reply) => {
      const principal = request.principal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });

      try {
        const result = await pool.query<{
          authorized: boolean;
          current_cycle_id: string;
          cycles: Array<{
            cycleId: string;
            cycleNumber: number;
            title: string;
            status: "active" | "archived";
            startedAt: string;
            endedAt: string | null;
            balances: Array<{
              ownerUserId: string;
              currency: string;
              debitMinusCreditMinor: string;
            }>;
          }>;
        }>(
          "WITH access AS (" +
            " SELECT r.id, r.current_cycle_id," +
            " EXISTS (SELECT 1 FROM ledger.relationship_members rm" +
            " WHERE rm.relationship_id=r.id AND rm.user_id=$2::uuid AND rm.status='active') AS authorized" +
            " FROM ledger.relationships r WHERE r.id=$1::uuid" +
          "), cycle_rows AS (" +
            " SELECT c.id, c.relationship_id, c.cycle_number, c.title, c.status," +
            " c.started_at, c.ended_at," +
            " COALESCE((SELECT jsonb_agg(jsonb_build_object(" +
              " 'ownerUserId', p.owner_user_id," +
              " 'currency', p.currency," +
              " 'debitMinusCreditMinor', p.net_position_minor::text" +
            " ) ORDER BY p.owner_user_id, p.currency)" +
            " FROM ledger.member_currency_positions p" +
            " WHERE p.relationship_id=c.relationship_id AND p.cycle_id=c.id), '[]'::jsonb) AS balances" +
            " FROM ledger.account_cycles c WHERE c.relationship_id=$1::uuid" +
          ") SELECT a.authorized, a.current_cycle_id," +
            " COALESCE(jsonb_agg(jsonb_build_object(" +
              " 'cycleId', c.id, 'cycleNumber', c.cycle_number, 'title', c.title," +
              " 'status', c.status, 'startedAt', c.started_at, 'endedAt', c.ended_at," +
              " 'balances', c.balances" +
            " ) ORDER BY c.cycle_number DESC) FILTER (WHERE c.id IS NOT NULL), '[]'::jsonb) AS cycles" +
          " FROM access a LEFT JOIN cycle_rows c ON true" +
          " GROUP BY a.authorized, a.current_cycle_id",
          [request.params.relationshipId, principal.userId]
        );

        const row = result.rows[0];
        if (!row) return reply.code(404).send({ error: "not_found" });
        if (!row.authorized) return reply.code(403).send({ error: "forbidden" });

        return reply.code(200).send({
          currentCycleId: row.current_cycle_id,
          balanceSemantics: "debit_minus_credit_minor",
          cycles: row.cycles
        });
      } catch (error) {
        request.log.error({ err: error }, "Account cycle lookup failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  return app;
}
