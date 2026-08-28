-- Communications Part 8.3: the recoverable closure window.
--
-- Two things must hold for the whole 30 days. Nothing may take the organization's inbound routing
-- away -- its reply aliases and verified receiving domain stay, and a customer replying mid-closure
-- still lands in the right conversation. And an owner asking to delete permanently before the
-- deadline must first be able to see what that destroys: active aliases, unfinished queued messages,
-- replies received since closure started. Restore then puts sending back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(16);

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e9100000-0000-0000-0000-000000000001', 'Closure Preview Co', 'closure-preview-co', 'active'),
  ('e9100000-0000-0000-0000-000000000002', 'Closure Preview Untouched', 'closure-preview-untouched', 'active');

insert into public.clients (id, organization_id, display_name) values
  ('e9200000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001', 'Preview Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e9300000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'email', 'customer@closure-preview.example', true);

-- A verified sending domain and its sender, plus the verified receiving domain the reply alias lives
-- on. These are the provider-backed resources the closure window must not disturb.
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified,
  provider_authenticated, ownership_status, dkim_status, spf_status, inbound_mx_status, verified_at
) values
  ('e9400000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001', 'sending',
   'send.closure-preview.example', 'verified', true, true, 'passing', 'passing', 'passing',
   'unchecked', now() - interval '200 days'),
  ('e9400000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000001', 'receiving',
   'reply.closure-preview.example', 'verified', true, false, 'passing', 'unchecked', 'unchecked',
   'passing', now() - interval '200 days');

insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated
) values (
  'e9500000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
  'e9400000-0000-0000-0000-000000000001', 'office@send.closure-preview.example', 'Preview Office',
  'enabled', true, true, true
);

-- One live alias and one that lapsed on its own 90-day clock. Only the live one can still route.
insert into public.communication_reply_aliases (
  id, organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id,
  alias_local_part, expires_at
) values
  ('e9600000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
   'e9400000-0000-0000-0000-000000000002', 'e9500000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'live-alias-8300', now() + interval '60 days');

-- The lapsed alias needs its own conversation tuple: the unique (org, sender, client, contact method)
-- constraint keeps one alias per conversation, so this one hangs off a second contact method.
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e9300000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'email', 'old@closure-preview.example', false);

insert into public.communication_reply_aliases (
  id, organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id,
  alias_local_part, expires_at
) values (
  'e9600000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000001',
  'e9400000-0000-0000-0000-000000000002', 'e9500000-0000-0000-0000-000000000001',
  'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000002',
  'lapsed-alias-8300', now() - interval '1 day'
);

-- Park every send already queued in this database so the claim assertions below see only our fixture.
update public.communication_outbox_events set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, sender_id, reply_alias_id
) values
  ('e9700000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'closure-preview-queued-1', 'customer@closure-preview.example', 'Queued subject',
   '<p>queued</p>', 'queued', 'e9500000-0000-0000-0000-000000000001',
   'e9600000-0000-0000-0000-000000000001'),
  ('e9700000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'closure-preview-parked-1', 'customer@closure-preview.example', 'Parked subject',
   '<p>parked</p>', 'parked', 'e9500000-0000-0000-0000-000000000001',
   'e9600000-0000-0000-0000-000000000001'),
  ('e9700000-0000-0000-0000-000000000003', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'closure-preview-done-1', 'customer@closure-preview.example', 'Delivered subject',
   '<p>done</p>', 'done', 'e9500000-0000-0000-0000-000000000001',
   'e9600000-0000-0000-0000-000000000001');

insert into public.communication_outbox_events (
  id, organization_id, delivery_intent_id, available_at, status
) values
  ('e9800000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
   'e9700000-0000-0000-0000-000000000001', now() - interval '1 minute', 'pending'),
  -- Parked for manual sender review: unsent mail the owner would still lose.
  ('e9800000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000001',
   'e9700000-0000-0000-0000-000000000002', 'infinity'::timestamptz, 'failed'),
  -- Finished with, so it is not part of the impact.
  ('e9800000-0000-0000-0000-000000000003', 'e9100000-0000-0000-0000-000000000001',
   'e9700000-0000-0000-0000-000000000003', now() - interval '1 day', 'submitted');

-- A reply from before the closure window opened. The preview counts what arrived during the window,
-- so this one must not be included.
insert into public.communication_inbound_messages (
  id, organization_id, reply_alias_id, client_id, client_contact_method_id, sender_id,
  provider_message_id, sender_email, subject, text_content, message_kind, review_status, created_at
) values (
  'e9900000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
  'e9600000-0000-0000-0000-000000000001', 'e9200000-0000-0000-0000-000000000001',
  'e9300000-0000-0000-0000-000000000001', 'e9500000-0000-0000-0000-000000000001',
  'closure-preview-old-reply', 'customer@closure-preview.example', 'Older reply', 'older reply',
  'reply', 'accepted', now() - interval '10 days'
);

