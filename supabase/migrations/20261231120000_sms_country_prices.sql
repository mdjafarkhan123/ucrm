-- Stage 10 Part 6: Countries & prices (`concept.pen` board `v6Jtu`, cards `R6mF2` and `dc8G7`).
--
-- One price list for every business. Each country row shows what Twilio charges Uplift, what businesses pay, the
-- margin, picture texts and the monthly number price, how many businesses use it, and its status. Selling prices
-- stay immutable versions in `communication_sms_retail_rates` and `communication_sms_number_retail_rates`, so a
-- text already sent keeps the price it was sent at. New here:
--   1. `communication_sms_twilio_prices`: Twilio's own cost per country, read by "Check Twilio prices". A check that
--      moves a cost keeps the old one, so the page can say "from $0.0468 to $0.0524" and what it did to the margin.
--   2. `communication_sms_countries`: a country Uplift doesn't offer (Jafar 2026-10-23: status Off). A business
--      can't ask for it; businesses already texting there keep it until each is turned off.
--   3. `communication_sms_price_list()` and `communication_sms_set_country_price(...)` for the tab and its pop-up.

-- 1. Twilio's cost ------------------------------------------------------------------------------------------------

create table public.communication_sms_twilio_prices (
  country_code text not null,
  kind text not null,
  number_type text not null,
  currency_code text not null default 'USD',
  cost_major numeric(14, 6) not null,
  previous_cost_major numeric(14, 6),
  cost_changed_at timestamptz,
  checked_at timestamptz not null default now(),
  primary key (country_code, kind, number_type),
  constraint communication_sms_twilio_prices_country_check check (country_code ~ '^[A-Z]{2}$'),
  constraint communication_sms_twilio_prices_kind_check check (kind in ('segment', 'number_month')),
  constraint communication_sms_twilio_prices_type_check
    check (number_type in ('local', 'mobile', 'national', 'toll_free', 'short_code')),
  constraint communication_sms_twilio_prices_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_twilio_prices_cost_check check (cost_major >= 0)
);

comment on table public.communication_sms_twilio_prices is
  'Stage 10 Part 6: Twilio''s cost to Uplift per country, read from Twilio''s Pricing API. Segment = the dearest carrier. Jafar-only truth.';

alter table public.communication_sms_twilio_prices enable row level security;
revoke all on table public.communication_sms_twilio_prices from anon, authenticated;

