-- Step 9: financial completion.
-- Defines the explicit payload fields per operation type:
-- credit_charge: { creditorUserId, debtorUserId, currency, amountMinor }
-- payment: { payerUserId, payeeUserId, currency, amountMinor }
-- allocation: { paymentId, obligationId, amountMinor }
-- sales_return: { originalObligationId, currency, amountMinor, reason? }
-- refund: { originalSalesReturnId, currency, amountMinor, reason? }
-- reversal: { originalOperationId, currency, amountMinor?, reason? }
-- credit_application: { creditSourceOperationId, targetObligationId, currency, amountMinor, reason? }
-- Attachments are not stored in v1; attachment metadata may be carried in payload.reason or a future attachments table.

ALTER TABLE ledger.obligations
  ADD COLUMN IF NOT EXISTS credit_applied_minor bigint NOT NULL DEFAULT 0
  CHECK (credit_applied_minor >= 0);

COMMENT ON COLUMN ledger.obligations.credit_applied_minor IS 'Amount of the obligation settled by approved credit applications from sales-return credits. Allocations plus credit applications must not exceed the obligation amount.';

CREATE TABLE ledger.refunds (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  source_operation_id uuid NOT NULL UNIQUE REFERENCES ledger.operations(operation_id),
  original_sales_return_operation_id uuid NOT NULL REFERENCES ledger.operations(operation_id),
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (relationship_id, source_operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id),
  UNIQUE (id, relationship_id, currency)
);
COMMENT ON TABLE ledger.refunds IS 'Independent refund operations linked to an approved sales return. Refunds cancel return credit in whole or part; they are not allocations.';
CREATE INDEX refunds_by_return_idx ON ledger.refunds(relationship_id, original_sales_return_operation_id, created_at);

CREATE TABLE ledger.reversals (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  source_operation_id uuid NOT NULL UNIQUE REFERENCES ledger.operations(operation_id),
  original_operation_id uuid NOT NULL REFERENCES ledger.operations(operation_id),
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (relationship_id, source_operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id),
  UNIQUE (original_operation_id),
  UNIQUE (id, relationship_id, currency)
);
COMMENT ON TABLE ledger.reversals IS 'Compensating reversal operations linked to an original approved financial operation. The reversal posts compensating journal entries; the original operation remains immutable.';
CREATE INDEX reversals_by_original_idx ON ledger.reversals(relationship_id, original_operation_id, created_at);

