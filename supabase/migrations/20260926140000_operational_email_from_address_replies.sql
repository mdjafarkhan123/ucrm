-- Operational email SES Part 4b step C: replies sent to the From address.
--
-- Some mail clients reply to From (office@mail.<root> / office@news.<root>) instead of the Reply-To alias
-- (RFC 5322 makes Reply-To advisory). Following GoHighLevel's dedicated-sending-domain pattern, the sending
-- subdomains now receive too (docs/contractor-email-contract.md, "Conversations and replies"). Until now the
-- resolver matched only purpose = 'receiving' domains, so such a reply returned NULL and was silently dropped.
--
-- Matching order, never guessed:
--   1. reply.<root> (the opaque alias): unchanged.
--   2. mail./news.<root>: the sent email it answers (In-Reply-To) -> its delivery intent's alias (the full alias
--      path, expiry included), else that intent's or Marketing recipient's client;
--   3. otherwise the sender's address against the organization's contacts -- accepted only when SES verified
--      the sender (aligned DKIM or DMARC pass), because a bare From header is trivially forged and this path has
--      no secret alias to vouch for it;
--   4. anything else waits in the guarded review queue.
-- The From local part names the staff sender (Marketing sends as <sender local part>@news.<root>); otherwise the
-- organization's default enabled sender answers.

drop function if exists public.record_communication_inbound_message(
  text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb, text
);

create function public.record_communication_inbound_message(
  target_provider_message_id text default null,
  target_in_reply_to_provider_message_id text default null,
  target_provider_callback_event_id uuid default null,
  target_sender_email text default null,
  target_sender_name text default null,
  target_to_recipients jsonb default null,
  target_cc_recipients jsonb default null,
  target_subject text default null,
  target_html_content text default null,
  target_text_content text default null,
  target_message_kind text default null,
  target_candidate_recipients jsonb default null,
  target_provider text default 'ses',
  target_sender_authenticated boolean default false
)
returns public.communication_inbound_messages
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  matched_domain_id uuid;
  matched_domain public.communication_email_domains;
  resolved_organization_id uuid;
  resolved_local_part text;
  alias public.communication_reply_aliases;
  in_reply_intent public.communication_delivery_intents;
  candidate_client_id uuid;
  contact_method public.client_contact_methods;
  resolved_client_id uuid;
  resolved_contact_method_id uuid;
  resolved_sender_id uuid;
  resolved_reply_alias_id uuid;
  resolved_review_status text;
  resolved_review_reason text;
  resolved_in_reply_to_intent_id uuid;
  resolved_message_kind text := target_message_kind;
  recent_count integer;
  inserted_row public.communication_inbound_messages;
