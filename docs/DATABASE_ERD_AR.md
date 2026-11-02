# مخطط قاعدة البيانات ERD — الدفتر التجاري المشترك

**الحالة:** مخطط as-built لـ ledger migrations 001–009 وidentity migration 010 وrelationship migration 011؛ لا يخلط الجداول المنفذة بالكيانات المستقبلية.  
**المراجعة:** 2026-11-02 | **قاعدة الاختبار:** PostgreSQL 16، CI Run #131.

> معرفات المستخدمين خارجية في هذه النسخة؛ لا يوجد جدول users ضمن schema ledger. الرسم يعرض الجداول الفعلية فقط.

## 1. مخطط ERD

```mermaid
erDiagram
 RELATIONSHIPS ||--o{ RELATIONSHIP_MEMBERS : members
 RELATIONSHIPS ||--o{ OPERATIONS : operations
 RELATIONSHIP_MEMBERS ||--o{ OPERATIONS : actor
 RELATIONSHIPS ||--o{ ACCOUNT_CYCLES : cycles
 RELATIONSHIPS ||--o{ ACCOUNTS : accounts
 RELATIONSHIP_MEMBERS ||--o{ ACCOUNTS : owner
 ACCOUNT_CYCLES ||--o{ OPERATIONS : cycle
 ACCOUNT_CYCLES ||--o{ JOURNAL_TRANSACTIONS : cycle
 ACCOUNT_CYCLES ||--o{ SETTLEMENT_REQUESTS : cycle
 RELATIONSHIPS o|--|| ACCOUNT_CYCLES : current_cycle
 OPERATIONS ||--o| JOURNAL_TRANSACTIONS : source
 JOURNAL_TRANSACTIONS ||--|{ JOURNAL_ENTRIES : entries
 ACCOUNTS ||--o{ JOURNAL_ENTRIES : posting
 RELATIONSHIPS ||--o{ APPROVALS : approvals_scope
 OPERATIONS ||--o{ APPROVALS : decisions
 RELATIONSHIP_MEMBERS ||--o{ APPROVALS : approver
 OPERATIONS ||--o| OBLIGATIONS : creates
 RELATIONSHIP_MEMBERS ||--o{ OBLIGATIONS : creditor
 RELATIONSHIP_MEMBERS ||--o{ OBLIGATIONS : debtor
 OPERATIONS ||--o| PAYMENTS : creates
 RELATIONSHIP_MEMBERS ||--o{ PAYMENTS : payer
 RELATIONSHIP_MEMBERS ||--o{ PAYMENTS : payee
 PAYMENTS ||--o{ ALLOCATIONS : allocated
 OBLIGATIONS ||--o{ ALLOCATIONS : settled
 OPERATIONS ||--o| ALLOCATIONS : allocation_source
 RELATIONSHIPS ||--|| RELATIONSHIP_SYNC_COUNTERS : counter
 RELATIONSHIPS ||--o{ RELATIONSHIP_EVENTS : events
 OPERATIONS o|--o{ RELATIONSHIP_EVENTS : event_subject
 RELATIONSHIPS ||--o{ SALES_RETURNS : returns
 OPERATIONS ||--o| SALES_RETURNS : source
 OBLIGATIONS ||--o{ SALES_RETURNS : original_obligation
 RELATIONSHIPS ||--o{ SETTLEMENT_REQUESTS : requests
 RELATIONSHIP_MEMBERS ||--o{ SETTLEMENT_REQUESTS : requester
 SETTLEMENT_REQUESTS ||--o| SETTLEMENT_DECISIONS : decision
 RELATIONSHIP_MEMBERS ||--o{ SETTLEMENT_DECISIONS : decider

 RELATIONSHIPS {
  uuid id PK
  text status
  timestamptz created_at
  uuid current_cycle_id FK
 }
 RELATIONSHIP_MEMBERS {
  uuid relationship_id PK,FK
  uuid user_id PK
  text role_label
  text status
  boolean can_approve
 }
 OPERATIONS {
  uuid operation_id PK
  uuid relationship_id FK
  uuid actor_user_id FK
  text operation_type
  bytea request_hash
  text business_state
  bigint base_version
  bigint server_version
  uuid cycle_id FK
  timestamptz created_at
 }
 APPROVALS {
  uuid id PK
  uuid relationship_id FK
  uuid operation_id FK
  uuid actor_user_id FK
  text decision
  bigint expected_server_version
  bigint resulting_server_version
  text reason
  timestamptz decided_at
 }
 OBLIGATIONS {
  uuid id PK
  uuid relationship_id FK
  uuid source_operation_id FK
  uuid creditor_user_id FK
  uuid debtor_user_id FK
  char currency
  bigint amount_minor
  text status
 }
 PAYMENTS {
  uuid id PK
  uuid relationship_id FK
  uuid source_operation_id FK
  uuid payer_user_id FK
  uuid payee_user_id FK
  char currency
  bigint amount_minor
  text status
 }
 ALLOCATIONS {
  uuid id PK
  uuid relationship_id FK
  uuid payment_id FK
  uuid obligation_id FK
  uuid source_operation_id FK
  char currency
  bigint amount_minor
 }
 ACCOUNTS {
  uuid id PK
  uuid relationship_id FK
  uuid owner_user_id FK
  text account_type
  char currency
 }
 JOURNAL_TRANSACTIONS {
  uuid id PK
  uuid relationship_id FK
  uuid source_operation_id FK
  char currency
  text description
  uuid cycle_id FK
  timestamptz posted_at
 }
 JOURNAL_ENTRIES {
  uuid id PK
  uuid journal_transaction_id FK
  uuid relationship_id FK
  char currency
  uuid account_id FK
  bigint debit_minor
  bigint credit_minor
 }
 RELATIONSHIP_SYNC_COUNTERS {
  uuid relationship_id PK,FK
  bigint last_sequence
 }
 RELATIONSHIP_EVENTS {
  uuid relationship_id PK,FK
  bigint server_sequence PK
  uuid event_id UK
  uuid operation_id FK
  text event_type
  jsonb event_payload
  timestamptz created_at
 }
 SALES_RETURNS {
  uuid id PK
  uuid relationship_id FK
  uuid source_operation_id FK,UK
  uuid original_obligation_id FK
  char currency
  bigint amount_minor
  text reason
  timestamptz created_at
 }
 SETTLEMENT_REQUESTS {
  uuid id PK
  uuid relationship_id FK
  uuid requested_by_user_id FK
  text status
  uuid cycle_id FK
  timestamptz requested_at
 }
 SETTLEMENT_DECISIONS {
  uuid idempotency_key PK
  uuid request_id FK,UK
  uuid relationship_id FK
  uuid actor_user_id FK
  text decision
  text reason
  timestamptz decided_at
 }
 ACCOUNT_CYCLES {
  uuid id PK
  uuid relationship_id FK
  bigint cycle_number
  text title
  text status
  timestamptz started_at
  timestamptz ended_at
  uuid created_by_reset_request_id
 }
```

