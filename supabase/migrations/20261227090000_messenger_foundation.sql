-- Messenger Part 3 (docs/messenger-behavior-contract.md, docs/messenger-implementation-plan.md § Database): the
-- tables Facebook Messenger needs before a Page can be connected or a message received. GoHighLevel's model:
-- a business connects its Facebook Page, and each person who messages that Page is one continuous thread under a
-- client or lead.
--
-- 1. Connected Pages. One row per Page per business. The Page's access key is stored only as AES-256-GCM
--    ciphertext (same envelope as Stripe and Twilio keys) and is wiped on disconnect. Reconnecting the same Page
--    reuses the same row, so old conversations stay and the same threads resume (Jafar, 2026-10-23).
-- 2. Messenger people. One row per person per Page (Meta's Page-scoped ID), always linked to a client or lead.
--    Someone new becomes a new lead; nobody is ever matched by name (Jafar, 2026-10-23). The last time they wrote
--    decides Meta's 24-hour reply window.
-- 3. Raw webhook deliveries, saved before any processing so nothing Meta sends is lost if processing fails.
-- 4. Received messages: the inbox's inbound table now accepts Messenger, tied to the person instead of a phone or
--    email. Meta's message ID keeps a repeated delivery from becoming a second message.
-- 5. Recording a received message: finds or creates the person and their lead, then saves the message once.
-- 6. Merging two clients carries their Messenger people to the survivor.
--
-- Sending (delivery intents, outbox) widens in Part 7 together with the send path that uses it.
-- No browser reads these tables: row level security is on with no policies. The server checks who is asking.

-- 1. Connected Pages ------------------------------------------------------------------------------------------

create table public.communication_messenger_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Meta's numeric Page ID, the key every webhook entry carries.
  page_id text not null,
  page_name text not null,
  -- active: receiving and replying. needs_reconnect: Meta stopped accepting the key or the subscription; the
  -- business must log in again. disconnected: the business switched it off; history stays, the key is gone.
  status text not null default 'active',
  needs_reconnect_reason text,
  -- The Page new Messenger conversations start from when a business has several.
  is_default boolean not null default false,
  encryption_key_id text,
  page_token_nonce bytea,
  page_token_ciphertext bytea,
  page_token_tag bytea,
  connected_by uuid references auth.users(id) on delete set null,
  connected_at timestamptz not null default now(),
  disconnected_at timestamptz,
  last_checked_at timestamptz,
  last_event_received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_messenger_connections_org_id_key unique (organization_id, id),
  -- Reconnecting a Page this business had before revives that row and its threads.
  constraint communication_messenger_connections_org_page_key unique (organization_id, page_id),
  constraint communication_messenger_connections_page_id_check check (page_id ~ '^[0-9]{1,32}$'),
  constraint communication_messenger_connections_page_name_check
    check (char_length(btrim(page_name)) between 1 and 200),
  constraint communication_messenger_connections_status_check
    check (status in ('active', 'needs_reconnect', 'disconnected')),
  constraint communication_messenger_connections_reason_check check (
    (status = 'needs_reconnect') = (needs_reconnect_reason is not null)
    and (needs_reconnect_reason is null
      or needs_reconnect_reason in ('token_invalid', 'permission_missing', 'webhook_unsubscribed'))
  ),
  constraint communication_messenger_connections_default_check
    check (not is_default or status <> 'disconnected'),
  -- A connected Page always has its key; a disconnected one never keeps it.
  constraint communication_messenger_connections_token_check check (
    case when status = 'disconnected' then
      encryption_key_id is null and page_token_nonce is null and page_token_ciphertext is null
        and page_token_tag is null
    else
      encryption_key_id ~ '^[A-Za-z0-9._-]{1,64}$'
        and octet_length(page_token_nonce) = 12
        and octet_length(page_token_ciphertext) > 0
        and octet_length(page_token_tag) = 16
    end
  ),
  constraint communication_messenger_connections_disconnected_check
    check ((status = 'disconnected') = (disconnected_at is not null))
);

comment on table public.communication_messenger_connections is
  'Server-owned Facebook Page connection. AES-256-GCM ciphertext only; a plaintext Page token must never enter Postgres.';

