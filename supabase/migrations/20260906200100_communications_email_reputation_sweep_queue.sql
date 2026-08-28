-- Communications Part 7.4 follow-up (performance review of the reputation layer).
--
-- Three findings from the review, fixed here:
--
--  1. The sweep read every adverse callback of the last seven days on every run, every five minutes.
--     That set grows with platform volume for ever, while the answer it produces -- "which tenants
--     got a new adverse event" -- is bounded by the number of tenants. Replaced with the standard
--     dirty-queue: the callback processor flags the organization when it lands an adverse event, and
--     the sweep reads only flagged rows. Cost is now O(tenants needing work), not O(recent events),
--     and it survives an outage because the flag is durable.
--  2. evaluate_communication_email_reputation() ran the metrics function twice -- once to aggregate,
--     once to find the worst breach. The second pass now reads the jsonb the first one produced.
--  3. communication_email_sending_pauses_org_lookup_idx is a strict prefix of the newer unique
--     (organization_id, source) index with the same predicate. Dropped; write cost for nothing.
--
-- communication_provider_callback_events_adverse_recent_idx existed only for the old sweep scan and
-- goes with it.

-- ---------------------------------------------------------------------------------------------------
-- 1. The queue column
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_email_reputation_state
  add column evaluation_requested_at timestamptz;

comment on column public.communication_email_reputation_state.evaluation_requested_at is
  'Set by the callback processor when an adverse event lands for this organization; cleared by the sweep once that request has been evaluated. Null means nothing is waiting.';

create index communication_email_reputation_state_pending_idx
  on public.communication_email_reputation_state (evaluation_requested_at)
  where evaluation_requested_at is not null;

drop index if exists public.communication_provider_callback_events_adverse_recent_idx;
drop index if exists public.communication_email_sending_pauses_org_lookup_idx;

-- ---------------------------------------------------------------------------------------------------
-- 2. The callback processor flags the organization. Re-emitted whole; the only change is the block
--    marked below.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.process_communication_provider_callbacks(batch_size integer default 500)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate record;
  norm text;
  processed_count integer := 0;
begin
  if batch_size < 1 or batch_size > 2000 then
    raise exception 'The callback batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select
      cb.id,
      cb.event_kind,
      cb.occurred_at,
      cb.received_at,
      cb.delivery_intent_id,
      intent.organization_id,
      intent.recipient_email,
      intent.delivery_outcome as current_outcome
    from public.communication_provider_callback_events cb
    left join public.communication_delivery_intents intent on intent.id = cb.delivery_intent_id
    where cb.processed_at is null
    order by cb.received_at, cb.id
    limit batch_size
    for update of cb skip locked
  loop
    norm := case lower(trim(candidate.event_kind))
      when 'delivered' then 'delivered'
      when 'soft_bounce' then 'soft_bounce'
      when 'hard_bounce' then 'hard_bounce'
      when 'invalid_email' then 'hard_bounce'
      when 'blocked' then 'blocked'
      when 'spam' then 'complaint'
      when 'complaint' then 'complaint'
      when 'deferred' then 'deferred'
      when 'unsubscribed' then 'unsubscribed'
      when 'list_addition' then 'other'
      when 'opened' then 'opened'
      when 'unique_opened' then 'opened'
      when 'click' then 'clicked'
      when 'proxy_open' then 'opened'
      else 'other'
    end;

    -- No resolved intent (a callback with no ucrm tag, or one that arrived before its intent): mark it
    -- processed so it stops being claimed, but leave its organization unresolved. Nothing downstream
    -- counts an event with a null organization.
    if candidate.delivery_intent_id is null or candidate.organization_id is null then
      update public.communication_provider_callback_events
      set processed_at = now(), normalized_kind = norm
      where id = candidate.id;
      processed_count := processed_count + 1;
      continue;
    end if;

    -- Latest provider word wins, except a terminal outcome (hard bounce / complaint) is only ever
    -- replaced by another terminal outcome -- a stray later 'delivered' never un-bounces a message.
    if norm in ('delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked', 'unsubscribed') then
      update public.communication_delivery_intents
      set delivery_outcome = norm,
        delivery_outcome_at = coalesce(candidate.occurred_at, candidate.received_at),
        delivery_outcome_detail = nullif(trim(candidate.event_kind), '')
      where id = candidate.delivery_intent_id
        and (
          delivery_outcome is null
          or delivery_outcome not in ('hard_bounce', 'complaint')
          or norm in ('hard_bounce', 'complaint')
        );
    end if;

    -- Complaint and hard bounce open an auditable suppression. A row already live for this
    -- (organization, address, reason) is left untouched -- its evidence is the first one we saw.
    if norm in ('complaint', 'hard_bounce') then
      insert into public.communication_email_suppressions (
        organization_id, recipient_email, reason, source, source_callback_event_id,
        first_delivery_intent_id, evidence
      ) values (
        candidate.organization_id, candidate.recipient_email, norm, 'provider_callback', candidate.id,
        candidate.delivery_intent_id,
        jsonb_build_object(
          'event_kind', candidate.event_kind,
          'occurred_at', candidate.occurred_at,
          'received_at', candidate.received_at
        )
      )
      on conflict (organization_id, recipient_email, reason) where released_at is null
      do nothing;
    end if;

    -- CHANGED IN THE 7.4 FOLLOW-UP: an adverse event is the only thing that can worsen a reputation
    -- rate, so it -- and nothing else -- asks for a re-evaluation. The newest request time always
    -- wins: the sweep clears the flag only if it is still the value it evaluated, so an event that
    -- lands mid-evaluation leaves the organization queued instead of being swallowed.
    if norm in ('complaint', 'hard_bounce', 'unsubscribed') then
      insert into public.communication_email_reputation_state (organization_id, evaluation_requested_at)
      values (candidate.organization_id, now())
      on conflict (organization_id) do update
      set evaluation_requested_at = excluded.evaluation_requested_at;
    end if;

    update public.communication_provider_callback_events
    set processed_at = now(), normalized_kind = norm, organization_id = candidate.organization_id
    where id = candidate.id;
    processed_count := processed_count + 1;
  end loop;

  return processed_count;
