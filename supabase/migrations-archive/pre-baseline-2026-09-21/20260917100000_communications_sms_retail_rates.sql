-- Communications A2 / Stage 2C (part 2): Jafar-set SMS retail rate versions.
--
-- Approved money model (docs/research/communications-a2-stage6-settings-owner-controls-plan.md, 2026-09-12,
-- "current and future-dated retail rates by supported destination/sender/message unit"):
-- Jafar publishes a retail price per message unit, keyed by destination, sender type and message unit. A new
-- rate can take effect now or on a future date. The applicable rate for a moment is the latest published
-- version whose effective_from has arrived; a future-dated version does nothing until then. New rates affect
-- new sends only — a send freezes the applicable rate into its credit reservation (a later part), so historical
-- charges keep their original rate no matter what is published afterwards. Provider cost is Jafar-only truth
-- from which margin (retail - cost) is derived; contractors only ever see the retail price.
--
-- This part adds the rate versions and their read/write commands only. The send command that freezes a rate,
-- the owner API and the Jafar UI are later Stage 2C parts. The table is server-owned: versions are written only
-- through communication_sms_set_retail_rate, are immutable once written (no UPDATE, no DELETE — a change is a
-- new version, never a rewrite of history), and the /api/* layer scopes reads and hides cost/margin from
-- contractors.

create table public.communication_sms_retail_rates (
  id uuid primary key default gen_random_uuid(),
  destination text not null,
  sender_type text not null,
  message_unit text not null,
  currency_code text not null default 'USD',
  -- Prices are stored in major currency units per message unit with sub-cent precision (SMS retail is quoted
  -- in fractions of a cent, e.g. 0.0079). The send command converts to minor units when it freezes the charge.
  retail_rate_major numeric(14, 6) not null,
  provider_cost_major numeric(14, 6),
  effective_from timestamptz not null default now(),
  set_by uuid not null,
  note text,
  created_at timestamptz not null default now(),
  constraint communication_sms_retail_rates_destination_check
    check (destination ~ '^[A-Z]{2}$'),
  constraint communication_sms_retail_rates_sender_type_check
    check (sender_type in ('long_code', 'toll_free', 'short_code', 'alphanumeric')),
  -- SMS bills per segment today. MMS or other units widen this list in their own migration when they ship.
  constraint communication_sms_retail_rates_message_unit_check
    check (message_unit in ('segment')),
  constraint communication_sms_retail_rates_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_retail_rates_retail_check
    check (retail_rate_major > 0),
  constraint communication_sms_retail_rates_cost_check
    check (provider_cost_major is null or provider_cost_major >= 0),
  constraint communication_sms_retail_rates_note_check
    check (note is null or char_length(note) <= 2000),
  -- One published version per rate key per instant; a new rate is always a distinct effective_from.
  constraint communication_sms_retail_rates_version_key
    unique (destination, sender_type, message_unit, currency_code, effective_from)
);

-- The version_key unique index (…, effective_from ascending) also serves the applicable-rate lookup
-- "latest effective_from <= T for this key" via a backward index scan, so no extra index is needed.

comment on table public.communication_sms_retail_rates is
  'Immutable SMS retail rate versions set by the Platform Owner, keyed by destination/sender/message unit. The '
  'applicable rate for a moment is the latest version whose effective_from has arrived; sends freeze it so '
  'historical charges keep their rate. Server-owned; written only via communication_sms_set_retail_rate. '
  'provider_cost_major and derived margin are Jafar-only.';

-- Jafar publishes a rate version. It takes effect now (effective_from null -> now()) or on a future date; a
-- retroactive effective_from is refused because a rate can never change a charge that has already been frozen.
create or replace function public.communication_sms_set_retail_rate(
  p_destination text,
  p_sender_type text,
  p_message_unit text,
  p_retail_rate_major numeric,
  p_set_by uuid,
  p_currency_code text default 'USD',
  p_provider_cost_major numeric default null,
  p_effective_from timestamptz default null,
  p_note text default null
) returns public.communication_sms_retail_rates
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  rate public.communication_sms_retail_rates;
  effective timestamptz := coalesce(p_effective_from, now());
begin
  if effective < now() then
    raise exception 'a retail rate takes effect now or in the future, never retroactively'
      using errcode = 'P0001';
  end if;

  insert into public.communication_sms_retail_rates (
    destination, sender_type, message_unit, currency_code,
    retail_rate_major, provider_cost_major, effective_from, set_by, note
  ) values (
    p_destination, p_sender_type, p_message_unit, coalesce(p_currency_code, 'USD'),
    p_retail_rate_major, p_provider_cost_major, effective, p_set_by, p_note
  )
  returning * into rate;

  return rate;
end;
$$;

-- The applicable rate for a moment: the latest published version whose effective_from has arrived for this key.
-- The send command calls this to freeze a charge; returns no row when no rate has been published yet.
create or replace function public.communication_sms_effective_retail_rate(
  p_destination text,
  p_sender_type text,
  p_message_unit text,
  p_currency_code text default 'USD',
  p_at timestamptz default now()
) returns public.communication_sms_retail_rates
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select r.*
  from public.communication_sms_retail_rates r
  where r.destination = p_destination
    and r.sender_type = p_sender_type
    and r.message_unit = p_message_unit
    and r.currency_code = coalesce(p_currency_code, 'USD')
    and r.effective_from <= p_at
  order by r.effective_from desc
  limit 1;
$$;

-- Server-owned. RLS on and deny-all to client roles; versions are immutable (service_role may read and insert,
-- never update or delete). The /api/* layer reads with service_role, scopes to what the caller may see, and
-- never exposes provider_cost_major or margin to contractors.
alter table public.communication_sms_retail_rates enable row level security;

revoke all on table public.communication_sms_retail_rates from public, anon, authenticated;
revoke all on table public.communication_sms_retail_rates from service_role;
grant select, insert on table public.communication_sms_retail_rates to service_role;

revoke all on function public.communication_sms_set_retail_rate(text, text, text, numeric, uuid, text, numeric, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_set_retail_rate(text, text, text, numeric, uuid, text, numeric, timestamptz, text)
  to service_role;

revoke all on function public.communication_sms_effective_retail_rate(text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.communication_sms_effective_retail_rate(text, text, text, text, timestamptz)
  to service_role;
