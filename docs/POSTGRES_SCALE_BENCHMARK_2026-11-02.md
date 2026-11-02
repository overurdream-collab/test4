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
2. Event-feed p95 rises from 0.85 ms at one worker to 45.36 ms at 50 workers; throughput gains flatten.
3. Supply operation-intake p95 rises from 0.75 ms to 21.21 ms at 50 workers; write throughput is nearly flat between 10 and 50 workers.
4. The full financial lifecycle is the current bottleneck: p95 rises from 10.08 ms at one worker to 591.96 ms at 50, while throughput falls from 196.32 lifecycles/s at 10 workers to 128.74 at 50. This requires profiling and optimization before scaling concurrency.
5. The benchmark uses 1,000 relationships and evenly distributed synthetic traffic. It does not model one million users, skewed hot merchants, real API/TLS/auth overhead, mobile networks, attachments, backup traffic, or long-duration operation.
6. Each phase lasts only five seconds. Treat these as directional microbenchmarks, not service-level objectives or production capacity guarantees.

## Next performance work

- Run longer 60–300 second phases to expose steady-state behavior.
- Capture pg_stat_activity wait events, pg_locks, WAL bytes, active connections, CPU, memory, and cache hit ratio during financial lifecycle load.
- Compare evenly distributed traffic with hot-relationship skew and simultaneous approvals against the same obligation/payment.
- Profile journal triggers and account upsert contention; optimize only after identifying measured bottlenecks.
- Add attachment and backup/restore load only after those components exist.
- Derive capacity targets after confirming DAU, transactions per user, peak sync bursts, and attachment volumes.

No production database or paid infrastructure was used.


## Financial lifecycle profiling — PR #14, Run #19

**Workflow:** https://github.com/overurdream-collab/test4/actions/runs/41365278492  
**Result:** Success. PostgreSQL 16.15, disposable GitHub-hosted CI database, same 1,000-relationship / 1M-operation / 1M-event seed.

The profiling runner completed both 10-second phases with zero lifecycle errors:

| Workers | Completed lifecycles | Throughput/s | Full lifecycle p50 | p95 | p99 |
|---:|---:|---:|---:|---:|---:|
| 10 | 1,051 | 104.01 | 93.66 ms | 124.73 ms | 169.77 ms |
| 50 | 841 | 80.01 | 608.87 ms | 817.83 ms | 1,005.62 ms |

The profiler adds sampling and measures a longer end-to-end path than the five-second benchmark, so do not compare these figures as if they were the same instrument. They independently confirm saturation at 50 workers.

At 50 workers, the slowest measured approval/posting stage was allocation approval/posting (p50 253.81 ms, p95 362.47 ms); credit-charge and payment approval/posting p95 were 227.02 ms and 218.91 ms. The profiler sampled CPU/running most often, with additional WALWrite/WALSync, Lock/extend, LockManager, WALInsert, and buffer waits. It recorded no deadlocks. These are sampled observations, not a complete wait-time attribution.

At 10 workers, allocation approval/posting p95 was 52.30 ms; at 50 it rose to 362.47 ms. The allocation path performs aggregate sums over allocations. The existing indexes are composite and begin with `relationship_id`, while the two aggregate predicates in `allocate_payment` and `assert_allocation_within_bounds` previously filtered only by payment_id or obligation_id. This prevented the intended leading index key from being used and could force broad scans as the table grows.

### Optimization added after Run #19

Migration `006_scope_allocation_aggregates.sql` adds `relationship_id` to both payment- and obligation-allocation aggregate predicates in both functions, matching the existing composite indexes:
- `allocations_by_payment_idx (relationship_id, payment_id)`
- `allocations_by_obligation_idx (relationship_id, obligation_id)`

This is a targeted query/index alignment fix. PostgreSQL invariant tests, including a re-run of the obligations/allocation suite after migration 006, passed in Run #66: https://github.com/overurdream-collab/test4/actions/runs/41365623554. API checks passed in Run #38: https://github.com/overurdream-collab/test4/actions/runs/41365623593. The post-change million-event + lifecycle profile is still running as Run #23: https://github.com/overurdream-collab/test4/actions/runs/41365623559. No performance improvement is claimed until that run completes and its results are compared.
