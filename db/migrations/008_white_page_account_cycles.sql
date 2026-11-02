-- White-page account cycles: reset archives the settled cycle and starts a new one.
-- The commercial relationship and its membership remain active.

CREATE TABLE ledger.account_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES ledger.relationships(id),
  cycle_number bigint NOT NULL CHECK (cycle_number > 0),
  title text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','archived')),
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ended_at timestamptz,
  created_by_reset_request_id uuid,
  UNIQUE (relationship_id, cycle_number),
  UNIQUE (id, relationship_id),
  CHECK ((status = 'active' AND ended_at IS NULL) OR
         (status = 'archived' AND ended_at IS NOT NULL))
);

-- Create the first cycle for every existing relationship. Existing financial
-- history remains together in that initial cycle; nothing is deleted or moved.
INSERT INTO ledger.account_cycles
  (id, relationship_id, cycle_number, title, status)
SELECT gen_random_uuid(), r.id, 1, 'الدورة الأولى', 'active'
FROM ledger.relationships r;

ALTER TABLE ledger.relationships
  ADD COLUMN current_cycle_id uuid;

UPDATE ledger.relationships r
SET current_cycle_id = c.id
FROM ledger.account_cycles c
WHERE c.relationship_id = r.id AND c.status = 'active';

ALTER TABLE ledger.relationships
  ALTER COLUMN current_cycle_id SET NOT NULL,
  ADD CONSTRAINT relationships_current_cycle_fk
    FOREIGN KEY (current_cycle_id, id)
    REFERENCES ledger.account_cycles (id, relationship_id);

ALTER TABLE ledger.operations ADD COLUMN cycle_id uuid;
UPDATE ledger.operations o
SET cycle_id = r.current_cycle_id
FROM ledger.relationships r
WHERE r.id = o.relationship_id;
ALTER TABLE ledger.operations
  ALTER COLUMN cycle_id SET NOT NULL,
  ADD CONSTRAINT operations_cycle_fk
    FOREIGN KEY (cycle_id, relationship_id)
    REFERENCES ledger.account_cycles (id, relationship_id);
CREATE INDEX operations_relationship_cycle_state_idx
  ON ledger.operations (relationship_id, cycle_id, business_state);

ALTER TABLE ledger.journal_transactions ADD COLUMN cycle_id uuid;
UPDATE ledger.journal_transactions jt
SET cycle_id = o.cycle_id
FROM ledger.operations o
WHERE o.operation_id = jt.source_operation_id;
ALTER TABLE ledger.journal_transactions
  ALTER COLUMN cycle_id SET NOT NULL,
  ADD CONSTRAINT journal_transactions_cycle_fk
    FOREIGN KEY (cycle_id, relationship_id)
    REFERENCES ledger.account_cycles (id, relationship_id);
CREATE INDEX journal_cycle_history_idx
  ON ledger.journal_transactions (relationship_id, cycle_id, posted_at DESC, id);

ALTER TABLE ledger.settlement_requests ADD COLUMN cycle_id uuid;
UPDATE ledger.settlement_requests sr
SET cycle_id = r.current_cycle_id
FROM ledger.relationships r
WHERE r.id = sr.relationship_id;
ALTER TABLE ledger.settlement_requests
  ALTER COLUMN cycle_id SET NOT NULL,
  ADD CONSTRAINT settlement_requests_cycle_fk
    FOREIGN KEY (cycle_id, relationship_id)
    REFERENCES ledger.account_cycles (id, relationship_id);

-- Every newly accepted operation is pinned to the relationship's current cycle.
CREATE OR REPLACE FUNCTION ledger.assign_current_account_cycle()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE current_id uuid;
BEGIN
  SELECT current_cycle_id INTO current_id
  FROM ledger.relationships
  WHERE id = NEW.relationship_id AND status = 'active'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship is not active' USING ERRCODE = '55000';
  END IF;
  IF NEW.cycle_id IS NOT NULL AND NEW.cycle_id <> current_id THEN
    RAISE EXCEPTION 'Operation targets a non-current account cycle'
      USING ERRCODE = '23514';
  END IF;
  NEW.cycle_id := current_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER operations_assign_current_cycle
BEFORE INSERT ON ledger.operations
FOR EACH ROW EXECUTE FUNCTION ledger.assign_current_account_cycle();

-- Journal entries inherit the exact cycle of their source operation.
CREATE OR REPLACE FUNCTION ledger.assign_journal_account_cycle()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE source_cycle uuid;
BEGIN
  SELECT cycle_id INTO source_cycle
  FROM ledger.operations
  WHERE operation_id = NEW.source_operation_id
    AND relationship_id = NEW.relationship_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Journal source operation not found' USING ERRCODE = '23503';
  END IF;
  IF NEW.cycle_id IS NOT NULL AND NEW.cycle_id <> source_cycle THEN
    RAISE EXCEPTION 'Journal transaction cycle differs from source operation'
      USING ERRCODE = '23514';
  END IF;
  NEW.cycle_id := source_cycle;
  RETURN NEW;
END;
$$;

