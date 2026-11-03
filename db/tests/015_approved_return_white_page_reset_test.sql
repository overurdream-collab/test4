\set ON_ERROR_STOP on
BEGIN;

INSERT INTO ledger.relationships(id,status)
VALUES ('19200000-0000-0000-0000-000000000001','active');
INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve) VALUES
('19200000-0000-0000-0000-000000000001','29200000-0000-0000-0000-000000000001','seller','active',true),
('19200000-0000-0000-0000-000000000001','29200000-0000-0000-0000-000000000002','buyer','active',true);

-- Fully settled cycle plus a fully approved return credit.
SELECT * FROM ledger.accept_operation('39200000-0000-0000-0000-000000000001','19200000-0000-0000-0000-000000000001',
'29200000-0000-0000-0000-000000000001','79200000-0000-0000-0000-000000000001','credit_charge',
decode(repeat('d1',32),'hex'),'{"creditorUserId":"29200000-0000-0000-0000-000000000001","debtorUserId":"29200000-0000-0000-0000-000000000002","currency":"YER","amountMinor":5000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69200000-0000-0000-0000-000000000001','19200000-0000-0000-0000-000000000001',
'39200000-0000-0000-0000-000000000001','29200000-0000-0000-0000-000000000002',1,'approved','charge');
SELECT * FROM ledger.accept_operation('39200000-0000-0000-0000-000000000002','19200000-0000-0000-0000-000000000001',
'29200000-0000-0000-0000-000000000002','79200000-0000-0000-0000-000000000002','payment',
decode(repeat('d2',32),'hex'),'{"payerUserId":"29200000-0000-0000-0000-000000000002","payeeUserId":"29200000-0000-0000-0000-000000000001","currency":"YER","amountMinor":5000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69200000-0000-0000-0000-000000000002','19200000-0000-0000-0000-000000000001',
'39200000-0000-0000-0000-000000000002','29200000-0000-0000-0000-000000000001',1,'approved','payment');
CREATE TEMP TABLE approved_return_ids AS
SELECT (SELECT id FROM ledger.obligations WHERE source_operation_id='39200000-0000-0000-0000-000000000001') obligation_id,
(SELECT id FROM ledger.payments WHERE source_operation_id='39200000-0000-0000-0000-000000000002') payment_id;
SELECT * FROM ledger.accept_operation('39200000-0000-0000-0000-000000000003','19200000-0000-0000-0000-000000000001',
'29200000-0000-0000-0000-000000000002','79200000-0000-0000-0000-000000000003','allocation',
decode(repeat('d3',32),'hex'),jsonb_build_object('paymentId',(SELECT payment_id FROM approved_return_ids),
'obligationId',(SELECT obligation_id FROM approved_return_ids),'amountMinor',5000),0,1,now());
SELECT ledger.decide_operation('69200000-0000-0000-0000-000000000003','19200000-0000-0000-0000-000000000001',
'39200000-0000-0000-0000-000000000003','29200000-0000-0000-0000-000000000001',1,'approved','allocation');
SELECT * FROM ledger.accept_operation('39200000-0000-0000-0000-000000000004','19200000-0000-0000-0000-000000000001',
'29200000-0000-0000-0000-000000000002','79200000-0000-0000-0000-000000000004','sales_return',
decode(repeat('d4',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM approved_return_ids),
'currency','YER','amountMinor',5000,'reason','Full approved return'),0,1,now());
SELECT ledger.decide_operation('69200000-0000-0000-0000-000000000004','19200000-0000-0000-0000-000000000001',
'39200000-0000-0000-0000-000000000004','29200000-0000-0000-0000-000000000001',1,'approved','return accepted');

DO $request$
DECLARE original_cycle uuid; request_id uuid;
BEGIN
  SELECT current_cycle_id INTO original_cycle
  FROM ledger.relationships WHERE id='19200000-0000-0000-0000-000000000001';

  request_id := ledger.request_settlement_reset(
    '85200000-0000-0000-0000-000000000001',
    '19200000-0000-0000-0000-000000000001',
    '29200000-0000-0000-0000-000000000002'
  );
  IF request_id <> '85200000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'Approved-return reset request returned unexpected id %',request_id;
  END IF;
END; $request$;

