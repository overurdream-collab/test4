-- Bilateral settlement-reset decision and relationship freeze.
-- Requests remain immutable. A separate immutable decision records approve/reject.

ALTER TABLE ledger.relationship_events
  ALTER COLUMN operation_id DROP NOT NULL;

ALTER TABLE ledger.relationships
  ADD COLUMN closed_at timestamptz;

CREATE TABLE ledger.settlement_decisions (
  idempotency_key uuid PRIMARY KEY,
  request_id uuid NOT NULL UNIQUE,
  relationship_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approved', 'rejected')),
  reason text,
  decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (request_id, relationship_id)
    REFERENCES ledger.settlement_requests (id, relationship_id),
  FOREIGN KEY (relationship_id, actor_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id)
);

CREATE INDEX settlement_decisions_relationship_time_idx
  ON ledger.settlement_decisions (relationship_id, decided_at DESC);

CREATE OR REPLACE FUNCTION ledger.reject_settlement_decision_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Settlement decisions are immutable'
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER settlement_decisions_are_immutable
BEFORE UPDATE OR DELETE ON ledger.settlement_decisions
FOR EACH ROW EXECUTE FUNCTION ledger.reject_settlement_decision_mutation();

-- Serialize every newly accepted operation with reset requests and final decisions.
-- A pending reset request freezes new business operations until it is rejected
-- or approved. The relationship row is the common serialization lock.
CREATE OR REPLACE FUNCTION ledger.guard_operation_during_settlement_reset()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  relationship_status text;
BEGIN
  SELECT status INTO relationship_status
  FROM ledger.relationships
  WHERE id = NEW.relationship_id
  FOR UPDATE;

  IF NOT FOUND OR relationship_status <> 'active' THEN
    RAISE EXCEPTION 'Relationship is not active'
      USING ERRCODE = '55000';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ledger.settlement_requests sr
    LEFT JOIN ledger.settlement_decisions sd ON sd.request_id = sr.id
    WHERE sr.relationship_id = NEW.relationship_id
      AND sd.request_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Relationship is frozen while settlement reset is awaiting a decision'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER operations_blocked_during_settlement_reset
BEFORE INSERT ON ledger.operations
FOR EACH ROW EXECUTE FUNCTION ledger.guard_operation_during_settlement_reset();

