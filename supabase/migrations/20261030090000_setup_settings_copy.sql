-- Client onboarding C5: accepted setup answers fill the matching CRM settings (plan §4, §10 journey 6).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §4, Jafar's choices of 2026-10-05 (C5):
-- accepting a section copies its accepted built-in answers at once; the newest word from the business wins, so a
-- setting the owner changed in Settings after the answer reached Uplift is kept; copying the same answers again
-- changes nothing; the client's setup time zone and currency count as confirmed, but currency never changes once
-- a quote has been sent. Industry reference: Kubernetes "kubectl apply" keeps the configuration it last applied
-- and leaves alone a field someone has changed by hand since (three-way merge).
--
-- Which answers are accepted, and what each becomes in settings, is worked out in the app (ADR 0005); this
-- function decides, setting by setting and under one lock, whether to write it.
--
-- 1. organization_setup_settings_copies keeps, per setting, the value setup last copied and how the last copy
--    went, so a repeat changes nothing and the Setup tab can say what happened.
-- 2. public.owner_copy_setup_settings applies a set of accepted values.

-- 1. What setup last copied ------------------------------------------------------------------------------------

create table public.organization_setup_settings_copies (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  setting_key text not null check (
    setting_key in ('name', 'trade', 'phone', 'address', 'address_is_public', 'timezone', 'currency_code', 'hours')
  ),
  -- The value setup last wrote into the setting, or found already there; null while setup has never set it.
  copied_value jsonb,
  -- The accepted value at the last copy, and what happened to it.
  proposed_value jsonb not null,
  outcome text not null check (outcome in ('copied', 'same', 'kept', 'locked')),
  checked_at timestamptz not null default now(),
  primary key (organization_id, setting_key)
);

comment on table public.organization_setup_settings_copies is
  'Client onboarding C5: per CRM setting, the value setup last copied into it and how the last copy went (copied, already the same, kept the owner''s newer change, or currency locked by a sent quote). Only the service role reads or writes it, through public.owner_copy_setup_settings.';

alter table public.organization_setup_settings_copies enable row level security;
revoke all on table public.organization_setup_settings_copies from public, anon, authenticated;
grant all on table public.organization_setup_settings_copies to service_role;

-- 2. Copying accepted values ------------------------------------------------------------------------------------