DO $decision$
DECLARE original_cycle uuid; next_cycle uuid; seller_position numeric; buyer_position numeric;
BEGIN
  SELECT cycle_id INTO original_cycle
  FROM ledger.settlement_requests WHERE id='85200000-0000-0000-0000-000000000001';
  IF ledger.decide_settlement_reset(
    '65200000-0000-0000-0000-000000000001',
    '19200000-0000-0000-0000-000000000001',
    '85200000-0000-0000-0000-000000000001',
    '29200000-0000-0000-0000-000000000001',
    'approved','return credit archived with the closed page'
  ) <> 'approved' THEN
    RAISE EXCEPTION 'Approved-return reset decision was not approved';
  END IF;

  SELECT current_cycle_id INTO next_cycle
  FROM ledger.relationships WHERE id='19200000-0000-0000-0000-000000000001';
  IF next_cycle = original_cycle THEN
    RAISE EXCEPTION 'Reset did not create a new active cycle';
  END IF;
  IF (SELECT count(*) FROM ledger.account_cycles
      WHERE relationship_id='19200000-0000-0000-0000-000000000001') <> 2 THEN
    RAISE EXCEPTION 'Expected exactly two cycles after reset';
  END IF;
  IF (SELECT status FROM ledger.account_cycles WHERE id=original_cycle) <> 'archived' THEN
    RAISE EXCEPTION 'Original cycle was not archived';
  END IF;

  SELECT net_position_minor INTO seller_position FROM ledger.member_currency_positions
  WHERE relationship_id='19200000-0000-0000-0000-000000000001' AND cycle_id=original_cycle
    AND owner_user_id='29200000-0000-0000-0000-000000000001' AND currency='YER';
  SELECT net_position_minor INTO buyer_position FROM ledger.member_currency_positions
  WHERE relationship_id='19200000-0000-0000-0000-000000000001' AND cycle_id=original_cycle
    AND owner_user_id='29200000-0000-0000-0000-000000000002' AND currency='YER';
  IF seller_position <> -5000 OR buyer_position <> 5000 THEN
    RAISE EXCEPTION 'Archived cycle must keep approved return credit; got %/%',seller_position,buyer_position;
  END IF;

  IF EXISTS (
    SELECT 1 FROM ledger.member_currency_positions
    WHERE relationship_id='19200000-0000-0000-0000-000000000001' AND cycle_id=next_cycle
      AND net_position_minor <> 0
  ) THEN
    RAISE EXCEPTION 'New white-page cycle must start with zero positions';
  END IF;
END; $decision$;

-- A return does not justify hiding unrelated debt in the same cycle.
SELECT * FROM ledger.accept_operation('39200000-0000-0000-0000-000000000005','19200000-0000-0000-0000-000000000001',
'29200000-0000-0000-0000-000000000001','79200000-0000-0000-0000-000000000005','credit_charge',
decode(repeat('d5',32),'hex'),'{"creditorUserId":"29200000-0000-0000-0000-000000000001","debtorUserId":"29200000-0000-0000-0000-000000000002","currency":"YER","amountMinor":4000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69200000-0000-0000-0000-000000000005','19200000-0000-0000-0000-000000000001',
'39200000-0000-0000-0000-000000000005','29200000-0000-0000-0000-000000000002',1,'approved','new charge');
CREATE TEMP TABLE mixed_return_ids AS
SELECT id obligation_id FROM ledger.obligations
WHERE source_operation_id='39200000-0000-0000-0000-000000000005';
SELECT * FROM ledger.accept_operation('39200000-0000-0000-0000-000000000006','19200000-0000-0000-0000-000000000001',
'29200000-0000-0000-0000-000000000002','79200000-0000-0000-0000-000000000006','sales_return',
decode(repeat('d6',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM mixed_return_ids),
'currency','YER','amountMinor',2000,'reason','Partial return with remaining debt'),0,1,now());
SELECT ledger.decide_operation('69200000-0000-0000-0000-000000000006','19200000-0000-0000-0000-000000000001',
'39200000-0000-0000-0000-000000000006','29200000-0000-0000-0000-000000000001',1,'approved','partial return accepted');

DO $mixed_balance_guard$
DECLARE next_cycle uuid;
BEGIN
  SELECT current_cycle_id INTO next_cycle
  FROM ledger.relationships WHERE id='19200000-0000-0000-0000-000000000001';
  BEGIN
    INSERT INTO ledger.settlement_requests(id,relationship_id,requested_by_user_id,cycle_id)
    VALUES ('85200000-0000-0000-0000-000000000002',
      '19200000-0000-0000-0000-000000000001',
      '29200000-0000-0000-0000-000000000002',next_cycle);
    RAISE EXCEPTION 'Reset with return plus unrelated debt unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END; $mixed_balance_guard$;

ROLLBACK;
