-- Communications: "Send Later" for an email reply from an already-open Conversations thread, plus cancelling
-- one before it goes out.
--
-- Email only. SMS is deliberately excluded here: an SMS reply's consent, balance, and quiet-hours gates
-- (communication_sms_enqueue_operational) are all evaluated once, at enqueue time -- holding a message for
-- hours before it actually leaves would let consent or balance go stale between the check and the real send.
-- That needs its own product/architecture decision and is not part of this change.
--
-- The outbox already carries everything a scheduled send needs: available_at (defaults to now(), and the
-- wake trigger + Cron sweep already only drain a row once it is due -- see
-- 20260830043551_communications_email_outbox_wake_on_insert_trigger.sql) and a 'cancelled' status on both
-- communication_outbox_events and communication_delivery_intents. So this adds no new column or table --
-- only an optional "send no earlier than" time on the existing enqueue command, and a command to cancel a
-- still-pending row before the worker claims it.

drop function public.enqueue_conversation_reply_email(uuid, uuid, uuid, text, text, text, text, jsonb);

create function public.enqueue_conversation_reply_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_logical_send_key text,
  target_subject text,
  target_html_content text,
  target_text_content text,
  target_attachments jsonb default '[]'::jsonb,
  target_available_at timestamptz default null
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  recipient public.client_contact_methods;
  latest_contact_method_id uuid;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
  alias public.communication_reply_aliases;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'customers.view') then
    raise exception 'You do not have permission to send a customer message.' using errcode = 'insufficient_privilege';
  end if;

  if target_available_at is not null and target_available_at <= now() then
    raise exception 'Choose a send time in the future.' using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from public.organizations organization
    where organization.id = target_organization_id and organization.lifecycle_status = 'active'
  ) then
    raise exception 'This organization cannot send customer email right now.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- The reply always goes to whichever address this conversation most recently used, not necessarily
  -- the customer's primary address -- falls back to primary only when the conversation itself has no
  -- resolvable prior activity (should not happen for an already-open conversation, kept defensive).
  select client_contact_method_id into latest_contact_method_id
  from (
    select client_contact_method_id, created_at
    from public.communication_delivery_intents
    where organization_id = target_organization_id and client_id = target_client_id
    union all
    select client_contact_method_id, created_at
    from public.communication_inbound_messages
    where organization_id = target_organization_id and client_id = target_client_id
  ) activity
  order by created_at desc
  limit 1;

  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.client_id = target_client_id
    and method.kind = 'email'
    and client.deleted_at is null
    and (latest_contact_method_id is null or method.id = latest_contact_method_id)
  order by method.is_primary desc, method.created_at, method.id
  limit 1
  for share of method, client;

  if recipient.id is null then
    raise exception 'This customer has no active email address to reply to.' using errcode = 'foreign_key_violation';
  end if;

  -- The actor's enabled manual sender is resolved and locked before its one referenced domain, exactly
  -- like enqueue_manual_communication_email. The worker repeats these authority checks before submission.
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
    target_organization_id, target_client_id, recipient.id, target_logical_send_key,
    recipient.normalized_value, target_subject, target_html_content, target_text_content,
    'manual', 'essential', sender.id, alias.id, target_actor_user_id
  ) on conflict (organization_id, logical_send_key) do update
    set logical_send_key = excluded.logical_send_key
  returning * into intent;

  perform private.attach_communication_outbound_files(
    intent.organization_id, intent.id, target_attachments
  );

  insert into public.communication_outbox_events (organization_id, delivery_intent_id, available_at)
  values (intent.organization_id, intent.id, coalesce(target_available_at, now()))
  on conflict (delivery_intent_id) do nothing;

  return intent;
end;
$function$;

revoke all on function public.enqueue_conversation_reply_email(uuid, uuid, uuid, text, text, text, text, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.enqueue_conversation_reply_email(uuid, uuid, uuid, text, text, text, text, jsonb, timestamptz)
  to service_role;

-- Cancels a still-scheduled reply before the worker has claimed it. Once a row is claimed (or settled) it is
-- no longer 'pending', or its available_at has already arrived -- either way the send is already underway or
-- done, and this refuses rather than race the worker.
create function public.cancel_communication_conversation_reply(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_delivery_intent_id uuid
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  intent public.communication_delivery_intents;
  outbox public.communication_outbox_events;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to cancel a scheduled message.' using errcode = 'insufficient_privilege';
  end if;

  select * into intent
  from public.communication_delivery_intents
  where organization_id = target_organization_id and id = target_delivery_intent_id
  for update;

  if intent.id is null then
    raise exception 'That scheduled message could not be found.' using errcode = 'no_data_found';
  end if;

  select * into outbox
  from public.communication_outbox_events
  where delivery_intent_id = intent.id
  for update;

  if outbox.id is null or outbox.status <> 'pending' or outbox.available_at <= now() then
    raise exception 'This message has already started sending and can no longer be cancelled.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  update public.communication_outbox_events
  set status = 'cancelled'
  where id = outbox.id;

  update public.communication_delivery_intents
  set status = 'cancelled'
  where id = intent.id
  returning * into intent;

  return intent;
end;
$$;

revoke all on function public.cancel_communication_conversation_reply(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_communication_conversation_reply(uuid, uuid, uuid)
  to service_role;
