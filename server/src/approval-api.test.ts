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
    relationshipStatus: "active",
    cycleReset: true
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

test("rejected white-page requests keep the relationship active without resetting the cycle", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [{ decision: "rejected" }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST",
    url: settlementDecisionUrl,
    headers: { "idempotency-key": "96000000-0000-0000-0000-000000000005" },
    payload: { decision: "rejected", reason: "Keep current page" }
  });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    status: "decided",
    requestId: decisionId,
    decision: "rejected",
    relationshipStatus: "active",
    cycleReset: false
  });
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


const accountCyclesUrl = "/v1/relationships/" + relationshipId + "/account-cycles";

test("returns current and archived cycles with explicit debit-minus-credit balances", async () => {
  const app = buildApprovalApi({
    pool: makePool(async (_sql, values) => {
      assert.deepEqual(values, [relationshipId, userId]);
      return {
        rows: [{
          authorized: true,
          current_cycle_id: "18000000-0000-0000-0000-000000000002",
          cycles: [
            {
              cycleId: "18000000-0000-0000-0000-000000000002",
              cycleNumber: 2,
              title: "صفحة بيضاء 2",
              status: "active",
              startedAt: "2026-11-02T10:00:00.000Z",
              endedAt: null,
              balances: []
            },
            {
              cycleId: "18000000-0000-0000-0000-000000000001",
              cycleNumber: 1,
              title: "الدورة الأولى",
              status: "archived",
              startedAt: "2026-10-01T10:00:00.000Z",
              endedAt: "2026-11-02T10:00:00.000Z",
              balances: [{
                ownerUserId: userId,
                currency: "YER",
                receivableMinor: "12500",
                payableMinor: "0",
                unappliedPaymentAssetMinor: "0",
                unappliedPaymentLiabilityMinor: "0"
              }]
            }
          ]
        }]
      };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: accountCyclesUrl });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    currentCycleId: "18000000-0000-0000-0000-000000000002",
    balanceSemantics: "separate_account_classes_minor_units",
    cycles: [
      {
        cycleId: "18000000-0000-0000-0000-000000000002",
        cycleNumber: 2,
        title: "صفحة بيضاء 2",
        status: "active",
        startedAt: "2026-11-02T10:00:00.000Z",
        endedAt: null,
        balances: []
      },
      {
        cycleId: "18000000-0000-0000-0000-000000000001",
        cycleNumber: 1,
        title: "الدورة الأولى",
        status: "archived",
        startedAt: "2026-10-01T10:00:00.000Z",
        endedAt: "2026-11-02T10:00:00.000Z",
        balances: [{
          ownerUserId: userId,
          currency: "YER",
          receivableMinor: "12500",
                payableMinor: "0",
                unappliedPaymentAssetMinor: "0",
                unappliedPaymentLiabilityMinor: "0"
        }]
      }
    ]
  });
  await app.close();
});

test("account-cycle balance contract keeps receivables, payables and unapplied payments separate", async () => {
  const app = buildApprovalApi({
    pool: makePool(async (sql) => {
      assert.ok(sql.includes("a.account_type='party_receivable'"));
      assert.ok(sql.includes("a.account_type='party_payable'"));
      assert.ok(sql.includes("a.account_type='unapplied_payment_asset'"));
      assert.ok(sql.includes("a.account_type='unapplied_payment_liability'"));
      assert.ok(sql.includes("jt.cycle_id=c.id"));
      return { rows: [{
        authorized: true,
        current_cycle_id: "18000000-0000-0000-0000-000000000002",
        cycles: [{
          cycleId: "18000000-0000-0000-0000-000000000002",
          cycleNumber: 2,
          title: "صفحة بيضاء 2",
          status: "active",
          startedAt: "2026-11-02T10:00:00.000Z",
          endedAt: null,
          balances: [
            { ownerUserId: userId, currency: "YER", receivableMinor: "12000", payableMinor: "0", unappliedPaymentAssetMinor: "3000", unappliedPaymentLiabilityMinor: "0" },
            { ownerUserId: "21000000-0000-0000-0000-000000000003", currency: "YER", receivableMinor: "0", payableMinor: "12000", unappliedPaymentAssetMinor: "0", unappliedPaymentLiabilityMinor: "3000" }
          ]
        }]
      }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: accountCyclesUrl });
  assert.equal(response.statusCode, 200);
  const body = JSON.parse(response.body);
  assert.equal(body.balanceSemantics, "separate_account_classes_minor_units");
  assert.deepEqual(body.cycles[0].balances, [
    { ownerUserId: userId, currency: "YER", receivableMinor: "12000", payableMinor: "0", unappliedPaymentAssetMinor: "3000", unappliedPaymentLiabilityMinor: "0" },
    { ownerUserId: "21000000-0000-0000-0000-000000000003", currency: "YER", receivableMinor: "0", payableMinor: "12000", unappliedPaymentAssetMinor: "0", unappliedPaymentLiabilityMinor: "3000" }
  ]);
  await app.close();
});

test("denies account-cycle history to a user outside the relationship", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({
      rows: [{ authorized: false, current_cycle_id: "18000000-0000-0000-0000-000000000002", cycles: [] }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: accountCyclesUrl });
  assert.equal(response.statusCode, 403);
  assert.deepEqual(JSON.parse(response.body), { error: "forbidden" });
  await app.close();
});

test("rejects unauthenticated account-cycle history before querying PostgreSQL", async () => {
  let called = false;
  const app = buildApprovalApi({
    pool: makePool(async () => {
      called = true;
      return { rows: [] };
    }),
    resolvePrincipal: async () => null
  });
  const response = await app.inject({ method: "GET", url: accountCyclesUrl });
  assert.equal(response.statusCode, 401);
  assert.equal(called, false);
  await app.close();
});

test("returns 404 when the relationship does not exist", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: accountCyclesUrl });
  assert.equal(response.statusCode, 404);
  await app.close();
});
