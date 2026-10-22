-- Stage 10 Part 2 (docs/global-sms-behavior-contract.md): a business buys a texting number, the GoHighLevel way.
--
-- 1. Number selling prices. Jafar's monthly and setup price per country and number kind, versioned like the message
--    retail rates (communication_sms_retail_rates): a change is a new version, never a rewrite, and an order keeps
--    the version it was priced at.
-- 2. Number orders. One row per purchase attempt, keyed by the browser's idempotency key, so a double press, a
--    retry or a resume after a dropped connection reaches the same order instead of buying a second number. The
--    order holds the money first (reserved on the credit account), is charged only once Twilio confirms the
--    number is ours, and releases the hold if Twilio definitely refuses.
-- 3. Sender identities learn their number kind and Twilio's number SID, so a bought number can later be released.

-- 1. Number selling prices ------------------------------------------------------------------------------------------

create table public.communication_sms_number_retail_rates (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  number_type text not null,
  currency_code text not null default 'USD',
  monthly_rate_major numeric(12, 2) not null,
  setup_rate_major numeric(12, 2) not null default 0,
  provider_monthly_cost_major numeric(14, 6),
  provider_setup_cost_major numeric(14, 6),
  effective_from timestamptz not null default now(),
  set_by uuid not null,
  note text,
  created_at timestamptz not null default now(),
  constraint communication_sms_number_retail_rates_country_check check (country_code ~ '^[A-Z]{2}$'),
  constraint communication_sms_number_retail_rates_type_check
    check (number_type in ('local', 'mobile', 'national', 'toll_free')),
  constraint communication_sms_number_retail_rates_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_number_retail_rates_monthly_check check (monthly_rate_major > 0),
  constraint communication_sms_number_retail_rates_setup_check check (setup_rate_major >= 0),
  constraint communication_sms_number_retail_rates_cost_check check (
    (provider_monthly_cost_major is null or provider_monthly_cost_major >= 0)
    and (provider_setup_cost_major is null or provider_setup_cost_major >= 0)
  ),
  constraint communication_sms_number_retail_rates_note_check check (note is null or char_length(note) <= 2000),
  constraint communication_sms_number_retail_rates_version_key
    unique (country_code, number_type, currency_code, effective_from)
);

alter table public.communication_sms_number_retail_rates enable row level security;
revoke all on table public.communication_sms_number_retail_rates from anon, authenticated;

create or replace function public.communication_sms_effective_number_rate(
  p_country_code text,
  p_number_type text,
  p_currency_code text default 'USD',
  p_at timestamptz default now()
)
returns public.communication_sms_number_retail_rates
language sql
stable security definer
set search_path to 'pg_catalog', 'public'
as $$
  select r.*
  from public.communication_sms_number_retail_rates r
  where r.country_code = p_country_code
    and r.number_type = p_number_type
    and r.currency_code = coalesce(p_currency_code, 'USD')
    and r.effective_from <= p_at
  order by r.effective_from desc
  limit 1;
$$;

create or replace function public.communication_sms_set_number_rate(
  p_country_code text,
  p_number_type text,
  p_monthly_rate_major numeric,
  p_set_by uuid,
  p_setup_rate_major numeric default 0,
  p_currency_code text default 'USD',
  p_provider_monthly_cost_major numeric default null,
  p_provider_setup_cost_major numeric default null,
  p_effective_from timestamptz default null,
  p_note text default null
)
returns public.communication_sms_number_retail_rates
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  rate public.communication_sms_number_retail_rates;
  effective timestamptz := coalesce(p_effective_from, now());
begin
  if effective < now() then
    raise exception 'a number price takes effect now or in the future, never retroactively'
      using errcode = 'P0001';
  end if;

  insert into public.communication_sms_number_retail_rates (
    country_code, number_type, currency_code, monthly_rate_major, setup_rate_major,
    provider_monthly_cost_major, provider_setup_cost_major, effective_from, set_by, note
  ) values (
    p_country_code, p_number_type, coalesce(p_currency_code, 'USD'), p_monthly_rate_major,
    coalesce(p_setup_rate_major, 0), p_provider_monthly_cost_major, p_provider_setup_cost_major, effective,
    p_set_by, p_note
  )
  returning * into rate;

  return rate;
end;
$$;

-- 3. Sender identities: number kind and Twilio's SID -----------------------------------------------------------------

alter table public.communication_sms_sender_identities
  add column number_type text,
  add column provider_phone_number_sid text,
  add constraint communication_sms_sender_identities_number_type_check
    check (number_type is null or number_type in ('local', 'mobile', 'national', 'toll_free')),
  add constraint communication_sms_sender_identities_provider_sid_check
    check (provider_phone_number_sid is null or provider_phone_number_sid ~ '^PN[0-9A-Fa-f]{32}$');

