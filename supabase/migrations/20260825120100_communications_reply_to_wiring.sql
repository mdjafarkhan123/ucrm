-- Part 4: wire reply-alias creation into outbound send, and return the Reply-To the worker should use.
--
-- Bundled fix: claim_communication_outbox_event()'s automated-sender fallback still read
-- clients.owner_user_id, a column 20260902140000_remove_client_owner_no_jobber_precedent.sql dropped
-- (Jobber has no client-level owner; see that migration's comment). No current caller reaches this
-- branch -- enqueue_quote_communication_email always sets sender_id directly, and the only other
-- 'automated' path is the unused generic enqueue_communication_email -- so it has never crashed in
-- practice, but it is exactly the same latent-bug shape the resend work found in
-- enqueue_quote_communication_email on 2026-08-25. Since this function has to change anyway to return
-- Reply-To fields, the dead branch is removed here rather than left for the next person to hit.

drop function public.claim_communication_outbox_event();

create function public.claim_communication_outbox_event()
returns table (
  outbox_event_id uuid, delivery_intent_id uuid, claim_token uuid, recipient_email text, subject text,
  html_content text, text_content text, logical_send_key text, sender_id uuid, sender_email text,
  sender_name text, reply_to_email text, reply_to_name text
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  current_recipient public.client_contact_methods;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  active_allowance record;
  allowance_limit_state text;
  allowance_limit_value integer;
  accepted_recipient_count integer;
  reserved_recipient_count integer;
  new_claim_token uuid;
  alias public.communication_reply_aliases;
  alias_domain public.communication_email_domains;
begin
  for candidate in
    select
      event.id as event_id,
      event.delivery_intent_id,
      intent.organization_id,
      intent.client_id,
      intent.client_contact_method_id,
      intent.recipient_email,
      intent.subject,
      intent.html_content,
      intent.text_content,
      intent.logical_send_key,
      intent.send_kind,
      intent.allowance_class,
      intent.sender_id,
      intent.reply_alias_id,
      intent.created_by
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    current_recipient := null;
    select method.* into current_recipient
    from public.client_contact_methods method
    where method.organization_id = candidate.organization_id
      and method.id = candidate.client_contact_method_id
    for share;

    if current_recipient.id is null
      or current_recipient.client_id <> candidate.client_id
      or current_recipient.kind <> 'email'
      or current_recipient.normalized_value <> candidate.recipient_email then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_no_longer_eligible',
        failure_message = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.event_id;
      continue;
    end if;

    selected_sender := null;
    if candidate.sender_id is not null then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id and sender.id = candidate.sender_id
      for share;
    elsif candidate.send_kind = 'automated' then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id
        and sender.is_organization_default and sender.lifecycle_state <> 'removed'
      order by sender.created_at, sender.id limit 1 for share;
    end if;

    if selected_sender.id is null then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    assigned_member_status := null;
    if selected_sender.assigned_user_id is not null then
      select member.status into assigned_member_status from public.organization_members member
      where member.organization_id = selected_sender.organization_id and member.user_id = selected_sender.assigned_user_id
      for share;
    end if;
    sender_domain := null;
    select domain.* into sender_domain from public.communication_email_domains domain
    where domain.organization_id = selected_sender.organization_id and domain.id = selected_sender.domain_id
    for share;

    if selected_sender.lifecycle_state = 'pending_verification'
      or (sender_domain.id is not null and sender_domain.lifecycle_state not in ('removal_pending', 'removed')
        and (sender_domain.lifecycle_state <> 'verified' or not sender_domain.provider_verified
          or not sender_domain.provider_authenticated or sender_domain.ownership_status <> 'passing'
          or sender_domain.dkim_status <> 'passing')) then
      update public.communication_delivery_intents set failure_code = 'sender_domain_temporarily_unavailable',
        failure_message = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if selected_sender.lifecycle_state <> 'enabled'
      or (candidate.send_kind = 'manual' and not selected_sender.allows_manual)
      or (candidate.send_kind = 'automated' and not selected_sender.allows_automated)
      or (selected_sender.assigned_user_id is not null and assigned_member_status is distinct from 'active')
      or sender_domain.id is null or sender_domain.purpose <> 'sending'
      or sender_domain.lifecycle_state in ('removal_pending', 'removed') then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    select * into active_allowance
    from private.resolve_communication_email_allowance(candidate.organization_id, now());
    if not found then
      update public.communication_delivery_intents set failure_code = 'email_allowance_period_unavailable',
        failure_message = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if candidate.allowance_class = 'optional' then
      allowance_limit_state := active_allowance.operational_limit_state;
      allowance_limit_value := active_allowance.operational_limit_value;
    else
      allowance_limit_state := active_allowance.essential_limit_state;
      allowance_limit_value := active_allowance.essential_limit_value;
    end if;
    if allowance_limit_state not in ('numeric', 'unlimited')
      or (allowance_limit_state = 'numeric' and allowance_limit_value is null) then
      update public.communication_delivery_intents set failure_code = 'email_allowance_unavailable',
        failure_message = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    insert into public.communication_email_capacity_buckets (
      organization_id, allowance_period_id, allowance_class
    ) values (candidate.organization_id, active_allowance.period_id, candidate.allowance_class)
    on conflict do nothing;
    perform 1 from public.communication_email_capacity_buckets bucket
    where bucket.organization_id = candidate.organization_id
      and bucket.allowance_period_id = active_allowance.period_id
      and bucket.allowance_class = candidate.allowance_class
    for update;

    if allowance_limit_state = 'numeric' then
      select coalesce(sum(usage.recipient_count), 0)::integer into accepted_recipient_count
      from public.communication_email_usage_events usage
      where usage.organization_id = candidate.organization_id
        and usage.allowance_period_id = active_allowance.period_id
        and usage.allowance_class = candidate.allowance_class;
      select coalesce(sum(reservation.recipient_count), 0)::integer into reserved_recipient_count
      from public.communication_email_capacity_reservations reservation
      where reservation.organization_id = candidate.organization_id
        and reservation.allowance_period_id = active_allowance.period_id
        and reservation.allowance_class = candidate.allowance_class
        and reservation.reservation_state in ('reserved', 'submission_unknown');
      if accepted_recipient_count + reserved_recipient_count >= allowance_limit_value then
        update public.communication_delivery_intents set failure_code = 'email_allowance_exhausted',
          failure_message = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set available_at = now() + interval '15 minutes',
          last_error = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    insert into public.communication_email_capacity_reservations (
      organization_id, delivery_intent_id, allowance_period_id, allowance_class, reservation_state, reserved_at, settled_at
    ) values (
      candidate.organization_id, candidate.delivery_intent_id, active_allowance.period_id,
      candidate.allowance_class, 'reserved', now(), null
    ) on conflict on constraint communication_email_capacity_reservations_delivery_intent_key do update set
      organization_id = excluded.organization_id,
      allowance_period_id = excluded.allowance_period_id,
      allowance_class = excluded.allowance_class,
      reservation_state = 'reserved', reserved_at = now(), settled_at = null
    where public.communication_email_capacity_reservations.reservation_state = 'released';
    if not found then
      raise exception 'The email capacity reservation is not available for this delivery intent.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;

    alias := null;
    alias_domain := null;
    if candidate.reply_alias_id is not null then
      select rep_alias.* into alias from public.communication_reply_aliases rep_alias
      where rep_alias.id = candidate.reply_alias_id and rep_alias.organization_id = candidate.organization_id
      for share;
      if alias.id is not null then
        select * into alias_domain from public.communication_email_domains
        where id = alias.receiving_domain_id and organization_id = candidate.organization_id
        for share;
      end if;
    end if;

    new_claim_token := gen_random_uuid();
    update public.communication_outbox_events set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null where id = candidate.event_id;
    update public.communication_delivery_intents set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null where id = candidate.delivery_intent_id;
    return query select candidate.event_id, candidate.delivery_intent_id, new_claim_token,
      candidate.recipient_email, candidate.subject, candidate.html_content, candidate.text_content,
      candidate.logical_send_key, selected_sender.id, selected_sender.email_address, selected_sender.display_name,
      case when alias.id is not null and alias_domain.id is not null
        then alias.alias_local_part || '@' || alias_domain.domain_name else null end,
      case when alias.id is not null then selected_sender.display_name else null end;
    return;
  end loop;
end;
$$;

revoke all on function public.claim_communication_outbox_event() from public;
grant execute on function public.claim_communication_outbox_event() to service_role;

-- enqueue_manual_communication_email and enqueue_quote_communication_email already resolve the exact
-- sender before inserting the delivery intent, so the alias can be created (or reused) right there.
create or replace function public.enqueue_manual_communication_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_contact_method_id uuid,
  target_logical_send_key text,
  target_subject text,
  target_html_content text,
  target_text_content text
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  recipient public.client_contact_methods;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
  alias public.communication_reply_aliases;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'customers.view') then
    raise exception 'You do not have permission to send a customer message.' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.organizations organization
    where organization.id = target_organization_id and organization.lifecycle_status = 'active'
  ) then
    raise exception 'This organization cannot send customer email right now.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.id = target_contact_method_id
    and method.client_id = target_client_id
    and method.kind = 'email'
    and client.deleted_at is null
  for share of method, client;

  if recipient.id is null then
    raise exception 'Choose an active email address for this customer.' using errcode = 'foreign_key_violation';
  end if;

  -- The actor's enabled manual sender is resolved and locked before its one referenced domain.
  -- The worker repeats these authority checks immediately before provider submission.
  select email_sender.* into sender
  from public.communication_email_senders email_sender
  where email_sender.organization_id = target_organization_id
    and email_sender.assigned_user_id = target_actor_user_id
    and email_sender.lifecycle_state = 'enabled'
    and email_sender.allows_manual
  order by email_sender.is_organization_default desc, email_sender.created_at, email_sender.id
  limit 1
  for share of email_sender;

  if sender.id is not null then
    select domain.* into sender_domain
    from public.communication_email_domains domain
    where domain.organization_id = target_organization_id
      and domain.id = sender.domain_id
      and domain.purpose = 'sending'
      and domain.lifecycle_state = 'verified'
      and domain.provider_verified
      and domain.provider_authenticated
      and domain.ownership_status = 'passing'
      and domain.dkim_status = 'passing'
    for share of domain;
  end if;

  if sender.id is null or sender_domain.id is null then
    raise exception 'Your assigned email sender is not ready. Ask an administrator to review it.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  alias := public.ensure_communication_reply_alias(target_organization_id, sender.id, target_client_id, recipient.id);

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
    subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by
  ) values (
    target_organization_id, target_client_id, target_contact_method_id, target_logical_send_key,
    recipient.normalized_value, target_subject, target_html_content, target_text_content,
    'manual', 'optional', sender.id, alias.id, target_actor_user_id
  ) on conflict (organization_id, logical_send_key) do update
    set logical_send_key = excluded.logical_send_key
  returning * into intent;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
  values (intent.organization_id, intent.id)
  on conflict (delivery_intent_id) do nothing;

  return intent;
