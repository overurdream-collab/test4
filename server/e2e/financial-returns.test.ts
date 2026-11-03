import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import {
  assertAmount,
  balanceFor,
  createHarness,
  json,
  phone
} from "./harness.js";

test("HTTP sales return credit is archived by bilateral white-page reset", async (t) => {
  const harness = createHarness(t);
  const { pool, identity, approval, login, invite, submit, decide, cycles } = harness;

  const seller = await login(phone());
  const buyer = await login(phone());
  const relation = await invite(seller, buyer);
  const opening = await cycles(seller.token, relation);
  const cycleId = opening.currentCycleId;

  const chargeId = randomUUID();
  const charge = await submit(seller.token, relation, {
    operationId: chargeId,
    operationType: "credit_charge",
    schemaVersion: 1,
    baseVersion: 0,
    payload: {
      creditorUserId: seller.userId,
      debtorUserId: buyer.userId,
      currency: "YER",
      amountMinor: 5000
    },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(charge.statusCode, 200, charge.body);
  const chargeDecision = await decide(buyer.token, relation, chargeId, "approved", "charge accepted");
  assert.equal(chargeDecision.statusCode, 200, chargeDecision.body);

  const paymentId = randomUUID();
  const payment = await submit(buyer.token, relation, {
    operationId: paymentId,
    operationType: "payment",
    schemaVersion: 1,
    baseVersion: 0,
    payload: {
      payerUserId: buyer.userId,
      payeeUserId: seller.userId,
      currency: "YER",
      amountMinor: 5000
    },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(payment.statusCode, 200, payment.body);
  const paymentDecision = await decide(seller.token, relation, paymentId, "approved", "payment accepted");
  assert.equal(paymentDecision.statusCode, 200, paymentDecision.body);

  const obligationId = await pool.query<{ id: string }>(
    "SELECT id FROM ledger.obligations WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
    [relation, chargeId]
  );
  const paymentRecordId = await pool.query<{ id: string }>(
    "SELECT id FROM ledger.payments WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
    [relation, paymentId]
  );
  assert.ok(obligationId.rows[0]?.id);
  assert.ok(paymentRecordId.rows[0]?.id);

  const allocationId = randomUUID();
  const allocation = await submit(buyer.token, relation, {
    operationId: allocationId,
    operationType: "allocation",
    schemaVersion: 1,
    baseVersion: 0,
    payload: {
      paymentId: paymentRecordId.rows[0]!.id,
      obligationId: obligationId.rows[0]!.id,
      amountMinor: 5000
    },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(allocation.statusCode, 200, allocation.body);
  const allocationDecision = await decide(seller.token, relation, allocationId, "approved", "allocation accepted");
  assert.equal(allocationDecision.statusCode, 200, allocationDecision.body);

  const returnId = randomUUID();
  const returnPayload = {
    originalObligationId: obligationId.rows[0]!.id,
    currency: "YER",
    amountMinor: "1000",
    reason: "Returned goods after settlement"
  };
  const salesReturn = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/sales-returns",
    headers: {
      authorization: "Bearer " + buyer.token,
      "idempotency-key": returnId
    },
    payload: returnPayload
  });
  assert.equal(salesReturn.statusCode, 201, salesReturn.body);
  assert.equal(json<{ operationId: string }>(salesReturn.body).operationId, returnId);

  const returnDecision = await decide(seller.token, relation, returnId, "approved", "return accepted");
  assert.equal(returnDecision.statusCode, 200, returnDecision.body);

  const returnReplay = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/sales-returns",
    headers: {
      authorization: "Bearer " + buyer.token,
      "idempotency-key": returnId
    },
    payload: returnPayload
  });
  assert.equal(returnReplay.statusCode, 200, returnReplay.body);
  assert.equal(json<{ status: string }>(returnReplay.body).status, "approved");

  const returns = await pool.query<{ id: string; count: string }>(
    "SELECT id, count(*) OVER()::text AS count FROM ledger.sales_returns WHERE relationship_id=$1::uuid AND original_obligation_id=$2::uuid",
    [relation, obligationId.rows[0]!.id]
  );
  assert.equal(returns.rows.length, 1);
  assert.equal(returns.rows[0]?.count, "1");
  const storedReturnId = returns.rows[0]!.id;

  const afterReturn = await cycles(seller.token, relation);
  const sellerAfterReturn = balanceFor(afterReturn, cycleId, seller.userId);
  const buyerAfterReturn = balanceFor(afterReturn, cycleId, buyer.userId);
  assertAmount(sellerAfterReturn.receivableMinor, -1000n, "seller receivable becomes credit");
  assertAmount(buyerAfterReturn.payableMinor, -1000n, "buyer payable becomes credit");

  const overReturn = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/sales-returns",
    headers: {
      authorization: "Bearer " + buyer.token,
      "idempotency-key": randomUUID()
    },
    payload: { ...returnPayload, amountMinor: "4001" }
  });
  assert.equal(overReturn.statusCode, 409, overReturn.body);
  assert.equal(json<{ error: string }>(overReturn.body).error, "return_exceeds_original_obligation");

  const mutateReturn = await approval.inject({
    method: "PATCH",
    url: "/v1/relationships/" + relation + "/sales-returns/" + storedReturnId,
    headers: { authorization: "Bearer " + seller.token },
    payload: {}
  });
  assert.equal(mutateReturn.statusCode, 409, mutateReturn.body);
  assert.equal(json<{ error: string }>(mutateReturn.body).error, "published_return_is_immutable");

  for (const token of [seller.token, buyer.token]) {
    const statement = await approval.inject({
      method: "GET",
      url: "/v1/relationships/" + relation + "/account-cycles/" + cycleId + "/sales-returns",
      headers: { authorization: "Bearer " + token }
    });
    assert.equal(statement.statusCode, 200, statement.body);
    const rows = json<{ salesReturns: Array<{ returnId: string; amountMinor: string; approval: { decision: string } }> }>(
      statement.body
    ).salesReturns;
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.returnId, storedReturnId);
    assert.equal(rows[0]?.amountMinor, "1000");
    assert.equal(rows[0]?.approval.decision, "approved");
  }

  const resetRequestId = randomUUID();
  const resetRequested = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests",
    headers: {
      authorization: "Bearer " + seller.token,
      "idempotency-key": resetRequestId
    },
    payload: {}
  });
  assert.equal(resetRequested.statusCode, 201, resetRequested.body);
  assert.equal(json<{ requestId: string }>(resetRequested.body).requestId, resetRequestId);

  const pendingReset = await approval.inject({
    method: "GET",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/pending",
    headers: { authorization: "Bearer " + buyer.token }
  });
  assert.equal(pendingReset.statusCode, 200, pendingReset.body);
  assert.equal(json<{ request: { requestId: string } }>(pendingReset.body).request.requestId, resetRequestId);

  const selfResetDecision = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/" + resetRequestId + "/decision",
    headers: {
      authorization: "Bearer " + seller.token,
      "idempotency-key": randomUUID()
    },
    payload: { decision: "approved", reason: "requester must not decide" }
  });
  assert.equal(selfResetDecision.statusCode, 403, selfResetDecision.body);

  const resetDecision = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/" + resetRequestId + "/decision",
    headers: {
      authorization: "Bearer " + buyer.token,
      "idempotency-key": randomUUID()
    },
    payload: { decision: "approved", reason: "approved return closes the page" }
  });
  assert.equal(resetDecision.statusCode, 200, resetDecision.body);
  const decisionBody = json<{ cycleReset: boolean; relationshipStatus: string }>(resetDecision.body);
  assert.equal(decisionBody.cycleReset, true);
  assert.equal(decisionBody.relationshipStatus, "active");

  const afterReset = await cycles(seller.token, relation);
  assert.notEqual(afterReset.currentCycleId, cycleId);
  assert.equal(afterReset.cycles.length, 2);
  const archived = afterReset.cycles.find((cycle) => cycle.cycleId === cycleId);
  const active = afterReset.cycles.find((cycle) => cycle.cycleId === afterReset.currentCycleId);
  assert.equal(archived?.status, "archived");
  assert.equal(active?.status, "active");

  const sellerArchived = balanceFor(afterReset, cycleId, seller.userId);
  const buyerArchived = balanceFor(afterReset, cycleId, buyer.userId);
  assertAmount(sellerArchived.receivableMinor, -1000n, "archived seller credit must be retained");
  assertAmount(buyerArchived.payableMinor, -1000n, "archived buyer credit must be retained");
  for (const owner of [seller.userId, buyer.userId]) {
    const current = balanceFor(afterReset, afterReset.currentCycleId, owner);
    assertAmount(current.receivableMinor, 0n, "new cycle receivable zero");
    assertAmount(current.payableMinor, 0n, "new cycle payable zero");
    assertAmount(current.unappliedPaymentAssetMinor, 0n, "new cycle asset zero");
    assertAmount(current.unappliedPaymentLiabilityMinor, 0n, "new cycle liability zero");
  }

  const relationshipState = await pool.query<{ status: string; current_cycle_id: string }>(
    "SELECT status,current_cycle_id FROM ledger.relationships WHERE id=$1::uuid",
    [relation]
  );
  assert.equal(relationshipState.rows[0]?.status, "active");
  assert.equal(relationshipState.rows[0]?.current_cycle_id, afterReset.currentCycleId);

  const archivedStatement = await approval.inject({
    method: "GET",
    url: "/v1/relationships/" + relation + "/account-cycles/" + cycleId + "/sales-returns",
    headers: { authorization: "Bearer " + buyer.token }
  });
  assert.equal(archivedStatement.statusCode, 200, archivedStatement.body);
  assert.equal(json<{ salesReturns: unknown[] }>(archivedStatement.body).salesReturns.length, 1);

  const relationships = await identity.inject({
    method: "GET",
    url: "/v1/relationships",
    headers: { authorization: "Bearer " + buyer.token }
  });
  assert.equal(relationships.statusCode, 200, relationships.body);
  const relationship = json<{ relationships: Array<{ relationshipId: string; status: string; currentCycleId: string }> }>(
    relationships.body
  ).relationships.find((item) => item.relationshipId === relation);
  assert.ok(relationship);
  assert.equal(relationship.status, "active");
  assert.equal(relationship.currentCycleId, afterReset.currentCycleId);
});

