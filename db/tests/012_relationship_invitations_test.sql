\\set ON_ERROR_STOP on
BEGIN;
DO $relationship_tests$
DECLARE inviter uuid; invitee uuid; wrong_user uuid; invitee_later uuid;
        invitation uuid; relationship uuid; second_invitation uuid; second_relationship uuid;
        rejected_invitation uuid; rejected_relationship uuid; expired_invitation uuid; expired_relationship uuid;
        result_status text; request_hash bytea:=decode(repeat('aa',32),'hex');
BEGIN
  inviter:=identity.get_or_create_user_by_phone('+967771234580');
  invitee:=identity.get_or_create_user_by_phone('+967771234581');
  wrong_user:=identity.get_or_create_user_by_phone('+967771234582');
  invitation:='91000000-0000-0000-0000-000000000001';
  relationship:='92000000-0000-0000-0000-000000000001';
  SELECT status INTO result_status FROM ledger.create_relationship_invitation(
    invitation,relationship,inviter,'+967771234581','merchant_customer','merchant','customer',request_hash,now()+interval '7 days');
  IF result_status<>'pending' THEN RAISE EXCEPTION 'New invitation is not pending'; END IF;
  IF (SELECT status FROM ledger.relationships WHERE id=relationship)<>'suspended' THEN
    RAISE EXCEPTION 'Relationship must remain suspended before invite acceptance';
  END IF;
  IF (SELECT count(*) FROM ledger.relationship_members WHERE relationship_id=relationship AND status='active')<>1 THEN
    RAISE EXCEPTION 'Pending relationship must have exactly one active member';
  END IF;
  IF (SELECT count(*) FROM ledger.relationship_members WHERE relationship_id=relationship AND status='invited')<>1 THEN
    RAISE EXCEPTION 'Known invitee should have invited membership';
  END IF;
  -- Idempotent create returns the original relationship even if retry generated a new candidate relationship ID.
  IF (SELECT relationship_id FROM ledger.create_relationship_invitation(
    invitation,'92000000-0000-0000-0000-000000000099',inviter,'+967771234581','merchant_customer','merchant','customer',request_hash,now()+interval '7 days'))<>relationship THEN
    RAISE EXCEPTION 'Idempotent invitation retry did not return canonical relationship';
  END IF;
  -- A wrong account cannot accept even if it is authenticated.
  BEGIN
    PERFORM ledger.decide_relationship_invitation(invitation,wrong_user,'93000000-0000-0000-0000-000000000001','accepted',NULL);
    RAISE EXCEPTION 'Wrong user accepted invitation';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  result_status:=ledger.decide_relationship_invitation(invitation,invitee,'93000000-0000-0000-0000-000000000002','accepted',NULL);
  IF result_status<>'accepted' OR (SELECT status FROM ledger.relationships WHERE id=relationship)<>'active' THEN
    RAISE EXCEPTION 'Invite acceptance did not activate relationship';
  END IF;
  IF (SELECT count(*) FROM ledger.relationship_members WHERE relationship_id=relationship AND status='active')<>2 THEN
    RAISE EXCEPTION 'Accepted relationship must have exactly two active members';
  END IF;
  IF ledger.decide_relationship_invitation(invitation,invitee,'93000000-0000-0000-0000-000000000002','accepted',NULL)<>'accepted' THEN
    RAISE EXCEPTION 'Decision retry did not return canonical result';
  END IF;
  -- Same user can be a member in another relationship; memberships stay relationship-scoped.
  invitee_later:=identity.get_or_create_user_by_phone('+967771234583');
  second_invitation:='91000000-0000-0000-0000-000000000002';
  second_relationship:='92000000-0000-0000-0000-000000000002';
  PERFORM * FROM ledger.create_relationship_invitation(second_invitation,second_relationship,wrong_user,
    '+967771234583','supplier_buyer','supplier','buyer',decode(repeat('bb',32),'hex'),now()+interval '7 days');
  PERFORM ledger.decide_relationship_invitation(second_invitation,invitee_later,'93000000-0000-0000-0000-000000000003','accepted',NULL);
  IF (SELECT count(*) FROM ledger.relationship_members WHERE user_id=invitee_later AND status='active')<>1 THEN
    RAISE EXCEPTION 'Multi-relationship membership was not recorded independently';
  END IF;
  -- Rejection closes only the pending relationship.
  rejected_invitation:='91000000-0000-0000-0000-000000000003';
  rejected_relationship:='92000000-0000-0000-0000-000000000003';
  PERFORM * FROM ledger.create_relationship_invitation(rejected_invitation,rejected_relationship,inviter,
    '+967771234583','merchant_customer','merchant','customer',decode(repeat('cc',32),'hex'),now()+interval '7 days');
  IF ledger.decide_relationship_invitation(rejected_invitation,invitee_later,'93000000-0000-0000-0000-000000000004','rejected','not a match')<>'rejected' THEN
    RAISE EXCEPTION 'Invitation rejection failed';
  END IF;
  IF (SELECT status FROM ledger.relationships WHERE id=rejected_relationship)<>'closed' THEN
    RAISE EXCEPTION 'Rejected invitation did not close pending relationship';
  END IF;
  -- An unregistered phone can register later and accept by verified phone match.
  expired_invitation:='91000000-0000-0000-0000-000000000004';
  expired_relationship:='92000000-0000-0000-0000-000000000004';
  PERFORM * FROM ledger.create_relationship_invitation(expired_invitation,expired_relationship,inviter,
    '+967771234584','merchant_customer','merchant','customer',decode(repeat('dd',32),'hex'),now()+interval '7 days');
  invitee_later:=identity.get_or_create_user_by_phone('+967771234584');
  IF ledger.decide_relationship_invitation(expired_invitation,invitee_later,'93000000-0000-0000-0000-000000000005','accepted',NULL)<>'accepted' THEN
    RAISE EXCEPTION 'Newly registered invitee could not accept by verified phone';
  END IF;
  -- Expired invitation is closed and not left as a usable suspended relationship.
  expired_invitation:='91000000-0000-0000-0000-000000000005';
  expired_relationship:='92000000-0000-0000-0000-000000000005';
  PERFORM * FROM ledger.create_relationship_invitation(expired_invitation,expired_relationship,inviter,
    '+967771234585','merchant_customer','merchant','customer',decode(repeat('ee',32),'hex'),now()+interval '7 days');
  UPDATE ledger.relationship_invitations SET expires_at=now()-interval '1 minute' WHERE id=expired_invitation;
  IF ledger.expire_relationship_invitations(identity.get_or_create_user_by_phone('+967771234585'))<>1 THEN
    RAISE EXCEPTION 'Expired invitation was not processed';
  END IF;
  IF (SELECT status FROM ledger.relationships WHERE id=expired_relationship)<>'closed' THEN
    RAISE EXCEPTION 'Expired invitation relationship was not closed';
  END IF;
  -- A pending relationship cannot accept a financial operation before both parties join.
  BEGIN
    PERFORM * FROM ledger.accept_operation(
      '94000000-0000-0000-0000-000000000001',rejected_relationship,inviter,
      '95000000-0000-0000-0000-000000000001','credit_charge',decode(repeat('ff',32),'hex'),
      '{"amountMinor":100,"currency":"YER"}'::jsonb,0,1,now());
    RAISE EXCEPTION 'Financial operation accepted on closed/pending relationship';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$relationship_tests$;
ROLLBACK;
SELECT 'relationship invitation tests passed' AS result;
