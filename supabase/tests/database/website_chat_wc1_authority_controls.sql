begin;

create extension if not exists pgtap with schema extensions;
select plan(33);

select ok((select relrowsecurity from pg_class where oid = 'public.communication_website_chat_authority_events'::regclass), 'authority events keep RLS enabled');
select is(has_table_privilege('anon', 'public.communication_website_chat_authority_events', 'select'), false, 'anonymous callers cannot read authority history');
select is(has_table_privilege('authenticated', 'public.communication_website_chat_authority_events', 'select'), false, 'contractors cannot read authority history');
select is(has_table_privilege('service_role', 'public.communication_website_chat_authority_events', 'select'), true, 'the owner service role can read authority history');

select is(has_function_privilege('anon', 'public.set_organization_website_chat_suspension(uuid, boolean, text, text, uuid)', 'execute'), false, 'anonymous callers cannot suspend Website Chat');
select is(has_function_privilege('authenticated', 'public.set_organization_website_chat_suspension(uuid, boolean, text, text, uuid)', 'execute'), false, 'contractors cannot suspend Website Chat through the owner authority');
select is(has_function_privilege('service_role', 'public.set_organization_website_chat_suspension(uuid, boolean, text, text, uuid)', 'execute'), true, 'the owner service role can suspend Website Chat');
select is(has_function_privilege('anon', 'public.rotate_website_chat_widget_public_token(uuid, uuid, integer, text, text, uuid)', 'execute'), false, 'anonymous callers cannot rotate a widget token');
select is(has_function_privilege('authenticated', 'public.rotate_website_chat_widget_public_token(uuid, uuid, integer, text, text, uuid)', 'execute'), false, 'contractors cannot rotate a widget token through the owner authority');
select is(has_function_privilege('service_role', 'public.rotate_website_chat_widget_public_token(uuid, uuid, integer, text, text, uuid)', 'execute'), true, 'the owner service role can rotate a widget token');
select is(has_function_privilege('authenticated', 'public.get_organization_website_chat_authority(uuid)', 'execute'), false, 'contractors cannot read owner Website Chat authority');
select is(has_function_privilege('service_role', 'public.get_organization_website_chat_authority(uuid)', 'execute'), true, 'the owner service role can read Website Chat authority');

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000008c1', 'WC1 Authority Test', 'wc1-authority-test', 'active');

insert into public.website_chat_widgets (id, organization_id, name, published)
values
  ('90000000-0000-0000-0000-0000000008c2', '90000000-0000-0000-0000-0000000008c1', 'Primary', true),
  ('90000000-0000-0000-0000-0000000008c3', '90000000-0000-0000-0000-0000000008c1', 'Secondary', false);

select is(
  public.set_organization_website_chat_suspension(
    '90000000-0000-0000-0000-0000000008c1', true, 'Investigating abusive traffic.',
    'owner@example.test', '90000000-0000-0000-0000-0000000008d1'
  ) ->> 'applied',
  'true', 'the owner suspension applies'
);
select is((select count(*)::integer from public.website_chat_widgets where organization_id = '90000000-0000-0000-0000-0000000008c1' and suspended_at is not null), 2, 'suspension reaches every existing widget');
select is((select count(*)::integer from public.communication_website_chat_authority_events where organization_id = '90000000-0000-0000-0000-0000000008c1'), 1, 'suspension writes one authority event');
select is((select count(*)::integer from public.platform_owner_audit_events where event_type = 'communications.website_chat_suspension_engaged' and target_key = '90000000-0000-0000-0000-0000000008c1'), 1, 'suspension writes the shared owner audit event');
select is(
  public.set_organization_website_chat_suspension(
    '90000000-0000-0000-0000-0000000008c1', true, 'Investigating abusive traffic.',
    'owner@example.test', '90000000-0000-0000-0000-0000000008d1'
  ) ->> 'applied',
  'false', 'replaying the suspension is idempotent'
);
select is((select count(*)::integer from public.communication_website_chat_authority_events where organization_id = '90000000-0000-0000-0000-0000000008c1'), 1, 'the suspension replay creates no duplicate history');

