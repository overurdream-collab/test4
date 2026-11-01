# PostgreSQL scale benchmark — 2026-11-02

**Workflow:** [GitHub Actions Run #9](https://github.com/overurdream-collab/test4/actions/runs/41362600710)  
**Result:** Success  
**Database:** PostgreSQL 16.15  
**Runner:** 4 vCPU, 15 GiB RAM  
**PostgreSQL settings observed:** shared_buffers=128MB, max_connections=100

## Dataset

- 1,000 synthetic commercial relationships.
- 1,000,000 operation rows.
- 1,000,000 ordered relationship events.
- 1,000 events per relationship.
- No customer data; disposable CI database.

## Event-feed read

Each request reads up to 100 events for one relationship using a cursor.

| Concurrent workers | Throughput (requests/s) | p50 (ms) | p95 (ms) | p99 (ms) |
|---:|---:|---:|---:|---:|
| 1 | 1,426.83 | 0.66 | 0.85 | 1.18 |
| 10 | 1,702.16 | 5.07 | 10.28 | 12.64 |
| 50 | 1,850.36 | 23.35 | 45.36 | 62.56 |

## Operation intake write

Each request calls ledger.accept_operation for a synthetic supply event. This measures inbox persistence and event append, not journal materialization.

| Concurrent workers | Throughput (operations/s) | p50 (ms) | p95 (ms) | p99 (ms) |
|---:|---:|---:|---:|---:|
| 1 | 1,415.83 | 0.63 | 0.75 | 1.10 |
| 10 | 4,052.21 | 2.30 | 3.83 | 5.18 |
| 50 | 3,905.59 | 11.88 | 21.21 | 27.20 |

## Approved financial lifecycle and journal posting

Each measured lifecycle creates and approves one credit charge, one payment, and one allocation, then verifies the generated obligation/payment IDs. This exercises the approval trigger and journal materialization paths.

| Concurrent workers | Throughput (complete lifecycles/s) | p50 (ms) | p95 (ms) | p99 (ms) |
|---:|---:|---:|---:|---:|
| 1 | 116.46 | 7.82 | 10.08 | 12.74 |
| 10 | 196.32 | 49.74 | 67.55 | 94.15 |
| 50 | 128.74 | 365.76 | 591.96 | 866.94 |

At 50 concurrent financial lifecycles, throughput fell below the 10-worker result while p95 rose to about 592 ms. Treat this as a saturation warning, not a capacity target. Profiling and optimization are required before increasing concurrency.

## Query plan evidence

The event-feed query used relationship_events_sync_idx with an index scan. For the measured page of 100 rows:

- Execution time: 0.712 ms.
- Planning time: 0.578 ms.
- Shared buffers: 103 read, 29 dirtied.
- Plan: Limit -> Index Scan using relationship_events_sync_idx.

The full EXPLAIN ANALYZE output is retained in the linked workflow logs.

## Interpretation — do not overclaim

1. The relationship-scoped event index performs well on this synthetic 1M-event dataset on the stated CI runner.
2. Read p95 rises from 0.83 ms at one worker to 42.41 ms at 50 workers; throughput gains flatten. This indicates contention/saturation as concurrency increases and warrants a longer profile.
3. Operation-intake write throughput rises from one to ten workers, then is nearly flat at 50 while latency rises. Investigate counter-row locks, WAL, connection pool pressure, and CPU before scaling.
4. These figures are short 5-second phases, not a soak test. They do not include TLS, production authentication, API process overhead, mobile networks, attachments, backups, financial approval posting, or physical devices.
5. This benchmark is not evidence of one million concurrent users. It only measures one database path at one million stored operation/event rows.

## Next performance work

- Add a separate benchmark for approval plus financial materialization and journal postings.
- Run longer 60–300 second phases and include concurrency 100 only after connection-pool and DB wait metrics are captured.
- Record CPU, WAL bytes, lock waits, active connections, cache hit ratio, and memory during the run.
- Benchmark skewed hot relationships as well as evenly distributed relationships.
- Derive capacity targets only after the user confirms DAU, transactions per user, peak sync bursts, and attachment volumes.

The earlier Run #3 was a baseline without the financial lifecycle phase; Run #9 supersedes its read/intake figures and adds the financial lifecycle measurement.

No production database or paid infrastructure was used.
