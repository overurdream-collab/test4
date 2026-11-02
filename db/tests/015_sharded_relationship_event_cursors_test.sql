\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE shard smallint; n bigint; op record; rel uuid:='13000000-0000-0000-0000-000000000301';
BEGIN
 INSERT INTO ledger.relationships(id,status) VALUES(rel,'active');
 INSERT INTO ledger.relationship_members(relationship_id,user_id,role_label,status,can_approve)
 VALUES(rel,'23000000-0000-0000-0000-000000000301','seller','active',false),
       (rel,'23000000-0000-0000-0000-000000000302','buyer','active',true);
 shard:=ledger.operation_sync_shard('33000000-0000-0000-0000-000000000301');
 SELECT * INTO op FROM ledger.accept_operation(
  '33000000-0000-0000-0000-000000000301',rel,
  '23000000-0000-0000-0000-000000000301',
  '73000000-0000-0000-0000-000000000301','supply',
  decode(repeat('ab',32),'hex'), '{"amountMinor":1000,"currency":"YER"}'::jsonb,
  0,1,now()
 );
 IF op.outcome<>'accepted' OR op.server_sequence<=shard::bigint*1000000000000 THEN
  RAISE EXCEPTION 'Acceptance did not use its shard sequence range: %',row_to_json(op);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ledger.relationship_events
   WHERE relationship_id=rel AND sync_shard=shard AND server_sequence=op.server_sequence
     AND event_type='operation.created') THEN
  RAISE EXCEPTION 'Created event missing from matching shard';
 END IF;
 PERFORM ledger.decide_operation(
  '63000000-0000-0000-0000-000000000301',rel,
  '33000000-0000-0000-0000-000000000301',
  '23000000-0000-0000-0000-000000000302',
  1,'approved','shard test'
 );
 IF (SELECT count(*) FROM ledger.relationship_events
     WHERE relationship_id=rel AND sync_shard=shard)<>2 THEN
  RAISE EXCEPTION 'Operation state event did not stay on its original shard';
 END IF;
 IF (SELECT count(DISTINCT sync_shard) FROM ledger.relationship_sync_shard_counters
     WHERE relationship_id=rel)<>8 THEN
  RAISE EXCEPTION 'Expected eight independent sequence counters';
 END IF;
END;
$$;
ROLLBACK;
SELECT 'sharded relationship event cursor tests passed' AS result;
