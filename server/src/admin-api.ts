import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import path from "node:path";
import Fastify, { type FastifyInstance } from "fastify";
import type { Pool } from "pg";
import {
  DeviceRevokedError,
  type AuthenticatedPrincipal,
  type PrincipalResolver
} from "./approval-api.js";

type Dependencies = {
  pool: Pick<Pool, "query">;
  resolvePrincipal: PrincipalResolver;
  uploadDir?: string;
};

type ServiceControlBody = { enabled: boolean };
type AdminAdBody = { imageDataUrl: string; title?: string };
type AdminAdRow = {
  id: string;
  image_url: string;
  title: string | null;
  sort_order: number;
  is_active: boolean;
  created_at: Date | string;
};

declare module "fastify" {
  interface FastifyRequest {
    adminPrincipal: AuthenticatedPrincipal | null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SALES_RETURNS = "sales_returns";
const AD_FILE = /^[0-9a-f-]+\.(png|jpg|jpeg|webp)$/i;
const AD_MIME: Record<string, { ext: string; type: string }> = {
  "image/png": { ext: "png", type: "image/png" },
  "image/jpeg": { ext: "jpg", type: "image/jpeg" },
  "image/webp": { ext: "webp", type: "image/webp" }
};

function databaseCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String((error as { code: unknown }).code)
    : undefined;
}

export function buildAdminApi(deps: Dependencies): FastifyInstance {
  return registerAdminApi(Fastify({ logger: false }), deps);
}

export function registerAdminApi(
  app: FastifyInstance,
  { pool, resolvePrincipal, uploadDir = path.resolve(process.cwd(), "uploads") }: Dependencies
): FastifyInstance {
  const adDir = path.join(uploadDir, "ads");
  app.decorateRequest("adminPrincipal", null);

  app.addHook("preHandler", async (request, reply) => {
    if (request.url.split("?")[0]?.startsWith("/uploads/ads/")) return;
    try {
      const principal = await resolvePrincipal(request);
      if (!principal || !UUID.test(principal.userId) || !UUID.test(principal.deviceId)) {
        return reply.code(401).send({ error: "unauthorized" });
      }
      request.adminPrincipal = principal;
    } catch (error) {
      if (error instanceof DeviceRevokedError) {
        return reply.code(403).send({ error: "device_revoked" });
      }
      return reply.code(401).send({ error: "unauthorized" });
    }
  });

  app.get("/v1/admin/service-controls/sales-returns", async (request, reply) => {
    const principal = request.adminPrincipal;
    if (!principal) return reply.code(401).send({ error: "unauthorized" });

    try {
      const result = await pool.query<{
        authorized: boolean;
        enabled: boolean | null;
        updated_at: Date | string | null;
        updated_by_user_id: string | null;
      }>(
        "SELECT EXISTS(SELECT 1 FROM identity.users WHERE id=$1::uuid AND status='active' AND is_admin=true) AS authorized," +
        " (SELECT enabled FROM ledger.service_controls WHERE service_key=$2) AS enabled," +
        " (SELECT updated_at FROM ledger.service_controls WHERE service_key=$2) AS updated_at," +
        " (SELECT updated_by_user_id FROM ledger.service_controls WHERE service_key=$2) AS updated_by_user_id",
        [principal.userId, SALES_RETURNS]
      );
      const row = result.rows[0];
      if (!row?.authorized) return reply.code(403).send({ error: "forbidden" });
      if (row.enabled === null) return reply.code(404).send({ error: "service_not_found" });

      return reply.code(200).send({
        service: SALES_RETURNS,
        enabled: row.enabled,
        updatedAt: row.updated_at,
        updatedByUserId: row.updated_by_user_id
      });
    } catch (error) {
      request.log.error({ err: error }, "Service control lookup failed");
      return reply.code(500).send({ error: "internal_error" });
    }
  });

  app.patch<{ Body: ServiceControlBody }>(
    "/v1/admin/service-controls/sales-returns",
    {
      schema: {
        body: {
          type: "object",
          additionalProperties: false,
          required: ["enabled"],
          properties: { enabled: { type: "boolean" } }
        }
      }
    },
    async (request, reply) => {
      const principal = request.adminPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });

      try {
        const result = await pool.query<{
          service_key: string;
          enabled: boolean;
          updated_at: Date | string;
          updated_by_user_id: string;
        }>(
          "SELECT service_key,enabled,updated_at,updated_by_user_id" +
          " FROM ledger.set_service_control($1::text,$2::boolean,$3::uuid)",
          [SALES_RETURNS, request.body.enabled, principal.userId]
        );
        const row = result.rows[0];
        if (!row) {
          request.log.error("Service control update returned no row");
          return reply.code(500).send({ error: "internal_error" });
        }

        return reply.code(200).send({
          service: row.service_key,
          enabled: row.enabled,
          updatedAt: row.updated_at,
          updatedByUserId: row.updated_by_user_id
        });
      } catch (error) {
        const code = databaseCode(error);
        if (code === "42501") return reply.code(403).send({ error: "forbidden" });
        if (code === "22023") return reply.code(422).send({ error: "validation_error" });
        request.log.error({ err: error }, "Service control update failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );


  function adJson(row: AdminAdRow) {
    return {
      id: row.id,
      imageUrl: row.image_url,
      title: row.title,
      sortOrder: row.sort_order,
      isActive: row.is_active,
      createdAt: row.created_at
    };
  }

  app.get("/v1/ads", async (request, reply) => {
    const principal = request.adminPrincipal;
    if (!principal) return reply.code(401).send({ error: "unauthorized" });
    try {
      const result = await pool.query<AdminAdRow>(
        "SELECT id,image_url,title,sort_order,is_active,created_at " +
        "FROM platform.admin_ads WHERE is_active=true " +
        "ORDER BY sort_order ASC,created_at DESC LIMIT 5"
      );
      return reply.code(200).send({ ads: result.rows.map(adJson) });
    } catch {
      return reply.code(500).send({ error: "internal_error" });
    }
  });

  app.get("/v1/admin/ads", async (request, reply) => {
    const principal = request.adminPrincipal;
    if (!principal) return reply.code(401).send({ error: "unauthorized" });
    try {
      const result = await pool.query<AdminAdRow & { authorized: boolean }>(
        "WITH admin_check AS (" +
        " SELECT EXISTS(SELECT 1 FROM identity.users WHERE id=$1::uuid AND status='active' AND is_admin=true) AS authorized" +
        ") SELECT admin_check.authorized,a.id,a.image_url,a.title,a.sort_order,a.is_active,a.created_at " +
        "FROM admin_check LEFT JOIN platform.admin_ads a ON true " +
        "ORDER BY a.is_active DESC NULLS LAST,a.sort_order ASC,a.created_at DESC",
        [principal.userId]
      );
      if (!result.rows[0]?.authorized) return reply.code(403).send({ error: "forbidden" });
      return reply.code(200).send({ ads: result.rows.filter(row => row.id).map(adJson) });
    } catch {
      return reply.code(500).send({ error: "internal_error" });
    }
  });

  app.post<{ Body: AdminAdBody }>(
    "/v1/admin/ads",
    {
      schema: {
        body: {
          type: "object",
          additionalProperties: false,
          required: ["imageDataUrl"],
          properties: {
            imageDataUrl: { type: "string", minLength: 30, maxLength: 4_000_000 },
            title: { type: "string", minLength: 1, maxLength: 120 }
          }
        }
      }
    },
    async (request, reply) => {
      const principal = request.adminPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      const match = /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/.exec(request.body.imageDataUrl);
      if (!match) return reply.code(422).send({ error: "invalid_image" });
      const mime = match[1]!;
      const bytes = Buffer.from(match[2]!, "base64");
      if (bytes.length === 0 || bytes.length > 2 * 1024 * 1024) {
        return reply.code(422).send({ error: "image_too_large" });
      }
      const format = AD_MIME[mime];
      if (!format) return reply.code(422).send({ error: "invalid_image" });
      try {
        const access = await pool.query<{ authorized: boolean; active_count: number }>(
          "SELECT EXISTS(SELECT 1 FROM identity.users WHERE id=$1::uuid AND status='active' AND is_admin=true) AS authorized," +
          " (SELECT count(*)::int FROM platform.admin_ads WHERE is_active=true) AS active_count",
          [principal.userId]
        );
        const row = access.rows[0];
        if (!row?.authorized) return reply.code(403).send({ error: "forbidden" });
        if (Number(row.active_count) >= 5) return reply.code(409).send({ error: "ad_limit_reached" });

        const id = randomUUID();
        const filename = id + "." + format.ext;
        await mkdir(adDir, { recursive: true });
        await writeFile(path.join(adDir, filename), bytes, { flag: "wx" });
        const imageUrl = "/uploads/ads/" + filename;
        const created = await pool.query<AdminAdRow>(
          "INSERT INTO platform.admin_ads(id,image_url,title,created_by_user_id) " +
          "VALUES($1::uuid,$2,$3,$4::uuid) " +
          "RETURNING id,image_url,title,sort_order,is_active,created_at",
          [id, imageUrl, request.body.title ?? null, principal.userId]
        );
        const createdRow = created.rows[0];
        if (!createdRow) {
          await unlink(path.join(adDir, filename)).catch(() => undefined);
          return reply.code(500).send({ error: "internal_error" });
        }
        return reply.code(201).send({ ad: adJson(createdRow) });
      } catch (error) {
        const code = databaseCode(error);
        if (code === "23514") return reply.code(409).send({ error: "ad_limit_reached" });
        if (code === "42501") return reply.code(403).send({ error: "forbidden" });
        request.log.error({ err: error }, "Admin ad upload failed");
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.delete<{ Params: { adId: string } }>(
    "/v1/admin/ads/:adId",
    {
      schema: {
        params: {
          type: "object", required: ["adId"],
          properties: { adId: { type: "string", format: "uuid" } }
        }
      }
    },
    async (request, reply) => {
      const principal = request.adminPrincipal;
      if (!principal) return reply.code(401).send({ error: "unauthorized" });
      try {
        const result = await pool.query<{ authorized: boolean; image_url: string | null }>(
          "WITH admin_check AS (" +
          " SELECT EXISTS(SELECT 1 FROM identity.users WHERE id=$1::uuid AND status='active' AND is_admin=true) AS authorized" +
          "), removed AS (" +
          " DELETE FROM platform.admin_ads WHERE id=$2::uuid" +
          " AND (SELECT authorized FROM admin_check) RETURNING image_url" +
          ") SELECT admin_check.authorized,(SELECT image_url FROM removed) AS image_url FROM admin_check",
          [principal.userId, request.params.adId]
        );
        const row = result.rows[0];
        if (!row?.authorized) return reply.code(403).send({ error: "forbidden" });
        if (!row.image_url) return reply.code(404).send({ error: "not_found" });
        const filename = path.basename(row.image_url);
        if (AD_FILE.test(filename)) {
          await unlink(path.join(adDir, filename)).catch(() => undefined);
        }
        return reply.code(200).send({ status: "deleted" });
      } catch {
        return reply.code(500).send({ error: "internal_error" });
      }
    }
  );

  app.get<{ Params: { file: string } }>("/uploads/ads/:file", async (request, reply) => {
    const filename = request.params.file;
    if (!AD_FILE.test(filename)) return reply.code(404).send({ error: "not_found" });
    const ext = filename.split(".").pop()?.toLowerCase();
    const type = ext === "png" ? "image/png" : ext === "webp" ? "image/webp" : "image/jpeg";
    try {
      const bytes = await readFile(path.join(adDir, filename));
      return reply.code(200).type(type).send(bytes);
    } catch {
      return reply.code(404).send({ error: "not_found" });
    }
  });

  return app;
}

