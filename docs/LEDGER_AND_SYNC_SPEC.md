# Ledger and Offline Synchronization Specification

**Status:** Conceptual target proposal; not the as-built SQL schema. For the exact PostgreSQL ERD and implementation-aligned financial rules, use `docs/DATABASE_ERD_AR.md` and `docs/LEDGER_FINANCIAL_SPEC_AR.md`. Do not treat proposed entities in this document as implemented tables.
**Date:** 2026-11-02
**Branch:** `design/ledger-and-sync-spec`
**Depends on:** `docs/PROJECT_FOUNDATION.md`

## 1. Purpose and boundaries

This specification defines the minimum safe financial and synchronization model for a shared commercial ledger. It is deliberately narrower than a full accounting system.

The system records obligations and the evidence/status around them. It does not move money, guarantee payment, infer an exchange rate, or make a financial decision on behalf of a party.

The server is authoritative for accepted shared state. A device may record a clearly marked local operation while offline, but it must never present that operation as synchronized or accepted by the other party.

## 2. Core vocabulary

| Concept | Meaning | Financial effect |
|---|---|---|
| Commercial relationship | A bounded relationship between two or more named parties | None by itself |
| Supply | Goods/services delivered or claimed as delivered | None unless a separate credit/charge event is approved |
| Credit charge | An agreed amount owed by one party to another | Increases obligation |
| Payment | Money received against an obligation or as an advance | Reduces obligation or creates unapplied credit |
| Settlement | Explicit allocation of one or more payments/credits to one or more obligations | Reconciles open items; does not create cash |
| Return / credit note | Accepted return or reduction of a prior charge | Reduces obligation, linked to original |
| Dispute | A request to challenge or clarify a record | No automatic financial effect |
| Reversal | A compensating event that neutralizes a prior posted event | Offsets prior posting; never erases it |
| Adjustment | A new, linked event correcting a prior amount or classification | Posts only the approved difference |

Do not use one generic `transaction` label without a required type and effect. In particular, supply, payment, and settlement are not interchangeable.

## 3. Relationship and party model

A relationship has a stable ID and an explicit membership list. Each member has a role and permissions scoped to that relationship. A user can have different roles in different relationships.

For the first release, a two-party relationship is the default supported financial model. The data model should not hard-code a global user role such as "merchant" or "customer". Multi-party relationships require a separately validated allocation model before being enabled.

Required relationship properties:
- stable ID, status, creation time, creator;
- member IDs, membership status, role label, permission set, joined/left timestamps;
- default display locale and timezone (display only; timestamps stored in UTC);
- per-relationship settings for approval policy, effective only for operations created after the setting version is accepted.

Membership removal must not delete historic financial records. Access to old records after leaving is a separately authorized policy decision; membership termination does not rewrite ledger history.

## 4. Money and currency rules

1. Every financial event has exactly one ISO-like supported currency code from the configured allow-list (initially YER, SAR, USD).
2. Store amounts as integer minor units where currency precision is fixed by configuration, or as exact decimal values with an explicitly fixed scale. Never use IEEE-754 floating point.
3. Store the currency code with every amount and every posting. Never infer currency from a symbol or user locale.
4. A relationship may have separate balances by currency. Never add unlike currencies into a single total.
5. Do not silently convert, round across currencies, or apply a market rate.
6. Amounts must be strictly positive for charge/payment/return commands; direction is represented by event type and posting accounts, not by allowing arbitrary negative user input.
7. Currency precision and permitted maximum amount are server-configured and validated. Display formatting must not change stored value.

A future exchange operation, if ever approved, must be a separately evidenced event containing both currencies, both exact amounts, the agreed rate, parties, and approval; it is not part of v1.

## 5. Financial posting model

### 5.1 Append-only journal

Use an append-only journal as the source of truth. A posted event is immutable. A correction is a new event linked to the original and carries a reason and actor.

For each relationship and currency, maintain balanced journal postings. The minimum account model is:
- `party_receivable`: amount this party is owed within the relationship;
- `party_payable`: amount this party owes within the relationship;
- `unapplied_credit`: payment/credit received but not yet allocated to an obligation (party-specific).

The exact account naming/sign convention must be made consistent in implementation and documented in API contracts. Each journal transaction must balance to zero within the same relationship and currency. Never balance across relationships or currencies.

Illustrative postings (debit/credit labels are accounting mechanics, not user-facing labels):

| Event | Posting effect |
|---|---|
| Approved credit charge from seller to buyer | Increase seller receivable and buyer payable by the same amount |
| Approved payment by buyer to seller, allocated to open debt | Decrease buyer payable and seller receivable by the same amount |
| Payment received in advance / not allocated | Record unapplied credit for the receiving party; do not silently choose an invoice |
| Approved return/credit note | Reduce the linked original obligation for the accepted amount |
| Reversal | Post exact compensating lines linked to the original journal transaction |
| Adjustment | Post only the approved delta, linked to the corrected event |