-- 2. Number orders ----------------------------------------------------------------------------------------------------

create table public.communication_sms_number_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  idempotency_key text not null,
  phone_number text not null,
  country_code text not null,
  number_type text not null,
  capable_sms boolean not null,
  capable_mms boolean not null,
  capable_voice boolean not null,
  locality text,
  region text,
  address_requirement text not null default 'none',
  bundle_sid text,
  address_sid text,
  number_rate_id uuid not null references public.communication_sms_number_retail_rates(id) on delete restrict,
  currency_code text not null,
  monthly_minor bigint not null,
  setup_minor bigint not null,
  charge_minor bigint not null,
  state text not null default 'reserved',
  provider_phone_number_sid text,
  sender_identity_id uuid,
  failure_code text,
  requested_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  purchased_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  constraint communication_sms_number_orders_org_id_key unique (organization_id, id),
  constraint communication_sms_number_orders_idempotency_key unique (organization_id, idempotency_key),
  constraint communication_sms_number_orders_idempotency_check
    check (char_length(trim(idempotency_key)) between 8 and 200),
  constraint communication_sms_number_orders_phone_check check (phone_number ~ '^\+[1-9][0-9]{7,14}$'),
  constraint communication_sms_number_orders_country_check check (country_code ~ '^[A-Z]{2}$'),
  constraint communication_sms_number_orders_type_check
    check (number_type in ('local', 'mobile', 'national', 'toll_free')),
  constraint communication_sms_number_orders_place_check check (
    (locality is null or char_length(locality) <= 200) and (region is null or char_length(region) <= 200)
  ),
  constraint communication_sms_number_orders_address_requirement_check
    check (address_requirement in ('none', 'any', 'local', 'foreign')),
  constraint communication_sms_number_orders_bundle_check
    check (bundle_sid is null or bundle_sid ~ '^BU[0-9A-Fa-f]{32}$'),
  constraint communication_sms_number_orders_address_check
    check (address_sid is null or address_sid ~ '^AD[0-9A-Fa-f]{32}$'),
  constraint communication_sms_number_orders_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_number_orders_amount_check check (
    monthly_minor > 0 and setup_minor >= 0 and charge_minor = monthly_minor + setup_minor
  ),
  constraint communication_sms_number_orders_state_check
    check (state in ('reserved', 'purchasing', 'purchased', 'completed', 'failed')),
  constraint communication_sms_number_orders_provider_sid_check
    check (provider_phone_number_sid is null or provider_phone_number_sid ~ '^PN[0-9A-Fa-f]{32}$'),
  constraint communication_sms_number_orders_failure_check
    check (failure_code is null or failure_code ~ '^[a-z][a-z0-9_]{1,99}$'),
  -- Owning a number and being charged for it go together: once Twilio confirms, the SID is on record; a failed
  -- order never owns one; a completed order has its sender.
  constraint communication_sms_number_orders_lifecycle_check check (
    (state in ('reserved', 'purchasing') and provider_phone_number_sid is null and purchased_at is null)
    or (state = 'purchased' and provider_phone_number_sid is not null and purchased_at is not null)
    or (state = 'completed' and provider_phone_number_sid is not null and purchased_at is not null
        and sender_identity_id is not null and completed_at is not null)
    or (state = 'failed' and provider_phone_number_sid is null and failure_code is not null and failed_at is not null)
  ),
  constraint communication_sms_number_orders_sender_fk foreign key (organization_id, sender_identity_id)
    references public.communication_sms_sender_identities(organization_id, id) on delete restrict
);

-- Only one business at a time can be buying a given number.
create unique index communication_sms_number_orders_open_number_key
  on public.communication_sms_number_orders (phone_number)
  where state in ('reserved', 'purchasing');

create index communication_sms_number_orders_org_created_idx
  on public.communication_sms_number_orders (organization_id, created_at desc, id desc);

create index communication_sms_number_orders_rate_idx
  on public.communication_sms_number_orders (number_rate_id);

create index communication_sms_number_orders_sender_idx
  on public.communication_sms_number_orders (organization_id, sender_identity_id)
  where sender_identity_id is not null;

alter table public.communication_sms_number_orders enable row level security;
revoke all on table public.communication_sms_number_orders from anon, authenticated;

