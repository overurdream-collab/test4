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

test("HTTP sales return preserves signed credit and blocks reset until cleared", async (t) => {
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

  const blockedReset = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests",
    headers: {
      authorization: "Bearer " + seller.token,
      "idempotency-key": randomUUID()
    },
    payload: {}
  });
  assert.equal(blockedReset.statusCode, 409, blockedReset.body);
  assert.equal(json<{ error: string }>(blockedReset.body).error, "settlement_not_complete");

  const offsetChargeId = randomUUID();
  const offsetCharge = await submit(buyer.token, relation, {
    operationId: offsetChargeId,
    operationType: "credit_charge",
    schemaVersion: 1,
    baseVersion: 0,
    payload: {
      creditorUserId: buyer.userId,
      debtorUserId: seller.userId,
      currency: "YER",
      amountMinor: 1000
    },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(offsetCharge.statusCode, 200, offsetCharge.body);
  const offsetChargeDecision = await decide(seller.token, relation, offsetChargeId, "approved", "offset charge accepted");
  assert.equal(offsetChargeDecision.statusCode, 200, offsetChargeDecision.body);

  const offsetPaymentId = randomUUID();
  const offsetPayment = await submit(seller.token, relation, {
    operationId: offsetPaymentId,
    operationType: "payment",
    schemaVersion: 1,
    baseVersion: 0,
    payload: {
      payerUserId: seller.userId,
      payeeUserId: buyer.userId,
      currency: "YER",
      amountMinor: 1000
    },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(offsetPayment.statusCode, 200, offsetPayment.body);
  const offsetPaymentDecision = await decide(buyer.token, relation, offsetPaymentId, "approved", "offset payment accepted");
  assert.equal(offsetPaymentDecision.statusCode, 200, offsetPaymentDecision.body);

  const offsetObligationId = await pool.query<{ id: string }>(
    "SELECT id FROM ledger.obligations WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
    [relation, offsetChargeId]
  );
  const offsetPaymentRecordId = await pool.query<{ id: string }>(
    "SELECT id FROM ledger.payments WHERE relationship_id=$1::uuid AND source_operation_id=$2::uuid",
    [relation, offsetPaymentId]
  );
  assert.ok(offsetObligationId.rows[0]?.id);
  assert.ok(offsetPaymentRecordId.rows[0]?.id);

  const offsetAllocationId = randomUUID();
  const offsetAllocation = await submit(seller.token, relation, {
    operationId: offsetAllocationId,
    operationType: "allocation",
    schemaVersion: 1,
    baseVersion: 0,
    payload: {
      paymentId: offsetPaymentRecordId.rows[0]!.id,
      obligationId: offsetObligationId.rows[0]!.id,
      amountMinor: 1000
    },
    clientCreatedAt: new Date().toISOString()
  });
  assert.equal(offsetAllocation.statusCode, 200, offsetAllocation.body);
  const offsetAllocationDecision = await decide(buyer.token, relation, offsetAllocationId, "approved", "offset allocation accepted");
  assert.equal(offsetAllocationDecision.statusCode, 200, offsetAllocationDecision.body);

  const afterOffset = await cycles(seller.token, relation);
  for (const owner of [seller.userId, buyer.userId]) {
    const row = balanceFor(afterOffset, cycleId, owner);
    assertAmount(row.receivableMinor, 0n, "credit return receivable cleared");
    assertAmount(row.payableMinor, 0n, "credit return payable cleared");
    assertAmount(row.unappliedPaymentAssetMinor, 0n, "credit return unapplied asset cleared");
    assertAmount(row.unappliedPaymentLiabilityMinor, 0n, "credit return unapplied liability cleared");
  }

  const resetId = randomUUID();
  const resetRequest = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests",
    headers: {
      authorization: "Bearer " + seller.token,
      "idempotency-key": resetId
    },
    payload: {}
  });
  assert.equal(resetRequest.statusCode, 201, resetRequest.body);

  const resetDecision = await approval.inject({
    method: "POST",
    url: "/v1/relationships/" + relation + "/settlement-reset-requests/" + resetId + "/decision",
    headers: {
      authorization: "Bearer " + buyer.token,
      "idempotency-key": randomUUID()
    },
    payload: { decision: "approved", reason: "credit cleared before reset" }
  });
  assert.equal(resetDecision.statusCode, 200, resetDecision.body);
  assert.equal(json<{ cycleReset: boolean }>(resetDecision.body).cycleReset, true);

  const afterReset = await cycles(seller.token, relation);
  assert.notEqual(afterReset.currentCycleId, cycleId);
  assert.equal(afterReset.cycles.length, 2);
  assert.equal(afterReset.cycles.find((cycle) => cycle.cycleId === cycleId)?.status, "archived");
  assert.equal(afterReset.cycles.find((cycle) => cycle.cycleId === afterReset.currentCycleId)?.status, "active");
  for (const owner of [seller.userId, buyer.userId]) {
    for (const cycle of afterReset.cycles) {
      const row = balanceFor(afterReset, cycle.cycleId, owner);
      assertAmount(row.receivableMinor, 0n, "archived/new receivable zero");
      assertAmount(row.payableMinor, 0n, "archived/new payable zero");
      assertAmount(row.unappliedPaymentAssetMinor, 0n, "archived/new unapplied asset zero");
      assertAmount(row.unappliedPaymentLiabilityMinor, 0n, "archived/new unapplied liability zero");
    }
  }

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
