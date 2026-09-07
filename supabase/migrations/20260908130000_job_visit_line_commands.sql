-- Invoices Part 5c-5: a visit's own quantities.
--
-- 5c-1 built the table (public.job_visit_line_items) and its rules, and nothing has read or written it since.
-- This file gives it the three things it was waiting for:
--
--   1. private.job_visit_effective_lines  -- what does THIS visit actually bill? (the one answer everyone uses)
--   2. public.job_visit_lines             -- the gated read behind the visit editor and the invoice composer
--   3. public.replace_job_visit_line_items -- the whole set for one visit, replaced in one transaction
--
-- The rule the table's own comment states is the rule enforced here: no rows means the visit bills the job's
-- lines unchanged. Rows mean this visit's complete billable set. A saved visit line is a snapshot, never a
-- pointer -- source_job_line_item_id records where a row came from so the editor can tell "the job's line,
-- unchanged" from "a line only this visit has", and nothing more.
--
-- Deliberately not here: anything about fixed_per_period jobs. Those bill the job's lines by period and
-- ignore visit overrides entirely, which is why the write command refuses a job that is not per_visit.

-- 1. What one visit actually bills -----------------------------------------------------------------------------

-- One place decides "override rows if there are any, otherwise the job's own lines", so the editor, the
-- composer, the batch planner and the totals can never disagree about what a visit is worth. Private, and
-- invoker: every caller is a definer function that has already proved the reader may see this job.
--
-- Cost is bounded by one visit: at most 100 override rows (the table's own trigger) or the job's at most 100
-- lines, each served by job_visit_line_items_visit_idx or job_line_items_job_idx.
create or replace function private.job_visit_effective_lines(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_id uuid
)
returns table (
  id uuid,
  is_override boolean,
  "position" integer,
  source_job_line_item_id uuid,
  source_catalog_item_id uuid,
  line_kind text,
  category text,
  is_labor boolean,
  name text,
  description text,
  unit_label text,
  quantity numeric,
  unit_price_minor bigint,
  unit_cost_minor bigint,
  is_taxable boolean,
  image_attachment_id uuid,
  line_total_minor bigint
)
language sql
stable
set search_path = pg_catalog, public
as $$
  select
    item.id, true, item.position, item.source_job_line_item_id, item.source_catalog_item_id,
    item.line_kind, item.category, item.is_labor, item.name, item.description, item.unit_label,
    item.quantity, item.unit_price_minor, item.unit_cost_minor, item.is_taxable,
    item.image_attachment_id, item.line_total_minor
  from public.job_visit_line_items as item
  where item.organization_id = target_organization_id
    and item.visit_id = target_visit_id

  union all

  select
    line.id, false, line.position, line.id, line.source_catalog_item_id,
    line.line_kind, line.category, line.is_labor, line.name, line.description, line.unit_label,
    line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_attachment_id, line.line_total_minor
  from public.job_line_items as line
  where line.organization_id = target_organization_id
    and line.job_id = target_job_id
    and not exists (
      select 1
      from public.job_visit_line_items as override
      where override.organization_id = target_organization_id
        and override.visit_id = target_visit_id
    )

  order by 3, 1;
$$;

comment on function private.job_visit_effective_lines(uuid, uuid, uuid) is
  'One visit''s effective lines: its own rows if it has any, otherwise the job''s. The single answer every '
  'reader, editor and biller uses, so none of them can price a visit differently from another.';

revoke all on function private.job_visit_effective_lines(uuid, uuid, uuid) from public;
revoke execute on function private.job_visit_effective_lines(uuid, uuid, uuid) from anon, authenticated;

-- 2. The gated read ---------------------------------------------------------------------------------------------

-- Behind two screens: the visit editor (one visit) and the invoice composer seeding a bill from visits that
-- were already chosen (several). One call either way, because the composer needs every chosen visit's lines
-- before it can show a single row, and one round trip per visit would be a waterfall.
--
-- Money obeys the job contract: prices need jobs.view_price and cost needs jobs.view_cost. A reader without
-- them still gets names, quantities and order, which is what a crew member's copy of the work looks like
-- everywhere else in this app.
create or replace function public.job_visit_lines(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_price boolean;
  can_cost boolean;
  wanted uuid[] := coalesce(target_visit_ids, '{}'::uuid[]);
  answer jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view') then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  -- The same 100 the claim command caps one invoice at: a longer selection could not be billed in one go,
  -- so answering it would be a promise the next screen cannot keep.
  if cardinality(wanted) > 100 then
    raise exception 'Too many visits were asked for at once.' using errcode = '54000';
  end if;

  can_price := private.member_has_permission(target_organization_id, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'visit_id', visit.id,
        'visit_date', visit.visit_date,
        'completed', visit.completed_at is not null,
        'revision', visit.revision,
        -- Whether this visit carries its own set. False means it is showing the job's lines and has not been
        -- customised, which is what the editor's "back to the job's lines" state is.
        'has_override', exists (
          select 1
          from public.job_visit_line_items as override
          where override.organization_id = target_organization_id
            and override.visit_id = visit.id
        ),
        -- Locked pricing, and why. A completed visit is a record of work done; an invoiced one is history a
        -- customer has seen. Both refuse an edit in the write command; the editor reads this to say so first.
        'locked', visit.completed_at is not null or claimed.invoiced,
        'lock_reason', case
          when claimed.invoiced then 'invoiced'
          when visit.completed_at is not null then 'completed'
          else null
        end,
        'subtotal_minor', case when can_price then coalesce(effective.subtotal_minor, 0) else null end,
        'lines', coalesce(effective.lines, '[]'::jsonb)
      )
      order by visit.visit_date nulls last, visit.position, visit.id
    ),
    '[]'::jsonb
  ) into answer
  from public.job_visits as visit
  cross join lateral (
    select exists (
      select 1
      from public.invoice_sources as claim
      where claim.organization_id = target_organization_id
        and claim.visit_id = visit.id
        and claim.source_kind = 'visit'
    ) as invoiced
  ) as claimed
  cross join lateral (
    select
      sum(line.line_total_minor) filter (where line.line_kind = 'priced') as subtotal_minor,
      jsonb_agg(
        jsonb_build_object(
          'id', line.id,
          'is_override', line.is_override,
          'source_job_line_item_id', line.source_job_line_item_id,
          'catalog_item_id', line.source_catalog_item_id,
          'line_kind', line.line_kind,
          'category', line.category,
          'is_labor', line.is_labor,
          'name', line.name,
          'description', line.description,
          'unit_label', line.unit_label,
          'quantity', line.quantity,
          'is_taxable', line.is_taxable,
          'image_attachment_id', line.image_attachment_id
        )
        || (case when can_price then jsonb_build_object(
              'unit_price_minor', line.unit_price_minor,
              'line_total_minor', line.line_total_minor
            ) else '{}'::jsonb end)
        || (case when can_cost then jsonb_build_object(
              'unit_cost_minor', line.unit_cost_minor
            ) else '{}'::jsonb end)
        order by line.position, line.id
      ) as lines
    from private.job_visit_effective_lines(target_organization_id, target_job_id, visit.id) as line
  ) as effective
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = any(wanted);

  return jsonb_build_object('visits', answer);
