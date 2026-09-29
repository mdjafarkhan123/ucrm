-- Marketing M4 stage 2: the launch snapshot, the Marketing allowance, and marketing_launch_campaign.
--
-- Run this whole file as one transaction that is rolled back at the end, the same convention
-- marketing_customer_group_preview.sql documents. Do not run it through a runner that executes each
-- statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- Nobody outside server code reaches the launch command or the tables it writes. ----------------------
select is(has_function_privilege('anon',
  'public.marketing_launch_campaign(uuid, uuid, uuid, integer, timestamptz, text)', 'execute'),
  false, 'signed-out callers cannot launch a campaign');
select is(has_function_privilege('authenticated',
  'public.marketing_launch_campaign(uuid, uuid, uuid, integer, timestamptz, text)', 'execute'),
  false, 'members cannot launch a campaign directly; the route checks marketing.launch first');
select is(has_function_privilege('service_role',
  'private.ensure_marketing_allowance_period(uuid, timestamptz)', 'execute'),
  false, 'the allowance period opener is private to the launch command');
select is((select relrowsecurity from pg_class where oid = 'public.marketing_campaign_recipients'::regclass),
  true, 'the recipient snapshot has row level security enabled');
select is((select relrowsecurity from pg_class where oid = 'public.marketing_email_capacity_reservations'::regclass),
  true, 'marketing allowance reservations have row level security enabled');
select is((select relrowsecurity from pg_class where oid = 'public.marketing_email_allowance_periods'::regclass),
  true, 'marketing allowance periods have row level security enabled');

set local role postgres;

-- Fixtures --------------------------------------------------------------------------------------------
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('fb100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'launch-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status, created_at)
values
  ('fb200000-0000-0000-0000-000000000001', 'Launch Org A', 'launch-org-a', 'active', now() - interval '40 days'),
  ('fb200000-0000-0000-0000-000000000002', 'Launch Org B', 'launch-org-b', 'active', now() - interval '40 days');