-- Open an order and hold its first charge (first month + setup) on the bought balance. Promotional credit pays for
-- messages only; a number is a real monthly cost. Replaying the same idempotency key returns the existing order
-- untouched, whatever state it reached.
create or replace function public.communication_sms_open_number_order(
  p_organization_id uuid,
  p_actor uuid,
  p_idempotency_key text,
  p_phone_number text,
  p_country_code text,
  p_number_type text,
  p_capable_sms boolean,
  p_capable_mms boolean,
  p_capable_voice boolean,
  p_locality text default null,
  p_region text default null,
  p_address_requirement text default 'none',
  p_bundle_sid text default null,
  p_address_sid text default null
)
returns public.communication_sms_number_orders
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  existing public.communication_sms_number_orders;
  created public.communication_sms_number_orders;
  rate public.communication_sms_number_retail_rates;
  account_currency text;
  settled bigint;
  reserved bigint;
  v_monthly bigint;
  v_setup bigint;
begin
  select * into existing
  from public.communication_sms_number_orders o
  where o.organization_id = p_organization_id and o.idempotency_key = p_idempotency_key;
  if found then
    return existing;
  end if;

  if not p_capable_sms then
    raise exception 'number_cannot_text' using errcode = 'P0001';
  end if;

  insert into public.communication_sms_credit_accounts (organization_id)
  values (p_organization_id)
  on conflict (organization_id) do nothing;

  select a.currency_code, a.settled_balance_minor, a.reserved_balance_minor
  into account_currency, settled, reserved
  from public.communication_sms_credit_accounts a
  where a.organization_id = p_organization_id
  for update;

  rate := public.communication_sms_effective_number_rate(p_country_code, p_number_type, account_currency, now());
  if rate.id is null then
    raise exception 'number_price_missing' using errcode = 'P0001';
  end if;

  v_monthly := round(rate.monthly_rate_major * 100)::bigint;
  v_setup := round(rate.setup_rate_major * 100)::bigint;

  if settled - reserved < v_monthly + v_setup then
    raise exception 'insufficient_balance' using errcode = 'P0001';
  end if;

  begin
    insert into public.communication_sms_number_orders (
      organization_id, idempotency_key, phone_number, country_code, number_type,
      capable_sms, capable_mms, capable_voice, locality, region, address_requirement, bundle_sid, address_sid,
      number_rate_id, currency_code, monthly_minor, setup_minor, charge_minor, requested_by
    ) values (
      p_organization_id, p_idempotency_key, p_phone_number, p_country_code, p_number_type,
      p_capable_sms, p_capable_mms, p_capable_voice, nullif(trim(p_locality), ''), nullif(trim(p_region), ''),
      coalesce(p_address_requirement, 'none'), p_bundle_sid, p_address_sid,
      rate.id, account_currency, v_monthly, v_setup, v_monthly + v_setup, p_actor
    )
    returning * into created;
  exception when unique_violation then
    -- Either a concurrent replay of this same key (return the winner) or another open order for this number.
    select * into existing
    from public.communication_sms_number_orders o
    where o.organization_id = p_organization_id and o.idempotency_key = p_idempotency_key;
    if found then
      return existing;
    end if;
    raise exception 'number_being_bought' using errcode = 'P0001';
  end;

  update public.communication_sms_credit_accounts
  set reserved_balance_minor = reserved_balance_minor + created.charge_minor,
      updated_at = now()
  where organization_id = p_organization_id;

  return created;
end;
$$;

-- Record that the Twilio purchase call is about to be made. Only a reserved order moves; anything else is returned
-- as it stands so the caller can decide (an order already purchasing needs reconciling, not a second buy).
create or replace function public.communication_sms_mark_number_order_purchasing(p_order_id uuid)
returns public.communication_sms_number_orders
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  o public.communication_sms_number_orders;
begin
  update public.communication_sms_number_orders
  set state = 'purchasing', updated_at = now()
  where id = p_order_id and state = 'reserved'
  returning * into o;
  if not found then
    select * into o from public.communication_sms_number_orders where id = p_order_id;
  end if;
  return o;
end;
$$;

-- Twilio confirmed the number is ours: record its SID and turn the hold into the charge, in one step. Replays are
-- harmless; the ledger's (organization, source, kind) key guards against a second charge.
create or replace function public.communication_sms_record_number_purchased(
  p_order_id uuid,
  p_provider_phone_number_sid text
)
returns public.communication_sms_number_orders
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  o public.communication_sms_number_orders;
  new_balance bigint;
