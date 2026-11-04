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

async function submitAndDecide(harness: any, token: string, relation: string, envelope: any, deciderToken: string) {
  const submitted = await harness.submit(token, relation, envelope);
  assert.equal(submitted.statusCode, 200, submitted.body);
  const decision = await harness.decide(deciderToken, relation, envelope.operationId, "approved", "step-9 completion approval");
  assert.equal(decision.statusCode, 200, decision.body);
  return decision;
}

async function rejectPending(harness: any, token: string, relation: string, operationId: string, reason: string) {
  const decision = await harness.decide(token, relation, operationId, "rejected", reason);
  assert.equal(decision.statusCode, 200, decision.body);
}

async function getObligation(pool: any, relation: string, sourceOperationId: string) {
  const row = await pool.query(
    "SELECT id FROM ledger.obligations WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
    [relation, sourceOperationId]
  );
  assert.ok(row.rows[0]?.id, "obligation must be materialized");
  return row.rows[0].id as string;
}

async function getPayment(pool: any, relation: string, sourceOperationId: string) {
  const row = await pool.query(
    "SELECT id FROM ledger.payments WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
    [relation, sourceOperationId]
  );
  assert.ok(row.rows[0]?.id, "payment must be materialized");
  return row.rows[0].id as string;
}

test("step 9: credit application, refund, reversal, and concurrent allocations", async (t) => {
  const harness = createHarness(t);
  const { pool, approval, login, invite, submit, decide, cycles } = harness;

  const seller = await login(phone());
  const buyer = await login(phone());
  const relation = await invite(seller, buyer);
  let cycleId = (await cycles(seller.token, relation)).currentCycleId;

  // ---------- initial settled obligation ----------
  const chargeId = randomUUID();
  await submitAndDecide(harness, seller.token, relation, {
    operationId: chargeId, operationType: "credit_charge", schemaVersion: 1, baseVersion: 0,
    payload: { creditorUserId: seller.userId, debtorUserId: buyer.userId, currency: "YER", amountMinor: 5000 },
    clientCreatedAt: new Date().toISOString()
  }, buyer.token);
  const obligationId = await getObligation(pool, relation, chargeId);

  const paymentId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: paymentId, operationType: "payment", schemaVersion: 1, baseVersion: 0,
    payload: { payerUserId: buyer.userId, payeeUserId: seller.userId, currency: "YER", amountMinor: 5000 },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);
  const paymentRecordId = await getPayment(pool, relation, paymentId);

  const allocationId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: allocationId, operationType: "allocation", schemaVersion: 1, baseVersion: 0,
    payload: { paymentId: paymentRecordId, obligationId, amountMinor: 5000 },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const settled = await cycles(seller.token, relation);
  for (const owner of [seller.userId, buyer.userId]) {
    const b = balanceFor(settled, cycleId, owner);
    assertAmount(b.receivableMinor, 0n, "initial settled receivable");
    assertAmount(b.payableMinor, 0n, "initial settled payable");
  }

  // ---------- credit balance from an approved return applied to a future purchase ----------
  const returnId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: returnId, operationType: "sales_return", schemaVersion: 1, baseVersion: 0,
    payload: { originalObligationId: obligationId, currency: "YER", amountMinor: "1000", reason: "returned goods" },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const afterReturn = await cycles(seller.token, relation);
  assertAmount(balanceFor(afterReturn, cycleId, seller.userId).receivableMinor, -1000n, "seller return credit");
  assertAmount(balanceFor(afterReturn, cycleId, buyer.userId).payableMinor, -1000n, "buyer return credit");

  const newChargeId = randomUUID();
  await submitAndDecide(harness, seller.token, relation, {
    operationId: newChargeId, operationType: "credit_charge", schemaVersion: 1, baseVersion: 0,
    payload: { creditorUserId: seller.userId, debtorUserId: buyer.userId, currency: "YER", amountMinor: 1000 },
    clientCreatedAt: new Date().toISOString()
  }, buyer.token);
  const newObligationId = await getObligation(pool, relation, newChargeId);

  const creditApplicationId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: creditApplicationId, operationType: "credit_application", schemaVersion: 1, baseVersion: 0,
    payload: { creditSourceOperationId: returnId, targetObligationId: newObligationId, currency: "YER", amountMinor: "1000", reason: "apply return credit to new charge" },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const creditRow = await pool.query(
    "SELECT credit_applied_minor FROM ledger.obligations WHERE id=$1::uuid",
    [newObligationId]
  );
  assert.equal(creditRow.rows[0]?.credit_applied_minor, "1000", "credit applied to obligation");

  const appRow = await pool.query(
    "SELECT count(*)::text AS count FROM ledger.credit_applications WHERE source_operation_id=$1::uuid",
    [creditApplicationId]
  );
  assert.equal(appRow.rows[0]?.count, "1", "credit application recorded");

  const afterCredit = await cycles(seller.token, relation);
  for (const owner of [seller.userId, buyer.userId]) {
    const b = balanceFor(afterCredit, cycleId, owner);
    assertAmount(b.receivableMinor, 0n, "receivable zero after credit application");
    assertAmount(b.payableMinor, 0n, "payable zero after credit application");
  }

  const overCredit = await submit(buyer.token, relation, {
    operationId: randomUUID(), operationType: "credit_application", schemaVersion: 1, baseVersion: 0,
    payload: { creditSourceOperationId: returnId, targetObligationId: newObligationId, currency: "YER", amountMinor: "1001", reason: "too much" },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(overCredit.statusCode, 200, overCredit.body);
  const overCreditDecision = await decide(seller.token, relation, (json<{ operationId: string }>(overCredit.body)).operationId, "approved", "too much credit");
  assert.equal(overCreditDecision.statusCode, 409, overCreditDecision.body);
  await rejectPending(harness, seller.token, relation, (json<{ operationId: string }>(overCredit.body)).operationId, "reject over-credit");

  const duplicateCredit = await submit(buyer.token, relation, {
    operationId: randomUUID(), operationType: "credit_application", schemaVersion: 1, baseVersion: 0,
    payload: { creditSourceOperationId: returnId, targetObligationId: newObligationId, currency: "YER", amountMinor: "1000", reason: "duplicate" },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(duplicateCredit.statusCode, 200, duplicateCredit.body);
  const duplicateCreditDecision = await decide(seller.token, relation, (json<{ operationId: string }>(duplicateCredit.body)).operationId, "approved", "duplicate credit");
  assert.equal(duplicateCreditDecision.statusCode, 409, duplicateCreditDecision.body);
  await rejectPending(harness, seller.token, relation, (json<{ operationId: string }>(duplicateCredit.body)).operationId, "reject duplicate credit");

  // ---------- independent refund cancels return credit ----------
  const refundChargeId = randomUUID();
  await submitAndDecide(harness, seller.token, relation, {
    operationId: refundChargeId, operationType: "credit_charge", schemaVersion: 1, baseVersion: 0,
    payload: { creditorUserId: seller.userId, debtorUserId: buyer.userId, currency: "YER", amountMinor: 1000 },
    clientCreatedAt: new Date().toISOString()
  }, buyer.token);
  const refundObligationId = await getObligation(pool, relation, refundChargeId);

  const refundPaymentId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: refundPaymentId, operationType: "payment", schemaVersion: 1, baseVersion: 0,
    payload: { payerUserId: buyer.userId, payeeUserId: seller.userId, currency: "YER", amountMinor: 1000 },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);
  const refundPaymentRecordId = await getPayment(pool, relation, refundPaymentId);

  const refundAllocationId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: refundAllocationId, operationType: "allocation", schemaVersion: 1, baseVersion: 0,
    payload: { paymentId: refundPaymentRecordId, obligationId: refundObligationId, amountMinor: 1000 },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const refundReturnId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: refundReturnId, operationType: "sales_return", schemaVersion: 1, baseVersion: 0,
    payload: { originalObligationId: refundObligationId, currency: "YER", amountMinor: "1000", reason: "refundable return" },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const afterRefundReturn = await cycles(seller.token, relation);
  assertAmount(balanceFor(afterRefundReturn, cycleId, seller.userId).receivableMinor, -1000n, "refund scenario return credit");
  assertAmount(balanceFor(afterRefundReturn, cycleId, buyer.userId).payableMinor, -1000n, "refund scenario buyer credit");

  const refundId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: refundId, operationType: "refund", schemaVersion: 1, baseVersion: 0,
    payload: { originalSalesReturnId: refundReturnId, currency: "YER", amountMinor: "1000", reason: "cash refund to buyer" },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const refundRow = await pool.query(
    "SELECT count(*)::text AS count FROM ledger.refunds WHERE source_operation_id=$1::uuid",
    [refundId]
  );
  assert.equal(refundRow.rows[0]?.count, "1", "independent refund recorded");

  const afterRefund = await cycles(seller.token, relation);
  for (const owner of [seller.userId, buyer.userId]) {
    const b = balanceFor(afterRefund, cycleId, owner);
    assertAmount(b.receivableMinor, 0n, "receivable zero after refund");
    assertAmount(b.payableMinor, 0n, "payable zero after refund");
  }

  const overRefund = await submit(buyer.token, relation, {
    operationId: randomUUID(), operationType: "refund", schemaVersion: 1, baseVersion: 0,
    payload: { originalSalesReturnId: refundReturnId, currency: "YER", amountMinor: "1001", reason: "too much" },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(overRefund.statusCode, 200, overRefund.body);
  const overRefundDecision = await decide(seller.token, relation, (json<{ operationId: string }>(overRefund.body)).operationId, "approved", "too much refund");
  assert.equal(overRefundDecision.statusCode, 409, overRefundDecision.body);
  await rejectPending(harness, seller.token, relation, (json<{ operationId: string }>(overRefund.body)).operationId, "reject over-refund");

  // ---------- reversal linked to the original operation ----------
  const reversalChargeId = randomUUID();
  await submitAndDecide(harness, seller.token, relation, {
    operationId: reversalChargeId, operationType: "credit_charge", schemaVersion: 1, baseVersion: 0,
    payload: { creditorUserId: seller.userId, debtorUserId: buyer.userId, currency: "YER", amountMinor: 1000 },
    clientCreatedAt: new Date().toISOString()
  }, buyer.token);

  const beforeReversal = await cycles(seller.token, relation);
  assertAmount(balanceFor(beforeReversal, cycleId, seller.userId).receivableMinor, 1000n, "reversal charge receivable exists");

  const reversalId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: reversalId, operationType: "reversal", schemaVersion: 1, baseVersion: 0,
    payload: { originalOperationId: reversalChargeId, currency: "YER", amountMinor: "1000", reason: "charge entered by mistake" },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const reversalOp = await pool.query(
    "SELECT business_state FROM ledger.operations WHERE operation_id=$1::uuid AND relationship_id=$2::uuid",
    [reversalId, relation]
  );
  assert.equal(reversalOp.rows[0]?.business_state, "approved", "reversal operation approved");
  const reversalEvent = await pool.query(
    "SELECT count(*)::text AS count FROM ledger.relationship_events WHERE operation_id=$1::uuid AND event_type='operation.state_changed'",
    [reversalId]
  );
  assert.equal(reversalEvent.rows[0]?.count, "1", "reversal event recorded");
  const reversalRow = await pool.query(
    "SELECT count(*)::text AS count FROM ledger.reversals WHERE source_operation_id=$1::uuid",
    [reversalId]
  );
  assert.equal(reversalRow.rows[0]?.count, "1", "reversal recorded");

  const afterReversal = await cycles(seller.token, relation);
  for (const owner of [seller.userId, buyer.userId]) {
    const b = balanceFor(afterReversal, cycleId, owner);
    assertAmount(b.receivableMinor, 0n, "receivable zero after reversal");
    assertAmount(b.payableMinor, 0n, "payable zero after reversal");
  }

  const doubleReversal = await submit(buyer.token, relation, {
    operationId: randomUUID(), operationType: "reversal", schemaVersion: 1, baseVersion: 0,
    payload: { originalOperationId: reversalChargeId, currency: "YER", amountMinor: "1000", reason: "again" },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(doubleReversal.statusCode, 200, doubleReversal.body);
  const doubleReversalDecision = await decide(seller.token, relation, (json<{ operationId: string }>(doubleReversal.body)).operationId, "approved", "again");
  assert.equal(doubleReversalDecision.statusCode, 409, doubleReversalDecision.body);
  await rejectPending(harness, seller.token, relation, (json<{ operationId: string }>(doubleReversal.body)).operationId, "reject duplicate reversal");

  // ---------- concurrent allocations on the same payment and obligation ----------
  const charge2Id = randomUUID();
  await submitAndDecide(harness, seller.token, relation, {
    operationId: charge2Id, operationType: "credit_charge", schemaVersion: 1, baseVersion: 0,
    payload: { creditorUserId: seller.userId, debtorUserId: buyer.userId, currency: "YER", amountMinor: 1000 },
    clientCreatedAt: new Date().toISOString()
  }, buyer.token);
  const obligation2Id = await getObligation(pool, relation, charge2Id);

  const payment2Id = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: payment2Id, operationType: "payment", schemaVersion: 1, baseVersion: 0,
    payload: { payerUserId: buyer.userId, payeeUserId: seller.userId, currency: "YER", amountMinor: 1000 },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);
  const payment2RecordId = await getPayment(pool, relation, payment2Id);

  const results = await Promise.all([
    submit(buyer.token, relation, {
      operationId: randomUUID(), operationType: "allocation", schemaVersion: 1, baseVersion: 0,
      payload: { paymentId: payment2RecordId, obligationId: obligation2Id, amountMinor: 600 },
      clientCreatedAt: new Date().toISOString()
    }),
    submit(buyer.token, relation, {
      operationId: randomUUID(), operationType: "allocation", schemaVersion: 1, baseVersion: 0,
      payload: { paymentId: payment2RecordId, obligationId: obligation2Id, amountMinor: 600 },
      clientCreatedAt: new Date().toISOString()
    })
  ]);

  const statuses = results.map((r) => r.statusCode);
  assert.ok(statuses.includes(200), "one concurrent allocation must succeed");
  assert.ok(statuses.includes(409), "the other concurrent allocation must fail");

  const successful = results.find((r) => r.statusCode === 200);
  if (!successful) throw new Error("expected one concurrent allocation to succeed");
  const successBody = json<{ operationId: string }>(successful.body);
  await decide(buyer.token, relation, successBody.operationId, "approved", "approve winning allocation");

  const overAllocate = await submit(buyer.token, relation, {
    operationId: randomUUID(), operationType: "allocation", schemaVersion: 1, baseVersion: 0,
    payload: { paymentId: payment2RecordId, obligationId: obligation2Id, amountMinor: 500 },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(overAllocate.statusCode, 200, overAllocate.body);
  const overAllocateDecision = await decide(seller.token, relation, (json<{ operationId: string }>(overAllocate.body)).operationId, "approved", "over allocation");
  assert.equal(overAllocateDecision.statusCode, 409, overAllocateDecision.body);
  await rejectPending(harness, seller.token, relation, (json<{ operationId: string }>(overAllocate.body)).operationId, "reject over-allocation");

  const finalAllocationId = randomUUID();
  await submitAndDecide(harness, buyer.token, relation, {
    operationId: finalAllocationId, operationType: "allocation", schemaVersion: 1, baseVersion: 0,
    payload: { paymentId: payment2RecordId, obligationId: obligation2Id, amountMinor: 400 },
    clientCreatedAt: new Date().toISOString()
  }, seller.token);

  const allocated = await pool.query(
    "SELECT coalesce(sum(amount_minor),0)::text AS sum FROM ledger.allocations WHERE obligation_id=$1::uuid",
    [obligation2Id]
  );
  assert.equal(allocated.rows[0]?.sum, "1000", "obligation fully allocated");

  const invalidType = await submit(seller.token, relation, {
    operationId: randomUUID(), operationType: "refund_cash" as any, schemaVersion: 1, baseVersion: 0,
    payload: {}, clientCreatedAt: new Date().toISOString()
  });
  assert.equal(invalidType.statusCode, 400, invalidType.body);

  const finalCycleId = (await cycles(seller.token, relation)).currentCycleId;
  for (const owner of [seller.userId, buyer.userId]) {
    const b = balanceFor(await cycles(seller.token, relation), finalCycleId, owner);
    assertAmount(b.receivableMinor, 0n, "final receivable zero");
    assertAmount(b.payableMinor, 0n, "final payable zero");
  }

  const resetRequestId = randomUUID();
  const resetRequested = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests",
    headers: { authorization: "Bearer " + seller.token, "idempotency-key": resetRequestId },
    payload: {}
  });
  assert.equal(resetRequested.statusCode, 201, resetRequested.body);
  const resetDecision = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/" + resetRequestId + "/decision",
    headers: { authorization: "Bearer " + buyer.token, "idempotency-key": randomUUID() },
    payload: { decision: "approved", reason: "all cycles settled after credit application, refund, reversal, and concurrency" }
  });
  assert.equal(resetDecision.statusCode, 200, resetDecision.body);
  assert.equal(json<{ cycleReset: boolean }>(resetDecision.body).cycleReset, true);
});