-- A Page feeds one business at a time, so a webhook entry always has one owner.
create unique index communication_messenger_connections_live_page_idx
  on public.communication_messenger_connections (page_id)
  where status <> 'disconnected';

create unique index communication_messenger_connections_one_default_idx
  on public.communication_messenger_connections (organization_id)
  where is_default;

create index communication_messenger_connections_connected_by_idx
  on public.communication_messenger_connections (connected_by)
  where connected_by is not null;

-- 2. Messenger people -----------------------------------------------------------------------------------------

create table public.communication_messenger_identities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  connection_id uuid not null,
  -- Meta's Page-scoped ID for this person: the same person has a different one on every Page.
  psid text not null,
  -- Filled only once Meta allows reading profile names; until then the lead shows as "Facebook user".
  display_name text,
  client_id uuid not null,
  -- When this person last wrote. Replies are allowed for 24 hours after it (Meta's window).
  last_inbound_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_messenger_identities_org_id_key unique (organization_id, id),
  constraint communication_messenger_identities_connection_psid_key unique (connection_id, psid),
  constraint communication_messenger_identities_connection_fkey
    foreign key (organization_id, connection_id)
    references public.communication_messenger_connections (organization_id, id) on delete cascade,
  -- Restrict: merging clients moves these first, and deleting a client must not silently lose a thread.
  constraint communication_messenger_identities_client_fkey
    foreign key (organization_id, client_id)
    references public.clients (organization_id, id) on delete restrict,
  constraint communication_messenger_identities_psid_check check (psid ~ '^[0-9]{1,32}$'),
  constraint communication_messenger_identities_display_name_check
    check (display_name is null or char_length(btrim(display_name)) between 1 and 200)
);

create index communication_messenger_identities_org_client_idx
  on public.communication_messenger_identities (organization_id, client_id);

-- 3. Raw webhook deliveries -----------------------------------------------------------------------------------

create table public.communication_messenger_webhook_events (
  id uuid primary key default gen_random_uuid(),
  -- SHA-256 of the exact bytes Meta signed. Meta resends the same bytes when it retries, so a retry is one row.
  body_sha256 bytea not null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  claim_token uuid,
  claimed_at timestamptz,
  processing_attempts integer not null default 0,
  processing_error text,
  processed_at timestamptz,
  constraint communication_messenger_webhook_events_body_key unique (body_sha256),
  constraint communication_messenger_webhook_events_sha_check check (octet_length(body_sha256) = 32),
  -- The route refuses bigger bodies before saving; this is the backstop.
  constraint communication_messenger_webhook_events_payload_check
    check (jsonb_typeof(payload) = 'object' and pg_column_size(payload) <= 1048576),
  constraint communication_messenger_webhook_events_claim_check
    check ((claim_token is null) = (claimed_at is null)),
  constraint communication_messenger_webhook_events_attempts_check check (processing_attempts >= 0),
  constraint communication_messenger_webhook_events_error_check
    check (processing_error is null or char_length(processing_error) <= 4000)
);

create index communication_messenger_webhook_events_pending_idx
  on public.communication_messenger_webhook_events (received_at)
  where processed_at is null;

alter table public.communication_messenger_connections enable row level security;
alter table public.communication_messenger_identities enable row level security;
alter table public.communication_messenger_webhook_events enable row level security;

revoke all on table public.communication_messenger_connections from public, anon, authenticated;
revoke all on table public.communication_messenger_identities from public, anon, authenticated;
revoke all on table public.communication_messenger_webhook_events from public, anon, authenticated;
grant select, insert, update, delete on table public.communication_messenger_connections to service_role;
grant select, insert, update, delete on table public.communication_messenger_identities to service_role;
grant select, insert, update, delete on table public.communication_messenger_webhook_events to service_role;

-- 4. Received messages ----------------------------------------------------------------------------------------

alter table public.communication_inbound_messages
  add column messenger_identity_id uuid,
  add constraint communication_inbound_messages_messenger_identity_fkey
    foreign key (organization_id, messenger_identity_id)
    references public.communication_messenger_identities (organization_id, id) on delete restrict;

