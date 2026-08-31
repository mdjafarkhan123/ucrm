-- Communications Part 7.4: reputation rates, configurable thresholds, and the optional-only
-- auto-pause that sits on top of 7.3's pause spine.
--
-- docs/contractor-email-contract.md
--   § Reputation controls
--     "Use rolling 24-hour and seven-day views. The initial configurable defaults are:
--        complaint 0.05% warn / 0.10% pause; hard bounce 1.00% / 2.00%; unsubscribe 0.50% / 1.00%."
--     "Apply rate-based pausing after at least 1,000 accepted recipients, or earlier after three
--      complaints or 20 hard bounces."
--     "Jafar can configure warnings, organization pause thresholds, samples, event-count triggers, and
--      windows. Organization overrides cannot weaken the platform safety ceiling. Changing the platform
--      ceiling requires separate confirmation, an impact warning, a reason, and immutable history."
--     "Only Jafar resumes an automatic reputation pause. At or beyond a provider danger threshold,
--      resumption requires explicit confirmation and remediation review. Resumption never releases
--      stale optional mail."
--   § Platform Owner controls
--     "warm-up stages, reputation thresholds, sample rules, and observation windows"
--     "reasoned, effective-dated overrides with immutable history"
--
-- Shape follows the standard ESP reputation loop: a rolling numerator of adverse provider events over a
-- rolling denominator of accepted recipients, gated by a minimum sample, evaluated out-of-band, acting
-- only on the marketing-grade (optional) class and never on protected-essential mail.
--
-- Transport is still a stub. This is the database layer and the owner surfaces it drives.

-- ---------------------------------------------------------------------------------------------------
-- 1. A stable event timestamp on the callback sink.
--    occurred_at is nullable (the provider may omit it), so every rolling window reads a generated
--    column instead. This replaces 7.1's occurred_at-based reputation index rather than adding to it.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_provider_callback_events
  add column event_at timestamptz
    generated always as (coalesce(occurred_at, received_at)) stored;

drop index if exists communication_provider_callback_events_org_kind_time_idx;

-- Per-organization reputation window: adverse events of one kind inside one rolling window.
create index communication_provider_callback_events_org_kind_event_at_idx
  on public.communication_provider_callback_events (organization_id, normalized_kind, event_at desc)
  where organization_id is not null and processed_at is not null;

-- The sweep's candidate scan: which tenants saw an adverse event recently, platform-wide.
create index communication_provider_callback_events_adverse_recent_idx
  on public.communication_provider_callback_events (event_at desc, organization_id)
  where processed_at is not null
    and normalized_kind in ('complaint', 'hard_bounce', 'unsubscribed');

-- ---------------------------------------------------------------------------------------------------
-- 2. Thresholds. Append-only and effective-dated: a change closes the live row and inserts a new one,
--    so the table *is* the immutable history. A platform row carries the full ceiling; an organization
--    row carries only the fields it tightens and inherits the rest.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_reputation_thresholds (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('platform', 'organization')),
  organization_id uuid references public.organizations(id) on delete cascade,
  signal text not null check (signal in ('complaint', 'hard_bounce', 'unsubscribe')),
  window_key text not null check (window_key in ('rolling_24h', 'rolling_7d')),
  -- Window length is a platform-only setting: contractors tighten rates, not observation windows.
  window_hours integer check (window_hours between 1 and 720),
  -- Percentages, e.g. 0.0500 = 0.05%.
  warn_rate numeric(7, 4) check (warn_rate > 0 and warn_rate <= 100),
  pause_rate numeric(7, 4) check (pause_rate > 0 and pause_rate <= 100),
  min_sample_recipients integer check (min_sample_recipients >= 0),
  -- The early trigger ("or earlier after three complaints"). Null means no early trigger.
  min_event_count integer check (min_event_count > 0),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  actor_owner_email text not null check (char_length(btrim(actor_owner_email)) between 3 and 320),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint communication_email_reputation_thresholds_scope_org_check check (
    (scope = 'platform' and organization_id is null)
    or (scope = 'organization' and organization_id is not null)
  ),
  -- A platform row is the complete ceiling; an organization row must tighten at least one field.
  constraint communication_email_reputation_thresholds_completeness_check check (
    (scope = 'platform'
      and window_hours is not null and warn_rate is not null
      and pause_rate is not null and min_sample_recipients is not null)
    or (scope = 'organization'
      and window_hours is null
      and num_nonnulls(warn_rate, pause_rate, min_sample_recipients, min_event_count) > 0)
  ),
  constraint communication_email_reputation_thresholds_rate_order_check check (
    warn_rate is null or pause_rate is null or warn_rate <= pause_rate
  ),
  constraint communication_email_reputation_thresholds_effective_range_check check (
    effective_to is null or effective_to > effective_from
  )
);

-- One live ceiling row per signal and window.
create unique index communication_email_reputation_thresholds_live_platform_idx
  on public.communication_email_reputation_thresholds (signal, window_key)
  where scope = 'platform' and effective_to is null;

-- One live override per organization, signal, and window. Also the resolver's lookup.
create unique index communication_email_reputation_thresholds_live_org_idx
  on public.communication_email_reputation_thresholds (organization_id, signal, window_key)
  where scope = 'organization' and effective_to is null;

-- One tenant's override history, newest first; also the organization cascade-delete path.
create index communication_email_reputation_thresholds_org_history_idx
  on public.communication_email_reputation_thresholds (organization_id, effective_from desc, id desc)
  where organization_id is not null;

alter table public.communication_email_reputation_thresholds enable row level security;
revoke all on public.communication_email_reputation_thresholds from anon, authenticated;
grant select, insert, update on public.communication_email_reputation_thresholds to service_role;

