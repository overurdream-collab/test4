-- Admin-managed home banner advertisements (maximum five active ads).

CREATE SCHEMA IF NOT EXISTS platform;

CREATE TABLE platform.admin_ads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  image_url text NOT NULL CHECK (length(image_url) BETWEEN 1 AND 500),
  title text CHECK (title IS NULL OR length(title) BETWEEN 1 AND 120),
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_by_user_id uuid REFERENCES identity.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX admin_ads_active_idx
  ON platform.admin_ads(is_active, sort_order, created_at);

CREATE OR REPLACE FUNCTION platform.enforce_admin_ads_limit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE active_count integer;
BEGIN
  IF NEW.is_active THEN
    SELECT count(*) INTO active_count
    FROM platform.admin_ads
    WHERE is_active = true AND id <> NEW.id;
    IF active_count >= 5 THEN
      RAISE EXCEPTION 'At most five active admin ads are allowed' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER admin_ads_limit
BEFORE INSERT OR UPDATE OF is_active ON platform.admin_ads
FOR EACH ROW EXECUTE FUNCTION platform.enforce_admin_ads_limit();
