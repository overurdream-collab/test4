# تحليل أداء PostgreSQL — 2026-11-02

## الحالة التنفيذية

هذا التقرير يسجل التشخيص الأولي لاختناق دورة الترحيل المالي عند 50 عاملاً. **لا يعلن سعة تشغيلية ولا يثبت سببًا جذريًا وحيدًا**. القياسات السابقة على PostgreSQL 16 في GitHub Actions أظهرت هبوط throughput للدورة المالية من نحو 196 lifecycle/s عند 10 عمال إلى نحو 129 عند 50، وارتفاع p95 من نحو 68ms إلى نحو 592ms. تكرارات القياس اختلفت، لذلك لا تُعامل هذه الأرقام كـSLO أو قدرة إنتاجية.

## الأدلة الحالية مقابل الفرضيات

| المرشح | ما نعرفه | الحكم الحالي |
|---|---|---|
| أقفال حسابات الأطراف | ظهرت عينات Lock/extend وLockManager؛ مرحلة allocation approval/posting كانت الأبطأ في profile سابق | مساهم محتمل؛ لا توجد attribution كافية إلى صفوف الحسابات تحديدًا |
| relationship counters | كل عملية مقبولة تخصص sequence داخل العلاقة | نقطة تسلسل محتملة؛ لم تُقَس منفصلة بعد |
| محفزات journal | اعتماد الدين والدفعة والتخصيص يرحّل آثارًا مالية داخل المعاملة | جزء من المسار الحرج؛ زمن كل trigger غير معزول بعد |
| WAL | ظهرت WALWrite/WALSync/WALInsert waits في عينات سابقة | نشاط/انتظار مؤكد في العينات، لكن ليس دليلًا أنه العامل الغالب |

## القياس المطلوب في التشغيل instrumented

يجب جمع عينات متزامنة مع حمل دورة مالية عند 10 و50 عاملاً:

- `pg_stat_activity`: الحالة، wait_event_type، wait_event، عمر أطول استعلام.
- `pg_locks`: نوع القفل ووضعه وهل هو ممنوح.
- `pg_stat_wal`: deltas لسجلات WAL والبايتات وfull buffers.
- `pg_stat_statements`: calls، total execution time، shared block hits/reads، temp writes.
- قياسات latency لكل مرحلة: accept، approval/posting، lookup، allocation.

تم تحديث workflow ليبدأ PostgreSQL مع `shared_preload_libraries=pg_stat_statements` ثم ينشئ الامتداد صراحةً؛ غياب الامتداد يجب أن يفشل كقيد قياس أو يظهر بوضوح، ولا يجوز تحويله إلى تكلفة صفرية.

## معيار تحديد السبب

لا ينسب الاختناق إلى أحد المرشحين إلا إذا تزامن ارتفاعه مع تدهور المرحلة المتأثرة وتكرر في تشغيلات قابلة للمقارنة. يجب فصل:
1. lock wait time عن CPU/running.
2. تسلسل relationship sequence عن أقفال حسابات الأطراف.
3. تكلفة trigger/journal عن زمن UPDATE/INSERT الأساسي.
4. WAL generation عن WAL flush waits.

## ما لم يثبت بعد

- لا يوجد حتى الآن artifact instrumented مكتمل تمت مراجعته في هذا التقرير.
- لا يوجد إثبات أن 50 عاملاً سعة مدعومة.
- لا يوجد تحسين أداء مثبت التكرار بعد تعديل allocation query scoping.
- لا تُجرى أي تغييرات على قاعدة إنتاجية أو موارد مدفوعة.

## الخطوة التالية

تشغيل benchmark instrumented بعد نجاح CI، حفظ artifact JSON، ومقارنة دلائل 10/50 عاملاً. بعدها فقط يُحدّث هذا التقرير باستنتاج مدعوم أو يعلن أن الأدلة غير كافية.


## نتائج التشغيل instrumented — Run #39

