-- Bilateral relationship invitations tied to verified identity phone numbers.
ALTER TABLE ledger.relationships
  ADD COLUMN relationship_type text CHECK (relationship_type IN ('merchant_customer','supplier_buyer')),
  ADD COLUMN created_by_user_id uuid REFERENCES identity.users(id);

CREATE TABLE ledger.relationship_invitations (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL UNIQUE REFERENCES ledger.relationships(id),
  inviter_user_id uuid NOT NULL REFERENCES identity.users(id),
  invitee_user_id uuid REFERENCES identity.users(id),
  invitee_phone_e164 text NOT NULL CHECK (invitee_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  relationship_type text NOT NULL CHECK (relationship_type IN ('merchant_customer','supplier_buyer')),
  inviter_role text NOT NULL CHECK (inviter_role IN ('merchant','customer','supplier','buyer')),
  invitee_role text NOT NULL CHECK (invitee_role IN ('merchant','customer','supplier','buyer')),
  request_hash bytea NOT NULL CHECK (octet_length(request_hash)=32),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','expired')),
  decision_id uuid UNIQUE,
  decision_reason text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  responded_at timestamptz,
  responded_by_user_id uuid REFERENCES identity.users(id),
  CHECK (inviter_user_id IS DISTINCT FROM invitee_user_id),
  CHECK (expires_at>created_at),
  UNIQUE (id,relationship_id),
  CHECK ((relationship_type='merchant_customer' AND
          ((inviter_role='merchant' AND invitee_role='customer') OR
           (inviter_role='customer' AND invitee_role='merchant'))) OR
         (relationship_type='supplier_buyer' AND
          ((inviter_role='supplier' AND invitee_role='buyer') OR
           (inviter_role='buyer' AND invitee_role='supplier')))),
  CHECK ((status='pending' AND decision_id IS NULL AND responded_at IS NULL AND responded_by_user_id IS NULL) OR
         (status IN ('accepted','rejected') AND decision_id IS NOT NULL AND responded_at IS NOT NULL AND responded_by_user_id IS NOT NULL) OR
         (status='expired' AND decision_id IS NULL AND responded_at IS NOT NULL AND responded_by_user_id IS NULL))
);

CREATE INDEX relationship_invitations_pending_phone_idx
  ON ledger.relationship_invitations(invitee_phone_e164,expires_at)
  WHERE status='pending';
CREATE INDEX relationship_invitations_pending_user_idx
  ON ledger.relationship_invitations(invitee_user_id,expires_at)
  WHERE status='pending' AND invitee_user_id IS NOT NULL;

CREATE TABLE ledger.relationship_invitation_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invitation_id uuid NOT NULL,
  relationship_id uuid NOT NULL,
  actor_user_id uuid REFERENCES identity.users(id),
  event_type text NOT NULL CHECK (event_type IN ('created','accepted','rejected','expired')),
  event_payload jsonb NOT NULL CHECK (jsonb_typeof(event_payload)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (invitation_id,relationship_id)
    REFERENCES ledger.relationship_invitations(id,relationship_id)
);
CREATE INDEX relationship_invitation_events_history_idx
  ON ledger.relationship_invitation_events(relationship_id,created_at,id);
CREATE TRIGGER relationship_invitation_events_immutable
BEFORE UPDATE OR DELETE ON ledger.relationship_invitation_events
FOR EACH ROW EXECUTE FUNCTION ledger.reject_event_mutation();

CREATE OR REPLACE FUNCTION ledger.enforce_two_active_relationship_members()
RETURNS trigger LANGUAGE plpgsql AS $two_members$
DECLARE active_count bigint;
BEGIN
  IF NEW.status='active' THEN
    PERFORM 1 FROM ledger.relationships WHERE id=NEW.relationship_id FOR UPDATE;
    SELECT count(*) INTO active_count FROM ledger.relationship_members
    WHERE relationship_id=NEW.relationship_id AND status='active' AND user_id<>NEW.user_id;
    IF active_count>=2 THEN
      RAISE EXCEPTION 'A v1 relationship supports exactly two active parties' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$two_members$;
CREATE TRIGGER relationship_members_max_two_active
BEFORE INSERT OR UPDATE OF status,relationship_id,user_id ON ledger.relationship_members
FOR EACH ROW EXECUTE FUNCTION ledger.enforce_two_active_relationship_members();

CREATE OR REPLACE FUNCTION ledger.require_two_active_members_for_operations()
RETURNS trigger LANGUAGE plpgsql AS $operation_bilateral$
DECLARE rel_status text; active_count bigint;
BEGIN
  SELECT status INTO rel_status FROM ledger.relationships WHERE id=NEW.relationship_id FOR UPDATE;
  IF NOT FOUND OR rel_status<>'active' THEN
    RAISE EXCEPTION 'Relationship is not active' USING ERRCODE='55000';
  END IF;
  SELECT count(*) INTO active_count FROM ledger.relationship_members
  WHERE relationship_id=NEW.relationship_id AND status='active';
  IF active_count<>2 THEN
    RAISE EXCEPTION 'Financial operations require exactly two active parties' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$operation_bilateral$;
CREATE TRIGGER operations_require_two_active_members
BEFORE INSERT ON ledger.operations
FOR EACH ROW EXECUTE FUNCTION ledger.require_two_active_members_for_operations();

CREATE OR REPLACE FUNCTION ledger.create_relationship_invitation(
  p_invitation_id uuid,p_relationship_id uuid,p_inviter_user_id uuid,
  p_invitee_phone_e164 text,p_relationship_type text,
  p_inviter_role text,p_invitee_role text,p_request_hash bytea,
  p_expires_at timestamptz
) RETURNS TABLE(invitation_id uuid,relationship_id uuid,status text)
LANGUAGE plpgsql AS $create_relationship$
DECLARE existing ledger.relationship_invitations%ROWTYPE; invitee_id uuid;
BEGIN
  IF p_request_hash IS NULL OR octet_length(p_request_hash)<>32 OR
     p_expires_at<=clock_timestamp() OR p_expires_at>clock_timestamp()+interval '14 days' THEN
    RAISE EXCEPTION 'Invalid relationship invitation envelope' USING ERRCODE='23514';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_invitation_id::text,0));
  SELECT * INTO existing FROM ledger.relationship_invitations WHERE id=p_invitation_id FOR UPDATE;
  IF FOUND THEN
    IF existing.inviter_user_id=p_inviter_user_id AND existing.invitee_phone_e164=p_invitee_phone_e164
       AND existing.relationship_type=p_relationship_type AND existing.inviter_role=p_inviter_role
       AND existing.invitee_role=p_invitee_role AND existing.request_hash=p_request_hash THEN
      RETURN QUERY SELECT existing.id,existing.relationship_id,existing.status;
      RETURN;
    END IF;
    RAISE EXCEPTION 'Invitation id reused with different content' USING ERRCODE='23505';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM identity.users u WHERE u.id=p_inviter_user_id AND u.status='active') OR
     NOT EXISTS (SELECT 1 FROM identity.phone_identities WHERE user_id=p_inviter_user_id) THEN
    RAISE EXCEPTION 'Inviter is not an active verified user' USING ERRCODE='42501';
  END IF;
  IF p_invitee_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' OR
     (p_relationship_type='merchant_customer' AND NOT
       ((p_inviter_role='merchant' AND p_invitee_role='customer') OR
        (p_inviter_role='customer' AND p_invitee_role='merchant'))) OR
     (p_relationship_type='supplier_buyer' AND NOT
       ((p_inviter_role='supplier' AND p_invitee_role='buyer') OR
        (p_inviter_role='buyer' AND p_invitee_role='supplier'))) OR
     p_relationship_type NOT IN ('merchant_customer','supplier_buyer') THEN
    RAISE EXCEPTION 'Invalid relationship type or role pair' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM identity.phone_identities
             WHERE user_id=p_inviter_user_id AND phone_e164=p_invitee_phone_e164) THEN
    RAISE EXCEPTION 'Cannot invite the same account' USING ERRCODE='23514';
  END IF;
  SELECT user_id INTO invitee_id FROM identity.phone_identities
  WHERE phone_e164=p_invitee_phone_e164;
  IF invitee_id IS NOT NULL AND NOT EXISTS
     (SELECT 1 FROM identity.users WHERE id=invitee_id AND status='active') THEN
    RAISE EXCEPTION 'Invitee account is not active' USING ERRCODE='42501';
  END IF;
  INSERT INTO ledger.relationships(id,status,relationship_type,created_by_user_id)
  VALUES(p_relationship_id,'suspended',p_relationship_type,p_inviter_user_id);
  INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve)
  VALUES(p_relationship_id,p_inviter_user_id,p_inviter_role,'active',true);
  IF invitee_id IS NOT NULL THEN
    INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve)
    VALUES(p_relationship_id,invitee_id,p_invitee_role,'invited',true);
  END IF;
  INSERT INTO ledger.relationship_invitations(
    id,relationship_id,inviter_user_id,invitee_user_id,invitee_phone_e164,relationship_type,
    inviter_role,invitee_role,request_hash,status,expires_at
  ) VALUES (p_invitation_id,p_relationship_id,p_inviter_user_id,invitee_id,p_invitee_phone_e164,
    p_relationship_type,p_inviter_role,p_invitee_role,p_request_hash,'pending',p_expires_at);
  INSERT INTO ledger.relationship_invitation_events(
    invitation_id,relationship_id,actor_user_id,event_type,event_payload
  ) VALUES (p_invitation_id,p_relationship_id,p_inviter_user_id,'created',
    jsonb_build_object('inviteePhoneE164',p_invitee_phone_e164,'relationshipType',p_relationship_type,
      'inviterRole',p_inviter_role,'inviteeRole',p_invitee_role,'expiresAt',p_expires_at));
  RETURN QUERY SELECT p_invitation_id,p_relationship_id,'pending'::text;