-- Records one check's answers. A cost that moved keeps the one before it and when it moved.
create or replace function public.communication_sms_record_twilio_prices(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  saved integer;
begin
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Prices must be a list.' using errcode = 'check_violation';
  end if;

  insert into public.communication_sms_twilio_prices as t (
    country_code, kind, number_type, currency_code, cost_major, checked_at
  )
  select r.country_code, r.kind, r.number_type, coalesce(r.currency_code, 'USD'), r.cost_major, now()
  from jsonb_to_recordset(p_rows) as r(
    country_code text, kind text, number_type text, currency_code text, cost_major numeric
  )
  on conflict (country_code, kind, number_type) do update
  set previous_cost_major = case when t.cost_major <> excluded.cost_major then t.cost_major else t.previous_cost_major end,
    cost_changed_at = case when t.cost_major <> excluded.cost_major then now() else t.cost_changed_at end,
    cost_major = excluded.cost_major,
    currency_code = excluded.currency_code,
    checked_at = excluded.checked_at;

  get diagnostics saved = row_count;
  return saved;
end;
$$;

revoke all on function public.communication_sms_record_twilio_prices(jsonb) from public, anon, authenticated;
grant execute on function public.communication_sms_record_twilio_prices(jsonb) to service_role;

-- 2. Countries Uplift doesn't offer ---------------------------------------------------------------------------

create table public.communication_sms_countries (
  country_code text primary key,
  offered boolean not null default true,
  changed_by_name text,
  changed_at timestamptz not null default now(),
  constraint communication_sms_countries_country_check check (country_code ~ '^[A-Z]{2}$'),
  constraint communication_sms_countries_name_check check (changed_by_name is null or char_length(changed_by_name) <= 200)
);

comment on table public.communication_sms_countries is
  'Stage 10 Part 6: a country Uplift stopped offering (offered = false). No row means offered.';

alter table public.communication_sms_countries enable row level security;
revoke all on table public.communication_sms_countries from anon, authenticated;

create or replace function public.communication_sms_set_country_offered(
  p_country_code text,
  p_offered boolean,
  p_actor_name text
) returns public.communication_sms_countries
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  country public.communication_sms_countries;
begin
  if p_country_code is null or p_country_code !~ '^[A-Z]{2}$' then
    raise exception 'Choose a country.' using errcode = 'check_violation';
  end if;

  insert into public.communication_sms_countries (country_code, offered, changed_by_name, changed_at)
  values (p_country_code, p_offered, p_actor_name, now())
  on conflict (country_code) do update
  set offered = excluded.offered, changed_by_name = excluded.changed_by_name, changed_at = excluded.changed_at
  returning * into country;
  return country;
end;
$$;

revoke all on function public.communication_sms_set_country_offered(text, boolean, text) from public, anon, authenticated;
grant execute on function public.communication_sms_set_country_offered(text, boolean, text) to service_role;

-- A business can't newly ask for a country Uplift doesn't offer. Its own country and the countries of numbers it
-- owns are still asked for automatically: those come with the number, not from a choice.
create or replace function public.communication_sms_request_destination(
  p_organization_id uuid,
  p_country_code text,
  p_actor uuid default null,
  p_is_home boolean default false
) returns public.communication_sms_destinations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  destination public.communication_sms_destinations;
begin
  if p_country_code is null or p_country_code !~ '^[A-Z]{2}$' then
    raise exception 'Choose a country.' using errcode = 'check_violation';
  end if;

  if not p_is_home
    and exists (
      select 1 from public.communication_sms_countries c
      where c.country_code = p_country_code and not c.offered
    )
    and not exists (
      select 1 from public.communication_sms_sender_identities s
      where s.organization_id = p_organization_id and s.country_code = p_country_code
        and s.lifecycle_state <> 'released'
    ) then
    raise exception 'Uplift doesn''t offer texting to that country.' using errcode = 'P0001';
  end if;

  insert into public.communication_sms_destinations (
    organization_id, country_code, is_home, requested_by
  ) values (
    p_organization_id, p_country_code, p_is_home, p_actor
  )
  on conflict (organization_id, country_code) do nothing
  returning * into destination;

  if destination.id is not null then
    insert into public.communication_sms_destination_events (organization_id, destination_id, event_kind, actor)
    values (p_organization_id, destination.id, 'requested', p_actor);
    return destination;
  end if;

  select d.* into destination
  from public.communication_sms_destinations d
  where d.organization_id = p_organization_id and d.country_code = p_country_code
  for update;

  if destination.status = 'off' then
    update public.communication_sms_destinations
    set status = 'setting_up', requested_by = p_actor, requested_at = now(),
      off_by = null, off_at = null, off_reason = null, business_message = null,
      is_home = is_home or p_is_home, updated_at = now()
    where id = destination.id
    returning * into destination;
    insert into public.communication_sms_destination_events (organization_id, destination_id, event_kind, actor)
    values (p_organization_id, destination.id, 'requested', p_actor);
  elsif p_is_home and not destination.is_home then
    update public.communication_sms_destinations
    set is_home = true, updated_at = now()
    where id = destination.id
    returning * into destination;
  end if;

  return destination;
end;
$$;

-- 3. The price list ---------------------------------------------------------------------------------------------

-- The number kind a business buys in a country: the one with a selling price, else the one Twilio prices, local
-- first. US and Canada also sell toll-free numbers, shown beside local.
create or replace function private.communication_sms_main_number_type(p_country text)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select t.number_type
  from (
    select n.number_type, 0 as source from public.communication_sms_number_retail_rates n
    where n.country_code = p_country and n.number_type <> 'toll_free'
    union all
    select p.number_type, 1 from public.communication_sms_twilio_prices p
    where p.country_code = p_country and p.kind = 'number_month' and p.number_type not in ('toll_free', 'short_code')
  ) t
  order by t.source, array_position(array['local', 'mobile', 'national'], t.number_type)
  limit 1;
$$;

revoke all on function private.communication_sms_main_number_type(text) from public, anon, authenticated;

create or replace function public.communication_sms_price_list()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with countries as (
    select destination as country from public.communication_sms_retail_rates
    union select country_code from public.communication_sms_number_retail_rates
    union select country_code from public.communication_sms_destinations
    union select country_code from public.communication_sms_twilio_prices
    union select country_code from public.communication_sms_countries
  ),
  listed as (
    select c.country, coalesce(private.communication_sms_main_number_type(c.country), 'local') as number_type
    from countries c
  ),
  built as (
    select r.country, jsonb_build_object(
      'country', r.country,
      'number_type', r.number_type,
      'toll_free', exists (
        select 1 from public.communication_sms_number_retail_rates n
        where n.country_code = r.country and n.number_type = 'toll_free'
      ),
      'offered', coalesce((select c.offered from public.communication_sms_countries c where c.country_code = r.country), true),
      'twilio', jsonb_build_object(
        'segment', (
          select jsonb_build_object('cost', p.cost_major, 'previous', p.previous_cost_major,
            'changed_at', p.cost_changed_at, 'checked_at', p.checked_at)
          from public.communication_sms_twilio_prices p
          where p.country_code = r.country and p.kind = 'segment'
          order by (p.number_type = r.number_type) desc, p.cost_major desc
          limit 1
        ),
        'number_month', (
          select jsonb_build_object('cost', p.cost_major, 'checked_at', p.checked_at)
          from public.communication_sms_twilio_prices p
          where p.country_code = r.country and p.kind = 'number_month' and p.number_type = r.number_type
        )
      ),
      'price', private.communication_sms_country_price(r.country),
      'segment_set_at', (
        select max(x.created_at) from public.communication_sms_retail_rates x
        where x.destination = r.country and x.message_unit = 'segment'
      ),
      'number', (
        select jsonb_build_object('monthly', n.monthly_rate_major, 'setup', n.setup_rate_major)
        from public.communication_sms_number_retail_rates n
        where n.country_code = r.country and n.number_type = r.number_type and n.effective_from <= now()
        order by n.effective_from desc limit 1
      ),
      'later', (
        select jsonb_build_object('segment', x.retail_rate_major, 'from', x.effective_from)
        from public.communication_sms_retail_rates x
        where x.destination = r.country and x.message_unit = 'segment' and x.sender_type = 'long_code'
          and x.effective_from > now()
        order by x.effective_from limit 1
      ),
      'using', (
        select count(*) from public.communication_sms_destinations d
        where d.country_code = r.country and d.status = 'ready'
      ),
      'asked', (
        select count(*) from public.communication_sms_destinations d
        where d.country_code = r.country and d.status = 'setting_up'
      )
    ) as row
    from listed r
  )
  select jsonb_build_object(
    'last_checked_at', (select max(p.checked_at) from public.communication_sms_twilio_prices p),
    'countries', coalesce(jsonb_agg(b.row order by b.country), '[]'::jsonb)
  )
  from built b;
$$;

comment on function public.communication_sms_price_list() is
  'Stage 10 Part 6: every country with a price, a Twilio cost, a request or an Off switch, for the Countries & prices tab.';

revoke all on function public.communication_sms_price_list() from public, anon, authenticated;
grant execute on function public.communication_sms_price_list() to service_role;

-- 4. Change a country's prices --------------------------------------------------------------------------------

-- Saves new price versions starting now or on a later date. A text segment is priced for local and mobile
-- numbers, and for toll-free ones where the country sells them; picture texts the same way where offered. A blank
-- price leaves that one as it is. Twilio's latest cost is kept beside each version.
create or replace function public.communication_sms_set_country_price(
  p_country_code text,
  p_segment numeric,
  p_mms numeric,
  p_number_month numeric,
  p_effective_from timestamptz,
  p_set_by uuid,
  p_actor_name text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  effective timestamptz := greatest(coalesce(p_effective_from, now()), now());
  v_note text := 'Countries & prices · ' || coalesce(nullif(trim(p_actor_name), ''), 'Uplift');
  v_number_type text := coalesce(private.communication_sms_main_number_type(p_country_code), 'local');
  segment_cost numeric;
  number_cost numeric;
  setup numeric;
  sender text;
  senders text[] := array['long_code'];
begin
  if p_country_code is null or p_country_code !~ '^[A-Z]{2}$' then
    raise exception 'Choose a country.' using errcode = 'check_violation';
  end if;
  if p_segment is null and p_mms is null and p_number_month is null then
    raise exception 'Type at least one price.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.communication_sms_number_retail_rates n
    where n.country_code = p_country_code and n.number_type = 'toll_free'
  ) then
    senders := senders || 'toll_free';
  end if;

  select p.cost_major into segment_cost
  from public.communication_sms_twilio_prices p
  where p.country_code = p_country_code and p.kind = 'segment'
  order by (p.number_type = v_number_type) desc, p.cost_major desc
  limit 1;

  foreach sender in array senders loop
    if p_segment is not null then
      perform public.communication_sms_set_retail_rate(
        p_country_code, sender, 'segment', p_segment, p_set_by, 'USD', segment_cost, effective, v_note
      );
    end if;
    if p_mms is not null then
      perform public.communication_sms_set_retail_rate(
        p_country_code, sender, 'mms', p_mms, p_set_by, 'USD',
        (select x.provider_cost_major from public.communication_sms_retail_rates x
          where x.destination = p_country_code and x.message_unit = 'mms' and x.provider_cost_major is not null
          order by x.created_at desc limit 1),
        effective, v_note
      );
    end if;
  end loop;

  if p_number_month is not null then
    select p.cost_major into number_cost
    from public.communication_sms_twilio_prices p
    where p.country_code = p_country_code and p.kind = 'number_month' and p.number_type = v_number_type;

    select n.setup_rate_major into setup
    from public.communication_sms_number_retail_rates n
    where n.country_code = p_country_code and n.number_type = v_number_type
    order by n.effective_from desc limit 1;

    insert into public.communication_sms_number_retail_rates (
      country_code, number_type, currency_code, monthly_rate_major, setup_rate_major,
      provider_monthly_cost_major, effective_from, set_by, note
    ) values (
      p_country_code, v_number_type, 'USD', p_number_month, coalesce(setup, 0), number_cost, effective, p_set_by, v_note
    );
  end if;

  return jsonb_build_object('country', p_country_code, 'effective_from', effective);
end;
$$;

comment on function public.communication_sms_set_country_price(text, numeric, numeric, numeric, timestamptz, uuid, text) is
  'Stage 10 Part 6: the Change price pop-up. New immutable price versions only; texts already sent keep theirs.';

revoke all on function public.communication_sms_set_country_price(text, numeric, numeric, numeric, timestamptz, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_set_country_price(text, numeric, numeric, numeric, timestamptz, uuid, text)
  to service_role;