-- The contract's initial defaults, applied to both rolling views.
insert into public.communication_email_reputation_thresholds (
  scope, signal, window_key, window_hours, warn_rate, pause_rate, min_sample_recipients,
  min_event_count, reason, actor_owner_email
)
select
  'platform', d.signal, w.window_key, w.window_hours, d.warn_rate, d.pause_rate, 1000,
  d.min_event_count,
  'Initial platform defaults from the contractor email contract.', 'system'
from (values
  ('complaint', 0.0500::numeric, 0.1000::numeric, 3),
  ('hard_bounce', 1.0000::numeric, 2.0000::numeric, 20),
  ('unsubscribe', 0.5000::numeric, 1.0000::numeric, null::integer)
) as d(signal, warn_rate, pause_rate, min_event_count)
cross join (values
  ('rolling_24h', 24),
  ('rolling_7d', 168)
) as w(window_key, window_hours);

-- ---------------------------------------------------------------------------------------------------
-- 3. The pause spine gains a source and a class scope.
--    A manual pause (7.3) still holds every class. A reputation pause holds optional mail only, so
--    protected-essential email -- receipts, secure links, security notices -- keeps flowing.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_email_sending_pauses
  add column source text not null default 'manual' check (source in ('manual', 'auto_reputation')),
  add column applies_to text not null default 'all' check (applies_to in ('all', 'optional')),
  add column evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence) = 'object'),
  -- Not "..._source_check": Postgres already auto-names the source column's inline check that.
  add constraint communication_email_sending_pauses_source_scope_check check (
    (source = 'manual' and applies_to = 'all')
    or (source = 'auto_reputation' and scope = 'organization' and applies_to = 'optional')
  );

-- A manual freeze and an automatic reputation pause can be live on the same tenant at once; only one
-- of each. Replaces 7.3's one-live-pause-per-organization index.
drop index if exists communication_email_sending_pauses_active_org_idx;
create unique index communication_email_sending_pauses_active_org_source_idx
  on public.communication_email_sending_pauses (organization_id, source)
  where scope = 'organization' and released_at is null;

