-- Communications Part 3: resend reuses the existing send commands, so it must stay authorized, tenant-safe,
-- and only ever act on a message that is genuinely stuck -- never one still on an active retry schedule.
begin;

create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('c9000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'resend-sender@example.test', 'test', now(), now(), now()),
  ('c9000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'resend-viewer@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c9100000-0000-0000-0000-000000000001', 'Resend Test', 'resend-test', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000002', 'field', 'active');

insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001', 'conversations.send', 'grant'),
  ('c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001', 'customers.view', 'grant');

insert into public.clients (id, organization_id, display_name)
values ('c9200000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001', 'Resend Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('c9300000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001', 'email', 'customer@resend-test.example', true);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_domain_id,
  provider_verified, provider_authenticated, ownership_status, dkim_status, dmarc_status,
  spf_status, inbound_mx_status, verified_at
) values (
  'c9400000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
  'sending', 'mail.resend-test.example', 'verified', 94001, true, true, 'passing', 'passing',
  'passing', 'pending', 'unchecked', now()
);

-- Manual send only ever uses a sender explicitly assigned to the acting member -- never the org default.
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated, assigned_user_id
) values (
  'c9500000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
  'c9400000-0000-0000-0000-000000000001', 'hello@mail.resend-test.example', 'Resend Test',
  'enabled', true, true, true, 'c9000000-0000-0000-0000-000000000001'
);

select function_privs_are(
  'public', 'resend_communication_email',
  array['uuid', 'uuid', 'uuid', 'text', 'text', 'bytea'],
  'service_role', array['EXECUTE'], 'only service role can resend a communication email'
);

-- A message stuck failed with retries exhausted (available_at pushed to infinity).
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
  subject, html_content, text_content, status, send_kind, sender_id
) values (
  'c9600000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001', 'c9300000-0000-0000-0000-000000000001',
  'resend-stuck-failed', 'customer@resend-test.example', 'Stuck subject', '<p>Body</p>', 'Body',
  'failed', 'manual', 'c9500000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id, status, available_at)
values ('c9100000-0000-0000-0000-000000000001', 'c9600000-0000-0000-0000-000000000001', 'failed',
  'infinity'::timestamptz);

-- A message still on an active retry schedule -- must not be resendable, or the automatic retry and a
-- manual resend could both eventually succeed and double-send the customer.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
  subject, html_content, text_content, status, send_kind, sender_id
) values (
  'c9600000-0000-0000-0000-000000000002', 'c9100000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001', 'c9300000-0000-0000-0000-000000000001',
  'resend-retrying', 'customer@resend-test.example', 'Retrying subject', '<p>Body</p>', 'Body',
  'failed', 'manual', 'c9500000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id, status, available_at)
values ('c9100000-0000-0000-0000-000000000001', 'c9600000-0000-0000-0000-000000000002', 'failed',
  now() + interval '5 minutes');

-- A cancelled message is always a terminal, eligible state, even with no outbox row at all.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
  subject, html_content, text_content, status, send_kind, sender_id
) values (
  'c9600000-0000-0000-0000-000000000003', 'c9100000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001', 'c9300000-0000-0000-0000-000000000001',
  'resend-cancelled', 'customer@resend-test.example', 'Cancelled subject', '<p>Body</p>', 'Body',
  'cancelled', 'manual', 'c9500000-0000-0000-0000-000000000001'
);

select throws_ok(
  $$select public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000002',
    'c9600000-0000-0000-0000-000000000001', 'resend-attempt-denied'
  )$$,
  '42501', 'You do not have permission to send a customer message.',
  'a member without conversations.send cannot resend'
);

select throws_ok(
  $$select public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001',
    'c9600000-0000-0000-0000-00000000ffff', 'resend-not-found'
  )$$,
  'P0002', 'The original message could not be found.',
  'an id that does not resolve inside this organization cannot be resent'
);

select throws_ok(
  $$select public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001',
    'c9600000-0000-0000-0000-000000000002', 'resend-still-retrying'
  )$$,
  '55000', 'This message cannot be resent right now.',
  'a message still on an active retry schedule cannot be resent yet'
);

