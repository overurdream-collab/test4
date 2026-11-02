import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
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
                partyBalanceMinor: "12500",
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
          partyBalanceMinor: "12500",
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
            { ownerUserId: userId, currency: "YER", receivableMinor: "12000", payableMinor: "0", partyBalanceMinor: "12000", unappliedPaymentAssetMinor: "3000", unappliedPaymentLiabilityMinor: "0" },
            { ownerUserId: "21000000-0000-0000-0000-000000000003", currency: "YER", receivableMinor: "0", payableMinor: "12000", partyBalanceMinor: "-12000", unappliedPaymentAssetMinor: "0", unappliedPaymentLiabilityMinor: "3000" }
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
    { ownerUserId: userId, currency: "YER", receivableMinor: "12000", payableMinor: "0", partyBalanceMinor: "12000", unappliedPaymentAssetMinor: "3000", unappliedPaymentLiabilityMinor: "0" },
    { ownerUserId: "21000000-0000-0000-0000-000000000003", currency: "YER", receivableMinor: "0", payableMinor: "12000", partyBalanceMinor: "-12000", unappliedPaymentAssetMinor: "0", unappliedPaymentLiabilityMinor: "3000" }
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


test("account cycle API preserves signed negative receivable and payable values", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [{
      authorized: true,
      current_cycle_id: "18000000-0000-0000-0000-000000000002",
      cycles: [{
        cycleId: "18000000-0000-0000-0000-000000000002",
        cycleNumber: 2, title: "صفحة بيضاء 2", status: "active",
        startedAt: "2026-11-02T10:00:00.000Z", endedAt: null,
        balances: [
          { ownerUserId: userId, currency: "YER", receivableMinor: "-5000", payableMinor: "0", partyBalanceMinor: "-5000", unappliedPaymentAssetMinor: "0", unappliedPaymentLiabilityMinor: "0" },
          { ownerUserId: "21000000-0000-0000-0000-000000000003", currency: "YER", receivableMinor: "0", payableMinor: "-5000", partyBalanceMinor: "5000", unappliedPaymentAssetMinor: "0", unappliedPaymentLiabilityMinor: "0" }
        ]
      }]
    }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: accountCyclesUrl });
  assert.equal(response.statusCode, 200);
  const balances = JSON.parse(response.body).cycles[0].balances;
  assert.equal(balances[0].receivableMinor, "-5000");
  assert.equal(balances[0].partyBalanceMinor, "-5000");
  assert.equal(balances[1].payableMinor, "-5000");
  assert.equal(balances[1].partyBalanceMinor, "5000");
  await app.close();
});


const returnKey = "81000000-0000-0000-0000-000000000001";
const obligationId = "82000000-0000-0000-0000-000000000001";
const cycleId = "83000000-0000-0000-0000-000000000001";
const returnUrl = "/v1/relationships/" + relationshipId + "/sales-returns";
const returnPayload = { originalObligationId: obligationId, currency: "YER", amountMinor: "2500", reason: "Returned goods" };

test("creates an idempotent sales-return operation using principal identity only", async () => {
  const calls: Array<{ sql: string; values: unknown[] }> = [];
  const app = buildApprovalApi({
    pool: makePool(async (sql, values) => {
      calls.push({ sql: String(sql), values: values ?? [] });
      if (calls.length === 1) return { rows: [] };
      if (calls.length === 2) return { rows: [{
        authorized: true, obligation_id: obligationId, amount_minor: "10000",
        returned_minor: "1000", cycle_status: "active", source_cycle_id: cycleId, current_cycle_id: cycleId
      }] };
      return { rows: [{
        outcome: "accepted", canonical_operation_id: returnKey, business_state: "awaiting_counterparty",
        server_version: 1, server_sequence: 44
      }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url: returnUrl, headers: { "idempotency-key": returnKey },
    payload: returnPayload
  });
  assert.equal(response.statusCode, 201);
  assert.deepEqual(JSON.parse(response.body), {
    status: "awaiting_counterparty", operationId: returnKey, serverVersion: 1, serverSequence: 44
  });
  assert.deepEqual(calls[2]!.values.slice(0, 5), [returnKey, relationshipId, userId, deviceId, "sales_return"]);
  assert.equal(calls[2]!.values[6], JSON.stringify(returnPayload));
  await app.close();
});

test("replays an already approved sales return before checking the remaining obligation", async () => {
  let acceptCalls = 0;
  const requestHash = createHash("sha256").update(JSON.stringify(returnPayload)).digest();
  const app = buildApprovalApi({
    pool: makePool(async (sql) => {
      if (String(sql).includes("FROM ledger.operations WHERE operation_id")) {
        return { rows: [{
          relationship_id: relationshipId, actor_user_id: userId, device_id: deviceId,
          operation_type: "sales_return", request_hash: requestHash, business_state: "approved",
          server_version: 2, server_sequence: 44
        }] };
      }
      acceptCalls++;
      return { rows: [] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "POST", url: returnUrl, headers: { "idempotency-key": returnKey }, payload: returnPayload });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    status: "approved", operationId: returnKey, serverVersion: 2, serverSequence: 44
  });
  assert.equal(acceptCalls, 0);
  await app.close();
});

test("rejects a sales return that exceeds the original obligation with HTTP 409", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [{
      authorized: true, obligation_id: obligationId, amount_minor: "10000", returned_minor: "9000",
      cycle_status: "active", source_cycle_id: cycleId, current_cycle_id: cycleId
    }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "POST", url: returnUrl, headers: { "idempotency-key": returnKey }, payload: returnPayload });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: "return_exceeds_original_obligation" });
  await app.close();
});

test("rejects a sales return against an archived source cycle with HTTP 409", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [{
      authorized: true, obligation_id: obligationId, amount_minor: "10000", returned_minor: "0",
      cycle_status: "archived", source_cycle_id: cycleId, current_cycle_id: "83000000-0000-0000-0000-000000000002"
    }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "POST", url: returnUrl, headers: { "idempotency-key": returnKey }, payload: returnPayload });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: "archived_cycle" });
  await app.close();
});

