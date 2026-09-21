-- Communications Part 3: the browser may never write a delivery record or choose a sender/recipient
-- address directly. The API passes only IDs, plain text, and its authenticated actor into this
-- service-only command; the command resolves the durable recipient and sender from UCRM authority.

revoke all on function public.enqueue_communication_email(uuid, uuid, uuid, text, text, text, text, text)
  from public, anon, authenticated, service_role;

create or replace function public.enqueue_manual_communication_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_contact_method_id uuid,
  target_logical_send_key text,
  target_subject text,
  target_html_content text,
  target_text_content text
)
returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  recipient public.client_contact_methods;
  sender public.communication_email_senders;
  intent public.communication_delivery_intents;
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

  -- A manual message is always tied to the logged-in member's own enabled sender. The claim repeats
  -- this check immediately before provider submission and holds the message for review if it changed.
  select email_sender.* into sender
  from public.communication_email_senders email_sender
  join public.communication_email_domains domain
    on domain.organization_id = email_sender.organization_id and domain.id = email_sender.domain_id
  where email_sender.organization_id = target_organization_id
    and email_sender.assigned_user_id = target_actor_user_id
    and email_sender.lifecycle_state = 'enabled'
    and email_sender.allows_manual
    and domain.purpose = 'sending'
    and domain.lifecycle_state = 'verified'
    and domain.provider_verified
    and domain.provider_authenticated
    and domain.ownership_status = 'passing'
    and domain.dkim_status = 'passing'
  order by email_sender.is_organization_default desc, email_sender.created_at, email_sender.id
  limit 1
  for share of email_sender, domain;

  if sender.id is null then
    raise exception 'Your assigned email sender is not ready. Ask an administrator to review it.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
    subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by
  ) values (
    target_organization_id, target_client_id, target_contact_method_id, target_logical_send_key,
    recipient.normalized_value, target_subject, target_html_content, target_text_content,
    'manual', 'optional', sender.id, target_actor_user_id
  ) on conflict (organization_id, logical_send_key) do update
    set logical_send_key = excluded.logical_send_key
  returning * into intent;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
  values (intent.organization_id, intent.id)
  on conflict (delivery_intent_id) do nothing;

  return intent;
end;
$$;

revoke all on function public.enqueue_manual_communication_email(uuid, uuid, uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.enqueue_manual_communication_email(uuid, uuid, uuid, uuid, text, text, text, text)
  to service_role;
