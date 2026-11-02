-- Approved sales returns / credit notes. Original financial facts remain immutable.
CREATE TABLE ledger.sales_returns (
 id uuid PRIMARY KEY, relationship_id uuid NOT NULL, source_operation_id uuid NOT NULL UNIQUE,
 original_obligation_id uuid NOT NULL, currency char(3) NOT NULL CHECK(currency IN ('YER','SAR','USD')),
 amount_minor bigint NOT NULL CHECK(amount_minor>0), reason text,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(relationship_id,source_operation_id) REFERENCES ledger.operations(relationship_id,operation_id),
 FOREIGN KEY(original_obligation_id,relationship_id,currency) REFERENCES ledger.obligations(id,relationship_id,currency),
 UNIQUE(id,relationship_id,currency), CHECK(reason IS NULL OR length(reason)<=1000)
);
CREATE INDEX sales_returns_by_obligation_idx ON ledger.sales_returns(relationship_id,original_obligation_id,created_at);
CREATE OR REPLACE FUNCTION ledger.reject_sales_return_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Sales returns are immutable; append a linked correction' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER sales_returns_are_immutable BEFORE UPDATE OR DELETE ON ledger.sales_returns FOR EACH ROW EXECUTE FUNCTION ledger.reject_sales_return_mutation();
CREATE OR REPLACE FUNCTION ledger.assert_sales_return_source() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE op ledger.operations%ROWTYPE; obl ledger.obligations%ROWTYPE; returned numeric;
BEGIN
 SELECT * INTO obl FROM ledger.obligations WHERE id=NEW.original_obligation_id AND relationship_id=NEW.relationship_id AND currency=NEW.currency FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original obligation not found' USING ERRCODE='23503'; END IF;
 SELECT * INTO op FROM ledger.operations WHERE operation_id=NEW.source_operation_id AND relationship_id=NEW.relationship_id;
 IF NOT FOUND OR op.business_state<>'approved' OR op.operation_type<>'sales_return' THEN RAISE EXCEPTION 'Return requires approved sales_return operation' USING ERRCODE='23514'; END IF;
 IF op.actor_user_id NOT IN (obl.creditor_user_id,obl.debtor_user_id) THEN RAISE EXCEPTION 'Return actor must be an original party' USING ERRCODE='42501'; END IF;
 IF NEW.reason IS NOT NULL AND length(NEW.reason)>1000 THEN RAISE EXCEPTION 'Return reason too long' USING ERRCODE='22023'; END IF;
 SELECT COALESCE(sum(amount_minor),0) INTO returned FROM ledger.sales_returns WHERE relationship_id=NEW.relationship_id AND original_obligation_id=NEW.original_obligation_id;
 IF returned+NEW.amount_minor>obl.amount_minor THEN RAISE EXCEPTION 'Cumulative returns exceed original obligation' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER sales_returns_require_approved_source BEFORE INSERT ON ledger.sales_returns FOR EACH ROW EXECUTE FUNCTION ledger.assert_sales_return_source();
CREATE OR REPLACE FUNCTION ledger.post_sales_return_to_journal() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE obl ledger.obligations%ROWTYPE; seller_account uuid; buyer_account uuid; journal_id uuid;
BEGIN
 SELECT * INTO obl FROM ledger.obligations WHERE id=NEW.original_obligation_id AND relationship_id=NEW.relationship_id;
 seller_account:=ledger.get_or_create_account(NEW.relationship_id,obl.creditor_user_id,'party_receivable',NEW.currency);
 buyer_account:=ledger.get_or_create_account(NEW.relationship_id,obl.debtor_user_id,'party_payable',NEW.currency);
 journal_id:=gen_random_uuid();
 INSERT INTO ledger.journal_transactions(id,relationship_id,source_operation_id,currency,description) VALUES(journal_id,NEW.relationship_id,NEW.source_operation_id,NEW.currency,'Approved sales return / credit note');
 INSERT INTO ledger.journal_entries(id,journal_transaction_id,relationship_id,currency,account_id,debit_minor,credit_minor) VALUES
 (gen_random_uuid(),journal_id,NEW.relationship_id,NEW.currency,seller_account,0,NEW.amount_minor),
 (gen_random_uuid(),journal_id,NEW.relationship_id,NEW.currency,buyer_account,NEW.amount_minor,0);
 RETURN NEW;
END; $$;
CREATE TRIGGER sales_returns_post_to_journal AFTER INSERT ON ledger.sales_returns FOR EACH ROW EXECUTE FUNCTION ledger.post_sales_return_to_journal();

-- Sales returns are posted only after the normal bilateral approval transition.