begin
  select * into o from public.communication_sms_number_orders where id = p_order_id for update;
  if not found then
    raise exception 'number_order_not_found' using errcode = 'P0001';
  end if;
  if o.state in ('purchased', 'completed') then
    return o;
  end if;
  if o.state = 'failed' then
    raise exception 'number_order_already_failed' using errcode = 'P0001';
  end if;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = settled_balance_minor - o.charge_minor,
      reserved_balance_minor = reserved_balance_minor - o.charge_minor,
      updated_at = now()
  where organization_id = o.organization_id
  returning settled_balance_minor into new_balance;

  insert into public.communication_sms_credit_ledger_entries (
    organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at, reason
  ) values (
    o.organization_id, 'number_order:' || o.id, 'charge', -o.charge_minor, new_balance, now(),
    'Phone number ' || o.phone_number || case when o.setup_minor > 0 then ' (first month and setup)'
      else ' (first month)' end
  );

  update public.communication_sms_number_orders
  set state = 'purchased',
      provider_phone_number_sid = p_provider_phone_number_sid,
      purchased_at = now(),
      updated_at = now()
  where id = p_order_id
  returning * into o;

  return o;
end;
$$;

-- Twilio definitely refused (or reconciliation proved nothing was bought): release the hold. Never fails an order
-- that already owns a number.
create or replace function public.communication_sms_fail_number_order(p_order_id uuid, p_failure_code text)
returns public.communication_sms_number_orders
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  o public.communication_sms_number_orders;
begin
  select * into o from public.communication_sms_number_orders where id = p_order_id for update;
  if not found then
    raise exception 'number_order_not_found' using errcode = 'P0001';
  end if;
  if o.state not in ('reserved', 'purchasing') then
    return o;
  end if;

  update public.communication_sms_credit_accounts
  set reserved_balance_minor = reserved_balance_minor - o.charge_minor,
      updated_at = now()
  where organization_id = o.organization_id;

  update public.communication_sms_number_orders
  set state = 'failed', failure_code = p_failure_code, failed_at = now(), updated_at = now()
  where id = p_order_id
  returning * into o;

  return o;
end;
$$;

-- The bought number joined the Messaging Service: create (or find) its sender, starting pending_setup with sending
-- off until readiness allows it, and close the order.
create or replace function public.communication_sms_complete_number_order(p_order_id uuid)
returns public.communication_sms_number_orders
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  o public.communication_sms_number_orders;
  v_sender_id uuid;
begin
  select * into o from public.communication_sms_number_orders where id = p_order_id for update;
  if not found then
    raise exception 'number_order_not_found' using errcode = 'P0001';
  end if;
  if o.state = 'completed' then
    return o;
  end if;
  if o.state <> 'purchased' then
    raise exception 'number_order_not_purchased' using errcode = 'P0001';
  end if;

  select s.id into v_sender_id
  from public.communication_sms_sender_identities s
  where s.organization_id = o.organization_id
    and s.phone_number = o.phone_number
    and s.lifecycle_state <> 'released';

  if v_sender_id is null then
    insert into public.communication_sms_sender_identities (
      organization_id, phone_number, country_code, sender_type, number_type, provider_phone_number_sid,
      capable_sms, capable_mms, capable_voice
    ) values (
      o.organization_id, o.phone_number, o.country_code,
      case when o.number_type = 'toll_free' then 'toll_free' else 'long_code' end,
      o.number_type, o.provider_phone_number_sid, o.capable_sms, o.capable_mms, o.capable_voice
    )
    returning id into v_sender_id;
  end if;

  update public.communication_sms_number_orders
  set state = 'completed', sender_identity_id = v_sender_id, completed_at = now(), updated_at = now()
  where id = p_order_id
  returning * into o;

  return o;
end;
$$;

revoke all on function public.communication_sms_effective_number_rate(text, text, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.communication_sms_set_number_rate(
  text, text, numeric, uuid, numeric, text, numeric, numeric, timestamptz, text
) from public, anon, authenticated;
revoke all on function public.communication_sms_open_number_order(
  uuid, uuid, text, text, text, text, boolean, boolean, boolean, text, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.communication_sms_mark_number_order_purchasing(uuid) from public, anon, authenticated;
revoke all on function public.communication_sms_record_number_purchased(uuid, text) from public, anon, authenticated;
revoke all on function public.communication_sms_fail_number_order(uuid, text) from public, anon, authenticated;
revoke all on function public.communication_sms_complete_number_order(uuid) from public, anon, authenticated;

grant execute on function public.communication_sms_effective_number_rate(text, text, text, timestamptz) to service_role;
grant execute on function public.communication_sms_set_number_rate(
  text, text, numeric, uuid, numeric, text, numeric, numeric, timestamptz, text
) to service_role;
grant execute on function public.communication_sms_open_number_order(
  uuid, uuid, text, text, text, text, boolean, boolean, boolean, text, text, text, text, text
) to service_role;
grant execute on function public.communication_sms_mark_number_order_purchasing(uuid) to service_role;
grant execute on function public.communication_sms_record_number_purchased(uuid, text) to service_role;
grant execute on function public.communication_sms_fail_number_order(uuid, text) to service_role;
grant execute on function public.communication_sms_complete_number_order(uuid) to service_role;
