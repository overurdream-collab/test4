\set ON_ERROR_STOP on
BEGIN;
INSERT INTO ledger.relationships(id,status) VALUES('19000000-0000-0000-0000-000000000001','active');
INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve) VALUES
('19000000-0000-0000-0000-000000000001','29000000-0000-0000-0000-000000000001','seller','active',true),
('19000000-0000-0000-0000-000000000001','29000000-0000-0000-0000-000000000002','buyer','active',true);

-- 10,000 obligation; 7,000 paid and allocated; then 8,000 returned.
SELECT * FROM ledger.accept_operation('39000000-0000-0000-0000-000000000001','19000000-0000-0000-0000-000000000001',
'29000000-0000-0000-0000-000000000001','79000000-0000-0000-0000-000000000001','credit_charge',
decode(repeat('a1',32),'hex'),'{"creditorUserId":"29000000-0000-0000-0000-000000000001","debtorUserId":"29000000-0000-0000-0000-000000000002","currency":"YER","amountMinor":10000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69000000-0000-0000-0000-000000000001','19000000-0000-0000-0000-000000000001',
'39000000-0000-0000-0000-000000000001','29000000-0000-0000-0000-000000000002',1,'approved','charge approved');
SELECT * FROM ledger.accept_operation('39000000-0000-0000-0000-000000000002','19000000-0000-0000-0000-000000000001',
'29000000-0000-0000-0000-000000000002','79000000-0000-0000-0000-000000000002','payment',
decode(repeat('a2',32),'hex'),'{"payerUserId":"29000000-0000-0000-0000-000000000002","payeeUserId":"29000000-0000-0000-0000-000000000001","currency":"YER","amountMinor":7000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69000000-0000-0000-0000-000000000002','19000000-0000-0000-0000-000000000001',
'39000000-0000-0000-0000-000000000002','29000000-0000-0000-0000-000000000001',1,'approved','payment approved');
CREATE TEMP TABLE return_test_ids AS
SELECT (SELECT id FROM ledger.obligations WHERE source_operation_id='39000000-0000-0000-0000-000000000001') obligation_id,
(SELECT id FROM ledger.payments WHERE source_operation_id='39000000-0000-0000-0000-000000000002') payment_id;
SELECT * FROM ledger.accept_operation('39000000-0000-0000-0000-000000000003','19000000-0000-0000-0000-000000000001',
'29000000-0000-0000-0000-000000000002','79000000-0000-0000-0000-000000000003','allocation',
decode(repeat('a3',32),'hex'),jsonb_build_object('paymentId',(SELECT payment_id FROM return_test_ids),
'obligationId',(SELECT obligation_id FROM return_test_ids),'amountMinor',7000),0,1,now());
SELECT ledger.decide_operation('69000000-0000-0000-0000-000000000003','19000000-0000-0000-0000-000000000001',
'39000000-0000-0000-0000-000000000003','29000000-0000-0000-0000-000000000001',1,'approved','allocation approved');
SELECT * FROM ledger.accept_operation('39000000-0000-0000-0000-000000000004','19000000-0000-0000-0000-000000000001',
'29000000-0000-0000-0000-000000000002','79000000-0000-0000-0000-000000000004','sales_return',
decode(repeat('a4',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM return_test_ids),
'currency','YER','amountMinor',8000,'reason','Partial goods return'),0,1,now());
SELECT ledger.decide_operation('69000000-0000-0000-0000-000000000004','19000000-0000-0000-0000-000000000001',
'39000000-0000-0000-0000-000000000004','29000000-0000-0000-0000-000000000001',1,'approved','return accepted');

DO $part_paid$
DECLARE sr numeric; bp numeric; sp numeric; buyer_position numeric;
BEGIN
 SELECT COALESCE(sum(je.debit_minor-je.credit_minor),0) INTO sr
 FROM ledger.journal_entries je JOIN ledger.accounts a ON a.id=je.account_id
 WHERE a.relationship_id='19000000-0000-0000-0000-000000000001' AND a.owner_user_id='29000000-0000-0000-0000-000000000001' AND a.account_type='party_receivable';
 SELECT COALESCE(sum(je.credit_minor-je.debit_minor),0) INTO bp
 FROM ledger.journal_entries je JOIN ledger.accounts a ON a.id=je.account_id
 WHERE a.relationship_id='19000000-0000-0000-0000-000000000001' AND a.owner_user_id='29000000-0000-0000-0000-000000000002' AND a.account_type='party_payable';
 SELECT net_position_minor INTO sp FROM ledger.member_currency_positions
 WHERE relationship_id='19000000-0000-0000-0000-000000000001' AND owner_user_id='29000000-0000-0000-0000-000000000001' AND currency='YER';
 SELECT net_position_minor INTO buyer_position FROM ledger.member_currency_positions
 WHERE relationship_id='19000000-0000-0000-0000-000000000001' AND owner_user_id='29000000-0000-0000-0000-000000000002' AND currency='YER';
 IF sr<>-5000 OR bp<>-5000 OR sp<>-5000 OR buyer_position<>5000 THEN
  RAISE EXCEPTION 'Expected signed credit after part-paid return; receivable %, payable %, positions %/%',sr,bp,sp,buyer_position;
 END IF;
END; $part_paid$;

-- Cumulative returns may never exceed the original obligation.
SELECT * FROM ledger.accept_operation('39000000-0000-0000-0000-000000000005','19000000-0000-0000-0000-000000000001',
'29000000-0000-0000-0000-000000000002','79000000-0000-0000-0000-000000000005','sales_return',
decode(repeat('a5',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM return_test_ids),
'currency','YER','amountMinor',3000),0,1,now());
DO $over_return$
BEGIN
 BEGIN
  PERFORM ledger.decide_operation('69000000-0000-0000-0000-000000000005','19000000-0000-0000-0000-000000000001',
  '39000000-0000-0000-0000-000000000005','29000000-0000-0000-0000-000000000001',1,'approved','over return');
  RAISE EXCEPTION 'Over-return unexpectedly approved';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
END; $over_return$;
DO $immutable$
BEGIN
 BEGIN
  UPDATE ledger.sales_returns SET reason='mutated'
  WHERE source_operation_id='39000000-0000-0000-0000-000000000004';
  RAISE EXCEPTION 'Sales return mutation unexpectedly succeeded';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
 END;
END; $immutable$;
ROLLBACK;
