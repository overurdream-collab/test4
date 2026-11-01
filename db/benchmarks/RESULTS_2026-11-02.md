# PostgreSQL scale benchmark — 2026-11-02

**Workflow:** [GitHub Actions Run #3](https://github.com/overurdream-collab/test4/actions/runs/41362226286)  
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
| 1 | 1,509.80 | 0.62 | 0.83 | 1.05 |
| 10 | 1,764.24 | 4.96 | 9.86 | 11.57 |
| 50 | 1,924.58 | 23.53 | 42.41 | 56.02 |

## Operation intake write

Each request calls ledger.accept_operation for a synthetic supply event. This measures inbox persistence and event append; it does **not** include journal materialization for an approved credit charge/payment/allocation.

| Concurrent workers | Throughput (operations/s) | p50 (ms) | p95 (ms) | p99 (ms) |
|---:|---:|---:|---:|---:|
| 1 | 1,387.05 | 0.62 | 0.83 | 1.40 |
| 10 | 4,213.42 | 2.23 | 3.54 | 4.45 |
| 50 | 4,032.73 | 11.32 | 20.74 | 26.82 |

## Query plan evidence

The event-feed query used relationship_events_sync_idx with an index scan. For the measured page of 100 rows:

- Execution time: 0.812 ms.
- Planning time: 0.675 ms.
- Shared buffers: 103 read, 31 dirtied.
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

No production database or paid infrastructure was used.
