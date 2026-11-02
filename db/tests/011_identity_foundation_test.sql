\set ON_ERROR_STOP on
BEGIN;

SELECT identity.get_or_create_user_by_phone('+967771234567') AS first_user \gset
SELECT identity.get_or_create_user_by_phone('+967771234567') AS same_user \gset
DO $$
BEGIN
 IF :'first_user' <> :'same_user' THEN
  RAISE EXCEPTION 'Same verified phone created more than one user';
 END IF;
END;
$$;

INSERT INTO identity.devices(id,user_id,device_label,platform)
VALUES('81000000-0000-0000-0000-000000000001',:'first_user','Test Android','android');

INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at)
VALUES('82000000-0000-0000-0000-000000000001',:'first_user',
'81000000-0000-0000-0000-000000000001',now()+interval '15 minutes');

INSERT INTO identity.otp_challenges(id,phone_e164,code_hash,requested_ip_hash,status,expires_at)
VALUES('83000000-0000-0000-0000-000000000001','+967771234568',
decode(repeat('ab',32),'hex'),decode(repeat('cd',32),'hex'),'delivered',now()+interval '5 minutes');

DO $$
BEGIN
 IF identity.consume_otp_challenge('+967771234568',decode(repeat('ef',32),'hex')) THEN
  RAISE EXCEPTION 'Wrong OTP hash unexpectedly accepted';
 END IF;
 IF identity.consume_otp_challenge('+967771234568',decode(repeat('ab',32),'hex')) THEN
  RAISE EXCEPTION 'OTP should be locked after wrong attempts only if max reached';
 END IF;
END;
$$;

-- A fresh challenge accepts exactly once and cannot be replayed.
INSERT INTO identity.otp_challenges(id,phone_e164,code_hash,status,expires_at)
VALUES('83000000-0000-0000-0000-000000000002','+967771234569',
decode(repeat('12',32),'hex'),'delivered',now()+interval '5 minutes');
DO $$
BEGIN
 IF NOT identity.consume_otp_challenge('+967771234569',decode(repeat('12',32),'hex')) THEN
  RAISE EXCEPTION 'Correct OTP was not accepted';
 END IF;
 IF identity.consume_otp_challenge('+967771234569',decode(repeat('12',32),'hex')) THEN
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

ROLLBACK;
SELECT 'identity foundation tests passed' AS result;
