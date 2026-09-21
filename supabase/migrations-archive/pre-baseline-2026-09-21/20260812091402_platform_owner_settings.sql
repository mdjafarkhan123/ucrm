-- Platform Owner Settings: a single global configuration row used by the public
-- onboarding flow and outgoing owner/contractor emails (payment instructions, privacy
-- policy link/version, sender display name/reply-to, and the list of emails that get
-- owner alerts). Singleton via a boolean primary key that can only ever be `true` -- the
-- table can never hold more than one row without a separate uniqueness trigger.

create table public.platform_owner_settings (
  id boolean primary key default true check (id),
  privacy_policy_url text not null default '',
  privacy_policy_version text not null default '',
  payment_instructions text not null default '',
  sender_display_name text not null default '',
  reply_to_address text not null default '',
  alert_recipient_emails text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger platform_owner_settings_set_updated_at
before update on public.platform_owner_settings
for each row execute function public.set_updated_at();

alter table public.platform_owner_settings enable row level security;

revoke all on public.platform_owner_settings from anon, authenticated;
grant select, insert, update on public.platform_owner_settings to service_role;

-- Atomic update + audit: reuses the existing platform_owner_audit_events history table
-- (same one package publish/edit/retire and onboarding actions already write to) so a
-- settings change can never happen without a matching before/after history row. Also
-- upserts the singleton row first, in case this is called before any GET has created it.
create or replace function public.update_owner_settings(
  actor_email text,
  new_privacy_policy_url text,
  new_privacy_policy_version text,
  new_payment_instructions text,
  new_sender_display_name text,
  new_reply_to_address text,
  new_alert_recipient_emails text[]
)
returns public.platform_owner_settings
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
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
  after_state := jsonb_build_object(
    'privacy_policy_url', new_privacy_policy_url,
    'privacy_policy_version', new_privacy_policy_version,
    'payment_instructions', new_payment_instructions,
    'sender_display_name', new_sender_display_name,
    'reply_to_address', new_reply_to_address,
    'alert_recipient_emails', new_alert_recipient_emails
  );

  update public.platform_owner_settings
  set privacy_policy_url = new_privacy_policy_url,
    privacy_policy_version = new_privacy_policy_version,
    payment_instructions = new_payment_instructions,
    sender_display_name = new_sender_display_name,
    reply_to_address = new_reply_to_address,
    alert_recipient_emails = new_alert_recipient_emails
  where id = true
  returning * into updated;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor_email, 'owner_settings.updated', 'platform_owner_settings', 'singleton', before_state, after_state
  );

  return updated;
end;
$$;

revoke all on function public.update_owner_settings(text, text, text, text, text, text, text[])
  from public, anon, authenticated;
grant execute on function public.update_owner_settings(text, text, text, text, text, text, text[])
  to service_role;
