-- Communications Part 2: make stored sender authority part of the atomic outbox claim.
-- Allowance authority is intentionally still absent, so the live worker route remains disabled.

alter table public.communication_delivery_intents
  add column send_kind text not null default 'manual'
    check (send_kind in ('manual', 'automated')),
  add column sender_id uuid,
  add constraint communication_delivery_intents_sender_fk
    foreign key (organization_id, sender_id)
    references public.communication_email_senders (organization_id, id) on delete restrict;

create index communication_delivery_intents_sender_idx
  on public.communication_delivery_intents (organization_id, sender_id)
  where sender_id is not null;

comment on column public.communication_delivery_intents.sender_id is
  'The queued sender preference. The worker may submit only the sender returned by the atomic claim.';

-- PostgreSQL cannot change a function's return row type through CREATE OR REPLACE.
drop function public.claim_communication_outbox_event();

create function public.claim_communication_outbox_event()
returns table (
  outbox_event_id uuid,
  delivery_intent_id uuid,
  claim_token uuid,
  recipient_email text,
  subject text,
  html_content text,
  text_content text,
  logical_send_key text,
  sender_id uuid,
  sender_email text,
  sender_name text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate record;
  current_recipient public.client_contact_methods;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  contact_owner_id uuid;
  new_claim_token uuid;
begin
  -- Inspect a bounded number of due rows so one deferred or invalid message cannot starve healthy work.
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
      intent.sender_id,
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
      select client.owner_user_id into contact_owner_id
      from public.clients client
      where client.organization_id = candidate.organization_id and client.id = candidate.client_id
      for share;

      if contact_owner_id is not null then
        select sender.* into selected_sender
        from public.communication_email_senders sender
        where sender.organization_id = candidate.organization_id
          and sender.assigned_user_id = contact_owner_id
          and sender.lifecycle_state <> 'removed'
        order by sender.created_at, sender.id
        limit 1
        for share;
      else
        select sender.* into selected_sender
        from public.communication_email_senders sender
        where sender.organization_id = candidate.organization_id
          and sender.is_organization_default
          and sender.lifecycle_state <> 'removed'
        order by sender.created_at, sender.id
        limit 1
        for share;
      end if;
    end if;

    if selected_sender.id is null then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents
        set status = 'failed', provider_message_id = null, accepted_at = null,
          failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;

        update public.communication_outbox_events
        set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents
        set status = 'cancelled', provider_message_id = null, accepted_at = null,
          failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;

        update public.communication_outbox_events
        set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    assigned_member_status := null;
    if selected_sender.assigned_user_id is not null then
      select member.status into assigned_member_status
      from public.organization_members member
      where member.organization_id = selected_sender.organization_id
        and member.user_id = selected_sender.assigned_user_id
      for share;
    end if;

    sender_domain := null;
    select domain.* into sender_domain
    from public.communication_email_domains domain
    where domain.organization_id = selected_sender.organization_id
      and domain.id = selected_sender.domain_id
    for share;

    if selected_sender.lifecycle_state = 'pending_verification'
      or (
        sender_domain.id is not null
        and sender_domain.lifecycle_state not in ('removal_pending', 'removed')
        and (
          sender_domain.lifecycle_state <> 'verified'
          or not sender_domain.provider_verified
          or not sender_domain.provider_authenticated
          or sender_domain.ownership_status <> 'passing'
          or sender_domain.dkim_status <> 'passing'
          or sender_domain.spf_status <> 'passing'
        )
      ) then
      update public.communication_delivery_intents
      set failure_code = 'sender_domain_temporarily_unavailable',
        failure_message = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;

      update public.communication_outbox_events
      set available_at = now() + interval '15 minutes',
        last_error = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if selected_sender.lifecycle_state <> 'enabled'
      or (candidate.send_kind = 'manual' and not selected_sender.allows_manual)
      or (candidate.send_kind = 'automated' and not selected_sender.allows_automated)
      or (selected_sender.assigned_user_id is not null and assigned_member_status is distinct from 'active')
      or sender_domain.id is null
      or sender_domain.purpose <> 'sending'
      or sender_domain.lifecycle_state in ('removal_pending', 'removed') then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents
        set status = 'failed', provider_message_id = null, accepted_at = null,
          failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;

        update public.communication_outbox_events
        set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents
        set status = 'cancelled', provider_message_id = null, accepted_at = null,
          failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;

        update public.communication_outbox_events
        set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    new_claim_token := gen_random_uuid();

    update public.communication_outbox_events
    set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null
    where id = candidate.event_id;

    update public.communication_delivery_intents
    set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null
    where id = candidate.delivery_intent_id;

    return query select
      candidate.event_id,
      candidate.delivery_intent_id,
      new_claim_token,
      candidate.recipient_email,
      candidate.subject,
      candidate.html_content,
      candidate.text_content,
      candidate.logical_send_key,
      selected_sender.id,
      selected_sender.email_address,
      selected_sender.display_name;
    return;
  end loop;
end;
$$;

revoke all on function public.claim_communication_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_outbox_event() to service_role;
