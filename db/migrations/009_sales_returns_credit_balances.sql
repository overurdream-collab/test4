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

-- Permit the new approved return operation through the same durable inbox.
CREATE OR REPLACE FUNCTION ledger.accept_operation(
 p_operation_id uuid,p_relationship_id uuid,p_actor_user_id uuid,p_device_id uuid,
 p_operation_type text,p_request_hash bytea,p_payload jsonb,p_base_version bigint,
 p_schema_version integer,p_client_created_at timestamptz
) RETURNS TABLE(outcome text,canonical_operation_id uuid,business_state text,
 server_version bigint,server_sequence bigint,server_created_at timestamptz)
LANGUAGE plpgsql AS $$
DECLARE x ledger.operations%ROWTYPE; n bigint; t timestamptz:=clock_timestamp();
BEGIN
 IF p_request_hash IS NULL OR octet_length(p_request_hash)<>32 OR p_payload IS NULL
 OR jsonb_typeof(p_payload)<>'object' OR p_base_version<0 OR p_schema_version<>1
 OR p_operation_type NOT IN ('credit_charge','payment','allocation','supply','sales_return') THEN
  RAISE EXCEPTION 'Invalid operation envelope' USING ERRCODE='23514';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_operation_id::text,0));
 SELECT * INTO x FROM ledger.operations WHERE operation_id=p_operation_id FOR UPDATE;
 IF FOUND THEN
  IF x.relationship_id=p_relationship_id AND x.actor_user_id=p_actor_user_id
   AND x.device_id=p_device_id AND x.operation_type=p_operation_type AND x.request_hash=p_request_hash THEN
   RETURN QUERY SELECT 'already_processed'::text,x.operation_id,x.business_state,x.server_version,x.server_sequence,x.created_at; RETURN;
  END IF;
  RAISE EXCEPTION 'Operation id reused with different envelope' USING ERRCODE='23505';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ledger.relationship_members WHERE relationship_id=p_relationship_id AND user_id=p_actor_user_id AND status='active') THEN
  RAISE EXCEPTION 'Actor is not an active relationship member' USING ERRCODE='42501';
 END IF;
 n:=ledger.next_relationship_sequence(p_relationship_id);
 INSERT INTO ledger.operations(operation_id,relationship_id,actor_user_id,operation_type,request_hash,business_state,
 base_version,server_version,device_id,client_schema_version,client_created_at,operation_payload,server_sequence,created_at)
 VALUES(p_operation_id,p_relationship_id,p_actor_user_id,p_operation_type,p_request_hash,'awaiting_counterparty',
 p_base_version,1,p_device_id,p_schema_version,p_client_created_at,p_payload,n,t);
 INSERT INTO ledger.relationship_events(relationship_id,server_sequence,event_id,operation_id,event_type,event_payload)
 VALUES(p_relationship_id,n,gen_random_uuid(),p_operation_id,'operation.created',
 jsonb_build_object('operationId',p_operation_id,'operationType',p_operation_type,'businessState','awaiting_counterparty','serverVersion',1,'payload',p_payload));
 RETURN QUERY SELECT 'accepted'::text,p_operation_id,'awaiting_counterparty'::text,1::bigint,n,t;
END; $$;

-- Reuse the existing approval state transition; this additional trigger posts
-- the return only when the operation changes to approved.
CREATE OR REPLACE FUNCTION ledger.materialize_approved_sales_return()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.business_state<>'approved' AND NEW.business_state='approved'
    AND NEW.operation_type='sales_return' THEN
  INSERT INTO ledger.sales_returns(id,relationship_id,source_operation_id,original_obligation_id,currency,amount_minor,reason)
  VALUES(gen_random_uuid(),NEW.relationship_id,NEW.operation_id,
   (NEW.operation_payload->>'originalObligationId')::uuid,
   (NEW.operation_payload->>'currency')::char(3),
   (NEW.operation_payload->>'amountMinor')::bigint,
   NULLIF(NEW.operation_payload->>'reason',''));
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER operations_materialize_sales_return
AFTER UPDATE OF business_state ON ledger.operations
FOR EACH ROW EXECUTE FUNCTION ledger.materialize_approved_sales_return();
