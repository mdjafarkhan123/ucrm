-- Communications A2 / Stage 3C data layer: contractor-safe number preferences and SMS compliance settings.
--
-- Two contractor-owned, low-risk preferences that the Phone & SMS settings page needs, following HighLevel's
-- proven model. Provisioning and release of numbers stay platform-owner (provider) actions; the only number
-- writes a contractor makes here are naming a number and choosing the default sending number. Compliance
-- settings mirror HighLevel's SMS Compliance tab: auto-appended opt-out language, sender identification, and how
-- often they are re-added. All writes go only through the security-definer commands below; the tables stay
-- server-owned (RLS on, no client policies), read by the checked contractor API.

-- ---------------------------------------------------------------------------------------------------------------
-- Numbers: friendly name + one default sending number per organization.
-- ---------------------------------------------------------------------------------------------------------------

alter table public.communication_sms_sender_identities
  add column is_default_sender boolean not null default false;

comment on column public.communication_sms_sender_identities.is_default_sender is
  'The organization''s chosen default outbound SMS sending number. At most one per organization; a contractor '
  'owner/admin sets it through communication_sms_set_default_sender.';

-- At most one default number per organization. A released number can never remain the default.
create unique index communication_sms_sender_identities_one_default_idx
  on public.communication_sms_sender_identities (organization_id)
  where is_default_sender and lifecycle_state <> 'released';

-- Rename a number's friendly label. Contractor-safe: local metadata only, never a provider action.
create or replace function public.communication_sms_rename_sender(
  p_organization_id uuid,
  p_sender_id uuid,
  p_display_name text,
  p_actor uuid
) returns public.communication_sms_sender_identities
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  sender public.communication_sms_sender_identities;
  cleaned text;
begin
  if p_actor is null then
    raise exception 'a number change must record who made it' using errcode = 'P0001';
  end if;
  cleaned := nullif(btrim(p_display_name), '');
  if cleaned is not null and char_length(cleaned) > 60 then
    raise exception 'a number name must be 60 characters or fewer' using errcode = 'P0001';
  end if;

  select * into sender
  from public.communication_sms_sender_identities
  where id = p_sender_id and organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'number not found' using errcode = 'P0001';
  end if;
  if sender.lifecycle_state = 'released' then
    raise exception 'a released number can no longer be changed' using errcode = 'P0001';
  end if;

  update public.communication_sms_sender_identities
  set display_name = cleaned,
      updated_at = now()
  where id = sender.id
  returning * into sender;

  return sender;
end;
$$;

-- Choose the organization's default sending number. Only a live, SMS-capable number can be the default; the
-- previous default (if any) is cleared in the same transaction so the one-default index always holds.
create or replace function public.communication_sms_set_default_sender(
  p_organization_id uuid,
  p_sender_id uuid,
  p_actor uuid
) returns public.communication_sms_sender_identities
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  sender public.communication_sms_sender_identities;
begin
  if p_actor is null then
    raise exception 'a number change must record who made it' using errcode = 'P0001';
  end if;

  select * into sender
  from public.communication_sms_sender_identities
  where id = p_sender_id and organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'number not found' using errcode = 'P0001';
  end if;
  if sender.lifecycle_state <> 'ready' then
    raise exception 'only a ready number can be made the default sending number' using errcode = 'P0001';
  end if;
  if not sender.capable_sms then
    raise exception 'the default sending number must be able to send SMS' using errcode = 'P0001';
  end if;

  update public.communication_sms_sender_identities
  set is_default_sender = false, updated_at = now()
  where organization_id = p_organization_id
    and is_default_sender
    and id <> sender.id;

  update public.communication_sms_sender_identities
  set is_default_sender = true, updated_at = now()
  where id = sender.id
  returning * into sender;

  return sender;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Compliance settings: opt-out language, sender identification and their re-insertion interval.
-- ---------------------------------------------------------------------------------------------------------------

