-- Communications A2 / Stage 2C (part 4): distinct outbound holds, promotional credit, and standalone
-- reasoned adjustments/refunds.
--
-- Approved behavior (docs/research/communications-a2-stage6-settings-owner-controls-plan.md, 2026-09-12,
-- "Jafar: organization controls", "Jafar: platform safety and rates", and the "Money" section; ROADMAP
-- "Stage 2C parts / 2C-4"). This part adds the money/control data + commands only. The owner /api layer and
-- Jafar UI are Stage 2C parts 5 and 6. Everything is server-owned: writes flow through the security-definer
-- commands below and the /api/* layer reads with service_role and scopes to the caller's organization.
--
-- Three separate concerns, deliberately not collapsed into one vague "SMS off" state:
--
--   * Holds — a reasoned pause on outbound SMS at one of three distinct scopes: platform (the whole shared
--     service), organization (one contractor), and provider (an emergency subaccount suspension). Release and
--     provider suspension are separate from ordinary texting/balance state. Holds pause OUTBOUND only; inbound
--     and required STOP/START/HELP handling are runtime concerns the worker keeps available regardless — this
--     table never records or blocks them. Readiness gains the 'outbound_paused' state promised in part 3.
--   * Promotional credit — Jafar-granted credit with an expiry, tracked as its own bucket separate from
--     purchased (settled) credit so it can expire without rewriting settled money. Expiry is derived on read
--     (a grant counts only while active and not yet expired), never swept into a stored 'expired' status, so it
--     cannot go stale — the same on-read approach as readiness in part 3.
--   * Standalone adjustments/refunds — Jafar posts a reasoned correction (either sign) or a refund (money
--     returned offsite) straight into the Stage 1 immutable ledger. The balance is never edited directly and
--     history is never rewritten; a correction is always a new, reasoned, uniquely-keyed ledger entry.

-- ---------------------------------------------------------------------------------------------------------------
-- Holds: distinct platform / organization / provider outbound pauses, each reasoned and separately released.
-- ---------------------------------------------------------------------------------------------------------------

create table public.communication_sms_holds (
  id uuid primary key default gen_random_uuid(),
  scope text not null,
  -- Null only for a platform-wide hold; a per-organization or provider hold always names its organization.
  organization_id uuid references public.organizations(id) on delete cascade,
  reason text not null,
  placed_by uuid,
  placed_at timestamptz not null default now(),
  status text not null default 'active',
  released_by uuid,
  released_at timestamptz,
  release_reason text,
  constraint communication_sms_holds_scope_check
    check (scope in ('platform', 'organization', 'provider')),
  -- A platform hold is global (no organization); an organization or provider hold always targets one org.
  constraint communication_sms_holds_scope_org_check check (
    (scope = 'platform' and organization_id is null)
    or (scope in ('organization', 'provider') and organization_id is not null)
  ),
  constraint communication_sms_holds_reason_check
    check (char_length(trim(reason)) between 1 and 2000),
  constraint communication_sms_holds_status_check check (status in ('active', 'released')),
  constraint communication_sms_holds_release_reason_check
    check (release_reason is null or char_length(release_reason) <= 2000),
  -- An active hold carries no release evidence; a released hold always records who released it and when.
  constraint communication_sms_holds_lifecycle_check check (
    (status = 'active' and released_at is null and released_by is null and release_reason is null)
    or (status = 'released' and released_at is not null and released_by is not null)
  )
);

-- At most one active hold per scope+target: one platform hold, one active hold per org, one provider hold per
-- org. NULLS NOT DISTINCT so two active platform holds (both null organization) collide as intended.
create unique index communication_sms_holds_one_active_idx
  on public.communication_sms_holds (scope, organization_id)
  nulls not distinct
  where status = 'active';

-- Resolving the governing hold for an organization scans only currently-active holds (a small set).
create index communication_sms_holds_active_idx
  on public.communication_sms_holds (organization_id, scope, placed_at desc)
  where status = 'active';

comment on table public.communication_sms_holds is
  'Reasoned outbound-SMS holds at platform, organization or provider scope. Pauses OUTBOUND only; inbound and '
  'STOP/START/HELP remain a runtime concern the worker keeps available. Server-owned; writes via the '
  'communication_sms_place_hold / communication_sms_release_hold commands only.';

-- ---------------------------------------------------------------------------------------------------------------
-- Promotional credit: a Jafar-granted, expiring credit bucket kept separate from purchased (settled) credit.
-- ---------------------------------------------------------------------------------------------------------------

create table public.communication_sms_promotional_credits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  currency_code text not null default 'USD',
  amount_minor bigint not null,
  reason text not null,
  granted_by uuid,
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'active',
  revoked_by uuid,
  revoked_at timestamptz,
  revoke_reason text,
  constraint communication_sms_promotional_credits_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_promotional_credits_amount_check check (amount_minor > 0),
  constraint communication_sms_promotional_credits_reason_check
    check (char_length(trim(reason)) between 1 and 2000),
  -- Promotional credit always expires, and never before it is granted.
  constraint communication_sms_promotional_credits_expiry_check check (expires_at > granted_at),
  constraint communication_sms_promotional_credits_status_check check (status in ('active', 'revoked')),
  constraint communication_sms_promotional_credits_revoke_reason_check
    check (revoke_reason is null or char_length(revoke_reason) <= 2000),
  -- An active grant carries no revocation evidence; a revoked grant always records who revoked it and when.
  constraint communication_sms_promotional_credits_lifecycle_check check (
    (status = 'active' and revoked_at is null and revoked_by is null and revoke_reason is null)
    or (status = 'revoked' and revoked_at is not null and revoked_by is not null)
  )
);

-- Summing an organization's live promotional balance touches only its active, unexpired grants.
create index communication_sms_promotional_credits_active_idx
  on public.communication_sms_promotional_credits (organization_id, expires_at)
  where status = 'active';

comment on table public.communication_sms_promotional_credits is
  'Jafar-granted, expiring SMS promotional credit, tracked separately from purchased (settled) credit. Expiry '
  'is derived on read (active and expires_at > now()), never a stored status, so the balance cannot go stale. '
  'Server-owned; writes via the communication_sms_grant/revoke_promotional_credit commands only.';

-- ---------------------------------------------------------------------------------------------------------------
-- Commands (security definer). All writes to the tables above, and all adjustment/refund ledger entries,
-- happen only through these.
-- ---------------------------------------------------------------------------------------------------------------

-- Place a reasoned outbound hold. The one-active partial index makes a duplicate active hold for the same
-- scope+target impossible; a friendly error is raised instead of surfacing the raw unique-violation.
create or replace function public.communication_sms_place_hold(
  p_scope text,
  p_organization_id uuid,
  p_reason text,
  p_placed_by uuid default null
) returns public.communication_sms_holds
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  hold public.communication_sms_holds;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'a hold must record a reason' using errcode = 'P0001';
  end if;

  begin
    insert into public.communication_sms_holds (scope, organization_id, reason, placed_by)
    values (p_scope, p_organization_id, p_reason, p_placed_by)
    returning * into hold;
  exception when unique_violation then
    raise exception 'an active % hold already exists for this target', p_scope using errcode = 'P0001';
  end;

  return hold;
end;
$$;

-- Release an active hold with a reason. Only an active hold can be released; a released hold stays released.
create or replace function public.communication_sms_release_hold(
  p_hold_id uuid,
  p_released_by uuid,
  p_release_reason text
) returns public.communication_sms_holds
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  hold public.communication_sms_holds;
begin
  if p_released_by is null then
    raise exception 'releasing a hold must record who released it' using errcode = 'P0001';
  end if;
  if p_release_reason is null or char_length(trim(p_release_reason)) = 0 then
    raise exception 'releasing a hold must record a reason' using errcode = 'P0001';
  end if;

  update public.communication_sms_holds
  set status = 'released',
      released_by = p_released_by,
      released_at = now(),
      release_reason = p_release_reason
  where id = p_hold_id and status = 'active'
  returning * into hold;

  if not found then
    raise exception 'hold % is not active and cannot be released', p_hold_id using errcode = 'P0001';
  end if;

  return hold;
end;
$$;

-- The single governing active hold that pauses an organization's outbound SMS, if any: an active platform
-- hold, or an active organization/provider hold for that org. When several apply, the most severe is returned
-- (provider suspension is an emergency, then platform, then organization) so the cause can be shown truthfully.
-- Returns no row when outbound is not held.
create or replace function public.communication_sms_active_outbound_hold(
  p_organization_id uuid
) returns table (
  scope text,
  reason text,
  placed_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select h.scope, h.reason, h.placed_at
  from public.communication_sms_holds h
  where h.status = 'active'
    and (h.scope = 'platform' or h.organization_id = p_organization_id)
  order by case h.scope when 'provider' then 3 when 'platform' then 2 else 1 end desc,
           h.placed_at desc, h.id desc
  limit 1;
$$;

-- Grant expiring promotional credit to an organization. Separate from purchased credit; never touches the
-- settled balance or the ledger.
create or replace function public.communication_sms_grant_promotional_credit(
  p_organization_id uuid,
  p_amount_minor bigint,
  p_expires_at timestamptz,
  p_reason text,
  p_granted_by uuid default null,
  p_currency_code text default 'USD'
) returns public.communication_sms_promotional_credits
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  grant_row public.communication_sms_promotional_credits;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'a promotional grant must be a positive amount' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'a promotional grant must record a reason' using errcode = 'P0001';
  end if;
  if p_expires_at is null or p_expires_at <= now() then
    raise exception 'a promotional grant must expire in the future' using errcode = 'P0001';
  end if;

  insert into public.communication_sms_promotional_credits (
    organization_id, amount_minor, expires_at, reason, granted_by, currency_code
  ) values (
    p_organization_id, p_amount_minor, p_expires_at, p_reason, p_granted_by,
    coalesce(p_currency_code, 'USD')
  )
  returning * into grant_row;

  return grant_row;
end;
$$;

-- Revoke an active promotional grant with a reason. Only an active grant can be revoked; an already-revoked or
-- naturally-expired grant is left as-is (a revoked grant stops counting immediately regardless of its expiry).
create or replace function public.communication_sms_revoke_promotional_credit(
  p_credit_id uuid,
  p_revoked_by uuid,
  p_reason text
) returns public.communication_sms_promotional_credits
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  grant_row public.communication_sms_promotional_credits;
begin
  if p_revoked_by is null then
    raise exception 'revoking a promotional grant must record who revoked it' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'revoking a promotional grant must record a reason' using errcode = 'P0001';
  end if;

  update public.communication_sms_promotional_credits
  set status = 'revoked',
      revoked_by = p_revoked_by,
      revoked_at = now(),
      revoke_reason = p_reason
  where id = p_credit_id and status = 'active'
  returning * into grant_row;

  if not found then
    raise exception 'promotional grant % is not active and cannot be revoked', p_credit_id
      using errcode = 'P0001';
  end if;

  return grant_row;
end;
$$;

-- An organization's live promotional balance: the sum of active grants that have not yet expired.
create or replace function public.communication_sms_promotional_balance(
  p_organization_id uuid
) returns bigint
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(sum(amount_minor), 0)::bigint
  from public.communication_sms_promotional_credits
  where organization_id = p_organization_id
    and status = 'active'
    and expires_at > now();
$$;

-- The spendable balance shown first to a contractor: purchased credit not currently reserved, plus live
-- promotional credit. No account row means no purchased credit (zero), so only promotional credit counts.
create or replace function public.communication_sms_spendable_balance(
  p_organization_id uuid
) returns bigint
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (select settled_balance_minor - reserved_balance_minor
     from public.communication_sms_credit_accounts
     where organization_id = p_organization_id),
    0
  )::bigint
  + public.communication_sms_promotional_balance(p_organization_id);
$$;

-- Post a reasoned, standalone correction to the settled (purchased) balance — either sign. The balance is never
-- edited directly: this raises/lowers it and records one immutable, uniquely-keyed ledger entry. A correction
-- that would drive settled below zero, or below the funds currently reserved, is refused.
create or replace function public.communication_sms_record_adjustment(
  p_organization_id uuid,
  p_amount_minor bigint,
  p_reason text,
  p_actor uuid default null,
  p_currency_code text default 'USD'
) returns public.communication_sms_credit_ledger_entries
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  entry public.communication_sms_credit_ledger_entries;
  reserved bigint;
  new_balance bigint;
begin
  if p_amount_minor is null or p_amount_minor = 0 then
    raise exception 'an adjustment must move a non-zero amount' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'an adjustment must record a reason' using errcode = 'P0001';
  end if;

  insert into public.communication_sms_credit_accounts (organization_id, currency_code)
  values (p_organization_id, coalesce(p_currency_code, 'USD'))
  on conflict (organization_id) do nothing;

  -- Check the resulting balance before writing it, so a refused correction returns a clear business error
  -- rather than the raw balances-check violation, while the constraint stays the backstop.
  select settled_balance_minor, reserved_balance_minor into new_balance, reserved
  from public.communication_sms_credit_accounts
  where organization_id = p_organization_id
  for update;

  new_balance := new_balance + p_amount_minor;

  if new_balance < reserved then
    raise exception 'adjustment would drive the settled balance below the reserved funds'
      using errcode = 'P0001';
  end if;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = new_balance,
      updated_at = now()
  where organization_id = p_organization_id;

  insert into public.communication_sms_credit_ledger_entries (
    organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at
  ) values (
    p_organization_id, 'adjustment:' || gen_random_uuid()::text, 'adjustment',
    p_amount_minor, new_balance, now()
  )
  returning * into entry;

  return entry;
end;
$$;

-- Refund settled (purchased) credit back to the contractor offsite. Lowers the settled balance by the refunded
-- amount and records one immutable, uniquely-keyed refund ledger entry (a negative movement). A refund larger
-- than the unreserved settled balance is refused.
create or replace function public.communication_sms_record_refund(
  p_organization_id uuid,
  p_amount_minor bigint,
  p_reason text,
  p_actor uuid default null
) returns public.communication_sms_credit_ledger_entries
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  entry public.communication_sms_credit_ledger_entries;
  reserved bigint;
  new_balance bigint;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'a refund must be a positive amount' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'a refund must record a reason' using errcode = 'P0001';
  end if;

  -- Check the resulting balance before writing it, so an over-refund returns a clear business error rather
  -- than the raw balances-check violation, while the constraint stays the backstop.
  select settled_balance_minor, reserved_balance_minor into new_balance, reserved
  from public.communication_sms_credit_accounts
  where organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'organization % has no credit account to refund from', p_organization_id
      using errcode = 'P0001';
  end if;

  new_balance := new_balance - p_amount_minor;

  if new_balance < reserved then
    raise exception 'refund exceeds the unreserved settled balance' using errcode = 'P0001';
  end if;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = new_balance,
      updated_at = now()
  where organization_id = p_organization_id;

  insert into public.communication_sms_credit_ledger_entries (
    organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at
  ) values (
    p_organization_id, 'refund:' || gen_random_uuid()::text, 'refund',
    -p_amount_minor, new_balance, now()
  )
  returning * into entry;

  return entry;
end;
$$;

-- The plain outbound state for one (org, country, sender type, use case): the part-3 setup readiness, but a
-- fully 'ready' capability becomes 'outbound_paused' when a hold governs the organization, and the pause scope
-- and reason are returned so the true cause is shown. Setup states (needs_setup, waiting_for_info, ...) are
-- never masked by a hold; a paused-but-not-yet-ready capability still shows its setup work. Per-message live
-- gates (consent, balance, quiet hours) stay separate runtime checks, as in part 3.
create or replace function public.communication_sms_outbound_state(
  p_organization_id uuid,
  p_country_code text,
  p_sender_type text,
  p_use_case text
) returns table (
  state text,
  effective_mode text,
  registration_status text,
  live_sender_count integer,
  pause_scope text,
  pause_reason text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  r record;
  h record;
begin
  select * into r
  from public.communication_sms_readiness(
    p_organization_id, p_country_code, p_sender_type, p_use_case
  );

  effective_mode := r.effective_mode;
  registration_status := r.registration_status;
  live_sender_count := r.live_sender_count;
  state := r.readiness_state;
  pause_scope := null;
  pause_reason := null;

  if r.readiness_state = 'ready' then
    select * into h from public.communication_sms_active_outbound_hold(p_organization_id);
    if found then
      state := 'outbound_paused';
      pause_scope := h.scope;
      pause_reason := h.reason;
    end if;
  end if;

  return next;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Server-owned access: RLS on and deny-all to client roles. service_role may read and write the hold and
-- promotional-credit records (never delete); the ledger keeps its Stage 1 append-only grant. The /api/* layer
-- reads with service_role, scopes to the caller's organization, and shows contractors retail figures only.
-- ---------------------------------------------------------------------------------------------------------------

alter table public.communication_sms_holds enable row level security;
alter table public.communication_sms_promotional_credits enable row level security;

revoke all on table public.communication_sms_holds from public, anon, authenticated;
revoke all on table public.communication_sms_holds from service_role;
grant select, insert, update on table public.communication_sms_holds to service_role;

revoke all on table public.communication_sms_promotional_credits from public, anon, authenticated;
revoke all on table public.communication_sms_promotional_credits from service_role;
grant select, insert, update on table public.communication_sms_promotional_credits to service_role;

revoke all on function public.communication_sms_place_hold(text, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_place_hold(text, uuid, text, uuid)
  to service_role;

revoke all on function public.communication_sms_release_hold(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_release_hold(uuid, uuid, text)
  to service_role;

revoke all on function public.communication_sms_active_outbound_hold(uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_active_outbound_hold(uuid)
  to service_role;

revoke all on function public.communication_sms_grant_promotional_credit(uuid, bigint, timestamptz, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_grant_promotional_credit(uuid, bigint, timestamptz, text, uuid, text)
  to service_role;

revoke all on function public.communication_sms_revoke_promotional_credit(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_revoke_promotional_credit(uuid, uuid, text)
  to service_role;

revoke all on function public.communication_sms_promotional_balance(uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_promotional_balance(uuid)
  to service_role;

revoke all on function public.communication_sms_spendable_balance(uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_spendable_balance(uuid)
  to service_role;

revoke all on function public.communication_sms_record_adjustment(uuid, bigint, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_adjustment(uuid, bigint, text, uuid, text)
  to service_role;

revoke all on function public.communication_sms_record_refund(uuid, bigint, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_refund(uuid, bigint, text, uuid)
  to service_role;

revoke all on function public.communication_sms_outbound_state(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_outbound_state(uuid, text, text, text)
  to service_role;