CREATE TABLE ledger.credit_applications (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL,
  source_operation_id uuid NOT NULL UNIQUE REFERENCES ledger.operations(operation_id),
  credit_source_operation_id uuid NOT NULL REFERENCES ledger.operations(operation_id),
  target_obligation_id uuid NOT NULL REFERENCES ledger.obligations(id),
  currency char(3) NOT NULL CHECK (currency IN ('YER', 'SAR', 'USD')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (relationship_id, source_operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id),
  FOREIGN KEY (target_obligation_id, relationship_id, currency)
    REFERENCES ledger.obligations (id, relationship_id, currency),
  UNIQUE (id, relationship_id, currency)
);
COMMENT ON TABLE ledger.credit_applications IS 'Explicit application of an approved sales-return credit balance to a future obligation of the same debtor and currency.';
CREATE INDEX credit_applications_by_return_idx ON ledger.credit_applications(relationship_id, credit_source_operation_id, created_at);
CREATE INDEX credit_applications_by_obligation_idx ON ledger.credit_applications(relationship_id, target_obligation_id, created_at);

CREATE OR REPLACE FUNCTION ledger.post_refund_to_journal()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  obl ledger.obligations%ROWTYPE;
  seller_receivable uuid;
  buyer_payable uuid;
  journal_id uuid;
BEGIN
  SELECT * INTO obl FROM ledger.obligations
  WHERE id = (SELECT original_obligation_id FROM ledger.sales_returns
              WHERE source_operation_id = NEW.original_sales_return_operation_id)
    AND relationship_id = NEW.relationship_id
    AND currency = NEW.currency;

  seller_receivable := ledger.get_or_create_account(NEW.relationship_id, obl.creditor_user_id, 'party_receivable', NEW.currency);
  buyer_payable := ledger.get_or_create_account(NEW.relationship_id, obl.debtor_user_id, 'party_payable', NEW.currency);

  journal_id := gen_random_uuid();
  INSERT INTO ledger.journal_transactions
    (id, relationship_id, source_operation_id, currency, description)
  VALUES
    (journal_id, NEW.relationship_id, NEW.source_operation_id, NEW.currency, 'Cash refund of approved sales return');

  INSERT INTO ledger.journal_entries
    (id, journal_transaction_id, relationship_id, currency, account_id, debit_minor, credit_minor)
  VALUES
    (gen_random_uuid(), journal_id, NEW.relationship_id, NEW.currency, seller_receivable, NEW.amount_minor, 0),
    (gen_random_uuid(), journal_id, NEW.relationship_id, NEW.currency, buyer_payable, 0, NEW.amount_minor);
  RETURN NEW;
END; $$;
CREATE TRIGGER refunds_post_to_journal
AFTER INSERT ON ledger.refunds
FOR EACH ROW EXECUTE FUNCTION ledger.post_refund_to_journal();

CREATE OR REPLACE FUNCTION ledger.apply_credit_application_to_obligation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE ledger.obligations
  SET credit_applied_minor = credit_applied_minor + NEW.amount_minor
  WHERE id = NEW.target_obligation_id
    AND relationship_id = NEW.relationship_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target obligation not found' USING ERRCODE = '23503';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER credit_applications_update_obligation_credit
AFTER INSERT ON ledger.credit_applications
FOR EACH ROW EXECUTE FUNCTION ledger.apply_credit_application_to_obligation();

CREATE OR REPLACE FUNCTION ledger.post_reversal_to_journal()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  journal_id uuid;
BEGIN
  journal_id := gen_random_uuid();
  INSERT INTO ledger.journal_transactions
    (id, relationship_id, source_operation_id, currency, description)
  SELECT gen_random_uuid(), NEW.relationship_id, NEW.source_operation_id, NEW.currency,
         'Reversal of operation ' || NEW.original_operation_id::text
  FROM ledger.operations
  WHERE operation_id = NEW.original_operation_id AND relationship_id = NEW.relationship_id
  LIMIT 1;

  INSERT INTO ledger.journal_entries
    (id, journal_transaction_id, relationship_id, currency, account_id, debit_minor, credit_minor)
  SELECT
    gen_random_uuid(), journal_id, je.relationship_id, je.currency, je.account_id,
    je.credit_minor, je.debit_minor
  FROM ledger.journal_transactions jt
  JOIN ledger.journal_entries je ON je.journal_transaction_id = jt.id
  WHERE jt.source_operation_id = NEW.original_operation_id
    AND jt.relationship_id = NEW.relationship_id;
  RETURN NEW;
END; $$;
CREATE TRIGGER reversals_post_to_journal
AFTER INSERT ON ledger.reversals
FOR EACH ROW EXECUTE FUNCTION ledger.post_reversal_to_journal();

CREATE OR REPLACE FUNCTION ledger.guard_refund_limits()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  return_amount numeric;
  applied numeric;
  refunded numeric;
BEGIN
  SELECT amount_minor::numeric INTO return_amount
  FROM ledger.sales_returns
  WHERE source_operation_id = NEW.original_sales_return_operation_id
    AND relationship_id = NEW.relationship_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original sales return not found' USING ERRCODE = '23503';
  END IF;

  SELECT COALESCE(sum(amount_minor),0)::numeric INTO applied
  FROM ledger.credit_applications WHERE credit_source_operation_id = NEW.original_sales_return_operation_id;

  SELECT COALESCE(sum(amount_minor),0)::numeric INTO refunded
  FROM ledger.refunds WHERE original_sales_return_operation_id = NEW.original_sales_return_operation_id;

  IF NEW.amount_minor::numeric > return_amount - applied - refunded THEN
    RAISE EXCEPTION 'Refund exceeds remaining return credit' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER refunds_respect_return_credit_limits
BEFORE INSERT ON ledger.refunds
FOR EACH ROW EXECUTE FUNCTION ledger.guard_refund_limits();

CREATE OR REPLACE FUNCTION ledger.guard_credit_application_limits()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  src_op ledger.operations%ROWTYPE;
  src_return ledger.sales_returns%ROWTYPE;
  src_obl ledger.obligations%ROWTYPE;
  obl ledger.obligations%ROWTYPE;
  return_amount numeric;
  used_credit numeric;
  refunded numeric;
  obligation_allocated numeric;
  obligation_credited numeric;
  obligation_remainder numeric;
  src_debtor uuid;
BEGIN
  SELECT * INTO src_op FROM ledger.operations
  WHERE operation_id = NEW.credit_source_operation_id
    AND relationship_id = NEW.relationship_id;
  IF NOT FOUND OR src_op.business_state <> 'approved'
     OR src_op.operation_type <> 'sales_return' THEN
    RAISE EXCEPTION 'Credit source must be an approved sales return' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO src_return FROM ledger.sales_returns
  WHERE source_operation_id = NEW.credit_source_operation_id
    AND relationship_id = NEW.relationship_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sales return record not found' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO obl FROM ledger.obligations
  WHERE id = NEW.target_obligation_id AND relationship_id = NEW.relationship_id AND currency = NEW.currency;
  IF NOT FOUND OR obl.status <> 'open' THEN
    RAISE EXCEPTION 'Open target obligation not found' USING ERRCODE = '23503';
  END IF;

  SELECT debtor_user_id INTO src_debtor
  FROM ledger.obligations
  WHERE id = src_return.original_obligation_id
    AND relationship_id = src_return.relationship_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original obligation not found' USING ERRCODE = '23503';
  END IF;

  IF obl.debtor_user_id <> src_debtor THEN
    -- The debtor of the target obligation must be the party that received the return credit.
    RAISE EXCEPTION 'Target obligation debtor does not match the return credit beneficiary' USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(sum(amount_minor),0)::numeric INTO return_amount
  FROM ledger.sales_returns
  WHERE original_obligation_id = src_return.original_obligation_id
    AND relationship_id = NEW.relationship_id;
  SELECT COALESCE(sum(amount_minor),0)::numeric INTO used_credit
  FROM ledger.credit_applications WHERE credit_source_operation_id = NEW.credit_source_operation_id;
  SELECT COALESCE(sum(amount_minor),0)::numeric INTO refunded
  FROM ledger.refunds WHERE original_sales_return_operation_id = NEW.credit_source_operation_id;
  SELECT COALESCE(sum(amount_minor),0)::numeric INTO obligation_allocated
  FROM ledger.allocations WHERE obligation_id = NEW.target_obligation_id;
  SELECT COALESCE(sum(amount_minor),0)::numeric INTO obligation_credited
  FROM ledger.credit_applications WHERE target_obligation_id = NEW.target_obligation_id;

  obligation_remainder := obl.amount_minor - obligation_allocated - obligation_credited;

  IF NEW.amount_minor::numeric > return_amount - used_credit - refunded THEN
    RAISE EXCEPTION 'Credit application exceeds remaining return credit' USING ERRCODE = '23514';
  END IF;
  IF NEW.amount_minor::numeric > obligation_remainder THEN
    RAISE EXCEPTION 'Credit application exceeds target obligation remainder' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER credit_applications_respect_limits
BEFORE INSERT ON ledger.credit_applications
FOR EACH ROW EXECUTE FUNCTION ledger.guard_credit_application_limits();

CREATE OR REPLACE FUNCTION ledger.guard_reversal_limits()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  op ledger.operations%ROWTYPE;
BEGIN
  SELECT * INTO op FROM ledger.operations
  WHERE operation_id = NEW.original_operation_id AND relationship_id = NEW.relationship_id;
  IF NOT FOUND OR op.business_state <> 'approved' THEN
    RAISE EXCEPTION 'Original operation must be approved' USING ERRCODE = '23503';
  END IF;
  IF op.operation_type = 'reversal' THEN
    RAISE EXCEPTION 'A reversal cannot be reversed' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER reversals_respect_limits
BEFORE INSERT ON ledger.reversals
FOR EACH ROW EXECUTE FUNCTION ledger.guard_reversal_limits();

-- Allow approved credit applications to update only the obligation credit applied column;
-- all other obligation fields remain immutable.
DROP TRIGGER IF EXISTS obligations_are_immutable ON ledger.obligations;
CREATE OR REPLACE FUNCTION ledger.obligations_immutable_except_credit_applied()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.amount_minor IS DISTINCT FROM OLD.amount_minor OR
     NEW.status IS DISTINCT FROM OLD.status OR
     NEW.creditor_user_id IS DISTINCT FROM OLD.creditor_user_id OR
     NEW.debtor_user_id IS DISTINCT FROM OLD.debtor_user_id OR
     NEW.currency IS DISTINCT FROM OLD.currency OR
     NEW.relationship_id IS DISTINCT FROM OLD.relationship_id OR
     NEW.source_operation_id IS DISTINCT FROM OLD.source_operation_id THEN
    RAISE EXCEPTION 'Financial facts are immutable; append a linked correction'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER obligations_are_immutable
BEFORE UPDATE ON ledger.obligations
FOR EACH ROW EXECUTE FUNCTION ledger.obligations_immutable_except_credit_applied();

CREATE OR REPLACE FUNCTION ledger.accept_operation(
 p_operation_id uuid,p_relationship_id uuid,p_actor_user_id uuid,p_device_id uuid,
 p_operation_type text,p_request_hash bytea,p_payload jsonb,p_base_version bigint,
 p_schema_version integer,p_client_created_at timestamptz
) RETURNS TABLE(outcome text,canonical_operation_id uuid,business_state text,
 server_version bigint,server_sequence bigint,server_created_at timestamptz)
LANGUAGE plpgsql AS $$
DECLARE x ledger.operations%ROWTYPE; n bigint; t timestamptz:=clock_timestamp();
BEGIN
 IF p_request_hash IS NULL OR octet_length(p_request_hash)<>32 OR p_payload IS NULL
 OR jsonb_typeof(p_payload)<>'object' OR p_base_version<0 OR p_schema_version<>1
 OR p_operation_type NOT IN ('credit_charge','payment','allocation','supply','sales_return','refund','reversal','credit_application') THEN
  RAISE EXCEPTION 'Invalid operation envelope' USING ERRCODE='23514';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_operation_id::text,0));
 SELECT * INTO x FROM ledger.operations WHERE operation_id=p_operation_id FOR UPDATE;
 IF FOUND THEN
  IF x.relationship_id=p_relationship_id AND x.actor_user_id=p_actor_user_id
   AND x.device_id=p_device_id AND x.operation_type=p_operation_type AND x.request_hash=p_request_hash THEN
   RETURN QUERY SELECT 'already_processed'::text,x.operation_id,x.business_state,x.server_version,x.server_sequence,x.created_at; RETURN;
  END IF;
  RAISE EXCEPTION 'Operation id reused with different envelope' USING ERRCODE='23505';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ledger.relationship_members WHERE relationship_id=p_relationship_id AND user_id=p_actor_user_id AND status='active') THEN
  RAISE EXCEPTION 'Actor is not an active relationship member' USING ERRCODE='42501';
 END IF;
 n:=ledger.next_relationship_sequence(p_relationship_id);
 INSERT INTO ledger.operations(operation_id,relationship_id,actor_user_id,operation_type,request_hash,business_state,
 base_version,server_version,device_id,client_schema_version,client_created_at,operation_payload,server_sequence,created_at)
 VALUES(p_operation_id,p_relationship_id,p_actor_user_id,p_operation_type,p_request_hash,'awaiting_counterparty',
 p_base_version,1,p_device_id,p_schema_version,p_client_created_at,p_payload,n,t);
 INSERT INTO ledger.relationship_events(relationship_id,server_sequence,event_id,operation_id,event_type,event_payload)
 VALUES(p_relationship_id,n,gen_random_uuid(),p_operation_id,'operation.created',
 jsonb_build_object('operationId',p_operation_id,'operationType',p_operation_type,'businessState','awaiting_counterparty','serverVersion',1,'payload',p_payload));
 RETURN QUERY SELECT 'accepted'::text,p_operation_id,'awaiting_counterparty'::text,1::bigint,n,t;
