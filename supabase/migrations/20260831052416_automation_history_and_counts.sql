-- Automation Part 6D-4: contractor-facing history and real counts.
--
-- The engine's truth lives in `private` (events, enrollments, matches, work items) and has NO grant to
-- anon/authenticated and is not exposed through PostgREST -- a contractor can never read those tables
-- directly. 6D-4 exposes two DELIBERATE, SAFE projections instead, through `public` security-definer read
-- functions that the app calls with the service client AFTER requireAutomationAccess has verified the caller's
-- organization and `view` permission (the same shape as create_automation_recipe_draft).
--
-- What crosses the boundary is a summary only: outcome, a short engine-authored reason, the subject id, and
-- bounded counts. What NEVER crosses: the enrollment `context` snapshot, event payloads, rendered message
-- bodies, and every lease/attempt/worker column. That omission is the 6D-4 completion gate.
--
-- No maintained counter is added (contract § Query, index, and count): the active-enrollment count is a
-- bounded indexed query. A maintained count is reconsidered only if 6D/6E measurement proves this misses its
-- budget.

-- ---------------------------------------------------------------------------------------------------
-- 1. Indexes the two reads are designed around.
-- ---------------------------------------------------------------------------------------------------

-- Recipe history: one recipe's match rows, newest decision first, unique id tie-breaker for keyset paging
-- (contract § Query, index, and count -> "Recipe history"). created_at is the decision time and lives on the
-- match row, so ordering needs no join.
create index automation_event_matches_recipe_idx
  on private.automation_event_matches (organization_id, recipe_id, created_at desc, id desc);

-- Active-enrollment count per recipe for the home list. Partial so it tracks only live enrollments, not the
-- full enrollment history, and answers the grouped count from an index range.
create index automation_enrollments_recipe_active_idx
  on private.automation_enrollments (organization_id, recipe_id)
  where state = 'active';

-- ---------------------------------------------------------------------------------------------------
-- 2. Active-enrollment counts for a page of recipes.
-- ---------------------------------------------------------------------------------------------------
-- Bounded: the caller passes at most one home page of recipe ids. Returns only recipes that have at least one
-- active enrollment; the caller treats a missing recipe as zero.
create function public.automation_active_enrollment_counts(
  p_organization_id uuid,
  p_recipe_ids uuid[]
)
returns table (recipe_id uuid, active_count bigint)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select e.recipe_id, count(*)::bigint as active_count
  from private.automation_enrollments e
  where e.organization_id = p_organization_id
    and e.recipe_id = any (p_recipe_ids)
    and e.state = 'active'
  group by e.recipe_id;
$$;

comment on function public.automation_active_enrollment_counts(uuid, uuid[]) is
  'Safe projection: how many subjects are currently enrolled (state = active) in each of the given recipes. '
  'Reads private.automation_enrollments under a security-definer boundary; exposes only the bounded count.';

revoke all on function public.automation_active_enrollment_counts(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.automation_active_enrollment_counts(uuid, uuid[])
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. One recipe's history: what the automation did, and for the skips, the plain reason it did not run.
-- ---------------------------------------------------------------------------------------------------
-- Cursor paginated on (created_at desc, id desc). The subject and (for enrolled rows) the enrollment summary
-- are PK look-ups against the <= p_limit rows the index already picked, so the join never widens the scan.
-- Projected columns are all safe: outcome and detail are engine-authored, subject_id is an identifier the
-- caller already may link to, and the two enrollment fields are bounded counts/state. The enrollment `context`
-- snapshot, event payload, and every worker/lease column are deliberately absent.
create function public.automation_recipe_history(
  p_organization_id uuid,
  p_recipe_id uuid,
  -- Null cursor = first page. Defaults let the caller omit them entirely for that page.
  p_before_happened_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default null
)
returns table (
  id uuid,
  happened_at timestamptz,
  outcome text,
  detail text,
  subject_type text,
  subject_id uuid,
  enrollment_state text,
  customer_messages_sent integer
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    em.id,
    em.created_at as happened_at,
    em.outcome,
    em.detail,
    ev.subject_type,
    ev.subject_id,
    en.state as enrollment_state,
    en.customer_messages_sent
  from private.automation_event_matches em
  join private.automation_events ev on ev.id = em.event_id
  left join private.automation_enrollments en on en.id = em.enrollment_id
  where em.organization_id = p_organization_id
    and em.recipe_id = p_recipe_id
    and (
      p_before_happened_at is null
      or em.created_at < p_before_happened_at
      or (em.created_at = p_before_happened_at and em.id < p_before_id)
    )
  order by em.created_at desc, em.id desc
  limit least(greatest(coalesce(p_limit, 25), 1), 50);
$$;

comment on function public.automation_recipe_history(uuid, uuid, timestamptz, uuid, integer) is
  'Safe projection: one recipe''s history, newest first, keyset-paginated. Each row is one (event, recipe) '
  'decision -- enrolled, or the plain reason it was not. Reads private engine tables under a security-definer '
  'boundary and exposes summaries only: never the enrollment context snapshot, event payload, message body, '
  'or any worker/lease state (docs/automation-behavior-contract.md § Query, index, and count).';

revoke all on function public.automation_recipe_history(uuid, uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.automation_recipe_history(uuid, uuid, timestamptz, uuid, integer)
  to service_role;
