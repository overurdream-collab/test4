\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE refresh_test_user AS
SELECT identity.get_or_create_user_by_phone('+967771234599') AS user_id;

INSERT INTO identity.devices(id,user_id,device_label,platform)
SELECT '84000000-0000-0000-0000-000000000001',user_id,'Refresh Test Android','android'
FROM refresh_test_user;

INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at)
SELECT '85000000-0000-0000-0000-000000000001',user_id,
'84000000-0000-0000-0000-000000000001',now()+interval '30 days'
FROM refresh_test_user;

INSERT INTO identity.refresh_tokens(id,session_id,user_id,device_id,token_hash,issued_at,expires_at)
SELECT '86000000-0000-0000-0000-000000000001','85000000-0000-0000-0000-000000000001',user_id,
'84000000-0000-0000-0000-000000000001',decode(repeat('11',32),'hex'),now(),now()+interval '30 days'
FROM refresh_test_user;

-- A live token rotates once and records both sides of the rotation.
DO $rotate_once$
DECLARE outcome record;
BEGIN
  SELECT * INTO outcome FROM identity.rotate_refresh_token(
    decode(repeat('11',32),'hex'),
    '86000000-0000-0000-0000-000000000002',
    decode(repeat('12',32),'hex'),
    now()+interval '30 days'
  );
  IF outcome.status<>'rotated' THEN
    RAISE EXCEPTION 'Expected rotated, got %',outcome.status;
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM identity.refresh_tokens
    WHERE id='86000000-0000-0000-0000-000000000001'
      AND used_at IS NOT NULL AND revoked_at IS NOT NULL
      AND replaced_by='86000000-0000-0000-0000-000000000002'
  ) THEN
    RAISE EXCEPTION 'Old refresh token was not marked as rotated';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM identity.refresh_tokens
    WHERE id='86000000-0000-0000-0000-000000000002'
      AND rotated_from='86000000-0000-0000-0000-000000000001'
      AND revoked_at IS NULL AND used_at IS NULL
  ) THEN
    RAISE EXCEPTION 'New refresh token was not linked to its predecessor';
  END IF;
END;
$rotate_once$;

-- Replaying a rotated token is treated as reuse and revokes the whole session.
DO $reuse_detected$
DECLARE outcome record;
BEGIN
  SELECT * INTO outcome FROM identity.rotate_refresh_token(
    decode(repeat('11',32),'hex'),
    '86000000-0000-0000-0000-000000000003',
    decode(repeat('13',32),'hex'),
    now()+interval '30 days'
  );
  IF outcome.status<>'reuse_detected' THEN
    RAISE EXCEPTION 'Expected reuse_detected, got %',outcome.status;
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM identity.auth_sessions
    WHERE id='85000000-0000-0000-0000-000000000001' AND revoked_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Reuse did not revoke the session';
  END IF;
  IF EXISTS(
    SELECT 1 FROM identity.refresh_tokens
    WHERE session_id='85000000-0000-0000-0000-000000000001' AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reuse left a live refresh token in the session';
  END IF;
END;
$reuse_detected$;

-- Unknown tokens are rejected without creating a row.
DO $unknown_token$
DECLARE outcome record;
BEGIN
  SELECT * INTO outcome FROM identity.rotate_refresh_token(
    decode(repeat('ff',32),'hex'),
    '86000000-0000-0000-0000-000000000004',
    decode(repeat('14',32),'hex'),
    now()+interval '30 days'
  );
  IF outcome.status<>'invalid' THEN
    RAISE EXCEPTION 'Unknown refresh token returned %',outcome.status;
  END IF;
  IF EXISTS(SELECT 1 FROM identity.refresh_tokens WHERE id='86000000-0000-0000-0000-000000000004') THEN
    RAISE EXCEPTION 'Unknown refresh token created a row';
  END IF;
END;
$unknown_token$;

-- Expired tokens are revoked and cannot rotate.
INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at)
SELECT '85000000-0000-0000-0000-000000000002',user_id,
'84000000-0000-0000-0000-000000000001',now()+interval '30 days'
FROM refresh_test_user;
INSERT INTO identity.refresh_tokens(id,session_id,user_id,device_id,token_hash,issued_at,expires_at)
SELECT '86000000-0000-0000-0000-000000000011','85000000-0000-0000-0000-000000000002',user_id,
'84000000-0000-0000-0000-000000000001',decode(repeat('21',32),'hex'),now()-interval '31 days',now()-interval '1 day'
FROM refresh_test_user;

