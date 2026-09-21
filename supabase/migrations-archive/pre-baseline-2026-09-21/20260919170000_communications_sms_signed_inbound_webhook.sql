-- Communications A2 Stage 5B: signed Twilio SMS inbound webhook.
--
-- communication_inbound_messages was email-only (NOT NULL sender_email, provider default 'brevo', no
-- channel column). SMS in Conversations (plan §6) extends this same table rather than forking a second
-- one -- GoHighLevel's public Conversations API stores every inbound channel as one row tagged by type,
-- and our own outbound side already shares one core table (communication_delivery_intents) across
-- channels with per-channel extras split out. This migration generalizes the inbound table the same way
-- (Jafar approved 2026-09-15, "do what jobber/ghl does").
--
-- Identity resolution mirrors the established pattern in accept_website_chat_first_message: normalize the
-- number and match it against client_contact_methods, creating a new Lead when nobody matches.
-- client_contact_methods_org_value_unique_idx (organization_id, kind, normalized_value) means phone-only
-- matching can never be ambiguous the way Website Chat's phone+email cross-check can, so there is no
-- "several matches" branch here. STOP, START and HELP reuse the same resolution so an unresolved or
-- brand-new sender is still protected, then separately record consent evidence for that resolved contact
-- method (docs/research/communications-a2-stage3-transport-webhooks.md).

alter table public.communication_inbound_messages
  add column channel text not null default 'email',
  add column sender_phone text;

alter table public.communication_inbound_messages
  alter column sender_email drop not null;

alter table public.communication_inbound_messages
  add constraint communication_inbound_messages_channel_check
    check (channel in ('email', 'sms')),
  add constraint communication_inbound_messages_channel_provider_check
    check (
      (channel = 'email' and provider = 'brevo')
      or (channel = 'sms' and provider = 'twilio')
    ),
  add constraint communication_inbound_messages_channel_sender_check
    check (
      (channel = 'email' and sender_email is not null)
      or (channel = 'sms' and sender_phone is not null
          and char_length(btrim(sender_phone)) between 3 and 20)
    );

-- communication_inbound_messages_resolution_complete assumed every resolved conversation carries a
-- communication_email_senders row (sender_id) -- true for email's reply-alias model, meaningless for SMS,
-- which has no equivalent "authorized mailbox" concept. Replace it with a channel-aware version: email
-- keeps the original all-three-or-none rule; sms only ever pairs client_id with client_contact_method_id
-- and never sets sender_id.
alter table public.communication_inbound_messages
  drop constraint communication_inbound_messages_resolution_complete;
alter table public.communication_inbound_messages
  add constraint communication_inbound_messages_resolution_complete check (
    (channel = 'email' and (
      (client_id is null and client_contact_method_id is null and sender_id is null)
      or (client_id is not null and client_contact_method_id is not null and sender_id is not null)
    ))
    or (channel = 'sms' and sender_id is null and (
      (client_id is null and client_contact_method_id is null)
      or (client_id is not null and client_contact_method_id is not null)
    ))
  );

comment on column public.communication_inbound_messages.channel is
  'email or sms. Determines which of sender_email/sender_phone is populated and which provider is valid.';
comment on column public.communication_inbound_messages.sender_phone is
  'Raw From number for an sms row (E.164 as Twilio sends it). Null for email.';

-- ---------------------------------------------------------------------------------------------------------------
-- Ordinary inbound SMS reply: resolve identity, insert the message. Mirrors
-- record_communication_inbound_message's shape (security definer, on-conflict dedupe by provider_message_id)
-- and accept_website_chat_first_message's contact-matching (distinct-client count against
-- client_contact_methods, scoped by org, kind and normalized value).
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.record_communication_sms_inbound_message(
  target_organization_id uuid,
  target_provider_message_id text,
  target_from_number text,
  target_body text,
  target_num_media integer
) returns public.communication_inbound_messages
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_from text := nullif(regexp_replace(coalesce(target_from_number, ''), '[^0-9]', '', 'g'), '');
  resolved_client_id uuid;
  resolved_method_id uuid;
  new_client_id uuid;
  inserted_row public.communication_inbound_messages;