insert into public.website_chat_widgets (id, organization_id, name)
values ('90000000-0000-0000-0000-0000000008c4', '90000000-0000-0000-0000-0000000008c1', 'Created During Hold');
select ok((select suspended_at is not null from public.website_chat_widgets where id = '90000000-0000-0000-0000-0000000008c4'), 'a new widget inherits the active organization suspension');
select is(public.get_organization_website_chat_authority('90000000-0000-0000-0000-0000000008c1') #>> '{suspension,reason}', 'Investigating abusive traffic.', 'the health read explains the active suspension');

select is(
  public.set_organization_website_chat_suspension(
    '90000000-0000-0000-0000-0000000008c1', false, 'Investigation is complete.',
    'owner@example.test', '90000000-0000-0000-0000-0000000008d2'
  ) ->> 'suspended',
  'false', 'the owner can restore Website Chat'
);
select is((select count(*)::integer from public.website_chat_widgets where organization_id = '90000000-0000-0000-0000-0000000008c1' and suspended_at is not null), 0, 'restore reaches every widget');

create temporary table token_before as
select public_token, revision from public.website_chat_widgets where id = '90000000-0000-0000-0000-0000000008c2';

select is(
  public.rotate_website_chat_widget_public_token(
    '90000000-0000-0000-0000-0000000008c1', '90000000-0000-0000-0000-0000000008c2',
    (select revision from token_before), 'The installation token was exposed.', 'owner@example.test',
    '90000000-0000-0000-0000-0000000008d3'
  ) ->> 'applied',
  'true', 'token rotation applies'
);
select isnt((select public_token from public.website_chat_widgets where id = '90000000-0000-0000-0000-0000000008c2'), (select public_token from token_before), 'token rotation replaces the public identifier');
select is((select revision from public.website_chat_widgets where id = '90000000-0000-0000-0000-0000000008c2'), (select revision + 1 from token_before), 'token rotation advances optimistic concurrency');
select is((select count(*)::integer from public.communication_website_chat_authority_events where event_kind = 'public_token_rotated' and widget_id = '90000000-0000-0000-0000-0000000008c2'), 1, 'token rotation writes one authority event');

select throws_ok(
  $$select public.rotate_website_chat_widget_public_token(
    '90000000-0000-0000-0000-0000000008c1', '90000000-0000-0000-0000-0000000008c2', 1,
    'Stale support screen.', 'owner@example.test', '90000000-0000-0000-0000-0000000008d4'
  )$$,
  '40001', 'The widget changed while you were reviewing it. Reload and try again.',
  'a stale owner screen cannot rotate over a newer widget revision'
);
select is(jsonb_array_length(public.get_organization_website_chat_authority('90000000-0000-0000-0000-0000000008c1') -> 'widgets'), 3, 'the health read returns the bounded widget list');
select is((public.get_organization_website_chat_authority('90000000-0000-0000-0000-0000000008c1') ->> 'widget_total_count')::integer, 3, 'the health read reports the full widget count');
select is((public.get_organization_website_chat_authority('90000000-0000-0000-0000-0000000008c1') ->> 'widgets_truncated')::boolean, false, 'the health read says when the bounded list is complete');
select is(jsonb_array_length(public.get_organization_website_chat_authority('90000000-0000-0000-0000-0000000008c1') -> 'recent_events'), 3, 'the health read returns suspension, restore, and rotation history');
select is(
  public.rotate_website_chat_widget_public_token(
    '90000000-0000-0000-0000-0000000008c1', '90000000-0000-0000-0000-0000000008c2',
    (select revision from token_before), 'The installation token was exposed.', 'owner@example.test',
    '90000000-0000-0000-0000-0000000008d3'
  ) ->> 'applied',
  'false', 'replaying token rotation is idempotent'
);
select is((select count(*)::integer from public.communication_website_chat_authority_events where event_kind = 'public_token_rotated' and widget_id = '90000000-0000-0000-0000-0000000008c2'), 1, 'the token replay creates no duplicate authority event');

select * from finish();
rollback;