-- ------------------------------------------------------------------------------------------------
-- Start the real 30-day window through the owner command, not by hand.
-- ------------------------------------------------------------------------------------------------

select ok(
  (public.apply_organization_closure_start(
    'e9100000-0000-0000-0000-000000000001', 'closure-preview-start-8300',
    'Owner asked to close the account.', 'jafar@example.com') ->> 'applied')::boolean,
  'the closure command opens the 30-day window'
);

select is(
  (select lifecycle_status from public.organizations
   where id = 'e9100000-0000-0000-0000-000000000001'),
  'pending_closure',
  'the organization is blocked for the duration of the window'
);

-- ------------------------------------------------------------------------------------------------
-- Inbound routing and the provider resources behind it survive the window.
-- ------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.communication_reply_aliases
   where organization_id = 'e9100000-0000-0000-0000-000000000001'),
  2,
  'closure removes none of the organization''s reply aliases'
);

select ok(
  (select lifecycle_state = 'verified' and provider_verified
   from public.communication_email_domains
   where id = 'e9400000-0000-0000-0000-000000000002'),
  'the verified receiving domain and its provider resources are left in place'
);

select is(
  (select review_status from public.record_communication_inbound_message(
    target_provider_message_id => 'closure-preview-window-reply',
    target_sender_email => 'customer@closure-preview.example',
    target_to_recipients => jsonb_build_array('live-alias-8300@reply.closure-preview.example'),
    target_cc_recipients => '[]'::jsonb,
    target_subject => 'Reply during closure',
    target_text_content => 'still here',
    target_message_kind => 'reply',
    target_candidate_recipients => jsonb_build_array(jsonb_build_object(
      'local_part', 'live-alias-8300', 'domain_name', 'reply.closure-preview.example'))
  )),
  'accepted',
  'a customer reply arriving mid-closure still resolves onto its conversation'
);

select is(
  (select organization_id from public.communication_inbound_messages
   where provider_message_id = 'closure-preview-window-reply'),
  'e9100000-0000-0000-0000-000000000001'::uuid,
  'the mid-closure reply is routed to the closing organization, not dropped'
);

-- Outbound is the one thing that does stop (Part 8.1), and it stops without cancelling.
select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'the claim hands out nothing while the window is open'
);

select is(
  (select failure_code from public.communication_delivery_intents
   where id = 'e9700000-0000-0000-0000-000000000001'),
  'organization_closing',
  'the queued send is held for closure, not cancelled'
);

-- ------------------------------------------------------------------------------------------------
-- The early-deletion impact preview.
-- ------------------------------------------------------------------------------------------------

select is(
  (public.preview_organization_closure_impact(
    'e9100000-0000-0000-0000-000000000001') ->> 'active_reply_aliases')::int,
  1,
  'the preview counts only aliases that can still route, not the lapsed one'
);

select is(
  (public.preview_organization_closure_impact(
    'e9100000-0000-0000-0000-000000000001') ->> 'queued_messages')::int,
  2,
  'the preview counts unfinished mail, including a send parked for review, and not a submitted one'
);

select is(
  (public.preview_organization_closure_impact(
    'e9100000-0000-0000-0000-000000000001') ->> 'recent_replies')::int,
  1,
  'the preview counts replies received since closure started, not older history'
);

select ok(
  (public.preview_organization_closure_impact(
    'e9100000-0000-0000-0000-000000000001') ->> 'closure_record_id') is not null,
  'the preview names the open window it would cut short'
);

select ok(
  ((public.preview_organization_closure_impact(
    'e9100000-0000-0000-0000-000000000001') ->> 'closure_deadline_at')::timestamptz
    > now() + interval '29 days'),
  'the preview carries the window deadline the owner would be skipping'
);

select is(
  (public.preview_organization_closure_impact(
    'e9100000-0000-0000-0000-000000000002') ->> 'active_reply_aliases')::int,
  0,
  'the preview is scoped to one organization and reports nothing for an untouched one'
);

select throws_ok(
  $$select public.preview_organization_closure_impact('e9100000-0000-0000-0000-0000000000ff')$$,
  '23503',
  'Organization was not found.',
  'the preview refuses an organization that does not exist'
);

-- ------------------------------------------------------------------------------------------------
-- Restore re-opens sending.
-- ------------------------------------------------------------------------------------------------

select public.apply_organization_closure_restore(
  'e9100000-0000-0000-0000-000000000001', 'closure-preview-restore-8300',
  'Owner changed their mind.', 'jafar@example.com');

update public.communication_outbox_events set available_at = now() - interval '1 minute'
where id = 'e9800000-0000-0000-0000-000000000001';

select public.claim_communication_outbox_event();

select isnt(
  coalesce((select failure_code from public.communication_delivery_intents
   where id = 'e9700000-0000-0000-0000-000000000001'), 'none'),
  'organization_closing',
  'restore lifts the closure hold and the send is considered again'
);

select * from finish();
rollback;
