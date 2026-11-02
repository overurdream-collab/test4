-- Rotating refresh tokens for verified phone sessions.
-- Only a keyed digest is stored; raw refresh tokens never reach the database.

CREATE TABLE identity.refresh_tokens (
  id uuid PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES identity.auth_sessions(id),
  user_id uuid NOT NULL REFERENCES identity.users(id),
  device_id uuid NOT NULL,
  token_hash bytea NOT NULL UNIQUE CHECK (octet_length(token_hash)=32),
  issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  revoked_at timestamptz,
  rotated_from uuid REFERENCES identity.refresh_tokens(id),
  replaced_by uuid REFERENCES identity.refresh_tokens(id),
  FOREIGN KEY (device_id,user_id) REFERENCES identity.devices(id,user_id),
  CHECK (expires_at > issued_at),
  CHECK (revoked_at IS NULL OR revoked_at >= issued_at)
);

CREATE INDEX identity_refresh_tokens_session_idx
  ON identity.refresh_tokens(session_id);

CREATE INDEX identity_refresh_tokens_active_idx
  ON identity.refresh_tokens(user_id,device_id,expires_at)
  WHERE revoked_at IS NULL;

-- Rotate a refresh token atomically. Reusing an already rotated or revoked
-- token is treated as theft: the whole session is revoked before returning.
CREATE OR REPLACE FUNCTION identity.rotate_refresh_token(
  p_token_hash bytea,
  p_new_id uuid,
  p_new_hash bytea,
  p_new_expires_at timestamptz,
  p_now timestamptz DEFAULT clock_timestamp()
) RETURNS TABLE(status text,user_id uuid,device_id uuid,session_id uuid)
LANGUAGE plpgsql AS $rotate_refresh$
DECLARE current identity.refresh_tokens%ROWTYPE; session_active boolean;
BEGIN
  IF p_token_hash IS NULL OR octet_length(p_token_hash)<>32
     OR p_new_hash IS NULL OR octet_length(p_new_hash)<>32
     OR p_new_id IS NULL OR p_new_expires_at<=p_now THEN
    RAISE EXCEPTION 'Invalid refresh token rotation' USING ERRCODE='22023';
  END IF;

  SELECT * INTO current FROM identity.refresh_tokens
  WHERE token_hash=p_token_hash FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'invalid'::text,NULL::uuid,NULL::uuid,NULL::uuid;
    RETURN;
  END IF;

  IF current.used_at IS NOT NULL OR current.revoked_at IS NOT NULL OR current.replaced_by IS NOT NULL THEN
    UPDATE identity.auth_sessions SET revoked_at=COALESCE(revoked_at,p_now)
    WHERE id=current.session_id AND revoked_at IS NULL;
    UPDATE identity.refresh_tokens rt SET revoked_at=COALESCE(rt.revoked_at,p_now)
    WHERE rt.session_id=current.session_id AND rt.revoked_at IS NULL;
    RETURN QUERY SELECT 'reuse_detected'::text,current.user_id,current.device_id,current.session_id;
    RETURN;
  END IF;

  IF current.expires_at<=p_now THEN
    UPDATE identity.refresh_tokens SET revoked_at=p_now WHERE id=current.id;
    RETURN QUERY SELECT 'expired'::text,current.user_id,current.device_id,current.session_id;
    RETURN;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM identity.auth_sessions s
    JOIN identity.devices d ON d.id=s.device_id AND d.user_id=s.user_id
    JOIN identity.users u ON u.id=s.user_id
    WHERE s.id=current.session_id AND s.user_id=current.user_id AND s.device_id=current.device_id
      AND s.expires_at>p_now AND s.revoked_at IS NULL
      AND d.status='active' AND u.status='active'
  ) INTO session_active;
  IF NOT session_active THEN
    UPDATE identity.refresh_tokens rt SET revoked_at=p_now
    WHERE rt.session_id=current.session_id AND rt.revoked_at IS NULL;
    RETURN QUERY SELECT 'session_inactive'::text,current.user_id,current.device_id,current.session_id;
    RETURN;
  END IF;

  INSERT INTO identity.refresh_tokens(
    id,session_id,user_id,device_id,token_hash,issued_at,expires_at,rotated_from
  ) VALUES(
    p_new_id,current.session_id,current.user_id,current.device_id,p_new_hash,p_now,p_new_expires_at,current.id
  );
  UPDATE identity.refresh_tokens
  SET used_at=p_now,revoked_at=p_now,replaced_by=p_new_id
  WHERE id=current.id;
  RETURN QUERY SELECT 'rotated'::text,current.user_id,current.device_id,current.session_id;
END;
$rotate_refresh$;

-- Logging out a device revokes every live session and refresh token on it.
CREATE OR REPLACE FUNCTION identity.revoke_device_sessions(
  p_user_id uuid,p_device_id uuid,p_now timestamptz DEFAULT clock_timestamp()
) RETURNS integer LANGUAGE plpgsql AS $revoke_device$
DECLARE revoked_sessions integer;
BEGIN
  UPDATE identity.auth_sessions SET revoked_at=COALESCE(revoked_at,p_now)
  WHERE user_id=p_user_id AND device_id=p_device_id AND revoked_at IS NULL;
  GET DIAGNOSTICS revoked_sessions = ROW_COUNT;
  UPDATE identity.refresh_tokens SET revoked_at=COALESCE(revoked_at,p_now)
  WHERE user_id=p_user_id AND device_id=p_device_id AND revoked_at IS NULL;
  RETURN revoked_sessions;
END;
$revoke_device$;
