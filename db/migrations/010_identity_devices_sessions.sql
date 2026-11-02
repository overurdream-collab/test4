-- Identity, verified phone ownership, devices, sessions and OTP challenges.
-- OTP delivery is intentionally provider-agnostic; plaintext codes are never stored.

CREATE SCHEMA IF NOT EXISTS identity;

CREATE TABLE identity.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','suspended')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.user_profiles (
  user_id uuid PRIMARY KEY REFERENCES identity.users(id),
  display_name text CHECK (display_name IS NULL OR length(display_name) BETWEEN 1 AND 80),
  locale text NOT NULL DEFAULT 'ar' CHECK (locale IN ('ar','en')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE identity.phone_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES identity.users(id),
  phone_e164 text NOT NULL UNIQUE
    CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id,user_id)
);

CREATE INDEX phone_identities_by_user_idx
  ON identity.phone_identities(user_id);

CREATE TABLE identity.devices (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES identity.users(id),
  device_label text NOT NULL CHECK (length(device_label) BETWEEN 1 AND 100),
  platform text NOT NULL CHECK (platform IN ('android','ios','web')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  registered_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  UNIQUE (id,user_id),
  CHECK ((status='active' AND revoked_at IS NULL) OR
         (status='revoked' AND revoked_at IS NOT NULL))
);

CREATE INDEX identity_devices_by_user_idx
  ON identity.devices(user_id,status);

CREATE TABLE identity.auth_sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  FOREIGN KEY (device_id,user_id) REFERENCES identity.devices(id,user_id),
  CHECK (expires_at > created_at)
);

CREATE INDEX identity_sessions_active_by_user_idx
  ON identity.auth_sessions(user_id,expires_at)
  WHERE revoked_at IS NULL;

CREATE TABLE identity.otp_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 text NOT NULL CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  purpose text NOT NULL DEFAULT 'login' CHECK (purpose='login'),
  code_hash bytea NOT NULL CHECK (octet_length(code_hash)=32),
  requested_ip_hash bytea CHECK (requested_ip_hash IS NULL OR octet_length(requested_ip_hash)=32),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','delivered','failed','consumed','locked','expired')),
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  CHECK (expires_at > created_at),
  CHECK ((status='consumed' AND consumed_at IS NOT NULL) OR
         (status<>'consumed' AND consumed_at IS NULL))
);

CREATE INDEX identity_otp_phone_window_idx
  ON identity.otp_challenges(phone_e164,created_at DESC);
CREATE INDEX identity_otp_ip_window_idx
  ON identity.otp_challenges(requested_ip_hash,created_at DESC)
  WHERE requested_ip_hash IS NOT NULL;

-- Reserve OTP challenges atomically under phone/IP advisory locks to prevent
-- concurrent requests from bypassing the rolling-window rate limits.
CREATE OR REPLACE FUNCTION identity.create_otp_challenge(
  p_phone_e164 text,p_code_hash bytea,p_ip_hash bytea,p_expires_at timestamptz
) RETURNS uuid LANGUAGE plpgsql AS $otp$
DECLARE phone_requests bigint; ip_requests bigint; challenge_id uuid;
BEGIN
  IF p_code_hash IS NULL OR octet_length(p_code_hash)<>32 OR p_ip_hash IS NULL OR octet_length(p_ip_hash)<>32 OR p_expires_at<=clock_timestamp() OR p_expires_at>clock_timestamp()+interval '6 minutes' THEN
    RAISE EXCEPTION 'Invalid OTP challenge request' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('otp-phone:'||p_phone_e164,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('otp-ip:'||encode(p_ip_hash,'hex'),0));
  SELECT count(*) INTO phone_requests FROM identity.otp_challenges
  WHERE phone_e164=p_phone_e164 AND created_at>clock_timestamp()-interval '15 minutes';
  SELECT count(*) INTO ip_requests FROM identity.otp_challenges
  WHERE requested_ip_hash=p_ip_hash AND created_at>clock_timestamp()-interval '1 hour';
  IF phone_requests>=3 OR ip_requests>=10 THEN RETURN NULL; END IF;
  INSERT INTO identity.otp_challenges(phone_e164,code_hash,requested_ip_hash,status,created_at,expires_at)
  VALUES(p_phone_e164,p_code_hash,p_ip_hash,'pending',clock_timestamp(),p_expires_at)
  RETURNING id INTO challenge_id;
  RETURN challenge_id;
END;
$otp$;

CREATE OR REPLACE FUNCTION identity.get_or_create_user_by_phone(p_phone_e164 text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE target_user uuid; target_status text;
BEGIN
  IF p_phone_e164 IS NULL OR p_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'Invalid E.164 phone' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_phone_e164,0));
  SELECT pi.user_id,u.status INTO target_user,target_status
  FROM identity.phone_identities pi
  JOIN identity.users u ON u.id=pi.user_id
  WHERE pi.phone_e164=p_phone_e164
  FOR UPDATE OF pi,u;
  IF FOUND THEN
    IF target_status<>'active' THEN
      RAISE EXCEPTION 'User is suspended' USING ERRCODE='42501';
    END IF;
    UPDATE identity.phone_identities SET verified_at=clock_timestamp()
    WHERE phone_e164=p_phone_e164;
    RETURN target_user;
  END IF;
  INSERT INTO identity.users DEFAULT VALUES RETURNING id INTO target_user;
  INSERT INTO identity.phone_identities(user_id,phone_e164,verified_at)
  VALUES(target_user,p_phone_e164,clock_timestamp());
  INSERT INTO identity.user_profiles(user_id) VALUES(target_user);
  RETURN target_user;
END;
$$;

