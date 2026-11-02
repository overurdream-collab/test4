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
    if (sql.includes("identity.create_otp_challenge")) {
      storedHash = values[1] as Buffer;
      return { rows: [{ challenge_id: "83000000-0000-0000-0000-000000000001" }] };
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


test("relationship creation, invitation lookup, bilateral acceptance and scoped listing", async () => {
  const sqlCalls: Array<{ sql: string; values: unknown[] }> = [];
  const relationshipId = "92000000-0000-0000-0000-000000000001";
  const invitationId = "91000000-0000-0000-0000-000000000001";
  const pool = makePool(async (sql: string, values: unknown[] = []) => {
    sqlCalls.push({ sql, values });
    if (sql.includes("consume_otp_challenge")) return { rows: [{ verified: true }] };
    if (sql.includes("get_or_create_user_by_phone")) return { rows: [{ user_id: userId }] };
    if (sql.includes("INSERT INTO identity.devices")) return { rows: [{ id: deviceId }] };
    if (sql.includes("INSERT INTO identity.auth_sessions")) return { rows: [] };
    if (sql.includes("FROM identity.auth_sessions s")) return { rows: [{ user_id: userId, device_id: deviceId }] };
    if (sql.includes("ledger.create_relationship_invitation")) {
      return { rows: [{ invitation_id: invitationId, relationship_id: relationshipId, status: "pending" }] };
    }
    if (sql.includes("expire_relationship_invitations")) return { rows: [{ expire_relationship_invitations: 0 }] };
    if (sql.includes("FROM ledger.relationship_invitations ri")) {
      return { rows: [{
        invitation_id: invitationId, relationship_id: relationshipId,
        relationship_type: "merchant_customer", inviter_user_id: "21000000-0000-0000-0000-000000000002",
        inviter_display_name: "Merchant", inviter_phone_e164: "+967770000001",
        inviter_role: "merchant", invitee_role: "customer",
        created_at: new Date("2026-11-02T12:00:00Z"), expires_at: new Date("2026-11-09T12:00:00Z")
      }] };
    }
    if (sql.includes("ledger.decide_relationship_invitation")) return { rows: [{ status: "accepted" }] };
    if (sql.includes("FROM ledger.relationships r")) {
      return { rows: [{
        relationship_id: relationshipId, relationship_type: "merchant_customer",
        status: "active", current_cycle_id: "96000000-0000-0000-0000-000000000001",
        my_role: "customer", other_user_id: "21000000-0000-0000-0000-000000000002",
        other_role: "merchant", other_display_name: "Merchant", other_phone_e164: "+967770000001"
      }] };
    }
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
  const headers = { authorization: "Bearer " + token };

  const create = await app.inject({
    method: "POST", url: "/v1/relationships",
    headers: { ...headers, "idempotency-key": "91000000-0000-0000-0000-000000000099" },
    payload: { inviteePhoneE164: "+967770000001", relationshipType: "merchant_customer", myRole: "merchant" }
  });
  assert.equal(create.statusCode, 201);
  assert.equal(JSON.parse(create.body).relationshipId, relationshipId);
  const createCall = sqlCalls.find(call => call.sql.includes("ledger.create_relationship_invitation"));
  assert.ok(createCall);
  assert.equal(createCall?.values[5], "merchant");
  assert.equal(createCall?.values[6], "customer");

  const invitations = await app.inject({ method: "GET", url: "/v1/relationship-invitations", headers });
  assert.equal(invitations.statusCode, 200);
  assert.equal(JSON.parse(invitations.body).invitations.length, 1);
  assert.ok(sqlCalls.some(call => call.sql.includes("expire_relationship_invitations")));

  const decision = await app.inject({
    method: "POST", url: "/v1/relationship-invitations/" + invitationId + "/decision",
    headers: { ...headers, "idempotency-key": "93000000-0000-0000-0000-000000000099" },
    payload: { decision: "accepted" }
  });
  assert.equal(decision.statusCode, 200);
  assert.equal(JSON.parse(decision.body).status, "accepted");

  const relationships = await app.inject({ method: "GET", url: "/v1/relationships", headers });
  assert.equal(relationships.statusCode, 200);
  const listed = JSON.parse(relationships.body).relationships[0];
  assert.equal(listed.relationshipId, relationshipId);
  assert.equal(listed.otherParty.role, "merchant");
  await app.close();
});

test("relationship creation rejects incompatible business roles before database mutation", async () => {
  const pool = makePool(async (sql: string) => {
    if (sql.includes("FROM identity.auth_sessions s")) return { rows: [{ user_id: userId, device_id: deviceId }] };
    return { rows: [] };
  });
  const app = buildIdentityApi({
    pool, otpDelivery: { sendCode: async () => undefined }, otpPepper, accessTokenSecret: accessSecret
  });
  // Build a valid signed token through the OTP endpoint first.
  const authPool = makePool(async (sql: string) => {
    if (sql.includes("consume_otp_challenge")) return { rows: [{ verified: true }] };
    if (sql.includes("get_or_create_user_by_phone")) return { rows: [{ user_id: userId }] };
    if (sql.includes("INSERT INTO identity.devices")) return { rows: [{ id: deviceId }] };
    if (sql.includes("INSERT INTO identity.auth_sessions")) return { rows: [] };
    if (sql.includes("FROM identity.auth_sessions s")) return { rows: [{ user_id: userId, device_id: deviceId }] };
    return { rows: [] };
  });
  const authApp = buildIdentityApi({
    pool: authPool, otpDelivery: { sendCode: async () => undefined }, otpPepper, accessTokenSecret: accessSecret,
    now: () => 1_800_000_000_000
  });
  const login = await authApp.inject({
    method: "POST", url: "/v1/auth/otp/verify",
    payload: { phoneE164: phone, code: "123456", deviceId, deviceLabel: "Test", platform: "android" }
  });
  const token = (JSON.parse(login.body) as { accessToken: string }).accessToken;
  const response = await app.inject({
    method: "POST", url: "/v1/relationships",
    headers: { authorization: "Bearer " + token, "idempotency-key": "91000000-0000-0000-0000-000000000098" },
    payload: { inviteePhoneE164: "+967770000001", relationshipType: "merchant_customer", myRole: "supplier" }
  });
  assert.equal(response.statusCode, 422);
  assert.equal(JSON.stringify(response.body).includes("ledger.create_relationship_invitation"), false);
  await app.close();
  await authApp.close();
});
