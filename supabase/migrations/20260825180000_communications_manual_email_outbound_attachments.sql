-- Communications Part 5 (5E-iii continued): extend enqueue_manual_communication_email with the same
-- target_attachments parameter enqueue_conversation_reply_email already has (20260825170000).
--
-- Decided 2026-08-25 ("Follow GHL"): GHL has one composer, so the same paperclip attaches a file whether
-- the message is a reply or a fresh conversation, and 5E-ii already routes "New conversation" through
-- this exact command via ManualEmailDialog.
--
-- A trailing default parameter is not enough to keep this a single overload: Postgres identifies a
-- function by its schema, name, and full argument-type list, so a default-valued 9th parameter creates a
-- *second*, ambiguous overload rather than extending the 8-argument one -- confirmed the hard way
-- (calling with the original 8 arguments then fails "function ... is not unique"). The old signature is
-- dropped first, exactly like enqueue_conversation_reply_email's own 7-to-8-argument change. This is
-- still a compatible change for every real caller: they all invoke through PostgREST/supabase-js with
-- named parameters, so an existing call that omits target_attachments keeps resolving to this one
-- function with the default applied -- including the untouched email.spec.ts fixtures, since that spec
-- mocks the RPC boundary rather than calling Postgres.

drop function public.enqueue_manual_communication_email(uuid, uuid, uuid, uuid, text, text, text, text);

create function public.enqueue_manual_communication_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_contact_method_id uuid,
  target_logical_send_key text,
  target_subject text,
  target_html_content text,
  target_text_content text,
  target_attachments jsonb default '[]'::jsonb
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
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

  -- Same ordering as enqueue_conversation_reply_email: attached inside this transaction and before the
  -- outbox event, so the worker can never claim a message before its files are recorded.
  perform private.attach_communication_outbound_files(
    intent.organization_id, intent.id, target_attachments
  );

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
  values (intent.organization_id, intent.id)
  on conflict (delivery_intent_id) do nothing;

  return intent;
end;
$function$;

revoke all on function public.enqueue_manual_communication_email(
  uuid, uuid, uuid, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.enqueue_manual_communication_email(
  uuid, uuid, uuid, uuid, text, text, text, text, jsonb
) to service_role;