-- ---------------------------------------------------------------------------------------------------
-- 4. Effective thresholds for one organization: the platform ceiling, tightened by any live override.
--    Resolution is least(): an override can only ever make a limit stricter, so a stale or mistaken
--    override can never weaken platform safety even if it slipped past the write-time check.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.communication_email_effective_reputation_thresholds(
  p_organization_id uuid,
  p_at timestamptz default now()
)
returns table (
  signal text,
  window_key text,
  window_hours integer,
  warn_rate numeric,
  pause_rate numeric,
  min_sample_recipients integer,
  min_event_count integer,
  is_overridden boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  -- least() ignores nulls, so an override that sets only one field inherits the rest untouched.
  select
    platform.signal,
    platform.window_key,
    platform.window_hours,
    least(platform.warn_rate, org.warn_rate),
    least(platform.pause_rate, org.pause_rate),
    least(platform.min_sample_recipients, org.min_sample_recipients),
    least(platform.min_event_count, org.min_event_count),
    org.id is not null
  from public.communication_email_reputation_thresholds platform
  left join public.communication_email_reputation_thresholds org
    on org.scope = 'organization'
    and org.organization_id = p_organization_id
    and org.signal = platform.signal
    and org.window_key = platform.window_key
    and org.effective_from <= p_at
    and org.effective_to is null
  where platform.scope = 'platform'
    and platform.effective_from <= p_at
    and platform.effective_to is null;
$$;

revoke all on function private.communication_email_effective_reputation_thresholds(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function private.communication_email_effective_reputation_thresholds(uuid, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. The measurement. Adverse events counted by distinct message (a provider may repeat a callback)
--    over accepted recipients in the same rolling window.
--
--    A pause needs the sample gate: 1,000 accepted recipients, or the early event-count trigger.
--    A warning does not -- it is a signal to look, not an action.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.communication_email_reputation_metrics(
  p_organization_id uuid,
  p_at timestamptz default now()
)
returns table (
  signal text,
  window_key text,
  window_hours integer,
  window_start timestamptz,
  accepted_recipients bigint,
  event_count bigint,
  rate numeric,
  warn_rate numeric,
  pause_rate numeric,
  min_sample_recipients integer,
  min_event_count integer,
  status text
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  with resolved as (
    select
      t.*,
      p_at - make_interval(hours => t.window_hours) as window_start
    from private.communication_email_effective_reputation_thresholds(p_organization_id, p_at) t
  ),
  counted as (
    select
      r.*,
      (
        select coalesce(sum(usage.recipient_count), 0)::bigint
        from public.communication_email_usage_events usage
        where usage.organization_id = p_organization_id
          and usage.occurred_at >= r.window_start
          and usage.occurred_at <= p_at
      ) as accepted_recipients,
      (
        select count(distinct callback.delivery_intent_id)::bigint
        from public.communication_provider_callback_events callback
        where callback.organization_id = p_organization_id
          and callback.processed_at is not null
          and callback.normalized_kind = case r.signal
            when 'unsubscribe' then 'unsubscribed' else r.signal end
          and callback.event_at >= r.window_start
          and callback.event_at <= p_at
      ) as event_count
    from resolved r
  ),
  rated as (
    select
      c.*,
      case
        when c.accepted_recipients > 0
        then round((100::numeric * c.event_count) / c.accepted_recipients, 4)
      end as rate
    from counted c
  )
  select
    rated.signal,
    rated.window_key,
    rated.window_hours,
    rated.window_start,
    rated.accepted_recipients,
    rated.event_count,
    rated.rate,
    rated.warn_rate,
    rated.pause_rate,
    rated.min_sample_recipients,
    rated.min_event_count,
    case
      when rated.rate is null then 'ok'
      when rated.rate >= rated.pause_rate
        and (
          rated.accepted_recipients >= rated.min_sample_recipients
          or (rated.min_event_count is not null and rated.event_count >= rated.min_event_count)
        ) then 'pause'
      when rated.rate >= rated.warn_rate then 'warn'
      else 'ok'
    end as status
  from rated
  order by rated.signal, rated.window_key;
$$;

revoke all on function private.communication_email_reputation_metrics(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function private.communication_email_reputation_metrics(uuid, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 6. The last evaluation per organization. It is the sweep's cursor, the owner list's cheap read, and
--    the reason of record on an automatic pause. Derived state only -- never the source of truth.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_reputation_state (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  evaluated_at timestamptz not null default now(),
  worst_status text not null default 'ok' check (worst_status in ('ok', 'warn', 'pause')),
  metrics jsonb not null default '[]'::jsonb check (jsonb_typeof(metrics) = 'array'),
  last_breach_at timestamptz,
  updated_at timestamptz not null default now()
);

-- The owner's attention queue: who is in warn or pause right now.
create index communication_email_reputation_state_attention_idx
  on public.communication_email_reputation_state (worst_status, evaluated_at desc)
  where worst_status <> 'ok';

alter table public.communication_email_reputation_state enable row level security;
revoke all on public.communication_email_reputation_state from anon, authenticated;
grant select, insert, update on public.communication_email_reputation_state to service_role;

create trigger communication_email_reputation_state_set_updated_at
before update on public.communication_email_reputation_state
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------------------------------
-- 7. Evaluate one organization: measure, record, and engage the optional-only pause when a pause
--    threshold is crossed. Never releases -- only Jafar resumes a reputation pause.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.evaluate_communication_email_reputation(
  p_organization_id uuid,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  measured jsonb;
  worst_rank integer := 1;
  worst text := 'ok';
  breach record;
  existing_pause public.communication_email_sending_pauses%rowtype;
  new_pause_id uuid;
  pause_reason text;
begin
  select
    coalesce(jsonb_agg(to_jsonb(m) order by m.signal, m.window_key), '[]'::jsonb),
    coalesce(max(case m.status when 'pause' then 3 when 'warn' then 2 else 1 end), 1)
  into measured, worst_rank
  from private.communication_email_reputation_metrics(p_organization_id, p_at) m;

  worst := case worst_rank when 3 then 'pause' when 2 then 'warn' else 'ok' end;

  select m.* into breach
  from private.communication_email_reputation_metrics(p_organization_id, p_at) m
  where m.status = 'pause'
  order by (m.rate / nullif(m.pause_rate, 0)) desc nulls last
  limit 1;

  insert into public.communication_email_reputation_state (
    organization_id, evaluated_at, worst_status, metrics, last_breach_at
  ) values (
    p_organization_id, p_at, worst, measured,
    case when worst = 'pause' then p_at end
  )
  on conflict (organization_id) do update set
    evaluated_at = excluded.evaluated_at,
    worst_status = excluded.worst_status,
    metrics = excluded.metrics,
    last_breach_at = coalesce(excluded.last_breach_at,
      public.communication_email_reputation_state.last_breach_at);

  if worst <> 'pause' then
    return jsonb_build_object('organization_id', p_organization_id, 'worst_status', worst,
      'paused', false, 'metrics', measured);
  end if;

  select * into existing_pause
  from public.communication_email_sending_pauses
  where scope = 'organization'
    and organization_id = p_organization_id
    and source = 'auto_reputation'
    and released_at is null
  for update;

  if found then
    return jsonb_build_object('organization_id', p_organization_id, 'worst_status', worst,
      'paused', true, 'pause_id', existing_pause.id, 'metrics', measured);
  end if;

  pause_reason := format(
    'Automatic pause: %s rate %s%% over the %s window is at or above the %s%% threshold (%s of %s recipients).',
    replace(breach.signal, '_', ' '), breach.rate,
    case breach.window_key when 'rolling_24h' then 'rolling 24-hour' else 'rolling 7-day' end,
    breach.pause_rate, breach.event_count, breach.accepted_recipients
  );

  insert into public.communication_email_sending_pauses (
    scope, organization_id, reason, engaged_by_owner_email, source, applies_to, evidence
  ) values (
    'organization', p_organization_id, pause_reason, 'system', 'auto_reputation', 'optional',
    jsonb_build_object('signal', breach.signal, 'window_key', breach.window_key,
      'rate', breach.rate, 'pause_rate', breach.pause_rate,
      'event_count', breach.event_count, 'accepted_recipients', breach.accepted_recipients,
      'evaluated_at', p_at)
  )
  returning id into new_pause_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    'system', 'communications.email_reputation_pause_engaged', 'organization',
    p_organization_id::text,
    jsonb_build_object('pause_id', new_pause_id, 'reason', pause_reason, 'metrics', measured)
  );

  return jsonb_build_object('organization_id', p_organization_id, 'worst_status', worst,
    'paused', true, 'pause_id', new_pause_id, 'metrics', measured);
end;
$$;

revoke all on function public.evaluate_communication_email_reputation(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.evaluate_communication_email_reputation(uuid, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 8. The sweep. Only a new adverse event can worsen a rate, so the candidate set is the tenants whose
--    latest adverse event is newer than their last evaluation. A quiet tenant costs nothing.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.sweep_communication_email_reputation(batch_size integer default 200)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  evaluated_count integer := 0;
begin
  if batch_size < 1 or batch_size > 2000 then
    raise exception 'The reputation sweep batch size is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  for candidate in
    select callback.organization_id, max(callback.event_at) as latest_event_at
    from public.communication_provider_callback_events callback
    left join public.communication_email_reputation_state state
      on state.organization_id = callback.organization_id
    where callback.processed_at is not null
      and callback.normalized_kind in ('complaint', 'hard_bounce', 'unsubscribed')
      and callback.event_at >= now() - interval '7 days'
      and (state.evaluated_at is null or callback.event_at > state.evaluated_at)
    group by callback.organization_id
    order by max(callback.event_at)
    limit batch_size
  loop
    perform public.evaluate_communication_email_reputation(candidate.organization_id, now());
    evaluated_count := evaluated_count + 1;
  end loop;

  return evaluated_count;
end;
$$;

revoke all on function public.sweep_communication_email_reputation(integer)
  from public, anon, authenticated;
grant execute on function public.sweep_communication_email_reputation(integer) to service_role;

create extension if not exists pg_cron;

select cron.schedule(
  'communications-email-reputation-sweep',
  '*/5 * * * *',
  $cron$ select public.sweep_communication_email_reputation(200); $cron$
);

-- ---------------------------------------------------------------------------------------------------
-- 9. Owner reads.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_email_reputation(p_organization_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, private
as $$
  select jsonb_build_object(
    'organization_id', p_organization_id,
    'measured_at', now(),
    'metrics', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.signal, m.window_key)
      from private.communication_email_reputation_metrics(p_organization_id, now()) m
    ), '[]'::jsonb),
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'signal', t.signal, 'window_key', t.window_key,
        'warn_rate', t.warn_rate, 'pause_rate', t.pause_rate,
        'min_sample_recipients', t.min_sample_recipients, 'min_event_count', t.min_event_count,
        'reason', t.reason, 'actor_owner_email', t.actor_owner_email,
        'effective_from', t.effective_from
      ) order by t.signal, t.window_key)
      from public.communication_email_reputation_thresholds t
      where t.scope = 'organization' and t.organization_id = p_organization_id and t.effective_to is null
    ), '[]'::jsonb),
    'reputation_pause', (
      select jsonb_build_object(
        'id', p.id, 'reason', p.reason, 'engaged_at', p.engaged_at, 'evidence', p.evidence
      )
      from public.communication_email_sending_pauses p
      where p.scope = 'organization' and p.organization_id = p_organization_id
        and p.source = 'auto_reputation' and p.released_at is null
      limit 1
    ),
    'state', (
      select jsonb_build_object(
        'worst_status', s.worst_status, 'evaluated_at', s.evaluated_at, 'last_breach_at', s.last_breach_at
      )
      from public.communication_email_reputation_state s
      where s.organization_id = p_organization_id
    )
  );
$$;

revoke all on function public.get_communication_email_reputation(uuid) from public, anon, authenticated;
grant execute on function public.get_communication_email_reputation(uuid) to service_role;

create or replace function public.get_communication_email_reputation_overview()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'platform_thresholds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'signal', t.signal, 'window_key', t.window_key, 'window_hours', t.window_hours,
        'warn_rate', t.warn_rate, 'pause_rate', t.pause_rate,
        'min_sample_recipients', t.min_sample_recipients, 'min_event_count', t.min_event_count,
        'reason', t.reason, 'actor_owner_email', t.actor_owner_email, 'effective_from', t.effective_from
      ) order by t.signal, t.window_key)
      from public.communication_email_reputation_thresholds t
      where t.scope = 'platform' and t.effective_to is null
    ), '[]'::jsonb),
    'attention', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', s.organization_id, 'organization_name', o.name,
        'worst_status', s.worst_status, 'evaluated_at', s.evaluated_at,
        'last_breach_at', s.last_breach_at, 'metrics', s.metrics,
        'reputation_pause_id', (
          select p.id from public.communication_email_sending_pauses p
          where p.scope = 'organization' and p.organization_id = s.organization_id
            and p.source = 'auto_reputation' and p.released_at is null
          limit 1
        )
      ) order by case s.worst_status when 'pause' then 0 else 1 end, s.evaluated_at desc)
      from public.communication_email_reputation_state s
      join public.organizations o on o.id = s.organization_id
      where s.worst_status <> 'ok'
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_communication_email_reputation_overview()
  from public, anon, authenticated;
