import { createHash, randomBytes, randomUUID } from "node:crypto";
import pg from "pg";

const { Pool } = pg;
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 60,
  idleTimeoutMillis: 10_000,
  connectionTimeoutMillis: 10_000,
  application_name: "ledger-financial-profile"
});
const monitorPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 4,
  application_name: "ledger-profile-monitor"
});

function uuidFromMd5(value) {
  const h = createHash("md5").update(value).digest("hex");
  return h.slice(0, 8) + "-" + h.slice(8, 12) + "-" + h.slice(12, 16) + "-" +
    h.slice(16, 20) + "-" + h.slice(20);
}

function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  return Number(sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * p))].toFixed(2));
}

function summarize(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return {
    count: sorted.length,
    p50: percentile(sorted, 0.50),
    p95: percentile(sorted, 0.95),
    p99: percentile(sorted, 0.99),
    max: sorted.length ? Number(sorted[sorted.length - 1].toFixed(2)) : null
  };
}

function delta(after, before) {
  const result = {};
  for (const key of Object.keys(after)) {
    result[key] = Number(after[key] ?? 0) - Number(before[key] ?? 0);
  }
  return result;
}

const rels = Array.from({ length: 1000 }, (_, i) => ({
  id: uuidFromMd5("bench-rel-" + (i + 1)),
  seller: uuidFromMd5("bench-user-" + (i + 1) + "-1"),
  buyer: uuidFromMd5("bench-user-" + (i + 1) + "-2"),
  device: uuidFromMd5("bench-device-profile-" + (i + 1))
}));

const stageSamples = Object.create(null);
function recordStage(name, milliseconds) {
  (stageSamples[name] ??= []).push(milliseconds);
}
async function timed(name, action) {
  const start = process.hrtime.bigint();
  try {
    return await action();
  } finally {
    recordStage(name, Number(process.hrtime.bigint() - start) / 1_000_000);
  }
}

async function createApprovedOperation(rel, type, actor, approver, payload) {
  const operationId = randomUUID();
  await timed("accept_" + type, () => pool.query(
    "SELECT * FROM ledger.accept_operation(" +
    "$1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::bytea,$7::jsonb,0,1,now())",
    [operationId, rel.id, actor, rel.device, type, randomBytes(32), JSON.stringify(payload)]
  ));
  await timed("approve_" + type + "_and_post", () => pool.query(
    "SELECT ledger.decide_operation($1::uuid,$2::uuid,$3::uuid,$4::uuid,1,'approved','financial profile')",
    [randomUUID(), rel.id, operationId, approver]
  ));
  return operationId;
}

async function readTopStatements() {
  const result = await monitorPool.query(
    "SELECT queryid::text AS queryid, calls::bigint AS calls, " +
    "total_exec_time::numeric AS total_exec_time_ms, rows::bigint AS rows, " +
    "shared_blks_hit::bigint AS shared_blks_hit, shared_blks_read::bigint AS shared_blks_read, " +
    "temp_blks_written::bigint AS temp_blks_written, left(query,240) AS query " +
    "FROM pg_stat_statements WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database()) " +
    "AND query ILIKE '%ledger.%' ORDER BY total_exec_time DESC LIMIT 20"
  );
  return result.rows;
}

function statementDeltas(afterRows, beforeRows) {
  const before = new Map(beforeRows.map(row => [row.queryid, row]));
  return afterRows.map(row => {
    const prior = before.get(row.queryid) ?? {};
    return {
      queryid: row.queryid,
      query: row.query,
      calls: Number(row.calls ?? 0) - Number(prior.calls ?? 0),
      total_exec_time_ms: Number(row.total_exec_time_ms ?? 0) - Number(prior.total_exec_time_ms ?? 0),
      rows: Number(row.rows ?? 0) - Number(prior.rows ?? 0),
      shared_blks_hit: Number(row.shared_blks_hit ?? 0) - Number(prior.shared_blks_hit ?? 0),
      shared_blks_read: Number(row.shared_blks_read ?? 0) - Number(prior.shared_blks_read ?? 0),
      temp_blks_written: Number(row.temp_blks_written ?? 0) - Number(prior.temp_blks_written ?? 0)
    };
  }).sort((a, b) => b.total_exec_time_ms - a.total_exec_time_ms);
}

