\set ON_ERROR_STOP on
BEGIN;

INSERT INTO ledger.relationships (id, status)
VALUES ('12000000-0000-0000-0000-000000000001', 'active');
INSERT INTO ledger.relationship_members
  (relationship_id, user_id, role_label, status, can_approve)
VALUES
  ('12000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', 'seller', 'active', false),
  ('12000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000002', 'buyer', 'active', true);
INSERT INTO ledger.operations
  (operation_id, relationship_id, actor_user_id, operation_type, request_hash,
   business_state, base_version, server_version)
VALUES
 ('32000000-0000-0000-0000-000000000001','12000000-0000-0000-0000-000000000001',
  '22000000-0000-0000-0000-000000000001','credit_charge',decode(repeat('aa',32),'hex'),
  'awaiting_counterparty',0,1);

DO $$
DECLARE v bigint;
BEGIN
  v := ledger.decide_operation(
    '62000000-0000-0000-0000-000000000001',
    '12000000-0000-0000-0000-000000000001',
    '32000000-0000-0000-0000-000000000001',
    '22000000-0000-0000-0000-000000000002',
    1,'approved','accepted'
  );
  IF v <> 2 THEN RAISE EXCEPTION 'Initial decision version mismatch'; END IF;

  v := ledger.decide_operation(
    '62000000-0000-0000-0000-000000000001',
    '12000000-0000-0000-0000-000000000001',
    '32000000-0000-0000-0000-000000000001',
    '22000000-0000-0000-0000-000000000002',
    1,'approved','accepted'
  );
  IF v <> 2 THEN RAISE EXCEPTION 'Exact retry did not return original result'; END IF;

  BEGIN
    PERFORM ledger.decide_operation(
      '62000000-0000-0000-0000-000000000001',
      '12000000-0000-0000-0000-000000000001',
      '32000000-0000-0000-0000-000000000001',
      '22000000-0000-0000-0000-000000000002',
      1,'approved','different reason'
    );
    RAISE EXCEPTION 'Changed payload reused same idempotency key';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END;
$$;

ROLLBACK;
SELECT 'approval idempotency payload tests passed' AS result;
