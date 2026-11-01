-- Tighten approval idempotency: the original reason is part of the request identity.
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
  prior_decision ledger.approvals%ROWTYPE;
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

  SELECT * INTO prior_decision FROM ledger.approvals WHERE id = p_decision_id;
  IF FOUND THEN
    IF prior_decision.relationship_id = p_relationship_id
       AND prior_decision.operation_id = p_operation_id
       AND prior_decision.actor_user_id = p_actor_user_id
       AND prior_decision.decision = p_decision
       AND prior_decision.expected_server_version = p_expected_server_version
       AND prior_decision.reason IS NOT DISTINCT FROM p_reason THEN
      RETURN prior_decision.resulting_server_version;
    END IF;
    RAISE EXCEPTION 'Idempotency key was reused with different decision content'
      USING ERRCODE = '23505';
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
