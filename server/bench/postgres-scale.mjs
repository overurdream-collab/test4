import { createHash, randomBytes, randomUUID } from "node:crypto";
import { Pool } from "pg";

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 60,
  idleTimeoutMillis: 10_000,
  connectionTimeoutMillis: 10_000
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

async function measure(label, concurrency, durationMs, task) {
  const latencies = [];
  let count = 0;
  let errors = 0;
  const deadline = Date.now() + durationMs;
  await Promise.all(Array.from({ length: concurrency }, async (_, worker) => {
    while (Date.now() < deadline) {
      const start = process.hrtime.bigint();
      try {
        await task(worker, count);
        count++;
      } catch (error) {
        errors++;
        if (errors <= 3) process.stderr.write(String(error) + "\n");
      } finally {
        latencies.push(Number(process.hrtime.bigint() - start) / 1_000_000);
      }
    }
  }));
  latencies.sort((a, b) => a - b);
  const result = {
    label,
    concurrency,
    durationMs,
    operations: count,
    errors,
    throughputPerSecond: Number((count / (durationMs / 1000)).toFixed(2)),
    latencyMs: {
      p50: percentile(latencies, 0.50),
      p95: percentile(latencies, 0.95),
      p99: percentile(latencies, 0.99)
    }
  };
  console.log(JSON.stringify(result));
  if (errors > 0) throw new Error(label + " benchmark had " + errors + " errors");
  return result;
}

const rels = Array.from({ length: 1000 }, (_, i) => ({
  id: uuidFromMd5("bench-rel-" + (i + 1)),
  actor: uuidFromMd5("bench-user-" + (i + 1) + "-1"),
  device: uuidFromMd5("bench-device-load-" + (i + 1))
}));

try {
  const env = await pool.query(
    "SELECT version() AS version, current_setting('shared_buffers') AS shared_buffers, " +
    "current_setting('max_connections') AS max_connections"
  );
  console.log(JSON.stringify({
    benchmark: "PostgreSQL relationship event feed and operation intake",
    seededOperations: 1_000_000,
    seededEvents: 1_000_000,
    seededRelationships: 1_000,
    database: env.rows[0]
  }));

  const explain = await pool.query(
    "EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) " +
    "SELECT server_sequence,event_id,operation_id,event_type,event_payload " +
    "FROM ledger.relationship_events WHERE relationship_id=$1::uuid " +
    "AND server_sequence > $2 ORDER BY server_sequence LIMIT 100",
    [rels[0].id, 500]
  );
  console.log("EVENT_FEED_EXPLAIN\n" + explain.rows.map(row => row["QUERY PLAN"]).join("\n"));

  for (const concurrency of [1, 10, 50]) {
    await measure("event_feed_read", concurrency, 5000, async (worker, index) => {
      const rel = rels[(worker * 37 + index) % rels.length];
      const cursor = 400 + ((index + worker) % 500);
      await pool.query(
        "SELECT server_sequence,event_id,operation_id,event_type,event_payload " +
        "FROM ledger.relationship_events WHERE relationship_id=$1::uuid " +
        "AND server_sequence > $2 ORDER BY server_sequence LIMIT 100",
        [rel.id, cursor]
      );
    });
  }

  for (const concurrency of [1, 10, 50]) {
    await measure("operation_intake_write", concurrency, 5000, async (worker) => {
      const rel = rels[(worker * 19 + Math.floor(Math.random() * rels.length)) % rels.length];
      await pool.query(
        "SELECT * FROM ledger.accept_operation(" +
        "$1::uuid,$2::uuid,$3::uuid,$4::uuid,'supply',$5::bytea,$6::jsonb,0,1,now())",
        [
          randomUUID(),
          rel.id,
          rel.actor,
          rel.device,
          randomBytes(32),
          JSON.stringify({ benchmark: true, currency: "YER", amountMinor: 1000 })
        ]
      );
    });
  }
} finally {
  await pool.end();
}
