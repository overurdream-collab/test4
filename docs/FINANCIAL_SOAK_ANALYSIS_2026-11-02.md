# Financial lifecycle soak: before/after analysis — 2026-11-02

## Decision
PR #42 is **not merged**. All 12 post-change matrix jobs and all three other CI checks passed, but the performance acceptance criterion did not. Do not describe hot-relationship contention as fixed or claim validated 50-worker production capacity.

## Test design
- PostgreSQL 16, 50 concurrent workers.
- Same deterministic seed: `mcias-ledger-soak-2026-11-02-v1`.
- 1,000 relationships; hot scenario targets 90% of attempts to one relationship.
- Uniform and hot scenarios, 60s and 300s, three independent fresh-database repetitions per cell.
- Captures pg_stat_activity, wait events and query text/query IDs, pg_locks, pg_stat_wal, pg_stat_database, pg_stat_statements, lifecycle/stage p50/p95/p99, deadlocks and errors.

## Before (baseline)
- Hot 60s: 108–130 lifecycles/s; p95 798–889 ms.
- Uniform 60s: 194–251 lifecycles/s; p95 421–484 ms.
- Hot 300s: 79–95 lifecycles/s; p95 1,170–1,360 ms.
- Uniform 300s: 116–119 lifecycles/s; p95 688–2,050 ms (high variability).

## After (migration 012), all repetitions

| Scenario | Repeat | Duration | Lifecycles/s | p50 ms | p95 ms | p99 ms | Errors | Deadlocks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Hot | 1 | 60s | 112.368 | 416.32 | 910.45 | 1229.82 | 0 | 0 |
| Hot | 2 | 60s | 117.686 | 399.32 | 859.47 | 1118.35 | 0 | 0 |
| Hot | 3 | 60s | 123.331 | 387.60 | 814.90 | 1036.60 | 0 | 0 |
| Uniform | 1 | 60s | 241.839 | 186.78 | 368.86 | 541.30 | 0 | 0 |
| Uniform | 2 | 60s | 227.153 | 197.29 | 400.50 | 546.20 | 0 | 0 |
| Uniform | 3 | 60s | 198.463 | 233.16 | 404.63 | 618.70 | 0 | 0 |
| Hot | 1 | 300s | 81.454 | 568.56 | 1308.54 | 1738.33 | 0 | 0 |
| Hot | 2 | 300s | 80.941 | 571.03 | 1315.36 | 1727.53 | 0 | 0 |
| Hot | 3 | 300s | 81.854 | 570.01 | 1299.78 | 1674.80 | 0 | 0 |
| Uniform | 1 | 300s | 120.677 | 245.12 | 2118.24 | 2495.69 | 0 | 0 |
| Uniform | 2 | 300s | 104.043 | 327.21 | 2017.59 | 3397.42 | 0 | 0 |
| Uniform | 3 | 300s | 110.252 | 298.66 | 2182.84 | 2872.03 | 0 | 0 |

## Diagnosis
The 90% hot-share target was achieved (observed 89.96–90.12%). Hot runs still show very high transactionid and LockManager wait samples. Query-attributed waits repeatedly point to the top-level calls:
- `SELECT * FROM ledger.accept_operation(...)`
- `SELECT ledger.decide_operation(...)`

For hot 300s repeat 1, samples include 10,704 transactionid waits in `accept_operation` and 10,755 in `decide_operation`; repeat 2 includes 11,156 and 11,214 respectively. The same pattern persists after migration 012.

The measured contention was **not removed** by moving the operation insert ahead of sequence allocation and optimizing the counter update. Top-level query attribution does not identify the exact internal row/trigger responsible, so the next change must not guess.

Uniform 300s runs also show high WALWrite/WALSync and CPU/running pressure, with p95 around 2.0–2.2 seconds. This broad-load signal is distinct from the hot-relationship bottleneck.

## Change and safety
Migration 012 and its regression test are on the PR branch only. The migration preserves `sales_return` introduced by migration 009. Migration/test CI and existing Approval API, PostgreSQL tests and million-event benchmark passed on head `1b20ba1dea908e3725a7b3fc0c60865f4f3099ac`.

