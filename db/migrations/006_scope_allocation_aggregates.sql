-- Keep allocation aggregate reads relationship-scoped so the composite
-- (relationship_id, payment_id / obligation_id) indexes can serve them.
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
  FROM ledger.allocations
  WHERE relationship_id = p_relationship_id AND payment_id = p_payment_id;
  SELECT COALESCE(sum(amount_minor), 0) INTO obligation_allocated
  FROM ledger.allocations
  WHERE relationship_id = p_relationship_id AND obligation_id = p_obligation_id;

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

CREATE OR REPLACE FUNCTION ledger.assert_allocation_within_bounds()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  pay ledger.payments%ROWTYPE;
  obl ledger.obligations%ROWTYPE;
  op ledger.operations%ROWTYPE;
  used_payment numeric;
  used_obligation numeric;
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
    RAISE EXCEPTION 'Allocation requires a confirmed payment and open obligation'
      USING ERRCODE = '23514';
  END IF;
  IF op.operation_id IS NULL OR op.business_state <> 'approved'
     OR op.operation_type <> 'allocation'
     OR op.actor_user_id NOT IN (pay.payer_user_id, pay.payee_user_id) THEN
    RAISE EXCEPTION 'Allocation requires an approved allocation operation by a party'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.currency <> pay.currency OR pay.currency <> obl.currency
     OR pay.payer_user_id <> obl.debtor_user_id
     OR pay.payee_user_id <> obl.creditor_user_id THEN
    RAISE EXCEPTION 'Allocation parties and currency must match'
      USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(sum(amount_minor),0) INTO used_payment
  FROM ledger.allocations
  WHERE relationship_id = NEW.relationship_id AND payment_id = NEW.payment_id;
  SELECT COALESCE(sum(amount_minor),0) INTO used_obligation
  FROM ledger.allocations
  WHERE relationship_id = NEW.relationship_id AND obligation_id = NEW.obligation_id;

  IF used_payment + NEW.amount_minor > pay.amount_minor
     OR used_obligation + NEW.amount_minor > obl.amount_minor THEN
    RAISE EXCEPTION 'Allocation exceeds payment or obligation remainder'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
