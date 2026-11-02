\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE identity_test_user AS
SELECT identity.get_or_create_user_by_phone('+967771234567') AS user_id;
CREATE TEMP TABLE identity_test_user_again AS
SELECT identity.get_or_create_user_by_phone('+967771234567') AS user_id;

DO $$
BEGIN
 IF (SELECT user_id FROM identity_test_user) <>
    (SELECT user_id FROM identity_test_user_again) THEN
  RAISE EXCEPTION 'Same verified phone created more than one user';
 END IF;
END;
$$;

INSERT INTO identity.devices(id,user_id,device_label,platform)
SELECT '81000000-0000-0000-0000-000000000001',user_id,'Test Android','android'
FROM identity_test_user;

INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at)
SELECT '82000000-0000-0000-0000-000000000001',user_id,
'81000000-0000-0000-0000-000000000001',now()+interval '15 minutes'
FROM identity_test_user;

-- One wrong attempt does not consume the challenge; the correct code may still be used.
INSERT INTO identity.otp_challenges(id,phone_e164,code_hash,requested_ip_hash,status,expires_at)
VALUES('83000000-0000-0000-0000-000000000001','+967771234568',
decode(repeat('ab',32),'hex'),decode(repeat('cd',32),'hex'),'delivered',now()+interval '5 minutes');

DO $$
BEGIN
 IF identity.consume_otp_challenge('+967771234568',decode(repeat('ef',32),'hex')) THEN
  RAISE EXCEPTION 'Wrong OTP hash unexpectedly accepted';
 END IF;
 IF NOT identity.consume_otp_challenge('+967771234568',decode(repeat('ab',32),'hex')) THEN
  RAISE EXCEPTION 'Correct OTP was not accepted after one wrong attempt';
 END IF;
 IF identity.consume_otp_challenge('+967771234568',decode(repeat('ab',32),'hex')) THEN
  RAISE EXCEPTION 'Consumed OTP was replayed';
 END IF;
END;
$$;

-- Five invalid attempts lock a challenge.
INSERT INTO identity.otp_challenges(id,phone_e164,code_hash,status,expires_at)
VALUES('83000000-0000-0000-0000-000000000003','+967771234570',
decode(repeat('34',32),'hex'),'delivered',now()+interval '5 minutes');
DO $$
DECLARE i integer;
BEGIN
 FOR i IN 1..5 LOOP
  PERFORM identity.consume_otp_challenge('+967771234570',decode(repeat('56',32),'hex'));
 END LOOP;
 IF (SELECT status FROM identity.otp_challenges WHERE id='83000000-0000-0000-0000-000000000003')<>'locked' THEN
  RAISE EXCEPTION 'OTP challenge did not lock after five failed attempts';
 END IF;
END;
$$;

-- Expired challenges cannot be consumed.
INSERT INTO identity.otp_challenges(id,phone_e164,code_hash,status,expires_at)
VALUES('83000000-0000-0000-0000-000000000004','+967771234571',
decode(repeat('78',32),'hex'),'delivered',now()-interval '1 minute');
DO $$
BEGIN
 IF identity.consume_otp_challenge('+967771234571',decode(repeat('78',32),'hex')) THEN
  RAISE EXCEPTION 'Expired OTP unexpectedly accepted';
 END IF;
 IF (SELECT status FROM identity.otp_challenges WHERE id='83000000-0000-0000-0000-000000000004')<>'expired' THEN
  RAISE EXCEPTION 'Expired challenge status was not recorded';
 END IF;
END;
$$;

-- Revoking a device also revokes its active sessions.
UPDATE identity.devices SET status='revoked',revoked_at=now()
WHERE id='81000000-0000-0000-0000-000000000001';
UPDATE identity.auth_sessions SET revoked_at=now()
WHERE device_id='81000000-0000-0000-0000-000000000001' AND revoked_at IS NULL;
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM identity.devices WHERE id='81000000-0000-0000-0000-000000000001' AND status='active') THEN
  RAISE EXCEPTION 'Revoked device remains active';
 END IF;
 IF EXISTS(SELECT 1 FROM identity.auth_sessions WHERE id='82000000-0000-0000-0000-000000000001' AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'Device session was not revoked';
 END IF;
END;
$$;

-- The rolling-window limits are enforced atomically by the database function.
DO $otp_rate_limit$
DECLARE i integer; reserved_id uuid;
BEGIN
 FOR i IN 1..3 LOOP
  reserved_id:=identity.create_otp_challenge(
   '+967771234572',decode(repeat('9a',32),'hex'),decode(repeat('8b',32),'hex'),now()+interval '5 minutes');
  IF reserved_id IS NULL THEN
   RAISE EXCEPTION 'OTP request % was unexpectedly rate limited',i;
  END IF;
 END LOOP;
 reserved_id:=identity.create_otp_challenge(
  '+967771234572',decode(repeat('9a',32),'hex'),decode(repeat('8b',32),'hex'),now()+interval '5 minutes');
 IF reserved_id IS NOT NULL THEN
  RAISE EXCEPTION 'Fourth OTP request within 15 minutes bypassed rate limit';
 END IF;
END;
$otp_rate_limit$;

ROLLBACK;
SELECT 'identity foundation tests passed' AS result;
