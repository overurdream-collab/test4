import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { DeviceRevokedError } from "./approval-api.js";
import { buildSyncApi } from "./sync-api.js";

const relationshipId = "13000000-0000-0000-0000-000000000001";
const operationId = "33000000-0000-0000-0000-000000000001";
const userId = "23000000-0000-0000-0000-000000000001";
const deviceId = "73000000-0000-0000-0000-000000000001";
const operationUrl = "/v1/relationships/" + relationshipId + "/operations";
const eventsUrl = "/v1/relationships/" + relationshipId + "/events?after=0&limit=10";

function makePool(query: (...args: any[]) => Promise<any>): Pool {
  return { query } as unknown as Pool;
}

test("operation intake hashes the envelope and binds authenticated actor and device", async () => {
  let values: unknown[] = [];
  const app = buildSyncApi({
    pool: makePool(async (_sql, args) => {
      values = args;
      return { rows: [{
        outcome: "accepted",
        canonical_operation_id: operationId,
        business_state: "awaiting_counterparty",
        server_version: 1,
        server_sequence: 1,
        server_created_at: "2026-11-02T00:00:00.000Z"
      }] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({
    method: "POST",
    url: operationUrl,
    payload: {
      operationId,
      operationType: "credit_charge",
      schemaVersion: 1,
      baseVersion: 0,
      payload: { amountMinor: 1500, currency: "YER" },
      clientCreatedAt: "2026-11-02T00:00:00.000Z"
    }
  });

  assert.equal(response.statusCode, 200);
  assert.equal(JSON.parse(response.body).outcome, "accepted");
  assert.equal(values[0], operationId);
  assert.equal(values[1], relationshipId);
  assert.equal(values[2], userId);
  assert.equal(values[3], deviceId);
  assert.equal((values[5] as Buffer).length, 32);
  await app.close();
});

test("operation replay returns already_processed from the database", async () => {
  const app = buildSyncApi({
    pool: makePool(async () => ({
      rows: [{
        outcome: "already_processed",
        canonical_operation_id: operationId,
        business_state: "awaiting_counterparty",
        server_version: 1,
        server_sequence: 1,
        server_created_at: "2026-11-02T00:00:00.000Z"
      }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({
    method: "POST",
    url: operationUrl,
    payload: {
      operationId,
      operationType: "credit_charge",
      schemaVersion: 1,
      baseVersion: 0,
      payload: { currency: "YER", amountMinor: 1500 },
      clientCreatedAt: "2026-11-02T00:00:00.000Z"
    }
  });

  assert.equal(response.statusCode, 200);
  assert.equal(JSON.parse(response.body).outcome, "already_processed");
  await app.close();
});

test("event cursor returns only the authorized relationship's ordered events", async () => {
  const app = buildSyncApi({
    pool: makePool(async () => ({
      rows: [{
        authorized: true,
        server_sequence: 3,
        event_id: "43000000-0000-4000-8000-000000000003",
        operation_id: operationId,
        event_type: "operation.state_changed",
        event_payload: { businessState: "approved" },
        created_at: "2026-11-02T00:00:00.000Z"
      }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({ method: "GET", url: eventsUrl });
  assert.equal(response.statusCode, 200);
  const body = JSON.parse(response.body);
  assert.equal(body.events.length, 1);
  assert.equal(body.events[0].serverSequence, 3);
  assert.equal(body.nextCursor, 3);
  await app.close();
});

test("event cursor rejects a principal without relationship membership", async () => {
  const app = buildSyncApi({
    pool: makePool(async () => ({ rows: [{ authorized: false, server_sequence: null }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({ method: "GET", url: eventsUrl });
  assert.equal(response.statusCode, 403);
  await app.close();
});

test("event cursor rejects invalid or unbounded limits", async () => {
  const app = buildSyncApi({
    pool: makePool(async () => ({ rows: [] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({
    method: "GET",
    url: "/v1/relationships/" + relationshipId + "/events?after=-1&limit=9999"
  });
  assert.equal(response.statusCode, 400);
  await app.close();
});

test("a revoked device receives 403 and its unsent outbox operation is not accepted", async () => {
  let calls = 0;
  const app = buildSyncApi({
    pool: makePool(async () => { calls++; return { rows: [] }; }),
    resolvePrincipal: async () => { throw new DeviceRevokedError(); }
  });
  const response = await app.inject({
    method: "POST",
    url: operationUrl,
    payload: {
      operationId,
      operationType: "credit_charge",
      schemaVersion: 1,
      baseVersion: 0,
      payload: { currency: "YER", amountMinor: 1500 },
      clientCreatedAt: "2026-11-02T00:00:00.000Z"
    }
  });
  assert.equal(response.statusCode, 403);
  assert.deepEqual(JSON.parse(response.body), { error: "device_revoked" });
  assert.equal(calls, 0);
  await app.close();
});

test("statement returns ordered operations with actor, version and decision", async () => {
  const app = buildSyncApi({
    pool: makePool(async () => ({
      rows: [{
        authorized: true,
        operation_id: operationId,
        actor_user_id: userId,
        operation_type: "credit_charge",
        business_state: "approved",
        base_version: 0,
        server_version: 2,
        server_sequence: 4,
        operation_payload: { currency: "YER", amountMinor: 1500 },
        client_created_at: "2026-11-02T00:00:00.000Z",
        server_created_at: "2026-11-02T00:00:01.000Z",
        decision: "approved",
        decision_reason: "accepted",
        decision_actor_id: userId,
        decided_at: "2026-11-02T00:00:02.000Z"
      }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({
    method: "GET",
    url: "/v1/relationships/" + relationshipId + "/operations?after=0&limit=50"
  });
  assert.equal(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.equal(body.operations.length, 1);
  assert.equal(body.operations[0].operationId, operationId);
  assert.equal(body.operations[0].actorUserId, userId);
  assert.equal(body.operations[0].serverVersion, 2);
  assert.equal(body.operations[0].serverSequence, 4);
  assert.equal(body.operations[0].decision.decision, "approved");
  assert.equal(body.nextCursor, 4);
  assert.equal(body.hasMore, false);
  await app.close();
});

test("statement denies a principal without relationship membership", async () => {
  const app = buildSyncApi({
    pool: makePool(async () => ({ rows: [{ authorized: false }] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({
    method: "GET",
    url: "/v1/relationships/" + relationshipId + "/operations?after=0&limit=50"
  });
  assert.equal(response.statusCode, 403, response.body);
  await app.close();
});

test("statement rejects invalid cursors", async () => {
  const app = buildSyncApi({
    pool: makePool(async () => ({ rows: [] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });

  const response = await app.inject({
    method: "GET",
    url: "/v1/relationships/" + relationshipId + "/operations?after=-1&limit=9999"
  });
  assert.equal(response.statusCode, 400);
  await app.close();
});
