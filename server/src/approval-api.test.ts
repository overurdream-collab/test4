import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { buildApprovalApi } from "./approval-api.js";

const relationshipId = "11000000-0000-0000-0000-000000000001";
const operationId = "31000000-0000-0000-0000-000000000005";
const decisionId = "61000000-0000-0000-0000-000000000001";
const userId = "21000000-0000-0000-0000-000000000002";
const deviceId = "71000000-0000-0000-0000-000000000001";
const url = "/v1/relationships/" + relationshipId + "/operations/" + operationId + "/decision";

function makePool(query: (...args: any[]) => Promise<any>): Pool {
  return { query } as unknown as Pool;
}

test("rejects unauthenticated requests before calling PostgreSQL", async () => {
  let called = false;
  const app = buildApprovalApi({
    pool: makePool(async () => {
      called = true;
      return { rows: [{ server_version: 2 }] };
    }),
    resolvePrincipal: async () => null
  });
  const response = await app.inject({
    method: "POST", url, headers: { "idempotency-key": decisionId },
    payload: { decision: "approved", expectedVersion: 1 }
  });
  assert.equal(response.statusCode, 401);
  assert.equal(called, false);
  await app.close();
});

test("ignores client-supplied actor fields and trusts only the authenticated principal", async () => {
  let boundValues: unknown[] = [];
  const app = buildApprovalApi({
    pool: makePool(async (_sql, values) => {
      boundValues = values;
      return { rows: [{ server_version: 2 }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const forged = await app.inject({
    method: "POST", url, headers: { "idempotency-key": decisionId },
    payload: { decision: "approved", expectedVersion: 1, actorUserId: "forged" }
  });
  assert.equal(forged.statusCode, 200);
  assert.equal(JSON.parse(forged.body).serverVersion, 2);
  assert.equal(boundValues[0], decisionId);
  assert.equal(boundValues[1], relationshipId);
  assert.equal(boundValues[2], operationId);
  assert.equal(boundValues[3], userId);
  assert.notEqual(boundValues[3], "forged");
  assert.equal(boundValues[4], 1);
  await app.close();
});

test("maps missing permission to 403 without exposing database details", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => {
      throw Object.assign(new Error("private database detail"), { code: "42501" });
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url, headers: { "idempotency-key": decisionId },
    payload: { decision: "approved", expectedVersion: 1 }
  });
  assert.equal(response.statusCode, 403);
  assert.deepEqual(JSON.parse(response.body), { error: "forbidden" });
  assert.equal(response.body.includes("private database detail"), false);
  await app.close();
});

test("maps stale-version and already-decided conflicts to 409", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => {
      throw Object.assign(new Error("stale"), { code: "40001" });
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url, headers: { "idempotency-key": decisionId },
    payload: { decision: "rejected", expectedVersion: 1 }
  });
  assert.equal(response.statusCode, 409);
  await app.close();
});


const settlementUrl = "/v1/relationships/" + relationshipId + "/settlement-reset-requests";

test("creates a settlement reset request using only the authenticated user", async () => {
  let values: unknown[] = [];
  const app = buildApprovalApi({
    pool: makePool(async (_sql, bound) => {
      values = bound;
      return { rows: [{ request_id: decisionId }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url: settlementUrl,
    headers: { "idempotency-key": decisionId },
    payload: {}
  });
  assert.equal(response.statusCode, 201);
  assert.deepEqual(JSON.parse(response.body), { status: "requested", requestId: decisionId });
  assert.deepEqual(values, [decisionId, relationshipId, userId]);
  await app.close();
});

test("rejects settlement reset requests when the ledger is not fully settled", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => {
      throw Object.assign(new Error("unpaid obligation"), { code: "23514" });
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url: settlementUrl,
    headers: { "idempotency-key": decisionId },
    payload: {}
  });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: "settlement_not_complete" });
  await app.close();
});

test("rejects unauthenticated settlement reset requests before calling PostgreSQL", async () => {
  let called = false;
  const app = buildApprovalApi({
    pool: makePool(async () => {
      called = true;
      return { rows: [{ request_id: decisionId }] };
    }),
    resolvePrincipal: async () => null
  });
  const response = await app.inject({
    method: "POST", url: settlementUrl,
    headers: { "idempotency-key": decisionId },
    payload: {}
  });
  assert.equal(response.statusCode, 401);
  assert.equal(called, false);
  await app.close();
});


const settlementDecisionUrl = settlementUrl + "/" + decisionId + "/decision";
const pendingSettlementUrl = settlementUrl + "/pending";

test("returns the pending settlement request to an authorized relationship member", async () => {
  const requestedAt = "2026-11-02T10:00:00.000Z";
  const app = buildApprovalApi({
    pool: makePool(async () => ({
      rows: [{
        authorized: true,
        request_id: decisionId,
        requested_by_user_id: "21000000-0000-0000-0000-000000000001",
        requested_at: requestedAt
      }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: pendingSettlementUrl });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    request: {
      requestId: decisionId,
      requestedByUserId: "21000000-0000-0000-0000-000000000001",
      requestedAt
    }
  });
  await app.close();
});

test("decides a settlement reset using the authenticated counterparty and idempotency key", async () => {
  let values: unknown[] = [];
  const app = buildApprovalApi({
    pool: makePool(async (_sql, bound) => {
      values = bound;
      return { rows: [{ decision: "approved" }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST",
    url: settlementDecisionUrl,
    headers: { "idempotency-key": "96000000-0000-0000-0000-000000000002" },
    payload: { decision: "approved", reason: "Settled by both parties" }
  });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    status: "decided",
    requestId: decisionId,
    decision: "approved",
    relationshipStatus: "closed"
  });
  assert.deepEqual(values, [
    "96000000-0000-0000-0000-000000000002",
    relationshipId,
    decisionId,
    userId,
    "approved",
    "Settled by both parties"
  ]);
  await app.close();
});

test("maps self-approval and missing counterparty permission to 403", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => {
      throw Object.assign(new Error("requester cannot decide"), { code: "42501" });
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url: settlementDecisionUrl,
    headers: { "idempotency-key": "96000000-0000-0000-0000-000000000003" },
    payload: { decision: "approved" }
  });
  assert.equal(response.statusCode, 403);
  assert.deepEqual(JSON.parse(response.body), { error: "forbidden" });
  await app.close();
});

test("returns a conflict when the ledger is no longer settled at final approval", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => {
      throw Object.assign(new Error("outstanding obligation"), { code: "23514" });
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url: settlementDecisionUrl,
    headers: { "idempotency-key": "96000000-0000-0000-0000-000000000004" },
    payload: { decision: "approved" }
  });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: "settlement_not_complete" });
  await app.close();
});
