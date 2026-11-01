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

## Documentation

Project decisions, architecture, requirements, and work history will be maintained under `docs/`.
