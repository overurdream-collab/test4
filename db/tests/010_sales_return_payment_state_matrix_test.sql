\set ON_ERROR_STOP on
BEGIN;
INSERT INTO ledger.relationships(id,status) VALUES('19100000-0000-0000-0000-000000000001','active');
INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve) VALUES
('19100000-0000-0000-0000-000000000001','29100000-0000-0000-0000-000000000001','seller','active',true),
('19100000-0000-0000-0000-000000000001','29100000-0000-0000-0000-000000000002','buyer','active',true);

-- Fully paid: 5,000 charge, 5,000 payment, fully allocated, then full return.
SELECT * FROM ledger.accept_operation('39100000-0000-0000-0000-000000000001','19100000-0000-0000-0000-000000000001',
'29100000-0000-0000-0000-000000000001','79100000-0000-0000-0000-000000000001','credit_charge',
decode(repeat('c1',32),'hex'),'{"creditorUserId":"29100000-0000-0000-0000-000000000001","debtorUserId":"29100000-0000-0000-0000-000000000002","currency":"YER","amountMinor":5000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69100000-0000-0000-0000-000000000001','19100000-0000-0000-0000-000000000001',
'39100000-0000-0000-0000-000000000001','29100000-0000-0000-0000-000000000002',1,'approved','charge');
SELECT * FROM ledger.accept_operation('39100000-0000-0000-0000-000000000002','19100000-0000-0000-0000-000000000001',
'29100000-0000-0000-0000-000000000002','79100000-0000-0000-0000-000000000002','payment',
decode(repeat('c2',32),'hex'),'{"payerUserId":"29100000-0000-0000-0000-000000000002","payeeUserId":"29100000-0000-0000-0000-000000000001","currency":"YER","amountMinor":5000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69100000-0000-0000-0000-000000000002','19100000-0000-0000-0000-000000000001',
'39100000-0000-0000-0000-000000000002','29100000-0000-0000-0000-000000000001',1,'approved','payment');
CREATE TEMP TABLE fully_paid_return_ids AS
SELECT (SELECT id FROM ledger.obligations WHERE source_operation_id='39100000-0000-0000-0000-000000000001') obligation_id,
(SELECT id FROM ledger.payments WHERE source_operation_id='39100000-0000-0000-0000-000000000002') payment_id;
SELECT * FROM ledger.accept_operation('39100000-0000-0000-0000-000000000003','19100000-0000-0000-0000-000000000001',
'29100000-0000-0000-0000-000000000002','79100000-0000-0000-0000-000000000003','allocation',
decode(repeat('c3',32),'hex'),jsonb_build_object('paymentId',(SELECT payment_id FROM fully_paid_return_ids),
'obligationId',(SELECT obligation_id FROM fully_paid_return_ids),'amountMinor',5000),0,1,now());
SELECT ledger.decide_operation('69100000-0000-0000-0000-000000000003','19100000-0000-0000-0000-000000000001',
'39100000-0000-0000-0000-000000000003','29100000-0000-0000-0000-000000000001',1,'approved','allocation');
SELECT * FROM ledger.accept_operation('39100000-0000-0000-0000-000000000004','19100000-0000-0000-0000-000000000001',
'29100000-0000-0000-0000-000000000002','79100000-0000-0000-0000-000000000004','sales_return',
decode(repeat('c4',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM fully_paid_return_ids),
'currency','YER','amountMinor',5000),0,1,now());
SELECT ledger.decide_operation('69100000-0000-0000-0000-000000000004','19100000-0000-0000-0000-000000000001',
'39100000-0000-0000-0000-000000000004','29100000-0000-0000-0000-000000000001',1,'approved','full return after full payment');