begin
  if normalized_from is null then
    return null;
  end if;

  -- client_contact_methods_org_value_unique_idx (organization_id, kind, normalized_value) guarantees at
  -- most one client can hold this number in this org -- unlike Website Chat's phone+email cross-check,
  -- SMS has only one identifier, so there is no ambiguous-match case to branch on here.
  select method.id, method.client_id into resolved_method_id, resolved_client_id
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.kind = 'phone'
    and method.normalized_value = normalized_from
    and client.deleted_at is null;

  if resolved_method_id is null then
    -- Nobody matched: a new Lead, exactly like an unmatched Website Chat visitor. Two inbound texts from
    -- the same brand-new number can race here; client_contact_methods_org_value_unique_idx (organization,
    -- kind, normalized_value) is the tiebreaker. The loser discards its own just-created Lead and attaches
    -- to whichever contact method actually won, rather than erroring the whole request.
    insert into public.clients (
      organization_id, display_name, lifecycle_status, lead_source, client_type
    ) values (
      target_organization_id, target_from_number, 'lead', 'SMS', 'person'
    ) returning id into new_client_id;

    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (target_organization_id, new_client_id, 'phone', target_from_number, true)
    on conflict (organization_id, kind, normalized_value) do nothing
    returning id into resolved_method_id;

    if resolved_method_id is null then
      select method.id, method.client_id into resolved_method_id, resolved_client_id
      from public.client_contact_methods method
      where method.organization_id = target_organization_id
        and method.kind = 'phone'
        and method.normalized_value = normalized_from;
      delete from public.clients where organization_id = target_organization_id and id = new_client_id;
    else
      resolved_client_id := new_client_id;
    end if;
  end if;

  insert into public.communication_inbound_messages (
    organization_id, channel, client_id, client_contact_method_id, provider, provider_message_id,
    sender_phone, subject, text_content, attachment_count, message_kind, review_status
  ) values (
    target_organization_id, 'sms', resolved_client_id, resolved_method_id, 'twilio', target_provider_message_id,
    target_from_number, '', coalesce(target_body, ''), coalesce(target_num_media, 0), 'reply', 'accepted'
  )
  on conflict (provider, provider_message_id) where provider_message_id is not null do nothing
  returning * into inserted_row;

  return inserted_row;
end;
$$;

comment on function public.record_communication_sms_inbound_message(uuid, text, text, text, integer) is
  'Resolves an inbound SMS sender by normalized number (one match, or no match creating a new Lead) and '
  'records the message. Idempotent by (provider, provider_message_id).';

revoke all on function public.record_communication_sms_inbound_message(uuid, text, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.record_communication_sms_inbound_message(uuid, text, text, text, integer)
  to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- STOP/START/HELP evidence: records against whichever client_contact_methods row matches the sending number
-- in this tenant (the same one record_communication_sms_inbound_message resolves to). Silently does nothing
-- when nobody matches -- STOP from a number no client has on file has nothing to protect. Idempotent via the
-- table's existing unique(organization_id, source, source_event_key).
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.record_communication_sms_consent_event_from_reply(
  target_organization_id uuid,
  target_provider_message_id text,
  target_from_number text,
  target_event_kind text,
  target_confirmed_by_provider boolean
) returns public.communication_sms_consent_events
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_from text := nullif(regexp_replace(coalesce(target_from_number, ''), '[^0-9]', '', 'g'), '');
  method public.client_contact_methods;
  inserted_row public.communication_sms_consent_events;
begin
  if normalized_from is null or target_event_kind not in ('opt_in', 'opt_out', 'help_requested') then
    return null;
  end if;

  select cm.* into method
  from public.client_contact_methods cm
  join public.clients client
    on client.organization_id = cm.organization_id and client.id = cm.client_id
  where cm.organization_id = target_organization_id
    and cm.kind = 'phone'
    and cm.normalized_value = normalized_from
    and client.deleted_at is null;

  if method.id is null then
    return null;
  end if;

  insert into public.communication_sms_consent_events (
    organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
    subjects, proof_method, occurred_at
  ) values (
    target_organization_id, method.client_id, method.id, target_event_kind, 'client_reply',
    target_provider_message_id || ':' || method.id,
    case when target_event_kind = 'opt_in'
      then array['service', 'work_updates', 'billing_updates']
      else null end,
    case
      when target_event_kind = 'opt_in' then 'client_reply'
      when target_confirmed_by_provider then 'provider_keyword'
      else 'client_reply'
    end,
    now()
  )
  on conflict (organization_id, source, source_event_key) do nothing
  returning * into inserted_row;

  return inserted_row;
end;
$$;

comment on function public.record_communication_sms_consent_event_from_reply(uuid, text, text, text, boolean) is
  'Records one consent evidence row for whichever client_contact_methods row matches the sending number in '
  'this organization. No match means nothing to protect, so it does nothing.';

revoke all on function public.record_communication_sms_consent_event_from_reply(uuid, text, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.record_communication_sms_consent_event_from_reply(uuid, text, text, text, boolean)
  to service_role;