insert into public.organization_members (organization_id, user_id, role)
values ('fb200000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 'owner');

-- The private test package, with its unlimited Marketing allowance taken away until the test sets one.
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
select organization.id, edition.id, 'month', 0, now() - interval '40 days', 'test_reset', 'Launch test baseline'
from (values
  ('fb200000-0000-0000-0000-000000000001'::uuid),
  ('fb200000-0000-0000-0000-000000000002'::uuid)
) as organization(id)
cross join public.package_editions edition
join public.packages package on package.id = edition.package_id
where package.slug = 'test-package' and edition.status = 'published';

insert into public.organization_package_exceptions (
  organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at, actor_owner_email
)
select organization.id, 'marketing_email_recipients', 'not_included', null, 'No Marketing allowance yet',
  now() - interval '40 days', '2100-01-01T00:00:00Z', 'owner@example.test'
from (values
  ('fb200000-0000-0000-0000-000000000001'::uuid),
  ('fb200000-0000-0000-0000-000000000002'::uuid)
) as organization(id);

select private.ensure_organization_commercial_rows('fb200000-0000-0000-0000-000000000001');
select private.ensure_organization_commercial_rows('fb200000-0000-0000-0000-000000000002');

update public.organization_commercial_state
set paid_through_date = (now() + interval '300 days')::date,
    paid_through_source = 'renewal',
    grace_ends_at = now() + interval '300 days',
    grace_basis_timezone = 'UTC'
where organization_id in (
  'fb200000-0000-0000-0000-000000000001',
  'fb200000-0000-0000-0000-000000000002'
);

-- Org A: two reachable customers, one whose address has hard bounced, one with no consent on record,
-- and one archived. (The database already forbids two Customers in one organization sharing an email
-- address, so the preview's duplicate_destination case cannot arise from separate Customers.)
insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status, archived_at)
values
  ('fb300000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', 'A Ready One', 'person', 'customer', null),
  ('fb300000-0000-0000-0000-000000000002', 'fb200000-0000-0000-0000-000000000001', 'B Ready Two', 'person', 'customer', null),
  ('fb300000-0000-0000-0000-000000000003', 'fb200000-0000-0000-0000-000000000001', 'C Hard Bounced', 'person', 'customer', null),
  ('fb300000-0000-0000-0000-000000000004', 'fb200000-0000-0000-0000-000000000001', 'D No Consent', 'person', 'customer', null),
  ('fb300000-0000-0000-0000-000000000005', 'fb200000-0000-0000-0000-000000000001', 'E Archived', 'person', 'customer', now());

insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
values ('fb300000-0000-0000-0000-0000000000b1', 'fb200000-0000-0000-0000-000000000002', 'Other Org Customer', 'person', 'customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('fb400000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000001', 'email', 'one@example.test', true),
  ('fb400000-0000-0000-0000-000000000002', 'fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000002', 'email', 'two@example.test', true),
  ('fb400000-0000-0000-0000-000000000003', 'fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000003', 'email', 'three@example.test', true),
  ('fb400000-0000-0000-0000-000000000004', 'fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000004', 'email', 'four@example.test', true),
  ('fb400000-0000-0000-0000-000000000005', 'fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000005', 'email', 'five@example.test', true),
  ('fb400000-0000-0000-0000-0000000000b1', 'fb200000-0000-0000-0000-000000000002', 'fb300000-0000-0000-0000-0000000000b1', 'email', 'otherorg@example.test', true);

insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
)
values
  ('fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000001', 'fb400000-0000-0000-0000-000000000001', 'opt_in', 'staff', 'launch-one', now()),
  ('fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000002', 'fb400000-0000-0000-0000-000000000002', 'opt_in', 'staff', 'launch-two', now()),
  ('fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000003', 'fb400000-0000-0000-0000-000000000003', 'opt_in', 'staff', 'launch-three', now()),
  ('fb200000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000005', 'fb400000-0000-0000-0000-000000000005', 'opt_in', 'staff', 'launch-five', now()),
  ('fb200000-0000-0000-0000-000000000002', 'fb300000-0000-0000-0000-0000000000b1', 'fb400000-0000-0000-0000-0000000000b1', 'opt_in', 'staff', 'launch-other', now());

insert into public.communication_email_suppressions (organization_id, recipient_email, reason, source)
values ('fb200000-0000-0000-0000-000000000001', 'three@example.test', 'hard_bounce', 'manual');

insert into public.marketing_customer_groups (id, organization_id, name, rules)
values
  ('fb500000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', 'Everyone', '{"version":"1"}'::jsonb),
  ('fb500000-0000-0000-0000-000000000002', 'fb200000-0000-0000-0000-000000000002', 'Everyone B', '{"version":"1"}'::jsonb);

insert into public.marketing_campaigns (id, organization_id, name, goal, customer_group_id, status, content)
values
  ('fb600000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', 'Spring Offer', 'promote_service', 'fb500000-0000-0000-0000-000000000001', 'draft', '{}'::jsonb),
  ('fb600000-0000-0000-0000-000000000002', 'fb200000-0000-0000-0000-000000000001', 'Second Offer', 'promote_service', 'fb500000-0000-0000-0000-000000000001', 'draft', '{}'::jsonb),
  ('fb600000-0000-0000-0000-000000000003', 'fb200000-0000-0000-0000-000000000001', 'Scheduled Offer', 'promote_service', 'fb500000-0000-0000-0000-000000000001', 'draft', '{}'::jsonb),
  ('fb600000-0000-0000-0000-000000000004', 'fb200000-0000-0000-0000-000000000001', 'No Group Offer', 'promote_service', null, 'draft', '{}'::jsonb),
  ('fb600000-0000-0000-0000-0000000000b1', 'fb200000-0000-0000-0000-000000000002', 'Other Org Offer', 'promote_service', 'fb500000-0000-0000-0000-000000000002', 'draft', '{}'::jsonb);

-- A plan without a Marketing allowance stops the launch before anything is written. -------------------
select throws_ok(
  $$select public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
      'fb600000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 1, null, 'key-unset')$$,
  '23514', null, 'a campaign cannot launch while the plan has no Marketing allowance');
select is(
  (select count(*)::int from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000001'),
  0, 'a refused launch leaves no recipient rows behind');

-- The newest exception already in effect wins over the earlier "not included" one.
insert into public.organization_package_exceptions (
  organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at, actor_owner_email
)
values
  ('fb200000-0000-0000-0000-000000000001', 'marketing_email_recipients', 'numeric', 3,
    'Launch test allowance', now() - interval '1 minute', '2100-01-01T00:00:00Z', 'owner@example.test'),
  ('fb200000-0000-0000-0000-000000000002', 'marketing_email_recipients', 'numeric', 10,
    'Launch test allowance', now() - interval '1 minute', '2100-01-01T00:00:00Z', 'owner@example.test');

-- A campaign with no audience chosen cannot be sent. ---------------------------------------------------
select throws_ok(
  $$select public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
      'fb600000-0000-0000-0000-000000000004', 'fb100000-0000-0000-0000-000000000001', 1, null, 'key-nogroup')$$,
  '23514', null, 'a campaign with no customer group cannot be sent');

-- A stale edit is refused rather than overwritten. -----------------------------------------------------
select throws_ok(
  $$select public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
      'fb600000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 9, null, 'key-stale')$$,
  'P0409', null, 'launching against a revision someone else already changed is refused');

-- The real launch. -------------------------------------------------------------------------------------
select is(
  (public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
    'fb600000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 1, null, 'key-one'))->>'status',
  'sending', 'a launch with no send time starts sending immediately');
select is(
  (select status from public.marketing_campaigns where id = 'fb600000-0000-0000-0000-000000000001'),
  'sending', 'the campaign leaves draft');
select is(
  (select recipient_total_count from public.marketing_campaigns where id = 'fb600000-0000-0000-0000-000000000001'),
  5, 'every matched customer is in the snapshot, reachable or not');
select is(
  (select recipient_eligible_count from public.marketing_campaigns where id = 'fb600000-0000-0000-0000-000000000001'),
  2, 'only the customers the campaign can actually reach are eligible');
select is(
  (select recipient_excluded_count from public.marketing_campaigns where id = 'fb600000-0000-0000-0000-000000000001'),
  3, 'the archived, unconsented and hard-bounced customers are recorded as excluded');
select is(
  (select excluded_reason from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000001' and client_id = 'fb300000-0000-0000-0000-000000000003'),
  'hard_bounce', 'a customer whose address has hard bounced is excluded for that reason');
select is(
  (select excluded_reason from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000001' and client_id = 'fb300000-0000-0000-0000-000000000005'),
  'inactive_customer', 'the archived customer keeps its real reason');
select is(
  (select recipient_email from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000001' and client_id = 'fb300000-0000-0000-0000-000000000001'),
  'one@example.test', 'a waiting recipient carries the address the campaign was confirmed against');
select is(
  (select count(*)::int from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000001' and status = 'excluded' and recipient_email is not null),
  0, 'an excluded recipient is never given a send address');
select is(
  (select reserved_count from public.marketing_email_capacity_reservations
   where campaign_id = 'fb600000-0000-0000-0000-000000000001'),
  2, 'the launch reserves exactly the eligible count');

-- Changing a customer afterwards does not rewrite history. ---------------------------------------------
update public.client_contact_methods set value = 'changed@example.test'
where id = 'fb400000-0000-0000-0000-000000000001';
select is(
  (select recipient_email from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000001' and client_id = 'fb300000-0000-0000-0000-000000000001'),
  'one@example.test', 'editing a customer later does not change what a launched campaign recorded');

-- A retried request answers with the original launch. --------------------------------------------------
select is(
  (public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
    'fb600000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 1, null, 'key-one'))->>'replayed',
  'true', 'the same idempotency key replays the first launch instead of sending again');
select is(
  (select count(*)::int from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000001'),
  5, 'a replay writes no second snapshot');

-- A genuinely new launch of an already-sent campaign is refused. ---------------------------------------
select throws_ok(
  $$select public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
      'fb600000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 2, null, 'key-again')$$,
  '23514', null, 'a campaign that already left draft cannot be sent a second time');

-- The allowance is held across campaigns. --------------------------------------------------------------
select throws_ok(
  $$select public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
      'fb600000-0000-0000-0000-000000000002', 'fb100000-0000-0000-0000-000000000001', 1, null, 'key-two')$$,
  '23514', null, 'a second campaign cannot borrow allowance the first one is still holding');

-- A future send time schedules instead of sending. -----------------------------------------------------
update public.organization_package_exceptions set allowance_value = 10
where organization_id = 'fb200000-0000-0000-0000-000000000001'
  and allowance_key = 'marketing_email_recipients' and allowance_state = 'numeric';
select is(
  (public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000001',
    'fb600000-0000-0000-0000-000000000003', 'fb100000-0000-0000-0000-000000000001', 1,
    now() + interval '2 days', 'key-three'))->>'status',
  'scheduled', 'a future send time leaves the campaign scheduled');
select is(
  (select scheduled_for is not null from public.marketing_campaigns
   where id = 'fb600000-0000-0000-0000-000000000003'),
  true, 'a scheduled campaign remembers when it should go out');

-- Tenant isolation. ------------------------------------------------------------------------------------
select is(
  (public.marketing_launch_campaign('fb200000-0000-0000-0000-000000000002',
    'fb600000-0000-0000-0000-0000000000b1', 'fb100000-0000-0000-0000-000000000001', 1, null, 'key-b'))->>'eligible_count',
  '1', 'another organization launches to its own customers only');
select is(
  (select count(*)::int from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-0000000000b1'
     and organization_id <> 'fb200000-0000-0000-0000-000000000002'),
  0, 'no snapshot row escapes its organization');

select * from finish();
rollback;
