\set ON_ERROR_STOP on
BEGIN;

INSERT INTO ledger.relationships (id,status)
VALUES
 ('13000000-0000-0000-0000-000000000101','active'),
 ('13000000-0000-0000-0000-000000000102','active'),
 ('13000000-0000-0000-0000-000000000103','active');

DO $$
DECLARE
  seq bigint;
  accepted record;
BEGIN
  -- Existing counter row takes the UPDATE fast path.
  INSERT INTO ledger.relationship_sync_counters(relationship_id,last_sequence)
  VALUES ('13000000-0000-0000-0000-000000000101',40);
  seq := ledger.next_relationship_sequence('13000000-0000-0000-0000-000000000101');
  IF seq <> 41 THEN RAISE EXCEPTION 'Expected existing counter 41, got %',seq; END IF;
  seq := ledger.next_relationship_sequence('13000000-0000-0000-0000-000000000101');
  IF seq <> 42 THEN RAISE EXCEPTION 'Expected existing counter 42, got %',seq; END IF;

  -- Missing counter row takes the safe first-insert path.
  seq := ledger.next_relationship_sequence('13000000-0000-0000-0000-000000000102');
  IF seq <> 1 THEN RAISE EXCEPTION 'Expected first sequence 1, got %',seq; END IF;
  seq := ledger.next_relationship_sequence('13000000-0000-0000-0000-000000000102');
  IF seq <> 2 THEN RAISE EXCEPTION 'Expected second sequence 2, got %',seq; END IF;

  -- Acceptance still commits a positive operation sequence and matching event.
  INSERT INTO ledger.relationship_members
    (relationship_id,user_id,role_label,status,can_approve)
  VALUES
    ('13000000-0000-0000-0000-000000000103','23000000-0000-0000-0000-000000000101','seller','active',false),
    ('13000000-0000-0000-0000-000000000103','23000000-0000-0000-0000-000000000102','buyer','active',true);

  SELECT * INTO accepted FROM ledger.accept_operation(
    '33000000-0000-0000-0000-000000000101',
    '13000000-0000-0000-0000-000000000103',
    '23000000-0000-0000-0000-000000000101',
    '73000000-0000-0000-0000-000000000101',
    'supply',
    decode(repeat('ab',32),'hex'),
    '{"amountMinor":1000,"currency":"YER"}'::jsonb,
    0,1,now()
  );
  IF accepted.outcome <> 'accepted' OR accepted.server_sequence <> 1 THEN
    RAISE EXCEPTION 'Acceptance returned wrong sequence: %',row_to_json(accepted);
  END IF;
  IF (SELECT server_sequence FROM ledger.operations
      WHERE operation_id='33000000-0000-0000-0000-000000000101') <> 1 THEN
    RAISE EXCEPTION 'Operation row was not assigned its event sequence';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_events
    WHERE relationship_id='13000000-0000-0000-0000-000000000103'
      AND server_sequence=1
      AND operation_id='33000000-0000-0000-0000-000000000101'
  ) THEN
    RAISE EXCEPTION 'Matching operation-created event is missing';
  END IF;

  -- Migration 012 must preserve the sales_return operation type added by migration 009.
  SELECT * INTO accepted FROM ledger.accept_operation(
    '33000000-0000-0000-0000-000000000102',
    '13000000-0000-0000-0000-000000000103',
    '23000000-0000-0000-0000-000000000101',
    '73000000-0000-0000-0000-000000000101',
    'sales_return',
    decode(repeat('cd',32),'hex'),
    '{"originalObligationId":"43000000-0000-0000-0000-000000000101","currency":"YER","amountMinor":"500","reason":"soak regression guard"}'::jsonb,
    0,1,now()
  );
  IF accepted.outcome <> 'accepted' OR accepted.server_sequence <> 2 THEN
    RAISE EXCEPTION 'sales_return operation was not preserved by sequence optimization: %',row_to_json(accepted);
  END IF;
END;
$$;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SELECT 'relationship sequence contention optimization tests passed' AS result;
