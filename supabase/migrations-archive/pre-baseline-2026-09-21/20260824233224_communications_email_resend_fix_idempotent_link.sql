create or replace function public.resend_communication_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_original_intent_id uuid,
  target_logical_send_key text,
  target_quote_url text default null,
  target_quote_token_hash bytea default null
)
returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  original public.communication_delivery_intents;
  outbox public.communication_outbox_events;
  result public.communication_delivery_intents;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to send a customer message.' using errcode = 'insufficient_privilege';
  end if;

  select * into original from public.communication_delivery_intents
    where organization_id = target_organization_id and id = target_original_intent_id
    for share;
  if original.id is null then
    raise exception 'The original message could not be found.' using errcode = 'no_data_found';
  end if;

  select * into outbox from public.communication_outbox_events
    where delivery_intent_id = original.id for share;

  if not (
    original.status = 'cancelled'
    or (original.status = 'failed' and (outbox.id is null or outbox.available_at = 'infinity'::timestamptz))
  ) then
    raise exception 'This message cannot be resent right now.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if original.quote_id is not null then
    if target_quote_url is null or target_quote_token_hash is null then
      raise exception 'The quote delivery link is not available.' using errcode = 'check_violation';
    end if;
    result := public.enqueue_quote_communication_email(
      target_organization_id, target_actor_user_id, original.quote_id,
      target_logical_send_key, target_quote_url, target_quote_token_hash
    );
  else
    result := public.enqueue_manual_communication_email(
      target_organization_id, target_actor_user_id, original.client_id, original.client_contact_method_id,
      target_logical_send_key, original.subject, original.html_content, original.text_content
    );
  end if;

  -- Unconditional, not "only if unset": a replay of the same resend key must return the existing row
  -- rather than silently losing it because the guard no longer matched.
  update public.communication_delivery_intents
    set resent_from_intent_id = original.id
    where id = result.id
    returning * into result;

  return result;
end;
$$;