grant execute on function public.get_communication_email_reputation_overview() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 10. Setting a threshold. Every change closes the live row and inserts a successor.
--     A platform change needs explicit confirmation and returns its impact. An organization override
--     is rejected outright if it would weaken the ceiling.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.set_communication_email_reputation_threshold(
  p_scope text,
  p_organization_id uuid,
  p_signal text,
  p_window_key text,
  p_window_hours integer,
  p_warn_rate numeric,
  p_pause_rate numeric,
  p_min_sample_recipients integer,
  p_min_event_count integer,
  p_reason text,
  p_actor_email text,
  p_confirm_platform_change boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  ceiling public.communication_email_reputation_thresholds%rowtype;
  existing public.communication_email_reputation_thresholds%rowtype;
  new_id uuid;
  impact_count integer := 0;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if p_scope not in ('platform', 'organization') then
    raise exception 'The threshold scope is invalid.' using errcode = 'check_violation';
  end if;
  if p_signal not in ('complaint', 'hard_bounce', 'unsubscribe')
    or p_window_key not in ('rolling_24h', 'rolling_7d') then
    raise exception 'The reputation signal or window is invalid.' using errcode = 'check_violation';
  end if;

  select * into ceiling
  from public.communication_email_reputation_thresholds
  where scope = 'platform' and signal = p_signal and window_key = p_window_key and effective_to is null
  for update;
  if not found then
    raise exception 'No platform threshold exists for that signal and window.'
      using errcode = 'foreign_key_violation';
  end if;

  if p_scope = 'platform' then
    if not coalesce(p_confirm_platform_change, false) then
      raise exception 'Changing the platform safety ceiling requires explicit confirmation.'
        using errcode = 'check_violation';
    end if;
    if p_organization_id is not null then
      raise exception 'A platform threshold has no organization.' using errcode = 'check_violation';
    end if;
    if p_window_hours is null or p_warn_rate is null or p_pause_rate is null
      or p_min_sample_recipients is null then
      raise exception 'A platform threshold needs a window, both rates, and a sample size.'
        using errcode = 'check_violation';
    end if;

    select count(*)::integer into impact_count
    from public.communication_email_reputation_thresholds org
    where org.scope = 'organization' and org.signal = p_signal
      and org.window_key = p_window_key and org.effective_to is null;

    update public.communication_email_reputation_thresholds
    set effective_to = now() where id = ceiling.id;

    insert into public.communication_email_reputation_thresholds (
      scope, signal, window_key, window_hours, warn_rate, pause_rate, min_sample_recipients,
      min_event_count, reason, actor_owner_email
    ) values (
      'platform', p_signal, p_window_key, p_window_hours, p_warn_rate, p_pause_rate,
      p_min_sample_recipients, p_min_event_count, clean_reason, actor
    )
    returning id into new_id;

    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, before_state, after_state
    ) values (
      actor, 'communications.email_reputation_platform_threshold_changed',
      'communication_email_reputation_threshold', new_id::text,
      to_jsonb(ceiling) - 'id',
      jsonb_build_object('signal', p_signal, 'window_key', p_window_key, 'window_hours', p_window_hours,
        'warn_rate', p_warn_rate, 'pause_rate', p_pause_rate,
        'min_sample_recipients', p_min_sample_recipients, 'min_event_count', p_min_event_count,
        'reason', clean_reason, 'organization_overrides_affected', impact_count)
    );

    return jsonb_build_object('id', new_id, 'scope', 'platform',
      'organization_overrides_affected', impact_count);
  end if;

  -- Organization override.
  if p_organization_id is null then
    raise exception 'An organization is required for an organization threshold.'
      using errcode = 'check_violation';
  end if;
  if p_window_hours is not null then
    raise exception 'Observation windows are set at the platform level only.'
      using errcode = 'check_violation';
  end if;
  perform 1 from public.organizations where id = p_organization_id;
  if not found then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  select * into existing
  from public.communication_email_reputation_thresholds
  where scope = 'organization' and organization_id = p_organization_id
    and signal = p_signal and window_key = p_window_key and effective_to is null
  for update;

  -- Clearing the override: close the live row and inherit the ceiling again.
  if num_nonnulls(p_warn_rate, p_pause_rate, p_min_sample_recipients, p_min_event_count) = 0 then
    if not found then
      return jsonb_build_object('id', null, 'scope', 'organization', 'cleared', true);
    end if;
    update public.communication_email_reputation_thresholds
    set effective_to = now() where id = existing.id;
    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, before_state, after_state
    ) values (
      actor, 'communications.email_reputation_organization_threshold_cleared', 'organization',
      p_organization_id::text, to_jsonb(existing) - 'id',
      jsonb_build_object('reason', clean_reason)
    );
    return jsonb_build_object('id', existing.id, 'scope', 'organization', 'cleared', true);
  end if;

  if p_warn_rate is not null and p_warn_rate > ceiling.warn_rate then
    raise exception 'An organization warning rate cannot exceed the platform ceiling of %.',
      ceiling.warn_rate using errcode = 'check_violation';
  end if;
  if p_pause_rate is not null and p_pause_rate > ceiling.pause_rate then
    raise exception 'An organization pause rate cannot exceed the platform ceiling of %.',
      ceiling.pause_rate using errcode = 'check_violation';
  end if;
  if p_min_sample_recipients is not null and p_min_sample_recipients > ceiling.min_sample_recipients then
    raise exception 'An organization sample size cannot exceed the platform ceiling of %.',
      ceiling.min_sample_recipients using errcode = 'check_violation';
  end if;
  if p_min_event_count is not null and ceiling.min_event_count is not null
    and p_min_event_count > ceiling.min_event_count then
    raise exception 'An organization event trigger cannot exceed the platform ceiling of %.',
      ceiling.min_event_count using errcode = 'check_violation';
  end if;
  if p_warn_rate is not null and p_pause_rate is not null and p_warn_rate > p_pause_rate then
    raise exception 'The warning rate must be at or below the pause rate.'
      using errcode = 'check_violation';
  end if;

  if found then
    update public.communication_email_reputation_thresholds
    set effective_to = now() where id = existing.id;
  end if;

  insert into public.communication_email_reputation_thresholds (
    scope, organization_id, signal, window_key, warn_rate, pause_rate, min_sample_recipients,
    min_event_count, reason, actor_owner_email
  ) values (
    'organization', p_organization_id, p_signal, p_window_key, p_warn_rate, p_pause_rate,
    p_min_sample_recipients, p_min_event_count, clean_reason, actor
  )
  returning id into new_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_reputation_organization_threshold_changed', 'organization',
    p_organization_id::text,
    case when existing.id is not null then to_jsonb(existing) - 'id' end,
    jsonb_build_object('threshold_id', new_id, 'signal', p_signal, 'window_key', p_window_key,
      'warn_rate', p_warn_rate, 'pause_rate', p_pause_rate,
      'min_sample_recipients', p_min_sample_recipients, 'min_event_count', p_min_event_count,
      'reason', clean_reason)
  );

  return jsonb_build_object('id', new_id, 'scope', 'organization', 'cleared', false);
