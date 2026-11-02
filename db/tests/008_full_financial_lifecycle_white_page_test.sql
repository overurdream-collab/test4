\set ON_ERROR_STOP on
BEGIN;

-- Full financial path: approved charge -> approved payment -> full allocation
-- -> zero balance -> bilateral white-page reset -> archived history -> new cycle.
INSERT INTO ledger.relationships (id, status)
VALUES ('17000000-0000-0000-0000-000000000001', 'active');

INSERT INTO ledger.relationship_members
  (relationship_id, user_id, role_label, status, can_approve)
VALUES
 ('17000000-0000-0000-0000-000000000001','27000000-0000-0000-0000-000000000001','seller','active',true),
 ('17000000-0000-0000-0000-000000000001','27000000-0000-0000-0000-000000000002','buyer','active',true);

-- 1) Post a real obligation through the accepted operation + counterparty approval path.
SELECT * FROM ledger.accept_operation(
 '37000000-0000-0000-0000-000000000001',
 '17000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000001',
 '77000000-0000-0000-0000-000000000001',
 'credit_charge', decode(repeat('c1',32),'hex'),
 '{"creditorUserId":"27000000-0000-0000-0000-000000000001","debtorUserId":"27000000-0000-0000-0000-000000000002","currency":"YER","amountMinor":5000}'::jsonb,
 0,1,now()
);
SELECT ledger.decide_operation(
 '67000000-0000-0000-0000-000000000001',
 '17000000-0000-0000-0000-000000000001',
 '37000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000002',
 1,'approved','full lifecycle charge approved'
);

-- 2) Record and approve the matching payment.
SELECT * FROM ledger.accept_operation(
 '37000000-0000-0000-0000-000000000002',
 '17000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000002',
 '77000000-0000-0000-0000-000000000002',
 'payment', decode(repeat('c2',32),'hex'),
 '{"payerUserId":"27000000-0000-0000-0000-000000000002","payeeUserId":"27000000-0000-0000-0000-000000000001","currency":"YER","amountMinor":5000}'::jsonb,
 0,1,now()
);
SELECT ledger.decide_operation(
 '67000000-0000-0000-0000-000000000002',
 '17000000-0000-0000-0000-000000000001',
 '37000000-0000-0000-0000-000000000002',
 '27000000-0000-0000-0000-000000000001',
 1,'approved','full lifecycle payment confirmed'
);

-- Capture the first cycle and source financial record identifiers.
CREATE TEMP TABLE lifecycle_ids AS
SELECT
  r.current_cycle_id AS old_cycle_id,
  (SELECT id FROM ledger.obligations WHERE source_operation_id='37000000-0000-0000-0000-000000000001') AS obligation_id,
  (SELECT id FROM ledger.payments WHERE source_operation_id='37000000-0000-0000-0000-000000000002') AS payment_id
FROM ledger.relationships r
WHERE r.id='17000000-0000-0000-0000-000000000001';

-- Before allocation, do not net an unpaid obligation against an unapplied payment.
-- Keep the four account classes distinct in the cycle-balance API contract.
DO $
DECLARE creditor_receivable numeric; creditor_unapplied_liability numeric;
        debtor_payable numeric; debtor_unapplied_asset numeric; cycle_now uuid;
BEGIN
  SELECT old_cycle_id INTO cycle_now FROM lifecycle_ids;
  SELECT
    COALESCE(sum(CASE WHEN a.account_type='party_receivable' THEN je.debit_minor-je.credit_minor ELSE 0 END),0),
    COALESCE(sum(CASE WHEN a.account_type='unapplied_payment_liability' THEN je.credit_minor-je.debit_minor ELSE 0 END),0)
  INTO creditor_receivable,creditor_unapplied_liability
  FROM ledger.journal_transactions jt
  JOIN ledger.journal_entries je ON je.journal_transaction_id=jt.id
  JOIN ledger.accounts a ON a.id=je.account_id
  WHERE jt.relationship_id='17000000-0000-0000-0000-000000000001'
    AND jt.cycle_id=cycle_now AND a.owner_user_id='27000000-0000-0000-0000-000000000001';

  SELECT
    COALESCE(sum(CASE WHEN a.account_type='party_payable' THEN je.credit_minor-je.debit_minor ELSE 0 END),0),
    COALESCE(sum(CASE WHEN a.account_type='unapplied_payment_asset' THEN je.debit_minor-je.credit_minor ELSE 0 END),0)
  INTO debtor_payable,debtor_unapplied_asset
  FROM ledger.journal_transactions jt
  JOIN ledger.journal_entries je ON je.journal_transaction_id=jt.id
  JOIN ledger.accounts a ON a.id=je.account_id
  WHERE jt.relationship_id='17000000-0000-0000-0000-000000000001'
    AND jt.cycle_id=cycle_now AND a.owner_user_id='27000000-0000-0000-0000-000000000002';

  IF creditor_receivable <> 5000 OR creditor_unapplied_liability <> 5000
     OR debtor_payable <> 5000 OR debtor_unapplied_asset <> 5000 THEN
    RAISE EXCEPTION 'Unapplied payment must remain separate from the obligation: creditor receivable %, creditor unapplied liability %, debtor payable %, debtor unapplied asset %',
      creditor_receivable,creditor_unapplied_liability,debtor_payable,debtor_unapplied_asset;
  END IF;
