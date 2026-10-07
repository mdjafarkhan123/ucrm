-- Jafar Settings home (A2): each Settings section saves only its own fields. A null argument now keeps the
-- saved value, read under the same row lock as the write, so two sections saved at once cannot overwrite
-- each other with stale copies. Callers that pass every field behave exactly as before; the audit event
-- records the merged result that was actually stored.
begin;

CREATE OR REPLACE FUNCTION public.update_owner_settings(
  actor_email text,
  new_privacy_policy_url text,
  new_privacy_policy_version text,
  new_payment_instructions text,
  new_sender_display_name text,
  new_reply_to_address text,
  new_alert_recipient_emails text[]
)
 RETURNS public.platform_owner_settings
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $$
declare
  current record;
  before_state jsonb;
  after_state jsonb;
  updated public.platform_owner_settings;
begin
  if actor_email is null or char_length(trim(actor_email)) = 0 then
    raise exception 'An acting owner email is required to update settings.' using errcode = 'check_violation';
  end if;

  insert into public.platform_owner_settings (id)
  values (true)
  on conflict (id) do nothing;

  select privacy_policy_url, privacy_policy_version, payment_instructions,
    sender_display_name, reply_to_address, alert_recipient_emails
  into current
  from public.platform_owner_settings
  where id = true
  for update;

  before_state := jsonb_build_object(
    'privacy_policy_url', current.privacy_policy_url,
    'privacy_policy_version', current.privacy_policy_version,
    'payment_instructions', current.payment_instructions,
    'sender_display_name', current.sender_display_name,
    'reply_to_address', current.reply_to_address,
    'alert_recipient_emails', current.alert_recipient_emails
  );

  update public.platform_owner_settings
  set privacy_policy_url = coalesce(new_privacy_policy_url, current.privacy_policy_url),
    privacy_policy_version = coalesce(new_privacy_policy_version, current.privacy_policy_version),
    payment_instructions = coalesce(new_payment_instructions, current.payment_instructions),
    sender_display_name = coalesce(new_sender_display_name, current.sender_display_name),
    reply_to_address = coalesce(new_reply_to_address, current.reply_to_address),
    alert_recipient_emails = coalesce(new_alert_recipient_emails, current.alert_recipient_emails)
  where id = true
  returning * into updated;

  after_state := jsonb_build_object(
    'privacy_policy_url', updated.privacy_policy_url,
    'privacy_policy_version', updated.privacy_policy_version,
    'payment_instructions', updated.payment_instructions,
    'sender_display_name', updated.sender_display_name,
    'reply_to_address', updated.reply_to_address,
    'alert_recipient_emails', updated.alert_recipient_emails
  );

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor_email, 'owner_settings.updated', 'platform_owner_settings', 'singleton', before_state, after_state
  );

  return updated;
end;
$$;

commit;