end;
$$;

revoke all on function public.set_communication_email_reputation_threshold(
  text, uuid, text, text, integer, numeric, numeric, integer, integer, text, text, boolean
) from public, anon, authenticated;
grant execute on function public.set_communication_email_reputation_threshold(
  text, uuid, text, text, integer, numeric, numeric, integer, integer, text, text, boolean
) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 11. Resuming an automatic pause. Jafar only, and only knowingly: if the organization is still at or
--     beyond a pause threshold, the resume is refused unless remediation review is confirmed.
--     Resuming never releases stale optional mail -- optional follow-ups expire after 24 hours
--     (§ Queueing, retries, and history), so anything older than that is cancelled, not delivered.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.resume_communication_email_reputation_pause(
  p_organization_id uuid,
  p_reason text,
  p_actor_email text,
  p_confirm_remediation boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  existing public.communication_email_sending_pauses%rowtype;
  still_breaching boolean;
  expired_count integer := 0;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;

  select * into existing
  from public.communication_email_sending_pauses
  where scope = 'organization' and organization_id = p_organization_id
    and source = 'auto_reputation' and released_at is null
  for update;
  if not found then
    return jsonb_build_object('released', false, 'reason_code', 'no_active_reputation_pause');
  end if;

  select exists (
    select 1 from private.communication_email_reputation_metrics(p_organization_id, now()) m
    where m.status = 'pause'
  ) into still_breaching;

  if still_breaching and not coalesce(p_confirm_remediation, false) then
    raise exception 'This organization is still at or above a pause threshold. Confirm remediation review to resume.'
      using errcode = 'check_violation';
  end if;

  update public.communication_email_sending_pauses
  set released_at = now(), released_by_owner_email = actor, released_reason = clean_reason
  where id = existing.id;

  -- Stale optional backlog: cancelled, never released.
  with stale as (
    select event.id as event_id, intent.id as intent_id
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.status in ('pending', 'failed')
      and intent.organization_id = p_organization_id
      and intent.allowance_class = 'optional'
      and intent.failure_code = 'sending_paused_reputation'
      and intent.created_at < now() - interval '24 hours'
  ),
  cancelled_intents as (
    update public.communication_delivery_intents intent
    set status = 'cancelled', provider_message_id = null, accepted_at = null,
      failure_code = 'optional_expired_during_pause',
      failure_message = 'Optional email expired while sending was paused and was not delivered.'
    from stale
    where intent.id = stale.intent_id
    returning intent.id
  ),
  cancelled_events as (
    update public.communication_outbox_events event
    set status = 'cancelled', claimed_at = null, claim_token = null,
      last_error = 'Optional email expired while sending was paused and was not delivered.'
    from stale
    where event.id = stale.event_id
    returning event.id
  )
  select count(*)::integer into expired_count from cancelled_events;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_reputation_pause_released', 'organization', p_organization_id::text,
    jsonb_build_object('pause_id', existing.id, 'engaged_reason', existing.reason,
      'evidence', existing.evidence),
    jsonb_build_object('released_reason', clean_reason, 'still_breaching', still_breaching,
      'remediation_confirmed', coalesce(p_confirm_remediation, false),
      'expired_optional_messages', expired_count)
  );

  return jsonb_build_object('released', true, 'pause_id', existing.id,
    'still_breaching', still_breaching, 'expired_optional_messages', expired_count);
