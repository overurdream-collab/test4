-- Append-only device lifecycle audit log.
-- Events are written by triggers so every registration, revocation, session
-- start and session revocation is recorded regardless of the caller.

CREATE TABLE identity.device_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id uuid NOT NULL,
  user_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN (
    'device.registered','device.revoked','session.started','session.revoked'
  )),
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (device_id,user_id) REFERENCES identity.devices(id,user_id)
);

CREATE INDEX identity_device_events_device_idx
  ON identity.device_events(device_id,created_at DESC,id DESC);

CREATE INDEX identity_device_events_user_idx
  ON identity.device_events(user_id,created_at DESC,id DESC);

-- Backfill lifecycle history for devices that existed before this migration.
INSERT INTO identity.device_events(device_id,user_id,event_type,details,created_at)
SELECT d.id,d.user_id,'device.registered',
  jsonb_build_object('platform',d.platform,'label',d.device_label),d.registered_at
FROM identity.devices d;

INSERT INTO identity.device_events(device_id,user_id,event_type,details,created_at)
SELECT d.id,d.user_id,'device.revoked',
  jsonb_build_object('platform',d.platform,'label',d.device_label),d.revoked_at
FROM identity.devices d
WHERE d.status='revoked' AND d.revoked_at IS NOT NULL;

CREATE OR REPLACE FUNCTION identity.record_device_lifecycle_event()
RETURNS trigger LANGUAGE plpgsql AS $device_event$
BEGIN
  IF TG_TABLE_NAME='devices' THEN
    IF TG_OP='INSERT' THEN
      INSERT INTO identity.device_events(device_id,user_id,event_type,details)
      VALUES(NEW.id,NEW.user_id,'device.registered',
        jsonb_build_object('platform',NEW.platform,'label',NEW.device_label));
    ELSIF TG_OP='UPDATE' AND NEW.status='revoked' AND OLD.status<>'revoked' THEN
      INSERT INTO identity.device_events(device_id,user_id,event_type,details)
      VALUES(NEW.id,NEW.user_id,'device.revoked',
        jsonb_build_object('platform',NEW.platform,'label',NEW.device_label));
    END IF;
  ELSIF TG_TABLE_NAME='auth_sessions' THEN
    IF TG_OP='INSERT' THEN
      INSERT INTO identity.device_events(device_id,user_id,event_type,details)
      VALUES(NEW.device_id,NEW.user_id,'session.started',
        jsonb_build_object('sessionId',NEW.id,'expiresAt',NEW.expires_at));
    ELSIF TG_OP='UPDATE' AND NEW.revoked_at IS NOT NULL AND OLD.revoked_at IS NULL THEN
      INSERT INTO identity.device_events(device_id,user_id,event_type,details)
      VALUES(NEW.device_id,NEW.user_id,'session.revoked',
        jsonb_build_object('sessionId',NEW.id,'revokedAt',NEW.revoked_at));
    END IF;
  END IF;
  RETURN NULL;
END;
$device_event$;

CREATE TRIGGER identity_devices_lifecycle_event
  AFTER INSERT OR UPDATE OF status ON identity.devices
  FOR EACH ROW EXECUTE FUNCTION identity.record_device_lifecycle_event();

CREATE TRIGGER identity_sessions_lifecycle_event
  AFTER INSERT OR UPDATE OF revoked_at ON identity.auth_sessions
  FOR EACH ROW EXECUTE FUNCTION identity.record_device_lifecycle_event();

-- The log is append-only: reject updates, deletes and truncation.
CREATE OR REPLACE FUNCTION identity.reject_device_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $device_event_immutable$
BEGIN
  RAISE EXCEPTION 'device event log is append-only' USING ERRCODE='42501';
END;
$device_event_immutable$;

CREATE TRIGGER identity_device_events_no_update
  BEFORE UPDATE OR DELETE ON identity.device_events
  FOR EACH ROW EXECUTE FUNCTION identity.reject_device_event_mutation();

CREATE TRIGGER identity_device_events_no_truncate
  BEFORE TRUNCATE ON identity.device_events
  FOR EACH STATEMENT EXECUTE FUNCTION identity.reject_device_event_mutation();
