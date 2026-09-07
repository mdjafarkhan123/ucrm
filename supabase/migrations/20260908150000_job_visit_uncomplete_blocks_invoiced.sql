-- Invoices Part 5c-5c BUG 2: a visit that is already on an invoice cannot be reopened.

-- "Mark Incomplete" used to be allowed on a billed visit. Nothing was double-billed -- the invoice command
-- still refused the second claim -- but the visit walked back to UPCOMING with a full menu (including
-- Delete), raised a second "ready to bill" reminder, and re-offered an invoice the person could carry all
-- the way to the composer before being told no. The claim is the fact that matters: while
-- invoice_sources holds a 'visit' row for this visit, the visit's completion is what that invoice was
-- written from, so it stays put. This is the same predicate replace_job_visit_line_items already uses to
-- freeze an invoiced visit's pricing (migration 20260908130000), and it is served by
-- invoice_sources_visit_unique_idx. A void does not release the claim (D4), so any claim row means locked.

-- Unchanged from 20260903120000 except for the new refusal. It sits AFTER the already-incomplete early
-- return on purpose: reopening a visit that is already open changes nothing, so it stays the idempotent
-- no-op it has always been rather than becoming an error the browser has to explain.
create or replace function public.uncomplete_job_visit(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_id uuid
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
begin
  if caller is null then
    raise exception 'You must be signed in to change a visit.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.complete') then
    raise exception 'You do not have access to complete this visit.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'closed' then
    raise exception 'A closed job''s visits cannot be changed. Reopen the job first.' using errcode = 'P0410';
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

  if current_visit.completed_at is null then
    return jsonb_build_object('applied', true, 'already_incomplete', true, 'revision', current_visit.revision);
  end if;

  if exists (
    select 1
    from public.invoice_sources as claim
    where claim.organization_id = target_organization_id
      and claim.visit_id = target_visit_id
      and claim.source_kind = 'visit'
  ) then
    raise exception 'This visit is already on an invoice, so it cannot be reopened.' using errcode = 'P0410',
      hint = 'Correct the invoice instead if the work was different from what was billed.';
  end if;

  update public.job_visits
  set completed_at = null, completed_by = null, revision = revision + 1, updated_at = now()
  where organization_id = target_organization_id and id = target_visit_id
  returning * into current_visit;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (target_organization_id, target_job_id, 'visit_uncompleted', caller, target_visit_id, '{}'::jsonb);

  return jsonb_build_object('applied', true, 'already_incomplete', false, 'revision', current_visit.revision);
end;
$$;

comment on function public.uncomplete_job_visit(uuid, uuid, uuid) is
  'Clears a visit''s completion. Checks jobs.complete, refuses on a closed job and on a visit an invoice '
  'already claims (P0410), is idempotent on an already-incomplete visit. Leaves any reminder the completion '
  'already raised untouched.';