select is(
  (public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001',
    'c9600000-0000-0000-0000-000000000001', 'resend-of-stuck-failed'
  )).resent_from_intent_id,
  'c9600000-0000-0000-0000-000000000001'::uuid,
  'resending an exhausted failed message links the new attempt to the original'
);

select is(
  (select status from public.communication_delivery_intents
    where logical_send_key = 'resend-of-stuck-failed'),
  'queued',
  'the resent attempt starts as a fresh queued message'
);

select is(
  (public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001',
    'c9600000-0000-0000-0000-000000000003', 'resend-of-cancelled'
  )).resent_from_intent_id,
  'c9600000-0000-0000-0000-000000000003'::uuid,
  'a cancelled message can also be resent'
);

select is(
  (public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001',
    'c9600000-0000-0000-0000-000000000001', 'resend-of-stuck-failed'
  )).id,
  (select id from public.communication_delivery_intents where logical_send_key = 'resend-of-stuck-failed'),
  'replaying the same resend key does not create a second attempt'
);

-- A quote-sourced resend has only ever been exercised by a human clicking Resend in the Inbox. Prove the
-- same command's quote branch (enqueue_quote_communication_email) works when driven directly, using a
-- genuinely published quote built through the real commands rather than fabricated rows.
insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('c9700000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001', '1 Resend Street', 'Resend City');

select set_config('request.jwt.claim.sub', 'c9000000-0000-0000-0000-000000000001', true);

select public.create_quote(
  'c9200000-0000-0000-0000-000000000001', 'c9700000-0000-0000-0000-000000000001',
  'Resend Quote Test', null
);

create function pg_temp.resend_quote_id() returns uuid language sql stable as
  'select id from public.quotes where title = ''Resend Quote Test''';
create function pg_temp.resend_quote_revision() returns integer language sql stable as
  'select revision from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''Resend Quote Test'')';

select public.replace_quote_version_lines(
  pg_temp.resend_quote_id(), pg_temp.resend_quote_revision(),
  jsonb_build_array(jsonb_build_object(
    'name', 'Resend line', 'category', 'service', 'quantity', 1,
    'unit_price_minor', 10000, 'unit_cost_minor', 4000, 'is_taxable', false
  ))
);

select public.set_quote_draft_tax(pg_temp.resend_quote_id(), pg_temp.resend_quote_revision(), 'no_tax');

select public.publish_quote(pg_temp.resend_quote_id(), pg_temp.resend_quote_revision());

select set_config('request.jwt.claim.sub', '', true);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, quote_id, logical_send_key,
  recipient_email, subject, html_content, text_content, status, send_kind, allowance_class, sender_id
) values (
  'c9600000-0000-0000-0000-000000000004', 'c9100000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001', 'c9300000-0000-0000-0000-000000000001',
  pg_temp.resend_quote_id(), 'resend-quote-stuck',
  'customer@resend-test.example', 'Your quote is ready', '<p>Body</p>', 'Body',
  'cancelled', 'automated', 'essential', 'c9500000-0000-0000-0000-000000000001'
);

select throws_ok(
  $$select public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001',
    'c9600000-0000-0000-0000-000000000004', 'resend-quote-missing-link'
  )$$,
  '23514', 'The quote delivery link is not available.',
  'a quote resend without a fresh link is refused, same as a first send'
);

select is(
  (public.resend_communication_email(
    'c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001',
    'c9600000-0000-0000-0000-000000000004', 'resend-of-quote',
    'https://app.example.test/q/resend-token',
    decode(repeat('aa', 32), 'hex')
  )).quote_id,
  pg_temp.resend_quote_id(),
  'resending a quote-sourced message keeps it tied to the same quote'
);

select is(
  (select resent_from_intent_id from public.communication_delivery_intents
    where logical_send_key = 'resend-of-quote'),
  'c9600000-0000-0000-0000-000000000004'::uuid,
  'the quote resend links back to the cancelled original'
);

select is(
  (select status from public.communication_delivery_intents where logical_send_key = 'resend-of-quote'),
  'queued', 'the resent quote email starts fresh, exactly like a manual resend'
);

select is(
  (select count(*)::integer from public.quote_access_links where quote_id = pg_temp.resend_quote_id()),
  1, 'resend mints a fresh access link for the resent quote email'
);

select * from finish();
rollback;