END;
$create_relationship$;

CREATE OR REPLACE FUNCTION ledger.decide_relationship_invitation(
  p_invitation_id uuid,p_actor_user_id uuid,p_decision_id uuid,
  p_decision text,p_reason text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql AS $decide_relationship$
DECLARE invite ledger.relationship_invitations%ROWTYPE; active_count bigint; added_user uuid;
BEGIN
  IF p_decision NOT IN ('accepted','rejected') THEN
    RAISE EXCEPTION 'Invalid invitation decision' USING ERRCODE='22023';
  END IF;
  SELECT * INTO invite FROM ledger.relationship_invitations
  WHERE id=p_invitation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitation not found' USING ERRCODE='23503'; END IF;
  IF invite.decision_id IS NOT NULL THEN
    IF invite.decision_id=p_decision_id AND invite.responded_by_user_id=p_actor_user_id AND invite.status=p_decision THEN
      RETURN invite.status;
    END IF;
    RAISE EXCEPTION 'Invitation already decided' USING ERRCODE='55000';
  END IF;
  IF invite.status<>'pending' THEN
    RAISE EXCEPTION 'Invitation is not pending' USING ERRCODE='55000';
  END IF;
  IF p_actor_user_id=invite.inviter_user_id OR NOT EXISTS (
    SELECT 1 FROM identity.phone_identities
    WHERE user_id=p_actor_user_id AND phone_e164=invite.invitee_phone_e164
  ) THEN
    RAISE EXCEPTION 'Only the verified invitee may decide this invitation' USING ERRCODE='42501';
  END IF;
  IF invite.invitee_user_id IS NOT NULL AND invite.invitee_user_id<>p_actor_user_id THEN
    RAISE EXCEPTION 'Invitation belongs to another account' USING ERRCODE='42501';
  END IF;
  IF invite.expires_at<=clock_timestamp() THEN
    UPDATE ledger.relationship_invitations SET status='expired',responded_at=clock_timestamp() WHERE id=invite.id;
    UPDATE ledger.relationships SET status='closed',closed_at=clock_timestamp() WHERE id=invite.relationship_id AND status='suspended';
    INSERT INTO ledger.relationship_invitation_events(invitation_id,relationship_id,event_type,event_payload)
    VALUES(invite.id,invite.relationship_id,'expired',jsonb_build_object('reason','expired_before_response'));
    RETURN 'expired';
  END IF;
  IF p_decision='accepted' THEN
    PERFORM 1 FROM ledger.relationships WHERE id=invite.relationship_id AND status='suspended' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invitation relationship is not pending' USING ERRCODE='55000'; END IF;
    SELECT count(*) INTO active_count FROM ledger.relationship_members
    WHERE relationship_id=invite.relationship_id AND status='active';
    IF active_count<>1 OR NOT EXISTS (SELECT 1 FROM ledger.relationship_members
       WHERE relationship_id=invite.relationship_id AND user_id=invite.inviter_user_id AND status='active') THEN
      RAISE EXCEPTION 'Invitation relationship is not awaiting its second party' USING ERRCODE='23514';
    END IF;
    INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve)
    VALUES(invite.relationship_id,p_actor_user_id,invite.invitee_role,'active',true)
    ON CONFLICT(relationship_id,user_id) DO UPDATE
      SET role_label=EXCLUDED.role_label,status='active',can_approve=true
      WHERE ledger.relationship_members.status='invited'
    RETURNING user_id INTO added_user;
    IF added_user IS NULL THEN RAISE EXCEPTION 'Invitee membership cannot be activated' USING ERRCODE='23514'; END IF;
    UPDATE ledger.relationships SET status='active' WHERE id=invite.relationship_id AND status='suspended';
    UPDATE ledger.relationship_invitations SET status='accepted',invitee_user_id=p_actor_user_id,
      decision_id=p_decision_id,decision_reason=p_reason,responded_at=clock_timestamp(),responded_by_user_id=p_actor_user_id
    WHERE id=invite.id;
  ELSE
    UPDATE ledger.relationship_invitations SET status='rejected',decision_id=p_decision_id,
      decision_reason=p_reason,responded_at=clock_timestamp(),responded_by_user_id=p_actor_user_id
    WHERE id=invite.id;
    UPDATE ledger.relationships SET status='closed',closed_at=clock_timestamp()
    WHERE id=invite.relationship_id AND status='suspended';
  END IF;
  INSERT INTO ledger.relationship_invitation_events(
    invitation_id,relationship_id,actor_user_id,event_type,event_payload
  ) VALUES (invite.id,invite.relationship_id,p_actor_user_id,p_decision,
    jsonb_build_object('decisionId',p_decision_id,'reason',p_reason,'relationshipStatus',
      CASE WHEN p_decision='accepted' THEN 'active' ELSE 'closed' END));
  RETURN p_decision;
END;
$decide_relationship$;

CREATE OR REPLACE FUNCTION ledger.expire_relationship_invitations(p_user_id uuid)
RETURNS integer LANGUAGE plpgsql AS $expire_relationship$
DECLARE expired_count integer;
BEGIN
  WITH expired AS (
    UPDATE ledger.relationship_invitations ri SET status='expired',responded_at=clock_timestamp()
    WHERE ri.status='pending' AND ri.expires_at<=clock_timestamp() AND ri.invitee_phone_e164 IN
      (SELECT phone_e164 FROM identity.phone_identities WHERE user_id=p_user_id)
    RETURNING ri.id,ri.relationship_id
  ), closed AS (
    UPDATE ledger.relationships r SET status='closed',closed_at=clock_timestamp()
    WHERE r.id IN (SELECT relationship_id FROM expired) AND r.status='suspended'
    RETURNING r.id
  )
  INSERT INTO ledger.relationship_invitation_events(invitation_id,relationship_id,event_type,event_payload)
  SELECT e.id,e.relationship_id,'expired',jsonb_build_object('reason','expired_before_response') FROM expired e;
  GET DIAGNOSTICS expired_count=ROW_COUNT;
  RETURN expired_count;
END;
$expire_relationship$;
