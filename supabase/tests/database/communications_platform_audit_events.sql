-- Communications A2 / Stage 2C (part 5c, platform-scoped prerequisite): platform_audit_events records Platform
-- Owner actions with no single owning organization. Same shape as access_audit_events minus the organization
-- tag; server-owned, append-only, no browser client may touch it directly.
begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

select has_table('public', 'platform_audit_events', 'platform audit events are a first-class record');
select col_is_pk('public', 'platform_audit_events', 'id', 'each event has a stable identity');
select has_index('public', 'platform_audit_events', 'platform_audit_events_created_idx',
  'an index backs listing events by recency');
select has_index('public', 'platform_audit_events', 'platform_audit_events_target_idx',
  'an index backs looking up events by target');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.platform_audit_events'::regclass),
  'platform audit events keep row-level security enabled'
);
select table_privs_are('public', 'platform_audit_events', 'authenticated', array[]::text[],
  'authenticated clients have no direct platform-audit privileges');
select table_privs_are('public', 'platform_audit_events', 'anon', array[]::text[],
  'anonymous clients have no direct platform-audit privileges');
select table_privs_are('public', 'platform_audit_events', 'service_role', array['SELECT', 'INSERT'],
  'only the server role reads/writes platform audit events, and never updates or deletes one');

-- No organization tag exists to be null-by-accident: the column is simply absent.
select hasnt_column('public', 'platform_audit_events', 'organization_id',
  'a platform event carries no organization -- that is the point of this table over access_audit_events');

-- Shape matches what recordPlatformAudit writes.
insert into public.platform_audit_events (
  actor_owner_email, event_type, target_type, target_key, before_state, after_state
) values (
  'jafar@example.com', 'communication_sms_platform_hold_placed', 'communication_sms_hold', 'a-hold-id',
  null, '{"scope": "platform"}'::jsonb
);
select is(
  (select count(*)::int from public.platform_audit_events where event_type = 'communication_sms_platform_hold_placed'),
  1, 'an event with only an after_state can be recorded'
);
select is(
  (select target_key from public.platform_audit_events where event_type = 'communication_sms_platform_hold_placed'),
  'a-hold-id', 'the target key is stored as given'
);

select * from finish();
rollback;