END;
$;

-- 3) Allocate the entire payment to the obligation and approve the allocation.
SELECT * FROM ledger.accept_operation(
 '37000000-0000-0000-0000-000000000003',
 '17000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000002',
 '77000000-0000-0000-0000-000000000003',
 'allocation', decode(repeat('c3',32),'hex'),
 jsonb_build_object(
   'paymentId',(SELECT payment_id FROM lifecycle_ids),
   'obligationId',(SELECT obligation_id FROM lifecycle_ids),
   'amountMinor',5000
 ),
 0,1,now()
);
SELECT ledger.decide_operation(
 '67000000-0000-0000-0000-000000000003',
 '17000000-0000-0000-0000-000000000001',
 '37000000-0000-0000-0000-000000000003',
 '27000000-0000-0000-0000-000000000001',
 1,'approved','full lifecycle allocation approved'
);

DO $
DECLARE nonzero_classes bigint; cycle_now uuid;
BEGIN
  SELECT old_cycle_id INTO cycle_now FROM lifecycle_ids;
  SELECT count(*) INTO nonzero_classes
  FROM (
    SELECT a.owner_user_id,a.currency,a.account_type,
           sum(je.debit_minor-je.credit_minor) AS signed_balance
    FROM ledger.journal_transactions jt
    JOIN ledger.journal_entries je ON je.journal_transaction_id=jt.id
    JOIN ledger.accounts a ON a.id=je.account_id
    WHERE jt.relationship_id='17000000-0000-0000-0000-000000000001'
      AND jt.cycle_id=cycle_now
    GROUP BY a.owner_user_id,a.currency,a.account_type
  ) account_balances
  WHERE signed_balance <> 0;
  IF nonzero_classes <> 0 THEN
    RAISE EXCEPTION 'Fully allocated lifecycle should clear all four account classes; nonzero groups %',nonzero_classes;
  END IF;
END;
$;
-- A separate approved allocation-command fixture remains pinned to the old cycle.
-- It is not posted to the journal; it exists solely to isolate the cycle guard.
INSERT INTO ledger.operations
  (operation_id,relationship_id,actor_user_id,operation_type,request_hash,
   business_state,base_version,server_version)
VALUES
 ('37000000-0000-0000-0000-000000000006',
  '17000000-0000-0000-0000-000000000001',
  '27000000-0000-0000-0000-000000000002',
  'allocation',decode(repeat('c6',32),'hex'),'approved',0,1);


DO $$
DECLARE outstanding numeric; unapplied numeric; position_count bigint;
        journal_count bigint; old_cycle uuid;
BEGIN
  SELECT old_cycle_id INTO old_cycle FROM lifecycle_ids;

  SELECT COALESCE(sum(o.amount_minor - COALESCE(a.allocated,0)),0)
  INTO outstanding
  FROM ledger.obligations o
  JOIN ledger.operations op ON op.operation_id=o.source_operation_id
  LEFT JOIN (SELECT obligation_id,sum(amount_minor) allocated
             FROM ledger.allocations GROUP BY obligation_id) a ON a.obligation_id=o.id
  WHERE op.cycle_id=old_cycle;

  SELECT COALESCE(sum(p.amount_minor - COALESCE(a.allocated,0)),0)
  INTO unapplied
  FROM ledger.payments p
  JOIN ledger.operations op ON op.operation_id=p.source_operation_id
  LEFT JOIN (SELECT payment_id,sum(amount_minor) allocated
             FROM ledger.allocations GROUP BY payment_id) a ON a.payment_id=p.id
  WHERE op.cycle_id=old_cycle;

  IF outstanding <> 0 OR unapplied <> 0 THEN
    RAISE EXCEPTION 'Expected fully settled cycle; outstanding %, unapplied %',outstanding,unapplied;
  END IF;

  SELECT count(*) INTO position_count
  FROM ledger.member_currency_positions
  WHERE relationship_id='17000000-0000-0000-0000-000000000001'
    AND cycle_id=old_cycle AND net_position_minor <> 0;
  IF position_count <> 0 THEN
    RAISE EXCEPTION 'Expected zero member positions after full allocation';
  END IF;

  SELECT count(*) INTO journal_count
  FROM ledger.journal_transactions
  WHERE relationship_id='17000000-0000-0000-0000-000000000001'
    AND cycle_id=old_cycle;
  IF journal_count < 3 THEN
    RAISE EXCEPTION 'Expected charge, payment and allocation journal history; found %',journal_count;
  END IF;
END;
$$;

-- 4) Request and approve the white-page reset as the counterparty.
SELECT ledger.request_settlement_reset(
 '87000000-0000-0000-0000-000000000001',
 '17000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000001'
);
SELECT ledger.decide_settlement_reset(
 '97000000-0000-0000-0000-000000000001',
 '17000000-0000-0000-0000-000000000001',
 '87000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000002',
 'approved','fully settled financial lifecycle test'
);

