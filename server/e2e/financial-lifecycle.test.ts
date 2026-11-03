import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import test from "node:test";
import { Pool } from "pg";
import { buildApprovalApi } from "../src/approval-api.js";
import { buildIdentityApi, createSessionPrincipalResolver } from "../src/identity-api.js";
import { buildSyncApi } from "../src/sync-api.js";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required for financial lifecycle E2E tests");

const accessTokenSecret = process.env.ACCESS_TOKEN_SECRET ?? "e2e-access-token-secret-32-bytes-minimum";
const otpPepper = process.env.OTP_PEPPER ?? "e2e-otp-pepper-secret-32-bytes-minimum";
const refreshTokenPepper = process.env.REFRESH_TOKEN_PEPPER ?? accessTokenSecret;

type Cycle = {
  cycleId: string;
  status: "active" | "archived";
  balances: Array<{
    ownerUserId: string;
    receivableMinor: string;
    payableMinor: string;
    unappliedPaymentAssetMinor: string;
    unappliedPaymentLiabilityMinor: string;
  }>;
};

type CyclesResponse = {
  currentCycleId: string;
  cycles: Cycle[];
};

type Login = { token: string; userId: string; deviceId: string; phoneE164: string };

function phone(): string {
  return "+9677" + String(randomInt(0, 100_000_000)).padStart(8, "0");
}

function json<T>(body: string): T {
  return JSON.parse(body) as T;
}

function zeroBalance() {
  return {
    ownerUserId: "",
    receivableMinor: "0",
    payableMinor: "0",
    unappliedPaymentAssetMinor: "0",
    unappliedPaymentLiabilityMinor: "0"
  };
}

function balanceFor(cycles: CyclesResponse, cycleId: string, ownerUserId: string) {
  const cycle = cycles.cycles.find((item) => item.cycleId === cycleId);
  assert.ok(cycle, "cycle " + cycleId + " must exist");
  const found = cycle.balances.find((item) => item.ownerUserId === ownerUserId);
  return found ?? zeroBalance();
}

function assertAmount(actual: string, expected: bigint, label: string): void {
  assert.equal(BigInt(actual), expected, label);
}

test("HTTP financial lifecycle closes with zero balances and a white-page reset", async (t) => {
  const pool = new Pool({ connectionString: databaseUrl });
  const otpCodes = new Map<string, string>();
  const resolver = createSessionPrincipalResolver(pool, accessTokenSecret);
  const identity = buildIdentityApi({
    pool,
    otpDelivery: {
      async sendCode(phoneE164, code) {
        otpCodes.set(phoneE164, code);
      }
    },
    otpPepper,
    accessTokenSecret,
    refreshTokenPepper
  });
  const sync = buildSyncApi({ pool, resolvePrincipal: resolver });
  const approval = buildApprovalApi({ pool, resolvePrincipal: resolver });

  t.after(async () => {
    await Promise.all([identity.close(), sync.close(), approval.close()]);
    await pool.end();
  });

  async function login(phoneE164: string): Promise<Login> {
    const deviceId = randomUUID();
    const requested = await identity.inject({
      method: "POST",
      url: "/v1/auth/otp/request",
      payload: { phoneE164 }
    });
    assert.equal(requested.statusCode, 202, requested.body);
    const code = otpCodes.get(phoneE164);
    assert.match(code ?? "", /^[0-9]{6}$/);

    const verified = await identity.inject({
      method: "POST",
      url: "/v1/auth/otp/verify",
      payload: {
        phoneE164,
        code,
        deviceId,
        deviceLabel: "Financial lifecycle E2E",
        platform: "android"
      }
    });
    assert.equal(verified.statusCode, 200, verified.body);
    const body = json<{ accessToken: string; user: { id: string } }>(verified.body);
    return { token: body.accessToken, userId: body.user.id, deviceId, phoneE164 };
  }

  async function submit(
    token: string,
    relationshipId: string,
    envelope: {
      operationId: string;
      operationType: "credit_charge" | "payment" | "allocation";
      schemaVersion: 1;
      baseVersion: number;
      payload: Record<string, unknown>;
      clientCreatedAt: string;
    }
  ) {
    return sync.inject({
      method: "POST",
      url: "/v1/relationships/" + relationshipId + "/operations",
      headers: { authorization: "Bearer " + token },
      payload: envelope
    });
  }

  async function decide(
    token: string,
    relationshipId: string,
    operationId: string,
    decision: "approved" | "rejected",
    reason: string
  ) {
    return approval.inject({
      method: "POST",
      url: "/v1/relationships/" + relationshipId + "/operations/" + operationId + "/decision",
      headers: {
        authorization: "Bearer " + token,
        "idempotency-key": randomUUID()
      },
      payload: { decision, expectedVersion: 1, reason }
    });
  }

  async function cycles(token: string, relationshipId: string): Promise<CyclesResponse> {
    const response = await approval.inject({
      method: "GET",
      url: "/v1/relationships/" + relationshipId + "/account-cycles",
      headers: { authorization: "Bearer " + token }
    });
    assert.equal(response.statusCode, 200, response.body);
    return json<CyclesResponse>(response.body);
  }

  const seller = await login(phone());
  const buyer = await login(phone());
  const outsider = await login(phone());

  const invited = await identity.inject({
    method: "POST",
    url: "/v1/relationships",
    headers: {
      authorization: "Bearer " + seller.token,
      "idempotency-key": randomUUID()
    },
    payload: {
      inviteePhoneE164: buyer.phoneE164,
      relationshipType: "merchant_customer",
      myRole: "merchant"
    }
  });
  assert.equal(invited.statusCode, 201, invited.body);
  const invitation = json<{ relationshipId: string; invitationId: string }>(invited.body);

  const accepted = await identity.inject({
    method: "POST",
    url: "/v1/relationship-invitations/" + invitation.invitationId + "/decision",
    headers: {
      authorization: "Bearer " + buyer.token,
      "idempotency-key": randomUUID()
    },
    payload: { decision: "accepted" }
  });
  assert.equal(accepted.statusCode, 200, accepted.body);

  const relation = invitation.relationshipId;
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
