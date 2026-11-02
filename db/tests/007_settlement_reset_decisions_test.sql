\set ON_ERROR_STOP on
BEGIN;

INSERT INTO ledger.relationships (id, status)
VALUES
 ('16000000-0000-0000-0000-000000000001','active'),
 ('16000000-0000-0000-0000-000000000002','active');

INSERT INTO ledger.relationship_members
 (relationship_id,user_id,role_label,status,can_approve)
VALUES
 ('16000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000001','seller','active',true),
 ('16000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000002','buyer','active',true),
 ('16000000-0000-0000-0000-000000000002','26000000-0000-0000-0000-000000000003','seller','active',true),
 ('16000000-0000-0000-0000-000000000002','26000000-0000-0000-0000-000000000004','buyer','active',true);

-- Party A requests reset after the existing balance gate has passed.
SELECT ledger.request_settlement_reset(
 '86000000-0000-0000-0000-000000000001',
 '16000000-0000-0000-0000-000000000001',
 '26000000-0000-0000-0000-000000000001'
);

DO $$
BEGIN
  -- Pending reset freezes any new business operation from either party.
  BEGIN
    PERFORM * FROM ledger.accept_operation(
      '36000000-0000-0000-0000-000000000001',
      '16000000-0000-0000-0000-000000000001',
      '26000000-0000-0000-0000-000000000002',
      '76000000-0000-0000-0000-000000000001',
      'supply', decode(repeat('b1',32),'hex'),
      '{"description":"must be blocked while reset is pending"}'::jsonb,
      0,1,now()
    );
    RAISE EXCEPTION 'Operation unexpectedly succeeded while reset was pending';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    IF SQLERRM NOT LIKE 'Relationship is frozen%' THEN RAISE; END IF;
  END;

  -- The requester cannot approve their own request.
  BEGIN
    PERFORM ledger.decide_settlement_reset(
      '96000000-0000-0000-0000-000000000001',
      '16000000-0000-0000-0000-000000000001',
      '86000000-0000-0000-0000-000000000001',
      '26000000-0000-0000-0000-000000000001',
      'approved','self approval attempt'
    );
    RAISE EXCEPTION 'Requester unexpectedly decided own reset request';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;

-- Only the other party can approve; approval starts a new white page.
DO $$
DECLARE decision_result text;
BEGIN
  decision_result := ledger.decide_settlement_reset(
    '96000000-0000-0000-0000-000000000002',
    '16000000-0000-0000-0000-000000000001',
    '86000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000002',
    'approved','All obligations settled'
  );
  IF decision_result <> 'approved' THEN
    RAISE EXCEPTION 'Expected approved result, got %', decision_result;
  END IF;

  -- Exact retry returns the original decision without creating another event.
  decision_result := ledger.decide_settlement_reset(
    '96000000-0000-0000-0000-000000000002',
    '16000000-0000-0000-0000-000000000001',
    '86000000-0000-0000-0000-000000000001',
    '26000000-0000-0000-0000-000000000002',
    'approved','All obligations settled'
  );
  IF decision_result <> 'approved' THEN
    RAISE EXCEPTION 'Idempotent decision retry failed';
  END IF;

  IF (SELECT status FROM ledger.relationships
      WHERE id='16000000-0000-0000-0000-000000000001') <> 'active'
     OR (SELECT closed_at FROM ledger.relationships
         WHERE id='16000000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION 'Approved reset did not close relationship';
  END IF;

  -- A delayed retry of the original request remains idempotent after closure.
  IF ledger.request_settlement_reset(
       '86000000-0000-0000-0000-000000000001',
       '16000000-0000-0000-0000-000000000001',
       '26000000-0000-0000-0000-000000000001'
     ) <> '86000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'Settlement request retry after closure was not idempotent';
  END IF;

  IF (SELECT count(*) FROM ledger.settlement_decisions
      WHERE request_id='86000000-0000-0000-0000-000000000001') <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one immutable settlement decision';
  END IF;

  IF (SELECT count(*) FROM ledger.relationship_events
      WHERE relationship_id='16000000-0000-0000-0000-000000000001'
        AND event_type IN ('settlement.reset_requested','settlement.reset_approved')) <> 2 THEN
    RAISE EXCEPTION 'Expected request and approval events in the sync feed';
  END IF;
END;
$$;

DO $$
BEGIN
  BEGIN
    PERFORM * FROM ledger.accept_operation(
      '36000000-0000-0000-0000-000000000002',
      '16000000-0000-0000-0000-000000000001',
      '26000000-0000-0000-0000-000000000002',
      '76000000-0000-0000-0000-000000000002',
      'supply', decode(repeat('b2',32),'hex'),
      '{"description":"closed relationship"}'::jsonb,
      0,1,now()
    );
    RAISE EXCEPTION 'Operation unexpectedly succeeded after relationship closure';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    IF SQLERRM <> 'Relationship is not active' THEN RAISE; END IF;
  END;
END;
$$;

-- A rejected request is also immutable, but the relationship remains usable.
SELECT ledger.request_settlement_reset(
 '86000000-0000-0000-0000-000000000002',
 '16000000-0000-0000-0000-000000000002',
 '26000000-0000-0000-0000-000000000003'
);

DO $$
DECLARE decision_result text;
BEGIN
  decision_result := ledger.decide_settlement_reset(
    '96000000-0000-0000-0000-000000000003',
    '16000000-0000-0000-0000-000000000002',
    '86000000-0000-0000-0000-000000000002',
    '26000000-0000-0000-0000-000000000004',
    'rejected','Account must remain open'
  );
  IF decision_result <> 'rejected' THEN
    RAISE EXCEPTION 'Expected rejected result';
  END IF;

  decision_result := ledger.decide_settlement_reset(
    '96000000-0000-0000-0000-000000000003',
    '16000000-0000-0000-0000-000000000002',
    '86000000-0000-0000-0000-000000000002',
    '26000000-0000-0000-0000-000000000004',
    'rejected','Account must remain open'
  );
  IF decision_result <> 'rejected' THEN
    RAISE EXCEPTION 'Rejected decision retry was not idempotent';
  END IF;

  IF (SELECT status FROM ledger.relationships
      WHERE id='16000000-0000-0000-0000-000000000002') <> 'active' THEN
    RAISE EXCEPTION 'Rejected reset unexpectedly closed relationship';
  END IF;

  IF (SELECT count(*) FROM ledger.relationship_events
      WHERE relationship_id='16000000-0000-0000-0000-000000000002'
        AND event_type IN ('settlement.reset_requested','settlement.reset_rejected')) <> 2 THEN
    RAISE EXCEPTION 'Expected request and rejection events in the sync feed';
  END IF;
END;
$$;

-- Rejection releases the freeze; normal offline-synced operations can resume.
SELECT * FROM ledger.accept_operation(
 '36000000-0000-0000-0000-000000000003',
 '16000000-0000-0000-0000-000000000002',
 '26000000-0000-0000-0000-000000000004',
 '76000000-0000-0000-0000-000000000003',
 'supply', decode(repeat('b3',32),'hex'),
 '{"description":"allowed after reset rejection"}'::jsonb,
 0,1,now()
);

ROLLBACK;
SELECT 'bilateral settlement reset decision tests passed' AS result;

-- White-page test update in progress.
