# API modules

This folder contains the first TypeScript/Fastify HTTP boundaries for the shared ledger.

## Approval API

- POST /v1/relationships/:relationshipId/operations/:operationId/decision
- Uses the PostgreSQL decision function for membership/permission checks, optimistic versioning, and idempotent decisions.

## Offline sync API (server side)

- POST /v1/relationships/:relationshipId/operations accepts a durable operation envelope.
- GET /v1/relationships/:relationshipId/events?after={sequence}&limit={n} reads the ordered relationship event feed.
- Actor and device identifiers come only from the trusted PrincipalResolver.
- Request hashes are calculated server-side from a canonicalized envelope.
- PostgreSQL assigns the per-relationship sequence and stores the operation/event atomically.
- Approval of credit_charge, payment, and allocation materializes the financial fact and journal posting in the same transaction as the decision/event.

## Security boundary

The module requires an injected PrincipalResolver. No production identity provider, bearer-token verifier, registration/OTP, device enrollment, or server bootstrap is bundled. Do not expose these routes until a real authentication adapter is implemented and tested.

The PostgreSQL functions enforce relationship membership, approval permissions, idempotency, state versions, and allocation bounds. The HTTP layer does not trust actor/device IDs from request payloads.

## Run checks

Requires Node.js 22 or newer.

    npm install --no-package-lock
    npm run typecheck
    npm test

Unit tests use a fake principal resolver and fake PostgreSQL pool. Database invariants run separately in the PostgreSQL 16 GitHub Actions workflow.

## Financial lifecycle E2E

`npm run test:e2e` runs the full HTTP path against a real PostgreSQL database: OTP login, relationship invitation, charge, self-approval rejection, counterparty approval, payment, allocation, account-cycle balances for both parties, outsider isolation, and white-page reset. It requires a migrated database:

    DATABASE_URL=postgres://ledger_test:ledger_test@localhost:5432/ledger_test \
    ACCESS_TOKEN_SECRET=... OTP_PEPPER=... REFRESH_TOKEN_PEPPER=... \
    npm run test:e2e

The GitHub workflow applies migrations 001–013 before running this suite.

## Still not implemented

- Mobile client or encrypted SQLite/SQLCipher outbox.
- Device registration/revocation and production authentication.
- Full sync conflict UX, attachment sync, backup/restore.
- Two-device offline/reconnect simulation or physical-device test.
- Load/performance benchmark or deployment.
