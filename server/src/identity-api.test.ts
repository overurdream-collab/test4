import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import type { Pool } from "pg";
import { buildIdentityApi, createSessionPrincipalResolver, type OtpDeliveryAdapter } from "./identity-api.js";

const otpPepper = "test-otp-pepper-must-be-at-least-32-bytes";
const accessSecret = "test-access-secret-must-be-at-least-32-bytes";
const userId = "21000000-0000-0000-0000-000000000001";
const deviceId = "71000000-0000-0000-0000-000000000001";
const sessionId = "81000000-0000-0000-0000-000000000001";
const phone = "+967771234567";

function makePool(query: (...args: any[]) => Promise<any>): Pool {
  return { query } as unknown as Pool;
}
test("OTP request stores only a digest and never returns the code", async () => {
  let storedHash: Buffer | undefined;
  let deliveredCode = "";
  const pool = makePool(async (sql: string, values: unknown[]) => {
    if (sql.includes("count(*)") && sql.includes("phone_e164")) return { rows: [{ count: 0 }] };
    if (sql.includes("count(*)") && sql.includes("requested_ip_hash")) return { rows: [{ count: 0 }] };
    if (sql.includes("INSERT INTO identity.otp_challenges")) {
      storedHash = values[1] as Buffer;
      return { rows: [{ id: "83000000-0000-0000-0000-000000000001" }] };
    }
    return { rows: [] };
  });
  const delivery: OtpDeliveryAdapter = { sendCode: async (_phone, code) => { deliveredCode = code; } };
  const app = buildIdentityApi({ pool, otpDelivery: delivery, otpPepper, accessTokenSecret: accessSecret });
  const response = await app.inject({ method: "POST", url: "/v1/auth/otp/request", payload: { phoneE164: phone } });
  assert.equal(response.statusCode, 202);
  assert.equal(deliveredCode.length, 6);
  assert.ok(storedHash);
  assert.equal(storedHash?.toString("utf8").includes(deliveredCode), false);
  assert.equal(response.body.includes(deliveredCode), false);
  await app.close();
});

test("OTP request rejects invalid E.164 input", async () => {
  let calls = 0;
  const app = buildIdentityApi({
    pool: makePool(async () => { calls++; return { rows: [] }; }),
    otpDelivery: { sendCode: async () => undefined }, otpPepper, accessTokenSecret: accessSecret
  });
  const response = await app.inject({ method: "POST", url: "/v1/auth/otp/request", payload: { phoneE164: "0771234567" } });
  assert.equal(response.statusCode, 400);
  assert.equal(calls, 0);
  await app.close();
});

test("OTP verification rejects an incorrect or expired challenge", async () => {
  let userCreationCalled = false;
  const app = buildIdentityApi({
    pool: makePool(async (sql: string) => {
      if (sql.includes("consume_otp_challenge")) return { rows: [{ verified: false }] };
      if (sql.includes("get_or_create_user_by_phone")) userCreationCalled = true;
      return { rows: [] };
    }),
    otpDelivery: { sendCode: async () => undefined }, otpPepper, accessTokenSecret: accessSecret
  });
  const response = await app.inject({
    method: "POST", url: "/v1/auth/otp/verify",
    payload: { phoneE164: phone, code: "123456", deviceId, deviceLabel: "Test", platform: "android" }
  });
  assert.equal(response.statusCode, 401);
  assert.equal(userCreationCalled, false);
  await app.close();
});

