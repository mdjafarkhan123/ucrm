-- Communications Part 5C-ii: enqueue, claim, finalize, and quarantine a manual forward.
--
-- Deliberately narrower than the customer-email claim path (20260825120100_communications_reply_to_
-- wiring.sql): no allowance/capacity reservation, no reply-alias resolution -- a forward is not customer
-- email (see 20260826090100's header comment). Sender/domain readiness is still re-checked at claim time,
-- since that is real send correctness, not allowance accounting, and mirrors every other claim function
-- here.
--
-- A forward only ever targets one already-resolved conversation's inbound message -- an unresolved
-- (guarded) message has no client_id, and this campaign's related-work/context features already treat an
-- unresolved conversation as having no client relationship yet (Part 5D), so forwarding one is out of
-- scope until it is resolved (Part 5C-i) onto a client.

create function public.enqueue_inbound_message_forward(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_source_inbound_message_id uuid,
  target_logical_send_key text,
  target_recipient_emails text[],
  target_subject text,
  target_html_content text,
  target_text_content text,
  target_attachment_ids uuid[] default '{}'::uuid[]
) returns public.communication_forward_events
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  source_message public.communication_inbound_messages;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  event public.communication_forward_events;
  available_attachment_count integer;
  requested_attachment_count integer;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.forward')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'customers.view') then
    raise exception 'You do not have permission to forward a message.' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.organizations organization
    where organization.id = target_organization_id and organization.lifecycle_status = 'active'
  ) then
    raise exception 'This organization cannot forward email right now.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  select message.* into source_message
  from public.communication_inbound_messages message
  where message.organization_id = target_organization_id
    and message.id = target_source_inbound_message_id
  for share;

  if source_message.id is null then
    raise exception 'This message does not exist.' using errcode = 'no_data_found';
  end if;
  if source_message.client_id is null then
    raise exception 'Resolve this message to a conversation before forwarding it.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if target_recipient_emails is null or array_length(target_recipient_emails, 1) is null
    or array_length(target_recipient_emails, 1) > 10 then
    raise exception 'Choose between 1 and 10 recipients.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from unnest(target_recipient_emails) recipient_email where position('@' in recipient_email) < 2
  ) then
    raise exception 'Enter a valid email address for every recipient.' using errcode = 'check_violation';
  end if;

  requested_attachment_count := coalesce(array_length(target_attachment_ids, 1), 0);
  if requested_attachment_count > 0 then
    select count(*) into available_attachment_count
    from public.communication_inbound_attachments attachment
    where attachment.organization_id = target_organization_id
      and attachment.inbound_message_id = target_source_inbound_message_id
      and attachment.status = 'available'
      and attachment.id = any(target_attachment_ids);
    if available_attachment_count <> requested_attachment_count then
      raise exception 'One or more attachments are no longer available to forward.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  end if;

  -- Same sender resolution as enqueue_conversation_reply_email: the actor's own enabled manual sender,
  -- locked before its one referenced domain. The claim function repeats this check defensively.
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

  insert into public.communication_forward_events (
    organization_id, client_id, source_inbound_message_id, sender_id, recipient_emails,
    logical_send_key, subject, html_content, text_content, created_by
  ) values (
    target_organization_id, source_message.client_id, target_source_inbound_message_id, sender.id,
    target_recipient_emails, target_logical_send_key, target_subject, target_html_content,
    target_text_content, target_actor_user_id
  ) on conflict (organization_id, logical_send_key) do update
    set logical_send_key = excluded.logical_send_key
  returning * into event;

  if requested_attachment_count > 0 then
    insert into public.communication_forward_attachments (organization_id, forward_event_id, inbound_attachment_id)
    select target_organization_id, event.id, attachment_id
    from unnest(target_attachment_ids) attachment_id
    on conflict (forward_event_id, inbound_attachment_id) do nothing;
  end if;

  return event;
end;
$$;

revoke all on function public.enqueue_inbound_message_forward(
  uuid, uuid, uuid, text, text[], text, text, text, uuid[]
) from public, anon, authenticated;
grant execute on function public.enqueue_inbound_message_forward(
  uuid, uuid, uuid, text, text[], text, text, text, uuid[]
) to service_role;

