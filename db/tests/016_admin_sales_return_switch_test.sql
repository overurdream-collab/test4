\set ON_ERROR_STOP on
BEGIN;

INSERT INTO identity.users(id,status,is_admin) VALUES
('29300000-0000-0000-0000-000000000001','active',true),
('29300000-0000-0000-0000-000000000002','active',false);
INSERT INTO ledger.relationships(id,status)
VALUES ('19300000-0000-0000-0000-000000000001','active');
INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve) VALUES
('19300000-0000-0000-0000-000000000001','29300000-0000-0000-0000-000000000001','seller','active',true),
('19300000-0000-0000-0000-000000000001','29300000-0000-0000-0000-000000000002','buyer','active',true);

DO $enabled_by_default$
BEGIN
  IF NOT ledger.sales_returns_enabled() THEN
    RAISE EXCEPTION 'Sales returns must be enabled by default';
  END IF;
END; $enabled_by_default$;

SELECT * FROM ledger.accept_operation('39300000-0000-0000-0000-000000000001','19300000-0000-0000-0000-000000000001',
'29300000-0000-0000-0000-000000000001','79300000-0000-0000-0000-000000000001','credit_charge',
decode(repeat('e1',32),'hex'),'{"creditorUserId":"29300000-0000-0000-0000-000000000001","debtorUserId":"29300000-0000-0000-0000-000000000002","currency":"YER","amountMinor":5000}'::jsonb,0,1,now());
SELECT ledger.decide_operation('69300000-0000-0000-0000-000000000001','19300000-0000-0000-0000-000000000001',
'39300000-0000-0000-0000-000000000001','29300000-0000-0000-0000-000000000002',1,'approved','charge');
CREATE TEMP TABLE admin_switch_ids AS
SELECT id obligation_id FROM ledger.obligations
WHERE source_operation_id='39300000-0000-0000-0000-000000000001';

-- A return submitted before the switch is turned off stays pending.
SELECT * FROM ledger.accept_operation('39300000-0000-0000-0000-000000000002','19300000-0000-0000-0000-000000000001',
'29300000-0000-0000-0000-000000000002','79300000-0000-0000-0000-000000000002','sales_return',
decode(repeat('e2',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM admin_switch_ids),
'currency','YER','amountMinor',1000,'reason','Pending before switch'),0,1,now());

DO $admin_disables$
DECLARE changed boolean;
BEGIN
  SELECT enabled INTO changed FROM ledger.set_service_control(
    'sales_returns', false, '29300000-0000-0000-0000-000000000001'
  );
  IF changed THEN
    RAISE EXCEPTION 'Admin disable did not turn the switch off';
  END IF;
  IF ledger.sales_returns_enabled() THEN
    RAISE EXCEPTION 'Sales returns remained enabled after admin disable';
  END IF;
END; $admin_disables$;

DO $new_return_blocked$
BEGIN
  BEGIN
    PERFORM * FROM ledger.accept_operation('39300000-0000-0000-0000-000000000003','19300000-0000-0000-0000-000000000001',
    '29300000-0000-0000-0000-000000000002','79300000-0000-0000-0000-000000000003','sales_return',
    decode(repeat('e3',32),'hex'),jsonb_build_object('originalObligationId',(SELECT obligation_id FROM admin_switch_ids),
    'currency','YER','amountMinor',1000,'reason','Must be blocked'),0,1,now());
    RAISE EXCEPTION 'New return succeeded while the service was disabled';
  EXCEPTION WHEN feature_not_supported THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM ledger.operations WHERE operation_id='39300000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'Blocked return operation was persisted';
  END IF;
END; $new_return_blocked$;

DO $pending_approval_blocked$
BEGIN
  BEGIN
    PERFORM ledger.decide_operation('69300000-0000-0000-0000-000000000002','19300000-0000-0000-0000-000000000001',
    '39300000-0000-0000-0000-000000000002','29300000-0000-0000-0000-000000000001',1,'approved','Must be blocked');
    RAISE EXCEPTION 'Pending return was approved while the service was disabled';
  EXCEPTION WHEN feature_not_supported THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM ledger.sales_returns
      WHERE source_operation_id='39300000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'Blocked return approval was materialized';
  END IF;
END; $pending_approval_blocked$;

DO $non_admin_cannot_toggle$
BEGIN
  BEGIN
    PERFORM * FROM ledger.set_service_control(
      'sales_returns', true, '29300000-0000-0000-0000-000000000002'
    );
    RAISE EXCEPTION 'Non-admin changed the service switch';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END; $non_admin_cannot_toggle$;

DO $admin_reenables$
DECLARE changed boolean;
BEGIN
  SELECT enabled INTO changed FROM ledger.set_service_control(
    'sales_returns', true, '29300000-0000-0000-0000-000000000001'
  );
  IF NOT changed OR NOT ledger.sales_returns_enabled() THEN
    RAISE EXCEPTION 'Admin re-enable did not turn the switch on';
  END IF;
  PERFORM ledger.decide_operation('69300000-0000-0000-0000-000000000003','19300000-0000-0000-0000-000000000001',
  '39300000-0000-0000-0000-000000000002','29300000-0000-0000-0000-000000000001',1,'approved','Approved after re-enable');
  IF NOT EXISTS (SELECT 1 FROM ledger.sales_returns
      WHERE source_operation_id='39300000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'Return was not materialized after re-enable';
  END IF;
END; $admin_reenables$;

DO $audit$
BEGIN
  IF (SELECT count(*) FROM ledger.service_control_changes
      WHERE service_key='sales_returns'
        AND actor_user_id='29300000-0000-0000-0000-000000000001') <> 2 THEN
    RAISE EXCEPTION 'Expected two audited admin changes';
  END IF;
END; $audit$;

ROLLBACK;
