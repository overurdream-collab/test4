\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE reset_guard text; cycle_guard text;
BEGIN
  reset_guard := pg_get_functiondef('ledger.guard_operation_during_settlement_reset()'::regprocedure);
  cycle_guard := pg_get_functiondef('ledger.assign_current_account_cycle()'::regprocedure);
  IF position('FOR SHARE' IN upper(reset_guard)) = 0 OR position('FOR UPDATE' IN upper(reset_guard)) > 0 THEN
    RAISE EXCEPTION 'Settlement operation guard must use a shared relationship lock';
  END IF;
  IF position('FOR SHARE' IN upper(cycle_guard)) = 0 OR position('FOR UPDATE' IN upper(cycle_guard)) > 0 THEN
    RAISE EXCEPTION 'Cycle assignment must use a shared relationship lock';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='ledger.operations'::regclass AND tgname='operations_blocked_during_settlement_reset' AND tgenabled='O') THEN
    RAISE EXCEPTION 'Settlement reset guard trigger is missing or disabled';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='ledger.operations'::regclass AND tgname='operations_assign_current_cycle' AND tgenabled='O') THEN
    RAISE EXCEPTION 'Current account-cycle trigger is missing or disabled';
  END IF;
END;
$$;
ROLLBACK;
SELECT 'shared relationship row-lock migration tests passed' AS result;
