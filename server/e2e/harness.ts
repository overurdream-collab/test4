import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import type { TestContext } from "node:test";
import pg from "pg";
import { buildAdminApi } from "../src/admin-api.js";
import { buildApprovalApi } from "../src/approval-api.js";
import { buildIdentityApi, createSessionPrincipalResolver } from "../src/identity-api.js";
import { buildSyncApi } from "../src/sync-api.js";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required for financial lifecycle E2E tests");

const accessTokenSecret = process.env.ACCESS_TOKEN_SECRET ?? "e2e-access-token-secret-32-bytes-minimum";
const otpPepper = process.env.OTP_PEPPER ?? "e2e-otp-pepper-secret-32-bytes-minimum";
const refreshTokenPepper = process.env.REFRESH_TOKEN_PEPPER ?? accessTokenSecret;

export type Cycle = {
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

export type CyclesResponse = {
  currentCycleId: string;
  cycles: Cycle[];
};

export type Login = { token: string; userId: string; deviceId: string; phoneE164: string };

export type OperationEnvelope = {
  operationId: string;
  operationType: "credit_charge" | "payment" | "allocation" | "sales_return" | "refund" | "reversal" | "credit_application";
  schemaVersion: 1;
  baseVersion: number;
  payload: Record<string, unknown>;
  clientCreatedAt: string;
};

export function phone(): string {
  return "+9677" + String(randomInt(0, 100_000_000)).padStart(8, "0");
}

export function json<T>(body: string): T {
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

export function balanceFor(cycles: CyclesResponse, cycleId: string, ownerUserId: string) {
  const cycle = cycles.cycles.find((item) => item.cycleId === cycleId);
  assert.ok(cycle, "cycle " + cycleId + " must exist");
  const found = cycle.balances.find((item) => item.ownerUserId === ownerUserId);
  return found ?? zeroBalance();
}

export function assertAmount(actual: string, expected: bigint, label: string): void {
  assert.equal(BigInt(actual), expected, label);
}

export function createHarness(t: TestContext) {
  const pool = new pg.Pool({ connectionString: databaseUrl });
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
  const admin = buildAdminApi({ pool, resolvePrincipal: resolver });

  t.after(async () => {
    await Promise.all([identity.close(), sync.close(), approval.close(), admin.close()]);
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
    await new Promise((resolve) => setTimeout(resolve, 400));
    return { token: body.accessToken, userId: body.user.id, deviceId, phoneE164 };
  }

  async function invite(seller: Login, buyer: Login) {
    const response = await identity.inject({
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
    assert.equal(response.statusCode, 201, response.body);
    const invitation = json<{ relationshipId: string; invitationId: string }>(response.body);

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
    return invitation.relationshipId;
  }

  async function submit(token: string, relationshipId: string, envelope: OperationEnvelope) {
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

  return { pool, identity, sync, approval, admin, login, invite, submit, decide, cycles };
}
