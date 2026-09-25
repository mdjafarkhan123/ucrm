-- Operational email SES Part 4: keep customer replies flowing while a reply domain changes mail provider.
--
-- The resolver used to match only a receiving domain in lifecycle_state 'verified'. Turning on customer replies
-- moves reply.<root>'s MX from Brevo to Amazon SES, and for the few minutes public DNS takes to agree the row
-- reads 'pending_dns' -- so every reply arriving in that window (through either provider) matched no domain,
-- returned null, and was acknowledged and dropped. The same happened whenever a live domain's MX check briefly
-- read 'unhealthy'.
--
-- Mail can only reach UCRM for a domain whose MX already points at a UCRM provider (and, for SES, whose receipt
-- rule UCRM created), and communication_email_domains_live_claim_idx allows one live row per domain name, so
-- accepting any live receiving row cannot route a reply to the wrong organization. Only a domain being removed
-- (or removed) stops receiving. Every other line of the function is unchanged from 20260925150000.

create or replace function "public"."record_communication_inbound_message"(
    "target_provider_message_id" text default null::text,
    "target_in_reply_to_provider_message_id" text default null::text,
    "target_provider_callback_event_id" uuid default null::uuid,
    "target_sender_email" text default null::text,
    "target_sender_name" text default null::text,
    "target_to_recipients" jsonb default null::jsonb,
    "target_cc_recipients" jsonb default null::jsonb,
    "target_subject" text default null::text,
    "target_html_content" text default null::text,
    "target_text_content" text default null::text,
    "target_message_kind" text default null::text,
    "target_candidate_recipients" jsonb default null::jsonb,
    "target_provider" text default 'brevo'::text
) returns "public"."communication_inbound_messages"
    language "plpgsql" security definer
    set "search_path" to 'pg_catalog', 'public'
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
  for candidate in select value from jsonb_array_elements(target_candidate_recipients)
  loop
    select * into matched_domain from public.communication_email_domains
    where purpose = 'receiving' and lifecycle_state in ('verified', 'pending_dns', 'unhealthy')
      and domain_name = lower(candidate ->> 'domain_name')
    limit 1;

    if matched_domain.id is not null then
      resolved_organization_id := matched_domain.organization_id;
      resolved_local_part := lower(candidate ->> 'local_part');
      exit;
    end if;
  end loop;

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
$$;
