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

test("app ads endpoint requires authentication before PostgreSQL", async () => {
  let called = false;
  const app = buildAdminApi({
    pool: makePool(async () => {
      called = true;
      return { rows: [] };
    }),
    resolvePrincipal: async () => null
  });
  const response = await app.inject({ method: "GET", url: "/v1/ads" });
  assert.equal(response.statusCode, 401);
  assert.equal(called, false);
  await app.close();
});

test("admin ads listing returns active ads and rejects non-admin users", async () => {
  const app = buildAdminApi({
    pool: makePool(async () => ({
      rows: [{
        authorized: false,
        id: null,
        image_url: null,
        title: null,
        sort_order: null,
        is_active: null,
        created_at: null
      }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const denied = await app.inject({ method: "GET", url: "/v1/admin/ads" });
  assert.equal(denied.statusCode, 403);
  await app.close();

  const adId = "31000000-0000-0000-0000-000000000001";
  const allowed = buildAdminApi({
    pool: makePool(async () => ({
      rows: [{
        authorized: true,
        id: adId,
        image_url: "/uploads/ads/banner.png",
        title: "عرض افتتاحي",
        sort_order: 0,
        is_active: true,
        created_at: "2026-11-07T10:00:00.000Z"
      }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const response = await allowed.inject({ method: "GET", url: "/v1/admin/ads" });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    ads: [{
      id: adId,
      imageUrl: "/uploads/ads/banner.png",
      title: "عرض افتتاحي",
      sortOrder: 0,
      isActive: true,
      createdAt: "2026-11-07T10:00:00.000Z"
    }]
  });
  await allowed.close();
});

test("admin ad upload stores one image and serves it publicly", async () => {
  const { mkdtemp, readFile, rm } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const path = await import("node:path");
  const uploadDir = await mkdtemp(path.join(tmpdir(), "qatlink-ads-"));
  const png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2lS8AAAAASUVORK5CYII=";
  const app = buildAdminApi({
    pool: makePool(async (sql, bound) => {
      if (sql.includes("active_count")) {
        return { rows: [{ authorized: true, active_count: 0 }] };
      }
      if (sql.includes("INSERT INTO platform.admin_ads")) {
        return {
          rows: [{
            id: bound[0],
            image_url: bound[1],
            title: bound[2],
            sort_order: 0,
            is_active: true,
            created_at: "2026-11-07T10:00:00.000Z"
          }]
        };
      }
      return { rows: [] };
    }),
    resolvePrincipal: async () => ({ userId, deviceId }),
    uploadDir
  });
  try {
    const response = await app.inject({
      method: "POST",
      url: "/v1/admin/ads",
      payload: { imageDataUrl: `data:image/png;base64,${png}`, title: "بانر" }
    });
    assert.equal(response.statusCode, 201);
    const body = JSON.parse(response.body) as { ad: { id: string; imageUrl: string } };
    assert.equal(body.ad.imageUrl, `/uploads/ads/${body.ad.id}.png`);
    const stored = await readFile(path.join(uploadDir, "ads", `${body.ad.id}.png`));
    assert.equal(stored.length > 0, true);

    const served = await app.inject({
      method: "GET",
      url: body.ad.imageUrl
    });
    assert.equal(served.statusCode, 200);
    assert.equal(served.headers["content-type"], "image/png");
    assert.equal(served.rawPayload.length, stored.length);
  } finally {
    await app.close();
    await rm(uploadDir, { recursive: true, force: true });
  }
});

test("admin ad upload enforces five active ads and valid image data", async () => {
  const app = buildAdminApi({
    pool: makePool(async (sql) => {
      if (sql.includes("active_count")) {
        return { rows: [{ authorized: true, active_count: 5 }] };
      }
      throw new Error("insert should not run");
    }),
    resolvePrincipal: async () => ({ userId, deviceId })
  });
  const png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2lS8AAAAASUVORK5CYII=";
  const limit = await app.inject({
    method: "POST", url: "/v1/admin/ads", payload: { imageDataUrl: png }
  });
  assert.equal(limit.statusCode, 409);
  assert.deepEqual(JSON.parse(limit.body), { error: "ad_limit_reached" });

  const invalid = await app.inject({
    method: "POST", url: "/v1/admin/ads",
    payload: { imageDataUrl: `data:text/plain;base64,${"A".repeat(48)}` }
  });
  assert.equal(invalid.statusCode, 422);
  await app.close();
});

test("admin ad deletion removes the stored file", async () => {
  const { mkdtemp, rm, writeFile, access } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const path = await import("node:path");
  const uploadDir = await mkdtemp(path.join(tmpdir(), "qatlink-ads-"));
  const adId = "31000000-0000-0000-0000-000000000002";
  const adDir = path.join(uploadDir, "ads");
  await writeFile(path.join(adDir, `${adId}.png`), "image").catch(async () => {
    const { mkdir } = await import("node:fs/promises");
    await mkdir(adDir, { recursive: true });
    await writeFile(path.join(adDir, `${adId}.png`), "image");
  });
  const app = buildAdminApi({
    pool: makePool(async () => ({
      rows: [{ authorized: true, image_url: `/uploads/ads/${adId}.png` }]
    })),
    resolvePrincipal: async () => ({ userId, deviceId }),
    uploadDir
  });
  try {
    const response = await app.inject({
      method: "DELETE", url: `/v1/admin/ads/${adId}`
    });
    assert.equal(response.statusCode, 200);
    assert.deepEqual(JSON.parse(response.body), { status: "deleted" });
    await assert.rejects(() => access(path.join(adDir, `${adId}.png`)));
  } finally {
    await app.close();
    await rm(uploadDir, { recursive: true, force: true });
  }
});