-- Replace the request function to enforce the two-party v1 relationship model
-- and to permit only one outstanding reset request at a time.
CREATE OR REPLACE FUNCTION ledger.request_settlement_reset(
  p_request_id uuid,
  p_relationship_id uuid,
  p_actor_user_id uuid
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  existing_request ledger.settlement_requests%ROWTYPE;
  active_member_count bigint;
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

  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id
      AND user_id = p_actor_user_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Requester is not an active relationship member'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO existing_request
  FROM ledger.settlement_requests WHERE id = p_request_id;
  IF FOUND THEN
    IF existing_request.relationship_id = p_relationship_id
       AND existing_request.requested_by_user_id = p_actor_user_id THEN
      RETURN existing_request.id;
    END IF;
    RAISE EXCEPTION 'Settlement request id reused with different content'
      USING ERRCODE = '23505';
  END IF;

  SELECT count(*) INTO active_member_count
  FROM ledger.relationship_members
  WHERE relationship_id = p_relationship_id AND status = 'active';
  IF active_member_count <> 2 THEN
    RAISE EXCEPTION 'Settlement reset requires exactly two active parties'
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
  LEFT JOIN (
    SELECT obligation_id, sum(amount_minor) AS allocated
    FROM ledger.allocations
    WHERE relationship_id = p_relationship_id
    GROUP BY obligation_id
  ) a ON a.obligation_id = o.id
  WHERE o.relationship_id = p_relationship_id;

  SELECT COALESCE(sum(p.amount_minor - COALESCE(a.allocated, 0)), 0)
  INTO unapplied_payments
  FROM ledger.payments p
  LEFT JOIN (
    SELECT payment_id, sum(amount_minor) AS allocated
    FROM ledger.allocations
    WHERE relationship_id = p_relationship_id
    GROUP BY payment_id
  ) a ON a.payment_id = p.id
  WHERE p.relationship_id = p_relationship_id;

  SELECT count(*) INTO pending_operations
  FROM ledger.operations
  WHERE relationship_id = p_relationship_id
    AND business_state IN ('awaiting_counterparty', 'disputed');

  IF outstanding_obligations <> 0 OR unapplied_payments <> 0
     OR pending_operations <> 0 THEN
    RAISE EXCEPTION
      'Cannot request settlement reset: outstanding obligations %, unapplied payments %, pending operations %',
      outstanding_obligations, unapplied_payments, pending_operations
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO ledger.settlement_requests (id, relationship_id, requested_by_user_id)
  VALUES (p_request_id, p_relationship_id, p_actor_user_id);
  RETURN p_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION ledger.append_settlement_request_event()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  next_sequence bigint;
BEGIN
  next_sequence := ledger.next_relationship_sequence(NEW.relationship_id);
  INSERT INTO ledger.relationship_events (
    relationship_id, server_sequence, event_id, operation_id, event_type, event_payload
  ) VALUES (
    NEW.relationship_id, next_sequence, gen_random_uuid(), NULL,
    'settlement.reset_requested',
    jsonb_build_object(
      'requestId', NEW.id,
      'requestedByUserId', NEW.requested_by_user_id,
      'requestedAt', NEW.requested_at
    )
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER settlement_request_sync_event
AFTER INSERT ON ledger.settlement_requests
FOR EACH ROW EXECUTE FUNCTION ledger.append_settlement_request_event();

CREATE OR REPLACE FUNCTION ledger.decide_settlement_reset(
  p_decision_id uuid,
  p_relationship_id uuid,
  p_request_id uuid,
  p_actor_user_id uuid,
  p_decision text,
  p_reason text DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  relationship_status text;
  reset_request ledger.settlement_requests%ROWTYPE;
  prior_decision ledger.settlement_decisions%ROWTYPE;
  active_member_count bigint;
  outstanding_obligations numeric;
  unapplied_payments numeric;
  pending_operations bigint;
BEGIN
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Unsupported settlement decision'
      USING ERRCODE = '22023';
  END IF;
  IF p_reason IS NOT NULL AND length(p_reason) > 1000 THEN
    RAISE EXCEPTION 'Settlement decision reason is too long'
      USING ERRCODE = '22023';
  END IF;

  SELECT status INTO relationship_status
  FROM ledger.relationships
  WHERE id = p_relationship_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not found' USING ERRCODE = '23503';
  END IF;

  SELECT * INTO prior_decision
  FROM ledger.settlement_decisions
  WHERE idempotency_key = p_decision_id;
  IF FOUND THEN
    IF prior_decision.relationship_id = p_relationship_id
       AND prior_decision.request_id = p_request_id
       AND prior_decision.actor_user_id = p_actor_user_id
       AND prior_decision.decision = p_decision
       AND prior_decision.reason IS NOT DISTINCT FROM p_reason THEN
      RETURN prior_decision.decision;
    END IF;
    RAISE EXCEPTION 'Settlement decision idempotency key reused with different content'
      USING ERRCODE = '23505';
  END IF;

  SELECT * INTO reset_request
  FROM ledger.settlement_requests
  WHERE id = p_request_id AND relationship_id = p_relationship_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Settlement reset request not found' USING ERRCODE = '23503';
  END IF;

  IF EXISTS (
    SELECT 1 FROM ledger.settlement_decisions
    WHERE request_id = p_request_id
  ) THEN
    RAISE EXCEPTION 'Settlement reset request already has a final decision'
      USING ERRCODE = '55000';
  END IF;

  IF relationship_status <> 'active' THEN
    RAISE EXCEPTION 'Relationship is not active' USING ERRCODE = '55000';
  END IF;

  IF p_actor_user_id = reset_request.requested_by_user_id THEN
    RAISE EXCEPTION 'Requester cannot decide their own settlement reset request'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id
      AND user_id = p_actor_user_id
      AND status = 'active'
      AND can_approve = true
  ) THEN
    RAISE EXCEPTION 'Counterparty lacks active settlement approval permission'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO active_member_count
  FROM ledger.relationship_members
  WHERE relationship_id = p_relationship_id AND status = 'active';
  IF active_member_count <> 2 THEN
    RAISE EXCEPTION 'Settlement decision requires exactly two active parties'
      USING ERRCODE = '23514';
  END IF;

  IF p_decision = 'approved' THEN
    -- Revalidate immediately before closure while holding the relationship lock.
    SELECT COALESCE(sum(o.amount_minor - COALESCE(a.allocated, 0)), 0)
    INTO outstanding_obligations
    FROM ledger.obligations o
    LEFT JOIN (
      SELECT obligation_id, sum(amount_minor) AS allocated
      FROM ledger.allocations
      WHERE relationship_id = p_relationship_id
      GROUP BY obligation_id
    ) a ON a.obligation_id = o.id
    WHERE o.relationship_id = p_relationship_id;

    SELECT COALESCE(sum(p.amount_minor - COALESCE(a.allocated, 0)), 0)
    INTO unapplied_payments
    FROM ledger.payments p
    LEFT JOIN (
      SELECT payment_id, sum(amount_minor) AS allocated
      FROM ledger.allocations
      WHERE relationship_id = p_relationship_id
      GROUP BY payment_id
    ) a ON a.payment_id = p.id
    WHERE p.relationship_id = p_relationship_id;

    SELECT count(*) INTO pending_operations
    FROM ledger.operations
    WHERE relationship_id = p_relationship_id
      AND business_state IN ('awaiting_counterparty', 'disputed');

    IF outstanding_obligations <> 0 OR unapplied_payments <> 0
       OR pending_operations <> 0 THEN
      RAISE EXCEPTION
        'Cannot approve settlement reset: outstanding obligations %, unapplied payments %, pending operations %',
        outstanding_obligations, unapplied_payments, pending_operations
        USING ERRCODE = '23514';
    END IF;

    UPDATE ledger.relationships
    SET status = 'closed', closed_at = clock_timestamp()
    WHERE id = p_relationship_id AND status = 'active';
  END IF;

  INSERT INTO ledger.settlement_decisions (
    idempotency_key, request_id, relationship_id, actor_user_id, decision, reason
  ) VALUES (
    p_decision_id, p_request_id, p_relationship_id, p_actor_user_id, p_decision, p_reason
  );

  RETURN p_decision;
END;
$$;

CREATE OR REPLACE FUNCTION ledger.append_settlement_decision_event()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  next_sequence bigint;
  relationship_status text;
BEGIN
  SELECT status INTO relationship_status
  FROM ledger.relationships WHERE id = NEW.relationship_id;
  next_sequence := ledger.next_relationship_sequence(NEW.relationship_id);
  INSERT INTO ledger.relationship_events (
    relationship_id, server_sequence, event_id, operation_id, event_type, event_payload
  ) VALUES (
    NEW.relationship_id, next_sequence, gen_random_uuid(), NULL,
    CASE NEW.decision
      WHEN 'approved' THEN 'settlement.reset_approved'
      ELSE 'settlement.reset_rejected'
    END,
    jsonb_build_object(
      'requestId', NEW.request_id,
      'decisionId', NEW.idempotency_key,
      'decidedByUserId', NEW.actor_user_id,
      'decision', NEW.decision,
      'reason', NEW.reason,
      'relationshipStatus', relationship_status,
      'decidedAt', NEW.decided_at
    )
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER settlement_decision_sync_event
AFTER INSERT ON ledger.settlement_decisions
FOR EACH ROW EXECUTE FUNCTION ledger.append_settlement_decision_event();
