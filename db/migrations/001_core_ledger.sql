-- Shared commercial ledger: first PostgreSQL journal prototype.
-- This is a prototype migration, not yet a production-ready application schema.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS ledger;

CREATE TABLE ledger.relationships (
  id uuid PRIMARY KEY,
  status text NOT NULL CHECK (status IN ('active', 'suspended', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ledger.relationship_members (
  relationship_id uuid NOT NULL REFERENCES ledger.relationships(id),
  user_id uuid NOT NULL,
  role_label text NOT NULL,
  status text NOT NULL CHECK (status IN ('invited', 'active', 'suspended', 'left')),
  PRIMARY KEY (relationship_id, user_id)
);

CREATE TABLE ledger.operations (
  operation_id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  operation_type text NOT NULL,
  request_hash bytea NOT NULL,
  business_state text NOT NULL CHECK (
    business_state IN ('awaiting_counterparty', 'approved', 'rejected', 'disputed', 'cancelled')
  ),
  base_version bigint NOT NULL CHECK (base_version >= 0),
  server_version bigint NOT NULL CHECK (server_version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (relationship_id, actor_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  UNIQUE (relationship_id, operation_id)
);

CREATE TABLE ledger.journal_transactions (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  source_operation_id uuid NOT NULL UNIQUE REFERENCES ledger.operations(operation_id),
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  description text NOT NULL,
  posted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, relationship_id, currency)
);

CREATE TABLE ledger.accounts (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  owner_user_id uuid NOT NULL,
  account_type text NOT NULL CHECK (
    account_type IN (
      'party_receivable',
      'party_payable',
      'unapplied_payment_asset',
      'unapplied_payment_liability'
    )
  ),
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (relationship_id, owner_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  UNIQUE (relationship_id, owner_user_id, account_type, currency),
  UNIQUE (id, relationship_id, currency)
);

CREATE TABLE ledger.journal_entries (
  id uuid PRIMARY KEY,
  journal_transaction_id uuid NOT NULL,
  relationship_id uuid NOT NULL,
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  account_id uuid NOT NULL,
  debit_minor bigint NOT NULL DEFAULT 0 CHECK (debit_minor >= 0),
  credit_minor bigint NOT NULL DEFAULT 0 CHECK (credit_minor >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (journal_transaction_id, relationship_id, currency)
    REFERENCES ledger.journal_transactions (id, relationship_id, currency),
  FOREIGN KEY (account_id, relationship_id, currency)
    REFERENCES ledger.accounts (id, relationship_id, currency),
  CHECK (
    (debit_minor > 0 AND credit_minor = 0)
    OR (credit_minor > 0 AND debit_minor = 0)
  )
);

-- A journal transaction is valid only when its final set of entries balances.
-- Deferred triggers evaluate the final transaction contents at COMMIT.
CREATE OR REPLACE FUNCTION ledger.assert_journal_balanced()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  target_id uuid;
  entry_count bigint;
  debit_total numeric;
  credit_total numeric;
BEGIN
  IF TG_TABLE_NAME = 'journal_transactions' THEN
    target_id := NEW.id;
  ELSE
    target_id := NEW.journal_transaction_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ledger.journal_transactions WHERE id = target_id
  ) THEN
    RETURN NULL;
  END IF;

  SELECT count(*), COALESCE(sum(debit_minor), 0), COALESCE(sum(credit_minor), 0)
    INTO entry_count, debit_total, credit_total
  FROM ledger.journal_entries
  WHERE journal_transaction_id = target_id;

  IF entry_count < 2 OR debit_total <= 0 OR debit_total <> credit_total THEN
    RAISE EXCEPTION 'Journal transaction % is not balanced (entries %, debit %, credit %)',
      target_id, entry_count, debit_total, credit_total
      USING ERRCODE = '23514';
  END IF;

  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER journal_transaction_must_balance
AFTER INSERT ON ledger.journal_transactions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION ledger.assert_journal_balanced();

CREATE CONSTRAINT TRIGGER journal_entries_must_balance
AFTER INSERT ON ledger.journal_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION ledger.assert_journal_balanced();

-- Posted journal history is append-only. Correct it with a new linked transaction.
CREATE OR REPLACE FUNCTION ledger.reject_journal_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Posted journal rows are immutable; append a compensating transaction'
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER journal_transactions_are_immutable
BEFORE UPDATE OR DELETE ON ledger.journal_transactions
FOR EACH ROW EXECUTE FUNCTION ledger.reject_journal_mutation();

CREATE TRIGGER journal_entries_are_immutable
BEFORE UPDATE OR DELETE ON ledger.journal_entries
FOR EACH ROW EXECUTE FUNCTION ledger.reject_journal_mutation();

CREATE INDEX relationship_operations_sync_idx
  ON ledger.operations (relationship_id, server_version);

CREATE INDEX relationship_journal_history_idx
  ON ledger.journal_transactions (relationship_id, posted_at DESC, id);

CREATE INDEX relationship_journal_entries_idx
  ON ledger.journal_entries (relationship_id, journal_transaction_id);
