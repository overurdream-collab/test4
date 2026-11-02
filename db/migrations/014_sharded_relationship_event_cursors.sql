-- Eight independent ordered event streams per relationship.
-- Each operation and its later state events use the same deterministic shard.
-- Large disjoint sequence ranges preserve the existing global unique key/index.
CREATE OR REPLACE FUNCTION ledger.operation_sync_shard(p_operation_id uuid)
RETURNS smallint LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT ((strpos('0123456789abcdef', right(replace(p_operation_id::text,'-',''),1))-1) % 8)::smallint
$$;

ALTER TABLE ledger.operations ADD COLUMN sync_shard smallint NOT NULL DEFAULT 0 CHECK(sync_shard BETWEEN 0 AND 7);
UPDATE ledger.operations SET sync_shard=ledger.operation_sync_shard(operation_id);
ALTER TABLE ledger.relationship_events ADD COLUMN sync_shard smallint NOT NULL DEFAULT 0 CHECK(sync_shard BETWEEN 0 AND 7);
UPDATE ledger.relationship_events e SET sync_shard=o.sync_shard
FROM ledger.operations o WHERE o.relationship_id=e.relationship_id AND o.operation_id=e.operation_id;

CREATE TABLE ledger.relationship_sync_shard_counters (
 relationship_id uuid NOT NULL REFERENCES ledger.relationships(id),
 sync_shard smallint NOT NULL CHECK(sync_shard BETWEEN 0 AND 7),
 last_sequence bigint NOT NULL CHECK(last_sequence>=0),
 PRIMARY KEY(relationship_id,sync_shard)
);
INSERT INTO ledger.relationship_sync_shard_counters(relationship_id,sync_shard,last_sequence)
SELECT c.relationship_id,s.shard,c.last_sequence
FROM ledger.relationship_sync_counters c CROSS JOIN generate_series(0,7) AS s(shard);

CREATE OR REPLACE FUNCTION ledger.next_relationship_sequence(p_relationship_id uuid,p_sync_shard smallint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE local_sequence bigint; sequence_offset bigint;
BEGIN
 sequence_offset:=p_sync_shard::bigint*1000000000000;
 UPDATE ledger.relationship_sync_shard_counters
 SET last_sequence=last_sequence+1
 WHERE relationship_id=p_relationship_id AND sync_shard=p_sync_shard
 RETURNING last_sequence INTO local_sequence;
 IF FOUND THEN RETURN sequence_offset+local_sequence; END IF;
 INSERT INTO ledger.relationship_sync_shard_counters(relationship_id,sync_shard,last_sequence)
 VALUES(p_relationship_id,p_sync_shard,1)
 ON CONFLICT(relationship_id,sync_shard)
 DO UPDATE SET last_sequence=ledger.relationship_sync_shard_counters.last_sequence+1
 RETURNING last_sequence INTO local_sequence;
 RETURN sequence_offset+local_sequence;
END;
$$;

CREATE OR REPLACE FUNCTION ledger.next_relationship_sequence(p_relationship_id uuid)
RETURNS bigint LANGUAGE sql AS $$ SELECT ledger.next_relationship_sequence(p_relationship_id,0::smallint) $$;

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
  next_shard smallint;
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

  next_shard := ledger.operation_sync_shard(p_operation_id);

  -- Insert the operation before contending for the relationship's ordered
  -- event counter. The row is uncommitted and invisible until sequence assignment.
  INSERT INTO ledger.operations (
    operation_id, relationship_id, actor_user_id, operation_type, request_hash,
    business_state, base_version, server_version, device_id,
    client_schema_version, client_created_at, operation_payload, server_sequence, sync_shard, created_at
  ) VALUES (
    p_operation_id, p_relationship_id, p_actor_user_id, p_operation_type, p_request_hash,
    'awaiting_counterparty', p_base_version, 1, p_device_id,
    p_schema_version, p_client_created_at, p_payload, 0, next_shard, now_server
  );

  next_sequence := ledger.next_relationship_sequence(p_relationship_id, next_shard);

  UPDATE ledger.operations
  SET server_sequence = next_sequence
  WHERE operation_id = p_operation_id;

  INSERT INTO ledger.relationship_events (
    relationship_id, sync_shard, server_sequence, event_id, operation_id, event_type, event_payload
  ) VALUES (
    p_relationship_id, next_shard, next_sequence, gen_random_uuid(), p_operation_id, 'operation.created',
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
      ELSE
        NULL; -- Supply is recorded as a business event, not a financial posting.
    END CASE;
  END IF;

  SELECT * INTO approval_row FROM ledger.approvals
  WHERE relationship_id = NEW.relationship_id AND operation_id = NEW.operation_id
  ORDER BY decided_at DESC LIMIT 1;

  next_sequence := ledger.next_relationship_sequence(NEW.relationship_id, NEW.sync_shard);
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
    relationship_id, sync_shard, server_sequence, event_id, operation_id, event_type, event_payload
  ) VALUES (
    NEW.relationship_id, NEW.sync_shard, next_sequence, gen_random_uuid(), NEW.operation_id,
    'operation.state_changed', payload
  );
  RETURN NEW;
END;
$$;
