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

test("HTTP financial lifecycle closes with zero balances and a white-page reset", async (t) => {
  const harness = createHarness(t);
  const { pool, identity, approval, login, invite, submit, decide, cycles } = harness;

  const seller = await login(phone());
  const buyer = await login(phone());
  const outsider = await login(phone());
  const relation = await invite(seller, buyer);

  const opening = await cycles(seller.token, relation);
  const originalCycleId = opening.currentCycleId;
  assert.equal(opening.cycles.length, 1);

  const chargeId = randomUUID();
  const chargeEnvelope = {
    operationId: chargeId,
    operationType: "credit_charge" as const,
    schemaVersion: 1 as const,
    baseVersion: 0,
    payload: {
      creditorUserId: seller.userId,
      debtorUserId: buyer.userId,
      currency: "YER",
      amountMinor: 5000
    },
    clientCreatedAt: new Date().toISOString()
  };
  const charge = await submit(seller.token, relation, chargeEnvelope);
  assert.equal(charge.statusCode, 200, charge.body);

  const selfApproval = await decide(seller.token, relation, chargeId, "approved", "creator must not approve");
  assert.equal(selfApproval.statusCode, 403, selfApproval.body);

  const chargeDecision = await decide(buyer.token, relation, chargeId, "approved", "charge accepted");
  assert.equal(chargeDecision.statusCode, 200, chargeDecision.body);
  assert.equal(json<{ serverVersion: number }>(chargeDecision.body).serverVersion, 2);

  const replay = await submit(seller.token, relation, chargeEnvelope);
  assert.equal(replay.statusCode, 200, replay.body);
  const obligationCount = await pool.query<{ count: string }>(
    "SELECT count(*)::text AS count FROM ledger.obligations WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
    [relation, chargeId]
  );
  assert.equal(obligationCount.rows[0]?.count, "1");

  const afterCharge = await cycles(seller.token, relation);
  const sellerCharge = balanceFor(afterCharge, originalCycleId, seller.userId);
  const buyerCharge = balanceFor(afterCharge, originalCycleId, buyer.userId);
  assertAmount(sellerCharge.receivableMinor, 5000n, "seller receivable after charge");
  assertAmount(buyerCharge.payableMinor, 5000n, "buyer payable after charge");

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

  const beforeAllocation = await cycles(seller.token, relation);
  const sellerBefore = balanceFor(beforeAllocation, originalCycleId, seller.userId);
  const buyerBefore = balanceFor(beforeAllocation, originalCycleId, buyer.userId);
  assertAmount(sellerBefore.receivableMinor, 5000n, "seller receivable before allocation");
  assertAmount(sellerBefore.unappliedPaymentLiabilityMinor, 5000n, "seller unapplied liability before allocation");
  assertAmount(buyerBefore.payableMinor, 5000n, "buyer payable before allocation");
  assertAmount(buyerBefore.unappliedPaymentAssetMinor, 5000n, "buyer unapplied asset before allocation");

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

  const afterAllocation = await cycles(seller.token, relation);
  for (const owner of [seller.userId, buyer.userId]) {
    const settled = balanceFor(afterAllocation, originalCycleId, owner);
    assertAmount(settled.receivableMinor, 0n, "receivable cleared");
    assertAmount(settled.payableMinor, 0n, "payable cleared");
    assertAmount(settled.unappliedPaymentAssetMinor, 0n, "unapplied asset cleared");
    assertAmount(settled.unappliedPaymentLiabilityMinor, 0n, "unapplied liability cleared");
  }

  const buyerView = await cycles(buyer.token, relation);
  assert.deepEqual(buyerView.currentCycleId, originalCycleId);
  const outsiderView = await approval.inject({
    method: "GET",
    url: "/v1/relationships/" + relation + "/account-cycles",
    headers: { authorization: "Bearer " + outsider.token }
  });
  assert.equal(outsiderView.statusCode, 403, outsiderView.body);

  const pendingBefore = await approval.inject({
    method: "GET",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/pending",
    headers: { authorization: "Bearer " + seller.token }
  });
  assert.equal(pendingBefore.statusCode, 200, pendingBefore.body);
  assert.equal(json<{ request: unknown }>(pendingBefore.body).request, null);

  const requestId = randomUUID();
  const resetRequested = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests",
    headers: {
      authorization: "Bearer " + seller.token,
      "idempotency-key": requestId
    },
    payload: {}
  });
  assert.equal(resetRequested.statusCode, 201, resetRequested.body);
  assert.equal(json<{ requestId: string }>(resetRequested.body).requestId, requestId);

  const pendingAfter = await approval.inject({
    method: "GET",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/pending",
    headers: { authorization: "Bearer " + buyer.token }
  });
  assert.equal(pendingAfter.statusCode, 200, pendingAfter.body);
  assert.equal(json<{ request: { requestId: string } }>(pendingAfter.body).request.requestId, requestId);

  const selfResetDecision = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/" + requestId + "/decision",
    headers: {
      authorization: "Bearer " + seller.token,
      "idempotency-key": randomUUID()
    },
    payload: { decision: "approved", reason: "requester must not decide" }
  });
  assert.equal(selfResetDecision.statusCode, 403, selfResetDecision.body);

  const resetDecision = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/" + requestId + "/decision",
    headers: {
      authorization: "Bearer " + buyer.token,
      "idempotency-key": randomUUID()
    },
    payload: { decision: "approved", reason: "cycle settled and reset" }
  });
  assert.equal(resetDecision.statusCode, 200, resetDecision.body);
  const decisionBody = json<{ cycleReset: boolean; relationshipStatus: string }>(resetDecision.body);
  assert.equal(decisionBody.cycleReset, true);
  assert.equal(decisionBody.relationshipStatus, "active");

  const afterReset = await cycles(seller.token, relation);
  assert.notEqual(afterReset.currentCycleId, originalCycleId);
  assert.equal(afterReset.cycles.length, 2);
  const archived = afterReset.cycles.find((cycle) => cycle.cycleId === originalCycleId);
  const active = afterReset.cycles.find((cycle) => cycle.cycleId === afterReset.currentCycleId);
  assert.equal(archived?.status, "archived");
  assert.equal(active?.status, "active");
  for (const owner of [seller.userId, buyer.userId]) {
    for (const cycle of afterReset.cycles) {
      const row = balanceFor(afterReset, cycle.cycleId, owner);
      assertAmount(row.receivableMinor, 0n, "archived/new receivable zero");
      assertAmount(row.payableMinor, 0n, "archived/new payable zero");
      assertAmount(row.unappliedPaymentAssetMinor, 0n, "archived/new unapplied asset zero");
      assertAmount(row.unappliedPaymentLiabilityMinor, 0n, "archived/new unapplied liability zero");
    }
  }

  const relationships = await identity.inject({
    method: "GET",
    url: "/v1/relationships",
    headers: { authorization: "Bearer " + seller.token }
  });
  assert.equal(relationships.statusCode, 200, relationships.body);
  const relationship = json<{ relationships: Array<{ relationshipId: string; status: string; currentCycleId: string }> }>(
    relationships.body
  ).relationships.find((item) => item.relationshipId === relation);
  assert.ok(relationship);
  assert.equal(relationship.status, "active");
  assert.equal(relationship.currentCycleId, afterReset.currentCycleId);
});