A supply record may carry quantity, description, delivery evidence, and dates. It affects the financial journal only when a separate charge/credit decision is made according to the relationship's approval policy.

### 5.2 Open items and allocations

An obligation and a payment are separate records. A settlement/allocation links a payment or credit to one or more open obligations.

For v1:
- require an explicit allocation when a payment is intended to settle specific charges;
- permit a payment to remain unapplied;
- never allocate automatically by oldest invoice unless the relationship explicitly enables that rule and both parties can inspect it;
- prevent allocation above the remaining unapplied payment amount or above the remaining open obligation;
- make allocation immutable once confirmed; correct it with a reversing allocation and a new allocation;
- show gross charges, payments, returns/credits, unapplied amounts, and net open balance separately.

This prevents a payment from being counted twice and avoids confusing "cash received" with "which debt was settled".

## 6. Approval and dispute state machine

Keep business state independent from sync state.

### 6.1 Proposed business states

- `draft_local`: editable local draft, not shared and no financial posting.
- `awaiting_counterparty`: server accepted the proposal, but required counterparty action is outstanding; no confirmed posting unless the policy explicitly defines a provisional view.
- `approved`: all required approvals exist; eligible financial effects are posted exactly once.
- `rejected`: proposal rejected; no financial posting.
- `disputed`: an approved record has an active dispute; original posting remains visible and is not silently removed.
- `reversed`: a compensating event has neutralized all or part of the original posting.
- `cancelled_before_posting`: proposal withdrawn before any posting.

A disputed item remains in history and its financial effect remains visible until an authorized resolution event is posted. A dispute is not itself a reversal.

### 6.2 Who can act

- Creator may edit a local draft only.
- A member with the relationship's configured approval permission may approve/reject a proposal addressed to them.
- A party cannot approve on behalf of the counterparty merely because they created the proposal.
- Auto-approval, if configured, must be explicitly enabled by an authorized relationship administrator, versioned, and applied only to proposals created after that policy version.
- Reversal/adjustment requires a reason and the permission defined by policy; high-risk corrections may require both parties.
- Every decision records actor, server timestamp, device ID, policy version, prior state, resulting state, and reason/evidence reference where applicable.

### 6.3 Concurrent decisions

Recommended v1 rule: use optimistic concurrency with a monotonically increasing server version. The first valid terminal decision committed by the server wins. A later approval/rejection against the stale version is rejected as a conflict, not silently overwritten. The client must refresh and show the actual decision and actor.

If the business wants "both parties must agree to reject" or another richer workflow, specify it as a different state machine; do not improvise it during sync.

## 7. Sync protocol

### 7.1 Local operation envelope

Every device-generated command must persist an immutable envelope before network transmission:

- `operation_id`: globally unique UUID/ULID generated on device;
- `actor_user_id`, `device_id`;
- `relationship_id`;
- `operation_type`, `schema_version`;
- `client_created_at` (informational only; not trusted for ordering);
- `base_server_version` for the aggregate being changed;
- `payload` with validated command data;
- `attachment_refs` (if any; uploaded separately);
- `local_status`: queued / sending / synced / conflict / failed;
- retry count and last error code.

The client must commit the user action and outbox envelope in one local database transaction. A crash must not leave a visible financial action without a durable outbox record, or an outbox record without the corresponding local action.

### 7.2 Server acceptance

For each operation, server processing must be atomic:
1. Authenticate the actor and device/session.
2. Check whether `operation_id` was already processed. If yes, return the original stored outcome without repeating side effects.
3. Validate relationship membership and permission at processing time.
4. Validate schema version, payload, currency, amount, references, and business state transition.
5. Check aggregate version / expected state.
6. Persist the operation result, journal entries (if approved), audit event, and new aggregate version in one database transaction.
7. Return canonical IDs, resulting version, business state, posting outcome, and server timestamp.

Use a unique database constraint on the idempotency scope (at minimum actor/device + operation ID, with operation ID globally unique preferred). Retain idempotency records at least as long as the financial/audit records they protect; do not expire them after a short cache TTL.

### 7.3 Retry and ordering

- Network timeout is an unknown outcome, not proof of failure. Retry with the same operation ID.
- Never create a new operation ID merely because the first request timed out.
- Operations that depend on earlier operations must declare dependency IDs and be processed in dependency order.
- Server must not rely on device wall clocks for financial ordering.
- Server event sequence/version determines canonical order.
- A retry returns the original result, even if the client has since changed screens or restarted.

### 7.4 Conflict handling

Do not use Last-Write-Wins for financial operations.

