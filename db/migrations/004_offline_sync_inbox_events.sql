-- Durable server inbox and per-relationship ordered event feed for offline sync.

ALTER TABLE ledger.operations
  ADD COLUMN device_id uuid,
  ADD COLUMN client_schema_version integer NOT NULL DEFAULT 1 CHECK (client_schema_version > 0),
  ADD COLUMN client_created_at timestamptz,
  ADD COLUMN operation_payload jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(operation_payload) = 'object'),
  ADD COLUMN server_sequence bigint NOT NULL DEFAULT 0 CHECK (server_sequence >= 0);

CREATE UNIQUE INDEX operations_relationship_sequence_unique
  ON ledger.operations (relationship_id, server_sequence)
  WHERE server_sequence > 0;

CREATE TABLE ledger.relationship_sync_counters (
  relationship_id uuid PRIMARY KEY REFERENCES ledger.relationships(id),
  last_sequence bigint NOT NULL DEFAULT 0 CHECK (last_sequence >= 0)
);

CREATE TABLE ledger.relationship_events (
  relationship_id uuid NOT NULL REFERENCES ledger.relationships(id),
  server_sequence bigint NOT NULL CHECK (server_sequence > 0),
  event_id uuid NOT NULL UNIQUE,
  operation_id uuid NOT NULL,
  event_type text NOT NULL,
  event_payload jsonb NOT NULL CHECK (jsonb_typeof(event_payload) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, server_sequence),
  FOREIGN KEY (relationship_id, operation_id)
    REFERENCES ledger.operations (relationship_id, operation_id)
);

CREATE INDEX relationship_events_sync_idx
  ON ledger.relationship_events (relationship_id, server_sequence);

CREATE OR REPLACE FUNCTION ledger.next_relationship_sequence(p_relationship_id uuid)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE result_sequence bigint;
BEGIN
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
     OR p_operation_type NOT IN ('credit_charge', 'payment', 'allocation', 'supply') THEN
    RAISE EXCEPTION 'Invalid operation envelope' USING ERRCODE = '23514';
  END IF;

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

  next_sequence := ledger.next_relationship_sequence(p_relationship_id);

  INSERT INTO ledger.operations (
    operation_id, relationship_id, actor_user_id, operation_type, request_hash,
    business_state, base_version, server_version, device_id,
    client_schema_version, client_created_at, operation_payload, server_sequence, created_at
  ) VALUES (
    p_operation_id, p_relationship_id, p_actor_user_id, p_operation_type, p_request_hash,
    'awaiting_counterparty', p_base_version, 1, p_device_id,
    p_schema_version, p_client_created_at, p_payload, next_sequence, now_server
  );

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

-- Every business-state transition produces a new ordered event. The original
-- operation event is never overwritten and retries do not emit duplicate events.
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
END;
$$;

CREATE TRIGGER operations_append_state_event
AFTER UPDATE OF business_state, server_version ON ledger.operations
FOR EACH ROW EXECUTE FUNCTION ledger.append_operation_state_event();

CREATE OR REPLACE FUNCTION ledger.reject_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Relationship sync events are immutable'
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER relationship_events_are_immutable
BEFORE UPDATE OR DELETE ON ledger.relationship_events
FOR EACH ROW EXECUTE FUNCTION ledger.reject_event_mutation();


-- Approval is the financial commit point: materialize the approved proposal into
-- the corresponding immutable financial record inside the same DB transaction.
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
END;
$$;