create index communication_inbound_messages_messenger_identity_idx
  on public.communication_inbound_messages (messenger_identity_id)
  where messenger_identity_id is not null;

alter table public.communication_inbound_messages
  drop constraint communication_inbound_messages_channel_check,
  add constraint communication_inbound_messages_channel_check
    check (channel in ('email', 'sms', 'messenger')),
  drop constraint communication_inbound_messages_channel_provider_check,
  add constraint communication_inbound_messages_channel_provider_check check (
    (channel = 'email' and provider = 'ses')
    or (channel = 'sms' and provider = 'twilio')
    or (channel = 'messenger' and provider = 'meta')
  ),
  drop constraint communication_inbound_messages_channel_sender_check,
  add constraint communication_inbound_messages_channel_sender_check check (
    (channel = 'email' and sender_email is not null)
    or (channel = 'sms' and sender_phone is not null and char_length(btrim(sender_phone)) between 3 and 20)
    or (channel = 'messenger' and messenger_identity_id is not null and sender_email is null
      and sender_phone is null)
  ),
  -- A Messenger message is always settled at once: its person and their client or lead exist before it is saved.
  drop constraint communication_inbound_messages_resolution_complete,
  add constraint communication_inbound_messages_resolution_complete check (
    (channel = 'email' and messenger_identity_id is null and (
      (client_id is null and client_contact_method_id is null and sender_id is null)
      or (client_id is not null and client_contact_method_id is not null and sender_id is not null)))
    or (channel = 'sms' and messenger_identity_id is null and sender_id is null and (
      (client_id is null and client_contact_method_id is null)
      or (client_id is not null and client_contact_method_id is not null)))
    or (channel = 'messenger' and sender_id is null and client_contact_method_id is null
      and client_id is not null and messenger_identity_id is not null)
  );

-- 5. Recording a received message -----------------------------------------------------------------------------

create function public.record_communication_messenger_inbound_message(
  target_connection_id uuid,
  target_psid text,
  target_mid text,
  target_text text,
  target_attachment_count integer,
  target_sent_at timestamptz
)
returns public.communication_inbound_messages
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  connection_row public.communication_messenger_connections;
  identity_row public.communication_messenger_identities;
  new_client_id uuid;
  -- Meta's own time orders the thread (retries can arrive out of order), never later than now.
  message_at timestamptz := least(coalesce(target_sent_at, now()), now());
  inserted_row public.communication_inbound_messages;
begin
  if target_psid is null or target_mid is null or btrim(target_mid) = '' then
    return null;
  end if;

  select * into connection_row
  from public.communication_messenger_connections
  where id = target_connection_id;

  -- A switched-off Page keeps its history but takes nothing new.
  if connection_row.id is null or connection_row.status = 'disconnected' then
    return null;
  end if;

  select * into identity_row
  from public.communication_messenger_identities
  where connection_id = connection_row.id and psid = target_psid
  for update;

  -- Someone new, or someone whose client was deleted: a new lead, exactly like an unmatched text. Never matched
  -- by name. Two first messages from the same person can race here; the (connection, psid) key is the
  -- tiebreaker, and the loser discards its own just-created lead.
  if identity_row.id is null or exists (
    select 1 from public.clients
    where organization_id = connection_row.organization_id and id = identity_row.client_id
      and deleted_at is not null
  ) then
    insert into public.clients (organization_id, display_name, lifecycle_status, lead_source, client_type)
    values (connection_row.organization_id, 'Facebook user', 'lead', 'Facebook Messenger', 'person')
    returning id into new_client_id;

    if identity_row.id is null then
      insert into public.communication_messenger_identities (organization_id, connection_id, psid, client_id)
      values (connection_row.organization_id, connection_row.id, target_psid, new_client_id)
      on conflict (connection_id, psid) do nothing
      returning * into identity_row;

      if identity_row.id is null then
        delete from public.clients where organization_id = connection_row.organization_id and id = new_client_id;
        select * into identity_row
        from public.communication_messenger_identities
        where connection_id = connection_row.id and psid = target_psid
        for update;
      end if;
    else
      update public.communication_messenger_identities
      set client_id = new_client_id, updated_at = now()
      where id = identity_row.id
      returning * into identity_row;
    end if;
  end if;

  insert into public.communication_inbound_messages (
    organization_id, channel, client_id, messenger_identity_id, provider, provider_message_id,
    subject, text_content, attachment_count, message_kind, review_status, created_at
  ) values (
    connection_row.organization_id, 'messenger', identity_row.client_id, identity_row.id, 'meta', target_mid,
    '', coalesce(target_text, ''), coalesce(target_attachment_count, 0), 'reply', 'accepted', message_at
  )
  on conflict (provider, provider_message_id) where provider_message_id is not null do nothing
  returning * into inserted_row;

  if inserted_row.id is not null then
    update public.communication_messenger_identities
    set last_inbound_at = greatest(coalesce(last_inbound_at, message_at), message_at), updated_at = now()
    where id = identity_row.id;

    update public.communication_messenger_connections
    set last_event_received_at = now(), updated_at = now()
    where id = connection_row.id;
  end if;

  return inserted_row;