Return typed outcomes:
- `accepted`: accepted and synchronized;
- `already_processed`: same idempotent result returned;
- `needs_approval`: accepted proposal awaiting counterparty;
- `conflict_stale_version`: aggregate changed; refresh and require a deliberate new action;
- `forbidden`: actor lacks permission;
- `invalid_reference`: referenced relationship/member/obligation is invalid;
- `validation_error`: payload violates rules;
- `dependency_pending`: required prior operation has not been accepted;
- `temporarily_unavailable`: retry same operation ID.

A conflict must preserve the local attempted operation and explain what happened. The user may explicitly discard an unaccepted local proposal or create a new operation after reviewing current server state. The system must never silently merge two conflicting financial amounts.

## 8. Attachment handling

Attachments are evidence, not the financial source of truth.

- Store file metadata, relationship scope, uploader, checksum, MIME type, byte size, upload status, and access policy.
- Uploads use a resumable or retry-safe process and a content checksum.
- A financial operation can reference an attachment only after the server confirms the attachment belongs to the same authorized relationship (or an explicitly allowed shared evidence scope).
- Do not expose public object URLs. Use short-lived authorized access.
- Deleting an attachment from a user's device must not erase server evidence referenced by a posted event.
- If a required attachment is missing, preserve the proposal as incomplete/awaiting evidence; do not fabricate evidence or silently approve it.

## 9. Security and tenant isolation

- Enforce relationship authorization on the server for every read and write; never trust client filtering.
- Every relationship-scoped row includes `relationship_id` or is reachable only through a relationship-scoped foreign key.
- Use composite foreign keys/constraints where practical to prevent cross-relationship references.
- Attachment download authorization must be checked independently of UI visibility.
- Device revocation blocks future sync but does not erase already accepted server history.
- Encrypt transport; encrypt sensitive local database contents at rest using platform-backed key storage.
- Avoid storing secrets in logs. Audit security-relevant access and permission changes.
- Backups must be encrypted, access-controlled, tested for restore, and include journal, idempotency, and audit records consistently.

## 10. Conceptual relational schema

This is a logical model, not executable SQL. IDs are opaque UUIDs unless a later scale/partitioning study justifies another representation.

| Table | Key fields and constraints |
|---|---|
| `users` | id, phone_e164, display_name, status, created_at; normalized unique phone subject to account recovery policy |
| `devices` | id, user_id, public_key/device metadata, revoked_at, last_seen_at |
| `relationships` | id, status, created_by, policy_version, created_at |
| `relationship_members` | relationship_id, user_id, role_label, permission_set, status; unique relationship/user |
| `business_operations` | id, relationship_id, operation_id unique, type, actor_id, base_version, business_state, payload, server_version, created_at |
| `approvals` | id, relationship_id, operation_id, actor_id, decision, policy_version, reason, decided_at; unique decision slot per operation/actor |
| `journal_transactions` | id, relationship_id, source_operation_id unique, currency, status, effective_at, created_at |
| `journal_entries` | id, journal_transaction_id, relationship_id, account_owner_id, account_type, debit_minor, credit_minor, currency; positive values, one-sided debit/credit, same currency/relationship as parent |
| `obligations` | id, relationship_id, source_operation_id, creditor_id, debtor_id, currency, original_amount_minor, status |
| `payments` | id, relationship_id, source_operation_id, payer_id, payee_id, currency, amount_minor, status |
| `allocations` | id, relationship_id, payment_id, obligation_id, amount_minor, source_operation_id, reversal_of_id; enforce same relationship/currency and cumulative bounds transactionally |
| `audit_events` | id, relationship_id, actor_id, device_id, event_type, subject_type/id, before/after references, reason, server_time |
| `idempotency_records` | operation_id unique, actor_id, device_id, request_hash, outcome_code, response_body/reference, processed_at |
| `attachments` | id, relationship_id, uploader_id, object_key, checksum, mime_type, byte_size, upload_state, created_at |
| `outbox` (device-local) | operation_id primary key, relationship_id, type, payload, base_version, local_state, attempts, last_error |
| `sync_cursor` (device-local) | relationship_id, last_server_sequence, updated_at; unique per relationship |

Required database safeguards:
- unique `operation_id` for accepted operations and journal source operations;
- foreign keys that bind all referenced entities to the same relationship;
- check constraints for positive amount and one-sided debit/credit entry;
- transactional validation that total debits equal total credits per journal transaction and currency;
- transactional allocation bounds (simple row CHECK constraints cannot enforce aggregate sums);
- indexes beginning with `relationship_id` for relationship-scoped list and sync queries;
- no hard-delete cascade from users, members, or operations into financial history.

The exact schema, indexes, row-level security approach, and partitioning strategy require a PostgreSQL prototype and query tests before final approval.

## 11. Scale and reliability approach

Design for horizontal application instances and stateless API workers, but do not prematurely split into microservices.