END; $$;

CREATE OR REPLACE FUNCTION ledger.append_operation_state_event()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  next_sequence bigint;
  approval_row ledger.approvals%ROWTYPE;
  payload jsonb;
BEGIN
  IF OLD.business_state IS NOT DISTINCT FROM NEW.business_state
     AND OLD.server_version = NEW.server_version THEN
    RETURN NEW;
  END IF;

  IF OLD.business_state <> 'approved' AND NEW.business_state = 'approved' THEN
    CASE NEW.operation_type
      WHEN 'credit_charge' THEN
        INSERT INTO ledger.obligations (
          id, relationship_id, source_operation_id, creditor_user_id, debtor_user_id,
          currency, amount_minor
        ) VALUES (
          gen_random_uuid(), NEW.relationship_id, NEW.operation_id,
          (NEW.operation_payload->>'creditorUserId')::uuid,
          (NEW.operation_payload->>'debtorUserId')::uuid,
          (NEW.operation_payload->>'currency')::char(3),
          (NEW.operation_payload->>'amountMinor')::bigint
        );
      WHEN 'payment' THEN
        INSERT INTO ledger.payments (
          id, relationship_id, source_operation_id, payer_user_id, payee_user_id,
          currency, amount_minor
        ) VALUES (
          gen_random_uuid(), NEW.relationship_id, NEW.operation_id,
          (NEW.operation_payload->>'payerUserId')::uuid,
          (NEW.operation_payload->>'payeeUserId')::uuid,
          (NEW.operation_payload->>'currency')::char(3),
          (NEW.operation_payload->>'amountMinor')::bigint
        );
      WHEN 'allocation' THEN
        PERFORM ledger.allocate_payment(
          gen_random_uuid(), NEW.relationship_id,
          (NEW.operation_payload->>'paymentId')::uuid,
          (NEW.operation_payload->>'obligationId')::uuid,
          NEW.operation_id,
          (NEW.operation_payload->>'amountMinor')::bigint
        );
      WHEN 'sales_return' THEN
        NULL; -- Materialized by operations_materialize_sales_return.
      WHEN 'refund' THEN
        INSERT INTO ledger.refunds (
          id, relationship_id, source_operation_id, original_sales_return_operation_id,
          currency, amount_minor, reason
        ) VALUES (
          gen_random_uuid(), NEW.relationship_id, NEW.operation_id,
          (NEW.operation_payload->>'originalSalesReturnId')::uuid,
          (NEW.operation_payload->>'currency')::char(3),
          (NEW.operation_payload->>'amountMinor')::bigint,
          NULLIF(NEW.operation_payload->>'reason','')
        );
      WHEN 'reversal' THEN
        INSERT INTO ledger.reversals (
          id, relationship_id, source_operation_id, original_operation_id,
          currency, amount_minor, reason
        ) VALUES (
          gen_random_uuid(), NEW.relationship_id, NEW.operation_id,
          (NEW.operation_payload->>'originalOperationId')::uuid,
          (NEW.operation_payload->>'currency')::char(3),
          NULLIF((NEW.operation_payload->>'amountMinor')::bigint,0),
          NULLIF(NEW.operation_payload->>'reason','')
        );
      WHEN 'credit_application' THEN
        INSERT INTO ledger.credit_applications (
          id, relationship_id, source_operation_id, credit_source_operation_id,
          target_obligation_id, currency, amount_minor, reason
        ) VALUES (
          gen_random_uuid(), NEW.relationship_id, NEW.operation_id,
          (NEW.operation_payload->>'creditSourceOperationId')::uuid,
          (NEW.operation_payload->>'targetObligationId')::uuid,
          (NEW.operation_payload->>'currency')::char(3),
          (NEW.operation_payload->>'amountMinor')::bigint,
          NULLIF(NEW.operation_payload->>'reason','')
        );
      ELSE
        NULL;
    END CASE;
  END IF;

  SELECT * INTO approval_row FROM ledger.approvals
  WHERE relationship_id = NEW.relationship_id AND operation_id = NEW.operation_id
  ORDER BY decided_at DESC LIMIT 1;

  next_sequence := ledger.next_relationship_sequence(NEW.relationship_id);
  payload := jsonb_build_object(
    'operationId', NEW.operation_id,
    'businessState', NEW.business_state,
    'serverVersion', NEW.server_version
  );
  IF approval_row.id IS NOT NULL THEN
    payload := payload || jsonb_build_object(
      'decisionId', approval_row.id,
      'decisionActorId', approval_row.actor_user_id,
      'decision', approval_row.decision,
      'reason', approval_row.reason
    );
  END IF;

  INSERT INTO ledger.relationship_events (
    relationship_id, server_sequence, event_id, operation_id, event_type, event_payload
  ) VALUES (
    NEW.relationship_id, next_sequence, gen_random_uuid(), NEW.operation_id,
    'operation.state_changed', payload
  );
  RETURN NEW;
