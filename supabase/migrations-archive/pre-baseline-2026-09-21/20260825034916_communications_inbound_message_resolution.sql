-- Part 4 item 4: atomic tenant/conversation resolution for one inbound Brevo callback item.
-- One security-definer function does org/alias/contact resolution, in-reply-to correlation, loop
-- detection, and the insert together, mirroring claim_communication_outbox_event's resolution style.
-- Provider callback dedup happens one layer up, at communication_provider_callback_events; this
-- function's own on-conflict is belt and suspenders against a duplicate provider Message-ID.

-- The loop-detection window query (organization_id, sender_email, subject, recency) is not covered by
-- the existing org+created_at index -- it needs sender_email and subject in the key too.
create index communication_inbound_messages_loop_detect_idx
  on public.communication_inbound_messages (organization_id, sender_email, subject, created_at desc);

create or replace function public.record_communication_inbound_message(
  target_provider_message_id text,
  target_in_reply_to_provider_message_id text,
  target_provider_callback_event_id uuid,
  target_sender_email text,
  target_sender_name text,
  target_to_recipients jsonb,
  target_cc_recipients jsonb,
  target_subject text,
  target_html_content text,
  target_text_content text,
  target_message_kind text,
  target_candidate_recipients jsonb
) returns public.communication_inbound_messages
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate jsonb;
  matched_domain public.communication_email_domains;
  resolved_organization_id uuid;
  resolved_local_part text;
  alias public.communication_reply_aliases;
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
  -- To first, then Cc, in the order the caller supplied them: the first candidate whose domain is one
  -- of this deployment's verified receiving domains identifies the tenant.
  for candidate in select value from jsonb_array_elements(target_candidate_recipients)
  loop
    select * into matched_domain from public.communication_email_domains
    where purpose = 'receiving' and lifecycle_state = 'verified'
      and domain_name = lower(candidate ->> 'domain_name')
    limit 1;

    if matched_domain.id is not null then
      resolved_organization_id := matched_domain.organization_id;
      resolved_local_part := lower(candidate ->> 'local_part');
      exit;
    end if;
  end loop;

  -- No recipient addressed one of our own receiving domains: pure noise or a misdelivery, not a
  -- product case. The caller inserts nothing for this callback item.
  if resolved_organization_id is null then
    return null;
  end if;

  select * into alias from public.communication_reply_aliases
  where receiving_domain_id = matched_domain.id and alias_local_part = resolved_local_part;

  if alias.id is null then
    resolved_review_status := 'pending_review';
    resolved_review_reason := 'unknown_sender';
  elsif alias.expires_at < now() then
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

  if target_in_reply_to_provider_message_id is not null then
    select id into resolved_in_reply_to_intent_id from public.communication_delivery_intents
    where organization_id = resolved_organization_id
      and provider_message_id = target_in_reply_to_provider_message_id;
  end if;

  -- A JS-classified 'reply' or 'auto_response'/'delivery_notice' is overridden to 'loop_detected' once
  -- the same sender+subject pair has recurred three times inside ten minutes, regardless of how the
  -- header classifier read this one message.
  select count(*) into recent_count from public.communication_inbound_messages
  where organization_id = resolved_organization_id
    and lower(sender_email) = lower(target_sender_email)
    and subject = target_subject
    and created_at > now() - interval '10 minutes';

  if recent_count >= 3 then
    resolved_message_kind := 'loop_detected';
  end if;

  insert into public.communication_inbound_messages (
    organization_id, reply_alias_id, client_id, client_contact_method_id, sender_id,
    provider_message_id, in_reply_to_provider_message_id, in_reply_to_intent_id,
    sender_email, sender_name, to_recipients, cc_recipients, subject, html_content, text_content,
    message_kind, review_status, review_reason, automation_suppressed, loop_detected_at,
    provider_callback_event_id
  ) values (
    resolved_organization_id, resolved_reply_alias_id, resolved_client_id, resolved_contact_method_id,
    resolved_sender_id, target_provider_message_id, target_in_reply_to_provider_message_id,
    resolved_in_reply_to_intent_id, target_sender_email, target_sender_name, target_to_recipients,
    target_cc_recipients, target_subject, target_html_content, target_text_content,
    resolved_message_kind, resolved_review_status, resolved_review_reason,
    (resolved_message_kind <> 'reply') or (resolved_review_status <> 'accepted'),
    case when resolved_message_kind = 'loop_detected' then now() else null end,
    target_provider_callback_event_id
  )
  on conflict (provider, provider_message_id) where provider_message_id is not null do nothing
  returning * into inserted_row;

  return inserted_row;
end;
$$;

revoke all on function public.record_communication_inbound_message(
  text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.record_communication_inbound_message(
  text, text, uuid, text, text, jsonb, jsonb, text, text, text, text, jsonb
) to service_role;