test("admin can disable sales returns globally at any time", async (t) => {
  const harness = createHarness(t);
  const { pool, approval, admin, login, invite, submit, decide } = harness;

  const operator = await login(phone());
  const buyer = await login(phone());
  await pool.query("UPDATE identity.users SET is_admin=true WHERE id=$1::uuid", [operator.userId]);

  try {
    const initial = await admin.inject({
      method: "GET",
      url: "/v1/admin/service-controls/sales-returns",
      headers: { authorization: "Bearer " + operator.token }
    });
    assert.equal(initial.statusCode, 200, initial.body);
    assert.equal(json<{ enabled: boolean }>(initial.body).enabled, true);

    const denied = await admin.inject({
      method: "PATCH",
      url: "/v1/admin/service-controls/sales-returns",
      headers: { authorization: "Bearer " + buyer.token },
      payload: { enabled: false }
    });
    assert.equal(denied.statusCode, 403, denied.body);

    const relation = await invite(operator, buyer);
    const chargeId = randomUUID();
    const charge = await submit(operator.token, relation, {
      operationId: chargeId,
      operationType: "credit_charge",
      schemaVersion: 1,
      baseVersion: 0,
      payload: {
        creditorUserId: operator.userId,
        debtorUserId: buyer.userId,
        currency: "YER",
        amountMinor: 5000
      },
      clientCreatedAt: new Date().toISOString()
    });
    assert.equal(charge.statusCode, 200, charge.body);
    const chargeDecision = await decide(buyer.token, relation, chargeId, "approved", "charge accepted");
    assert.equal(chargeDecision.statusCode, 200, chargeDecision.body);

    const obligation = await pool.query<{ id: string }>(
      "SELECT id FROM ledger.obligations WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
      [relation, chargeId]
    );
    assert.ok(obligation.rows[0]?.id);

    const pendingReturnId = randomUUID();
    const pendingReturn = await approval.inject({
      method: "POST",
      url: "/v1/relationships/" + relation + "/sales-returns",
      headers: {
        authorization: "Bearer " + buyer.token,
        "idempotency-key": pendingReturnId
      },
      payload: {
        originalObligationId: obligation.rows[0]!.id,
        currency: "YER",
        amountMinor: "1000",
        reason: "Created before the global switch"
      }
    });
    assert.equal(pendingReturn.statusCode, 201, pendingReturn.body);

    const disabled = await admin.inject({
      method: "PATCH",
      url: "/v1/admin/service-controls/sales-returns",
      headers: { authorization: "Bearer " + operator.token },
      payload: { enabled: false }
    });
    assert.equal(disabled.statusCode, 200, disabled.body);
    assert.equal(json<{ enabled: boolean }>(disabled.body).enabled, false);

    const newReturn = await approval.inject({
      method: "POST",
      url: "/v1/relationships/" + relation + "/sales-returns",
      headers: {
        authorization: "Bearer " + buyer.token,
        "idempotency-key": randomUUID()
      },
      payload: {
        originalObligationId: obligation.rows[0]!.id,
        currency: "YER",
        amountMinor: "1000",
        reason: "Must be blocked globally"
      }
    });
    assert.equal(newReturn.statusCode, 503, newReturn.body);
    assert.equal(json<{ error: string }>(newReturn.body).error, "sales_returns_disabled");

    const blockedDecision = await decide(operator.token, relation, pendingReturnId, "approved", "blocked by switch");
    assert.equal(blockedDecision.statusCode, 503, blockedDecision.body);
    assert.equal(json<{ error: string }>(blockedDecision.body).error, "sales_returns_disabled");

    const enabled = await admin.inject({
      method: "PATCH",
      url: "/v1/admin/service-controls/sales-returns",
      headers: { authorization: "Bearer " + operator.token },
      payload: { enabled: true }
    });
    assert.equal(enabled.statusCode, 200, enabled.body);
    assert.equal(json<{ enabled: boolean }>(enabled.body).enabled, true);

    const approved = await decide(operator.token, relation, pendingReturnId, "approved", "approved after re-enable");
    assert.equal(approved.statusCode, 200, approved.body);
  } finally {
    await admin.inject({
      method: "PATCH",
      url: "/v1/admin/service-controls/sales-returns",
      headers: { authorization: "Bearer " + operator.token },
      payload: { enabled: true }
    });
  }
});