test("OTP verification creates one session and returns a signed short-lived access token", async () => {
  const sqlCalls: string[] = [];
  const pool = makePool(async (sql: string) => {
    sqlCalls.push(sql);
    if (sql.includes("consume_otp_challenge")) return { rows: [{ verified: true }] };
    if (sql.includes("get_or_create_user_by_phone")) return { rows: [{ user_id: userId }] };
    if (sql.includes("INSERT INTO identity.devices")) return { rows: [{ id: deviceId }] };
    if (sql.includes("INSERT INTO identity.auth_sessions")) return { rows: [] };
    return { rows: [] };
  });
  const app = buildIdentityApi({
    pool, otpDelivery: { sendCode: async () => undefined }, otpPepper, accessTokenSecret: accessSecret,
    now: () => 1_800_000_000_000
  });
  const response = await app.inject({
    method: "POST", url: "/v1/auth/otp/verify",
    payload: { phoneE164: phone, code: "123456", deviceId, deviceLabel: "Test Android", platform: "android" }
  });
  assert.equal(response.statusCode, 200);
  const body = JSON.parse(response.body) as { accessToken: string; user: { id: string }; expiresAt: string };
  assert.equal(body.user.id, userId);
  assert.equal(typeof body.accessToken, "string");
  assert.ok(new Date(body.expiresAt).getTime() > 1_800_000_000_000);
  assert.ok(sqlCalls.some(sql => sql.includes("INSERT INTO identity.auth_sessions")));
  await app.close();
});

test("session resolver rejects missing and malformed bearer tokens before database access", async () => {
  let calls = 0;
  const resolver = createSessionPrincipalResolver(makePool(async () => { calls++; return { rows: [] }; }), accessSecret);
  assert.equal(await resolver({ headers: {} } as any), null);
  assert.equal(await resolver({ headers: { authorization: "Bearer invalid" } } as any), null);
  assert.equal(calls, 0);
});

test("session resolver requires an active server session and active device", async () => {
  const claims = {
    iss: "shared-commercial-ledger", aud: "shared-ledger-mobile", sub: userId,
    did: deviceId, jti: sessionId, iat: 1_800_000_000, exp: 1_800_000_900
  };
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const input = header + "." + payload;
  const token = input + "." + createHmac("sha256", accessSecret).update(input).digest("base64url");
  const resolver = createSessionPrincipalResolver(
    makePool(async (sql: string, values: unknown[]) => {
      assert.ok(sql.includes("identity.auth_sessions"));
      assert.deepEqual(values, [sessionId, userId, deviceId]);
      return { rows: [{ user_id: userId, device_id: deviceId }] };
    }),
    accessSecret, () => 1_800_000_100_000
  );
  const principal = await resolver({ headers: { authorization: "Bearer " + token } } as any);
  assert.deepEqual(principal, { userId, deviceId });
});

test("revocation endpoint is scoped to the authenticated user's devices", async () => {
  const sqlCalls: string[] = [];
  const pool = makePool(async (sql: string) => {
    sqlCalls.push(sql);
    if (sql.includes("consume_otp_challenge")) return { rows: [{ verified: true }] };
    if (sql.includes("get_or_create_user_by_phone")) return { rows: [{ user_id: userId }] };
    if (sql.includes("INSERT INTO identity.devices")) return { rows: [{ id: deviceId }] };
    if (sql.includes("INSERT INTO identity.auth_sessions")) return { rows: [] };
    if (sql.includes("FROM identity.auth_sessions s")) return { rows: [{ user_id: userId, device_id: deviceId }] };
    if (sql.includes("WITH revoked_device")) return { rows: [{ id: deviceId }] };
    return { rows: [] };
  });
  const app = buildIdentityApi({
    pool, otpDelivery: { sendCode: async () => undefined }, otpPepper, accessTokenSecret: accessSecret,
    now: () => 1_800_000_000_000
  });
  const login = await app.inject({
    method: "POST", url: "/v1/auth/otp/verify",
    payload: { phoneE164: phone, code: "123456", deviceId, deviceLabel: "Test", platform: "android" }
  });
  assert.equal(login.statusCode, 200);
  const token = (JSON.parse(login.body) as { accessToken: string }).accessToken;
  const response = await app.inject({
    method: "POST", url: "/v1/devices/" + deviceId + "/revoke",
    headers: { authorization: "Bearer " + token }, payload: {}
  });
  assert.equal(response.statusCode, 200);
  assert.ok(sqlCalls.some(sql => sql.includes("WITH revoked_device")));
  await app.close();
});
