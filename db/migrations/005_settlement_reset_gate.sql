-- A relationship cannot be reset/closed while either party still has unsettled
-- obligations, unapplied payments, or pending business operations.
CREATE TABLE ledger.settlement_requests (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL REFERENCES ledger.relationships(id),
  requested_by_user_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'requested' CHECK (status = 'requested'),
  requested_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (relationship_id, requested_by_user_id)
    REFERENCES ledger.relationship_members (relationship_id, user_id),
  UNIQUE (id, relationship_id)
);

CREATE OR REPLACE FUNCTION ledger.request_settlement_reset(
  p_request_id uuid,
  p_relationship_id uuid,
  p_actor_user_id uuid
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  existing_request ledger.settlement_requests%ROWTYPE;
  outstanding_obligations numeric;
  unapplied_payments numeric;
  pending_operations bigint;
BEGIN
  -- Serialize concurrent settlement-reset requests for this relationship.
  -- This request is an eligibility snapshot; a later approval must revalidate settlement.
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

CREATE OR REPLACE FUNCTION ledger.reject_settlement_request_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Settlement requests are immutable; record a separate decision'
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER settlement_requests_are_immutable
BEFORE UPDATE OR DELETE ON ledger.settlement_requests
FOR EACH ROW EXECUTE FUNCTION ledger.reject_settlement_request_mutation();
