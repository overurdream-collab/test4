-- Reduce the time spent holding the per-relationship event-sequence row lock.
-- The ordered counter remains transactional and is still held through commit.
-- New operation rows are inserted before allocating the event sequence; no reader
-- can observe server_sequence=0 because the insert and sequence assignment share
-- the same transaction.

CREATE OR REPLACE FUNCTION ledger.next_relationship_sequence(p_relationship_id uuid)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE result_sequence bigint;
BEGIN
  UPDATE ledger.relationship_sync_counters
  SET last_sequence = last_sequence + 1
  WHERE relationship_id = p_relationship_id
  RETURNING last_sequence INTO result_sequence;

  IF FOUND THEN
    RETURN result_sequence;
  END IF;

  -- First event for a relationship, including the concurrent first-insert race.
  INSERT INTO ledger.relationship_sync_counters (relationship_id, last_sequence)
  VALUES (p_relationship_id, 1)
  ON CONFLICT (relationship_id)
  DO UPDATE SET last_sequence = ledger.relationship_sync_counters.last_sequence + 1
  RETURNING last_sequence INTO result_sequence;

  RETURN result_sequence;
END;
$$;

CREATE OR REPLACE FUNCTION ledger.accept_operation(
  p_operation_id uuid,
  p_relationship_id uuid,
  p_actor_user_id uuid,
  p_device_id uuid,
  p_operation_type text,
  p_request_hash bytea,
  p_payload jsonb,
  p_base_version bigint,
  p_schema_version integer,
  p_client_created_at timestamptz
) RETURNS TABLE (
  outcome text,
  canonical_operation_id uuid,
  business_state text,
  server_version bigint,
  server_sequence bigint,
  server_created_at timestamptz
)
LANGUAGE plpgsql AS $$
DECLARE
  existing ledger.operations%ROWTYPE;
  next_sequence bigint;
  now_server timestamptz := clock_timestamp();
BEGIN
  IF p_request_hash IS NULL OR octet_length(p_request_hash) <> 32
     OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
     OR p_base_version < 0 OR p_schema_version <> 1
     OR p_operation_type NOT IN ('credit_charge', 'payment', 'allocation', 'supply', 'sales_return') THEN
    RAISE EXCEPTION 'Invalid operation envelope' USING ERRCODE = '23514';
  END IF;

  -- Serialize duplicate submissions of the same operation ID before checking inbox state.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_operation_id::text, 0));

  SELECT * INTO existing FROM ledger.operations
  WHERE operation_id = p_operation_id
  FOR UPDATE;
  IF FOUND THEN
    IF existing.relationship_id = p_relationship_id
       AND existing.actor_user_id = p_actor_user_id
       AND existing.device_id = p_device_id
       AND existing.operation_type = p_operation_type
       AND existing.request_hash = p_request_hash THEN
      RETURN QUERY SELECT
        'already_processed'::text, existing.operation_id, existing.business_state,
        existing.server_version, existing.server_sequence, existing.created_at;
      RETURN;
    END IF;
    RAISE EXCEPTION 'Operation id reused with different envelope'
      USING ERRCODE = '23505';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ledger.relationship_members
    WHERE relationship_id = p_relationship_id
      AND user_id = p_actor_user_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Actor is not an active relationship member'
      USING ERRCODE = '42501';
  END IF;

  -- Insert the operation before contending for the relationship's ordered
  -- event counter. The row is uncommitted and invisible until sequence assignment.
  INSERT INTO ledger.operations (
    operation_id, relationship_id, actor_user_id, operation_type, request_hash,
    business_state, base_version, server_version, device_id,
    client_schema_version, client_created_at, operation_payload, server_sequence, created_at
  ) VALUES (
    p_operation_id, p_relationship_id, p_actor_user_id, p_operation_type, p_request_hash,
    'awaiting_counterparty', p_base_version, 1, p_device_id,
    p_schema_version, p_client_created_at, p_payload, 0, now_server
  );

  next_sequence := ledger.next_relationship_sequence(p_relationship_id);

  UPDATE ledger.operations
  SET server_sequence = next_sequence
  WHERE operation_id = p_operation_id;

  INSERT INTO ledger.relationship_events (
    relationship_id, server_sequence, event_id, operation_id, event_type, event_payload
  ) VALUES (
    p_relationship_id, next_sequence, gen_random_uuid(), p_operation_id, 'operation.created',
    jsonb_build_object(
      'operationId', p_operation_id,
      'operationType', p_operation_type,
      'businessState', 'awaiting_counterparty',
      'serverVersion', 1,
      'payload', p_payload
    )
  );

  RETURN QUERY SELECT
    'accepted'::text, p_operation_id, 'awaiting_counterparty'::text,
    1::bigint, next_sequence, now_server;
END;
$$;