test("sales-return request requires a valid idempotency key", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => { throw new Error("must not query"); }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "POST", url: returnUrl, payload: returnPayload });
  assert.equal(response.statusCode, 400);
  await app.close();
});

test("returns detailed sales-return rows scoped to relationship and account cycle", async () => {
  const app = buildApprovalApi({
    pool: makePool(async (_sql, values) => {
      assert.deepEqual(values, [relationshipId, cycleId, userId]);
      return { rows: [{
        authorized: true, cycle_found: true,
        sales_returns: [{
          returnId: returnKey, relationshipId, cycleId, operationId: returnKey,
          originalObligationId: obligationId, currency: "YER", amountMinor: "2500",
          reason: "Returned goods", operationState: "approved", createdByUserId: userId,
          originalAmountMinor: "10000", creditorUserId: userId,
          debtorUserId: "21000000-0000-0000-0000-000000000003",
          approval: { decision: "approved", decidedByUserId: "21000000-0000-0000-0000-000000000003" }
        }]
      }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: "/v1/relationships/" + relationshipId + "/account-cycles/" + cycleId + "/sales-returns" });
  assert.equal(response.statusCode, 200);
  const body = JSON.parse(response.body);
  assert.equal(body.salesReturns[0].amountMinor, "2500");
  assert.equal(body.salesReturns[0].approval.decision, "approved");
  await app.close();
});

test("denies detailed sales-return statement access to non-members", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [{ authorized: false, cycle_found: true, sales_returns: [] }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: "/v1/relationships/" + relationshipId + "/account-cycles/" + cycleId + "/sales-returns" });
  assert.equal(response.statusCode, 403);
  await app.close();
});

test("rejects edits to a published sales return as immutable", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [{ authorized: true, exists: true }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "PATCH", url: returnUrl + "/" + returnKey, payload: { amountMinor: "1" }
  });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: "published_return_is_immutable" });
  await app.close();
});

test("counterparty approval reuses the operation decision API and maps self-approval to 403", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => { throw Object.assign(new Error("creator cannot approve"), { code: "42501" }); }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST",
    url: "/v1/relationships/" + relationshipId + "/operations/" + returnKey + "/decision",
    headers: { "idempotency-key": decisionId },
    payload: { decision: "approved", expectedVersion: 1 }
  });
  assert.equal(response.statusCode, 403);
  await app.close();
});

test("counterparty approval maps a return-overrun race to HTTP 409", async () => {
  const app = buildApprovalApi({
    pool: makePool(async () => { throw Object.assign(new Error("cumulative return cap"), { code: "23514" }); }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST",
    url: "/v1/relationships/" + relationshipId + "/operations/" + returnKey + "/decision",
    headers: { "idempotency-key": decisionId },
    payload: { decision: "approved", expectedVersion: 1 }
  });
  assert.equal(response.statusCode, 409);
  await app.close();
});

test("ignores client-supplied actor identity and binds only the authenticated principal", async () => {
  let acceptedValues: unknown[] = [];
  let calls = 0;
  const app = buildApprovalApi({
    pool: makePool(async (_sql, values) => {
      calls++;
      if (calls === 1) return { rows: [{
        authorized: true, obligation_id: obligationId, amount_minor: "10000", returned_minor: "0",
        cycle_status: "active", source_cycle_id: cycleId, current_cycle_id: cycleId
      }] };
      acceptedValues = values;
      return { rows: [{
        outcome: "accepted", canonical_operation_id: returnKey, business_state: "awaiting_counterparty",
        server_version: 1, server_sequence: 45
      }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url: returnUrl, headers: { "idempotency-key": returnKey },
    payload: { ...returnPayload, actorUserId: "forged-user" }
  });
  assert.equal(response.statusCode, 201);
  assert.equal(acceptedValues[2], userId);
  assert.notEqual(acceptedValues[2], "forged-user");
  assert.equal(acceptedValues[3], deviceId);
  await app.close();
});

test("rejects reuse of a sales-return idempotency key with different payload", async () => {
  const requestHash = createHash("sha256").update(JSON.stringify(returnPayload)).digest();
  const app = buildApprovalApi({
    pool: makePool(async () => ({ rows: [{
      relationship_id: relationshipId, actor_user_id: userId, device_id: deviceId,
      operation_type: "sales_return", request_hash: requestHash, business_state: "approved",
      server_version: 2, server_sequence: 44
    }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "POST", url: returnUrl, headers: { "idempotency-key": returnKey },
    payload: { ...returnPayload, amountMinor: "2600" }
  });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: "idempotency_conflict" });
  await app.close();
});
