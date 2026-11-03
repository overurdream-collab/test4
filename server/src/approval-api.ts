import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { createHash } from "node:crypto";
import type { Pool } from "pg";

export type AuthenticatedPrincipal = {
  userId: string;
  deviceId: string;
};

export type PrincipalResolver = (
  request: FastifyRequest
) => Promise<AuthenticatedPrincipal | null>;

export class DeviceRevokedError extends Error {
  constructor() {
    super("device_revoked");
    this.name = "DeviceRevokedError";
  }
}

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
    case "22023": return 422;
    case "23514": return 409;
    case "0A000": return 503;
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
          status === 409 ? "conflict" :
          status === 503 ? "sales_returns_disabled" : "validation_error";
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
              receivableMinor: string;
              payableMinor: string;
              partyBalanceMinor: string;
              unappliedPaymentAssetMinor: string;
              unappliedPaymentLiabilityMinor: string;
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
              " 'ownerUserId', b.owner_user_id," +
              " 'currency', b.currency," +
              " 'receivableMinor', b.receivable_minor::text," +
              " 'payableMinor', b.payable_minor::text," +
              " 'partyBalanceMinor', (b.receivable_minor - b.payable_minor)::text," +
              " 'unappliedPaymentAssetMinor', b.unapplied_payment_asset_minor::text," +
              " 'unappliedPaymentLiabilityMinor', b.unapplied_payment_liability_minor::text" +
            " ) ORDER BY b.owner_user_id, b.currency)" +
            " FROM (" +
              " SELECT a.owner_user_id, a.currency," +
              " COALESCE(sum(CASE WHEN a.account_type='party_receivable' THEN je.debit_minor-je.credit_minor ELSE 0 END),0) AS receivable_minor," +
              " COALESCE(sum(CASE WHEN a.account_type='party_payable' THEN je.credit_minor-je.debit_minor ELSE 0 END),0) AS payable_minor," +
              " COALESCE(sum(CASE WHEN a.account_type='unapplied_payment_asset' THEN je.debit_minor-je.credit_minor ELSE 0 END),0) AS unapplied_payment_asset_minor," +
              " COALESCE(sum(CASE WHEN a.account_type='unapplied_payment_liability' THEN je.credit_minor-je.debit_minor ELSE 0 END),0) AS unapplied_payment_liability_minor" +
              " FROM ledger.journal_transactions jt" +
              " JOIN ledger.journal_entries je ON je.journal_transaction_id=jt.id AND je.relationship_id=jt.relationship_id AND je.currency=jt.currency" +
              " JOIN ledger.accounts a ON a.id=je.account_id AND a.relationship_id=je.relationship_id AND a.currency=je.currency" +
              " WHERE jt.relationship_id=c.relationship_id AND jt.cycle_id=c.id" +
              " GROUP BY a.owner_user_id, a.currency" +
            " ) b), '[]'::jsonb) AS balances" +
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
          balanceSemantics: "separate_account_classes_minor_units",
          cycles: row.cycles
        });
      } catch (error) {
        request.log.error({ err: error }, "Account cycle lookup failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.post<{
    Params: { relationshipId: string };
    Body: { originalObligationId: string; currency: "YER" | "SAR" | "USD"; amountMinor: string; reason?: string; baseVersion?: number };
  }>(
    "/v1/relationships/:relationshipId/sales-returns",
    {
      schema: {
        params: { type: "object", required: ["relationshipId"], properties: { relationshipId: { type: "string", format: "uuid" } } },
        headers: { type: "object", required: ["idempotency-key"], properties: { "idempotency-key": { type: "string", format: "uuid" } } },
        body: {
          type: "object", additionalProperties: false,
          required: ["originalObligationId", "currency", "amountMinor"],
          properties: {
            originalObligationId: { type: "string", format: "uuid" },
            currency: { type: "string", enum: ["YER", "SAR", "USD"] },
            amountMinor: { type: "string", pattern: "^[1-9][0-9]{0,17}$" },
            reason: { type: "string", maxLength: 1000 },
            baseVersion: { type: "integer", minimum: 0 }
          }
        }
      }
    },
    async (request, reply) => {
      const key = request.headers["idempotency-key"];
      if (typeof key !== "string" || !UUID.test(key)) return reply.code(400).send({ error: "invalid_idempotency_key" });
      const principal = request.principal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      const payload = {
        originalObligationId: request.body.originalObligationId,
        currency: request.body.currency,
        amountMinor: request.body.amountMinor,
        ...(request.body.reason ? { reason: request.body.reason } : {})
      };
      const hash = createHash("sha256").update(JSON.stringify(payload)).digest();
      try {
        const prior = await pool.query<{
          relationship_id: string; actor_user_id: string; device_id: string; operation_type: string;
          request_hash: Buffer; business_state: string; server_version: string | number; server_sequence: string | number;
        }>(
          "SELECT relationship_id,actor_user_id,device_id,operation_type,request_hash,business_state,server_version,server_sequence FROM ledger.operations WHERE operation_id=$1::uuid",
          [key]
        );
        if (prior.rows[0]) {
          const existing = prior.rows[0];
          const same = existing.relationship_id === request.params.relationshipId &&
            existing.actor_user_id === principal.userId && existing.device_id === principal.deviceId &&
            existing.operation_type === "sales_return" && Buffer.from(existing.request_hash).equals(hash);
          if (!same) return reply.code(409).send({ error: "idempotency_conflict" });
          return reply.code(200).send({
            status: existing.business_state, operationId: key,
            serverVersion: Number(existing.server_version), serverSequence: Number(existing.server_sequence)
          });
        }
        const check = await pool.query<{
          authorized: boolean; obligation_id: string | null; amount_minor: string | null;
          returned_minor: string | null; cycle_status: string | null; source_cycle_id: string | null;
          current_cycle_id: string | null;
        }>(
          "SELECT EXISTS(SELECT 1 FROM ledger.relationship_members rm WHERE rm.relationship_id=$1::uuid AND rm.user_id=$2::uuid AND rm.status='active') AS authorized," +
          " o.id AS obligation_id,o.amount_minor::text AS amount_minor," +
          " COALESCE((SELECT sum(sr.amount_minor) FROM ledger.sales_returns sr WHERE sr.relationship_id=o.relationship_id AND sr.original_obligation_id=o.id),0)::text AS returned_minor," +
          " c.status AS cycle_status,source_op.cycle_id AS source_cycle_id,r.current_cycle_id" +
          " FROM ledger.relationships r JOIN ledger.obligations o ON o.relationship_id=r.id AND o.id=$3::uuid AND o.currency=$4::char(3)" +
          " JOIN ledger.operations source_op ON source_op.relationship_id=o.relationship_id AND source_op.operation_id=o.source_operation_id" +
          " JOIN ledger.account_cycles c ON c.id=source_op.cycle_id AND c.relationship_id=o.relationship_id" +
          " WHERE r.id=$1::uuid",
          [request.params.relationshipId, principal.userId, request.body.originalObligationId, request.body.currency]
        );
        const row = check.rows[0];
        if (!row) return reply.code(404).send({ error: "obligation_not_found" });
        if (!row.authorized) return reply.code(403).send({ error: "forbidden" });
        if (row.cycle_status !== "active" || row.source_cycle_id !== row.current_cycle_id) {
          return reply.code(409).send({ error: "archived_cycle" });
        }
        if (BigInt(request.body.amountMinor) > BigInt(row.amount_minor!) - BigInt(row.returned_minor!)) {
          return reply.code(409).send({ error: "return_exceeds_original_obligation" });
        }
        const accepted = await pool.query<{
          outcome: string; canonical_operation_id: string; business_state: string;
          server_version: string | number; server_sequence: string | number;
        }>(
          "SELECT * FROM ledger.accept_operation($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::bytea,$7::jsonb,$8::bigint,$9::integer,$10::timestamptz)",
          [key, request.params.relationshipId, principal.userId, principal.deviceId, "sales_return", hash, JSON.stringify(payload), request.body.baseVersion ?? 0, 1, new Date()]
        );
        const op = accepted.rows[0];
        if (!op || op.canonical_operation_id !== key) {
          request.log.error("Sales return inbox returned an invalid canonical operation");
          return reply.code(500).send({ error: "internal_error" });
        }
        return reply.code(op.outcome === "already_processed" ? 200 : 201).send({
          status: op.business_state, operationId: op.canonical_operation_id,
          serverVersion: Number(op.server_version), serverSequence: Number(op.server_sequence)
        });
      } catch (error) {
        const code = typeof error === "object" && error !== null && "code" in error
          ? String((error as { code: unknown }).code) : undefined;
        if (code === "23514") return reply.code(409).send({ error: "return_conflict" });
        if (code === "0A000") return reply.code(503).send({ error: "sales_returns_disabled" });
        const status = statusForDatabaseError(code);
        if (status === 500) {
          request.log.error({ err: error }, "Sales return request failed");
          return reply.code(500).send({ error: "internal_error" });
        }
        return reply.code(status).send({ error: status === 403 ? "forbidden" : status === 404 ? "not_found" : status === 409 ? "conflict" : "validation_error" });
      }
    }
  );

  app.get<{ Params: { relationshipId: string; cycleId: string } }>(
    "/v1/relationships/:relationshipId/account-cycles/:cycleId/sales-returns",
    {
      schema: {
        params: { type: "object", required: ["relationshipId", "cycleId"], properties: {
          relationshipId: { type: "string", format: "uuid" }, cycleId: { type: "string", format: "uuid" }
        } }
      }
    },
    async (request, reply) => {
      const principal = request.principal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      try {
        const result = await pool.query<{ authorized: boolean; cycle_found: boolean; sales_returns: unknown[] }>(
          "WITH access AS (SELECT EXISTS(SELECT 1 FROM ledger.relationship_members WHERE relationship_id=$1::uuid AND user_id=$3::uuid AND status='active') AS authorized," +
          " EXISTS(SELECT 1 FROM ledger.account_cycles WHERE relationship_id=$1::uuid AND id=$2::uuid) AS cycle_found)" +
          " SELECT access.authorized,access.cycle_found,COALESCE((SELECT jsonb_agg(jsonb_build_object(" +
          " 'returnId',sr.id,'relationshipId',sr.relationship_id,'cycleId',op.cycle_id,'operationId',sr.source_operation_id," +
          " 'originalObligationId',sr.original_obligation_id,'currency',sr.currency,'amountMinor',sr.amount_minor::text," +
          " 'reason',sr.reason,'createdAt',sr.created_at,'operationState',op.business_state,'createdByUserId',op.actor_user_id," +
          " 'originalAmountMinor',obl.amount_minor::text,'creditorUserId',obl.creditor_user_id,'debtorUserId',obl.debtor_user_id," +
          " 'approval',jsonb_build_object('decision',ap.decision,'decidedByUserId',ap.actor_user_id,'decidedAt',ap.decided_at,'reason',ap.reason)" +
          " ) ORDER BY sr.created_at,sr.id) FROM ledger.sales_returns sr" +
          " JOIN ledger.operations op ON op.relationship_id=sr.relationship_id AND op.operation_id=sr.source_operation_id" +
          " JOIN ledger.obligations obl ON obl.id=sr.original_obligation_id AND obl.relationship_id=sr.relationship_id" +
          " LEFT JOIN LATERAL (SELECT a.decision,a.actor_user_id,a.decided_at,a.reason FROM ledger.approvals a WHERE a.operation_id=op.operation_id ORDER BY a.decided_at DESC LIMIT 1) ap ON true" +
          " WHERE sr.relationship_id=$1::uuid AND op.cycle_id=$2::uuid),'[]'::jsonb) AS sales_returns FROM access",
          [request.params.relationshipId, request.params.cycleId, principal.userId]
        );
        const row = result.rows[0];
        if (!row?.authorized) return reply.code(403).send({ error: "forbidden" });
        if (!row.cycle_found) return reply.code(404).send({ error: "cycle_not_found" });
        return reply.code(200).send({ cycleId: request.params.cycleId, salesReturns: row.sales_returns });
      } catch (error) {
        request.log.error({ err: error }, "Sales return statement lookup failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.patch<{ Params: { relationshipId: string; returnId: string } }>(
    "/v1/relationships/:relationshipId/sales-returns/:returnId",
    {
      schema: { params: { type: "object", required: ["relationshipId", "returnId"], properties: {
        relationshipId: { type: "string", format: "uuid" }, returnId: { type: "string", format: "uuid" }
      } }, body: { type: "object" } }
    },
    async (request, reply) => {
      const principal = request.principal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      try {
        const result = await pool.query<{ authorized: boolean; exists: boolean }>(
          "SELECT EXISTS(SELECT 1 FROM ledger.relationship_members WHERE relationship_id=$1::uuid AND user_id=$2::uuid AND status='active') AS authorized," +
          " EXISTS(SELECT 1 FROM ledger.sales_returns WHERE relationship_id=$1::uuid AND id=$3::uuid) AS exists",
          [request.params.relationshipId, principal.userId, request.params.returnId]
        );
        const row = result.rows[0];
        if (!row?.authorized) return reply.code(403).send({ error: "forbidden" });
        if (!row.exists) return reply.code(404).send({ error: "return_not_found" });
        return reply.code(409).send({ error: "published_return_is_immutable" });
      } catch (error) {
        request.log.error({ err: error }, "Sales return mutation guard failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  return app;
}
