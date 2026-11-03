-- Global admin service controls. The first control is the sales-return switch.
-- A disabled switch blocks new returns and approval of pending returns at the
-- database layer, regardless of which API or client submitted the operation.

ALTER TABLE identity.users
  ADD COLUMN is_admin boolean NOT NULL DEFAULT false;

CREATE TABLE ledger.service_controls (
  service_key text PRIMARY KEY CHECK (service_key IN ('sales_returns')),
  enabled boolean NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_by_user_id uuid REFERENCES identity.users(id),
  CHECK (updated_by_user_id IS NOT NULL OR enabled = true)
);

INSERT INTO ledger.service_controls(service_key, enabled)
VALUES ('sales_returns', true);

CREATE TABLE ledger.service_control_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_key text NOT NULL,
  enabled boolean NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES identity.users(id),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX service_control_changes_by_service_idx
  ON ledger.service_control_changes(service_key, changed_at DESC);

CREATE OR REPLACE FUNCTION ledger.sales_returns_enabled()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT enabled FROM ledger.service_controls WHERE service_key = 'sales_returns'),
    true
  );
$$;

CREATE OR REPLACE FUNCTION ledger.set_service_control(
  p_service_key text,
  p_enabled boolean,
  p_actor_user_id uuid
) RETURNS TABLE(
  service_key text,
  enabled boolean,
  updated_at timestamptz,
  updated_by_user_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE
  changed_at timestamptz := clock_timestamp();
BEGIN
  IF p_service_key <> 'sales_returns' THEN
    RAISE EXCEPTION 'Unsupported service control' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM identity.users
    WHERE id = p_actor_user_id AND status = 'active' AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Admin permission is required' USING ERRCODE = '42501';
  END IF;

  INSERT INTO ledger.service_controls(
    service_key, enabled, updated_at, updated_by_user_id
  ) VALUES (
    p_service_key, p_enabled, changed_at, p_actor_user_id
  )
  ON CONFLICT (service_key) DO UPDATE SET
    enabled = EXCLUDED.enabled,
    updated_at = EXCLUDED.updated_at,
    updated_by_user_id = EXCLUDED.updated_by_user_id;

  INSERT INTO ledger.service_control_changes(
    service_key, enabled, actor_user_id, changed_at
  ) VALUES (
    p_service_key, p_enabled, p_actor_user_id, changed_at
  );

  RETURN QUERY
  SELECT c.service_key, c.enabled, c.updated_at, c.updated_by_user_id
  FROM ledger.service_controls c
  WHERE c.service_key = p_service_key;
END;
$$;

CREATE OR REPLACE FUNCTION ledger.guard_sales_return_insert_enabled()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.operation_type = 'sales_return' AND NOT ledger.sales_returns_enabled() THEN
    RAISE EXCEPTION 'Sales return service is disabled' USING ERRCODE = '0A000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER operations_guard_sales_return_insert
BEFORE INSERT ON ledger.operations
FOR EACH ROW EXECUTE FUNCTION ledger.guard_sales_return_insert_enabled();

CREATE OR REPLACE FUNCTION ledger.guard_sales_return_approval_enabled()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT ledger.sales_returns_enabled() THEN
    RAISE EXCEPTION 'Sales return service is disabled' USING ERRCODE = '0A000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER operations_guard_sales_return_approval
BEFORE UPDATE OF business_state ON ledger.operations
FOR EACH ROW
WHEN (
  OLD.business_state <> 'approved'
  AND NEW.business_state = 'approved'
  AND NEW.operation_type = 'sales_return'
)
EXECUTE FUNCTION ledger.guard_sales_return_approval_enabled();