DO $fully_paid_return$
DECLARE seller_credit numeric; buyer_credit numeric;
BEGIN
 SELECT sum(je.debit_minor-je.credit_minor) INTO seller_credit
 FROM ledger.journal_entries je JOIN ledger.accounts a ON a.id=je.account_id
 WHERE a.relationship_id='19100000-0000-0000-0000-000000000001'
 AND a.owner_user_id='29100000-0000-0000-0000-000000000001' AND a.account_type='party_receivable';
 SELECT sum(je.credit_minor-je.debit_minor) INTO buyer_credit
 FROM ledger.journal_entries je JOIN ledger.accounts a ON a.id=je.account_id
 WHERE a.relationship_id='19100000-0000-0000-0000-000000000001'
 AND a.owner_user_id='29100000-0000-0000-0000-000000000002' AND a.account_type='party_payable';
 IF seller_credit<>-5000 OR buyer_credit<>-5000 THEN
  RAISE EXCEPTION 'Fully paid return must create signed 5,000 buyer credit; got %/%',seller_credit,buyer_credit;
 END IF;
END; $fully_paid_return$;

-- Unpaid: return 2,000 from a 4,000 obligation and leave 2,000 due.
SELECT * FROM ledger.accept_operation('39100000-0000-0000-0000-000000000005','19100000-0000-0000-0000-000000000001',
'29100000-0000-0000-0000-000000000001','79100000-0000-0000-0000-000000000005','credit_charge',
decode(repeat('c5',32),'hex'),'{"creditorUserId":"29100000-0000-0000-0000-000000000001","debtorUserId":"29100000-0000-0000-0000-000000000002","currency":"YER","amountMinor":4000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69100000-0000-0000-0000-000000000005','19100000-0000-0000-0000-000000000001',
'39100000-0000-0000-0000-000000000005','29100000-0000-0000-0000-000000000002',1,'approved','unpaid charge');
CREATE TEMP TABLE unpaid_return_ids AS
SELECT id obligation_id FROM ledger.obligations WHERE source_operation_id='39100000-0000-0000-0000-000000000005';
SELECT * FROM ledger.accept_operation('39100000-0000-0000-0000-000000000006','19100000-0000-0000-0000-000000000001',
'29100000-0000-0000-0000-000000000002','79100000-0000-0000-0000-000000000006','sales_return',
decode(repeat('c6',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM unpaid_return_ids),
'currency','YER','amountMinor',2000),0,1,now());
SELECT ledger.decide_operation('69100000-0000-0000-0000-000000000006','19100000-0000-0000-0000-000000000001',
'39100000-0000-0000-0000-000000000006','29100000-0000-0000-0000-000000000001',1,'approved','partial return against unpaid charge');

DO $unpaid_return$
DECLARE seller_due numeric; buyer_due numeric;
BEGIN
 SELECT sum(je.debit_minor-je.credit_minor) INTO seller_due
 FROM ledger.journal_entries je JOIN ledger.journal_transactions jt ON jt.id=je.journal_transaction_id
 JOIN ledger.accounts a ON a.id=je.account_id
 WHERE jt.source_operation_id IN ('39100000-0000-0000-0000-000000000005','39100000-0000-0000-0000-000000000006')
 AND a.owner_user_id='29100000-0000-0000-0000-000000000001' AND a.account_type='party_receivable';
 SELECT sum(je.credit_minor-je.debit_minor) INTO buyer_due
 FROM ledger.journal_entries je JOIN ledger.journal_transactions jt ON jt.id=je.journal_transaction_id
 JOIN ledger.accounts a ON a.id=je.account_id
 WHERE jt.source_operation_id IN ('39100000-0000-0000-0000-000000000005','39100000-0000-0000-0000-000000000006')
 AND a.owner_user_id='29100000-0000-0000-0000-000000000002' AND a.account_type='party_payable';
 IF seller_due<>2000 OR buyer_due<>2000 THEN
  RAISE EXCEPTION 'Unpaid partial return must leave 2,000 due; got %/%',seller_due,buyer_due;
 END IF;
END; $unpaid_return$;

-- A cycle with credit or debt cannot be archived as a white page.
DO $reset_guard$
BEGIN
 BEGIN
  INSERT INTO ledger.settlement_requests(id,relationship_id,requested_by_user_id,cycle_id)
  SELECT gen_random_uuid(),id,'29100000-0000-0000-0000-000000000001',current_cycle_id
  FROM ledger.relationships WHERE id='19100000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'Reset with signed balances unexpectedly succeeded';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
END; $reset_guard$;
ROLLBACK;
