-- Communications A2 / Stage 4A part 1: SMS consent proof is scoped to one exact customer number and to specific
-- operational subjects, only an owner or administrator may record external proof, verbal proof is refused, and a
-- newer opt-out always wins over an older opt-in.
begin;

create extension if not exists pgtap with schema extensions;
select plan(33);

-- ---------------------------------------------------------------------------------------------------------------
-- Shape and access boundary.
-- ---------------------------------------------------------------------------------------------------------------
select has_column('public', 'communication_sms_consent_events', 'subjects',
  'consent evidence records the operational subjects an opt-in covers');
select has_column('public', 'communication_sms_consent_events', 'proof_method',
  'consent evidence records how an opt-in was proven');
select hasnt_table('public', 'communication_sms_consent_state',
  'the Stage 1 per-method global projection is removed in favor of subject-aware reads');
select has_function('public', 'communication_sms_consent_status',
  array['uuid', 'uuid', 'text'], 'a subject-aware consent read exists');
select has_function('public', 'communication_sms_record_consent_proof',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text[]', 'timestamp with time zone', 'text', 'jsonb'],
  'the owner/admin consent-proof command exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_consent_events'::regclass),
  'consent evidence keeps row-level security enabled');
select function_privs_are('public', 'communication_sms_record_consent_proof',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text[]', 'timestamp with time zone', 'text', 'jsonb'],
  'authenticated', array[]::text[],
  'authenticated clients cannot call the consent-proof command directly');
select function_privs_are('public', 'communication_sms_record_consent_proof',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text[]', 'timestamp with time zone', 'text', 'jsonb'],
  'service_role', array['EXECUTE'],
  'the server role owns the consent-proof command');

-- ---------------------------------------------------------------------------------------------------------------
-- Fixtures: two organizations, a client and phone in each, and members of each role in org A.
-- ---------------------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'consent-owner@example.test', 'test', now(), now()),
  ('f0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'consent-admin@example.test', 'test', now(), now()),
  ('f0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'consent-field@example.test', 'test', now(), now()),
  ('f0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'consent-other-owner@example.test', 'test', now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('f1000000-0000-0000-0000-000000000001', 'Consent Co A', 'consent-co-a', 'active'),
  ('f1000000-0000-0000-0000-000000000002', 'Consent Co B', 'consent-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003', 'field', 'active'),
  ('f1000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000004', 'owner', 'active');

insert into public.clients (id, organization_id, display_name) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'Consent Client A'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002', 'Consent Client B');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('f3000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001', 'phone', '+15550000101', true),
  ('f3000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002',
   'f2000000-0000-0000-0000-000000000002', 'phone', '+15550000102', true);

-- ---------------------------------------------------------------------------------------------------------------
-- Unknown by default: no evidence means every subject blocks sending.
-- ---------------------------------------------------------------------------------------------------------------
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'service'),
  'unknown', 'with no evidence a subject is unknown and blocks sending');

-- ---------------------------------------------------------------------------------------------------------------
-- Owner and admin may record external proof; an ordinary member may not.
-- ---------------------------------------------------------------------------------------------------------------
select lives_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'signed_agreement', array['service']::text[], '2026-09-14 10:00:00+00', 'proof-owner-service')$$,
  'an owner can record external consent proof');
select lives_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'web_form', array['work_updates']::text[], '2026-09-14 11:00:00+00', 'proof-admin-work')$$,
  'an administrator can record external consent proof');
select throws_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'signed_agreement', array['service']::text[], '2026-09-14 12:00:00+00', 'proof-field-service')$$,
  '42501', null, 'an ordinary member cannot record consent proof');

-- ---------------------------------------------------------------------------------------------------------------
-- Subject separation: a granted subject is opted_in; an ungranted subject stays unknown.
-- ---------------------------------------------------------------------------------------------------------------
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'service'),
  'opted_in', 'the service subject the owner recorded is opted_in');
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'work_updates'),
  'opted_in', 'the work_updates subject the admin recorded is opted_in');
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'billing_updates'),
  'unknown', 'a subject nobody recorded stays unknown and blocks sending');

-- ---------------------------------------------------------------------------------------------------------------
-- Verbal consent and other invalid input are refused.
-- ---------------------------------------------------------------------------------------------------------------
select throws_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'verbal', array['service']::text[], '2026-09-14 10:00:00+00', 'proof-verbal')$$,
  'P0001', null, 'verbal consent is refused');
select throws_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'signed_agreement', array[]::text[], '2026-09-14 10:00:00+00', 'proof-no-subject')$$,
  'P0001', null, 'proof must cover at least one subject');
select throws_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'signed_agreement', array['marketing']::text[], '2026-09-14 10:00:00+00', 'proof-marketing')$$,
  'P0001', null, 'marketing is not an operational subject and is refused');
select throws_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'signed_agreement', array['service']::text[], now() + interval '1 day', 'proof-future')$$,
  'P0001', null, 'consent proof cannot be dated in the future');