CREATE TRIGGER journal_transactions_assign_cycle
BEFORE INSERT ON ledger.journal_transactions
FOR EACH ROW EXECUTE FUNCTION ledger.assign_journal_account_cycle();

-- Keep the historical all-time view, and add a cycle-scoped view for the
-- current white page and archived statements.
CREATE OR REPLACE VIEW ledger.member_currency_positions AS
SELECT
  jt.relationship_id,
  jt.cycle_id,
  a.owner_user_id,
  je.currency,
  sum(je.debit_minor - je.credit_minor)::numeric AS net_position_minor
FROM ledger.journal_entries je
JOIN ledger.journal_transactions jt ON jt.id = je.journal_transaction_id
JOIN ledger.accounts a ON a.id = je.account_id
  AND a.relationship_id = je.relationship_id
  AND a.currency = je.currency
GROUP BY jt.relationship_id, jt.cycle_id, a.owner_user_id, je.currency;

CREATE INDEX settlement_requests_cycle_idx
  ON ledger.settlement_requests (relationship_id, cycle_id, requested_at DESC);

-- A request can only close the current cycle after that cycle is fully settled.
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
    RAISE EXCEPTION 'Settlement request id reused with different content'
      USING ERRCODE = '23505';
  END IF;

  SELECT current_cycle_id INTO cycle_id_now
  FROM ledger.relationships WHERE id = p_relationship_id;

  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id AND user_id = p_actor_user_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Requester is not an active relationship member'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO active_members FROM ledger.relationship_members
  WHERE relationship_id = p_relationship_id AND status = 'active';
  IF active_members <> 2 THEN
    RAISE EXCEPTION 'White-page reset requires exactly two active parties'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1 FROM ledger.settlement_requests sr
    LEFT JOIN ledger.settlement_decisions sd ON sd.request_id = sr.id
    WHERE sr.relationship_id = p_relationship_id AND sd.request_id IS NULL
  ) THEN
    RAISE EXCEPTION 'A settlement reset request is already awaiting a decision'
      USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(sum(o.amount_minor - COALESCE(a.allocated, 0)), 0)
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

-- Approval archives the old cycle and atomically creates a fresh zero-balance
-- cycle. The relationship, parties, roles and permissions remain unchanged.
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
    RAISE EXCEPTION 'Settlement decision idempotency key reused with different content'
      USING ERRCODE = '23505';
  END IF;

  SELECT * INTO reset_request FROM ledger.settlement_requests
  WHERE id = p_request_id AND relationship_id = p_relationship_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Settlement reset request not found' USING ERRCODE = '23503';
  END IF;
  IF EXISTS (SELECT 1 FROM ledger.settlement_decisions WHERE request_id = p_request_id) THEN
    RAISE EXCEPTION 'Settlement reset request already has a final decision'
      USING ERRCODE = '55000';
  END IF;
  IF relationship_status <> 'active' OR current_cycle <> reset_request.cycle_id THEN
    RAISE EXCEPTION 'Relationship or requested cycle is no longer current'
      USING ERRCODE = '55000';
  END IF;
  IF p_actor_user_id = reset_request.requested_by_user_id THEN
    RAISE EXCEPTION 'Requester cannot decide their own settlement reset request'
      USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id AND user_id = p_actor_user_id
      AND status = 'active' AND can_approve = true
  ) THEN
    RAISE EXCEPTION 'Counterparty lacks active settlement approval permission'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO active_members FROM ledger.relationship_members
  WHERE relationship_id = p_relationship_id AND status = 'active';
  IF active_members <> 2 THEN
    RAISE EXCEPTION 'Settlement decision requires exactly two active parties'
      USING ERRCODE = '23514';
  END IF;

  IF p_decision = 'approved' THEN
    SELECT COALESCE(sum(o.amount_minor - COALESCE(a.allocated, 0)), 0)
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

CREATE OR REPLACE FUNCTION ledger.append_settlement_decision_event()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  next_sequence bigint;
  current_cycle uuid;
BEGIN
  SELECT current_cycle_id INTO current_cycle
  FROM ledger.relationships WHERE id = NEW.relationship_id;
  next_sequence := ledger.next_relationship_sequence(NEW.relationship_id);
  INSERT INTO ledger.relationship_events (
    relationship_id, server_sequence, event_id, operation_id, event_type, event_payload
  ) VALUES (
    NEW.relationship_id, next_sequence, gen_random_uuid(), NULL,
    CASE NEW.decision WHEN 'approved' THEN 'settlement.reset_approved'
                      ELSE 'settlement.reset_rejected' END,
    jsonb_build_object(
      'requestId', NEW.request_id,
      'decisionId', NEW.idempotency_key,
      'decidedByUserId', NEW.actor_user_id,
      'decision', NEW.decision,
      'reason', NEW.reason,
      'relationshipStatus', 'active',
      'archivedCycleId', (SELECT cycle_id FROM ledger.settlement_requests WHERE id=NEW.request_id),
      'currentCycleId', current_cycle,
      'decidedAt', NEW.decided_at
    )
  );
  RETURN NEW;
END;
$$;
