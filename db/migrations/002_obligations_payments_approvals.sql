-- Relationship-scoped obligations, payments, approvals, and explicit allocations.
-- PostgreSQL 16 prototype. No payment execution or external service integration.

-- Strengthen the source-operation reference: a journal cannot point at an
-- operation belonging to another commercial relationship.
ALTER TABLE ledger.journal_transactions
  ADD CONSTRAINT journal_source_operation_same_relationship_fk
  FOREIGN KEY (relationship_id, source_operation_id)
  REFERENCES ledger.operations (relationship_id, operation_id);

ALTER TABLE ledger.relationship_members
  ADD COLUMN can_approve boolean NOT NULL DEFAULT false;

CREATE TABLE ledger.approvals (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approved', 'rejected')),
  expected_server_version bigint NOT NULL CHECK (expected_server_version > 0),
  resulting_server_version bigint NOT NULL CHECK (resulting_server_version > expected_server_version),
  reason text,
  decided_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (relationship_id, operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id),
  FOREIGN KEY (relationship_id, actor_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  UNIQUE (operation_id, actor_user_id)
);

CREATE TABLE ledger.obligations (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  source_operation_id uuid NOT NULL,
  creditor_user_id uuid NOT NULL,
  debtor_user_id uuid NOT NULL,
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (creditor_user_id <> debtor_user_id),
  FOREIGN KEY (relationship_id, source_operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id),
  FOREIGN KEY (relationship_id, creditor_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  FOREIGN KEY (relationship_id, debtor_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  UNIQUE (source_operation_id),
  UNIQUE (id, relationship_id, currency)
);

CREATE TABLE ledger.payments (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  source_operation_id uuid NOT NULL,
  payer_user_id uuid NOT NULL,
  payee_user_id uuid NOT NULL,
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  status text NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed', 'voided')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (payer_user_id <> payee_user_id),
  FOREIGN KEY (relationship_id, source_operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id),
  FOREIGN KEY (relationship_id, payer_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  FOREIGN KEY (relationship_id, payee_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  UNIQUE (source_operation_id),
  UNIQUE (id, relationship_id, currency)
);

CREATE TABLE ledger.allocations (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  obligation_id uuid NOT NULL,
  source_operation_id uuid NOT NULL UNIQUE,
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (payment_id, relationship_id, currency)
    REFERENCES ledger.payments (id, relationship_id, currency),
  FOREIGN KEY (obligation_id, relationship_id, currency)
    REFERENCES ledger.obligations (id, relationship_id, currency),
  FOREIGN KEY (relationship_id, source_operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id),
  UNIQUE (id, relationship_id, currency)
);

CREATE INDEX obligations_open_by_party_idx
  ON ledger.obligations (relationship_id, debtor_user_id, currency, created_at)
  WHERE status = 'open';
CREATE INDEX payments_by_payer_idx
  ON ledger.payments (relationship_id, payer_user_id, currency, created_at);
CREATE INDEX allocations_by_obligation_idx
  ON ledger.allocations (relationship_id, obligation_id);
CREATE INDEX allocations_by_payment_idx
  ON ledger.allocations (relationship_id, payment_id);

-- Decisions are server-authoritative and compare-and-set on the aggregate version.
CREATE OR REPLACE FUNCTION ledger.decide_operation(
  p_decision_id uuid,
  p_relationship_id uuid,
  p_operation_id uuid,
  p_actor_user_id uuid,
  p_expected_server_version bigint,
  p_decision text,
  p_reason text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  op ledger.operations%ROWTYPE;
  next_version bigint;
BEGIN
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Unsupported decision: %', p_decision USING ERRCODE = '22023';
  END IF;

  SELECT * INTO op
  FROM ledger.operations
  WHERE relationship_id = p_relationship_id AND operation_id = p_operation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Operation not found in relationship' USING ERRCODE = '23503';
  END IF;
  IF op.business_state <> 'awaiting_counterparty' THEN
    RAISE EXCEPTION 'Operation is not awaiting a decision' USING ERRCODE = '55000';
  END IF;
  IF op.server_version <> p_expected_server_version THEN
    RAISE EXCEPTION 'Stale operation version: expected %, current %',
      p_expected_server_version, op.server_version USING ERRCODE = '40001';
  END IF;
  IF op.actor_user_id = p_actor_user_id THEN
    RAISE EXCEPTION 'Creator cannot approve their own operation' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id
      AND user_id = p_actor_user_id
      AND status = 'active'
      AND can_approve = true
  ) THEN
    RAISE EXCEPTION 'Actor lacks active approval permission' USING ERRCODE = '42501';
  END IF;

  next_version := op.server_version + 1;
  INSERT INTO ledger.approvals (
    id, relationship_id, operation_id, actor_user_id, decision,
    expected_server_version, resulting_server_version, reason
  ) VALUES (
    p_decision_id, p_relationship_id, p_operation_id, p_actor_user_id, p_decision,
    p_expected_server_version, next_version, p_reason
  );

  UPDATE ledger.operations
  SET business_state = p_decision, server_version = next_version
  WHERE relationship_id = p_relationship_id AND operation_id = p_operation_id;

  RETURN next_version;
END;
$$;

-- Serialize concurrent allocations by locking both aggregates in a stable order.
-- A payment may remain partially or fully unapplied; no FIFO allocation occurs.
CREATE OR REPLACE FUNCTION ledger.allocate_payment(
  p_allocation_id uuid,
  p_relationship_id uuid,
  p_payment_id uuid,
  p_obligation_id uuid,
  p_source_operation_id uuid,
  p_amount_minor bigint
) RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  pay ledger.payments%ROWTYPE;
  obl ledger.obligations%ROWTYPE;
  payment_allocated numeric;
  obligation_allocated numeric;
  source_op ledger.operations%ROWTYPE;
BEGIN
  IF p_amount_minor IS NULL OR p_amount_minor <= 0 THEN
    RAISE EXCEPTION 'Allocation amount must be positive' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO pay FROM ledger.payments
  WHERE id = p_payment_id AND relationship_id = p_relationship_id
  FOR UPDATE;
  IF NOT FOUND OR pay.status <> 'confirmed' THEN
    RAISE EXCEPTION 'Confirmed payment not found' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO obl FROM ledger.obligations
  WHERE id = p_obligation_id AND relationship_id = p_relationship_id
  FOR UPDATE;
  IF NOT FOUND OR obl.status <> 'open' THEN
    RAISE EXCEPTION 'Open obligation not found' USING ERRCODE = '23503';
  END IF;

  IF pay.currency <> obl.currency OR pay.payer_user_id <> obl.debtor_user_id
     OR pay.payee_user_id <> obl.creditor_user_id THEN
    RAISE EXCEPTION 'Payment and obligation parties/currency do not match'
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO source_op FROM ledger.operations
  WHERE operation_id = p_source_operation_id
    AND relationship_id = p_relationship_id;
  IF NOT FOUND OR source_op.business_state <> 'approved' THEN
    RAISE EXCEPTION 'Allocation source operation must be approved in this relationship'
      USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(sum(amount_minor), 0) INTO payment_allocated
  FROM ledger.allocations WHERE payment_id = p_payment_id;
  SELECT COALESCE(sum(amount_minor), 0) INTO obligation_allocated
  FROM ledger.allocations WHERE obligation_id = p_obligation_id;

  IF payment_allocated + p_amount_minor > pay.amount_minor THEN
    RAISE EXCEPTION 'Allocation exceeds unapplied payment amount' USING ERRCODE = '23514';
  END IF;
  IF obligation_allocated + p_amount_minor > obl.amount_minor THEN
    RAISE EXCEPTION 'Allocation exceeds open obligation amount' USING ERRCODE = '23514';
  END IF;

  INSERT INTO ledger.allocations (
    id, relationship_id, payment_id, obligation_id, source_operation_id, currency, amount_minor
  ) VALUES (
    p_allocation_id, p_relationship_id, p_payment_id, p_obligation_id,
    p_source_operation_id, pay.currency, p_amount_minor
  );

  RETURN p_amount_minor;
END;
$$;

-- Financial facts and allocation history are append-only.
CREATE OR REPLACE FUNCTION ledger.reject_financial_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Financial facts are immutable; append a linked correction'
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER obligations_are_immutable
BEFORE UPDATE OR DELETE ON ledger.obligations
FOR EACH ROW EXECUTE FUNCTION ledger.reject_financial_mutation();
CREATE TRIGGER payments_are_immutable
BEFORE UPDATE OR DELETE ON ledger.payments
FOR EACH ROW EXECUTE FUNCTION ledger.reject_financial_mutation();
CREATE TRIGGER allocations_are_immutable
BEFORE UPDATE OR DELETE ON ledger.allocations
FOR EACH ROW EXECUTE FUNCTION ledger.reject_financial_mutation();
CREATE TRIGGER approvals_are_immutable
BEFORE UPDATE OR DELETE ON ledger.approvals
FOR EACH ROW EXECUTE FUNCTION ledger.reject_financial_mutation();
