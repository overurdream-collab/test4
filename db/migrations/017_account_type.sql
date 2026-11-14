-- Persist the account type chosen at registration.
-- Existing profiles remain NULL until their next verified login sets the value.

ALTER TABLE identity.user_profiles
  ADD COLUMN IF NOT EXISTS account_type text
  CHECK (account_type IS NULL OR account_type IN ('customer','merchant','supplier'));

COMMENT ON COLUMN identity.user_profiles.account_type IS
  'Registration role: customer, merchant, or supplier. Set once and not user-editable.';