end;
$$;

comment on function public.job_visit_lines(uuid, uuid, uuid[]) is
  'Effective lines for up to 100 of one job''s visits, with each visit''s own subtotal, whether it carries '
  'its own set, and whether its pricing is locked. Prices need jobs.view_price, cost needs jobs.view_cost.';

revoke all on function public.job_visit_lines(uuid, uuid, uuid[]) from public;
revoke execute on function public.job_visit_lines(uuid, uuid, uuid[]) from anon;
grant execute on function public.job_visit_lines(uuid, uuid, uuid[]) to authenticated;

-- 3. Replacing one visit's set --------------------------------------------------------------------------------

-- The twin of replace_job_line_items, one level down. Same shape of promise: the whole set at once, the
-- table's own constraints as the only judge of a line, and a stale revision refused rather than merged.
--
-- Two rules this command owns that the job's does not:
--
--   * An empty list is not "bill nothing". It is "go back to the job's lines" -- the state the visit was in
--     before anyone customised it, and the only way back. Billing nothing is not a thing a visit can mean.
--   * Pricing freezes when the work is done or billed. update_job_visit already refuses a completed visit;
--     this one refuses an invoiced one too, because a customer has seen those numbers.
create or replace function public.replace_job_visit_line_items(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_id uuid,
  expected_revision integer,
  new_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  current_visit public.job_visits;
  line_count integer := 0;
begin
  if caller is null then
    raise exception 'You must be signed in to price a visit.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'A visit''s pricing must be a list of lines.' using errcode = 'check_violation';
  end if;

  -- Job first, then visit: the same lock order every command in this campaign takes, so two of them running
  -- at once queue rather than deadlock.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  if current_job.status <> 'active' then
    raise exception 'A closed job''s visits cannot be repriced.' using errcode = 'P0410';
  end if;

  -- Per-visit pricing is the whole point of this table. A job billed by period bills the job's lines for the
  -- period, so a visit override there would be saved and silently never used.
  if current_job.price_basis is distinct from 'per_visit' then
    raise exception 'Only a job billed per visit can price its visits separately.'
      using errcode = 'check_violation',
      hint = 'Change the job''s billing to per visit first.';
  end if;

  select visit.* into current_visit
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = target_visit_id
  for update;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;

  if current_visit.completed_at is not null then
    raise exception 'A completed visit''s pricing cannot be changed.' using errcode = 'P0410',
      hint = 'Reopen the visit first if the work was different from what was recorded.';
  end if;

  if exists (
    select 1
    from public.invoice_sources as claim
    where claim.organization_id = target_organization_id
      and claim.visit_id = target_visit_id
      and claim.source_kind = 'visit'
  ) then
    raise exception 'An invoiced visit''s pricing cannot be changed.' using errcode = 'P0410';
  end if;

  if current_visit.revision is distinct from expected_revision then
    raise exception 'Someone else changed this visit. Reload to see the latest.' using errcode = 'P0409';
  end if;

  delete from public.job_visit_line_items
  where organization_id = target_organization_id
    and visit_id = target_visit_id;

  -- A duplicated row keeps its own numbers but gives up its provenance: source_job_line_item_id is unique
  -- per visit precisely so "the job's line, changed" stays one row and everything else is a visit-only line.
  insert into public.job_visit_line_items (
    organization_id, job_id, visit_id, position, source_job_line_item_id, source_catalog_item_id,
    line_kind, category, is_labor, name, description, unit_label, quantity, unit_price_minor,
    unit_cost_minor, is_taxable, image_attachment_id
  )
  select
    target_organization_id,
    target_job_id,
    target_visit_id,
    (numbered.rank - 1)::integer,
    case when numbered.source_rank = 1 then numbered.source_job_line_item_id end,
    numbered.source_catalog_item_id,
    numbered.line_kind,
    numbered.category,
    numbered.is_labor,
    numbered.name,
    numbered.description,
    numbered.unit_label,
    numbered.quantity,
    numbered.unit_price_minor,
    numbered.unit_cost_minor,
    numbered.is_taxable,
    numbered.image_attachment_id
  from (
    select
      row_number() over (order by (line.value->>'position')::integer, line.ordinality) as rank,
      nullif(line.value->>'source_job_line_item_id', '')::uuid as source_job_line_item_id,
      row_number() over (
        partition by nullif(line.value->>'source_job_line_item_id', '')::uuid
        order by (line.value->>'position')::integer, line.ordinality
      ) as source_rank,
      nullif(line.value->>'source_catalog_item_id', '')::uuid as source_catalog_item_id,
      coalesce(line.value->>'line_kind', 'priced') as line_kind,
      nullif(line.value->>'category', '') as category,
      coalesce((line.value->>'is_labor')::boolean, false) as is_labor,
      line.value->>'name' as name,
      nullif(line.value->>'description', '') as description,
      nullif(line.value->>'unit_label', '') as unit_label,
      (line.value->>'quantity')::numeric as quantity,
      (line.value->>'unit_price_minor')::bigint as unit_price_minor,
      (line.value->>'unit_cost_minor')::bigint as unit_cost_minor,
      coalesce((line.value->>'is_taxable')::boolean, true) as is_taxable,
      nullif(line.value->>'image_attachment_id', '')::uuid as image_attachment_id
    from jsonb_array_elements(new_lines) with ordinality as line(value, ordinality)
  ) as numbered;

  get diagnostics line_count = row_count;

  -- A visit line that names a job line from another job would be a cross-job price. The composite foreign key
  -- already refuses another organization's line; this refuses another job's.
  if exists (
    select 1
    from public.job_visit_line_items as item
    join public.job_line_items as source
      on source.organization_id = item.organization_id
     and source.id = item.source_job_line_item_id
    where item.organization_id = target_organization_id
      and item.visit_id = target_visit_id
      and source.job_id <> target_job_id
  ) then
    raise exception 'A visit can only change lines that belong to its own job.' using errcode = 'check_violation';
  end if;

  update public.job_visits
  set revision = current_visit.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id
    and id = target_visit_id;

  -- Redacted, like every other job event: how many lines this visit now carries and whether it is on its own
  -- set at all, never what they say or what they cost.
  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visit_updated',
    caller,
    target_visit_id,
    jsonb_build_object(
      'changed', to_jsonb(array['pricing']),
      'line_count', line_count,
      'has_override', line_count > 0
    )
  );

  return jsonb_build_object(
    'revision', current_visit.revision + 1,
    'line_count', line_count,
    'has_override', line_count > 0
  );
end;
$$;

comment on function public.replace_job_visit_line_items(uuid, uuid, uuid, integer, jsonb) is
  'Replaces one visit''s own priced lines in one transaction. Checks jobs.edit, refuses a job that is not '
  'billed per visit, a completed or invoiced visit (P0410) and a stale revision (P0409). An empty list '
  'clears the override, putting the visit back on the job''s lines.';

revoke all on function public.replace_job_visit_line_items(uuid, uuid, uuid, integer, jsonb) from public;
revoke execute on function public.replace_job_visit_line_items(uuid, uuid, uuid, integer, jsonb) from anon;
grant execute on function public.replace_job_visit_line_items(uuid, uuid, uuid, integer, jsonb) to authenticated;
