-- Communications A2 / Stage 8 (part 2): account usage-window reconciliation.
--
-- Stage 8-1 settles one message at a time by its known Message SID -- it can only ever check a message our own
-- system already knows about. It cannot catch a message Twilio billed that never got a delivery intent/
-- reservation row at all (a bug that bypassed the enqueue command, a duplicate provider-side charge, or any
-- other systemic drift). Twilio's own documented fix for exactly this is Usage Records: an account-level daily
-- aggregate ("suitable for reconciliation and usage-based billing" -- researched fresh against Twilio's Usage
-- Records docs, GET /2010-04-01/Accounts/{AccountSid}/Usage/Records/Daily.json, 2026-09-15, not memory). This
-- migration adds the durable cursor + findings this cross-check needs; the actual Twilio call and per-day diff
-- run in the application (sms-usage-reconciliation-cron.ts), matching 8-1's split (SQL owns candidates/state,
-- TypeScript owns the one Twilio call per item).
--
-- Category scope: `sms-outbound` only (confirmed against Twilio's usage-categories doc), matching exactly what
-- Stage 4/8-1 charges a contractor for -- inbound SMS is never billed to a contractor today, so comparing
-- against the combined `sms` category (which also counts inbound) would manufacture false drift.
--
-- Design, mirroring 8-1's bounded-poll caution:
--   - Restricted key: the runtime send key already reads Messages; it does NOT yet carry the Usage Records
--     read permission. Confirmed via Twilio's own Restricted API Keys permissions doc (PDF table): the
--     capability string is `/twilio/billing/usage/read`, covering GET .../Usage/Records (and its Daily/Monthly
--     subresources). Added to the shared messaging policy in twilio.ts this same change -- affects newly
--     created/rotated keys only; an already-issued key needs rotation before this can run live (moot today,
--     Stage 9's hard constraint already blocks any live call).
--   - Cursor lives directly on communication_twilio_accounts (a strict 1:1 with organization_id already), not a
--     separate table -- there is exactly one cursor per org, same reasoning 8-1 used to add its own cursor
--     columns directly onto the reservation row instead of a side table.
--   - Findings are a new append-only-per-day table (upserted by day so a re-check can correct itself), reusing
--     the existing communication_sms_reconciliation_items queue for anything that actually drifts -- a new
--     'usage_window_drift' reason on the same table Jafar Operations already reads for billing_mismatch, rather
--     than a second parallel "needs attention" surface. It is org+date scoped (no single delivery_intent_id),
--     so it is keyed by a synthetic provider_message_id ('usage-window:{org}:{date}') instead -- that column is
--     free text already, not SID-validated, and the row's existing identity check
--     (delivery_intent_id is not null or provider_message_id is not null) already accepts this shape.
--   - Zero tolerance on both count and price: this is a detection-only, human-reviewed queue (nothing here
--     auto-adjusts money, unlike 8-1's settle command), so being maximally sensitive is the safe default. A
--     day whose settlement genuinely just has not finished yet within the lag window self-heals on the next
--     overlap re-check and auto-resolves its own reconciliation item -- no permanent false alarm.
--   - Lag + overlap: the cron only looks at usage_date <= today - 2 days (LAG_DAYS), giving 8-1's own bounded
--     price-settlement backoff room to finish first, and re-checks the last 3 already-reconciled days
--     (OVERLAP_DAYS) every run to catch anything that settles late or that Twilio itself corrects retroactively.
--   - Bounded window: a long-dormant org's first-ever check (or a big backlog) is capped at 14 days per cron
--     run, not the full history at once, matching the "bounded" caution used everywhere else in this campaign.

-- 1. Cursor: where this org's usage-window check last left off, and when it was last attempted.
alter table public.communication_twilio_accounts
  add column usage_reconciled_through date,
  add column usage_reconciliation_checked_at timestamptz;

comment on column public.communication_twilio_accounts.usage_reconciled_through is
  'Last usage_date (GMT) whose Twilio Usage Records window has already been compared against our own '
  'settled totals for this org. Null until the first check ever runs.';

-- 2. Findings: one row per organization+day actually compared, upserted so a later re-check (inside the
--    overlap window) corrects the same row instead of accumulating duplicates.
create table public.communication_sms_usage_reconciliation_findings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  usage_date date not null,
  our_message_count integer not null,
  our_price_minor bigint not null,
  provider_message_count integer not null,
  provider_price_minor bigint not null,
  price_currency text not null,
  status text not null,
  checked_at timestamptz not null default now(),
  constraint communication_sms_usage_reconciliation_findings_key
    unique (organization_id, usage_date),
  constraint communication_sms_usage_reconciliation_findings_our_count_check
    check (our_message_count >= 0),
  constraint communication_sms_usage_reconciliation_findings_our_price_check
    check (our_price_minor >= 0),
  constraint communication_sms_usage_reconciliation_findings_provider_count_check
    check (provider_message_count >= 0),
  constraint communication_sms_usage_reconciliation_findings_provider_price_check
    check (provider_price_minor >= 0),
  constraint communication_sms_usage_reconciliation_findings_currency_check
    check (price_currency ~ '^[A-Z]{3}$'),
  constraint communication_sms_usage_reconciliation_findings_status_check
    check (status in ('matched', 'drift'))
);
create index communication_sms_usage_reconciliation_findings_drift_idx
  on public.communication_sms_usage_reconciliation_findings (organization_id, usage_date desc)
  where status = 'drift';

alter table public.communication_sms_usage_reconciliation_findings enable row level security;
revoke all on public.communication_sms_usage_reconciliation_findings from public, anon, authenticated;
grant select, insert, update on public.communication_sms_usage_reconciliation_findings to service_role;

-- 3. Widen the existing reconciliation-items queue with the new reason, and a partial unique index covering
--    org+date-scoped items (the existing one only applies while delivery_intent_id is not null).
alter table public.communication_sms_reconciliation_items
  drop constraint communication_sms_reconciliation_items_reason_check,
  add constraint communication_sms_reconciliation_items_reason_check
    check (reason in (
      'submission_unknown', 'callback_before_finalize', 'missing_callback', 'billing_mismatch',
      'usage_window_drift'
    ));

create unique index communication_sms_reconciliation_items_usage_window_key
  on public.communication_sms_reconciliation_items (organization_id, provider_message_id, reason)
  where status in ('open', 'processing', 'failed') and delivery_intent_id is null;

-- 4. Bounded, read-only candidate list: one row per organization due for a check, with the exact date window
--    to query (already clamped to the lag/overlap/max-window rules described above).
create or replace function public.communication_sms_list_usage_reconciliation_candidates(
  p_limit integer default 50,
  p_lag_days integer default 2,
  p_overlap_days integer default 3,
  p_max_window_days integer default 14
) returns table (
  organization_id uuid,
  twilio_account_id uuid,
  subaccount_sid text,
  window_start date,
  window_end date
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    account.organization_id,
    account.id as twilio_account_id,
    account.subaccount_sid,
    greatest(
      coalesce(
        account.usage_reconciled_through - (greatest(p_overlap_days, 1) - 1),
        (current_date - p_lag_days)
      ),
      (current_date - p_lag_days) - (greatest(p_max_window_days, 1) - 1)
    ) as window_start,
    current_date - p_lag_days as window_end
  from public.communication_twilio_accounts account
  where account.lifecycle_state in ('ready', 'restricted')
    and (
      account.usage_reconciled_through is null
      or account.usage_reconciled_through < current_date - p_lag_days
    )
  order by coalesce(account.usage_reconciliation_checked_at, to_timestamp(0)), account.organization_id
  limit greatest(p_limit, 0);
$$;

revoke all on function public.communication_sms_list_usage_reconciliation_candidates(integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.communication_sms_list_usage_reconciliation_candidates(integer, integer, integer, integer)
  to service_role;

-- 5. Our own per-day totals for a window: settled reservations grouped by the date Twilio actually accepted
--    the message (accepted_at, GMT), matching how a Twilio Daily Usage Record is dated -- not by when we
--    happened to poll/settle its price (which can lag accepted_at by up to 8-1's own bounded backoff).
--    Purpose-built partial index: this query's exact filter shape (org + sms + submitted + accepted_at range)
--    has no existing covering index; the reservation join is already covered by that table's own
--    communication_sms_credit_reservations_one_intent unique key on delivery_intent_id.
create index communication_delivery_intents_sms_submitted_accepted_idx
  on public.communication_delivery_intents (organization_id, accepted_at)
  where channel = 'sms' and status = 'submitted';

create or replace function public.communication_sms_usage_reconciliation_our_totals(
  p_organization_id uuid,
  p_window_start date,
  p_window_end date
) returns table (
  usage_date date,
  message_count integer,
  price_minor bigint,
  price_currency text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    (intent.accepted_at at time zone 'utc')::date as usage_date,
    count(*)::integer as message_count,
    coalesce(sum(reservation.reported_provider_price_minor), 0)::bigint as price_minor,
    max(reservation.reported_provider_price_currency) as price_currency
  from public.communication_delivery_intents intent
  join public.communication_sms_credit_reservations reservation
    on reservation.delivery_intent_id = intent.id
  where intent.organization_id = p_organization_id
    and intent.channel = 'sms'
    and intent.status = 'submitted'
    and (intent.accepted_at at time zone 'utc')::date between p_window_start and p_window_end
  group by 1
  order by 1;
$$;

revoke all on function public.communication_sms_usage_reconciliation_our_totals(uuid, date, date)
  from public, anon, authenticated;
grant execute on function public.communication_sms_usage_reconciliation_our_totals(uuid, date, date)
  to service_role;

-- 6. Record one day's comparison. Idempotent by (organization_id, usage_date): a later overlap re-check
--    replaces the row. A mismatch opens (or leaves open) a reconciliation item; a now-matching day auto-
--    resolves any reconciliation item it previously opened, since the only cause this system can distinguish
--    is settlement lag, which is expected to clear within the overlap window.
create or replace function public.communication_sms_record_usage_reconciliation_finding(
  p_organization_id uuid,
  p_usage_date date,
  p_our_message_count integer,
  p_our_price_minor bigint,
  p_provider_message_count integer,
  p_provider_price_minor bigint,
  p_price_currency text
) returns public.communication_sms_usage_reconciliation_findings
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  finding public.communication_sms_usage_reconciliation_findings;
  drifted boolean;
  synthetic_key text;
begin
  drifted := p_our_message_count <> p_provider_message_count or p_our_price_minor <> p_provider_price_minor;
  synthetic_key := 'usage-window:' || p_organization_id::text || ':' || p_usage_date::text;

  insert into public.communication_sms_usage_reconciliation_findings (
    organization_id, usage_date, our_message_count, our_price_minor,
    provider_message_count, provider_price_minor, price_currency, status, checked_at
  ) values (
    p_organization_id, p_usage_date, p_our_message_count, p_our_price_minor,
    p_provider_message_count, p_provider_price_minor, p_price_currency,
    case when drifted then 'drift' else 'matched' end, now()
  )
  on conflict (organization_id, usage_date) do update
    set our_message_count = excluded.our_message_count,
        our_price_minor = excluded.our_price_minor,
        provider_message_count = excluded.provider_message_count,
        provider_price_minor = excluded.provider_price_minor,
        price_currency = excluded.price_currency,
        status = excluded.status,
        checked_at = excluded.checked_at
  returning * into finding;

  if drifted then
    insert into public.communication_sms_reconciliation_items (
      organization_id, provider_message_id, reason, last_error
    ) values (
      p_organization_id, synthetic_key, 'usage_window_drift',
      format(
        'Twilio reported %s outbound SMS for %s (%s minor units) but our own settled records show %s (%s minor units).',
        p_provider_message_count, p_usage_date, p_provider_price_minor, p_our_message_count, p_our_price_minor
      )
    )
    on conflict (organization_id, provider_message_id, reason)
      where status in ('open', 'processing', 'failed') and delivery_intent_id is null
      do nothing;
  else
    update public.communication_sms_reconciliation_items
    set status = 'resolved', resolved_at = now()
    where organization_id = p_organization_id
      and provider_message_id = synthetic_key
      and reason = 'usage_window_drift'
      and status in ('open', 'processing', 'failed');
  end if;

  return finding;
end;
$$;

revoke all on function public.communication_sms_record_usage_reconciliation_finding(
  uuid, date, integer, bigint, integer, bigint, text
) from public, anon, authenticated;
grant execute on function public.communication_sms_record_usage_reconciliation_finding(
  uuid, date, integer, bigint, integer, bigint, text
) to service_role;

-- 7. Advance the cursor once a window has actually been compared end to end. Never called on a failed check
--    (the candidate list's own oldest-checked-first ordering naturally retries it next run).
create or replace function public.communication_sms_advance_usage_reconciliation_cursor(
  p_organization_id uuid,
  p_reconciled_through date
) returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
  update public.communication_twilio_accounts
  set usage_reconciled_through = greatest(coalesce(usage_reconciled_through, p_reconciled_through), p_reconciled_through),
      usage_reconciliation_checked_at = now()
  where organization_id = p_organization_id;
$$;

revoke all on function public.communication_sms_advance_usage_reconciliation_cursor(uuid, date)
  from public, anon, authenticated;
grant execute on function public.communication_sms_advance_usage_reconciliation_cursor(uuid, date)
  to service_role;

-- 8. Poll schedule: once daily (usage data is a daily aggregate; no value in checking more often). Created
--    INACTIVE, same caution as every other cron that makes a real Twilio API call.
do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'sms_usage_reconciliation_cron_target_url'
  ) then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
      'sms_usage_reconciliation_cron_target_url',
      'Internal URL the SMS usage-window reconciliation cron job calls (net.http_post target). Update this '
      'value directly when the deployment target changes -- no migration or code change needed.'
    );
  end if;

  if not exists (
    select 1 from vault.secrets where name = 'sms_usage_reconciliation_cron_secret'
  ) then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
      'sms_usage_reconciliation_cron_secret',
      'Bearer secret sent as the Authorization header to the internal sms-usage-reconciliation-cron route. '
      'Must match the app''s SMS_USAGE_RECONCILIATION_CRON_SECRET environment variable.'
    );
  end if;
end;
$$;

do $$
declare
  job_id bigint;
begin
  if not exists (
    select 1 from cron.job where jobname = 'communications-sms-usage-reconciliation'
  ) then
    job_id := cron.schedule(
      'communications-sms-usage-reconciliation',
      '30 7 * * *',
      $cron$
      select net.http_post(
        url := (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'sms_usage_reconciliation_cron_target_url'
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select decrypted_secret from vault.decrypted_secrets
            where name = 'sms_usage_reconciliation_cron_secret'
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