end;
$$;

create or replace function public.enqueue_quote_communication_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_quote_id uuid,
  target_logical_send_key text,
  target_quote_url text,
  target_quote_token_hash bytea
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  quote_row public.quotes; version_row public.quote_versions; client_row public.clients;
  recipient public.client_contact_methods; quote_recipient public.quote_recipients;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
  alias public.communication_reply_aliases;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'quotes.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to send this quote by email.' using errcode = 'insufficient_privilege';
  end if;
  if target_quote_url !~ '^https?://[^[:space:]]+$' or target_quote_token_hash is null
    or octet_length(target_quote_token_hash) <> 32 then
    raise exception 'The quote delivery link is not available.' using errcode = 'check_violation';
  end if;
  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = target_logical_send_key for share;
  if intent.id is not null then
    if intent.quote_id is distinct from target_quote_id then
      raise exception 'This email retry does not match the original quote.' using errcode = 'unique_violation';
    end if;
    return intent;
  end if;
  select * into quote_row from public.quotes
    where organization_id = target_organization_id and id = target_quote_id
      and status in ('awaiting_response', 'changes_requested', 'approved') and archived_at is null for share;
  if quote_row.id is null then raise exception 'This quote is not available to send.' using errcode = 'foreign_key_violation'; end if;
  select * into version_row from public.quote_versions
    where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
      and quote_id = quote_row.id and status = 'published' for share;
  select * into client_row from public.clients
    where organization_id = quote_row.organization_id and id = quote_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = quote_row.organization_id and client_id = quote_row.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if version_row.id is null or client_row.id is null or recipient.id is null then
    raise exception 'This quote needs an active customer email address before it can be sent.' using errcode = 'object_not_in_prerequisite_state';
  end if;
  select * into sender from public.communication_email_senders
    where organization_id = quote_row.organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    raise exception 'No automated email sender is ready for this business.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  alias := public.ensure_communication_reply_alias(quote_row.organization_id, sender.id, quote_row.client_id, recipient.id);

  insert into public.quote_recipients (organization_id, quote_id, display_name, email, created_by)
    values (quote_row.organization_id, quote_row.id, coalesce(nullif(trim(client_row.display_name), ''), recipient.normalized_value), recipient.normalized_value, target_actor_user_id)
    on conflict (organization_id, quote_id, email) do update set display_name = excluded.display_name returning * into quote_recipient;
  update public.quote_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = quote_row.organization_id and quote_id = quote_row.id and recipient_id = quote_recipient.id and revoked_at is null;
  insert into public.quote_access_links (organization_id, quote_id, quote_version_id, recipient_id, token_hash, issued_by)
    values (quote_row.organization_id, quote_row.id, version_row.id, quote_recipient.id, target_quote_token_hash, target_actor_user_id);
  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, quote_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by)
    values (quote_row.organization_id, quote_row.client_id, recipient.id, quote_row.id, target_logical_send_key, recipient.normalized_value,
      'Your quote from ' || version_row.organization_name,
      '<p>Your quote is ready to review.</p><p><a href="' || replace(target_quote_url, '&', '&amp;') || '">View your quote</a></p>',
      'Your quote is ready to review. View it here: ' || target_quote_url, 'automated', 'essential', sender.id, alias.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);
  return intent;
end;
$$;

revoke all on function public.enqueue_manual_communication_email(uuid, uuid, uuid, uuid, text, text, text, text) from public;
grant execute on function public.enqueue_manual_communication_email(uuid, uuid, uuid, uuid, text, text, text, text) to service_role;
revoke all on function public.enqueue_quote_communication_email(uuid, uuid, uuid, text, text, bytea) from public;
grant execute on function public.enqueue_quote_communication_email(uuid, uuid, uuid, text, text, bytea) to service_role;