-- Consume only the newest live challenge. Failed guesses count and lock at five.
-- The application supplies an HMAC-SHA256 digest; the OTP itself is never stored.
CREATE OR REPLACE FUNCTION identity.consume_otp_challenge(
  p_phone_e164 text,p_code_hash bytea,p_now timestamptz DEFAULT clock_timestamp()
) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE challenge identity.otp_challenges%ROWTYPE;
BEGIN
  IF p_code_hash IS NULL OR octet_length(p_code_hash)<>32 THEN
    RETURN false;
  END IF;
  SELECT * INTO challenge
  FROM identity.otp_challenges
  WHERE phone_e164=p_phone_e164 AND purpose='login'
    AND status='delivered' AND consumed_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF challenge.expires_at<=p_now THEN
    UPDATE identity.otp_challenges SET status='expired' WHERE id=challenge.id;
    RETURN false;
  END IF;
  IF challenge.attempts>=5 THEN
    UPDATE identity.otp_challenges SET status='locked' WHERE id=challenge.id;
    RETURN false;
  END IF;
  IF challenge.code_hash=p_code_hash THEN
    UPDATE identity.otp_challenges
    SET status='consumed',consumed_at=p_now,attempts=attempts+1
    WHERE id=challenge.id;
    RETURN true;
  END IF;
  UPDATE identity.otp_challenges
  SET attempts=attempts+1,
      status=CASE WHEN attempts+1>=5 THEN 'locked' ELSE status END
  WHERE id=challenge.id;
  RETURN false;
END;
$$;

     OR p_code_hash IS NULL OR octet_length(p_code_hash)<>32
     OR p_ip_hash IS NULL OR octet_length(p_ip_hash)<>32
     OR p_expires_at<=clock_timestamp()
     OR p_expires_at>clock_timestamp()+interval '6 minutes' THEN
    RAISE EXCEPTION 'Invalid OTP challenge request' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('otp-phone:'||p_phone_e164,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('otp-ip:'||encode(p_ip_hash,'hex'),0));
  SELECT count(*) INTO phone_requests FROM identity.otp_challenges
  WHERE phone_e164=p_phone_e164 AND created_at>clock_timestamp()-interval '15 minutes';
  SELECT count(*) INTO ip_requests FROM identity.otp_challenges
  WHERE requested_ip_hash=p_ip_hash AND created_at>clock_timestamp()-interval '1 hour';
  IF phone_requests>=3 OR ip_requests>=10 THEN RETURN NULL; END IF;
  INSERT INTO identity.otp_challenges(phone_e164,code_hash,requested_ip_hash,status,created_at,expires_at)
  VALUES(p_phone_e164,p_code_hash,p_ip_hash,'pending',clock_timestamp(),p_expires_at)
  RETURNING id INTO challenge_id;
  RETURN challenge_id;
END;
$;

-- Serialize registration for the same verified phone; one phone maps to one account.
CREATE OR REPLACE FUNCTION identity.get_or_create_user_by_phone(p_phone_e164 text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE target_user uuid; target_status text;
BEGIN
  IF p_phone_e164 IS NULL OR p_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'Invalid E.164 phone' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_phone_e164,0));
  SELECT pi.user_id,u.status INTO target_user,target_status
  FROM identity.phone_identities pi
  JOIN identity.users u ON u.id=pi.user_id
  WHERE pi.phone_e164=p_phone_e164
  FOR UPDATE OF pi,u;
  IF FOUND THEN
    IF target_status<>'active' THEN
      RAISE EXCEPTION 'User is suspended' USING ERRCODE='42501';
    END IF;
    UPDATE identity.phone_identities SET verified_at=clock_timestamp()
    WHERE phone_e164=p_phone_e164;
    RETURN target_user;
  END IF;
  INSERT INTO identity.users DEFAULT VALUES RETURNING id INTO target_user;
  INSERT INTO identity.phone_identities(user_id,phone_e164,verified_at)
  VALUES(target_user,p_phone_e164,clock_timestamp());
  INSERT INTO identity.user_profiles(user_id) VALUES(target_user);
  RETURN target_user;
END;
$$;

-- Consume only the newest live challenge. Failed guesses count and lock at five.
-- The application supplies an HMAC-SHA256 digest; the OTP itself is never stored.
CREATE OR REPLACE FUNCTION identity.consume_otp_challenge(
  p_phone_e164 text,p_code_hash bytea,p_now timestamptz DEFAULT clock_timestamp()
) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE challenge identity.otp_challenges%ROWTYPE;
BEGIN
  IF p_code_hash IS NULL OR octet_length(p_code_hash)<>32 THEN
    RETURN false;
  END IF;
  SELECT * INTO challenge
  FROM identity.otp_challenges
  WHERE phone_e164=p_phone_e164 AND purpose='login'
    AND status='delivered' AND consumed_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF challenge.expires_at<=p_now THEN
    UPDATE identity.otp_challenges SET status='expired' WHERE id=challenge.id;
    RETURN false;
  END IF;
  IF challenge.attempts>=5 THEN
    UPDATE identity.otp_challenges SET status='locked' WHERE id=challenge.id;
    RETURN false;
  END IF;
  IF challenge.code_hash=p_code_hash THEN
    UPDATE identity.otp_challenges
    SET status='consumed',consumed_at=p_now,attempts=attempts+1
    WHERE id=challenge.id;
    RETURN true;
  END IF;
  UPDATE identity.otp_challenges
  SET attempts=attempts+1,
      status=CASE WHEN attempts+1>=5 THEN 'locked' ELSE status END
  WHERE id=challenge.id;
  RETURN false;
END;
$$;