create function public.claim_communication_forward_event()
returns table (
  forward_event_id uuid, claim_token uuid, recipient_emails text[], subject text, html_content text,
  text_content text, sender_id uuid, sender_email text, sender_name text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate record;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  new_claim_token uuid;
begin
  for candidate in
    select event.*
    from public.communication_forward_events event
    where event.status in ('queued', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update skip locked
  loop
    select sender.* into selected_sender
    from public.communication_email_senders sender
    where sender.organization_id = candidate.organization_id and sender.id = candidate.sender_id
    for share;

    assigned_member_status := null;
    if selected_sender.assigned_user_id is not null then
      select member.status into assigned_member_status from public.organization_members member
      where member.organization_id = selected_sender.organization_id
        and member.user_id = selected_sender.assigned_user_id
      for share;
    end if;
    select domain.* into sender_domain from public.communication_email_domains domain
    where domain.organization_id = selected_sender.organization_id and domain.id = selected_sender.domain_id
    for share;

    if selected_sender.id is null or selected_sender.lifecycle_state <> 'enabled'
      or not selected_sender.allows_manual
      or (selected_sender.assigned_user_id is not null and assigned_member_status is distinct from 'active')
      or sender_domain.id is null or sender_domain.purpose <> 'sending'
      or sender_domain.lifecycle_state not in ('verified')
      or not sender_domain.provider_verified or not sender_domain.provider_authenticated
      or sender_domain.ownership_status <> 'passing' or sender_domain.dkim_status <> 'passing' then
      update public.communication_forward_events
      set status = 'failed', available_at = 'infinity'::timestamptz,
        failure_code = 'forward_sender_review_required',
        failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
      where id = candidate.id;
      continue;
    end if;

    new_claim_token := gen_random_uuid();
    update public.communication_forward_events
    set status = 'claimed', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, failure_code = null, failure_message = null
    where id = candidate.id;

    return query select candidate.id, new_claim_token, candidate.recipient_emails, candidate.subject,
      candidate.html_content, candidate.text_content, selected_sender.id, selected_sender.email_address,
      selected_sender.display_name;
    return;
  end loop;
end;
$$;

revoke all on function public.claim_communication_forward_event() from public, anon, authenticated;
grant execute on function public.claim_communication_forward_event() to service_role;

create function public.finalize_communication_forward_event(
  target_forward_event_id uuid,
  target_claim_token uuid,
  target_outcome text,
  target_provider_message_id text default null,
  target_failure_code text default null,
  target_failure_message text default null
)
returns public.communication_forward_events
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed_event public.communication_forward_events;
  next_available_at timestamptz;
begin
  if target_outcome not in ('submitted', 'retry', 'submission_unknown', 'cancelled') then
    raise exception 'The forward outcome is invalid.' using errcode = 'check_violation';
  end if;

  select * into claimed_event from public.communication_forward_events where id = target_forward_event_id
  for update;
  if not found then
    raise exception 'The forward event does not exist.' using errcode = 'no_data_found';
  end if;

  if claimed_event.status <> 'claimed' then
    if claimed_event.finalized_claim_token is distinct from target_claim_token then
      raise exception 'The forward claim is no longer current.' using errcode = 'object_not_in_prerequisite_state';
    end if;
    return claimed_event;
  end if;

  if claimed_event.claim_token is distinct from target_claim_token then
    raise exception 'The forward claim token is invalid.' using errcode = 'insufficient_privilege';
  end if;

  if target_outcome = 'submitted' then
    if nullif(trim(target_provider_message_id), '') is null then
      raise exception 'A submitted forward requires a provider message identifier.' using errcode = 'not_null_violation';
    end if;
    update public.communication_forward_events
    set status = 'submitted', provider_message_id = trim(target_provider_message_id), accepted_at = now(),
      claimed_at = null, claim_token = null, finalized_claim_token = target_claim_token,
      failure_code = null, failure_message = null
    where id = claimed_event.id
    returning * into claimed_event;

  elsif target_outcome = 'retry' then
    next_available_at := case claimed_event.attempt_count
      when 1 then now() + interval '5 minutes'
      when 2 then now() + interval '30 minutes'
      when 3 then now() + interval '2 hours'
      when 4 then now() + interval '8 hours'
      when 5 then now() + interval '24 hours'
      else 'infinity'::timestamptz
    end;
    update public.communication_forward_events
    set status = 'failed', available_at = next_available_at, claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.id
    returning * into claimed_event;

  elsif target_outcome = 'submission_unknown' then
    update public.communication_forward_events
    set status = 'submission_unknown', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.id
    returning * into claimed_event;

  else
    update public.communication_forward_events
    set status = 'cancelled', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.id
    returning * into claimed_event;
  end if;

  return claimed_event;
end;
$$;

revoke all on function public.finalize_communication_forward_event(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_communication_forward_event(uuid, uuid, text, text, text, text)
  to service_role;

create function public.quarantine_stale_communication_forward_claims(
  batch_size integer default 50,
  stale_after interval default interval '15 minutes'
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quarantined_count integer;
begin
  if batch_size < 1 or batch_size > 100 then
    raise exception 'The stale forward batch is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if stale_after < interval '1 minute' or stale_after > interval '1 day' then
    raise exception 'The stale forward threshold is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  with stale as (
    select id from public.communication_forward_events
    where status = 'claimed' and claimed_at <= now() - stale_after
    order by claimed_at, id
    limit batch_size
    for update skip locked
  )
  update public.communication_forward_events event
  set status = 'submission_unknown', finalized_claim_token = event.claim_token,
    claimed_at = null, claim_token = null,
    last_error = 'The worker lease expired before its provider outcome was recorded.'
  from stale
  where event.id = stale.id;
  get diagnostics quarantined_count = row_count;

  return quarantined_count;
end;
$$;

revoke all on function public.quarantine_stale_communication_forward_claims(integer, interval)
  from public, anon, authenticated;
grant execute on function public.quarantine_stale_communication_forward_claims(integer, interval)
  to service_role;