No production database was modified and no deployment occurred. PR #42 remains open and unmerged.

## Required next investigation
1. Instrument internal SQL phases separately inside `accept_operation` and `decide_operation` (counter allocation, operation row, relationship event, approval transition, journal posting/triggers).
2. Capture blocker PID / blocked PID and `pg_blocking_pids()` with relation and tuple identity where available; query-level aggregation is insufficient to prove the exact row.
3. Isolate the lock common to the hot relationship during acceptance and decision. Do not change journal, counters, or approval semantics without proof.
4. Implement one targeted fix only after attribution, then rerun the full 12-cell matrix on the same seed. Acceptance requires three consecutive hot repetitions at both durations to beat baseline without regressions, retaining every result.

## Workflow proof
- Financial soak: run 41480600293 — 12/12 matrix jobs successful.
- Approval API: run 41480600290 — success.
- PostgreSQL million-event benchmark: run 41480600172 — success.
- Ledger PostgreSQL tests: run 41480600450 — success.
- PR: https://github.com/overurdream-collab/test4/pull/42 (open, not merged).


---

## استكمال التحقق الكامل للمخطط — 2026-11-02 (Runs 41495182602 / 41495182632)

### تصحيح مهم لطريقة المقارنة
القياسات القديمة في قسم "Before" أعلاه لا تمثل baseline موثوقًا للمخطط الكامل؛ workflow القديم لم يطبق migrations 007–011. لذلك لا تستخدمها لإثبات تحسن أو تراجع بعد الإصلاح. أُضيف workflow مستقل يعيد بناء المخطط الكامل حتى migration 012 (قبل migration 013) ثم يقارن تشغيل hot بنفس seed والعمال والمدد.

### سبب deadlocks المثبت في baseline الكامل قبل 013
في migration 011 كانت دالة `ledger.require_two_active_members_for_operations()` تقفل صف العلاقة بـ `FOR UPDATE` عند كل INSERT للعملية. كما كانت حارسا التصفير وتعيين دورة الحساب يستخدمان قفلًا حصريًا. في baseline الكامل قبل 013، أظهر القياس أن التعارض على tuple في `ledger.relationships` نتج عنه deadlocks كثيفة:
- 60 ثانية، التكرارات 1/2/3: deadlocks = 406 / 442 / 448؛ أخطاء = 503 / 519 / 534.
- 300 ثانية، التكرارات 1/2/3: deadlocks = 1,570 / 1,218 / 950؛ أخطاء = 1,995 / 1,645 / 1,399.
- throughput المبلغ عنه منخفض جدًا (0.483–0.841 lifecycle/s) وp95 بين 15,176 و16,073 ms، بسبب فشل المعاملات والانتظار؛ هذه ليست baseline إنتاجية سليمة بل قياس فشل متزامن.
- blocker samples تشير مباشرة إلى `ledger.relationships` مع `AccessExclusiveLock` في طلبات `accept_operation` المتزامنة.

### الإصلاح الجزئي المثبت في migration 013
تم تحويل أقفال القراءة في الدوال الثلاث إلى `FOR SHARE`:
- `guard_operation_during_settlement_reset`
- `assign_current_account_cycle`
- `require_two_active_members_for_operations`

يبقى مسار طلب/اعتماد التصفير يستخدم القفل الحصري، لذلك يظل متسلسلًا مع العمليات النشطة ويحمي حد الدورة. اختبار migration 014 يتحقق من تعريف الدوال وبقاء triggers الثلاثة مفعّلة.

### نتائج post-fix — المخطط الكامل، seed موحد، 50 عاملًا
Run **41495182632**: 12/12 jobs ناجحة. Run **41495182556** (PostgreSQL tests)، **41495182777** (Approval API)، و**41495182784** (million-event benchmark): جميعها success.

