-- Automation 6D-6: the claim's fairness ranking must run over the bounded candidate slice, not the whole
-- backlog.
--
-- 6D-2a intended the per-organization ranking to see "a small slice of the queue, never the whole backlog"
-- and bounded it with `limit v_candidate_window` (<= 400). But the window function and that LIMIT sat at the
-- same query level, and Postgres evaluates window functions over the FULL input before ORDER BY/LIMIT. The
-- planner therefore Seq-Scanned every pending row, sorted the whole set to disk, ran row_number() over all of
-- it, and only then trimmed to 400. Measured on 48,000 due rows: 102 ms with an external-merge disk spill,
-- growing linearly with the backlog -- on the hottest path in the engine, run every minute by every worker.
--
-- Fix: take the candidate slice FIRST in its own subquery (bounded Index Scan on
-- automation_work_items_claim_idx + Limit), then rank only those rows. Measured on the same data: 0.75 ms,
-- 11 buffers, no spill (~135x), and now O(candidate window) instead of O(backlog).
--
-- Behaviour is identical. The slice is the earliest `v_candidate_window` rows in (available_at, id) order, so
-- it is a downward-closed prefix: for any row in the slice, every same-organization row that is "earlier" is
-- also in the slice. Each row's per-organization rank within the slice therefore equals its rank across the
-- whole backlog, so the cap decision and the final pick are unchanged. Everything after the `due` CTE is
-- copied verbatim from the 6D-2a definition.
create or replace function public.claim_automation_work_items(
  p_batch_size integer default 25,
  p_per_organization_cap integer default 5,
  p_lease_seconds integer default 120,
  p_max_attempts integer default 8,
  p_worker text default null
)
returns table (
  work_item_id uuid,
  claim_token uuid,
  organization_id uuid,
  enrollment_id uuid,
  step_index integer,
  attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_token uuid := gen_random_uuid();
  v_worker text := left(coalesce(nullif(btrim(p_worker), ''), 'automation-worker'), 100);
  v_candidate_window integer;
begin
  if p_batch_size < 1 or p_batch_size > 200 then
    raise exception 'The claim batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_per_organization_cap < 1 or p_per_organization_cap > p_batch_size then
    raise exception 'The per-organization cap is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The claim lease is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception 'The attempt cap is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  -- Dead-letter first, bounded. A row that has burned its attempts -- including one whose worker kept dying
  -- before it could report anything -- becomes visible instead of being claimed forever.
  update private.automation_work_items as w
  set state = 'needs_attention',
    attention_reason = 'max_attempts',
    attention_at = now(),
    claim_token = null,
    claimed_at = null
  where w.id in (
    select doomed.id
    from private.automation_work_items as doomed
    where doomed.state = 'pending'
      and doomed.available_at <= now()
      and doomed.attempts >= p_max_attempts
    order by doomed.available_at, doomed.id
    limit p_batch_size
    for update skip locked
  );

  -- The candidate window bounds the fairness pass: ranking is computed over a small slice of the queue, never
  -- the whole backlog. Four batches of head-room is enough for the cap to have something to reorder.
  v_candidate_window := least(p_batch_size * 4, 400);

  return query
  -- 6D-6: bound the slice BEFORE ranking it. This subquery is the only change from the 6D-2a definition.
  with candidates as (
    select w.id, w.available_at, w.organization_id
    from private.automation_work_items as w
    where w.state = 'pending'
      and w.available_at <= now()
      and w.attempts < p_max_attempts
    order by w.available_at, w.id
    limit v_candidate_window
  ),
  due as (
    select
      candidates.id,
      candidates.available_at,
      row_number() over (
        partition by candidates.organization_id order by candidates.available_at, candidates.id
      ) as per_organization_rank
    from candidates
  ),
  -- Sorting on the boolean puts every within-cap row first (false < true), then lets over-cap rows fill
  -- whatever capacity is left. One pass, both rules.
  ranked as (
    select
      due.id,
      row_number() over (
        order by (due.per_organization_rank > p_per_organization_cap), due.available_at, due.id
      ) as pick_order
    from due
  ),
  picked as (
    select ranked.id from ranked where ranked.pick_order <= p_batch_size
  ),
  locked as (
    select w.id
    from private.automation_work_items as w
    where w.id in (select picked.id from picked)
    order by w.available_at, w.id
    for update skip locked
  )
  update private.automation_work_items as w
  set claim_token = v_token,
    claimed_at = now(),
    claimed_by = v_worker,
    attempts = w.attempts + 1,
    -- The claim IS the lease: the row stops being due until the lease passes.
    available_at = now() + make_interval(secs => p_lease_seconds),
    last_error_code = null,
    last_error_message = null
  from locked
  where w.id = locked.id
  returning w.id, w.claim_token, w.organization_id, w.enrollment_id, w.step_index, w.attempts;
end;
$$;

comment on function public.claim_automation_work_items(integer, integer, integer, integer, text) is
  'Atomically claims a bounded, organization-fair batch of due work under a per-row lease. Safe to run from '
  'any number of workers at once: there is no global lock, and an abandoned claim recovers when its lease '
  'passes. Service role only.';

revoke all on function public.claim_automation_work_items(integer, integer, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.claim_automation_work_items(integer, integer, integer, integer, text)
  to service_role;
