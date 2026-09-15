-- Communications A2 / Stage 8 (part 1): price reconciliation by known Twilio Message SID.
--
-- Nothing has ever turned a 'reserved' SMS credit hold into a real, final charge. The Stage 4B worker's own
-- comment says so explicitly ("The reservation stays 'reserved'. Settlement against the provider's billed
-- price is Stage 8 work."): submission only proves Twilio accepted the message, never what it actually cost
-- or how many segments it was actually billed for. This migration adds that missing settlement step.
--
-- Twilio's status callback webhook never carries Price/PriceUnit (confirmed against Twilio's own Message
-- resource and Track Outbound Message Status docs, researched 2026-09-15, not memory) -- the only way to learn
-- a message's final billed price and segment count is GET /Messages/{Sid}.json after the fact, on an
-- undocumented delay ("may not be immediately available", no fixed SLA published). So this is a bounded poll,
-- not a webhook: a cron finds reservations whose message Twilio already accepted (delivery_intent.status =
-- 'submitted') and still holds an unsettled reservation, fetches the Message resource, and either settles it
-- or backs off to a later retry.
--
-- Money design, following the approved plan's "keep provider cost separate from the immutable retail rate":
--   - The per-segment RETAIL rate charged to the contractor never changes. Twilio's own raw price (its cost to
--     US, in Twilio's currency) is recorded purely for margin visibility and never drives a contractor's
--     charge.
--   - What CAN legitimately change is how many segments Twilio actually billed for versus the estimate frozen
--     at send time (encoding/unicode edge cases). If they differ, that is a real, measurable correction at the
--     same frozen per-segment rate -- posted as a separate, visible ledger adjustment, matching the plan's
--     "later corrections append adjustments."
--   - A reservation that never gets a price after bounded attempts keeps its hold and opens a
--     'billing_mismatch' reconciliation item (that reason value already existed, pre-provisioned by 2C-4/9A's
--     schema for exactly this) so it surfaces in existing Jafar Operations, matching the plan's "unknown cost
--     ... until resolved."
--
-- Found while building this: no code has ever actually spent a promotional credit for good either. The public
-- communication_sms_enqueue_operational is now a thin permission-check wrapper (confirmed live on the dev DB,
-- 2026-09-15 -- a later refactor not yet reflected in any migration file this session reviewed) that delegates
-- to private.communication_sms_enqueue_operational_core, which computes "promotional credit already spoken
-- for" by summing reservations in state ('reserved', 'submission_unknown') only. Once this migration lets a
-- reservation reach 'settled' for the first time ever, a settled promo-funded send would silently free its
-- promo dollars back up for reuse. Fixed below by widening that one filter on the live core function -- found
-- and confirmed unique via `prosrc ilike '%reserved_promotional_minor%'` (one match) before writing this.

-- 1. Where a settlement's findings live, and the bounded-retry schedule that drives the poll.
alter table public.communication_sms_credit_reservations
  add column price_check_attempts integer not null default 0,
  add column price_check_available_at timestamptz not null default now(),
  add column reported_provider_price_minor bigint,
  add column reported_provider_price_currency text,
  add column reported_segment_count integer,
  add column price_checked_at timestamptz;

alter table public.communication_sms_credit_reservations
  add constraint communication_sms_credit_reservations_price_check_attempts_check
    check (price_check_attempts >= 0),
  add constraint communication_sms_credit_reservations_reported_segments_check
    check (reported_segment_count is null or reported_segment_count between 1 and 10),
  add constraint communication_sms_credit_reservations_reported_price_check
    check (reported_provider_price_minor is null or reported_provider_price_minor >= 0),
  add constraint communication_sms_credit_reservations_reported_currency_check
    check (reported_provider_price_currency is null or reported_provider_price_currency ~ '^[A-Z]{3}$');

create index communication_sms_credit_reservations_price_check_idx
  on public.communication_sms_credit_reservations (price_check_available_at)
  where state = 'reserved';

comment on column public.communication_sms_credit_reservations.reported_provider_price_minor is
  'Twilio''s own billed cost for this message, informational only -- never used to compute the contractor''s '
  'retail charge (see this migration''s header).';

