-- Allow concurrent operations on one relationship while preserving reset/cycle boundary safety.
-- FOR SHARE locks are mutually compatible. Reset request/decision paths retain FOR UPDATE.
CREATE OR REPLACE FUNCTION ledger.guard_operation_during_settlement_reset()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE relationship_status text;
BEGIN
  SELECT status INTO relationship_status FROM ledger.relationships
  WHERE id = NEW.relationship_id FOR SHARE;
  IF NOT FOUND OR relationship_status <> 'active' THEN
    RAISE EXCEPTION 'Relationship is not active' USING ERRCODE = '55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM ledger.settlement_requests sr
    LEFT JOIN ledger.settlement_decisions sd ON sd.request_id = sr.id
    WHERE sr.relationship_id = NEW.relationship_id AND sd.request_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Relationship is frozen while settlement reset is awaiting a decision' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ledger.assign_current_account_cycle()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE current_id uuid;
BEGIN
  SELECT current_cycle_id INTO current_id FROM ledger.relationships
  WHERE id = NEW.relationship_id AND status = 'active' FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship is not active' USING ERRCODE = '55000';
  END IF;
  IF NEW.cycle_id IS NOT NULL AND NEW.cycle_id <> current_id THEN
    RAISE EXCEPTION 'Operation targets a non-current account cycle' USING ERRCODE = '23514';
  END IF;
  NEW.cycle_id := current_id;
  RETURN NEW;
END;
$$;
