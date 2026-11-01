\set ON_ERROR_STOP on

BEGIN;

INSERT INTO ledger.relationships (id, status)
VALUES ('10000000-0000-0000-0000-000000000001', 'active');

INSERT INTO ledger.relationship_members (relationship_id, user_id, role_label, status)
VALUES
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'seller', 'active'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'buyer', 'active');

INSERT INTO ledger.operations (
  operation_id, relationship_id, actor_user_id, operation_type, request_hash,
  business_state, base_version, server_version
) VALUES (
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'credit_charge',
  decode(repeat('ab', 32), 'hex'),
  'approved',
  0,
  1
);

INSERT INTO ledger.accounts (id, relationship_id, owner_user_id, account_type, currency)
VALUES
  ('40000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001',
   'party_receivable', 'YER'),
  ('40000000-0000-0000-0000-000000000002',
   '10000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000002',
   'party_payable', 'YER');

INSERT INTO ledger.journal_transactions (
  id, relationship_id, source_operation_id, currency, description
) VALUES (
  '50000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  'YER',
  'Approved credit charge'
);

INSERT INTO ledger.journal_entries (
  id, journal_transaction_id, relationship_id, currency, account_id, debit_minor, credit_minor
) VALUES
  ('60000000-0000-0000-0000-000000000001',
   '50000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001',
   'YER',
   '40000000-0000-0000-0000-000000000001',
   250000,
   0),
  ('60000000-0000-0000-0000-000000000002',
   '50000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001',
   'YER',
   '40000000-0000-0000-0000-000000000002',
   0,
   250000);

COMMIT;

DO $$
DECLARE
  debit_total numeric;
  credit_total numeric;
BEGIN
  SELECT sum(debit_minor), sum(credit_minor)
    INTO debit_total, credit_total
  FROM ledger.journal_entries
  WHERE journal_transaction_id = '50000000-0000-0000-0000-000000000001';

  IF debit_total <> 250000 OR credit_total <> 250000 THEN
    RAISE EXCEPTION 'Expected balanced 250000 minor-unit posting; got debit %, credit %',
      debit_total, credit_total;
  END IF;

  -- Same operation ID must not be accepted twice.
  BEGIN
    INSERT INTO ledger.operations (
      operation_id, relationship_id, actor_user_id, operation_type, request_hash,
      business_state, base_version, server_version
    ) VALUES (
      '30000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000001',
      'credit_charge',
      decode(repeat('ab', 32), 'hex'),
      'approved',
      0,
      2
    );
    RAISE EXCEPTION 'Duplicate operation_id unexpectedly succeeded';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- Posted journal entries cannot be edited or deleted.
  BEGIN
    UPDATE ledger.journal_entries
      SET debit_minor = 1
      WHERE id = '60000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Journal mutation unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
END;
$$;

-- A YER journal transaction cannot point at a SAR account because the
-- composite foreign key includes relationship and currency.
DO $$
BEGIN
  INSERT INTO ledger.accounts (id, relationship_id, owner_user_id, account_type, currency)
  VALUES (
    '40000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'party_payable',
    'SAR'
  );

  BEGIN
    INSERT INTO ledger.journal_entries (
      id, journal_transaction_id, relationship_id, currency, account_id, debit_minor, credit_minor
    ) VALUES (
      '60000000-0000-0000-0000-000000000003',
      '50000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      'YER',
      '40000000-0000-0000-0000-000000000003',
      100,
      0
    );
    RAISE EXCEPTION 'Cross-currency journal entry unexpectedly succeeded';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
END;
$$;

ROLLBACK;

SELECT 'ledger core tests passed' AS result;