end;
$$;

revoke all on function public.resume_communication_email_reputation_pause(uuid, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.resume_communication_email_reputation_pause(uuid, text, text, boolean)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 12. The manual organization pause command stays manual: it can neither see nor release the
--     automatic pause. Body is 7.3's, narrowed to source = 'manual'.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.set_communication_email_organization_pause(
  p_organization_id uuid,
  p_engage boolean,
  p_reason text,
  p_actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  existing public.communication_email_sending_pauses%rowtype;
  new_id uuid;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organizations where id = p_organization_id;
  if not found then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  select * into existing
  from public.communication_email_sending_pauses
  where scope = 'organization' and organization_id = p_organization_id
    and source = 'manual' and released_at is null
  order by engaged_at desc
  for update;

  if p_engage then
    if found then
      return existing.id;
    end if;
    insert into public.communication_email_sending_pauses (
      scope, organization_id, reason, engaged_by_owner_email, source, applies_to
    )
    values ('organization', p_organization_id, clean_reason, actor, 'manual', 'all')
    returning id into new_id;
    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, after_state
    ) values (
      actor, 'communications.email_organization_pause_engaged', 'organization',
      p_organization_id::text, jsonb_build_object('pause_id', new_id, 'reason', clean_reason)
    );
    return new_id;
  end if;

  if not found then
    return null;
  end if;
  update public.communication_email_sending_pauses
  set released_at = now(), released_by_owner_email = actor, released_reason = clean_reason
  where id = existing.id;
  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_organization_pause_released', 'organization',
    p_organization_id::text,
    jsonb_build_object('pause_id', existing.id, 'engaged_reason', existing.reason,
      'engaged_by', existing.engaged_by_owner_email),
    jsonb_build_object('released_reason', clean_reason)
  );
  return existing.id;
end;
$$;