- GitHub Actions: PostgreSQL million-event scale benchmark Run #39، ID `41471230009`، النتيجة `success`.
- PostgreSQL 16 بدأ مع `shared_preload_libraries=pg_stat_statements`، وتم تنفيذ `CREATE EXTENSION` بنجاح؛ الحقل `pgStatStatementsAvailable=true`.
- المقارنة في نفس تشغيل CI، مدة profile تقارب 10 ثوانٍ لكل مستوى:

| القياس | 10 عمال | 50 عاملًا |
|---|---:|---:|
| الدورات المالية المكتملة | 3,833 | 3,505 |
| throughput (lifecycle/s) | 380.64 | 341.09 |
| p50 للدورة (ms) | 25.49 | 140.11 |
| p95 للدورة (ms) | 32.61 | 187.41 |
| p99 للدورة (ms) | 38.47 | 304.10 |
| WAL bytes | 66,903,300 | 208,658,918 |
| sampled WALWrite (LWLock + IO) | 111 + 0 | 389 + 2 |
| sampled WALInsert | 0 | 77 |
| sampled CPU/running | 40 | 187 |
| sampled LockManager | 2 | 0 |
| pg_stat_statements total execution time (ms) | 26,879.75 | 124,505.60 |
| deadlocks | 0 | 0 |

### قراءة النتائج

1. **WAL contention هو أقوى إشارة قياس حالية عند 50 عاملًا**: WALWrite samples ارتفعت من 111 إلى 391، وظهرت 77 عينة WALInsert، كما ارتفع WAL volume من 66.9MB إلى 208.7MB رغم انخفاض عدد الدورات المكتملة. WAL لكل دورة ارتفع تقريبًا من 17.5KB إلى 59.5KB (نحو 3.4×).
2. **CPU/running ارتفع بوضوح أيضًا** (40 إلى 187 عينة)، لذلك النتيجة لا تثبت أن WAL هو العامل الوحيد؛ هناك منافسة موارد/تزامن مصاحبة.
3. **أقفال الحسابات/LockManager ليست مدعومة كسبب غالب في هذه العينة**: ظهر LockManager مرتين عند 10 عمال ولم يظهر عند 50، ولم تُسجل عينات lock غير ممنوحة في الملخص. لكن القياس الحالي لا يسجل مدة انتظار كل صف حساب على حدة، فلا ينفي كل contention على مستوى الصفوف.
4. **relationship sequence counters**: عينات advisory exclusive locks موجودة (59 عند 10 مقابل 242 عند 50)، لكنها granted؛ لا نملك قياسًا يثبت أنها كانت تنتظر أو أنها سبب هبوط throughput.
5. **journal triggers**: جزء من المراحل البطيئة. عند 50 عاملًا كانت p95 لمرحلة approve_allocation_and_post هي 57.94ms، وapprove_credit_charge_and_post 45.09ms، وapprove_payment_and_post 45.84ms. لا توجد حتى الآن attribution مستقلة لتكلفة trigger مقابل باقي SQL في المعاملة.
6. `pg_stat_statements` أكد زيادة aggregate execution time من 26.9s إلى 124.5s، لكنه يجمع الاستعلامات كلها ولا يحدد وحده trigger أو statement بعينه.

### الاستنتاج المنضبط

**السبب الأرجح المدعوم حاليًا هو ضغط WAL (WALWrite/WALInsert) مع زيادة CPU/running تحت التزامن، وليس أقفال حسابات الأطراف أو relationship counter المثبتة كسبب وحيد.** الثقة متوسطة إلى منخفضة لأن كل مستوى قيس في profile قصير واحد على runner مشترك، وعدادات العينات ليست مدد انتظار. لا نعلن سعة 50 عاملًا. يلزم تكرار 60–300 ثانية على ظروف ثابتة، وقياس hot-relationship skew، وpg_stat_statements حسب queryid، وفصل زمن journal triggers/SQL قبل قرار تحسين بنيوي.