## 2. مسؤولية الجداول

| الجدول | المسؤولية |
|---|---|
| relationships | العلاقة التجارية ومؤشر الدورة الحالية |
| relationship_members | عضوية العلاقة والدور وصلاحية الاعتماد |
| operations | أوامر الأعمال وحالتها وإصداراتها ودورتها |
| approvals | قرارات اعتماد/رفض العمليات |
| obligations | أصل المستحق والدائن والمدين |
| payments | الدفعات المسجلة |
| allocations | تخصيص دفعة إلى التزام |
| accounts | حسابات الأستاذ المساعدة لكل طرف/نوع/عملة |
| journal_transactions | رأس القيد ومصدره |
| journal_entries | الأسطر المدينة والدائنة |
| relationship_sync_counters | عداد تسلسل أحداث العلاقة |
| relationship_events | سجل أحداث المزامنة |
| settlement_requests | طلب التصفير |
| settlement_decisions | قرار الطرف المقابل |
| account_cycles | صفحات الحساب الحالية والمؤرشفة |
| sales_returns | المرتجعات المعتمدة المرتبطة بالتزام أصلي؛ immutable ويُنشئ قيدًا عكسيًا |

## 3. قيود لا يظهرها الرسم وحده

- المفاتيح المركبة تربط السجلات بالعلاقة نفسها، وتمنع مراجع عابرة للعلاقات.
- أسطر القيد مرتبطة برأس القيد والحساب وبالعملة والعلاقة ذاتها.
- تخصيص الدفعة يخضع للتحقق من الأطراف والعملة والمبالغ المتبقية؛ migration 008 يمنع تخصيصًا بين دورتين.
- العمليات والقيود وطلبات التصفير تحمل cycle_id. لكل علاقة دورة نشطة واحدة، وrelationships.current_cycle_id يشير إلى الحالية.
- operation_id في relationship_events يقبل NULL لأحداث التصفير.
- السجلات المالية وأحداث/قرارات محددة محمية من UPDATE/DELETE بواسطة triggers. سجل المرتجعات sales_returns منفذ في migration 009 ومحصن من UPDATE/DELETE؛ لا يعني ذلك اكتمال واجهة مرتجع أو رد نقدي مستقل أو سير عمل عام لعكس كل أنواع الدفعات والتخصيصات.