END; $$;

-- Obligation remainder now accounts for credit applications as well as allocations.
CREATE OR REPLACE FUNCTION ledger.allocate_payment(
  p_allocation_id uuid,
  p_relationship_id uuid,
  p_payment_id uuid,
  p_obligation_id uuid,
  p_source_operation_id uuid,
  p_amount_minor bigint
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  pay ledger.payments%ROWTYPE;
  obl ledger.obligations%ROWTYPE;
  payment_allocated numeric;
  obligation_allocated numeric;
  obligation_credited numeric;
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
    RAISE EXCEPTION 'Payment and obligation parties/currency do not match' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO source_op FROM ledger.operations
  WHERE operation_id = p_source_operation_id
    AND relationship_id = p_relationship_id;
  IF NOT FOUND OR source_op.business_state <> 'approved' THEN
    RAISE EXCEPTION 'Allocation source operation must be approved in this relationship' USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(sum(amount_minor), 0) INTO payment_allocated
  FROM ledger.allocations WHERE payment_id = p_payment_id;
  SELECT COALESCE(sum(amount_minor), 0) INTO obligation_allocated
  FROM ledger.allocations WHERE obligation_id = p_obligation_id;
  SELECT COALESCE(sum(amount_minor), 0) INTO obligation_credited
  FROM ledger.credit_applications WHERE target_obligation_id = p_obligation_id;

  IF payment_allocated + p_amount_minor > pay.amount_minor THEN
    RAISE EXCEPTION 'Allocation exceeds unapplied payment amount' USING ERRCODE = '23514';
  END IF;
  IF obligation_allocated + p_amount_minor > obl.amount_minor - COALESCE(obligation_credited,0) THEN
    RAISE EXCEPTION 'Allocation exceeds open obligation remainder' USING ERRCODE = '23514';
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

CREATE OR REPLACE FUNCTION ledger.assert_allocation_within_bounds()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  pay ledger.payments%ROWTYPE;
  obl ledger.obligations%ROWTYPE;
  op ledger.operations%ROWTYPE;
  used_payment numeric;
  used_obligation numeric;
  obligation_credited numeric;
BEGIN
  SELECT * INTO pay FROM ledger.payments
  WHERE id = NEW.payment_id AND relationship_id = NEW.relationship_id
  FOR UPDATE;
  SELECT * INTO obl FROM ledger.obligations
  WHERE id = NEW.obligation_id AND relationship_id = NEW.relationship_id
  FOR UPDATE;
  SELECT * INTO op FROM ledger.operations
  WHERE operation_id = NEW.source_operation_id
    AND relationship_id = NEW.relationship_id;

  IF pay.id IS NULL OR obl.id IS NULL OR pay.status <> 'confirmed' OR obl.status <> 'open' THEN
    RAISE EXCEPTION 'Allocation requires a confirmed payment and open obligation' USING ERRCODE = '23514';
  END IF;
  IF op.operation_id IS NULL OR op.business_state <> 'approved'
     OR op.operation_type <> 'allocation'
     OR op.actor_user_id NOT IN (pay.payer_user_id, pay.payee_user_id) THEN
    RAISE EXCEPTION 'Allocation requires an approved allocation operation by a party' USING ERRCODE = '42501';
  END IF;
  IF NEW.currency <> pay.currency OR pay.currency <> obl.currency
     OR pay.payer_user_id <> obl.debtor_user_id
     OR pay.payee_user_id <> obl.creditor_user_id THEN
    RAISE EXCEPTION 'Allocation parties and currency must match' USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(sum(amount_minor),0) INTO used_payment
  FROM ledger.allocations WHERE payment_id = NEW.payment_id;
  SELECT COALESCE(sum(amount_minor),0) INTO used_obligation
  FROM ledger.allocations WHERE obligation_id = NEW.obligation_id;
  SELECT COALESCE(sum(amount_minor),0) INTO obligation_credited
  FROM ledger.credit_applications WHERE target_obligation_id = NEW.obligation_id;

  IF used_payment + NEW.amount_minor > pay.amount_minor
     OR used_obligation + NEW.amount_minor > obl.amount_minor - COALESCE(obligation_credited,0) THEN
    RAISE EXCEPTION 'Allocation exceeds payment or obligation remainder' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

-- White-page reset must treat credit applied to an obligation as settled.
CREATE OR REPLACE FUNCTION ledger.request_settlement_reset(
  p_request_id uuid,
  p_relationship_id uuid,
  p_actor_user_id uuid
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  prior ledger.settlement_requests%ROWTYPE;
  cycle_id_now uuid;
  active_members bigint;
  outstanding_obligations numeric;
  unapplied_payments numeric;
  pending_operations bigint;
BEGIN
  PERFORM 1 FROM ledger.relationships
  WHERE id = p_relationship_id AND status = 'active'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active relationship not found' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO prior FROM ledger.settlement_requests WHERE id = p_request_id;
  IF FOUND THEN
    IF prior.relationship_id = p_relationship_id
       AND prior.requested_by_user_id = p_actor_user_id THEN
      RETURN prior.id;
    END IF;
    RAISE EXCEPTION 'Settlement request id reused with different content' USING ERRCODE = '23505';
  END IF;

  SELECT current_cycle_id INTO cycle_id_now
  FROM ledger.relationships WHERE id = p_relationship_id;

  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id AND user_id = p_actor_user_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Requester is not an active relationship member' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO active_members FROM ledger.relationship_members
  WHERE relationship_id = p_relationship_id AND status = 'active';
  IF active_members <> 2 THEN
    RAISE EXCEPTION 'White-page reset requires exactly two active parties' USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1 FROM ledger.settlement_requests sr
    LEFT JOIN ledger.settlement_decisions sd ON sd.request_id = sr.id
    WHERE sr.relationship_id = p_relationship_id AND sd.request_id IS NULL
  ) THEN
    RAISE EXCEPTION 'A settlement reset request is already awaiting a decision' USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(sum(o.amount_minor - COALESCE(a.allocated, 0) - COALESCE(o.credit_applied_minor, 0)), 0)
  INTO outstanding_obligations
  FROM ledger.obligations o
  JOIN ledger.operations op ON op.operation_id = o.source_operation_id
  LEFT JOIN (
    SELECT obligation_id, sum(amount_minor) AS allocated
    FROM ledger.allocations WHERE relationship_id = p_relationship_id
    GROUP BY obligation_id
  ) a ON a.obligation_id = o.id
  WHERE o.relationship_id = p_relationship_id AND op.cycle_id = cycle_id_now;

  SELECT COALESCE(sum(p.amount_minor - COALESCE(a.allocated, 0)), 0)
  INTO unapplied_payments
  FROM ledger.payments p
  JOIN ledger.operations op ON op.operation_id = p.source_operation_id
  LEFT JOIN (
    SELECT payment_id, sum(amount_minor) AS allocated
    FROM ledger.allocations WHERE relationship_id = p_relationship_id
    GROUP BY payment_id
  ) a ON a.payment_id = p.id
  WHERE p.relationship_id = p_relationship_id AND op.cycle_id = cycle_id_now;

  SELECT count(*) INTO pending_operations
  FROM ledger.operations
  WHERE relationship_id = p_relationship_id AND cycle_id = cycle_id_now
    AND business_state IN ('awaiting_counterparty', 'disputed');

  IF outstanding_obligations <> 0 OR unapplied_payments <> 0 OR pending_operations <> 0 THEN
    RAISE EXCEPTION
      'Cannot request white-page reset: outstanding obligations %, unapplied payments %, pending operations %',
      outstanding_obligations, unapplied_payments, pending_operations
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO ledger.settlement_requests
    (id, relationship_id, requested_by_user_id, cycle_id)
  VALUES (p_request_id, p_relationship_id, p_actor_user_id, cycle_id_now);
  RETURN p_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION ledger.decide_settlement_reset(
  p_decision_id uuid,
  p_relationship_id uuid,
  p_request_id uuid,
  p_actor_user_id uuid,
  p_decision text,
  p_reason text DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  relationship_status text;
  current_cycle uuid;
  reset_request ledger.settlement_requests%ROWTYPE;
  prior ledger.settlement_decisions%ROWTYPE;
  active_members bigint;
  outstanding_obligations numeric;
  unapplied_payments numeric;
  pending_operations bigint;
  next_cycle_number bigint;
  next_cycle_id uuid;
BEGIN
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Unsupported settlement decision' USING ERRCODE = '22023';
  END IF;
  IF p_reason IS NOT NULL AND length(p_reason) > 1000 THEN
    RAISE EXCEPTION 'Settlement decision reason is too long' USING ERRCODE = '22023';
  END IF;

  SELECT status, current_cycle_id INTO relationship_status, current_cycle
  FROM ledger.relationships WHERE id = p_relationship_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not found' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO prior FROM ledger.settlement_decisions
  WHERE idempotency_key = p_decision_id;
  IF FOUND THEN
    IF prior.relationship_id = p_relationship_id AND prior.request_id = p_request_id
       AND prior.actor_user_id = p_actor_user_id AND prior.decision = p_decision
       AND prior.reason IS NOT DISTINCT FROM p_reason THEN
      RETURN prior.decision;
    END IF;
    RAISE EXCEPTION 'Settlement decision idempotency key reused with different content' USING ERRCODE = '23505';
  END IF;

  SELECT * INTO reset_request FROM ledger.settlement_requests
  WHERE id = p_request_id AND relationship_id = p_relationship_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Settlement reset request not found' USING ERRCODE = '23503';
  END IF;
  IF EXISTS (SELECT 1 FROM ledger.settlement_decisions WHERE request_id = p_request_id) THEN
    RAISE EXCEPTION 'Settlement reset request already has a final decision' USING ERRCODE = '55000';
  END IF;
  IF relationship_status <> 'active' OR current_cycle <> reset_request.cycle_id THEN
    RAISE EXCEPTION 'Relationship or requested cycle is no longer current' USING ERRCODE = '55000';
  END IF;
  IF p_actor_user_id = reset_request.requested_by_user_id THEN
    RAISE EXCEPTION 'Requester cannot decide their own settlement reset request' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id AND user_id = p_actor_user_id
      AND status = 'active' AND can_approve = true
  ) THEN
    RAISE EXCEPTION 'Counterparty lacks active settlement approval permission' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO active_members FROM ledger.relationship_members
  WHERE relationship_id = p_relationship_id AND status = 'active';
  IF active_members <> 2 THEN
    RAISE EXCEPTION 'Settlement decision requires exactly two active parties' USING ERRCODE = '23514';
  END IF;

  IF p_decision = 'approved' THEN
    SELECT COALESCE(sum(o.amount_minor - COALESCE(a.allocated, 0) - COALESCE(o.credit_applied_minor, 0)), 0)
    INTO outstanding_obligations
    FROM ledger.obligations o
    JOIN ledger.operations op ON op.operation_id = o.source_operation_id
    LEFT JOIN (
      SELECT obligation_id, sum(amount_minor) AS allocated
      FROM ledger.allocations WHERE relationship_id = p_relationship_id
      GROUP BY obligation_id
    ) a ON a.obligation_id = o.id
    WHERE o.relationship_id = p_relationship_id AND op.cycle_id = current_cycle;

    SELECT COALESCE(sum(p.amount_minor - COALESCE(a.allocated, 0)), 0)
    INTO unapplied_payments
    FROM ledger.payments p
    JOIN ledger.operations op ON op.operation_id = p.source_operation_id
    LEFT JOIN (
      SELECT payment_id, sum(amount_minor) AS allocated
      FROM ledger.allocations WHERE relationship_id = p_relationship_id
      GROUP BY payment_id
    ) a ON a.payment_id = p.id
    WHERE p.relationship_id = p_relationship_id AND op.cycle_id = current_cycle;

    SELECT count(*) INTO pending_operations FROM ledger.operations
    WHERE relationship_id = p_relationship_id AND cycle_id = current_cycle
      AND business_state IN ('awaiting_counterparty', 'disputed');

    IF outstanding_obligations <> 0 OR unapplied_payments <> 0 OR pending_operations <> 0 THEN
      RAISE EXCEPTION
        'Cannot approve white-page reset: outstanding obligations %, unapplied payments %, pending operations %',
        outstanding_obligations, unapplied_payments, pending_operations
        USING ERRCODE = '23514';
    END IF;

    UPDATE ledger.account_cycles
    SET status = 'archived', ended_at = clock_timestamp()
    WHERE id = current_cycle AND status = 'active';

    SELECT COALESCE(max(cycle_number), 0) + 1 INTO next_cycle_number
    FROM ledger.account_cycles WHERE relationship_id = p_relationship_id;

    INSERT INTO ledger.account_cycles
      (relationship_id, cycle_number, title, status, created_by_reset_request_id)
    VALUES
      (p_relationship_id, next_cycle_number,
       'صفحة بيضاء ' || next_cycle_number::text, 'active', p_request_id)
    RETURNING id INTO next_cycle_id;

    UPDATE ledger.relationships
    SET current_cycle_id = next_cycle_id
    WHERE id = p_relationship_id;

  END IF;

  INSERT INTO ledger.settlement_decisions
    (idempotency_key, request_id, relationship_id, actor_user_id, decision, reason)
  VALUES (p_decision_id, p_request_id, p_relationship_id, p_actor_user_id, p_decision, p_reason);

  RETURN p_decision;
END;
$$;