end;
$$;

revoke all on function public.process_communication_provider_callbacks(integer) from public, anon, authenticated;
grant execute on function public.process_communication_provider_callbacks(integer) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. Evaluate once, read twice.
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
  breach jsonb;
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

  -- The worst breach comes out of the measurement we already have, not a second pass over it.
  select entry into breach
  from jsonb_array_elements(measured) entry
  where entry ->> 'status' = 'pause'
  order by ((entry ->> 'rate')::numeric / nullif((entry ->> 'pause_rate')::numeric, 0)) desc nulls last
  limit 1;

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
    replace(breach ->> 'signal', '_', ' '), breach ->> 'rate',
    case breach ->> 'window_key' when 'rolling_24h' then 'rolling 24-hour' else 'rolling 7-day' end,
    breach ->> 'pause_rate', breach ->> 'event_count', breach ->> 'accepted_recipients'
  );

  insert into public.communication_email_sending_pauses (
    scope, organization_id, reason, engaged_by_owner_email, source, applies_to, evidence
  ) values (
    'organization', p_organization_id, pause_reason, 'system', 'auto_reputation', 'optional',
    jsonb_build_object('signal', breach ->> 'signal', 'window_key', breach ->> 'window_key',
      'rate', (breach ->> 'rate')::numeric, 'pause_rate', (breach ->> 'pause_rate')::numeric,
      'event_count', (breach ->> 'event_count')::bigint,
      'accepted_recipients', (breach ->> 'accepted_recipients')::bigint,
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
-- 4. The sweep drains the queue.
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
    select state.organization_id, state.evaluation_requested_at
    from public.communication_email_reputation_state state
    where state.evaluation_requested_at is not null
    order by state.evaluation_requested_at
    limit batch_size
  loop
    perform public.evaluate_communication_email_reputation(candidate.organization_id, now());

    update public.communication_email_reputation_state
    set evaluation_requested_at = null
    where organization_id = candidate.organization_id
      and evaluation_requested_at = candidate.evaluation_requested_at;

    evaluated_count := evaluated_count + 1;
  end loop;

  return evaluated_count;
end;
$$;

revoke all on function public.sweep_communication_email_reputation(integer)
  from public, anon, authenticated;
grant execute on function public.sweep_communication_email_reputation(integer) to service_role;
