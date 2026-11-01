# Shared Commercial Ledger

A Yemen-first, offline-first platform for recording and reconciling financial obligations across commercial relationships.

## Current engineering status

- PostgreSQL 16 append-only journal core is merged and its invariant suite passes.
- Relationship-scoped obligations, payments, explicit allocations, approval decisions, and journal-based member positions are merged and tested.
- An initial TypeScript/Fastify approval HTTP boundary is under review in PR #8; it requires a real authentication resolver before exposure.
- A Flutter offline-store package and HTTP sync coordinator are under review in PR #10; FFI/fake-server tests simulate two independent clients, but SQLCipher native encryption and physical-device sync are not yet verified.
- No production authentication adapter, backup/key recovery, performance/load benchmark, production database, or deployment exists yet.

## Product direction

- One user account can participate in multiple commercial roles and relationships.
- Each relationship has its own auditable ledger.
- YER, SAR, and USD balances remain separate; no implicit currency conversion.
- Financial records are append-only. Corrections use explicit reversals or adjustments.
- Essential workflows work offline and synchronize safely when connectivity returns.
- Synchronization status is distinct from counterparty approval status.

## Engineering approach

Build and validate the financial core before UI work. Use feature branches and reviewed pull requests. Do not connect a production database, deploy, or incur paid costs without explicit approval.

## Documentation and handoff

1. [Complete Arabic project handoff](docs/MASTER_HANDOFF_AR.md)
2. [Arabic product requirements and PRD reconciliation](docs/PRODUCT_REQUIREMENTS_AR.md)
3. [Current project status and next steps](docs/PROJECT_STATUS_AND_NEXT_STEPS_AR.md)
4. [Project foundation](docs/PROJECT_FOUNDATION.md)
5. [Ledger and offline synchronization specification](docs/LEDGER_AND_SYNC_SPEC.md)
6. [API and offline sync implementation contract](docs/IMPLEMENTATION_API_OFFLINE_SYNC_AR.md)

The handoff documents distinguish implemented code, passing tests, proposals, and unfinished work. Do not describe proposed features or unrun tests as complete.
