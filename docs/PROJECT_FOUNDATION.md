# Project Foundation — Shared Commercial Ledger

**Status:** Initial engineering baseline; requirements and architecture are subject to validation.
**Market:** Yemen first.
**Repository:** `overurdream-collab/test4`
**Baseline date:** 2026-11-02

## 1. Product purpose

Provide a shared, auditable record of financial obligations between people and businesses. The product is not limited to a merchant–customer debt book: one account may act as merchant, customer, supplier, buyer, or another permitted role across multiple independent commercial relationships.

The ledger is a record and reconciliation tool. It must not silently act as a bank, payment processor, inventory system, or accounting ERP.

## 2. Approved product decisions

1. **Offline-first:** essential daily workflows must work without internet and synchronize later.
2. **Yemen-first:** Arabic RTL, practical support for Yemen phone numbers, low-bandwidth operation, and modest Android devices are primary design constraints.
3. **Multiple roles:** one user account may hold multiple roles in different relationships.
4. **Relationship isolation:** each commercial relationship has its own ledger and membership/authorization rules.
5. **Separate currencies:** YER, SAR, and USD are separate balances. No implicit conversion, aggregation, or exchange-rate assumption.
6. **Append-only financial history:** never silently edit or delete a posted financial event. Correct it through a linked reversal or adjustment with actor, reason, timestamp, and audit evidence.
7. **Bilateral workflow:** a transaction may require the receiving party's approval. Auto-approval is optional, must be explicitly enabled by an authorized party, and applies only to future transactions.
8. **Separate states:** local synchronization state and financial approval/dispute state are independent. A locally recorded action that has not synchronized is not yet visible as a confirmed counterparty action.
9. **No automatic financial authority:** the product does not autonomously authorize payments, settle external funds, or make irreversible financial decisions.
10. **Stable main:** development occurs on feature branches and is reviewed through pull requests. Do not deploy or incur paid costs without explicit approval.

## 3. Initial transaction vocabulary

The domain model must distinguish at least:
- Debt/credit sale or purchase.
- Goods or service supply (not the same as a cash payment).
- Cash/payment received or paid.
- Settlement between parties.
- Return/credit note.
- Reversal or correction.
- Dispute or request for clarification.

Do not collapse supply, payment, and settlement into one generic transaction type. Their effects and evidence differ.

## 4. Core ledger invariants

- Every posted event belongs to exactly one relationship and one currency.
- Every amount is stored as an exact decimal/minor-unit representation; never use binary floating point for money.
- A transaction cannot be counted twice because a device retries synchronization.
- Posted events are immutable; corrections reference the event they correct.
- A balance is reproducible from the ordered, auditable ledger entries.
- No cross-currency netting or conversion occurs unless a separately specified, explicitly accepted exchange transaction is introduced.
- A party cannot approve, reject, or view another relationship's private records without authorization.
- A pending, disputed, reversed, or unsynchronized item must not be presented as an ordinary confirmed balance without clear status.

## 5. Proposed architecture (not yet implemented)

Use a **modular monolith** first; avoid microservices until measured scale or team boundaries justify them.

- **Mobile client:** Flutter; Arabic RTL and accessible offline workflows.
- **Local store:** SQLite with SQLCipher or equivalent at-rest protection; durable local outbox.
- **API/backend:** TypeScript with NestJS (subject to a short technical spike).
- **Server database:** PostgreSQL.
- **Web administration:** React/TypeScript, introduced after core transaction and sync contracts stabilize.
- **Attachments:** S3-compatible object storage, with metadata and authorization in PostgreSQL.
- **Background work:** durable worker/job mechanism for notifications, attachment processing, and sync follow-up.
- **Push notifications:** optional delivery channel; never the source of truth for financial state.

The exact hosting provider, costs, and final framework choice are not approved. Prefer free/local validation first; no paid service or production deployment is authorized by this baseline.

## 6. Domain concepts to model