revoke all on function public.set_communication_email_organization_pause(uuid, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.set_communication_email_organization_pause(uuid, boolean, text, text)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 13. The health read reports which kind of pause is holding a tenant.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_email_sending_health()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'platform_pause', (
      select jsonb_build_object(
        'id', p.id, 'reason', p.reason,
        'engaged_by', p.engaged_by_owner_email, 'engaged_at', p.engaged_at
      )
      from public.communication_email_sending_pauses p
      where p.scope = 'platform' and p.released_at is null
      order by p.engaged_at desc
      limit 1
    ),
    'organization_pauses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'organization_id', p.organization_id, 'organization_name', o.name,
        'reason', p.reason, 'engaged_by', p.engaged_by_owner_email, 'engaged_at', p.engaged_at,
        'source', p.source, 'applies_to', p.applies_to, 'evidence', p.evidence
      ) order by p.engaged_at desc)
      from public.communication_email_sending_pauses p
      join public.organizations o on o.id = p.organization_id
      where p.scope = 'organization' and p.released_at is null
    ), '[]'::jsonb),
    'held_email_count', (
      select count(*)
      from public.communication_outbox_events e
      join public.communication_delivery_intents i on i.id = e.delivery_intent_id
      where e.status in ('pending', 'failed')
        and i.failure_code in ('sending_paused_platform', 'sending_paused_organization',
          'sending_paused_reputation')
    ),
    'queued_email_count', (
      select count(*)
      from public.communication_outbox_events e
      where e.status in ('pending', 'failed')
    )
  );
$$;

