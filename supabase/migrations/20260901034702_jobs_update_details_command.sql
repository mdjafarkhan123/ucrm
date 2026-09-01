-- Jobs Part 8: the one command that stages and saves a job's editable details.
--
-- Part 8 gives a job its detail page. The only two fields that page lets a person change are the job's title
-- and its instructions; scope lines, visits and billing each get their own command in later parts. This is
-- that one command. It mirrors public.create_job_with_visits: it checks its own permission, refuses a stale
-- revision so two editors cannot silently overwrite each other, does the write under the job's own guards,
-- appends a history row, and hands back the new revision for the next save.

create or replace function public.update_job_details(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_title text,
  new_instructions text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  clean_title text := trim(coalesce(new_title, ''));
  clean_instructions text := nullif(trim(coalesce(new_instructions, '')), '');
  changed text[] := array[]::text[];
begin
  if caller is null then
    raise exception 'You must be signed in to edit a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  -- Lock the job row for the length of this transaction so the revision we check is the revision we write
  -- against. A job in another organization, or one that never existed, is simply not found here — the
  -- permission check above already proved the caller belongs to target_organization_id, so a stranger cannot
  -- tell a missing job from a forbidden one.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id = target_job_id
  for update;

  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  -- The optimistic lock: the caller sends the revision it last read, and a mismatch means someone else saved
  -- in between. Refuse rather than clobber; the browser is told to reload.
  if current_job.revision is distinct from expected_revision then
    raise exception 'Someone else changed this job. Reload to see the latest.' using errcode = 'P0409';
  end if;

  -- Which of the two fields actually moved. Redacted metadata only: the names of the fields that changed,
  -- never their before-and-after content.
  if clean_title is distinct from current_job.title then
    changed := array_append(changed, 'title');
  end if;
  if clean_instructions is distinct from current_job.instructions then
    changed := array_append(changed, 'instructions');
  end if;

  -- The title length check on the jobs table surfaces as a 23514 the API turns into a form error, so an empty
  -- or over-long title is caught here rather than by a second guard that could disagree with the table.
  update public.jobs
  set title = clean_title,
      instructions = clean_instructions,
      revision = current_job.revision + 1
  where organization_id = target_organization_id
    and id = target_job_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'details_updated',
    caller,
    jsonb_build_object('changed', to_jsonb(changed))
  );

  return jsonb_build_object('revision', current_job.revision + 1);
end;
$$;

comment on function public.update_job_details(uuid, uuid, integer, text, text) is
  'Staged save of a job''s title and instructions. Checks jobs.edit, refuses a stale revision (P0409), '
  'bumps revision and appends a details_updated history row. The only editor of these two fields.';

revoke all on function public.update_job_details(uuid, uuid, integer, text, text) from public;
revoke execute on function public.update_job_details(uuid, uuid, integer, text, text) from anon;
grant execute on function public.update_job_details(uuid, uuid, integer, text, text) to authenticated;

notify pgrst, 'reload schema';
