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
};

type ServiceControlBody = { enabled: boolean };

declare module "fastify" {
  interface FastifyRequest {
    adminPrincipal: AuthenticatedPrincipal | null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SALES_RETURNS = "sales_returns";

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
  { pool, resolvePrincipal }: Dependencies
): FastifyInstance {
  app.decorateRequest("adminPrincipal", null);

  app.addHook("preHandler", async (request, reply) => {
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

  return app;
}