## 4. ما ليس موجودًا كجداول في migrations 001–009

لا توجد جداول ledger للمستخدمين/OTP، الأجهزة والجلسات، المرفقات، سياسات الموافقة المستقلة، سجل تدقيق أمني منفصل، أو outbox وsync cursor المحليين (هذه ضمن طبقة الهاتف). لا ترسم هذه كجداول منفذة قبل إضافة migrations.

## 5. مصدر الحقيقة والاختبار

- المصدر: migrations 001–009 داخل db/migrations.
- الاختبارات: db/tests/001 إلى 005 و007.
- Workflow: .github/workflows/ledger-db-tests.yml.
- دليل PostgreSQL 16: [CI Run #94](https://github.com/overurdream-collab/test4/actions/runs/41424042840).
- لا توجد قاعدة إنتاجية أو نشر ضمن هذا العمل.

**تحديث بعد PR #25–#28:** أضيفت sales_returns في migration 009، وأصبح API يعرض partyBalanceMinor بإشارة موجبة/سالبة لكل طرف. PostgreSQL Run #131 وApproval API Run #66 ناجحان. راجع ملف التسليم لأرقام SHA وروابط التشغيل.

**تنبيه:** الرسم يوضح الكيانات وروابطها. ملفات SQL هي المرجع النهائي لأنواع القيود المركبة وCHECK والفهارس وtriggers.

## 6. مخطط الهوية والأجهزة — migration 010

الجداول التالية منفذة في schema منفصل باسم `identity`، وليست جزءًا من دفتر `ledger`:

```mermaid
erDiagram
 USERS ||--o| USER_PROFILES : profile
 USERS ||--o{ PHONE_IDENTITIES : verified_phones
 USERS ||--o{ DEVICES : owns
 USERS ||--o{ AUTH_SESSIONS : sessions
 DEVICES ||--o{ AUTH_SESSIONS : session_device
 OTP_CHALLENGES {
  uuid id PK
  text phone_e164
  text purpose
  bytea code_hash
  bytea requested_ip_hash
  text status
  smallint attempts
  timestamptz created_at
  timestamptz expires_at
  timestamptz consumed_at
 }
 USERS {
  uuid id PK
  text status
  timestamptz created_at
 }
 USER_PROFILES {
  uuid user_id PK,FK
  text display_name
  text locale
  timestamptz updated_at
 }
 PHONE_IDENTITIES {
  uuid id PK
  uuid user_id FK
  text phone_e164 UK
  timestamptz verified_at
 }
 DEVICES {
  uuid id PK
  uuid user_id FK
  text device_label
  text platform
  text status
  timestamptz registered_at
  timestamptz last_seen_at
  timestamptz revoked_at
 }
 AUTH_SESSIONS {
  uuid id PK
  uuid user_id FK
  uuid device_id FK
  timestamptz created_at
  timestamptz expires_at
  timestamptz revoked_at
 }
```

| الجدول | المسؤولية |
|---|---|
| identity.users | حساب المستخدم الموحد وحالته |
| identity.phone_identities | أرقام الهاتف الموثقة؛ الرقم الواحد لحساب واحد |
| identity.user_profiles | الاسم الظاهر واللغة |
| identity.devices | الأجهزة النشطة أو الملغاة |
| identity.auth_sessions | جلسات access token قصيرة العمر، مرتبطة بالمستخدم والجهاز |
| identity.otp_challenges | تحديات OTP؛ يخزن HMAC digest لا الرمز النصي |

### حدود الربط الحالية
- `identity.users.id` هو معرف الحساب الذي يعيده مسار OTP.
- جداول `ledger.relationship_members.user_id` لا تحمل حتى الآن FK مباشرًا إلى `identity.users`؛ هذا مقصود مؤقتًا للحفاظ على بيانات/اختبارات ledger السابقة التي استخدمت معرفات خارجية. يجب أن ينشئ مسار العلاقات عضوية بمعرف حساب موثق، ثم يمكن إضافة قيد FK بعد ترحيل/مطابقة البيانات بأمان.
- لا توجد بعد جداول دعوات/طلبات ربط العلاقات في migration 010.
- لا يوجد مزود SMS فعلي أو refresh token؛ لا تعتبر وجود OTP adapter مصادقة إنتاجية مكتملة.




## 7. مخطط العلاقات والدعوات — migration 011

```mermaid
erDiagram
 RELATIONSHIPS ||--o| RELATIONSHIP_INVITATIONS : invitation
 IDENTITY_USERS ||--o{ RELATIONSHIP_INVITATIONS : inviter
 IDENTITY_USERS o|--o{ RELATIONSHIP_INVITATIONS : invitee
 RELATIONSHIP_INVITATIONS ||--o{ RELATIONSHIP_INVITATION_EVENTS : audit
 RELATIONSHIPS ||--o{ RELATIONSHIP_INVITATION_EVENTS : history
 IDENTITY_USERS o|--o{ RELATIONSHIP_INVITATION_EVENTS : actor
 RELATIONSHIPS {
  uuid id PK
  text status
  text relationship_type
  uuid created_by_user_id FK
  uuid current_cycle_id FK
 }
 RELATIONSHIP_INVITATIONS {
  uuid id PK
  uuid relationship_id FK,UK
  uuid inviter_user_id FK
  uuid invitee_user_id FK
  text invitee_phone_e164
  text relationship_type
  text inviter_role
  text invitee_role
  bytea request_hash
  text status
  uuid decision_id UK
  timestamptz expires_at
  timestamptz responded_at
  uuid responded_by_user_id FK
 }
 RELATIONSHIP_INVITATION_EVENTS {
  uuid id PK
  uuid invitation_id FK
  uuid relationship_id FK
  uuid actor_user_id FK
  text event_type
  jsonb event_payload
  timestamptz created_at
 }
```

| الجدول | المسؤولية |
|---|---|
| ledger.relationship_invitations | طلب ربط واحد لعلاقة v1، مرتبط بالهاتف الموثق، مع idempotency وقرار القبول/الرفض |
| ledger.relationship_invitation_events | سجل أحداث غير قابل للتعديل/الحذف لإنشاء الدعوة والقبول والرفض والانتهاء |

### قيود العلاقة الجديدة
- تنشأ العلاقة بحالة `suspended` وبطرف نشط واحد؛ لا تقبل عمليات مالية.
- قبول الدعوة يتطلب حسابًا نشطًا ورقم هاتف موثقًا يطابق رقم المدعو، ثم تصبح العلاقة `active` بطرفين نشطين.
- الرفض أو انتهاء الدعوة يغلق العلاقة المعلقة.
- migration 011 يمنع أكثر من طرفين نشطين ويمنع إدخال عملية مالية ما لم يوجد طرفان نشطان.
- لم يضف FK مباشرًا من `ledger.relationship_members.user_id` إلى `identity.users.id` للحفاظ على معرفات السجلات القديمة؛ دالة إنشاء العلاقة تتحقق من الهوية قبل إنشاء العضوية الجديدة.
