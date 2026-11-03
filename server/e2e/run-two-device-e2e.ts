import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomInt, randomUUID } from "node:crypto";
import path from "node:path";
import pg from "pg";
import { buildApprovalApi } from "../src/approval-api.js";
import { buildIdentityApi, createSessionPrincipalResolver } from "../src/identity-api.js";
import { buildSyncApi } from "../src/sync-api.js";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const accessTokenSecret =
  process.env.ACCESS_TOKEN_SECRET ?? "e2e-access-token-secret-32-bytes-minimum";
const otpPepper = process.env.OTP_PEPPER ?? "e2e-otp-pepper-secret-32-bytes-minimum";
const refreshTokenPepper = process.env.REFRESH_TOKEN_PEPPER ?? accessTokenSecret;

function phone(): string {
  return "+9677" + String(randomInt(0, 100_000_000)).padStart(8, "0");
}

function json<T>(body: string): T {
  return JSON.parse(body) as T;
}

type Login = { token: string; userId: string; deviceId: string; phoneE164: string };

function runFlutter(env: NodeJS.ProcessEnv): Promise<void> {
  return new Promise((resolve, reject) => {
    const mobileRoot = path.resolve(process.cwd(), "../mobile");
    const child = spawn(
      "flutter",
      ["test", "test_e2e/two_devices_real_server_test.dart", "-r", "expanded"],
      { cwd: mobileRoot, env: { ...process.env, ...env }, stdio: "inherit" }
    );
    const timeout = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error("Flutter two-device E2E exceeded 180 seconds"));
    }, 180_000);
    child.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on("exit", (code) => {
      clearTimeout(timeout);
      if (code === 0) resolve();
      else reject(new Error("Flutter two-device E2E failed with exit code " + code));
    });
  });
}

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
      deviceLabel: "Two-device offline E2E",
      platform: "android"
    }
  });
  assert.equal(verified.statusCode, 200, verified.body);
  const body = json<{ accessToken: string; user: { id: string } }>(verified.body);
  return { token: body.accessToken, userId: body.user.id, deviceId, phoneE164 };
}

async function invite(seller: Login, buyer: Login): Promise<string> {
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

async function verifyCommitted(relationshipId: string, operationId: string): Promise<void> {
  const operation = await pool.query<{
    business_state: string;
  }>(
    "SELECT business_state FROM ledger.operations WHERE operation_id=$1::uuid AND relationship_id=$2::uuid",
    [operationId, relationshipId]
  );
  assert.equal(operation.rows.length, 1, "exactly one operation must exist");
  assert.equal(operation.rows[0]?.business_state, "approved");

  const events = await pool.query<{ count: number }>(
    "SELECT count(*)::int AS count FROM ledger.relationship_events" +
    " WHERE relationship_id=$1::uuid AND operation_id=$2::uuid",
    [relationshipId, operationId]
  );
  assert.equal(events.rows[0]?.count, 2, "operation.created and state_changed only");

  const total = await pool.query<{ count: number }>(
    "SELECT count(*)::int AS count FROM ledger.operations WHERE relationship_id=$1::uuid",
    [relationshipId]
  );
  assert.equal(total.rows[0]?.count, 1, "no duplicate financial operation");
}

try {
  const seller = await login(phone());
  const buyer = await login(phone());
  const relationshipId = await invite(seller, buyer);

  const syncBase = await sync.listen({ host: "127.0.0.1", port: 0 });
  const approvalBase = await approval.listen({ host: "127.0.0.1", port: 0 });
  const chargeId = randomUUID();
  const approvalId = randomUUID();

  console.log("Two-device E2E sync server: " + syncBase);
  console.log("Two-device E2E approval server: " + approvalBase);
  await runFlutter({
    E2E_SYNC_URL: syncBase,
    E2E_APPROVAL_URL: approvalBase,
    E2E_SELLER_TOKEN: seller.token,
    E2E_BUYER_TOKEN: buyer.token,
    E2E_RELATIONSHIP_ID: relationshipId,
    E2E_SELLER_USER_ID: seller.userId,
    E2E_BUYER_USER_ID: buyer.userId,
    E2E_CHARGE_ID: chargeId,
    E2E_APPROVAL_ID: approvalId
  });

  await verifyCommitted(relationshipId, chargeId);
  console.log("Two-device offline/reconnect E2E passed");
} finally {
  await Promise.allSettled([
    identity.close(),
    sync.close(),
    approval.close()
  ]);
  await pool.end();
}