DO $$
DECLARE old_cycle uuid; new_cycle uuid; retained_journals bigint;
        old_operations bigint; nonzero_new_positions bigint;
BEGIN
  SELECT old_cycle_id INTO old_cycle FROM lifecycle_ids;
  SELECT current_cycle_id INTO new_cycle FROM ledger.relationships
  WHERE id='17000000-0000-0000-0000-000000000001';

  IF old_cycle = new_cycle THEN RAISE EXCEPTION 'Reset did not create a new cycle'; END IF;
  IF (SELECT status FROM ledger.account_cycles WHERE id=old_cycle) <> 'archived' THEN
    RAISE EXCEPTION 'Previous cycle was not archived';
  END IF;
  IF (SELECT status FROM ledger.relationships
      WHERE id='17000000-0000-0000-0000-000000000001') <> 'active' THEN
    RAISE EXCEPTION 'Commercial relationship must remain active';
  END IF;

  SELECT count(*) INTO retained_journals FROM ledger.journal_transactions
  WHERE relationship_id='17000000-0000-0000-0000-000000000001' AND cycle_id=old_cycle;
  SELECT count(*) INTO old_operations FROM ledger.operations
  WHERE relationship_id='17000000-0000-0000-0000-000000000001' AND cycle_id=old_cycle;
  IF retained_journals < 3 OR old_operations <> 4 THEN
    RAISE EXCEPTION 'Archived financial history missing: journal %, operations %',
      retained_journals,old_operations;
  END IF;

  SELECT count(*) INTO nonzero_new_positions
  FROM ledger.member_currency_positions
  WHERE relationship_id='17000000-0000-0000-0000-000000000001'
    AND cycle_id=new_cycle AND net_position_minor <> 0;
  IF nonzero_new_positions <> 0 THEN
    RAISE EXCEPTION 'New white-page cycle must start with zero balances';
  END IF;
END;
$$;

-- 5) Prove that a new-cycle payment cannot be allocated to an old-cycle obligation.
SELECT * FROM ledger.accept_operation(
 '37000000-0000-0000-0000-000000000004',
 '17000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000002',
 '77000000-0000-0000-0000-000000000004',
 'payment', decode(repeat('c4',32),'hex'),
 '{"payerUserId":"27000000-0000-0000-0000-000000000002","payeeUserId":"27000000-0000-0000-0000-000000000001","currency":"YER","amountMinor":100}'::jsonb,
 0,1,now()
);
SELECT ledger.decide_operation(
 '67000000-0000-0000-0000-000000000004',
 '17000000-0000-0000-0000-000000000001',
 '37000000-0000-0000-0000-000000000004',
 '27000000-0000-0000-0000-000000000001',
 1,'approved','new cycle payment confirmed'
);
-- Create an open obligation in the new cycle so the cross-cycle guard can be
-- tested without being short-circuited by the archived obligation's zero remainder.
SELECT * FROM ledger.accept_operation(
 '37000000-0000-0000-0000-000000000007',
 '17000000-0000-0000-0000-000000000001',
 '27000000-0000-0000-0000-000000000001',
 '77000000-0000-0000-0000-000000000007',
 'credit_charge', decode(repeat('c7',32),'hex'),
 '{"creditorUserId":"27000000-0000-0000-0000-000000000001","debtorUserId":"27000000-0000-0000-0000-000000000002","currency":"YER","amountMinor":100}'::jsonb,
 0,1,now()
);
SELECT ledger.decide_operation(
 '67000000-0000-0000-0000-000000000007',
 '17000000-0000-0000-0000-000000000001',
 '37000000-0000-0000-0000-000000000007',
 '27000000-0000-0000-0000-000000000002',
 1,'approved','new cycle obligation approved'
);


DO $$
DECLARE new_payment uuid; new_obligation uuid;
BEGIN
  SELECT id INTO new_payment FROM ledger.payments
  WHERE source_operation_id='37000000-0000-0000-0000-000000000004';
  SELECT id INTO new_obligation FROM ledger.obligations
  WHERE source_operation_id='37000000-0000-0000-0000-000000000007';

  -- Both financial records are open and belong to the new cycle. The source
  -- allocation command belongs to the archived cycle: only the cycle guard
  -- should reject this otherwise-valid allocation.
  BEGIN
    INSERT INTO ledger.allocations
      (id,relationship_id,payment_id,obligation_id,source_operation_id,currency,amount_minor)
    VALUES
      ('78000000-0000-0000-0000-000000000001',
       '17000000-0000-0000-0000-000000000001',
       new_payment,new_obligation,
       '37000000-0000-0000-0000-000000000006','YER',1);
    RAISE EXCEPTION 'Cross-cycle allocation unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'Allocation must stay within one account cycle%' THEN RAISE; END IF;
  END;
END;
$$;

ROLLBACK;
SELECT 'full financial lifecycle and white-page reset tests passed' AS result;
