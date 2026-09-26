-- A contractor administrator can remove an email sender address.
--
-- Removal is a soft state change, never a row delete: reply aliases, delivery intents, inbound messages and
-- forward events all reference the sender (ON DELETE RESTRICT) and keep their history. A removed sender
-- disappears from the settings list, stops counting against the sending domain's removal check, and frees
-- its address for re-use (communication_email_senders_live_address_idx excludes 'removed'). Queued email is
-- left to the claim command, which already holds manual email for review and cancels automated email whose
-- sender is no longer eligible, so nothing is silently re-sent from another identity. Amazon SES has no
-- per-address sender resource, so there is no provider step.

create function public.remove_communication_email_sender(
  target_organization_id uuid,
  target_sender_id uuid,
  actor_user_id uuid,
  command_idempotency_key text
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  selected_sender public.communication_email_senders;
  before_state jsonb;
  existing_event public.communication_email_authority_events;
begin
  if command_idempotency_key is null or char_length(btrim(command_idempotency_key)) not between 1 and 180 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;

  select * into existing_event from public.communication_email_authority_events
  where organization_id = target_organization_id and idempotency_key = command_idempotency_key;
  if found then
    if existing_event.event_type <> 'sender.removed' or existing_event.target_id <> target_sender_id then
      raise exception 'The idempotency key was already used for another command.'
        using errcode = 'unique_violation';
    end if;
    select * into strict selected_sender from public.communication_email_senders
    where organization_id = target_organization_id and id = target_sender_id;
    return jsonb_build_object('replayed', true, 'sender', to_jsonb(selected_sender));
  end if;

  select * into selected_sender from public.communication_email_senders
  where organization_id = target_organization_id and id = target_sender_id
  for update;
  if not found or selected_sender.lifecycle_state = 'removed' then
    raise exception 'The sender was not found.' using errcode = 'no_data_found';
  end if;
  before_state := to_jsonb(selected_sender);

  update public.communication_email_senders
  set lifecycle_state = 'removed', is_organization_default = false, updated_at = now()
  where organization_id = target_organization_id and id = target_sender_id
  returning * into selected_sender;

  insert into public.communication_email_authority_events (
    organization_id, actor_kind, actor_user_id, event_type, target_type, target_id,
    before_state, after_state, idempotency_key
  ) values (
    target_organization_id, 'contractor_user', actor_user_id, 'sender.removed', 'sender',
    target_sender_id, before_state, to_jsonb(selected_sender), command_idempotency_key
  );

  return jsonb_build_object('replayed', false, 'sender', to_jsonb(selected_sender));
end;
$function$;

revoke all on function public.remove_communication_email_sender(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.remove_communication_email_sender(uuid, uuid, uuid, text)
  to service_role;
