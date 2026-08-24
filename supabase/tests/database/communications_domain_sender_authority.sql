-- Communications Part 2: domains and sender identities are tenant-safe stored authority.
begin;

create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'domain-admin-a@example.test', 'test', now(), now(), now()),
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'domain-field-a@example.test', 'test', now(), now(), now()),
  ('d1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'domain-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d2000000-0000-0000-0000-000000000001', 'Domain Test A', 'domain-test-a', 'active'),
  ('d2000000-0000-0000-0000-000000000002', 'Domain Test B', 'domain-test-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'admin'),
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'field'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', 'admin');

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_domain_id,
  provider_verified, provider_authenticated, ownership_status, dkim_status, dmarc_status,
  spf_status, inbound_mx_status, verified_at
) values
  ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
   'sending', 'mail.domain-a.test', 'verified', 91001, true, true, 'passing', 'passing',
   'passing', 'passing', 'unchecked', now()),
  ('d3000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001',
   'receiving', 'reply.domain-a.test', 'verified', 91002, true, false, 'passing', 'unchecked',
   'unchecked', 'unchecked', 'passing', now()),
  ('d3000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000002',
   'sending', 'mail.domain-b.test', 'pending_dns', 91003, false, false, 'pending', 'pending',
   'pending', 'pending', 'unchecked', null);

insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, provider_sender_id,
  lifecycle_state, is_organization_default, allows_manual, allows_automated
) values (
  'd4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001', 'hello@mail.domain-a.test', 'Domain Test A',
  92001, 'enabled', true, true, true
);

select has_index(
  'public', 'communication_email_domains', 'communication_email_domains_live_claim_idx',
  'live domain claims have a global partial unique index'
);
select has_index(
  'public', 'communication_email_senders', 'communication_email_senders_eligible_idx',
  'worker sender resolution has a narrow partial index'
);
select has_index(
  'public', 'communication_email_authority_events',
  'communication_email_authority_events_organization_time_idx',
  'authority history has an organization cursor index'
);
select is(
  (select count(*)::integer from public.communication_email_domains), 3,
  'separate sending and receiving domain authorities can be stored'
);
select is(
  (select count(*)::integer from public.communication_email_senders), 1,
  'an eligible sender on its exact verified sending domain can be stored'
);

select throws_ok(
  $$insert into public.communication_email_domains (organization_id, purpose, domain_name)
    values ('d2000000-0000-0000-0000-000000000002', 'sending', 'mail.domain-a.test')$$,
  '23505', null,
  'another organization cannot claim a live domain'
);
select lives_ok(
  $$insert into public.communication_email_domains (
      organization_id, purpose, domain_name, lifecycle_state, provider_verified,
      provider_authenticated, ownership_status, dkim_status, spf_status
    ) values (
      'd2000000-0000-0000-0000-000000000002', 'sending', 'mail.invalid-spf.test',
      'verified', true, true, 'passing', 'passing', 'failing'
    )$$,
  'a Brevo-authenticated sending domain can become verified while SPF remains diagnostic'
);
select throws_ok(
  $$insert into public.communication_email_senders (
      organization_id, domain_id, email_address, display_name, lifecycle_state
    ) values (
      'd2000000-0000-0000-0000-000000000001',
      'd3000000-0000-0000-0000-000000000002', 'hello@reply.domain-a.test', 'Wrong Purpose', 'enabled'
    )$$,
  '23503', 'A sender requires a live sending domain in the same organization.',
  'a receiving domain cannot authorize a sender'
);
select throws_ok(
  $$insert into public.communication_email_senders (
      organization_id, domain_id, email_address, display_name, lifecycle_state
    ) values (
      'd2000000-0000-0000-0000-000000000001',
      'd3000000-0000-0000-0000-000000000001', 'hello@other.test', 'Wrong Domain', 'enabled'
    )$$,
  '23514', 'The sender address must use its sending domain.',
  'a sender address must align exactly with its stored domain'
);
select throws_ok(
  $$insert into public.communication_email_senders (
      organization_id, domain_id, email_address, display_name, lifecycle_state,
      is_organization_default
    ) values (
      'd2000000-0000-0000-0000-000000000001',
      'd3000000-0000-0000-0000-000000000001', 'second@mail.domain-a.test',
      'Second Default', 'enabled', true
    )$$,
  '23505', null,
  'an organization has at most one enabled default sender'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer from public.communication_email_domains), 2,
  'an administrator sees only their organization domains'
);
select is(
  (select count(*)::integer from public.communication_email_senders), 1,
  'an administrator sees only their organization senders'
);
select throws_ok(
  $$insert into public.communication_email_domains (organization_id, purpose, domain_name)
    values ('d2000000-0000-0000-0000-000000000001', 'sending', 'direct-write.test')$$,
  '42501', null,
  'authenticated users cannot bypass server commands with a direct domain insert'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*)::integer from public.communication_email_domains), 0,
  'a member without connection permission cannot read domains'
);
select is(
  (select count(*)::integer from public.communication_email_senders), 0,
  'a member without connection or send permission cannot read senders'
);

reset role;
select table_privs_are(
  'public', 'communication_email_domains', 'authenticated', array['SELECT'],
  'authenticated receives read-only table privilege and RLS decides visibility'
);
select table_privs_are(
  'public', 'communication_email_senders', 'authenticated', array['SELECT'],
  'authenticated cannot directly mutate sender authority'
);
select table_privs_are(
  'public', 'communication_email_authority_events', 'authenticated', array['SELECT'],
  'email authority history is append-only from the contractor boundary'
);

reset role;
select function_privs_are(
  'public', 'begin_communication_email_domain_removal',
  array['uuid', 'uuid', 'integer', 'integer'], 'service_role', array['EXECUTE'],
  'only service role can start domain removal'
);
select is(
  (public.begin_communication_email_domain_removal(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001', 0, 0
  ) ->> 'status'),
  'impact_changed',
  'a stale removal preview is rejected atomically'
);
select is(
  (public.begin_communication_email_domain_removal(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001', 1, 0
  ) ->> 'status'),
  'blocked',
  'a domain with a live sender cannot enter removal'
);

update public.communication_email_senders
set lifecycle_state = 'removed', is_organization_default = false,
    provider_sender_id = null, provider_cleanup_error = null
where id = 'd4000000-0000-0000-0000-000000000001';

select is(
  (public.begin_communication_email_domain_removal(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001', 0, 0
  ) ->> 'status'),
  'started',
  'a clear domain enters removal pending atomically'
);
select throws_ok(
  $$insert into public.communication_email_senders (
      organization_id, domain_id, email_address, display_name, lifecycle_state
    ) values (
      'd2000000-0000-0000-0000-000000000001',
      'd3000000-0000-0000-0000-000000000001', 'late@mail.domain-a.test', 'Late Sender',
      'pending_verification'
    )$$,
  '23514', 'A live sender requires a verified sending domain.',
  'a sender cannot be added after domain removal starts'
);
select function_privs_are(
  'public', 'finalize_communication_email_domain_removal',
  array['uuid', 'uuid', 'text', 'text', 'text'], 'service_role', array['EXECUTE'],
  'only service role can finalize domain removal'
);
select is(
  (public.finalize_communication_email_domain_removal(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    'owner@example.test', 'No longer used', 'domain-removal-test-command'
  ) ->> 'status'),
  'completed',
  'provider-confirmed cleanup and its receipt finalize together'
);

select * from finish();
rollback;
