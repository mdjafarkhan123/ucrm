-- Communications Part 7.2: the suppression removal workflow. A hard bounce is cleared by an
-- organization administrator immediately (still recorded); a spam complaint becomes a request only
-- Jafar can approve. Approving releases the suppression; denying leaves it. Every owner decision is in
-- the owner audit log.
begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e7200000-0000-0000-0000-000000000001', 'Suppression Test', 'suppression-test', 'active');

insert into public.communication_email_suppressions (id, organization_id, recipient_email, reason) values
  ('e7210000-0000-0000-0000-00000000000b', 'e7200000-0000-0000-0000-000000000001', 'bounce@test.example', 'hard_bounce'),
  ('e7210000-0000-0000-0000-00000000000c', 'e7200000-0000-0000-0000-000000000001', 'complaint@test.example', 'complaint'),
  ('e7210000-0000-0000-0000-00000000000d', 'e7200000-0000-0000-0000-000000000001', 'deny@test.example', 'complaint'),
  ('e7210000-0000-0000-0000-00000000000e', 'e7200000-0000-0000-0000-000000000001', 'withdraw@test.example', 'complaint');

-- ------------------------------------------------------------------------------------------------
-- Constraints
-- ------------------------------------------------------------------------------------------------

select throws_ok(
  $$insert into public.communication_email_suppression_removal_requests
      (suppression_id, organization_id, suppression_reason, recipient_email, requested_by_email,
       request_reason, request_evidence, consent_confirmed, status, decided_at)
    values ('e7210000-0000-0000-0000-00000000000c', 'e7200000-0000-0000-0000-000000000001', 'complaint',
      'complaint@test.example', 'a@b.co', 'reason here', 'evidence', true, 'pending', now())$$,
  '23514', null, 'a pending request cannot carry a decided_at'
);

-- ------------------------------------------------------------------------------------------------
-- Hard bounce: an admin request auto-approves and releases in one step
-- ------------------------------------------------------------------------------------------------

select is(
  public.request_communication_email_suppression_removal(
    'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000b',
    null, 'ADMIN@Test.co', 'address was a typo, fixed', 'confirmed with customer by phone', true) ->> 'status',
  'approved',
  'a hard-bounce removal request is auto-approved'
);

select ok(
  (select released_at is not null and released_by_kind = 'organization_admin'
   from public.communication_email_suppressions where id = 'e7210000-0000-0000-0000-00000000000b'),
  'the hard-bounce suppression is released by the organization'
);

select is(
  (select requested_by_email from public.communication_email_suppression_removal_requests
   where suppression_id = 'e7210000-0000-0000-0000-00000000000b'),
  'admin@test.co',
  'the requester email is normalised to lower case'
);

select throws_ok(
  $$select public.request_communication_email_suppression_removal(
      'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000b',
      null, 'admin@test.co', 'again', 'again', true)$$,
  '23514', null, 'a released address will not accept a new removal request'
);

-- ------------------------------------------------------------------------------------------------
-- Complaint: request stays pending, needs Jafar
-- ------------------------------------------------------------------------------------------------

select is(
  public.request_communication_email_suppression_removal(
    'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000c',
    null, 'admin@test.co', 'customer opted back in', 'opt-in form submitted 2026-08-28', true) ->> 'status',
  'pending',
  'a complaint removal request is left pending'
);

select ok(
  (select released_at is null from public.communication_email_suppressions
   where id = 'e7210000-0000-0000-0000-00000000000c'),
  'the complaint suppression stays blocked while the request is pending'
);

select throws_ok(
  $$select public.request_communication_email_suppression_removal(
      'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000c',
      null, 'admin@test.co', 'again', 'again', true)$$,
  '23505', null, 'a second open request for the same address is rejected'
);

select throws_ok(
  $$select public.request_communication_email_suppression_removal(
      'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000d',
      null, 'admin@test.co', 'reason', 'evidence', false)$$,
  '23514', null, 'a removal request without a consent confirmation is rejected'
);

-- ------------------------------------------------------------------------------------------------
-- Jafar approves the complaint request
-- ------------------------------------------------------------------------------------------------

select is(
  public.decide_communication_email_suppression_removal(
    (select id from public.communication_email_suppression_removal_requests
     where suppression_id = 'e7210000-0000-0000-0000-00000000000c'),
    'jafar@example.com', 'approve', null) ->> 'status',
  'approved',
  'the owner can approve a pending complaint request'
);

select ok(
  (select released_at is not null and released_by_kind = 'platform_owner'
     and released_by_owner_email = 'jafar@example.com'
   from public.communication_email_suppressions where id = 'e7210000-0000-0000-0000-00000000000c'),
  'approving releases the complaint suppression as the platform owner'
);

select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type = 'communications.email_suppression_removal_approved'
     and target_key = 'e7210000-0000-0000-0000-00000000000c'),
  1,
  'approving writes one owner audit event'
);

select throws_ok(
  $$select public.decide_communication_email_suppression_removal(
      (select id from public.communication_email_suppression_removal_requests
       where suppression_id = 'e7210000-0000-0000-0000-00000000000c'),
      'jafar@example.com', 'approve', null)$$,
  '23514', null, 'a request cannot be decided twice'
);

-- ------------------------------------------------------------------------------------------------
-- Jafar denies a complaint request; the address stays blocked
-- ------------------------------------------------------------------------------------------------

select public.request_communication_email_suppression_removal(
  'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000d',
  null, 'admin@test.co', 'please remove', 'they said so', true);

select throws_ok(
  $$select public.decide_communication_email_suppression_removal(
      (select id from public.communication_email_suppression_removal_requests
       where suppression_id = 'e7210000-0000-0000-0000-00000000000d' and status = 'pending'),
      'jafar@example.com', 'deny', null)$$,
  '23514', null, 'denying a request requires a note'
);

select is(
  public.decide_communication_email_suppression_removal(
    (select id from public.communication_email_suppression_removal_requests
     where suppression_id = 'e7210000-0000-0000-0000-00000000000d' and status = 'pending'),
    'jafar@example.com', 'deny', 'not enough evidence of renewed consent') ->> 'status',
  'denied',
  'the owner can deny a pending request with a note'
);

select ok(
  (select released_at is null from public.communication_email_suppressions
   where id = 'e7210000-0000-0000-0000-00000000000d'),
  'a denied request leaves the address blocked'
);

-- ------------------------------------------------------------------------------------------------
-- Withdraw and re-file
-- ------------------------------------------------------------------------------------------------

select public.request_communication_email_suppression_removal(
  'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000e',
  null, 'admin@test.co', 'open then change mind', 'evidence', true);

select is(
  public.withdraw_communication_email_suppression_removal(
    'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000e',
    null, 'admin@test.co') ->> 'status',
  'withdrawn',
  'an organization can withdraw its own pending request'
);

select is(
  public.request_communication_email_suppression_removal(
    'e7200000-0000-0000-0000-000000000001', 'e7210000-0000-0000-0000-00000000000e',
    null, 'admin@test.co', 'actually please remove', 'evidence again', true) ->> 'status',
  'pending',
  'a fresh request can be filed after a withdrawal'
);

-- ------------------------------------------------------------------------------------------------
-- Reads
-- ------------------------------------------------------------------------------------------------

select is(
  (public.get_communication_email_blocked_addresses('e7200000-0000-0000-0000-000000000001')
     ->> 'blocked_total')::int,
  2,
  'the contractor read reports the two addresses still blocked'
);

select is(
  (public.get_communication_email_suppression_removal_queue() ->> 'pending_total')::int,
  1,
  'the owner queue reports the one still-pending request'
);

select * from finish();
rollback;
