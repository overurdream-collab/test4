import { createHash } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import type { Pool } from "pg";
import type { AuthenticatedPrincipal, PrincipalResolver } from "./approval-api.js";

type Dependencies = {
  pool: Pick<Pool, "query">;
  resolvePrincipal: PrincipalResolver;
};

type OperationParams = { relationshipId: string };
type OperationBody = {
  operationId: string;
  operationType: "credit_charge" | "payment" | "allocation" | "supply" | "return";
  schemaVersion: 1;
  baseVersion: number;
  payload: Record<string, unknown>;
  clientCreatedAt: string;
};

type EventsParams = { relationshipId: string };
type EventsQuery = { after?: string; limit?: string };

declare module "fastify" {
  interface FastifyRequest {
    syncPrincipal: AuthenticatedPrincipal | null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, item]) => JSON.stringify(key) + ":" + canonicalJson(item));
    return "{" + entries.join(",") + "}";
  }
  return JSON.stringify(value) ?? "null";
}

function databaseStatus(code: string | undefined): number {
  if (code === "42501") return 403;
  if (code === "23503") return 404;
  if (code === "23505" || code === "40001" || code === "55000") return 409;
  if (code === "23514" || code === "22023" || code === "22P02") return 422;
  return 500;
}

function dbCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String((error as { code: unknown }).code)
    : undefined;
}

export function buildSyncApi({ pool, resolvePrincipal }: Dependencies): FastifyInstance {
  const app = Fastify({ logger: false });
  app.decorateRequest("syncPrincipal", null);

  app.addHook("preHandler", async (request, reply) => {
    try {
      const principal = await resolvePrincipal(request);
      if (!principal || !UUID.test(principal.userId) || !UUID.test(principal.deviceId)) {
        return reply.code(401).send({ error: "unauthorized" });
      }
      request.syncPrincipal = principal;
    } catch {
      return reply.code(401).send({ error: "unauthorized" });
    }
  });

  app.post<{ Params: OperationParams; Body: OperationBody }>(
    "/v1/relationships/:relationshipId/operations",
    {
      schema: {
        params: {
          type: "object", required: ["relationshipId"],
          properties: { relationshipId: { type: "string", format: "uuid" } }
        },
        body: {
          type: "object", additionalProperties: false,
          required: ["operationId", "operationType", "schemaVersion", "baseVersion", "payload", "clientCreatedAt"],
          properties: {
            operationId: { type: "string", format: "uuid" },
            operationType: { type: "string", enum: ["credit_charge", "payment", "allocation", "supply", "return"] },
            schemaVersion: { type: "integer", const: 1 },
            baseVersion: { type: "integer", minimum: 0 },
            payload: { type: "object" },
            clientCreatedAt: { type: "string", format: "date-time" }
          }
        }
      }
    },
    async (request, reply) => {
      const principal = request.syncPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });

      const hashInput = {
        relationshipId: request.params.relationshipId,
        operationId: request.body.operationId,
        actorUserId: principal.userId,
        deviceId: principal.deviceId,
        operationType: request.body.operationType,
        schemaVersion: request.body.schemaVersion,
        baseVersion: request.body.baseVersion,
        payload: request.body.payload,
        clientCreatedAt: request.body.clientCreatedAt
      };
      const requestHash = createHash("sha256").update(canonicalJson(hashInput)).digest();

      try {
        const result = await pool.query<{
          outcome: string;
          canonical_operation_id: string;
          business_state: string;
          server_version: string | number;
          server_sequence: string | number;
          server_created_at: Date | string;
        }>(
          "SELECT * FROM ledger.accept_operation(" +
            "$1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::bytea,$7::jsonb,$8::bigint,$9::integer,$10::timestamptz" +
          ")",
          [
            request.body.operationId,
            request.params.relationshipId,
            principal.userId,
            principal.deviceId,
            request.body.operationType,
            requestHash,
            JSON.stringify(request.body.payload),
            request.body.baseVersion,
            request.body.schemaVersion,
            new Date(request.body.clientCreatedAt)
          ]
        );
        const row = result.rows[0];
        if (!row) return reply.code(500).send({ error: "internal_error" });

        return reply.code(200).send({
          outcome: row.outcome,
          operationId: row.canonical_operation_id,
          businessState: row.business_state,
          serverVersion: Number(row.server_version),
          serverSequence: Number(row.server_sequence),
          serverCreatedAt: row.server_created_at
        });
      } catch (error) {
        const status = databaseStatus(dbCode(error));
        if (status === 500) {
          request.log.error({ err: error }, "Operation acceptance failed");
          return reply.code(500).send({ error: "internal_error" });
        }
        const code = status === 403 ? "forbidden" :
          status === 404 ? "not_found" :
          status === 409 ? "conflict" : "validation_error";
        return reply.code(status).send({ error: code });
      }
    }
  );

  app.get<{ Params: EventsParams; Querystring: EventsQuery }>(
    "/v1/relationships/:relationshipId/events",
    {
      schema: {
        params: {
          type: "object", required: ["relationshipId"],
          properties: { relationshipId: { type: "string", format: "uuid" } }
        },
        querystring: {
          type: "object", additionalProperties: false,
          properties: {
            after: { type: "string", pattern: "^[0-9]+$" },
            limit: { type: "string", pattern: "^[0-9]+$" }
          }
        }
      }
    },
    async (request, reply) => {
      const principal = request.syncPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });

      const after = Number(request.query.after ?? "0");
      const limit = Number(request.query.limit ?? "100");
      if (!Number.isSafeInteger(after) || after < 0 ||
          !Number.isSafeInteger(limit) || limit < 1 || limit > 200) {
        return reply.code(400).send({ error: "invalid_sync_cursor" });
      }

      try {
        const result = await pool.query<{
          authorized: boolean;
          server_sequence: string | number | null;
          event_id: string | null;
          operation_id: string | null;
          event_type: string | null;
          event_payload: Record<string, unknown> | null;
          created_at: Date | string | null;
        }>(
          "WITH auth AS (" +
            " SELECT EXISTS (SELECT 1 FROM ledger.relationship_members" +
            " WHERE relationship_id=$1::uuid AND user_id=$2::uuid AND status='active') AS authorized" +
          ") " +
          "SELECT auth.authorized, e.server_sequence, e.event_id, e.operation_id," +
          " e.event_type, e.event_payload, e.created_at" +
          " FROM auth LEFT JOIN LATERAL (" +
            " SELECT server_sequence,event_id,operation_id,event_type,event_payload,created_at" +
            " FROM ledger.relationship_events WHERE relationship_id=$1::uuid AND server_sequence>$3::bigint" +
            " ORDER BY server_sequence LIMIT ($4::integer + 1)" +
          ") e ON auth.authorized ORDER BY e.server_sequence NULLS LAST",
          [request.params.relationshipId, principal.userId, after, limit]
        );

        if (result.rows[0]?.authorized !== true) {
          return reply.code(403).send({ error: "forbidden" });
        }

        const fetchedEvents = result.rows
          .filter(row => row.server_sequence !== null)
          .map(row => ({
            serverSequence: Number(row.server_sequence),
            eventId: row.event_id,
            operationId: row.operation_id,
            eventType: row.event_type,
            payload: row.event_payload,
            createdAt: row.created_at
          }));
        const hasMore = fetchedEvents.length > limit;
        const events = fetchedEvents.slice(0, limit);
        const nextCursor = events.length > 0
          ? events[events.length - 1]!.serverSequence
          : after;

        return reply.code(200).send({ events, nextCursor, hasMore });
      } catch (error) {
        request.log.error({ err: error }, "Relationship event sync failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  return app;
}