async function snapshot() {
  const [wal, database] = await Promise.all([
    monitorPool.query("SELECT wal_records, wal_fpi, wal_bytes, wal_buffers_full FROM pg_stat_wal"),
    monitorPool.query("SELECT xact_commit, blks_hit, blks_read, tup_inserted, tup_updated, deadlocks, temp_bytes FROM pg_stat_database WHERE datname=current_database()")
  ]);
  let statements = null;
  let statementsError = null;
  try {
    const result = await monitorPool.query("SELECT COALESCE(sum(calls),0)::bigint AS calls, COALESCE(sum(total_exec_time),0)::numeric AS total_exec_time_ms, COALESCE(sum(shared_blks_hit),0)::bigint AS shared_blks_hit, COALESCE(sum(shared_blks_read),0)::bigint AS shared_blks_read, COALESCE(sum(temp_blks_written),0)::bigint AS temp_blks_written FROM pg_stat_statements WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database()) AND query ILIKE '%ledger.%'");
    statements = result.rows[0];
  } catch (error) {
    statementsError = String(error);
  }
  let statementsByQuery = null;
  try {
    statementsByQuery = await readTopStatements();
  } catch (error) {
    statementsError = [statementsError, String(error)].filter(Boolean).join("; ");
  }
  return { wal: wal.rows[0], database: database.rows[0], statements, statementsByQuery, statementsError };
}