-- ---------------------------------------------------------------------------------------------------------------
-- Exact-number scope: proof cannot attach to another organization's contact method or a mismatched client.
-- ---------------------------------------------------------------------------------------------------------------
select throws_ok(
  $$select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002',
      'signed_agreement', array['service']::text[], '2026-09-14 10:00:00+00', 'proof-cross-tenant')$$,
  'P0001', null, 'proof cannot attach to another organization''s phone number');

-- ---------------------------------------------------------------------------------------------------------------
-- Idempotency: the same recorded proof key returns the same evidence row and never duplicates it.
-- ---------------------------------------------------------------------------------------------------------------
select is(
  (select public.communication_sms_record_consent_proof(
      'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
      'signed_agreement', array['service']::text[], '2026-09-14 10:00:00+00', 'proof-owner-service')).source_event_key,
  'proof-owner-service', 'recording the same proof again returns the same evidence row');
select is(
  (select count(*)::integer from public.communication_sms_consent_events
    where organization_id = 'f1000000-0000-0000-0000-000000000001'
      and source = 'staff' and source_event_key = 'proof-owner-service'),
  1, 'the repeated proof did not create a duplicate evidence row');

-- ---------------------------------------------------------------------------------------------------------------
-- A newer opt-out is a global legal block across every subject; an older opt-in cannot clear it.
-- ---------------------------------------------------------------------------------------------------------------
insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
  proof_method, occurred_at
) values (
  'f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001', 'opt_out', 'client_reply', 'stop-keyword',
  'client_reply', '2026-09-15 09:00:00+00'
);
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'service'),
  'opted_out', 'a newer opt-out blocks a previously opted-in subject');
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'work_updates'),
  'opted_out', 'the opt-out is global and blocks every subject');

-- A delayed, older opt-in arriving after the opt-out still cannot clear the newer opt-out.
insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
  subjects, proof_method, occurred_at
) values (
  'f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001', 'opt_in', 'import', 'late-old-optin',
  array['service']::text[], 'signed_agreement', '2026-09-14 08:00:00+00'
);
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'service'),
  'opted_out', 'a delayed older opt-in cannot clear the newer opt-out');

-- ---------------------------------------------------------------------------------------------------------------
-- Re-opt-in per subject: a customer can validly opt back in for one subject after opting out, subject by subject.
-- ---------------------------------------------------------------------------------------------------------------
insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
  subjects, proof_method, occurred_at
) values (
  'f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001', 'opt_in', 'client_reply', 'reoptin-service',
  array['service']::text[], 'client_reply', '2026-09-15 10:00:00+00'
);
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'service'),
  'opted_in', 'a newer re-opt-in for service restores that subject');
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'work_updates'),
  'opted_out', 'work_updates stays blocked because only service was re-opted-in');

-- ---------------------------------------------------------------------------------------------------------------
-- HELP requests are evidence but never change eligibility.
-- ---------------------------------------------------------------------------------------------------------------
insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
) values (
  'f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001', 'help_requested', 'client_reply', 'help-keyword',
  '2026-09-15 11:00:00+00'
);
select is(
  public.communication_sms_consent_status(
    'f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'service'),
  'opted_in', 'a later HELP request does not change the service opt-in');

-- ---------------------------------------------------------------------------------------------------------------
-- Constraint backstops: the evidence table itself refuses malformed rows even outside the command.
-- ---------------------------------------------------------------------------------------------------------------
select throws_ok(
  $$insert into public.communication_sms_consent_events (
      organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
      proof_method, occurred_at
    ) values (
      'f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000001', 'opt_in', 'staff', 'optin-no-subjects',
      'signed_agreement', now()
    )$$,
  '23514', null, 'an opt-in without subjects is refused by the constraint');
select throws_ok(
  $$insert into public.communication_sms_consent_events (
      organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
      subjects, proof_method, occurred_at
    ) values (
      'f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000001', 'opt_in', 'staff', 'optin-bad-subject',
      array['marketing']::text[], 'signed_agreement', now()
    )$$,
  '23514', null, 'an opt-in for a non-operational subject is refused by the constraint');
select throws_ok(
  $$insert into public.communication_sms_consent_events (
      organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
      subjects, occurred_at
    ) values (
      'f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000001', 'opt_out', 'client_reply', 'optout-with-subjects',
      array['service']::text[], now()
    )$$,
  '23514', null, 'a global opt-out cannot carry a subject list');

-- The Stage 1 append-only privileges are preserved: the server may add evidence but never rewrite it.
select table_privs_are('public', 'communication_sms_consent_events', 'service_role',
  array['SELECT', 'INSERT'],
  'the server role can append but not rewrite consent evidence');
select table_privs_are('public', 'communication_sms_consent_events', 'authenticated', array[]::text[],
  'authenticated clients have no direct consent evidence privileges');

select * from finish();
rollback;