| السيناريو | التكرار | المدة | lifecycle/s | p50 ms | p95 ms | p99 ms | الأخطاء | deadlocks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Hot | 1 | 60s | 100.490 | 456.40 | 1063.37 | 1430.83 | 0 | 0 |
| Hot | 2 | 60s | 118.318 | 400.07 | 850.41 | 1177.58 | 0 | 0 |
| Hot | 3 | 60s | 108.712 | 425.81 | 930.88 | 1438.47 | 0 | 0 |
| Uniform | 1 | 60s | 185.960 | 225.58 | 545.78 | 681.10 | 0 | 0 |
| Uniform | 2 | 60s | 189.446 | 233.34 | 524.43 | 676.77 | 0 | 0 |
| Uniform | 3 | 60s | 205.919 | 212.11 | 476.06 | 641.31 | 0 | 0 |
| Hot | 1 | 300s | 69.173 | 667.02 | 1551.17 | 2050.06 | 0 | 0 |
| Hot | 2 | 300s | 102.182 | 437.80 | 1098.23 | 1481.38 | 0 | 0 |
| Hot | 3 | 300s | 68.300 | 680.56 | 1557.22 | 2059.42 | 0 | 0 |
| Uniform | 1 | 300s | 124.683 | 234.69 | 2196.07 | 2669.01 | 0 | 0 |
| Uniform | 2 | 300s | 114.981 | 361.16 | 694.13 | 3367.96 | 0 | 0 |
| Uniform | 3 | 300s | 105.393 | 327.53 | 1306.28 | 3436.67 | 0 | 0 |

Observed hot share: 90.02–90.10%. جميع تشغيلات post-fix بلا أخطاء أو deadlocks.

### ما لم يُحل بعد — bottleneck التالي مثبت
رغم اختفاء deadlocks الناتجة عن قفل صف العلاقة، لا تزال عينات الحجب في hot 300s تُظهر:
- `locktype=tuple`, `relation=ledger.relationship_sync_counters`.
- المتنافسون هم `accept_operation` و`decide_operation`.
- `decide_operation` يحدّث `operations`، وtrigger `append_operation_state_event` يستدعي `next_relationship_sequence` ثانية لإصدار event. لذلك القبول والقرار يتنافسان على عدّاد العلاقة نفسه.
- hot 300s p95 بعد الإصلاح: 1098.23–1557.22 ms؛ التكرارات متذبذبة، ولا تحقق معيار تحسن متكرر مثبت.
- median hot 60s p95 = 930.88 ms، median hot 300s p95 = 1551.17 ms. لا يجوز الادعاء أن مشكلة الأداء حُلّت.

### قرار الاستئناف
1. migration 013 حلّت مشكلة deadlock في الحراس الثلاثة، وهذا مثبت عبر 3 تكرارات لكل مدة.
2. لا نغيّر migration 012 أو معنى `server_sequence` قبل فحص جميع مستهلكي cursor/sequence واختبارات offline sync؛ العداد الصفّي هو نقطة التسلسل التي تضمن ترتيب أحداث العلاقة.
3. التحقيق التالي يجب أن يختبر بدائل تحافظ على cursor semantics: PostgreSQL sequence عالمي/مخصص، أو range leasing مع ضمانات واضحة، أو فصل stream sequence عن event insertion. لا يعتمد أي بديل قبل اختبارات الترتيب، rollback gaps، concurrent accept/approve، وإعادة المزامنة.
4. لا دمج PR ولا نشر إنتاجي. PR #42 يبقى مفتوحًا.

### Workflow evidence
- Post-fix full matrix: https://github.com/overurdream-collab/test4/actions/runs/41495182632 — success, 12/12.
- Full-schema pre-013 diagnostic baseline: https://github.com/overurdream-collab/test4/actions/runs/41495182602 — expected failures captured (all 6 jobs); demonstrates relationship-row deadlocks.
- PostgreSQL: https://github.com/overurdream-collab/test4/actions/runs/41495182556 — success.
- Approval API: https://github.com/overurdream-collab/test4/actions/runs/41495182777 — success.
- Million-event benchmark: https://github.com/overurdream-collab/test4/actions/runs/41495182784 — success.
- Branch head before this documentation update: `dd319834c3fcc70752f82b94fcf9c99e86f0abcd`.