create table public.communication_sms_compliance_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  -- When enabled, outbound SMS gets opt-out language appended if it is missing. Null text means the system
  -- default wording is used; a contractor may store their own.
  opt_out_enabled boolean not null default true,
  opt_out_text text,
  -- When enabled, outbound SMS gets sender identification appended if it is missing.
  sender_info_enabled boolean not null default true,
  sender_info_text text,
  -- How often opt-out/sender wording is re-added to an ongoing conversation, in days (HighLevel: 1-60).
  periodic_reinsert_days integer not null default 30,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_compliance_settings_opt_out_text_check
    check (opt_out_text is null or char_length(btrim(opt_out_text)) between 1 and 320),
  constraint communication_sms_compliance_settings_sender_info_text_check
    check (sender_info_text is null or char_length(btrim(sender_info_text)) between 1 and 320),
  constraint communication_sms_compliance_settings_reinsert_days_check
    check (periodic_reinsert_days between 1 and 60)
);

comment on table public.communication_sms_compliance_settings is
  'Per-organization SMS compliance preferences (opt-out language, sender identification and re-insertion '
  'interval), following HighLevel''s SMS Compliance tab. One row per organization; a missing row means defaults. '
  'Server-owned: written only through communication_sms_set_compliance_settings.';

-- Save the organization's compliance settings. Upsert so the first save creates the row and later saves update
-- it. A disabled toggle keeps any stored custom text; enabling with no custom text falls back to the default.
create or replace function public.communication_sms_set_compliance_settings(
  p_organization_id uuid,
  p_opt_out_enabled boolean,
  p_opt_out_text text,
  p_sender_info_enabled boolean,
  p_sender_info_text text,
  p_periodic_reinsert_days integer,
  p_actor uuid
) returns public.communication_sms_compliance_settings
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings public.communication_sms_compliance_settings;
  opt_out_clean text;
  sender_info_clean text;
begin
  if p_actor is null then
    raise exception 'a compliance change must record who made it' using errcode = 'P0001';
  end if;
  if p_opt_out_enabled is null or p_sender_info_enabled is null then
    raise exception 'the compliance toggles are required' using errcode = 'P0001';
  end if;
  if p_periodic_reinsert_days is null or p_periodic_reinsert_days < 1 or p_periodic_reinsert_days > 60 then
    raise exception 'the re-insertion interval must be between 1 and 60 days' using errcode = 'P0001';
  end if;

  opt_out_clean := nullif(btrim(p_opt_out_text), '');
  sender_info_clean := nullif(btrim(p_sender_info_text), '');
  if opt_out_clean is not null and char_length(opt_out_clean) > 320 then
    raise exception 'the opt-out wording is too long' using errcode = 'P0001';
  end if;
  if sender_info_clean is not null and char_length(sender_info_clean) > 320 then
    raise exception 'the sender information is too long' using errcode = 'P0001';
  end if;

  insert into public.communication_sms_compliance_settings (
    organization_id, opt_out_enabled, opt_out_text, sender_info_enabled, sender_info_text,
    periodic_reinsert_days, updated_by, updated_at
  ) values (
    p_organization_id, p_opt_out_enabled, opt_out_clean, p_sender_info_enabled, sender_info_clean,
    p_periodic_reinsert_days, p_actor, now()
  )
  on conflict (organization_id) do update
  set opt_out_enabled = excluded.opt_out_enabled,
      opt_out_text = excluded.opt_out_text,
      sender_info_enabled = excluded.sender_info_enabled,
      sender_info_text = excluded.sender_info_text,
      periodic_reinsert_days = excluded.periodic_reinsert_days,
      updated_by = excluded.updated_by,
      updated_at = now()
  returning * into settings;

  return settings;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Access: tables stay server-owned; only the checked API (service_role) reads, and only the commands write.
-- ---------------------------------------------------------------------------------------------------------------

alter table public.communication_sms_compliance_settings enable row level security;

revoke all on table public.communication_sms_compliance_settings from public, anon, authenticated;
revoke all on table public.communication_sms_compliance_settings from service_role;
grant select on table public.communication_sms_compliance_settings to service_role;

revoke all on function public.communication_sms_rename_sender(uuid, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_rename_sender(uuid, uuid, text, uuid) to service_role;

revoke all on function public.communication_sms_set_default_sender(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_set_default_sender(uuid, uuid, uuid) to service_role;

revoke all on function public.communication_sms_set_compliance_settings(uuid, boolean, text, boolean, text, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_set_compliance_settings(uuid, boolean, text, boolean, text, integer, uuid)
  to service_role;