revoke all on function public.get_communication_email_sending_health() from public, anon, authenticated;
grant execute on function public.get_communication_email_sending_health() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 14. The claim honours the class scope of a pause. A manual freeze holds everything; a reputation
--     pause holds optional mail only and lets protected-essential email through.
--     The rest of the body is migration 20260906190000's definition unchanged.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.claim_communication_outbox_event()
returns table (
  outbox_event_id uuid, delivery_intent_id uuid, claim_token uuid, recipient_email text, subject text,
  html_content text, text_content text, logical_send_key text, sender_id uuid, sender_email text,
  sender_name text, reply_to_email text, reply_to_name text
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  candidate record;
  current_recipient public.client_contact_methods;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  active_allowance record;
  allowance_limit_state text;
  allowance_limit_value integer;
  accepted_recipient_count integer;
  reserved_recipient_count integer;
  new_claim_token uuid;
  alias public.communication_reply_aliases;
  alias_domain public.communication_email_domains;
  holding_pause public.communication_email_sending_pauses%rowtype;
  hold_code text;
  hold_message text;
begin
  -- Part 7.3: an account-wide emergency pause stops the queue outright. The worker claims nothing and
  -- tries again later; queued rows keep their state and are re-checked in full when the pause lifts.
  if exists (
    select 1 from public.communication_email_sending_pauses
    where scope = 'platform' and released_at is null
  ) then
    return;
  end if;

  for candidate in
    select
      event.id as event_id,
      event.delivery_intent_id,
      intent.organization_id,
      intent.client_id,
      intent.client_contact_method_id,
      intent.recipient_email,
      intent.subject,
      intent.html_content,
      intent.text_content,
      intent.logical_send_key,
      intent.send_kind,
      intent.allowance_class,
      intent.sender_id,
      intent.reply_alias_id,
      intent.created_by
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    current_recipient := null;
    select method.* into current_recipient
    from public.client_contact_methods method
    where method.organization_id = candidate.organization_id
      and method.id = candidate.client_contact_method_id
    for share;

    if current_recipient.id is null
      or current_recipient.client_id <> candidate.client_id
      or current_recipient.kind <> 'email'
      or current_recipient.normalized_value <> candidate.recipient_email then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_no_longer_eligible',
        failure_message = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.event_id;
      continue;
    end if;

    -- Part 7.1: suppression recheck. Fail-closed and never retried -- a suppressed address is cleared
    -- by a person (7.2), not by waiting.
    if exists (
      select 1
      from public.communication_email_suppressions suppression
      where suppression.organization_id = candidate.organization_id
        and suppression.recipient_email = candidate.recipient_email
        and suppression.released_at is null
        and (
          suppression.reason = 'hard_bounce'
          or (suppression.reason = 'complaint' and candidate.allowance_class = 'optional')
        )
    ) then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_suppressed',
        failure_message = 'This recipient address is on the organization suppression list.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This recipient address is on the organization suppression list.'
      where id = candidate.event_id;
      continue;
    end if;

    -- Parts 7.3 and 7.4: an organization pause holds this tenant's mail -- deferred, not cancelled --
    -- and re-checked from scratch on every retry. A manual freeze holds every class; the automatic
    -- reputation pause holds optional mail only, so essential email keeps flowing.
    holding_pause := null;
    select pause.* into holding_pause
    from public.communication_email_sending_pauses pause
    where pause.scope = 'organization'
      and pause.organization_id = candidate.organization_id
      and pause.released_at is null
      and (pause.applies_to = 'all' or candidate.allowance_class = 'optional')
    order by case when pause.applies_to = 'all' then 0 else 1 end
    limit 1;

    if holding_pause.id is not null then
      if holding_pause.source = 'auto_reputation' then
        hold_code := 'sending_paused_reputation';
        hold_message := 'Optional email is paused while this organization''s delivery reputation is reviewed.';
      else
        hold_code := 'sending_paused_organization';
        hold_message := 'Sending for this organization is paused. UCRM will retry when it resumes.';
      end if;
      update public.communication_delivery_intents
      set failure_code = hold_code, failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '5 minutes', last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    selected_sender := null;
    if candidate.sender_id is not null then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id and sender.id = candidate.sender_id
      for share;
    elsif candidate.send_kind = 'automated' then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id
        and sender.is_organization_default and sender.lifecycle_state <> 'removed'
      order by sender.created_at, sender.id limit 1 for share;
    end if;

    if selected_sender.id is null then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    assigned_member_status := null;
    if selected_sender.assigned_user_id is not null then
      select member.status into assigned_member_status from public.organization_members member
      where member.organization_id = selected_sender.organization_id and member.user_id = selected_sender.assigned_user_id
      for share;
    end if;
    sender_domain := null;
    select domain.* into sender_domain from public.communication_email_domains domain
    where domain.organization_id = selected_sender.organization_id and domain.id = selected_sender.domain_id
    for share;

    if selected_sender.lifecycle_state = 'pending_verification'
      or (sender_domain.id is not null and sender_domain.lifecycle_state not in ('removal_pending', 'removed')
        and (sender_domain.lifecycle_state <> 'verified' or not sender_domain.provider_verified
          or not sender_domain.provider_authenticated or sender_domain.ownership_status <> 'passing'
          or sender_domain.dkim_status <> 'passing')) then
      update public.communication_delivery_intents set failure_code = 'sender_domain_temporarily_unavailable',
        failure_message = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if selected_sender.lifecycle_state <> 'enabled'
      or (candidate.send_kind = 'manual' and not selected_sender.allows_manual)
      or (candidate.send_kind = 'automated' and not selected_sender.allows_automated)
      or (selected_sender.assigned_user_id is not null and assigned_member_status is distinct from 'active')
      or sender_domain.id is null or sender_domain.purpose <> 'sending'
      or sender_domain.lifecycle_state in ('removal_pending', 'removed') then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    select * into active_allowance
    from private.resolve_communication_email_allowance(candidate.organization_id, now());
    if not found then
      update public.communication_delivery_intents set failure_code = 'email_allowance_period_unavailable',
        failure_message = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if candidate.allowance_class = 'optional' then
      allowance_limit_state := active_allowance.operational_limit_state;
      allowance_limit_value := active_allowance.operational_limit_value;
    else
      allowance_limit_state := active_allowance.essential_limit_state;
      allowance_limit_value := active_allowance.essential_limit_value;
    end if;
    if allowance_limit_state not in ('numeric', 'unlimited')
      or (allowance_limit_state = 'numeric' and allowance_limit_value is null) then
      update public.communication_delivery_intents set failure_code = 'email_allowance_unavailable',
        failure_message = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
        last_error = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    insert into public.communication_email_capacity_buckets (
      organization_id, allowance_period_id, allowance_class
    ) values (candidate.organization_id, active_allowance.period_id, candidate.allowance_class)
    on conflict do nothing;
    perform 1 from public.communication_email_capacity_buckets bucket
    where bucket.organization_id = candidate.organization_id
      and bucket.allowance_period_id = active_allowance.period_id
      and bucket.allowance_class = candidate.allowance_class
    for update;

    if allowance_limit_state = 'numeric' then
      select coalesce(sum(usage.recipient_count), 0)::integer into accepted_recipient_count
      from public.communication_email_usage_events usage
      where usage.organization_id = candidate.organization_id
        and usage.allowance_period_id = active_allowance.period_id
        and usage.allowance_class = candidate.allowance_class;
      select coalesce(sum(reservation.recipient_count), 0)::integer into reserved_recipient_count
      from public.communication_email_capacity_reservations reservation
      where reservation.organization_id = candidate.organization_id
        and reservation.allowance_period_id = active_allowance.period_id
        and reservation.allowance_class = candidate.allowance_class
        and reservation.reservation_state in ('reserved', 'submission_unknown');
      if accepted_recipient_count + reserved_recipient_count >= allowance_limit_value then
        update public.communication_delivery_intents set failure_code = 'email_allowance_exhausted',
          failure_message = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set available_at = now() + interval '15 minutes',
          last_error = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    insert into public.communication_email_capacity_reservations (
      organization_id, delivery_intent_id, allowance_period_id, allowance_class, reservation_state, reserved_at, settled_at
    ) values (
      candidate.organization_id, candidate.delivery_intent_id, active_allowance.period_id,
      candidate.allowance_class, 'reserved', now(), null
    ) on conflict on constraint communication_email_capacity_reservations_delivery_intent_key do update set
      organization_id = excluded.organization_id,
      allowance_period_id = excluded.allowance_period_id,
      allowance_class = excluded.allowance_class,
      reservation_state = 'reserved', reserved_at = now(), settled_at = null
    where public.communication_email_capacity_reservations.reservation_state = 'released';
    if not found then
      raise exception 'The email capacity reservation is not available for this delivery intent.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;

    alias := null;
    alias_domain := null;
    if candidate.reply_alias_id is not null then
      select rep_alias.* into alias from public.communication_reply_aliases rep_alias
      where rep_alias.id = candidate.reply_alias_id and rep_alias.organization_id = candidate.organization_id
      for share;
      if alias.id is not null then
        select * into alias_domain from public.communication_email_domains
        where id = alias.receiving_domain_id and organization_id = candidate.organization_id
        for share;
      end if;
    end if;

    new_claim_token := gen_random_uuid();
    update public.communication_outbox_events set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null where id = candidate.event_id;
    update public.communication_delivery_intents set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null where id = candidate.delivery_intent_id;
    return query select candidate.event_id, candidate.delivery_intent_id, new_claim_token,
      candidate.recipient_email, candidate.subject, candidate.html_content, candidate.text_content,
      candidate.logical_send_key, selected_sender.id, selected_sender.email_address, selected_sender.display_name,
      case when alias.id is not null and alias_domain.id is not null
        then alias.alias_local_part || '@' || alias_domain.domain_name else null end,
      case when alias.id is not null then selected_sender.display_name else null end;
    return;
  end loop;
end;
$function$;

revoke all on function public.claim_communication_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_outbox_event() to service_role;
