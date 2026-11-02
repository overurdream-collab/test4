\\set ON_ERROR_STOP on
BEGIN;

INSERT INTO ledger.relationships (id, status)
VALUES ('15000000-0000-0000-0000-000000000001', 'active');
INSERT INTO ledger.relationship_members
  (relationship_id, user_id, role_label, status, can_approve)
VALUES
 ('15000000-0000-0000-0000-000000000001','25000000-0000-0000-0000-000000000001','seller','active',false),
 ('15000000-0000-0000-0000-000000000001','25000000-0000-0000-0000-000000000002','buyer','active',true);

SELECT * FROM ledger.accept_operation(
 '35000000-0000-0000-0000-000000000001',
 '15000000-0000-0000-0000-000000000001',
 '25000000-0000-0000-0000-000000000001',
 '75000000-0000-0000-0000-000000000001',
 'credit_charge', decode(repeat('a1',32),'hex'),
 '{"creditorUserId":"25000000-0000-0000-0000-000000000001","debtorUserId":"25000000-0000-0000-0000-000000000002","currency":"YER","amountMinor":5000}'::jsonb,
 0,1,now()
);
SELECT ledger.decide_operation(
 '65000000-0000-0000-0000-000000000001',
 '15000000-0000-0000-0000-000000000001',
 '35000000-0000-0000-0000-000000000001',
 '25000000-0000-0000-0000-000000000002',
 1,'approved','charge accepted'
);

DO $$
BEGIN
  BEGIN
    PERFORM ledger.request_settlement_reset(
      '85000000-0000-0000-0000-000000000001',
      '15000000-0000-0000-0000-000000000001',
      '25000000-0000-0000-0000-000000000002'
    );
    RAISE EXCEPTION 'Reset request with unpaid balance unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'Cannot request settlement reset:%' THEN RAISE; END IF;
  END;
END;
$$;

SELECT * FROM ledger.accept_operation(
 '35000000-0000-0000-0000-000000000002',
 '15000000-0000-0000-0000-000000000001',
 '25000000-0000-0000-0000-000000000002',
 '75000000-0000-0000-0000-000000000002',
 'payment', decode(repeat('a2',32),'hex'),
 '{"payerUserId":"25000000-0000-0000-0000-000000000002","payeeUserId":"25000000-0000-0000-0000-000000000001","currency":"YER","amountMinor":5000}'::jsonb,
 0,1,now()
);
SELECT ledger.decide_operation(
 '65000000-0000-0000-0000-000000000002',
 '15000000-0000-0000-0000-000000000001',
 '35000000-0000-0000-0000-000000000002',
 '25000000-0000-0000-0000-000000000001',
 1,'approved','payment confirmed'
);

SELECT * FROM ledger.accept_operation(
 '35000000-0000-0000-0000-000000000003',
 '15000000-0000-0000-0000-000000000001',
 '25000000-0000-0000-0000-000000000002',
 '75000000-0000-0000-0000-000000000003',
 'allocation', decode(repeat('a3',32),'hex'),
 jsonb_build_object(
   'paymentId',(SELECT id FROM ledger.payments WHERE source_operation_id='35000000-0000-0000-0000-000000000002'),
   'obligationId',(SELECT id FROM ledger.obligations WHERE source_operation_id='35000000-0000-0000-0000-000000000001'),
   'amountMinor',5000
 ),
 0,1,now()
);
SELECT ledger.decide_operation(
 '65000000-0000-0000-0000-000000000003',
 '15000000-0000-0000-0000-000000000001',
 '35000000-0000-0000-0000-000000000003',
 '25000000-0000-0000-0000-000000000001',
 1,'approved','payment allocated'
);

DO $$
DECLARE req uuid;
BEGIN
  req := ledger.request_settlement_reset(
    '85000000-0000-0000-0000-000000000002',
    '15000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000002'
  );
  IF req <> '85000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'Settlement request id mismatch';
  END IF;
  IF (SELECT count(*) FROM ledger.settlement_requests
      WHERE relationship_id='15000000-0000-0000-0000-000000000001'
        AND status='requested') <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one pending settlement request';
  END IF;
END;
$$;

ROLLBACK;
SELECT 'settlement reset gate tests passed' AS result;
