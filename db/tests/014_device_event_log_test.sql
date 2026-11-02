\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE device_log_user AS
SELECT identity.get_or_create_user_by_phone('+967771234599') AS user_id;

INSERT INTO identity.devices(id,user_id,device_label,platform)
SELECT '84000000-0000-0000-0000-000000000101',user_id,'Audit Device','android'
FROM device_log_user;

INSERT INTO identity.auth_sessions(id,user_id,device_id,expires_at)
SELECT '85000000-0000-0000-0000-000000000101',user_id,
'84000000-0000-0000-0000-000000000101',now()+interval '30 days'
FROM device_log_user;

DO $registration_events$
BEGIN
  IF (SELECT count(*) FROM identity.device_events
      WHERE device_id='84000000-0000-0000-0000-000000000101'
        AND event_type='device.registered') <> 1 THEN
    RAISE EXCEPTION 'Device registration did not append exactly one event';
  END IF;
  IF (SELECT count(*) FROM identity.device_events
      WHERE device_id='84000000-0000-0000-0000-000000000101'
        AND event_type='session.started') <> 1 THEN
    RAISE EXCEPTION 'Session start did not append exactly one event';
  END IF;
END;
$registration_events$;

UPDATE identity.devices
SET status='revoked',revoked_at=now()
WHERE id='84000000-0000-0000-0000-000000000101';

UPDATE identity.auth_sessions
SET revoked_at=now()
WHERE id='85000000-0000-0000-0000-000000000101' AND revoked_at IS NULL;

DO $revocation_events$
DECLARE event_types text[];
BEGIN
  SELECT array_agg(event_type ORDER BY created_at,event_type) INTO event_types
  FROM identity.device_events
  WHERE device_id='84000000-0000-0000-0000-000000000101';
  IF event_types IS NULL OR array_length(event_types,1)<>4 THEN
    RAISE EXCEPTION 'Expected four lifecycle events, got %',event_types;
  END IF;
  IF NOT ('device.revoked'=ANY(event_types)) OR NOT ('session.revoked'=ANY(event_types)) THEN
    RAISE EXCEPTION 'Revocation events missing: %',event_types;
  END IF;
END;
$revocation_events$;

-- Updating or deleting an audit row must fail even for the owning role.
DO $reject_update$
BEGIN
  BEGIN
    UPDATE identity.device_events SET event_type='device.revoked'
    WHERE device_id='84000000-0000-0000-0000-000000000101';
    RAISE EXCEPTION 'Device event update unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$reject_update$;

DO $reject_delete$
BEGIN
  BEGIN
    DELETE FROM identity.device_events
    WHERE device_id='84000000-0000-0000-0000-000000000101';
    RAISE EXCEPTION 'Device event delete unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$reject_delete$;

DO $reject_truncate$
BEGIN
  BEGIN
    TRUNCATE identity.device_events;
    RAISE EXCEPTION 'Device event truncate unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$reject_truncate$;

DO $events_intact$
BEGIN
  IF (SELECT count(*) FROM identity.device_events
      WHERE device_id='84000000-0000-0000-0000-000000000101') <> 4 THEN
    RAISE EXCEPTION 'Audit rows changed after rejected mutations';
  END IF;
END;
$events_intact$;

-- Ownership is part of the composite key: an event cannot point at another
-- user's device.
INSERT INTO identity.devices(id,user_id,device_label,platform)
SELECT '84000000-0000-0000-0000-000000000102',
       identity.get_or_create_user_by_phone('+967771234598'),'Other Device','ios';

DO $reject_cross_user_event$
BEGIN
  BEGIN
    INSERT INTO identity.device_events(device_id,user_id,event_type)
    VALUES('84000000-0000-0000-0000-000000000102',
           (SELECT user_id FROM device_log_user),'device.registered');
    RAISE EXCEPTION 'Cross-user device event unexpectedly succeeded';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
END;
$reject_cross_user_event$;

ROLLBACK;
SELECT 'device event log tests passed' AS result;