async function profilePhase(concurrency, durationMs) {
  for (const key of Object.keys(stageSamples)) delete stageSamples[key];
  const waitSamples = Object.create(null);
  const lockSamples = Object.create(null);
  const activitySamples = [];
  const walSamples = [];
  const statementSamples = [];
  let lastStatementSampleAt = 0;
  const before = await snapshot();
  let stopMonitor = false;

  const monitor = (async () => {
    while (!stopMonitor) {
      try {
        const [waits, locks, activity, wal] = await Promise.all([
          monitorPool.query(
            "SELECT COALESCE(wait_event_type,'CPU_or_running') AS wait_type, " +
            "COALESCE(wait_event,'none') AS wait_event, state, count(*)::int AS sessions " +
            "FROM pg_stat_activity WHERE application_name='ledger-financial-profile' AND state='active' " +
            "GROUP BY 1,2,3"
          ),
          monitorPool.query(
            "SELECT l.locktype, l.mode, l.granted, count(*)::int AS lock_count " +
            "FROM pg_locks l JOIN pg_stat_activity a USING(pid) " +
            "WHERE a.application_name='ledger-financial-profile' " +
            "GROUP BY l.locktype,l.mode,l.granted"
          ),
          monitorPool.query(
            "SELECT state, wait_event_type, wait_event, count(*)::int AS sessions, " +
            "max(clock_timestamp()-query_start) AS longest_query_age " +
            "FROM pg_stat_activity WHERE application_name='ledger-financial-profile' " +
            "GROUP BY state,wait_event_type,wait_event"
          ),
          monitorPool.query("SELECT wal_records, wal_fpi, wal_bytes, wal_buffers_full FROM pg_stat_wal")
        ]);
        for (const row of waits.rows) {
          const key = [row.wait_type, row.wait_event, row.state].join("|");
          waitSamples[key] = (waitSamples[key] ?? 0) + row.sessions;
        }
        for (const row of locks.rows) {
          const key = [row.locktype, row.mode, row.granted].join("|");
          lockSamples[key] = (lockSamples[key] ?? 0) + row.lock_count;
        }
        const sampledAt = new Date().toISOString();
        activitySamples.push({ sampledAt, groups: activity.rows });
        walSamples.push({ sampledAt, ...wal.rows[0] });
        if (Date.now() - lastStatementSampleAt >= 5000) {
          try {
            statementSamples.push({ sampledAt, rows: await readTopStatements() });
            lastStatementSampleAt = Date.now();
          } catch (error) {
            process.stderr.write("pg_stat_statements sample failed: " + String(error) + "\\n");
          }
        }
      } catch (error) {
        process.stderr.write("monitor sample failed: " + String(error) + "\n");
      }
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  })();

  const startedAt = Date.now();
  const deadline = startedAt + durationMs;
  let completed = 0;
  let errors = 0;
  const fullLatency = [];

  await Promise.all(Array.from({ length: concurrency }, async (_, worker) => {
    let localIndex = worker * 23;
    while (Date.now() < deadline) {
      const rel = rels[localIndex % rels.length];
      localIndex += concurrency * 7 + 1;
      const start = process.hrtime.bigint();
      try {
        const amountMinor = 1000;
        const chargeId = await createApprovedOperation(
          rel, "credit_charge", rel.seller, rel.buyer,
          {
            creditorUserId: rel.seller,
            debtorUserId: rel.buyer,
            currency: "YER",
            amountMinor
          }
        );
        const obligation = await timed("lookup_obligation_id", () => pool.query(
          "SELECT id FROM ledger.obligations WHERE source_operation_id=$1::uuid",
          [chargeId]
        ));
        if (!obligation.rows[0]) throw new Error("approved credit charge did not create obligation");

        const paymentId = await createApprovedOperation(
          rel, "payment", rel.buyer, rel.seller,
          {
            payerUserId: rel.buyer,
            payeeUserId: rel.seller,
            currency: "YER",
            amountMinor
          }
        );
        const payment = await timed("lookup_payment_id", () => pool.query(
          "SELECT id FROM ledger.payments WHERE source_operation_id=$1::uuid",
          [paymentId]
        ));
        if (!payment.rows[0]) throw new Error("approved payment did not create payment");

        await createApprovedOperation(
          rel, "allocation", rel.buyer, rel.seller,
          {
            paymentId: payment.rows[0].id,
            obligationId: obligation.rows[0].id,
            amountMinor
          }
        );
        completed++;
      } catch (error) {
        errors++;
        if (errors <= 5) process.stderr.write("financial lifecycle error: " + String(error) + "\n");
      } finally {
        fullLatency.push(Number(process.hrtime.bigint() - start) / 1_000_000);
      }
    }
  }));

  stopMonitor = true;
  await monitor;
  const after = await snapshot();
  const actualDurationMs = Date.now() - startedAt;
  const stageReport = Object.fromEntries(
    Object.entries(stageSamples).map(([name, values]) => [name, summarize(values)])
  );
  const report = {
    label: "financial_lifecycle_profile",
    concurrency,
    targetDurationMs: durationMs,
    actualDurationMs,
    completedLifecycles: completed,
    errors,
    throughputPerSecond: Number((completed / (actualDurationMs / 1000)).toFixed(2)),
    fullLifecycleLatencyMs: summarize(fullLatency),
    stageLatencyMs: stageReport,
    sampledWaitEvents: waitSamples,
    sampledLocks: lockSamples,
    sampledActivity: activitySamples,
    sampledWal: walSamples,
    sampledPgStatStatements: statementSamples,
    topStatementDeltas: before.statementsByQuery && after.statementsByQuery ? statementDeltas(after.statementsByQuery, before.statementsByQuery) : null,
    walDelta: delta(after.wal, before.wal),
    databaseDelta: delta(after.database, before.database),
    pgStatStatementsAvailable: Boolean(before.statements && after.statements),
    pgStatStatementsError: after.statementsError,
    pgStatStatementsDelta: before.statements && after.statements ? delta(after.statements, before.statements) : null
  };
  console.log(JSON.stringify(report));
  if (errors > 0) throw new Error("financial profile had " + errors + " failed lifecycles");
}

const configuredDurationMs = Number.parseInt(process.env.FINANCIAL_PROFILE_DURATION_MS ?? "60000", 10);
if (!Number.isInteger(configuredDurationMs) || configuredDurationMs < 10000 || configuredDurationMs > 300000) {
  throw new Error("FINANCIAL_PROFILE_DURATION_MS must be an integer between 10000 and 300000");
}

try {
  const environment = await monitorPool.query(
    "SELECT version() AS version, current_setting('shared_buffers') AS shared_buffers, " +
    "current_setting('max_connections') AS max_connections"
  );
  console.log(JSON.stringify({ profile: "financial lifecycle lock/WAL/queryid profile", durationMs: configuredDurationMs, environment: environment.rows[0] }));
  await profilePhase(10, configuredDurationMs);
  await profilePhase(50, configuredDurationMs);
} finally {
  await Promise.all([pool.end(), monitorPool.end()]);
}
