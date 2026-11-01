-- Synthetic-only scale fixture: 1,000 relationships, 1,000,000 operations and events.
-- Run only in a disposable PostgreSQL benchmark database.

INSERT INTO ledger.relationships (id, status)
SELECT md5('bench-rel-' || n)::uuid, 'active'
FROM generate_series(1, 1000) AS gs(n);

INSERT INTO ledger.relationship_members (relationship_id, user_id, role_label, status, can_approve)
SELECT
  md5('bench-rel-' || n)::uuid,
  md5('bench-user-' || n || '-1')::uuid,
  'seller',
  'active',
  true
FROM generate_series(1, 1000) AS gs(n)
UNION ALL
SELECT
  md5('bench-rel-' || n)::uuid,
  md5('bench-user-' || n || '-2')::uuid,
  'buyer',
  'active',
  true
FROM generate_series(1, 1000) AS gs(n);

INSERT INTO ledger.operations (
  operation_id, relationship_id, actor_user_id, operation_type, request_hash,
  business_state, base_version, server_version, created_at, device_id,
  client_schema_version, client_created_at, operation_payload, server_sequence
)
SELECT
  md5('bench-op-' || n)::uuid,
  md5('bench-rel-' || (((n - 1) % 1000) + 1))::uuid,
  md5('bench-user-' || (((n - 1) % 1000) + 1) || '-1')::uuid,
  'supply',
  decode(md5('bench-request-a-' || n) || md5('bench-request-b-' || n), 'hex'),
  'awaiting_counterparty',
  0,
  1,
  now() - ((n % 86400)::text || ' seconds')::interval,
  md5('bench-device-' || n)::uuid,
  1,
  now(),
  jsonb_build_object('amountMinor', 1000 + (n % 1000), 'currency', 'YER'),
  ((n - 1) / 1000) + 1
FROM generate_series(1, 1000000) AS gs(n);

INSERT INTO ledger.relationship_sync_counters (relationship_id, last_sequence)
SELECT md5('bench-rel-' || n)::uuid, 1000
FROM generate_series(1, 1000) AS gs(n);

INSERT INTO ledger.relationship_events (
  relationship_id, server_sequence, event_id, operation_id, event_type, event_payload
)
SELECT
  md5('bench-rel-' || (((n - 1) % 1000) + 1))::uuid,
  ((n - 1) / 1000) + 1,
  md5('bench-event-' || n)::uuid,
  md5('bench-op-' || n)::uuid,
  'operation.created',
  jsonb_build_object(
    'operationId', md5('bench-op-' || n)::uuid,
    'operationType', 'supply',
    'businessState', 'awaiting_counterparty',
    'serverVersion', 1,
    'payload', jsonb_build_object('amountMinor', 1000 + (n % 1000), 'currency', 'YER')
  )
FROM generate_series(1, 1000000) AS gs(n);

ANALYZE ledger.relationships;
ANALYZE ledger.relationship_members;
ANALYZE ledger.operations;
ANALYZE ledger.relationship_sync_counters;
ANALYZE ledger.relationship_events;
