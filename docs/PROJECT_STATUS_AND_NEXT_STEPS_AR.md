# حالة المشروع وخطة العمل — دفتر الحسابات التجارية المشترك

**آخر تحديث:** 2026-11-02  
**المستودع:** https://github.com/overurdream-collab/test4  
**الفرع الأساسي:** main

## 1. الحالة التنفيذية المختصرة

المشروع في مرحلة تأسيس المتطلبات والتصميم، مع نموذج PostgreSQL أولي على فرع مستقل. لا يوجد تطبيق مستخدم أو API أو نشر إنتاجي حتى الآن.

| المجال | الحالة | الدليل/التوضيح |
|---|---|---|
| رؤية المنتج والقرارات الأساسية | موثقة | `docs/PROJECT_FOUNDATION.md` |
| متطلبات PRD الأصلي | جُمعت في وثيقة عربية | `docs/PRODUCT_REQUIREMENTS_AR.md` |
| ملف تسليم شامل | أُعد | `docs/MASTER_HANDOFF_AR.md` |
| مواصفات ledger/sync | موثقة كمقترح هندسي | `docs/LEDGER_AND_SYNC_SPEC.md` |
| PostgreSQL prototype | موجود على فرع | `prototype/postgres-journal-core` |
| SQL tests | موجودة على الفرع | لم يُثبت نجاح تشغيلها |
| PostgreSQL CI workflow | مدمج في main | `.github/workflows/ledger-db-tests.yml` |
| تطبيق Flutter | غير منفذ | — |
| API | غير منفذ | — |
| مزامنة فعلية بين جهازين | غير منفذة | — |
| لوحة الإدارة | غير منفذة | — |
| نشر/قاعدة إنتاجية | غير موجودة | لا موافقة على موارد مدفوعة |
| اختبارات حمل | غير منفذة | لا توجد افتراضات حمل متفق عليها |

## 2. GitHub

- Repository: `overurdream-collab/test4`
- Visibility عند آخر تحقق: Public.
- Default branch: `main`.
- صلاحيات GitHub connector عند آخر تحقق: admin/push متاحة.
- استخدم feature branches وPRs، ولا تكتب مباشرة إلى main.

### PRs المعروفة
- PR #1 — Project foundation: مدمج. Merge SHA المعروف: `5a2ebdc9d1e0cf5c668a6432569ba41b4d8218b7`.
- PR #2 — Ledger and sync specification: مدمج. راجع GitHub لاستخراج merge SHA الدقيق عند الحاجة.
- PR #4 — Enable PostgreSQL ledger validation workflow: مدمج. Merge SHA: `0e2f1241dad4374207fc15faa7d35c02e0c573e8`.
- PR #3 — Prototype PostgreSQL append-only ledger core: آخر حالة شوهدت مفتوح وغير مدمج، قابل للدمج. آخر head SHA معروف: `09bfdde94b0073e5176ee5c9ef5a46d79a773204`. تحقق مباشرة قبل أي إجراء.

**تحذير:** أداة جلب workflow runs لم تعرض Run ناجحًا مرتبطًا بآخر SHA للـ prototype. لا تكتب PASS ولا تدمج باعتبار الاختبارات ناجحة قبل تشغيلها فعليًا والتحقق من النتيجة.

## 3. الملفات المهمة

على main:
- `README.md`
- `docs/PROJECT_FOUNDATION.md`
- `docs/LEDGER_AND_SYNC_SPEC.md`
- `.github/workflows/ledger-db-tests.yml`

على فرع النموذج:
- `db/migrations/001_core_ledger.sql`
- `db/tests/001_core_ledger_test.sql`

أصبحت الملفات التالية موجودة على `main` بعد دمج PR #5:
- `docs/MASTER_HANDOFF_AR.md`
- `docs/PRODUCT_REQUIREMENTS_AR.md`
- `docs/PROJECT_STATUS_AND_NEXT_STEPS_AR.md`

## 4. الخطوة التالية ذات الأولوية

### P0 — إثبات PostgreSQL prototype
1. تحقق من workflow الموجود على main.
2. تحقق من PR #3 وفرعه.
3. شغّل PostgreSQL 16 محليًا أو في CI.
4. طبق migration.
5. نفذ SQL tests.
6. أصلح أي فشل وسجل SHA لكل إصلاح.
7. أضف اختبارات سلبية للقيود غير المتوازنة، وتعديل/حذف القيود، وخلط العملات والعلاقات، وتكرار operation ID.
8. لا تدمج قبل Run ناجح ومراجعة صحيحة لقواعد الدفتر.

### P1 — إكمال ERD والنموذج المالي
- users / devices / relationships / members / roles.
- business operations / approvals / disputes.
- obligations / payments / allocations.
- journal transactions / journal entries / accounts.
- reversals / adjustments / audit events.
- attachments metadata / idempotency records.
- device outbox / sync cursor.

يجب أن تمنع العلاقات المركبة cross-relationship references، وتُفرض حدود التخصيصات بمعاملة ذرية.

### P2 — API وعقود المعاملة
- identity/authentication.
- relationship membership and permissions.
- command endpoint with idempotency.
- approve/reject/dispute/adjust/reverse.
- cursor-based sync.
- audit and evidence access.
- typed conflict/error results.

### P3 — تطبيق Offline-First
- local encrypted SQLite.
- atomic local write + outbox.
- durable retry with same operation ID.
- visible sync state separate from approval state.
- conflict resolution workflow.
- two-device acceptance tests.

### P4 — الإكمال التدريجي
- attachments.
- account statements and reports.
- admin panel.
- controlled pilot.
- measured scale plan.

## 5. أدلة القبول الأساسية

لا يُعلن اكتمال النواة إلا إذا أثبتت:
- إنشاء دين دون إنترنت وحفظه بعد إعادة تشغيل التطبيق.
- مزامنة العملية مرة واحدة رغم إعادة المحاولة.
- وصولها للطرف الآخر كعملية معلقة.
- الموافقة تخضع لصلاحية الطرف الصحيح.
- الرصيد يتغير مرة واحدة فقط بعد الاعتماد.
- الدفعة لا تسدد دينًا إلا عبر تخصيص صريح/سياسة معتمدة.
- لا خلط بين العملات.
- العكس والتعديل لا يمحوان الأصل.
- لا وصول بين العلاقات.
- استعادة backup تطابق القيود والتدقيق.
- تدفق كامل بين جهازين دون اتصال ثم بعد عودة الشبكة.

## 6. سياسة التقرير اليومي / Worklog

كل عمل جوهري يوثق في GitHub:
- التاريخ.
- الهدف.
- الملفات المتغيرة.
- commit SHA.
- الاختبارات التي شغلت فعلًا وأوامرها.
- Run URL ونتيجة الفحوصات.
- ما فشل وكيف عولج.
- ما بقي.
- هل تم الدمج أم لا.

لا تكتب أن اختبارًا نجح لمجرد أن ملف الاختبار موجود أو أن workflow معرف.

## 7. سجل الحالة

### 2026-11-02
- مراجعة ملفات main والـ PR #3.
- مراجعة PRD 1.1 الأصلي (44 صفحة).
- تجميع القرارات الأحدث مع متطلبات المصدر وتحديد التعارضات.
- إعداد وثائق التسليم العربية لتسهيل نقل المشروع إلى وكيل آخر.
- لم يتم في هذه الخطوة تنفيذ كود أو تشغيل اختبار جديد.
