import { createHash, randomBytes, randomUUID } from "node:crypto";
import { appendFile, writeFile } from "node:fs/promises";
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
  max: 2,
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

const seed = process.env.BENCH_SEED ?? "ledger-soak-seed-2026-11-02";
const hotRelationshipShare = Number(process.env.HOT_RELATIONSHIP_SHARE ?? "0.8");
if (!(hotRelationshipShare >= 0 && hotRelationshipShare <= 1)) throw new Error("HOT_RELATIONSHIP_SHARE must be between 0 and 1");
const rels = Array.from({ length: 1000 }, (_, i) => ({
  id: uuidFromMd5(seed + "-bench-rel-" + (i + 1)),
  seller: uuidFromMd5(seed + "-bench-user-" + (i + 1) + "-1"),
  buyer: uuidFromMd5(seed + "-bench-user-" + (i + 1) + "-2"),
  device: uuidFromMd5(seed + "-bench-device-profile-" + (i + 1))
}));
const hotRelationship = rels[0];
const reportPath = process.env.BENCH_REPORT_PATH ?? "bench/financial-soak-results.jsonl";
await writeFile(reportPath, "");

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

async function snapshot() {
  const [wal, database] = await Promise.all([
    monitorPool.query("SELECT wal_records, wal_fpi, wal_bytes, wal_buffers_full FROM pg_stat_wal"),
    monitorPool.query("SELECT xact_commit, blks_hit, blks_read, tup_inserted, tup_updated, deadlocks, temp_bytes FROM pg_stat_database WHERE datname=current_database()")
  ]);
  let statements = null;
  let statementsError = null;
  try {
    const result = await monitorPool.query("SELECT COALESCE(sum(calls),0)::bigint AS calls, COALESCE(sum(total_exec_time),0)::numeric AS total_exec_time_ms, COALESCE(sum(shared_blks_hit),0)::bigint AS shared_blks_hit, COALESCE(sum(shared_blks_read),0)::bigint AS shared_blks_read, COALESCE(sum(temp_blks_written),0)::bigint AS temp_blks_written FROM pg_stat_statements");
    statements = result.rows[0];
  } catch (error) {
    statementsError = String(error);
  }
  return { wal: wal.rows[0], database: database.rows[0], statements, statementsError };
}

async function profilePhase(concurrency, durationMs, repeat) {
  for (const key of Object.keys(stageSamples)) delete stageSamples[key];
  const waitSamples = Object.create(null);
  const lockSamples = Object.create(null);
  const activitySamples = [];
  const before = await snapshot();
  let stopMonitor = false;

  const monitor = (async () => {
    while (!stopMonitor) {
      try {
        const [waits, locks, activity] = await Promise.all([
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
          )
        ]);
        for (const row of waits.rows) {
          const key = [row.wait_type, row.wait_event, row.state].join("|");
          waitSamples[key] = (waitSamples[key] ?? 0) + row.sessions;
        }
        for (const row of locks.rows) {
          const key = [row.locktype, row.mode, row.granted].join("|");
          lockSamples[key] = (lockSamples[key] ?? 0) + row.lock_count;
        }
        activitySamples.push({ sampledAt: new Date().toISOString(), groups: activity.rows });
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
      const sample = localIndex++;
      const rel = (sample % 10) < hotRelationshipShare * 10
        ? hotRelationship
        : rels[1 + (sample % (rels.length - 1))];
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
    label: "financial_lifecycle_soak",
    seed,
    repeat,
    concurrency,
    hotRelationshipId: hotRelationship.id,
    hotRelationshipShare,
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
    walDelta: delta(after.wal, before.wal),
    databaseDelta: delta(after.database, before.database),
    pgStatStatementsAvailable: Boolean(before.statements && after.statements),
    pgStatStatementsError: after.statementsError,
    pgStatStatementsDelta: before.statements && after.statements ? delta(after.statements, before.statements) : null
  };
  const serialized = JSON.stringify(report);
  console.log(serialized);
  await appendFile(reportPath, serialized + "\\n");
  if (errors > 0) throw new Error("financial profile had " + errors + " failed lifecycles");
}

try {
  const environment = await monitorPool.query(
    "SELECT version() AS version, current_setting('shared_buffers') AS shared_buffers, " +
    "current_setting('max_connections') AS max_connections"
  );
  console.log(JSON.stringify({
    profile: "financial lifecycle hot-relationship soak",
    seed, hotRelationshipShare, hotRelationshipId: hotRelationship.id,
    environment: environment.rows[0]
  }));
  const concurrency = Number(process.env.SOAK_CONCURRENCY ?? "50");
  const repeats = Number(process.env.SOAK_REPEATS ?? "3");
  const durations = (process.env.SOAK_DURATIONS_SECONDS ?? "60,300")
    .split(",").map(value => Number(value.trim()) * 1000);
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 50) throw new Error("SOAK_CONCURRENCY must be 1..50");
  if (!Number.isInteger(repeats) || repeats < 3) throw new Error("SOAK_REPEATS must be at least 3");
  if (durations.some(value => !Number.isInteger(value) || value < 1000)) throw new Error("Invalid SOAK_DURATIONS_SECONDS");
  for (const durationMs of durations) {
    for (let repeat = 1; repeat <= repeats; repeat++) {
      await profilePhase(concurrency, durationMs, repeat);
    }
  }
} finally {
  await Promise.all([pool.end(), monitorPool.end()]);
}
