\set ON_ERROR_STOP on
BEGIN;

INSERT INTO ledger.relationships (id, status)
VALUES
 ('13000000-0000-0000-0000-000000000001','active'),
 ('13000000-0000-0000-0000-000000000002','active');
INSERT INTO ledger.relationship_members
  (relationship_id,user_id,role_label,status,can_approve)
VALUES
 ('13000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000001','seller','active',false),
 ('13000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000002','buyer','active',true),
 ('13000000-0000-0000-0000-000000000002','23000000-0000-0000-0000-000000000001','seller','active',false),
 ('13000000-0000-0000-0000-000000000002','23000000-0000-0000-0000-000000000002','buyer','active',true);

DO $$
DECLARE
  accepted record;
  replay record;
  second_relation record;
  event_count bigint;
  max_sequence bigint;
BEGIN
  SELECT * INTO accepted FROM ledger.accept_operation(
    '33000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000001',
    'credit_charge',
    decode(repeat('ab',32),'hex'),
    '{"amountMinor":1500,"currency":"YER","description":"Offline test"}'::jsonb,
    0,1,now()
  );
  IF accepted.outcome <> 'accepted' OR accepted.server_sequence <> 1
     OR accepted.business_state <> 'awaiting_counterparty' THEN
    RAISE EXCEPTION 'Unexpected first acceptance result: %', row_to_json(accepted);
  END IF;

  SELECT * INTO replay FROM ledger.accept_operation(
    '33000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000001',
    'credit_charge',
    decode(repeat('ab',32),'hex'),
    '{"amountMinor":1500,"currency":"YER","description":"Offline test"}'::jsonb,
    0,1,now()
  );
  IF replay.outcome <> 'already_processed' OR replay.server_sequence <> 1 THEN
    RAISE EXCEPTION 'Retry did not return original operation';
  END IF;

  BEGIN
    PERFORM * FROM ledger.accept_operation(
      '33000000-0000-0000-0000-000000000001',
      '13000000-0000-0000-0000-000000000001',
      '23000000-0000-0000-0000-000000000001',
      '73000000-0000-0000-0000-000000000001',
      'credit_charge',
      decode(repeat('cd',32),'hex'),
      '{"amountMinor":1501,"currency":"YER"}'::jsonb,
      0,1,now()
    );
    RAISE EXCEPTION 'Changed operation envelope reused same operation ID';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  SELECT * INTO second_relation FROM ledger.accept_operation(
    '33000000-0000-0000-0000-000000000002',
    '13000000-0000-0000-0000-000000000002',
    '23000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000001',
    'credit_charge',
    decode(repeat('ef',32),'hex'),
    '{"amountMinor":2500,"currency":"YER"}'::jsonb,
    0,1,now()
  );
  IF second_relation.server_sequence <> 1 THEN
    RAISE EXCEPTION 'Relationship sequence was not isolated';
  END IF;

  PERFORM ledger.decide_operation(
    '63000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000002',
    1,'approved','approved offline proposal'
  );

  -- State transition emits exactly one second event; exact retry emits none.
  PERFORM ledger.decide_operation(
    '63000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000002',
    1,'approved','approved offline proposal'
  );

  SELECT count(*), max(server_sequence)
    INTO event_count, max_sequence
  FROM ledger.relationship_events
  WHERE relationship_id='13000000-0000-0000-0000-000000000001';
  IF event_count <> 2 OR max_sequence <> 2 THEN
    RAISE EXCEPTION 'Expected exactly two ordered events; got count %, max %',
      event_count, max_sequence;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_events
    WHERE relationship_id='13000000-0000-0000-0000-000000000001'
      AND server_sequence=2 AND event_type='operation.state_changed'
      AND event_payload->>'businessState'='approved'
  ) THEN
    RAISE EXCEPTION 'Approval state change event missing';
  END IF;

  BEGIN
    UPDATE ledger.relationship_events
    SET event_type='tampered'
    WHERE relationship_id='13000000-0000-0000-0000-000000000001'
      AND server_sequence=1;
    RAISE EXCEPTION 'Sync event update unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$$;

ROLLBACK;
SELECT 'offline inbox and event feed tests passed' AS result;