At minimum, validate entities and ownership boundaries for:
- users, authentication identities, devices, and sessions;
- roles and relationship memberships;
- commercial relationships and invitations;
- transactions and immutable transaction events;
- ledger accounts and ledger entries, partitioned by relationship and currency;
- approvals, disputes, adjustment/reversal requests, and settlements;
- attachments and their evidence metadata;
- device outbox, server inbox/idempotency records, and synchronization cursors;
- audit events, notifications, and notification preferences.

This is a conceptual inventory, not a finalized SQL schema. Avoid adding subscriptions, ads, or complex staff management until the core ledger is proven.

## 7. Offline synchronization contract

The implementation must use durable local writes and an explicit synchronization protocol:
1. Generate a globally unique operation ID on the device before queuing an operation.
2. Persist the operation and its local state atomically.
3. Send queued operations with idempotency keys; retry safely after timeouts or app restarts.
4. Server validates identity, relationship membership, authorization, schema version, and business invariants before accepting an operation.
5. Server records the operation ID and result so retries cannot duplicate financial effects.
6. Client receives canonical server IDs, versions, and outcomes, then marks the outbox item synchronized.
7. Conflicts in financial operations are surfaced for resolution; never resolve them with Last-Write-Wins.
8. Preserve an auditable distinction between locally created, transmitted, accepted by server, awaiting counterparty approval, approved, rejected, disputed, and reversed states.

A device must not display an unsynchronized local approval as though the other party has received it.

## 8. Approval and transaction state

Keep these dimensions separate:

**Sync state (illustrative):** local-only → queued → sending → synchronized → sync-error.

**Business state (illustrative):** draft → awaiting-counterparty → approved / rejected / disputed → reversed or adjusted where applicable.

Exact transitions, who may perform them, and whether an operation is reversible must be specified in a state-transition table before implementation.

## 9. Initial acceptance tests

The first engineering milestones must prove:
- offline create, close, and reopen without losing queued operations;
- repeated delivery of one operation does not create duplicate ledger entries;
- two devices can synchronize without silent financial overwrites;
- ledger balances reconcile exactly per relationship and currency;
- YER, SAR, and USD never mix implicitly;
- reversal/adjustment preserves the original event and complete linkage;
- approval and rejection permissions are enforced server-side;
- tenant/relationship isolation holds across API and attachment access;
- backup and restore preserve ledger history and idempotency state;
- an end-to-end offline commercial cycle succeeds before network reconnection and reconciles after sync.

No test has been run yet. These are acceptance criteria, not passing results.

## 10. Explicitly deferred from first release

Unless separately approved after the core ledger works:
- electronic payment processing;
- full inventory and warehouse management;
- tax invoice/e-invoicing compliance;
- full accounting or ERP functions;
- WhatsApp automation;
- advertising, social feed, or reels;
- AI-based financial decisions;
- complex subscription and monetization logic.

## 11. Open decisions requiring product validation

These are not silently decided:
- How should simultaneous approve/reject actions from different devices be handled?
- How can a user change a phone number or recover an account while a device has unsynchronized financial operations?
- What limited operations remain available when a subscription/license expires while offline, if monetization is later introduced?
- What are the exact transaction fields and evidence requirements for each transaction type?
- Which approval rules are mandatory versus configurable per relationship?
- What is the minimum supported Android version/device profile for the Yemen pilot?
- What backup/export format and recovery procedure should be offered to users?

## 12. Delivery sequence

1. Validate requirements and transaction vocabulary with realistic merchant/supplier/customer scenarios.
2. Specify ledger invariants, data model, and state-transition tables.
3. Specify and test offline sync/idempotency protocol.
4. Implement identity, relationship membership, and authorization.
5. Implement the financial ledger and approval/dispute flows.
6. Implement offline mobile workflows and reconciliation.
7. Add attachments, reports, and administration.
8. Run a controlled pilot with test accounts and documented recovery procedures.

## 13. Worklog

### 2026-11-02 — Repository foundation
- Confirmed GitHub connector reports admin and push permissions for this repository.
- Created the initial README on `main` because the repository had no commits and therefore no base commit from which to create a feature branch.
- Created feature branch `docs/project-foundation` from that baseline.
- Added this initial product and engineering baseline on the feature branch.
- No application code, database, deployment, paid resource, or automated test has been created or run.
