# Approval API module

This module implements the HTTP boundary for counterparty approve/reject decisions.

## Current implementation

- Fastify route: POST /v1/relationships/:relationshipId/operations/:operationId/decision
- Requires Idempotency-Key (UUID), decision, expectedVersion, optional reason.
- Requires an injected PrincipalResolver. The resolver must validate the user's bearer/session token and return a trusted userId and deviceId.
- The user identity is never accepted from the request body.
- The PostgreSQL function remains the authorization and concurrency authority.
- Database error codes are mapped to safe HTTP statuses without returning SQL details.

## Security boundary

No production token verifier or identity provider is bundled. This is deliberate: the repository has not selected or configured an authentication provider. The API cannot be exposed until a real resolver is implemented and tested against the chosen identity system. Unit tests use a controlled fake resolver only.

## Run locally

Requires Node.js 22 or newer.

    npm install --no-package-lock
    npm run typecheck
    npm test

The current tests validate the HTTP boundary with a fake PostgreSQL pool. PostgreSQL authorization and approval invariants are tested separately by the repository's PostgreSQL 16 workflow.

## Not implemented here

- Account registration, phone OTP, sessions, token issuance, or device enrollment.
- Operation creation endpoint and generic sync inbox/outbox endpoints.
- Production server bootstrap, deployment, or secrets management.
- Offline SQLite storage or mobile client.