-- 2. Bounded, read-only candidate list for the poll: reservations still open whose message Twilio has already
--    accepted, due for a check (or their first one), oldest-due first. This cron runs single-flight (see the
--    schedule below) and every write it makes is already idempotent by reservation state, so no claim token is
--    needed here the way the outbox claim functions need one for concurrent workers.
create or replace function public.communication_sms_list_price_reconciliation_candidates(
  p_limit integer default 100
) returns table (
  delivery_intent_id uuid,
  organization_id uuid,
  provider_message_id text,
  twilio_account_id uuid,
  subaccount_sid text,
  price_check_attempts integer
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    reservation.delivery_intent_id,
    reservation.organization_id,
    intent.provider_message_id,
    account.id as twilio_account_id,
    account.subaccount_sid,
    reservation.price_check_attempts
  from public.communication_sms_credit_reservations reservation
  join public.communication_delivery_intents intent
    on intent.id = reservation.delivery_intent_id and intent.channel = 'sms'
  join public.communication_twilio_accounts account
    on account.organization_id = reservation.organization_id
  where reservation.state = 'reserved'
    and reservation.price_check_available_at <= now()
    and intent.status = 'submitted'
  order by reservation.price_check_available_at, reservation.reserved_at
  limit greatest(p_limit, 0);
$$;

revoke all on function public.communication_sms_list_price_reconciliation_candidates(integer)
  from public, anon, authenticated;
grant execute on function public.communication_sms_list_price_reconciliation_candidates(integer)
  to service_role;

-- 3. Success path: Twilio has a final price/segment count for this message. Converts the hold into the
--    account's first-ever real charge for this send, then -- only if the actual segment count differs from
--    what was estimated at send time -- posts a separate, visible adjustment at the same frozen per-segment
--    rate. Idempotent: a reservation no longer 'reserved' is a safe no-op, since the webhook-less poll can see
--    the same candidate more than once across runs.
create or replace function public.communication_sms_settle_reservation_price(
  p_delivery_intent_id uuid,
  p_reported_segment_count integer,
  p_reported_provider_price_minor bigint,
  p_reported_provider_price_currency text,
  p_actor uuid default null
) returns public.communication_sms_credit_reservations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reservation public.communication_sms_credit_reservations;
  settled bigint;
  reserved bigint;
  per_segment_minor numeric;
  corrected_amount_minor bigint;
  delta bigint;
begin
  select * into reservation
  from public.communication_sms_credit_reservations
  where delivery_intent_id = p_delivery_intent_id
  for update;

  if not found then
    raise exception 'No SMS credit reservation exists for this delivery intent.' using errcode = 'P0001';
  end if;

  if reservation.state <> 'reserved' then
    return reservation;
  end if;

  update public.communication_sms_credit_reservations
  set reported_segment_count = p_reported_segment_count,
      reported_provider_price_minor = p_reported_provider_price_minor,
      reported_provider_price_currency = p_reported_provider_price_currency,
      price_checked_at = now()
  where id = reservation.id;

  select settled_balance_minor, reserved_balance_minor into settled, reserved
  from public.communication_sms_credit_accounts
  where organization_id = reservation.organization_id
  for update;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = settled - reservation.reserved_purchased_minor,
      reserved_balance_minor = reserved - reservation.reserved_purchased_minor,
      updated_at = now()
  where organization_id = reservation.organization_id;

  insert into public.communication_sms_credit_ledger_entries (
    organization_id, reservation_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at
  ) values (
    reservation.organization_id, reservation.id, 'charge:' || reservation.source_key, 'charge',
    -reservation.reserved_purchased_minor, settled - reservation.reserved_purchased_minor, now()
  );

  update public.communication_sms_credit_reservations
  set state = 'settled', settled_at = now()
  where id = reservation.id;

  if p_reported_segment_count is not null and p_reported_segment_count <> reservation.segment_count then
    per_segment_minor := reservation.amount_minor::numeric / reservation.segment_count;
    corrected_amount_minor := ceil(p_reported_segment_count * per_segment_minor)::bigint;
    delta := corrected_amount_minor - reservation.amount_minor;
    if delta <> 0 then
      perform public.communication_sms_record_adjustment(
        reservation.organization_id,
        -delta,
        format(
          'SMS segment recount: Twilio billed %s segment(s) for this message; %s were estimated at send time.',
          p_reported_segment_count, reservation.segment_count
        ),
        'price-reconciliation:' || reservation.delivery_intent_id::text,
        p_actor
      );
    end if;
  end if;

  select * into reservation
  from public.communication_sms_credit_reservations
  where id = reservation.id;

  return reservation;
end;
$$;

revoke all on function public.communication_sms_settle_reservation_price(uuid, integer, bigint, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_settle_reservation_price(uuid, integer, bigint, text, uuid)
  to service_role;

-- 4. No-price-yet or transient-failure path: back off before trying again (1h, 2h, 4h, 8h, 16h, then capped at
--    24h), and once bounded attempts are exhausted, open a 'billing_mismatch' reconciliation item so an
--    unresolved price surfaces in Jafar Operations instead of being retried forever. The reservation keeps its
--    hold either way -- per the approved plan, unknown cost stays reserved until resolved.
create or replace function public.communication_sms_defer_price_reconciliation(
  p_delivery_intent_id uuid,
  p_last_error text default null
) returns public.communication_sms_credit_reservations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reservation public.communication_sms_credit_reservations;
  next_attempts integer;
  backoff_hours integer;
  max_attempts constant integer := 8;
begin
  select * into reservation
  from public.communication_sms_credit_reservations
  where delivery_intent_id = p_delivery_intent_id
  for update;

  if not found or reservation.state <> 'reserved' then
    return reservation;
  end if;

  next_attempts := reservation.price_check_attempts + 1;
  backoff_hours := least(power(2, next_attempts - 1)::numeric, 24)::integer;

  update public.communication_sms_credit_reservations
  set price_check_attempts = next_attempts,
      price_check_available_at = now() + make_interval(hours => backoff_hours)
  where id = reservation.id
  returning * into reservation;

  if next_attempts >= max_attempts then
    insert into public.communication_sms_reconciliation_items (
      organization_id, delivery_intent_id, reason, last_error
    ) values (
      reservation.organization_id, reservation.delivery_intent_id, 'billing_mismatch',
      coalesce(nullif(trim(p_last_error), ''), 'Twilio never reported a final price for this message.')
    )
    on conflict (delivery_intent_id, reason) where status in ('open', 'processing', 'failed')
      and delivery_intent_id is not null do nothing;
  end if;

  return reservation;
end;
$$;

revoke all on function public.communication_sms_defer_price_reconciliation(uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_defer_price_reconciliation(uuid, text)
  to service_role;

-- 5. Fix: widen private.communication_sms_enqueue_operational_core's promotional-consumption filter to include
--    'settled' reservations, so a settled promo-funded send stays permanently spent (see this migration's
--    header). Patched via pg_get_functiondef rather than hand-copied, mirroring how 20260913023817 patched
--    claim_communication_outbox_event for the same reason.
do $migration$
declare
  function_sql text;
  updated_sql text;
begin
  function_sql := pg_get_functiondef(
    'private.communication_sms_enqueue_operational_core(uuid,uuid,uuid,uuid,text,text,text,text,uuid)'
      ::regprocedure
  );
  updated_sql := replace(
    function_sql,
    $$where organization_id = p_organization_id and state in ('reserved', 'submission_unknown');$$,
    $$where organization_id = p_organization_id and state in ('reserved', 'submission_unknown', 'settled');$$
  );
  if updated_sql = function_sql then
    raise exception 'Could not widen communication_sms_enqueue_operational_core''s promotional-consumption '
      'filter to include settled reservations.';
  end if;
  execute updated_sql;
end;
$migration$;

-- 6. Poll schedule: every 30 minutes (most candidates will not be due yet, held back by their own backoff).
--    Created INACTIVE, matching the outbox send worker's own caution (20260919140000) -- this cron makes real
--    Twilio API calls, so it waits for Jafar to activate it alongside enabling live SMS traffic.
create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'sms_price_reconciliation_cron_target_url'
  ) then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
      'sms_price_reconciliation_cron_target_url',
      'Internal URL the SMS price-reconciliation cron job calls (net.http_post target). Update this value '
      'directly when the deployment target changes -- no migration or code change needed.'
    );
  end if;

  if not exists (
    select 1 from vault.secrets where name = 'sms_price_reconciliation_cron_secret'
  ) then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
      'sms_price_reconciliation_cron_secret',
      'Bearer secret sent as the Authorization header to the internal sms-price-reconciliation-cron route. '
      'Must match the app''s SMS_PRICE_RECONCILIATION_CRON_SECRET environment variable.'
    );
  end if;
end;
$$;

do $$
declare
  job_id bigint;
begin
  if not exists (
    select 1 from cron.job where jobname = 'communications-sms-price-reconciliation'
  ) then
    job_id := cron.schedule(
      'communications-sms-price-reconciliation',
      '*/30 * * * *',
      $cron$
      select net.http_post(
        url := (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'sms_price_reconciliation_cron_target_url'
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select decrypted_secret from vault.decrypted_secrets
            where name = 'sms_price_reconciliation_cron_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 60000
      );
      $cron$
    );
    perform cron.alter_job(job_id := job_id, active := false);
  end if;
end;
$$;