end;
$$;

revoke all on function public.record_communication_messenger_inbound_message(uuid, text, text, text, integer, timestamptz)
  from public, anon, authenticated;
grant execute on function public.record_communication_messenger_inbound_message(uuid, text, text, text, integer, timestamptz)
  to service_role;

-- 6. Merging two clients --------------------------------------------------------------------------------------
-- Unchanged from the live definition except for the Messenger line under "Conversations".

CREATE OR REPLACE FUNCTION public.merge_clients(p_primary_client_id uuid, p_secondary_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  loaded record;
  primary_row public.clients;
  secondary_row public.clients;
  org uuid;
  p uuid;
  s uuid;
  plan jsonb;
  snapshot jsonb;
  primary_prefs public.client_communication_preferences;
  secondary_prefs public.client_communication_preferences;
  primary_opted_out boolean;
  secondary_opted_out boolean;
  merge_id uuid;
begin
  select * into loaded from private.load_clients_for_merge(p_primary_client_id, p_secondary_client_id, true);
  primary_row := loaded.primary_row;
  secondary_row := loaded.secondary_row;
  org := primary_row.organization_id;
  p := primary_row.id;
  s := secondary_row.id;

  -- Hold any card checkout still settling for either client, then ask the plan under that lock, so a payment
  -- cannot start landing between the check and the move.
  perform 1 from public.payment_stripe_checkouts
  where organization_id = org and client_id in (p, s)
  for update;

  plan := private.client_merge_plan(primary_row, secondary_row);
  if jsonb_array_length(plan -> 'blockers') > 0 then
    raise exception 'These clients cannot be merged: %',
      (select string_agg(item ->> 'label', ' ') from jsonb_array_elements(plan -> 'blockers') as item)
      using errcode = 'check_violation';
  end if;

  -- Who the duplicate was, kept forever on the merge record.
  select jsonb_build_object(
    'display_name', secondary_row.display_name,
    'first_name', secondary_row.first_name,
    'last_name', secondary_row.last_name,
    'company_name', secondary_row.company_name,
    'client_type', secondary_row.client_type,
    'lifecycle_status', secondary_row.lifecycle_status,
    'lead_source', secondary_row.lead_source,
    'created_at', secondary_row.created_at,
    'contact_methods', coalesce((
      select jsonb_agg(jsonb_build_object('kind', kind, 'value', value, 'label', label) order by kind, created_at)
      from public.client_contact_methods where organization_id = org and client_id = s
    ), '[]'::jsonb),
    'properties', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'address_line1', address_line1, 'city', city, 'postal_code', postal_code) order by created_at)
      from public.properties where organization_id = org and client_id = s
    ), '[]'::jsonb)
  ) into snapshot;

  perform set_config('app.client_merge_in_progress', 'true', true);
  set constraints
    public.client_marketing_consent_events_method_fk,
    public.client_marketing_unsubscribe_links_method_fk,
    public.communication_sms_consent_events_method_fk,
    public.invoice_payment_allocations_payment_fk
    deferred;

  -- The client row: the primary's values win; a blank on the primary is filled from the secondary.
  update public.clients as c set
    first_name = coalesce(c.first_name, secondary_row.first_name),
    last_name = coalesce(c.last_name, secondary_row.last_name),
    company_name = coalesce(c.company_name, secondary_row.company_name),
    lead_source = coalesce(c.lead_source, secondary_row.lead_source),
    lead_temperature = coalesce(c.lead_temperature, secondary_row.lead_temperature),
    next_follow_up_at = coalesce(c.next_follow_up_at, secondary_row.next_follow_up_at),
    billing_payment_term_id = coalesce(c.billing_payment_term_id, secondary_row.billing_payment_term_id),
    -- Once either was a customer, the merged client is one, dated from the earlier conversion.
    lifecycle_status = case when secondary_row.lifecycle_status = 'customer' then 'customer' else c.lifecycle_status end,
    converted_to_customer_at = case
      when c.converted_to_customer_at is null then secondary_row.converted_to_customer_at
      when secondary_row.converted_to_customer_at is null then c.converted_to_customer_at
      else least(c.converted_to_customer_at, secondary_row.converted_to_customer_at)
    end,
    -- Stays archived only if both were: live work from the secondary brings the survivor back, as new work does.
    archived_at = case when secondary_row.archived_at is null then null else c.archived_at end,
    -- The billing address is one whole address, so it is taken whole or not at all.
    billing_address_line1 = case when c.billing_address_line1 is null then secondary_row.billing_address_line1 else c.billing_address_line1 end,
    billing_address_line2 = case when c.billing_address_line1 is null then secondary_row.billing_address_line2 else c.billing_address_line2 end,
    billing_city = case when c.billing_address_line1 is null then secondary_row.billing_city else c.billing_city end,
    billing_state_region = case when c.billing_address_line1 is null then secondary_row.billing_state_region else c.billing_state_region end,
    billing_postal_code = case when c.billing_address_line1 is null then secondary_row.billing_postal_code else c.billing_postal_code end,
    billing_country = case when c.billing_address_line1 is null then secondary_row.billing_country else c.billing_country end
  where c.id = p;

  -- Preferences: any "stop" on either record survives (Jafar, 2026-09-28).
  select * into primary_prefs from public.client_communication_preferences where organization_id = org and client_id = p;
  select * into secondary_prefs from public.client_communication_preferences where organization_id = org and client_id = s;
  primary_opted_out := primary_prefs.sms_opt_out_at is not null
    and (primary_prefs.sms_opt_in_at is null or primary_prefs.sms_opt_in_at < primary_prefs.sms_opt_out_at);
  secondary_opted_out := secondary_prefs.sms_opt_out_at is not null
    and (secondary_prefs.sms_opt_in_at is null or secondary_prefs.sms_opt_in_at < secondary_prefs.sms_opt_out_at);

  if secondary_prefs.client_id is not null then
    update public.client_communication_preferences as pref set
      appointment_reminders = pref.appointment_reminders and secondary_prefs.appointment_reminders,
      quote_follow_ups = pref.quote_follow_ups and secondary_prefs.quote_follow_ups,
      invoice_reminders = pref.invoice_reminders and secondary_prefs.invoice_reminders,
      job_follow_ups = pref.job_follow_ups and secondary_prefs.job_follow_ups,
      review_requests = pref.review_requests and secondary_prefs.review_requests,
      contact_policy = case
        when array_position(array['allow', 'no_marketing', 'do_not_disturb'], secondary_prefs.contact_policy)
           > array_position(array['allow', 'no_marketing', 'do_not_disturb'], pref.contact_policy)
        then secondary_prefs.contact_policy else pref.contact_policy end,
      sms_opt_out_at = case when secondary_opted_out and not primary_opted_out then secondary_prefs.sms_opt_out_at else pref.sms_opt_out_at end,
      sms_opt_in_at = case when secondary_opted_out and not primary_opted_out then secondary_prefs.sms_opt_in_at else pref.sms_opt_in_at end,
      opt_out_source = case when secondary_opted_out and not primary_opted_out then secondary_prefs.opt_out_source else pref.opt_out_source end
    where pref.organization_id = org and pref.client_id = p;
  end if;

  -- Contact people and their phones and emails. The survivor keeps its own primary and billing choices.
  update public.client_contacts set
    client_id = p,
    is_primary = is_primary and not exists (
      select 1 from public.client_contacts where organization_id = org and client_id = p and is_primary)
  where organization_id = org and client_id = s;

  update public.client_contact_methods as method set
    client_id = p,
    is_primary = method.is_primary and not exists (
      select 1 from public.client_contact_methods as mine
      where mine.organization_id = org and mine.client_id = p and mine.kind = method.kind and mine.is_primary),
    is_billing_contact = method.is_billing_contact and not exists (
      select 1 from public.client_contact_methods as mine
      where mine.organization_id = org and mine.client_id = p and mine.is_billing_contact)
  where method.organization_id = org and method.client_id = s;

  update public.client_marketing_consent_events set client_id = p where organization_id = org and client_id = s;
  update public.client_marketing_consent_state set client_id = p where organization_id = org and client_id = s;
  update public.client_marketing_unsubscribe_links set client_id = p where organization_id = org and client_id = s;
  update public.communication_sms_consent_events set client_id = p where organization_id = org and client_id = s;

  -- Properties. The primary-property row moves on its own first: a non-primary row arriving at a client with no
  -- properties would otherwise be promoted by properties_set_first_primary and collide with it.
  update public.properties set
    client_id = p,
    is_primary = not exists (
      select 1 from public.properties where organization_id = org and client_id = p and deleted_at is null),
    is_billing_address = is_billing_address and not exists (
      select 1 from public.properties where organization_id = org and client_id = p and is_billing_address)
  where organization_id = org and client_id = s and is_primary;

  update public.properties set
    client_id = p,
    is_primary = false,
    is_billing_address = is_billing_address and not exists (
      select 1 from public.properties where organization_id = org and client_id = p and is_billing_address)
  where organization_id = org and client_id = s;

  -- Work and money. Only the client link changes; numbers, statuses and frozen documents stay as they were.
  update public.requests set client_id = p where organization_id = org and client_id = s;
  update public.opportunities set client_id = p where organization_id = org and client_id = s;
  update public.quotes set client_id = p where organization_id = org and client_id = s;
  update public.jobs set client_id = p where organization_id = org and client_id = s;
  update public.invoices set client_id = p where organization_id = org and client_id = s;
  update public.invoice_sources set client_id = p where organization_id = org and client_id = s;
  update public.invoice_events set client_id = p where organization_id = org and client_id = s;
  update public.client_payment_events set client_id = p where organization_id = org and client_id = s;
  update public.invoice_payment_allocations set client_id = p where organization_id = org and client_id = s;
  update public.client_opening_balances set client_id = p where organization_id = org and client_id = s;
  update public.payment_stripe_checkouts set client_id = p where organization_id = org and client_id = s;

  -- Conversations: the two threads become one.
  update public.communication_delivery_intents set client_id = p where organization_id = org and client_id = s;
  update public.communication_inbound_messages set client_id = p where organization_id = org and client_id = s;
  -- Messenger people move before their messages' client is deleted: the client link restricts deletion.
  update public.communication_messenger_identities set client_id = p where organization_id = org and client_id = s;
  update public.communication_reply_aliases set client_id = p where organization_id = org and client_id = s;
  update public.communication_forward_events set client_id = p where organization_id = org and client_id = s;
  update public.website_chat_sessions set client_id = p where organization_id = org and client_id = s;
  update public.website_chat_sessions set candidate_client_id_by_phone = p
    where organization_id = org and candidate_client_id_by_phone = s;
  update public.website_chat_sessions set candidate_client_id_by_email = p
    where organization_id = org and candidate_client_id_by_email = s;
  update public.website_chat_messages set client_id = p where organization_id = org and client_id = s;

  -- One assignee per conversation: the survivor's stands; the secondary's is used only if it had none.
  update public.communication_conversation_assignments set client_id = p
  where organization_id = org and client_id = s
    and not exists (select 1 from public.communication_conversation_assignments where organization_id = org and client_id = p);
  -- Followers combine.
  insert into public.communication_conversation_followers (organization_id, client_id, user_id, followed_at)
  select organization_id, p, user_id, followed_at
  from public.communication_conversation_followers where organization_id = org and client_id = s
  on conflict do nothing;
  -- Read position: the earlier one, so a teammate still sees the other thread's messages they had not read.
  insert into public.communication_conversation_read_marks (organization_id, user_id, client_id, last_read_at, created_at, updated_at)
  select organization_id, user_id, p, last_read_at, created_at, now()
  from public.communication_conversation_read_marks where organization_id = org and client_id = s
  on conflict (organization_id, user_id, client_id)
  do update set last_read_at = least(communication_conversation_read_marks.last_read_at, excluded.last_read_at),
    updated_at = now();
  -- The secondary's leftover rows in these three go with it (they cascade).

  -- Marketing sends: both duplicates may have received one campaign; both send records are kept.
  update public.marketing_campaign_recipients set
    client_id = p,
    merged_from_client_id = coalesce(merged_from_client_id, s)
  where organization_id = org and client_id = s;
  update public.marketing_campaign_result_credits set client_id = p where organization_id = org and client_id = s;

  update public.file_shares set client_id = p where organization_id = org and client_id = s;
  update public.review_requests set client_id = p where organization_id = org and client_id = s;
  update public.import_rows set match_client_id = p where organization_id = org and match_client_id = s;
  update public.import_rows set result_client_id = p where organization_id = org and result_client_id = s;

  -- Notes, files, tags and history point at the client by type and id. Tags and note links combine without
  -- repeating one the survivor already has.
  update public.note_links as link set entity_id = p
  where link.organization_id = org and link.entity_type = 'client' and link.entity_id = s
    and not exists (
      select 1 from public.note_links as mine
      where mine.note_id = link.note_id and mine.entity_type = 'client' and mine.entity_id = p);
  delete from public.note_links where organization_id = org and entity_type = 'client' and entity_id = s;

  update public.tag_assignments as tag set entity_id = p
  where tag.organization_id = org and tag.entity_type = 'client' and tag.entity_id = s
    and not exists (
      select 1 from public.tag_assignments as mine
      where mine.tag_id = tag.tag_id and mine.entity_type = 'client' and mine.entity_id = p);
  delete from public.tag_assignments where organization_id = org and entity_type = 'client' and entity_id = s;

  update public.file_links as link set entity_id = p
  where link.organization_id = org and link.entity_type = 'client' and link.entity_id = s
    and not exists (
      select 1 from public.file_links as mine
      where mine.file_id = link.file_id and mine.entity_type = 'client' and mine.entity_id = p and mine.role = link.role);
  -- A leftover is the same file already on the survivor in the same role, so removing it loses nothing.
  delete from public.file_links where organization_id = org and entity_type = 'client' and entity_id = s;

  update public.attachments set entity_id = p where organization_id = org and entity_type = 'client' and entity_id = s;
  update public.files set origin_id = p where organization_id = org and origin_type = 'client' and origin_id = s;
  update public.activity_events set entity_id = p where organization_id = org and entity_type = 'client' and entity_id = s;

  -- An earlier merge into the secondary now leads to the survivor too.
  update public.client_merges set surviving_client_id = p where organization_id = org and surviving_client_id = s;

  insert into public.client_merges (organization_id, surviving_client_id, merged_client_id, merged_client_snapshot, moved, merged_by)
  values (org, p, s, snapshot, plan -> 'moves', (select auth.uid()))
  returning id into merge_id;

  insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata)
  values (org, 'client', p, 'client_merged',
    left('Merged in "' || secondary_row.display_name || '".', 280),
    (select auth.uid()),
    jsonb_build_object('merge_id', merge_id, 'merged_client_id', s, 'merged_display_name', secondary_row.display_name,
      'moved', plan -> 'moves'));

  -- Everything that matters has moved. Whatever still points at the secondary is its own duplicate bookkeeping
  -- (preferences, a second assignee, follower and read rows) and cascades away; a RESTRICT key still pointing
  -- here would mean a table this merge does not know about, and fails the whole merge rather than lose it.
  delete from public.clients where id = s;

  perform set_config('app.client_merge_in_progress', 'false', true);

  return jsonb_build_object('merge_id', merge_id, 'surviving_client_id', p);
end;
$function$;
