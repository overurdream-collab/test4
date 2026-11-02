import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  randomUUID,
  timingSafeEqual
} from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import type { Pool } from "pg";

export type IdentityPrincipal = { userId: string; deviceId: string };

type DbPool = Pick<Pool, "query">;

export interface OtpDeliveryAdapter {
  sendCode(phoneE164: string, code: string, expiresAt: Date): Promise<void>;
}

type IdentityDependencies = {
  pool: DbPool;
  otpDelivery: OtpDeliveryAdapter;
  otpPepper: string;
  accessTokenSecret: string;
  refreshTokenPepper?: string;
  now?: () => number;
};

type OtpRequestBody = { phoneE164: string };
type OtpVerifyBody = {
  phoneE164: string;
  code: string;
  deviceId: string;
  deviceLabel: string;
  platform: "android" | "ios" | "web";
};

type AccessClaims = {
  iss: "shared-commercial-ledger";
  aud: "shared-ledger-mobile";
  sub: string;
  did: string;
  jti: string;
  iat: number;
  exp: number;
};

declare module "fastify" {
  interface FastifyRequest {
    identityPrincipal: IdentityPrincipal | null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PHONE = /^\+[1-9][0-9]{7,14}$/;
const ISSUER = "shared-commercial-ledger";
const AUDIENCE = "shared-ledger-mobile";
const ACCESS_TTL_SECONDS = 15 * 60;
const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60;

function hmac(secret: string, value: string): Buffer {
  return createHmac("sha256", secret).update(value, "utf8").digest();
}

function createRefreshToken(secret: string): { token: string; hash: Buffer } {
  const token = randomBytes(32).toString("base64url");
  return { token, hash: hmac(secret, "refresh:" + token) };
}

function hashRefreshToken(secret: string, token: string): Buffer {
  return hmac(secret, "refresh:" + token);
}

function signAccessToken(claims: AccessClaims, secret: string): string {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const input = header + "." + payload;
  return input + "." + hmac(secret, input).toString("base64url");
}

function verifyAccessToken(token: string, secret: string, nowSeconds: number): AccessClaims | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [headerPart, payloadPart, signaturePart] = parts;
  if (!headerPart || !payloadPart || !signaturePart) return null;
  try {
    const header = JSON.parse(Buffer.from(headerPart, "base64url").toString("utf8")) as { alg?: string; typ?: string };
    if (header.alg !== "HS256" || header.typ !== "JWT") return null;
    const input = headerPart + "." + payloadPart;
    const expected = hmac(secret, input);
    const supplied = Buffer.from(signaturePart, "base64url");
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return null;
    const claims = JSON.parse(Buffer.from(payloadPart, "base64url").toString("utf8")) as Partial<AccessClaims>;
    if (
      claims.iss !== ISSUER || claims.aud !== AUDIENCE ||
      typeof claims.sub !== "string" || !UUID.test(claims.sub) ||
      typeof claims.did !== "string" || !UUID.test(claims.did) ||
      typeof claims.jti !== "string" || !UUID.test(claims.jti) ||
      typeof claims.iat !== "number" || typeof claims.exp !== "number" ||
      claims.exp <= nowSeconds || claims.iat > nowSeconds + 60 ||
      claims.exp - claims.iat > ACCESS_TTL_SECONDS
    ) return null;
    return claims as AccessClaims;
  } catch {
    return null;
  }
}

export function createSessionPrincipalResolver(
  pool: DbPool,
  accessTokenSecret: string,
  now: () => number = Date.now
): (request: FastifyRequest) => Promise<IdentityPrincipal | null> {
  if (Buffer.byteLength(accessTokenSecret, "utf8") < 32) {
    throw new Error("ACCESS_TOKEN_SECRET must be at least 32 bytes");
  }
  return async (request) => {
    const authorization = request.headers.authorization;
    if (typeof authorization !== "string" || !authorization.startsWith("Bearer ")) return null;
    const token = authorization.slice(7).trim();
    const claims = verifyAccessToken(token, accessTokenSecret, Math.floor(now() / 1000));
    if (!claims) return null;
    const result = await pool.query<{ user_id: string; device_id: string }>(
      "SELECT s.user_id, s.device_id " +
      "FROM identity.auth_sessions s " +
      "JOIN identity.devices d ON d.id=s.device_id AND d.user_id=s.user_id " +
      "JOIN identity.users u ON u.id=s.user_id " +
      "WHERE s.id=$1::uuid AND s.user_id=$2::uuid AND s.device_id=$3::uuid " +
      "AND s.expires_at > now() AND s.revoked_at IS NULL " +
      "AND d.status='active' AND u.status='active'",
      [claims.jti, claims.sub, claims.did]
    );
    const row = result.rows[0];
    if (!row || row.user_id !== claims.sub || row.device_id !== claims.did) return null;
    return { userId: row.user_id, deviceId: row.device_id };
  };
}

export function buildIdentityApi({
  pool,
  otpDelivery,
  otpPepper,
  accessTokenSecret,
  refreshTokenPepper = accessTokenSecret,
  now = Date.now
}: IdentityDependencies): FastifyInstance {
  if (Buffer.byteLength(otpPepper, "utf8") < 32) {
    throw new Error("OTP_PEPPER must be at least 32 bytes");
  }
  if (Buffer.byteLength(accessTokenSecret, "utf8") < 32) {
    throw new Error("ACCESS_TOKEN_SECRET must be at least 32 bytes");
  }
  if (Buffer.byteLength(refreshTokenPepper, "utf8") < 32) {
    throw new Error("REFRESH_TOKEN_PEPPER must be at least 32 bytes");
  }

  const app = Fastify({ logger: false });
  app.decorateRequest("identityPrincipal", null);
  const resolvePrincipal = createSessionPrincipalResolver(pool, accessTokenSecret, now);

  app.addHook("preHandler", async (request, reply) => {
    const path = request.url.split("?")[0];
    if (path === "/v1/auth/otp/request" || path === "/v1/auth/otp/verify" || path === "/v1/auth/refresh") return;
    try {
      const principal = await resolvePrincipal(request);
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      request.identityPrincipal = principal;
    } catch {
      return reply.code(401).send({ error: "unauthorized" });
    }
  });

  app.post<{ Body: OtpRequestBody }>(
    "/v1/auth/otp/request",
    {
      schema: {
        body: {
          type: "object", additionalProperties: false, required: ["phoneE164"],
          properties: { phoneE164: { type: "string", pattern: "^\\+[1-9][0-9]{7,14}$" } }
        }
      }
    },
    async (request, reply) => {
      const { phoneE164 } = request.body;
      if (!PHONE.test(phoneE164)) return reply.code(400).send({ error: "invalid_phone" });
      const ipHash = hmac(otpPepper, "ip:" + request.ip);
      try {
        const code = randomInt(100000, 1000000).toString();
        const codeHash = hmac(otpPepper, "login:" + phoneE164 + ":" + code);
        const expiresAt = new Date(now() + 5 * 60 * 1000);
        const challenge = await pool.query<{ challenge_id: string | null }>(
          "SELECT identity.create_otp_challenge($1,$2,$3,$4) AS challenge_id",
          [phoneE164, codeHash, ipHash, expiresAt]
        );
        const challengeId = challenge.rows[0]?.challenge_id;
        if (!challengeId) return reply.code(429).send({ error: "otp_rate_limited" });
        try {
          await otpDelivery.sendCode(phoneE164, code, expiresAt);
          await pool.query(
            "UPDATE identity.otp_challenges SET status='delivered' WHERE id=$1::uuid AND status='pending'",
            [challengeId]
          );
        } catch {
          await pool.query(
            "UPDATE identity.otp_challenges SET status='failed' WHERE id=$1::uuid AND status='pending'",
            [challengeId]
          );
          return reply.code(503).send({ error: "otp_delivery_unavailable" });
        }
        return reply.code(202).send({ status: "accepted", expiresAt });
      } catch {
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.post<{ Body: OtpVerifyBody }>(
    "/v1/auth/otp/verify",
    {
      schema: {
        body: {
          type: "object", additionalProperties: false,
          required: ["phoneE164","code","deviceId","deviceLabel","platform"],
          properties: {
            phoneE164: { type: "string", pattern: "^\\+[1-9][0-9]{7,14}$" },
            code: { type: "string", pattern: "^[0-9]{6}$" },
            deviceId: { type: "string", format: "uuid" },
            deviceLabel: { type: "string", minLength: 1, maxLength: 100 },
            platform: { type: "string", enum: ["android","ios","web"] }
          }
        }
      }
    },
    async (request, reply) => {
      const body = request.body;
      if (!PHONE.test(body.phoneE164) || !/^\d{6}$/.test(body.code) ||
          !UUID.test(body.deviceId) || body.deviceLabel.trim().length === 0) {
        return reply.code(400).send({ error: "invalid_otp_request" });
      }
      try {
        const codeHash = hmac(otpPepper, "login:" + body.phoneE164 + ":" + body.code);
        const verified = await pool.query<{ verified: boolean }>(
          "SELECT identity.consume_otp_challenge($1,$2) AS verified",
          [body.phoneE164, codeHash]
        );
        if (verified.rows[0]?.verified !== true) {
          return reply.code(401).send({ error: "invalid_or_expired_otp" });
        }

        const userResult = await pool.query<{ user_id: string }>(
          "SELECT identity.get_or_create_user_by_phone($1) AS user_id",
          [body.phoneE164]
        );
        const userId = userResult.rows[0]?.user_id;
        if (!userId) return reply.code(500).send({ error: "internal_error" });

        const deviceResult = await pool.query<{ id: string }>(
          "INSERT INTO identity.devices(id,user_id,device_label,platform) " +
          "VALUES($1::uuid,$2::uuid,$3,$4) " +
          "ON CONFLICT(id) DO UPDATE SET device_label=EXCLUDED.device_label, " +
          "platform=EXCLUDED.platform,last_seen_at=now() " +
          "WHERE identity.devices.user_id=EXCLUDED.user_id AND identity.devices.status='active' " +
          "RETURNING id",
          [body.deviceId, userId, body.deviceLabel.trim(), body.platform]
        );
        if (!deviceResult.rows[0]) return reply.code(409).send({ error: "device_unavailable" });

        const sessionId = randomUUID();
        const issuedAt = Math.floor(now() / 1000);
        const expiresAt = new Date((issuedAt + ACCESS_TTL_SECONDS) * 1000);
        const sessionExpiresAt = new Date((issuedAt + REFRESH_TTL_SECONDS) * 1000);
        await pool.query(
          "INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at) " +
          "VALUES($1::uuid,$2::uuid,$3::uuid,$4)",
          [sessionId, userId, body.deviceId, sessionExpiresAt]
        );
        const refresh = createRefreshToken(refreshTokenPepper);
        const refreshTokenId = randomUUID();
        await pool.query(
          "INSERT INTO identity.refresh_tokens(id,session_id,user_id,device_id,token_hash,expires_at) " +
          "VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6)",
          [refreshTokenId, sessionId, userId, body.deviceId, refresh.hash, sessionExpiresAt]
        );
        const accessToken = signAccessToken({
          iss: ISSUER, aud: AUDIENCE, sub: userId, did: body.deviceId,
          jti: sessionId, iat: issuedAt, exp: issuedAt + ACCESS_TTL_SECONDS
        }, accessTokenSecret);
        return reply.code(200).send({
          accessToken, tokenType: "Bearer", expiresAt,
          refreshToken: refresh.token, refreshExpiresAt: sessionExpiresAt,
          user: { id: userId, phoneE164: body.phoneE164 },
          deviceId: body.deviceId
        });
      } catch (error) {
        const code = typeof error === "object" && error !== null && "code" in error
          ? String((error as { code: unknown }).code) : undefined;
        if (code === "42501") return reply.code(403).send({ error: "account_suspended" });
        if (code === "23505") return reply.code(409).send({ error: "device_unavailable" });
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.post<{ Body: { refreshToken: string } }>(
    "/v1/auth/refresh",
    {
      schema: {
        body: {
          type: "object", additionalProperties: false, required: ["refreshToken"],
          properties: { refreshToken: { type: "string", minLength: 20, maxLength: 200 } }
        }
      }
    },
    async (request, reply) => {
      const refreshToken = request.body.refreshToken;
      if (typeof refreshToken !== "string" || refreshToken.length < 20) {
        return reply.code(400).send({ error: "invalid_refresh_token" });
      }
      const issuedAt = Math.floor(now() / 1000);
      const nextRefresh = createRefreshToken(refreshTokenPepper);
      const nextRefreshId = randomUUID();
      const refreshExpiresAt = new Date((issuedAt + REFRESH_TTL_SECONDS) * 1000);
      try {
        const result = await pool.query<{
          status: string; user_id: string | null; device_id: string | null; session_id: string | null;
        }>(
          "SELECT status,user_id,device_id,session_id FROM identity.rotate_refresh_token($1,$2,$3,$4)",
          [hashRefreshToken(refreshTokenPepper, refreshToken), nextRefreshId, nextRefresh.hash, refreshExpiresAt]
        );
        const row = result.rows[0];
        if (!row || row.status !== "rotated" || !row.user_id || !row.device_id || !row.session_id) {
          return reply.code(401).send({ error: "invalid_refresh_token" });
        }
        const expiresAt = new Date((issuedAt + ACCESS_TTL_SECONDS) * 1000);
        const accessToken = signAccessToken({
          iss: ISSUER, aud: AUDIENCE, sub: row.user_id, did: row.device_id,
          jti: row.session_id, iat: issuedAt, exp: issuedAt + ACCESS_TTL_SECONDS
        }, accessTokenSecret);
        return reply.code(200).send({
          accessToken, tokenType: "Bearer", expiresAt,
          refreshToken: nextRefresh.token, refreshExpiresAt
        });
      } catch (error) {
        const code = typeof error === "object" && error !== null && "code" in error
          ? String((error as { code: unknown }).code) : undefined;
        if (code === "22023") return reply.code(400).send({ error: "invalid_refresh_token" });
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.post(
    "/v1/auth/logout",
    { schema: { body: { type: "object", additionalProperties: false } } },
    async (request, reply) => {
      const principal = request.identityPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      try {
        await pool.query(
          "SELECT identity.revoke_device_sessions($1::uuid,$2::uuid) AS revoked",
          [principal.userId, principal.deviceId]
        );
        return reply.code(200).send({ status: "logged_out" });
      } catch {
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.get("/v1/me", async (request, reply) => {
    const principal = request.identityPrincipal;
    if (!principal) return reply.code(401).send({ error: "unauthorized" });
    try {
      const result = await pool.query<{
        user_id: string; phone_e164: string; display_name: string | null;
        locale: string; device_id: string;
      }>(
        "SELECT u.id AS user_id,pi.phone_e164,p.display_name,p.locale,d.id AS device_id " +
        "FROM identity.users u " +
        "JOIN identity.phone_identities pi ON pi.user_id=u.id " +
        "JOIN identity.devices d ON d.user_id=u.id " +
        "LEFT JOIN identity.user_profiles p ON p.user_id=u.id " +
        "WHERE u.id=$1::uuid AND d.id=$2::uuid AND d.status='active' " +
        "ORDER BY pi.verified_at DESC LIMIT 1",
        [principal.userId, principal.deviceId]
      );
      const row = result.rows[0];
      if (!row) return reply.code(404).send({ error: "profile_not_found" });
      return reply.code(200).send({
        user: { id: row.user_id, phoneE164: row.phone_e164, displayName: row.display_name, locale: row.locale },
        deviceId: row.device_id
      });
    } catch {
      return reply.code(500).send({ error: "internal_error" });
    }
  });

  app.patch<{ Body: { displayName: string } }>(
    "/v1/me",
    {
      schema: {
        body: {
          type: "object", additionalProperties: false, required: ["displayName"],
          properties: { displayName: { type: "string", minLength: 1, maxLength: 80 } }
        }
      }
    },
    async (request, reply) => {
      const principal = request.identityPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      const displayName = request.body.displayName.trim();
      if (!displayName || displayName.length > 80) return reply.code(400).send({ error: "invalid_display_name" });
      try {
        await pool.query(
          "INSERT INTO identity.user_profiles(user_id,display_name) VALUES($1::uuid,$2) " +
          "ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name,updated_at=now()",
          [principal.userId, displayName]
        );
        return reply.code(200).send({ status: "updated" });
      } catch {
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.post<{ Params: { deviceId: string } }>(
    "/v1/devices/:deviceId/revoke",
    {
      schema: {
        params: {
          type: "object", required: ["deviceId"],
          properties: { deviceId: { type: "string", format: "uuid" } }
        },
        body: { type: "object", additionalProperties: false }
      }
    },
    async (request, reply) => {
      const principal = request.identityPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      if (!UUID.test(request.params.deviceId)) return reply.code(400).send({ error: "invalid_device_id" });
      try {
        const result = await pool.query<{ id: string }>(
          "WITH revoked_device AS (" +
          " UPDATE identity.devices SET status='revoked',revoked_at=now() " +
          " WHERE id=$1::uuid AND user_id=$2::uuid AND status='active' RETURNING id" +
          "), revoked_sessions AS (" +
          " UPDATE identity.auth_sessions SET revoked_at=now() " +
          " WHERE device_id IN (SELECT id FROM revoked_device) AND user_id=$2::uuid AND revoked_at IS NULL" +
          " RETURNING id" +
          "), revoked_refresh AS (" +
          " UPDATE identity.refresh_tokens SET revoked_at=now() " +
          " WHERE session_id IN (SELECT id FROM revoked_sessions) AND user_id=$2::uuid AND revoked_at IS NULL" +
          ") SELECT id FROM revoked_device",
          [request.params.deviceId, principal.userId]
        );
        if (!result.rows[0]) return reply.code(404).send({ error: "device_not_found" });
        return reply.code(200).send({ status: "revoked", deviceId: request.params.deviceId });
      } catch {
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );


  app.post<{
    Body: {
      inviteePhoneE164: string;
      relationshipType: "merchant_customer" | "supplier_buyer";
      myRole: "merchant" | "customer" | "supplier" | "buyer";
    };
  }>(
    "/v1/relationships",
    {
      schema: {
        headers: {
          type: "object", required: ["idempotency-key"],
          properties: { "idempotency-key": { type: "string", format: "uuid" } }
        },
        body: {
          type: "object", additionalProperties: false,
          required: ["inviteePhoneE164","relationshipType","myRole"],
          properties: {
            inviteePhoneE164: { type: "string", pattern: "^\\+[1-9][0-9]{7,14}$" },
            relationshipType: { type: "string", enum: ["merchant_customer","supplier_buyer"] },
            myRole: { type: "string", enum: ["merchant","customer","supplier","buyer"] }
          }
        }
      }
    },
    async (request, reply) => {
      const principal = request.identityPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      const idempotencyKey = request.headers["idempotency-key"];
      if (typeof idempotencyKey !== "string" || !UUID.test(idempotencyKey)) {
        return reply.code(400).send({ error: "invalid_idempotency_key" });
      }
      const rolePairs = {
        merchant_customer: { merchant: "customer", customer: "merchant" },
        supplier_buyer: { supplier: "buyer", buyer: "supplier" }
      } as const;
      const inviteeRole = rolePairs[request.body.relationshipType][
        request.body.myRole as keyof typeof rolePairs[typeof request.body.relationshipType]
      ];
      if (!inviteeRole) return reply.code(422).send({ error: "invalid_role_pair" });
      const canonicalRequest = JSON.stringify({
        inviteePhoneE164: request.body.inviteePhoneE164,
        relationshipType: request.body.relationshipType,
        myRole: request.body.myRole,
        inviteeRole
      });
      const requestHash = createHash("sha256").update(canonicalRequest, "utf8").digest();
      const relationshipId = randomUUID();
      const expiresAt = new Date(now() + 7 * 24 * 60 * 60 * 1000);
      try {
        const result = await pool.query<{
          invitation_id: string; relationship_id: string; status: string; expires_at: Date | string; created: boolean;
        }>(
          "SELECT * FROM ledger.create_relationship_invitation(" +
          "$1::uuid,$2::uuid,$3::uuid,$4,$5,$6,$7,$8,$9)",
          [idempotencyKey, relationshipId, principal.userId, request.body.inviteePhoneE164,
            request.body.relationshipType, request.body.myRole, inviteeRole, requestHash, expiresAt]
        );
        const row = result.rows[0];
        if (!row) return reply.code(500).send({ error: "internal_error" });
        return reply.code(row.created ? 201 : 200).send({
          invitationId: row.invitation_id,
          relationshipId: row.relationship_id,
          status: row.status,
          inviteePhoneE164: request.body.inviteePhoneE164,
          expiresAt: row.expires_at
        });
      } catch (error) {
        const code = typeof error === "object" && error !== null && "code" in error
          ? String((error as { code: unknown }).code) : undefined;
        if (code === "42501") return reply.code(403).send({ error: "forbidden" });
        if (code === "23505" || code === "55000") return reply.code(409).send({ error: "conflict" });
        if (code === "23514" || code === "22023") return reply.code(422).send({ error: "validation_error" });
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.get("/v1/relationship-invitations", async (request, reply) => {
    const principal = request.identityPrincipal;
    if (!principal) return reply.code(401).send({ error: "unauthorized" });
    try {
      await pool.query("SELECT ledger.expire_relationship_invitations($1::uuid)", [principal.userId]);
      const result = await pool.query<{
        invitation_id: string; relationship_id: string; relationship_type: string;
        inviter_user_id: string; inviter_display_name: string | null;
        inviter_phone_e164: string | null; inviter_role: string; invitee_role: string;
        created_at: Date | string; expires_at: Date | string;
      }>(
        "SELECT ri.id AS invitation_id,ri.relationship_id,ri.relationship_type,ri.inviter_user_id," +
        "up.display_name AS inviter_display_name,ip.phone_e164 AS inviter_phone_e164," +
        "ri.inviter_role,ri.invitee_role,ri.created_at,ri.expires_at " +
        "FROM ledger.relationship_invitations ri " +
        "JOIN identity.phone_identities mine ON mine.user_id=$1::uuid AND mine.phone_e164=ri.invitee_phone_e164 " +
        "LEFT JOIN identity.user_profiles up ON up.user_id=ri.inviter_user_id " +
        "LEFT JOIN LATERAL (SELECT phone_e164 FROM identity.phone_identities " +
        "WHERE user_id=ri.inviter_user_id ORDER BY verified_at DESC LIMIT 1) ip ON true " +
        "WHERE ri.status='pending' AND ri.expires_at>now() " +
        "AND (ri.invitee_user_id IS NULL OR ri.invitee_user_id=$1::uuid) " +
        "ORDER BY ri.created_at DESC",
        [principal.userId]
      );
      return reply.code(200).send({ invitations: result.rows.map(row => ({
        invitationId: row.invitation_id,
        relationshipId: row.relationship_id,
        relationshipType: row.relationship_type,
        inviter: {
          userId: row.inviter_user_id,
          displayName: row.inviter_display_name,
          phoneE164: row.inviter_phone_e164,
          role: row.inviter_role
        },
        myRole: row.invitee_role,
        createdAt: row.created_at,
        expiresAt: row.expires_at
      })) });
    } catch {
      return reply.code(500).send({ error: "internal_error" });
    }
  });

  app.post<{
    Params: { invitationId: string };
    Body: { decision: "accepted" | "rejected"; reason?: string };
  }>(
    "/v1/relationship-invitations/:invitationId/decision",
    {
      schema: {
        params: {
          type: "object", required: ["invitationId"],
          properties: { invitationId: { type: "string", format: "uuid" } }
        },
        headers: {
          type: "object", required: ["idempotency-key"],
          properties: { "idempotency-key": { type: "string", format: "uuid" } }
        },
        body: {
          type: "object", additionalProperties: false, required: ["decision"],
          properties: {
            decision: { type: "string", enum: ["accepted","rejected"] },
            reason: { type: "string", maxLength: 1000 }
          }
        }
      }
    },
    async (request, reply) => {
      const principal = request.identityPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      const decisionId = request.headers["idempotency-key"];
      if (typeof decisionId !== "string" || !UUID.test(decisionId) || !UUID.test(request.params.invitationId)) {
        return reply.code(400).send({ error: "invalid_idempotency_key" });
      }
      try {
        const result = await pool.query<{ status: string }>(
          "SELECT ledger.decide_relationship_invitation($1::uuid,$2::uuid,$3::uuid,$4,$5) AS status",
          [request.params.invitationId, principal.userId, decisionId, request.body.decision, request.body.reason ?? null]
        );
        const status = result.rows[0]?.status;
        if (status === "expired") return reply.code(410).send({ status: "expired" });
        if (status !== "accepted" && status !== "rejected") return reply.code(500).send({ error: "internal_error" });
        return reply.code(200).send({ invitationId: request.params.invitationId, status });
      } catch (error) {
        const code = typeof error === "object" && error !== null && "code" in error
          ? String((error as { code: unknown }).code) : undefined;
        if (code === "42501") return reply.code(403).send({ error: "forbidden" });
        if (code === "23503") return reply.code(404).send({ error: "not_found" });
        if (code === "55000" || code === "23505") return reply.code(409).send({ error: "conflict" });
        if (code === "23514" || code === "22023") return reply.code(422).send({ error: "validation_error" });
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.get("/v1/relationships", async (request, reply) => {
    const principal = request.identityPrincipal;
    if (!principal) return reply.code(401).send({ error: "unauthorized" });
    try {
      const result = await pool.query<{
        relationship_id: string; relationship_type: string | null; status: string;
        current_cycle_id: string; my_role: string; other_user_id: string | null;
        other_role: string | null; other_display_name: string | null; other_phone_e164: string | null;
      }>(
        "SELECT r.id AS relationship_id,r.relationship_type,r.status,r.current_cycle_id," +
        "me.role_label AS my_role,other.user_id AS other_user_id,other.role_label AS other_role," +
        "profile.display_name AS other_display_name,other_phone.phone_e164 AS other_phone_e164 " +
        "FROM ledger.relationships r " +
        "JOIN ledger.relationship_members me ON me.relationship_id=r.id AND me.user_id=$1::uuid AND me.status='active' " +
        "LEFT JOIN ledger.relationship_members other ON other.relationship_id=r.id " +
        "AND other.user_id<>me.user_id AND other.status IN ('active','invited') " +
        "LEFT JOIN identity.user_profiles profile ON profile.user_id=other.user_id " +
        "LEFT JOIN LATERAL (SELECT phone_e164 FROM identity.phone_identities " +
        "WHERE user_id=other.user_id ORDER BY verified_at DESC LIMIT 1) other_phone ON true " +
        "ORDER BY r.created_at DESC",
        [principal.userId]
      );
      return reply.code(200).send({ relationships: result.rows.map(row => ({
        relationshipId: row.relationship_id,
        relationshipType: row.relationship_type,
        status: row.status,
        currentCycleId: row.current_cycle_id,
        myRole: row.my_role,
        otherParty: row.other_user_id ? {
          userId: row.other_user_id,
          role: row.other_role,
          displayName: row.other_display_name,
          phoneE164: row.other_phone_e164
        } : null
      })) });
    } catch {
      return reply.code(500).send({ error: "internal_error" });
    }
  });

  return app;
}
