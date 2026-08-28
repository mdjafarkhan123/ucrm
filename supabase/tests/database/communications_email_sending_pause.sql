-- Communications Part 7.3: the sending-pause spine. A manual pause -- platform-wide or per-organization
-- -- is a hard stop the outbox claim honours: platform makes claim a no-op, an organization pause holds
-- that tenant's rows (deferred, annotated, never cancelled). Every change is in the owner audit log.
begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d7100000-0000-0000-0000-000000000001', 'Pause Test A', 'pause-test-a', 'active'),
  ('d7100000-0000-0000-0000-000000000002', 'Pause Test B', 'pause-test-b', 'active');

insert into public.clients (id, organization_id, display_name)
values ('d7200000-0000-0000-0000-000000000001', 'd7100000-0000-0000-0000-000000000001', 'Pause Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('d7300000-0000-0000-0000-000000000001', 'd7100000-0000-0000-0000-000000000001',
  'd7200000-0000-0000-0000-000000000001', 'email', 'held@pause-test.example', true);

-- Park any send already queued in this database so the claim assertions below see only our fixture.
update public.communication_outbox_events set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');

-- ------------------------------------------------------------------------------------------------
-- Constraints
-- ------------------------------------------------------------------------------------------------

select throws_ok(
  $$insert into public.communication_email_sending_pauses (scope, organization_id, reason, engaged_by_owner_email)
    values ('platform', 'd7100000-0000-0000-0000-000000000001', 'bad', 'jafar@example.com')$$,
  '23514',
  null,
  'a platform pause cannot carry an organization_id'
);

select throws_ok(
  $$insert into public.communication_email_sending_pauses (scope, reason, engaged_by_owner_email)
    values ('organization', 'needs an org', 'jafar@example.com')$$,
  '23514',
  null,
  'an organization pause requires an organization_id'
);

select throws_ok(
  $$insert into public.communication_email_sending_pauses (scope, reason, engaged_by_owner_email, released_at)
    values ('platform', 'half released', 'jafar@example.com', now())$$,
  '23514',
  null,
  'released_at without released_by and released_reason is rejected'
);

-- ------------------------------------------------------------------------------------------------
-- Platform pause: engage, idempotency, health, release
-- ------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.set_communication_email_platform_pause(true, 'Brevo shared-IP incident', 'JAFAR@Example.com')$$,
  'platform pause engages'
);

select is(
  (select count(*)::int from public.communication_email_sending_pauses where scope = 'platform' and released_at is null),
  1,
  'exactly one live platform pause exists'
);

select is(
  (select engaged_by_owner_email from public.communication_email_sending_pauses
   where scope = 'platform' and released_at is null),
  'jafar@example.com',
  'the actor email is normalised to lower case'
);

select is(
  public.set_communication_email_platform_pause(true, 'second call', 'jafar@example.com'),
  (select id from public.communication_email_sending_pauses where scope = 'platform' and released_at is null),
  're-engaging returns the existing pause and adds no row'
);

select is(
  (select count(*)::int from public.communication_email_sending_pauses where scope = 'platform'),
  1,
  'no duplicate platform row from the second engage'
);

select is(
  (public.get_communication_email_sending_health() -> 'platform_pause' ->> 'reason'),
  'Brevo shared-IP incident',
  'health reports the live platform pause'
);

select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'the outbox claim is a no-op while the platform is paused'
);

select lives_ok(
  $$select public.set_communication_email_platform_pause(false, 'incident resolved', 'jafar@example.com')$$,
  'platform pause releases'
);

select ok(
  not exists (select 1 from public.communication_email_sending_pauses where scope = 'platform' and released_at is null),
  'no live platform pause after release'
);

select is(
  public.set_communication_email_platform_pause(false, 'nothing to do', 'jafar@example.com'),
  null,
  'releasing when nothing is paused returns null'
);

-- ------------------------------------------------------------------------------------------------
-- Organization pause: engage, uniqueness, and the claim deferral
-- ------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.set_communication_email_organization_pause(
      'd7999999-0000-0000-0000-000000000000', true, 'unknown org', 'jafar@example.com')$$,
  '23503',
  null,
  'pausing an organization that does not exist is rejected'
);

select lives_ok(
  $$select public.set_communication_email_organization_pause(
      'd7100000-0000-0000-0000-000000000001', true, 'chargeback investigation', 'jafar@example.com')$$,
  'organization pause engages'
);

-- A queued send for the paused organization.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
) values (
  'd7400000-0000-0000-0000-000000000001', 'd7100000-0000-0000-0000-000000000001',
  'd7200000-0000-0000-0000-000000000001', 'd7300000-0000-0000-0000-000000000001',
  'pause-test-send-1', 'held@pause-test.example', 'Held subject', '<p>held</p>', 'held'
);
insert into public.communication_outbox_events (id, organization_id, delivery_intent_id, available_at)
values ('d7500000-0000-0000-0000-000000000001', 'd7100000-0000-0000-0000-000000000001',
  'd7400000-0000-0000-0000-000000000001', now() - interval '1 minute');

select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'the claim does not hand out a send for a paused organization'
);

select ok(
  (select available_at > now() from public.communication_outbox_events
   where id = 'd7500000-0000-0000-0000-000000000001')
  and (select status from public.communication_outbox_events
   where id = 'd7500000-0000-0000-0000-000000000001') = 'pending'
  and (select failure_code from public.communication_delivery_intents
   where id = 'd7400000-0000-0000-0000-000000000001') = 'sending_paused_organization',
  'the held send is deferred and annotated, not cancelled'
);

-- ------------------------------------------------------------------------------------------------
-- Audit trail: platform engage + release, organization engage = 3 events
-- ------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type like 'communications.email_%_pause_%'),
  3,
  'every pause change wrote one owner audit event'
);

select * from finish();
rollback;