Initial scale principles:
- paginate all relationship history; never load an entire ledger on mobile;
- use cursor-based incremental sync, not full-table polling;
- index by relationship, server sequence/time, and relevant participant/status;
- keep attachment bytes out of PostgreSQL; keep metadata and authorization there;
- make background jobs retryable and idempotent;
- use connection pooling and bounded request sizes;
- measure read/write latency, sync backlog, database utilization, error rates, and per-tenant hot spots;
- introduce partitioning, read replicas, queues, or service extraction only when measurements justify them.

A one-million-user target is not the same as one million concurrent users. Capacity planning needs explicit assumptions for daily active users, transactions per user, peak writes/second, attachment volume, retention, and sync burst behavior. Those assumptions have not yet been supplied and must not be invented.

## 12. Backup, recovery, and account changes

- Backups must include a mutually consistent snapshot of journal, business operations, idempotency records, audit events, relationship membership, and attachment metadata.
- Test restoration into an isolated environment and reconcile journal totals against source operations.
- Device-local unsynchronized operations must be exportable/recoverable before app removal or device replacement, subject to user authentication and encryption.
- Phone-number change must be an authenticated identity update, not a new account that strands history.
- Account recovery must not allow a new claimant to take over a phone identity without the defined verification process.
- Revoked/lost devices must not be able to sync new operations after revocation; already queued local actions need a visible recovery path and must not be silently submitted by another user.

## 13. Required test scenarios

These are required tests; none are claimed to have run in this documentation-only change.

### Journal correctness
1. Approved credit charge creates balanced postings exactly once.
2. Allocated payment reduces the correct open obligation exactly once.
3. Unapplied payment does not reduce a specific obligation until allocation.
4. Return/credit note cannot exceed the remaining eligible original amount.
5. Reversal preserves original event and posts exact compensating entries.
6. YER, SAR, and USD balances remain isolated.
7. Same amount represented in different currencies never reconciles as equal.

### Approval and authorization
8. Creator cannot approve their own proposal when counterparty approval is required.
9. Unauthorized member cannot approve, reject, reverse, or read private evidence.
10. Concurrent approve/reject attempts result in one canonical terminal decision and one stale-version conflict.
11. Policy changes affect only operations covered by their effective version.

### Offline and idempotency
12. Create an operation offline, close/reopen app, and sync it once.
13. Simulate server commit followed by dropped response; retry same operation ID and verify no duplicate posting.
14. Send same operation ID with a different payload hash; reject as idempotency misuse.
15. Sync dependent operations out of order; server returns dependency pending without corrupting state.
16. Two devices act on the same stale version; one succeeds and the other receives a conflict.
17. Revoke a device while it has queued operations; reject new sync and preserve recoverable local data.
18. Restore backup and verify journal, audit trail, and idempotency records reconcile.

### Isolation and performance
19. Attempt cross-relationship IDs in every foreign-key/reference path; reject.
20. Verify attachment reads require relationship authorization.
21. Run cursor sync across large histories without gaps or duplicates.
22. Load-test representative peak writes and sync bursts after workload assumptions are agreed.

## 14. Decisions recommended for the first prototype

These are recommendations to validate, not silently finalized product policy:
1. Start with two-party relationships only.
2. Use a balanced append-only journal and explicit obligation/payment/allocation records.
3. Require counterparty approval for new credit charges by default; make policy configurable only after user testing.
4. Let payments be recorded as proposals and require explicit allocation to settle specific obligations.
5. Use first-server-commit-wins for concurrent terminal decisions, with stale-version conflict for the losing action.
6. Preserve all local queued operations across app restarts and never change operation IDs on retry.
7. Do not implement subscription expiry, automatic exchange rates, or multi-party allocation in the first prototype.

## 15. Relationship to the implemented schema\n\nThe conceptual schema in Section 10 is a target model, not a list of tables already deployed. The as-built database is defined by migrations 001–008. Its exact entity relationships are documented in `docs/DATABASE_ERD_AR.md`; implemented posting behavior and explicit gaps are documented in `docs/LEDGER_FINANCIAL_SPEC_AR.md`. In particular, user/device/attachment/audit/idempotency-record entities in the conceptual proposal must not be mistaken for PostgreSQL tables in the current ledger schema.\n\n## 16. Worklog

### 2026-11-02 — Ledger and sync specification
- Created this engineering proposal on `design/ledger-and-sync-spec`.
- Defined transaction vocabulary, append-only posting model, approval states, idempotent sync envelope, conflict outcomes, attachment boundaries, logical schema, security safeguards, scale principles, recovery, and required test scenarios.
- No application code or database migration was executed.
- No automated tests were run; all tests in Section 13 are acceptance requirements.
- No paid service, production deployment, or destructive operation was performed.
