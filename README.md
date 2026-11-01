# Shared Commercial Ledger

A Yemen-first, offline-first platform for recording and reconciling financial obligations across commercial relationships.

## Project status

This repository is being initialized. No production application code, deployment, or automated test suite exists yet.

## Product direction

- One user account can participate in multiple commercial roles and relationships.
- Each relationship has its own auditable ledger.
- YER, SAR, and USD balances remain separate; no implicit currency conversion.
- Financial records are append-only. Corrections use explicit reversals or adjustments.
- Essential workflows work offline and synchronize safely when connectivity returns.
- Synchronization status is distinct from counterparty approval status.

## Engineering approach

Start with a documented modular-monolith architecture and validate the data model, ledger invariants, and offline synchronization protocol before broad UI implementation. Keep `main` stable; implement work on feature branches and merge through reviewed pull requests.

## Documentation and handoff

Start here when joining or transferring the project:

1. [Complete Arabic project handoff](docs/MASTER_HANDOFF_AR.md)
2. [Arabic product requirements and PRD reconciliation](docs/PRODUCT_REQUIREMENTS_AR.md)
3. [Current project status and next steps](docs/PROJECT_STATUS_AND_NEXT_STEPS_AR.md)
4. [Project foundation](docs/PROJECT_FOUNDATION.md)
5. [Ledger and offline synchronization specification](docs/LEDGER_AND_SYNC_SPEC.md)

The handoff document identifies approved decisions, historical PRD requirements, deferred scope, open decisions, GitHub evidence, and the exact next engineering task. Do not treat proposed architecture or unrun tests as implemented or passing.
