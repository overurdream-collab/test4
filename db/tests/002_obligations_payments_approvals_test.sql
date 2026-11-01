\set ON_ERROR_STOP on
BEGIN;

INSERT INTO ledger.relationships (id, status)
VALUES
 ('11000000-0000-0000-0000-000000000001', 'active'),
 ('11000000-0000-0000-0000-000000000002', 'active');
INSERT INTO ledger.relationship_members
  (relationship_id, user_id, role_label, status, can_approve)
VALUES
  ('11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'seller', 'active', false),
  ('11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000002', 'buyer', 'active', true),
  ('11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000003', 'clerk', 'active', false),
  ('11000000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000002', 'buyer', 'active', false),
  ('11000000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000001', 'seller', 'active', false);

-- Approved source operations: charge, payment, and allocation commands.
INSERT INTO ledger.operations
  (operation_id, relationship_id, actor_user_id, operation_type, request_hash,
   business_state, base_version, server_version)
VALUES
 ('31000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','credit_charge',decode(repeat('11',32),'hex'),'approved',0,1),
 ('31000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','payment',decode(repeat('22',32),'hex'),'approved',0,1),
 ('31000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000002','21000000-0000-0000-0000-000000000002','credit_charge',decode(repeat('33',32),'hex'),'approved',0,1),
 ('31000000-0000-0000-0000-000000000004','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','allocation',decode(repeat('44',32),'hex'),'approved',0,1),
 ('31000000-0000-0000-0000-000000000005','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','pending_charge',decode(repeat('55',32),'hex'),'awaiting_counterparty',0,1),
 ('31000000-0000-0000-0000-000000000006','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','stale_charge',decode(repeat('66',32),'hex'),'awaiting_counterparty',0,2),
 ('31000000-0000-0000-0000-000000000007','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','allocation',decode(repeat('77',32),'hex'),'approved',0,1),
 ('31000000-0000-0000-0000-000000000008','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','allocation',decode(repeat('88',32),'hex'),'approved',0,1),
 ('31000000-0000-0000-0000-000000000009','11000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','credit_charge',decode(repeat('99',32),'hex'),'awaiting_counterparty',0,1);

INSERT INTO ledger.obligations
 (id,relationship_id,source_operation_id,creditor_user_id,debtor_user_id,currency,amount_minor)
VALUES
 ('41000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','YER',10000);

INSERT INTO ledger.payments
 (id,relationship_id,source_operation_id,payer_user_id,payee_user_id,currency,amount_minor)
VALUES
 ('51000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000002','21000000-0000-0000-0000-000000000002','21000000-0000-0000-0000-000000000001','YER',7000);

DO $$
DECLARE v bigint;
BEGIN
  -- Authorized counterparty approval advances the server version exactly once.
  v := ledger.decide_operation(
    '61000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000005',
    '21000000-0000-0000-0000-000000000002',
    1,'approved','Verified by counterparty'
  );
  IF v <> 2 THEN RAISE EXCEPTION 'Expected server version 2, got %',v; END IF;

  -- Creator cannot approve own operation.
  BEGIN
    PERFORM ledger.decide_operation(
      '61000000-0000-0000-0000-000000000002',
      '11000000-0000-0000-0000-000000000001',
      '31000000-0000-0000-0000-000000000006',
      '21000000-0000-0000-0000-000000000001',
      2,'approved',NULL
    );
    RAISE EXCEPTION 'Self-approval unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  -- Active member without approval permission is rejected.
  BEGIN
    PERFORM ledger.decide_operation(
      '61000000-0000-0000-0000-000000000003',
      '11000000-0000-0000-0000-000000000001',
      '31000000-0000-0000-0000-000000000006',
      '21000000-0000-0000-0000-000000000003',
      2,'approved',NULL
    );
    RAISE EXCEPTION 'Unauthorized approval unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  -- Stale version is a conflict, never last-write-wins.
  BEGIN
    PERFORM ledger.decide_operation(
      '61000000-0000-0000-0000-000000000004',
      '11000000-0000-0000-0000-000000000001',
      '31000000-0000-0000-0000-000000000006',
      '21000000-0000-0000-0000-000000000002',
      1,'rejected','stale test'
    );
    RAISE EXCEPTION 'Stale approval unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;

  -- Explicit partial allocation: 60 + 10 from a 70 payment to a 100 obligation.
  PERFORM ledger.allocate_payment(
    '71000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    '41000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000004',
    6000
  );
  PERFORM ledger.allocate_payment(
    '71000000-0000-0000-0000-000000000002',
    '11000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    '41000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000007',
    1000
  );

  IF (SELECT sum(amount_minor) FROM ledger.allocations
      WHERE payment_id='51000000-0000-0000-0000-000000000001') <> 7000 THEN
    RAISE EXCEPTION 'Payment allocation total mismatch';
  END IF;

  -- Exceeding the payment's remaining unapplied amount is forbidden.
  BEGIN
    PERFORM ledger.allocate_payment(
      '71000000-0000-0000-0000-000000000003',
      '11000000-0000-0000-0000-000000000001',
      '51000000-0000-0000-0000-000000000001',
      '41000000-0000-0000-0000-000000000001',
      '31000000-0000-0000-0000-000000000008',
      1
    );
    RAISE EXCEPTION 'Over-allocation of payment unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END;
$$;


-- Journal postings and balances must reflect charges, receipts, and allocations.
DO $
DECLARE seller_position numeric; buyer_position numeric; bad_count bigint;
BEGIN
  SELECT net_position_minor INTO seller_position
  FROM ledger.member_currency_positions
  WHERE relationship_id='11000000-0000-0000-0000-000000000001'
    AND owner_user_id='21000000-0000-0000-0000-000000000001' AND currency='YER';
  SELECT net_position_minor INTO buyer_position
  FROM ledger.member_currency_positions
  WHERE relationship_id='11000000-0000-0000-0000-000000000001'
    AND owner_user_id='21000000-0000-0000-0000-000000000002' AND currency='YER';
  IF seller_position <> 3000 OR buyer_position <> -3000 THEN
    RAISE EXCEPTION 'Expected seller/buyer positions +3000/-3000, got %/%',
      seller_position, buyer_position;
  END IF;

  SELECT count(*) INTO bad_count
  FROM (
    SELECT journal_transaction_id
    FROM ledger.journal_entries
    GROUP BY journal_transaction_id
    HAVING sum(debit_minor) <> sum(credit_minor)
  ) unbalanced;
  IF bad_count <> 0 THEN RAISE EXCEPTION 'Found unbalanced journal transactions'; END IF;

  BEGIN
    INSERT INTO ledger.obligations
      (id,relationship_id,source_operation_id,creditor_user_id,debtor_user_id,currency,amount_minor)
    VALUES
      ('41000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000001',
       '31000000-0000-0000-0000-000000000009','21000000-0000-0000-0000-000000000001',
       '21000000-0000-0000-0000-000000000002','YER',500);
    RAISE EXCEPTION 'Unapproved obligation unexpectedly posted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END;
$;

-- Same relationship/currency is enforced by composite foreign keys.
DO $$
BEGIN
  BEGIN
    INSERT INTO ledger.obligations
     (id,relationship_id,source_operation_id,creditor_user_id,debtor_user_id,currency,amount_minor)
    VALUES
     ('41000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000003','21000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','YER',100);
    RAISE EXCEPTION 'Cross-relationship obligation source unexpectedly succeeded';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END;
$$;

ROLLBACK;
SELECT 'obligations/payments/approvals tests passed' AS result;
