import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { buildAdminApi } from "./admin-api.js";

const userId = "21000000-0000-0000-0000-000000000001";
const deviceId = "71000000-0000-0000-0000-000000000001";
const controlUrl = "/v1/admin/service-controls/sales-returns";

function makePool(query: (...args: any[]) => Promise<any>): Pool {
  return { query } as unknown as Pool;
}

test("admin service control rejects unauthenticated requests before PostgreSQL", async () => {
  let called = false;
  const app = buildAdminApi({
    pool: makePool(async () => {
      called = true;
      return { rows: [] };
    }),
    resolvePrincipal: async () => null
  });
  const response = await app.inject({ method: "GET", url: controlUrl });
  assert.equal(response.statusCode, 401);
  assert.equal(called, false);
  await app.close();
});

test("admin service control hides the switch from non-admin users", async () => {
  const app = buildAdminApi({
    pool: makePool(async () => ({
      rows: [{ authorized: false, enabled: true, updated_at: null, updated_by_user_id: null }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: controlUrl });
  assert.equal(response.statusCode, 403);
  assert.deepEqual(JSON.parse(response.body), { error: "forbidden" });
  await app.close();
});

test("admin service control returns the global sales-return switch", async () => {
  let values: unknown[] = [];
  const app = buildAdminApi({
    pool: makePool(async (_sql, bound) => {
      values = bound;
      return {
        rows: [{
          authorized: true,
          enabled: true,
          updated_at: "2026-11-03T10:00:00.000Z",
          updated_by_user_id: userId
        }]
      };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({ method: "GET", url: controlUrl });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    service: "sales_returns",
    enabled: true,
    updatedAt: "2026-11-03T10:00:00.000Z",
    updatedByUserId: userId
  });
  assert.deepEqual(values, [userId, "sales_returns"]);
  await app.close();
});

test("admin service control maps a non-admin update to 403", async () => {
  const app = buildAdminApi({
    pool: makePool(async () => {
      throw Object.assign(new Error("not admin"), { code: "42501" });
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "PATCH",
    url: controlUrl,
    payload: { enabled: false }
  });
  assert.equal(response.statusCode, 403);
  assert.deepEqual(JSON.parse(response.body), { error: "forbidden" });
  await app.close();
});

test("admin service control toggles sales returns for all users", async () => {
  let values: unknown[] = [];
  const app = buildAdminApi({
    pool: makePool(async (_sql, bound) => {
      values = bound;
      return {
        rows: [{
          service_key: "sales_returns",
          enabled: false,
          updated_at: "2026-11-03T10:01:00.000Z",
          updated_by_user_id: userId
        }]
      };
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "PATCH",
    url: controlUrl,
    payload: { enabled: false }
  });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    service: "sales_returns",
    enabled: false,
    updatedAt: "2026-11-03T10:01:00.000Z",
    updatedByUserId: userId
  });
  assert.deepEqual(values, ["sales_returns", false, userId]);
  await app.close();
});

test("admin service control validates the enabled field", async () => {
  const app = buildAdminApi({
    pool: makePool(async () => ({ rows: [] })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await app.inject({
    method: "PATCH",
    url: controlUrl,
    payload: {}
  });
  assert.equal(response.statusCode, 400);
  await app.close();
});
