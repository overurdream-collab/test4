-- Allow a bilateral white-page reset when the only outstanding signed
-- balances are the immutable credit created by approved sales returns.
-- The archived cycle keeps that credit for audit; nothing is written off,
-- deleted, or moved into the new cycle.

CREATE OR REPLACE FUNCTION ledger.guard_settlement_reset_has_no_signed_credit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  target_cycle uuid;
BEGIN
  IF TG_TABLE_NAME = 'settlement_requests' THEN
    target_cycle := NEW.cycle_id;
  ELSIF NEW.decision = 'approved' THEN
    SELECT sr.cycle_id INTO target_cycle
    FROM ledger.settlement_requests sr
    WHERE sr.id = NEW.request_id
      AND sr.relationship_id = NEW.relationship_id;
  ELSE
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ledger.member_currency_positions p
    LEFT JOIN (
      SELECT
        a.owner_user_id,
        je.currency,
        sum(je.debit_minor - je.credit_minor) AS expected
      FROM ledger.sales_returns ret
      JOIN ledger.operations op
        ON op.operation_id = ret.source_operation_id
       AND op.relationship_id = ret.relationship_id
      JOIN ledger.journal_transactions jt
        ON jt.source_operation_id = ret.source_operation_id
       AND jt.relationship_id = ret.relationship_id
      JOIN ledger.journal_entries je
        ON je.journal_transaction_id = jt.id
       AND je.relationship_id = jt.relationship_id
      JOIN ledger.accounts a
        ON a.id = je.account_id
       AND a.relationship_id = je.relationship_id
      WHERE ret.relationship_id = NEW.relationship_id
        AND op.cycle_id = target_cycle
      GROUP BY a.owner_user_id, je.currency
    ) return_credit
      ON return_credit.owner_user_id = p.owner_user_id
     AND return_credit.currency = p.currency
    WHERE p.relationship_id = NEW.relationship_id
      AND p.cycle_id = target_cycle
      AND p.net_position_minor <> 0
      AND (
        return_credit.expected IS NULL
        OR p.net_position_minor IS DISTINCT FROM return_credit.expected
      )
  ) THEN
    RAISE EXCEPTION 'Cannot reset a cycle with an unsettled signed party balance or credit'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;