DO $expired_token$
DECLARE outcome record;
BEGIN
  SELECT * INTO outcome FROM identity.rotate_refresh_token(
    decode(repeat('21',32),'hex'),
    '86000000-0000-0000-0000-000000000012',
    decode(repeat('22',32),'hex'),
    now()+interval '30 days'
  );
  IF outcome.status<>'expired' THEN
    RAISE EXCEPTION 'Expected expired, got %',outcome.status;
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM identity.refresh_tokens
    WHERE id='86000000-0000-0000-0000-000000000011' AND revoked_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Expired refresh token was not revoked';
  END IF;
END;
$expired_token$;

-- A revoked device blocks rotation even when the token itself is still valid.
INSERT INTO identity.devices(id,user_id,device_label,platform,status,revoked_at)
SELECT '84000000-0000-0000-0000-000000000002',user_id,'Revoked Device','android','revoked',now()
FROM refresh_test_user;
INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at)
SELECT '85000000-0000-0000-0000-000000000003',user_id,
'84000000-0000-0000-0000-000000000002',now()+interval '30 days'
FROM refresh_test_user;
INSERT INTO identity.refresh_tokens(id,session_id,user_id,device_id,token_hash,issued_at,expires_at)
SELECT '86000000-0000-0000-0000-000000000021','85000000-0000-0000-0000-000000000003',user_id,
'84000000-0000-0000-0000-000000000002',decode(repeat('31',32),'hex'),now(),now()+interval '30 days'
FROM refresh_test_user;

DO $inactive_session$
DECLARE outcome record;
BEGIN
  SELECT * INTO outcome FROM identity.rotate_refresh_token(
    decode(repeat('31',32),'hex'),
    '86000000-0000-0000-0000-000000000022',
    decode(repeat('32',32),'hex'),
    now()+interval '30 days'
  );
  IF outcome.status<>'session_inactive' THEN
    RAISE EXCEPTION 'Expected session_inactive, got %',outcome.status;
  END IF;
END;
$inactive_session$;

-- Logout revokes every live session and refresh token on the device.
INSERT INTO identity.devices(id,user_id,device_label,platform)
SELECT '84000000-0000-0000-0000-000000000003',user_id,'Logout Device','android'
FROM refresh_test_user;
INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at)
SELECT '85000000-0000-0000-0000-000000000004',user_id,
'84000000-0000-0000-0000-000000000003',now()+interval '30 days'
FROM refresh_test_user;
INSERT INTO identity.refresh_tokens(id,session_id,user_id,device_id,token_hash,issued_at,expires_at)
SELECT '86000000-0000-0000-0000-000000000031','85000000-0000-0000-0000-000000000004',user_id,
'84000000-0000-0000-0000-000000000003',decode(repeat('41',32),'hex'),now(),now()+interval '30 days'
FROM refresh_test_user;

DO $logout_device$
DECLARE revoked integer;
BEGIN
  SELECT identity.revoke_device_sessions(
    (SELECT user_id FROM refresh_test_user),
    '84000000-0000-0000-0000-000000000003'
  ) INTO revoked;
  IF revoked<>1 THEN
    RAISE EXCEPTION 'Logout revoked % sessions instead of 1',revoked;
  END IF;
  IF EXISTS(
    SELECT 1 FROM identity.refresh_tokens
    WHERE session_id='85000000-0000-0000-0000-000000000004' AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Logout left a live refresh token';
  END IF;
END;
$logout_device$;

ROLLBACK;
SELECT 'identity refresh token tests passed' AS result;
