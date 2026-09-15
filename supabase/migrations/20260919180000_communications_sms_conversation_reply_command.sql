-- Communications Stage 6B: send an SMS reply from an already-open Conversations thread.
--
-- Sibling of enqueue_conversation_reply_email (20260825085400): same "resolve the recipient from this
-- conversation's own most recent activity, never a browser-chosen contact method" shape, but the actual
-- send is delegated whole to communication_sms_enqueue_operational (20260919110000), which already owns
-- every SMS-specific gate (consent, readiness/holds, balance, segments, rate, quiet hours) and the atomic
-- intent/reservation/snapshot/outbox write. This command's only job is recipient resolution and naming the
-- operational subject: a manual Conversations reply is a direct service conversation (implementation plan
-- §4A, "plain operational subjects: direct service conversations..."), so it always sends subject 'service'.
-- Sender selection is left to the organization default (p_sender_id null) -- there is no per-user assigned
-- SMS sender the way email has assigned mailboxes, only the one org-default number set in Phone & SMS (3C).

create or replace function public.enqueue_conversation_reply_sms(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_logical_send_key text,
  target_body text
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  recipient public.client_contact_methods;
  latest_contact_method_id uuid;
begin
  -- The reply always goes to whichever phone this conversation most recently used, falling back to the
  -- customer's primary phone only when the conversation itself has no resolvable prior SMS activity.
  select client_contact_method_id into latest_contact_method_id
  from (
    select client_contact_method_id, created_at
    from public.communication_delivery_intents
    where organization_id = target_organization_id and client_id = target_client_id and channel = 'sms'
    union all
    select client_contact_method_id, created_at
    from public.communication_inbound_messages
    where organization_id = target_organization_id and client_id = target_client_id and channel = 'sms'
  ) activity
  order by created_at desc
  limit 1;

  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.client_id = target_client_id
    and method.kind = 'phone'
    and client.deleted_at is null
    and (latest_contact_method_id is null or method.id = latest_contact_method_id)
  order by method.is_primary desc, method.created_at, method.id
  limit 1
  for share of method, client;

  if recipient.id is null then
    raise exception 'This customer has no active phone number to reply to.' using errcode = 'foreign_key_violation';
  end if;

  return public.communication_sms_enqueue_operational(
    target_organization_id, target_actor_user_id, target_client_id, recipient.id,
    null, 'service', target_body, 'manual', target_logical_send_key
  );
end;
$$;

revoke all on function public.enqueue_conversation_reply_sms(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.enqueue_conversation_reply_sms(uuid, uuid, uuid, text, text)
  to service_role;

comment on function public.enqueue_conversation_reply_sms(uuid, uuid, uuid, text, text) is
  'Resolves the SMS reply recipient from this conversation''s own most recent activity (falling back to the '
  'primary phone) and delegates the send to communication_sms_enqueue_operational with subject ''service'' '
  '(a manual reply is a direct service conversation) and the organization''s default sender.';