-- `proposals` maps a setting key to {"value": <jsonb>, "told_at": <timestamptz>}: the accepted value and when the
-- business told Uplift it (the send that first held it, or when Uplift recorded its answer to a help request).
-- Values: name, trade, phone and timezone and currency_code are strings; address_is_public a boolean; address
-- {"address_line1", "address_line2", "city", "region", "postal_code", "country_code"}; hours {"mode":
-- "appointment_only"} or {"mode": "weekly", "rows": [{weekday, period_index, is_open, is_open_24h, opens_at,
-- closes_at}]} with times as HH:MM, ordered by weekday then period.
--
-- A setting is written when it is still empty, still holds what setup last copied, or the business told Uplift
-- after the last time a person saved that part of Settings. It is left alone when the accepted value is what
-- setup last copied: the client has said nothing new, so whatever is in Settings stands.
create function public.owner_copy_setup_settings(
  target_organization_id uuid,
  proposals jsonb,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  settings_row public.organization_settings;
  current_name text;
  setting text;
  proposal jsonb;
  proposed jsonb;
  told_at timestamptz;
  current_value jsonb;
  previous public.organization_setup_settings_copies;
  edited_at timestamptz;
  decision text;
  results jsonb := '{}';
  profile_changed text[] := '{}';
  hours_changed boolean := false;
  before_state jsonb := '{}';
  after_state jsonb := '{}';
  quote_sent boolean;
begin
  if target_organization_id is null or clean_email is null or jsonb_typeof(proposals) is distinct from 'object' then
    raise exception 'Say which client, what to copy, and who is copying it.' using errcode = 'check_violation';
  end if;

  -- Takes turns with the Settings pages, which lock the same row to save.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;
  if settings_row.organization_id is null then
    raise exception 'This client''s settings were not found.' using errcode = 'no_data_found';
  end if;

  select organization.name into current_name
  from public.organizations as organization
  where organization.id = target_organization_id;

  select exists (
    select 1 from public.quotes
    where organization_id = target_organization_id
      and (current_published_version_id is not null or sent_at is not null)
  ) into quote_sent;

  for setting in
    select proposal_key from jsonb_object_keys(proposals) as proposal_key
    where proposal_key in ('name', 'trade', 'phone', 'address', 'address_is_public', 'timezone', 'currency_code', 'hours')
    order by proposal_key
  loop
    proposal := proposals -> setting;
    proposed := proposal -> 'value';
    told_at := (proposal ->> 'told_at')::timestamptz;
    if proposed is null or proposed = 'null'::jsonb or told_at is null then
      continue;
    end if;

    -- What the setting holds now, in the proposal's shape. A time zone or currency nobody confirmed is only the
    -- account's starting default, and hours never set are nothing: both count as empty.
    current_value := case setting
      when 'name' then to_jsonb(current_name)
      when 'trade' then to_jsonb(settings_row.trade)
      when 'phone' then to_jsonb(settings_row.phone)
      when 'address' then jsonb_build_object(
        'address_line1', settings_row.address_line1,
        'address_line2', settings_row.address_line2,
        'city', settings_row.city,
        'region', settings_row.region,
        'postal_code', settings_row.postal_code,
        'country_code', settings_row.country_code
      )
      when 'address_is_public' then to_jsonb(settings_row.address_is_public)
      when 'timezone' then
        case when settings_row.timezone_confirmed_at is not null then to_jsonb(settings_row.timezone) end
      when 'currency_code' then
        case when settings_row.currency_confirmed_at is not null then to_jsonb(settings_row.currency_code) end
      when 'hours' then
        case settings_row.hours_mode
          when 'appointment_only' then jsonb_build_object('mode', 'appointment_only')
          when 'weekly' then jsonb_build_object('mode', 'weekly', 'rows', coalesce((
            select jsonb_agg(jsonb_build_object(
              'weekday', hours.weekday,
              'period_index', hours.period_index,
              'is_open', hours.is_open,
              'is_open_24h', hours.is_open_24h,
              'opens_at', to_char(hours.opens_at, 'HH24:MI'),
              'closes_at', to_char(hours.closes_at, 'HH24:MI')
            ) order by hours.weekday, hours.period_index)
            from public.organization_business_hours as hours
            where hours.organization_id = target_organization_id
          ), '[]'::jsonb))
        end
    end;
    if current_value = 'null'::jsonb or current_value = jsonb_build_object(
      'address_line1', null, 'address_line2', null, 'city', null, 'region', null, 'postal_code', null,
      'country_code', null
    ) then
      current_value := null;
    end if;

    -- When a person last saved the part of Settings this setting lives in; setup's own copies do not count.
    edited_at := case
      when setting = 'hours' then
        case when settings_row.hours_updated_by is not null then settings_row.hours_updated_at end
      else
        case when settings_row.profile_updated_by is not null then settings_row.profile_updated_at end
    end;

    select * into previous
    from public.organization_setup_settings_copies as copies
    where copies.organization_id = target_organization_id and copies.setting_key = setting;

    if current_value = proposed then
      decision := 'same';
    elsif previous.copied_value = proposed then
      decision := 'kept';
    elsif current_value is null
      or current_value = previous.copied_value
      or edited_at is null
      or told_at > edited_at then
      decision := case when setting = 'currency_code' and quote_sent
        and proposed is distinct from to_jsonb(settings_row.currency_code) then 'locked' else 'copied' end;
    else
      decision := 'kept';
    end if;

    -- The currency the account already uses, now confirmed by the client, is no change to it.
    if decision = 'copied' and setting = 'currency_code' and settings_row.currency_confirmed_at is null
      and proposed = to_jsonb(settings_row.currency_code) then
      decision := 'same';
      update public.organization_settings set currency_confirmed_at = now()
      where organization_id = target_organization_id;
      profile_changed := profile_changed || array['currency_confirmed'];
    end if;
    if decision = 'copied' and setting = 'timezone' and settings_row.timezone_confirmed_at is null
      and proposed = to_jsonb(settings_row.timezone) then
      decision := 'same';
      update public.organization_settings set timezone_confirmed_at = now()
      where organization_id = target_organization_id;
      profile_changed := profile_changed || array['timezone_confirmed'];
    end if;

    if decision = 'copied' then
      before_state := before_state || jsonb_build_object(setting, current_value);
      after_state := after_state || jsonb_build_object(setting, proposed);

      if setting = 'name' then
        if char_length(btrim(proposed #>> '{}')) not between 2 and 120 then
          raise exception 'Business name must be between 2 and 120 characters.' using errcode = 'check_violation';
        end if;
        update public.organizations set name = btrim(proposed #>> '{}') where id = target_organization_id;
        profile_changed := profile_changed || array['name'];
      elsif setting = 'trade' then
        update public.organization_settings set trade = nullif(btrim(proposed #>> '{}'), '')
        where organization_id = target_organization_id;
        profile_changed := profile_changed || array['trade'];
      elsif setting = 'phone' then
        update public.organization_settings set phone = nullif(btrim(proposed #>> '{}'), '')
        where organization_id = target_organization_id;
        profile_changed := profile_changed || array['phone'];
      elsif setting = 'address' then
        if proposed ->> 'country_code' !~ '^[A-Z]{2}$' then
          raise exception 'Choose a country from the list.' using errcode = 'check_violation';
        end if;
        update public.organization_settings
        set address_line1 = nullif(btrim(proposed ->> 'address_line1'), ''),
            address_line2 = nullif(btrim(proposed ->> 'address_line2'), ''),
            city = nullif(btrim(proposed ->> 'city'), ''),
            region = nullif(btrim(proposed ->> 'region'), ''),
            postal_code = nullif(btrim(proposed ->> 'postal_code'), ''),
            country_code = proposed ->> 'country_code'
        where organization_id = target_organization_id;
        profile_changed := profile_changed
          || array['address_line1', 'address_line2', 'city', 'region', 'postal_code', 'country_code'];
      elsif setting = 'address_is_public' then
        update public.organization_settings set address_is_public = (proposed #>> '{}')::boolean
        where organization_id = target_organization_id;
        profile_changed := profile_changed || array['address_is_public'];
      elsif setting = 'timezone' then
        if not exists (select 1 from pg_catalog.pg_timezone_names where name = proposed #>> '{}') then
          raise exception 'Choose a valid timezone.' using errcode = 'check_violation';
        end if;
        update public.organization_settings
        set timezone = proposed #>> '{}', timezone_confirmed_at = now()
        where organization_id = target_organization_id;
        profile_changed := profile_changed || array['timezone', 'timezone_confirmed'];
      elsif setting = 'currency_code' then
        update public.organization_settings
        set currency_code = proposed #>> '{}', currency_confirmed_at = now()
        where organization_id = target_organization_id;
        profile_changed := profile_changed || array['currency_code', 'currency_confirmed'];
      elsif setting = 'hours' then
        if proposed ->> 'mode' not in ('weekly', 'appointment_only') then
          raise exception 'Choose weekly hours or appointment only.' using errcode = 'check_violation';
        end if;
        delete from public.organization_business_hours where organization_id = target_organization_id;
        if proposed ->> 'mode' = 'weekly' then
          insert into public.organization_business_hours (
            organization_id, weekday, period_index, is_open, is_open_24h, opens_at, closes_at
          )
          select
            target_organization_id,
            (item ->> 'weekday')::smallint,
            (item ->> 'period_index')::smallint,
            (item ->> 'is_open')::boolean,
            (item ->> 'is_open_24h')::boolean,
            nullif(item ->> 'opens_at', '')::time,
            nullif(item ->> 'closes_at', '')::time
          from jsonb_array_elements(proposed -> 'rows') as item;
          if (
            select count(distinct weekday) from public.organization_business_hours
            where organization_id = target_organization_id
          ) <> 7 then
            raise exception 'Business hours must cover every day of the week.' using errcode = 'check_violation';
          end if;
        end if;
        update public.organization_settings set hours_mode = proposed ->> 'mode'
        where organization_id = target_organization_id;
        hours_changed := true;
      end if;
    end if;

    insert into public.organization_setup_settings_copies (
      organization_id, setting_key, copied_value, proposed_value, outcome
    ) values (
      target_organization_id, setting,
      case when decision in ('copied', 'same') then proposed else previous.copied_value end,
      proposed, decision
    )
    on conflict (organization_id, setting_key) do update
    set copied_value = excluded.copied_value,
        proposed_value = excluded.proposed_value,
        outcome = excluded.outcome,
        checked_at = now();

    results := results || jsonb_build_object(setting, decision);
  end loop;

  -- A copy is a save nobody made in Settings: it moves the revision on, so a Settings page left open is told to
  -- reload rather than saving over it, and it names no person as the last editor.
  if cardinality(profile_changed) > 0 then
    update public.organization_settings
    set profile_revision = profile_revision + 1, profile_updated_by = null, profile_updated_at = now()
    where organization_id = target_organization_id;
    insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
    values (target_organization_id, 'profile', profile_changed, null);
  end if;
  if hours_changed then
    update public.organization_settings
    set hours_revision = hours_revision + 1, hours_updated_by = null, hours_updated_at = now()
    where organization_id = target_organization_id;
    insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
    values (
      target_organization_id, 'hours',
      case when settings_row.hours_mode is distinct from after_state #>> '{hours,mode}'
        then array['hours_mode', 'hours'] else array['hours'] end,
      null
    );
  end if;

  if after_state <> '{}'::jsonb then
    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, before_state, after_state
    ) values (
      clean_email, 'organization.setup_settings_copied', 'organization', target_organization_id::text,
      before_state, after_state
    );
  end if;

  return jsonb_build_object('status', 'saved', 'results', results);
end;
$$;

comment on function public.owner_copy_setup_settings(uuid, jsonb, text) is
  'Client onboarding C5: copies a client''s accepted setup values into their CRM settings, setting by setting, keeping any newer change the owner made in Settings. A repeat changes nothing. Service role only.';

revoke all on function public.owner_copy_setup_settings(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.owner_copy_setup_settings(uuid, jsonb, text) to service_role;