begin
  -- A reply addressed to both the alias and the From address resolves through the alias.
  select domain.id, lower(candidate.value ->> 'local_part')
  into matched_domain_id, resolved_local_part
  from jsonb_array_elements(target_candidate_recipients) with ordinality as candidate(value, position)
  join public.communication_email_domains domain
    on domain.domain_name = lower(candidate.value ->> 'domain_name')
  where domain.purpose in ('receiving', 'sending', 'marketing_sending')
    and domain.lifecycle_state in ('verified', 'pending_dns', 'unhealthy')
  order by (domain.purpose = 'receiving') desc, candidate.position
  limit 1;

  if matched_domain_id is null then
    return null;
  end if;
  select * into matched_domain from public.communication_email_domains where id = matched_domain_id;
  resolved_organization_id := matched_domain.organization_id;

  if target_in_reply_to_provider_message_id is not null then
    select * into in_reply_intent from public.communication_delivery_intents
    where organization_id = resolved_organization_id
      and provider_message_id = target_in_reply_to_provider_message_id;
    resolved_in_reply_to_intent_id := in_reply_intent.id;
  end if;

  if matched_domain.purpose = 'receiving' then
    select * into alias from public.communication_reply_aliases
    where receiving_domain_id = matched_domain.id and alias_local_part = resolved_local_part;
  elsif in_reply_intent.reply_alias_id is not null then
    select * into alias from public.communication_reply_aliases
    where id = in_reply_intent.reply_alias_id and organization_id = resolved_organization_id;
  end if;

  if alias.id is not null then
    if alias.expires_at < now() then
      resolved_review_status := 'pending_review';
      resolved_review_reason := 'expired_alias';
    else
      select * into contact_method from public.client_contact_methods
      where organization_id = resolved_organization_id
        and client_id = alias.client_id
        and kind = 'email'
        and normalized_value = lower(target_sender_email);

      if contact_method.id is null then
        resolved_review_status := 'pending_review';
        resolved_review_reason := 'ambiguous_sender';
      else
        resolved_review_status := 'accepted';
        resolved_client_id := alias.client_id;
        resolved_contact_method_id := contact_method.id;
        resolved_sender_id := alias.sender_id;
        resolved_reply_alias_id := alias.id;
      end if;
    end if;
  elsif matched_domain.purpose = 'receiving' then
    resolved_review_status := 'pending_review';
    resolved_review_reason := 'unknown_sender';
  else
    -- From-address reply without an alias.
    candidate_client_id := in_reply_intent.client_id;
    if candidate_client_id is null and target_in_reply_to_provider_message_id is not null then
      select client_id into candidate_client_id from public.marketing_campaign_recipients
      where organization_id = resolved_organization_id
        and provider_message_id = target_in_reply_to_provider_message_id;
    end if;

    -- Unique per organization (client_contact_methods_org_value_unique_idx), so at most one contact matches.
    select * into contact_method from public.client_contact_methods
    where organization_id = resolved_organization_id
      and kind = 'email'
      and normalized_value = lower(target_sender_email);

    resolved_sender_id := in_reply_intent.sender_id;
    if resolved_sender_id is null then
      select sender.id into resolved_sender_id from public.communication_email_senders sender
      where sender.organization_id = resolved_organization_id
        and sender.lifecycle_state = 'enabled'
        and (
          lower(split_part(sender.email_address, '@', 1)) = resolved_local_part
          or sender.is_organization_default
        )
      order by (lower(split_part(sender.email_address, '@', 1)) = resolved_local_part) desc,
        (sender.domain_id = matched_domain.id) desc,
        sender.is_organization_default desc,
        sender.created_at
      limit 1;
    end if;

    if contact_method.id is null then
      resolved_review_status := 'pending_review';
      resolved_review_reason := case when candidate_client_id is null
        then 'unknown_sender' else 'ambiguous_sender' end;
    elsif resolved_sender_id is null
      or (candidate_client_id is not null and contact_method.client_id <> candidate_client_id)
      or (candidate_client_id is null and not coalesce(target_sender_authenticated, false)) then
      resolved_review_status := 'pending_review';
      resolved_review_reason := 'ambiguous_sender';
    else
      resolved_review_status := 'accepted';
      resolved_client_id := contact_method.client_id;
      resolved_contact_method_id := contact_method.id;
    end if;

    if resolved_review_status <> 'accepted' then
      resolved_sender_id := null;
    end if;
  end if;

  select count(*) into recent_count from public.communication_inbound_messages
  where organization_id = resolved_organization_id
    and lower(sender_email) = lower(target_sender_email)
    and subject = target_subject
    and created_at > now() - interval '10 minutes';

  if recent_count >= 3 then
    resolved_message_kind := 'loop_detected';
  end if;

  insert into public.communication_inbound_messages (
    organization_id, reply_alias_id, client_id, client_contact_method_id, sender_id, provider,
    provider_message_id, in_reply_to_provider_message_id, in_reply_to_intent_id,
    sender_email, sender_name, to_recipients, cc_recipients, subject, html_content, text_content,
    message_kind, review_status, review_reason, automation_suppressed, loop_detected_at,
    provider_callback_event_id
  ) values (
    resolved_organization_id, resolved_reply_alias_id, resolved_client_id, resolved_contact_method_id,
    resolved_sender_id, target_provider, target_provider_message_id, target_in_reply_to_provider_message_id,
    resolved_in_reply_to_intent_id, target_sender_email, target_sender_name, target_to_recipients,
    target_cc_recipients, target_subject, target_html_content, target_text_content,
    resolved_message_kind, resolved_review_status, resolved_review_reason,
    (resolved_message_kind <> 'reply') or (resolved_review_status <> 'accepted'),
    case when resolved_message_kind = 'loop_detected' then now() else null end,
    target_provider_callback_event_id
  )
  on conflict (provider, provider_message_id) where provider_message_id is not null do nothing
  returning * into inserted_row;

  if inserted_row.id is null then
    return null;
  end if;

  return inserted_row;
end;
$function$;

revoke all on function public.record_communication_inbound_message(
  text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb, text, boolean
) from public, anon, authenticated;
grant execute on function public.record_communication_inbound_message(
  text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb, text, boolean
) to service_role;
