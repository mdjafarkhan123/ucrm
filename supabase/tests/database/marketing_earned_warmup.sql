-- Marketing M6f: earned warm-up for the Marketing sending domain.
--
-- A step advances only after its minimum days, a full day's limit of real sends, and clean bounce/complaint
-- rates; simulator sends never count; a reputation pause and 30 quiet days each step down; a capped
-- organization cannot starve another organization's campaign.
--
-- Run this whole file as one transaction that is rolled back at the end.
begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- Nobody outside server code reaches the warm-up. ----------------------------------------------------------
select is(has_function_privilege('authenticated', 'public.get_marketing_warmup_progress(uuid)', 'execute'),
  false, 'members cannot read warm-up progress directly');
select is(has_function_privilege('anon', 'public.get_marketing_warmup_progress(uuid)', 'execute'),
  false, 'signed-out callers cannot read warm-up progress');
select is(has_table_privilege('authenticated', 'public.marketing_warmup_state', 'select'),
  false, 'members cannot read the warm-up state table');

set local role postgres;

-- Park anything already queued so the claim assertions see only these fixtures.
update public.marketing_campaigns set status = 'completed' where status in ('sending', 'scheduled');

-- Fixtures: org W warms up; org V is a healthy organization that launches later. ---------------------------
insert into public.organizations (id, name, slug, lifecycle_status, created_at) values
  ('fe200000-0000-0000-0000-00000000000a', 'Warmup Org W', 'warmup-org-w', 'active', now() - interval '90 days'),
  ('fe200000-0000-0000-0000-00000000000b', 'Warmup Org V', 'warmup-org-v', 'active', now() - interval '90 days');

insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
select ('fe300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fe200000-0000-0000-0000-00000000000a',
  'W Customer ' || n, 'person', 'customer'
from generate_series(1, 300) n;
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
select ('fe400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fe200000-0000-0000-0000-00000000000a',
  ('fe300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'email', 'w' || n || '@example.test', true
from generate_series(1, 300) n;
insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
)
select 'fe200000-0000-0000-0000-00000000000a', ('fe300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('fe400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'opt_in', 'staff', 'warmup-w-' || n, now()
from generate_series(1, 300) n;

insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
values ('fe310000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-00000000000b', 'V Customer', 'person', 'customer');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('fe410000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-00000000000b',
  'fe310000-0000-0000-0000-000000000001', 'email', 'v1@example.test', true);
insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
) values ('fe200000-0000-0000-0000-00000000000b', 'fe310000-0000-0000-0000-000000000001',
  'fe410000-0000-0000-0000-000000000001', 'opt_in', 'staff', 'warmup-v-1', now());

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider, provider_verified,
  provider_authenticated, ownership_status, dkim_status, spf_status, verified_at, warmup_started_at
) values
  ('fe500000-0000-0000-0000-00000000000a', 'fe200000-0000-0000-0000-00000000000a', 'marketing_sending',
    'news.warmup-org-w.test', 'verified', 'ses', true, true, 'passing', 'passing', 'passing',
    now() - interval '40 days', now() - interval '40 days'),
  ('fe500000-0000-0000-0000-00000000000b', 'fe200000-0000-0000-0000-00000000000b', 'marketing_sending',
    'news.warmup-org-v.test', 'verified', 'ses', true, true, 'passing', 'passing', 'passing',
    now() - interval '40 days', now() - interval '40 days');

-- A new domain starts at step 1. --------------------------------------------------------------------------
select is(private.resolve_marketing_warmup_limit('fe500000-0000-0000-0000-00000000000a', now()), 100,
  'a domain that has never sent starts at 100 a day');
select is((select step::int from public.marketing_warmup_state where domain_id = 'fe500000-0000-0000-0000-00000000000a'),
  1, 'its first send stores step 1');
select is(private.try_advance_marketing_warmup('fe500000-0000-0000-0000-00000000000a', now()), false,
  'waiting out the calendar with no sends earns nothing');

-- One sent campaign: 60 real customers and 40 Amazon simulator addresses. ---------------------------------
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values
  ('fe600000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-00000000000a', 'W First',
    'promote_service', 'completed', '{}'::jsonb, now() - interval '1 day', 'warmup-w-first', 100, 100, 0),
  ('fe600000-0000-0000-0000-000000000002', 'fe200000-0000-0000-0000-00000000000a', 'W Second',
    'promote_service', 'completed', '{}'::jsonb, now() - interval '1 day', 'warmup-w-second', 200, 200, 0);

insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name,
  status, provider_message_id, submitted_at
)
select ('fe700000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fe200000-0000-0000-0000-00000000000a',
  'fe600000-0000-0000-0000-000000000001',
  ('fe300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('fe400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  case when n <= 60 then 'w' || n || '@example.test' else 'success+' || n || '@simulator.amazonses.com' end,
  'W Customer ' || n, 'delivered', 'ses-warm-' || n, now() - interval '1 day'
from generate_series(1, 100) n;

select is(private.try_advance_marketing_warmup('fe500000-0000-0000-0000-00000000000a', now()), false,
  'simulator sends do not count: 60 real sends are short of the 100 a step 1 domain must earn');

update public.marketing_campaign_recipients set recipient_email = 'w' || right(id::text, 3)::int || '@example.test'
where campaign_id = 'fe600000-0000-0000-0000-000000000001';

select is(private.try_advance_marketing_warmup('fe500000-0000-0000-0000-00000000000a', now()), true,
  '100 real, clean sends after the minimum 3 days earn step 2');
select is(private.resolve_marketing_warmup_limit('fe500000-0000-0000-0000-00000000000a', now()), 250,
  'step 2 allows 250 a day');
select is(private.try_advance_marketing_warmup('fe500000-0000-0000-0000-00000000000a', now()), false,
  'a step just reached cannot be passed before its own minimum days');

-- Step 2, five days in, with 300 real sends -- but 10 hard bounces (3.3%). ---------------------------------
update public.marketing_warmup_state set step_started_at = now() - interval '5 days'
where domain_id = 'fe500000-0000-0000-0000-00000000000a';

insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name,
  status, provider_message_id, submitted_at
)
select ('fe710000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fe200000-0000-0000-0000-00000000000a',
  'fe600000-0000-0000-0000-000000000002',
  ('fe300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('fe400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'w' || n || '@example.test', 'W Customer ' || n, 'delivered', 'ses-warm2-' || n, now() - interval '1 day'
from generate_series(101, 300) n;

insert into public.marketing_campaign_recipient_events (
  provider_event_key, provider_message_id, event_kind, payload, organization_id, normalized_kind, processed_at
)
select 'ses:ses-warm2-' || n || ':Bounce', 'ses-warm2-' || n, 'Bounce', '{}'::jsonb,
  'fe200000-0000-0000-0000-00000000000a', 'hard_bounce', now()
from generate_series(101, 110) n;

select is(private.try_advance_marketing_warmup('fe500000-0000-0000-0000-00000000000a', now()), false,
  'a 3.3% hard-bounce rate holds the step even with enough days and sends');

delete from public.marketing_campaign_recipient_events
where provider_message_id in (select 'ses-warm2-' || n from generate_series(104, 110) n);

select is(private.try_advance_marketing_warmup('fe500000-0000-0000-0000-00000000000a', now()), true,
  'at 1% hard bounces the step is earned');
select is((select step::int from public.marketing_warmup_state where domain_id = 'fe500000-0000-0000-0000-00000000000a'),
  3, 'the domain is on step 3 (500 a day)');
select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type = 'communications.marketing_warmup_step_changed'
     and target_key = 'fe200000-0000-0000-0000-00000000000a' and after_state ->> 'cause' = 'earned'),
  2, 'each earned step is recorded for Jafar');

-- A reputation pause gives back one step. -----------------------------------------------------------------
select lives_ok(
  $$select private.step_down_marketing_warmup('fe200000-0000-0000-0000-00000000000a', 'reputation_pause', now())$$,
  'stepping down on a pause runs');
select is((select step::int from public.marketing_warmup_state where domain_id = 'fe500000-0000-0000-0000-00000000000a'),
  2, 'the pause takes the domain from step 3 back to step 2');

-- 30 quiet days each give back one step. ------------------------------------------------------------------
update public.marketing_warmup_state set step = 4, step_started_at = now() - interval '70 days'
where domain_id = 'fe500000-0000-0000-0000-00000000000a';
update public.marketing_campaign_recipients set submitted_at = now() - interval '65 days'
where organization_id = 'fe200000-0000-0000-0000-00000000000a';

select is(private.resolve_marketing_warmup_limit('fe500000-0000-0000-0000-00000000000a', now()), 250,
  '65 quiet days take step 4 down two steps to 250 a day');
select is((select step::int from public.marketing_warmup_state where domain_id = 'fe500000-0000-0000-0000-00000000000a'),
  2, 'the quiet drop is stored');
select is(private.resolve_marketing_warmup_limit('fe500000-0000-0000-0000-00000000000a', now()), 250,
  'the same silence is never counted twice');

-- A graduated domain has no warm-up cap. ------------------------------------------------------------------
update public.marketing_warmup_state set step = 7, step_started_at = now()
where domain_id = 'fe500000-0000-0000-0000-00000000000a';
select is(private.resolve_marketing_warmup_limit('fe500000-0000-0000-0000-00000000000a', now()), null,
  'a graduated domain has no warm-up cap');
select is(public.get_marketing_warmup_progress('fe200000-0000-0000-0000-00000000000a') ->> 'status', 'graduated',
  'the progress card reports graduation');

-- The progress card for a domain one day into step 1. -----------------------------------------------------
update public.marketing_warmup_state set step = 1, step_started_at = now() - interval '1 day'
where domain_id = 'fe500000-0000-0000-0000-00000000000a';
select is(
  (select jsonb_build_object('status', p ->> 'status', 'step', (p ->> 'step')::int, 'limit', (p ->> 'daily_limit')::int,
     'next', (p ->> 'next_daily_limit')::int, 'days', (p ->> 'days_remaining')::int,
     'needed', (p ->> 'sends_needed')::int, 'ok', (p ->> 'quality_ok')::boolean)
   from public.get_marketing_warmup_progress('fe200000-0000-0000-0000-00000000000a') p),
  '{"status":"warming","step":1,"limit":100,"next":250,"days":2,"needed":100,"ok":true}'::jsonb,
  'the progress card shows the step, the limits, the days left, and the sends still needed');
select is(public.get_marketing_warmup_progress('fe200000-0000-0000-0000-00000000000b') ->> 'step', '1',
  'an organization that has never sent reads as step 1 without anything stored');
select is(public.get_marketing_warmup_progress('fe200000-0000-0000-0000-00000000000c') ->> 'status', 'no_domain',
  'an organization with no Marketing domain has no warm-up to show');

-- A capped organization cannot starve a later organization. -----------------------------------------------
-- W is held to 1 a day and has already used it today; its 60-recipient queue sits ahead of V's single recipient.
update public.marketing_warmup_state set limit_override = 1
where domain_id = 'fe500000-0000-0000-0000-00000000000a';
update public.marketing_campaign_recipients set submitted_at = now()
where id = 'fe700000-0000-0000-0000-000000000001';

insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values
  ('fe600000-0000-0000-0000-000000000003', 'fe200000-0000-0000-0000-00000000000a', 'W Capped',
    'promote_service', 'sending', '{}'::jsonb, now() - interval '1 hour', 'warmup-w-capped', 60, 60, 0),
  ('fe600000-0000-0000-0000-000000000004', 'fe200000-0000-0000-0000-00000000000b', 'V Later',
    'promote_service', 'sending', '{}'::jsonb, now(), 'warmup-v-later', 1, 1, 0);

insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
)
select ('fe720000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fe200000-0000-0000-0000-00000000000a',
  'fe600000-0000-0000-0000-000000000003',
  ('fe300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('fe400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'w' || n || '@example.test', 'W Customer ' || n, 'waiting'
from generate_series(1, 60) n;
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
) values ('fe730000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-00000000000b',
  'fe600000-0000-0000-0000-000000000004', 'fe310000-0000-0000-0000-000000000001',
  'fe410000-0000-0000-0000-000000000001', 'v1@example.test', 'V Customer', 'waiting');

select is((select recipient_email from public.claim_marketing_campaign_recipient()), 'v1@example.test',
  'the first claim reaches the later organization past the capped organization''s 60 waiting recipients');
select ok(
  (select capped_until > now() from public.marketing_warmup_state where domain_id = 'fe500000-0000-0000-0000-00000000000a'),
  'the capped organization is marked until the next day');
select is(
  (select count(*)::int from public.marketing_campaign_recipients
   where campaign_id = 'fe600000-0000-0000-0000-000000000003' and status = 'waiting'),
  60, 'the capped organization''s recipients stay waiting for tomorrow, not failed');
select is_empty($$select * from public.claim_marketing_campaign_recipient()$$,
  'a capped organization is skipped without being scanned again');

-- Reaching the limit is where a step is earned: the claim advances and sends in the same call. ------------
update public.marketing_warmup_state
set limit_override = null, capped_until = null, step = 1, step_started_at = now() - interval '4 days'
where domain_id = 'fe500000-0000-0000-0000-00000000000a';
-- 100 real sends earlier in the step, all today, so today's 100 is used up.
update public.marketing_campaign_recipients set submitted_at = now()
where campaign_id = 'fe600000-0000-0000-0000-000000000001';

select is(
  (select organization_id from public.claim_marketing_campaign_recipient()),
  'fe200000-0000-0000-0000-00000000000a'::uuid,
  'an organization at its limit that has earned the next step keeps sending');
select is((select step::int from public.marketing_warmup_state where domain_id = 'fe500000-0000-0000-0000-00000000000a'),
  2, 'the claim moved it to step 2');

-- Operational email keeps its own calendar ceiling. --------------------------------------------------------
select ok(
  pg_get_functiondef('public.claim_communication_outbox_event()'::regprocedure)
    like '%resolve_communication_email_warmup_ceiling%',
  'operational email still uses the calendar warm-up, never the Marketing ladder');

select * from finish();
rollback;
