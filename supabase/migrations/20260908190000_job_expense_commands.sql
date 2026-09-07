-- Jobs Part 14c: recording expenses.
--
-- 14a built public.job_expenses, wired a receipt onto it as an attachment (entity_type 'job_expense'), and
-- left the table unwritable. This file gives it the four things it was waiting for, the exact twins of the
-- labor commands 14b shipped:
--
--   1. public.add_job_expense     -- record a cost incurred on a job
--   2. public.update_job_expense  -- correct an expense already recorded
--   3. public.delete_job_expense  -- remove an expense recorded in error
--   4. public.job_expenses_list   -- the gated read behind the Expenses section of a job
--
-- The same three rules from the behavior contract that shaped labor shape expenses:
--
--   * Recording your own expense and touching somebody else's are different permissions, and after a job
--     closes only the second one survives. An own-level holder is the person who recorded it (created_by),
--     because an expense has no "whose hours" -- it has who wrote it down.
--   * Closing a job locks the crew, not the books. An own-level holder loses the ability to touch a closed
--     job's expenses; a team-level holder can still correct them, and every such change is written to
--     job_costing_events with after_close = true.
--   * Workers never see money. That an expense exists, what it was, and its date are visible to the person
--     who recorded it; the total on it is not, in this reader or anywhere else, without jobs.view_cost.

-- 1. Who may write whose expense -----------------------------------------------------------------------------

-- Recording an expense you entered and touching one somebody else entered are different permissions, and
-- after a job closes only the second one survives. All three commands ask the same question, so it is asked
-- in one place: three copies of this rule would be three chances for the delete to disagree with the edit.
create or replace function private.can_write_job_expense(
  target_organization_id uuid,
  actor_id uuid,
  subject_created_by uuid,
  job_is_closed boolean
)
returns boolean
language sql
stable
set search_path = pg_catalog, public
as $$
  select private.member_has_permission(target_organization_id, actor_id, 'jobs.view')
    and (
      private.member_has_permission(target_organization_id, actor_id, 'expenses.manage_team')
      or (
        subject_created_by = actor_id
        and not job_is_closed
        and private.member_has_permission(target_organization_id, actor_id, 'expenses.record')
      )
    );
$$;

comment on function private.can_write_job_expense(uuid, uuid, uuid, boolean) is
  'Whether this person may record or change this expense: anyone''s with expenses.manage_team, the ones they '
  'recorded themselves with expenses.record while the job is still open. Closing a job locks the crew out of '
  'its expenses, not the manager correcting them.';

revoke all on function private.can_write_job_expense(uuid, uuid, uuid, boolean) from public;
revoke execute on function private.can_write_job_expense(uuid, uuid, uuid, boolean) from anon, authenticated;

-- 2. Recording an expense -----------------------------------------------------------------------------------

create or replace function public.add_job_expense(
  target_organization_id uuid,
  target_job_id uuid,
  name text,
  expense_date date,
  total_minor bigint,
  accounting_code text default null,
  description text default null,
  reimburse_to_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  job_closed boolean;
  new_expense public.job_expenses;
begin
  if caller is null then
    raise exception 'You must be signed in to record an expense.' using errcode = 'insufficient_privilege';
  end if;

  -- No row lock. An expense is appended to a job, never derived from it, so two people recording an expense
  -- at once have nothing to fight over -- and locking the job here would make every expense queue behind
  -- whatever else is editing the job.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  job_closed := current_job.status <> 'active';

  -- The person recording it is the person who owns it, so the own/team gate is asked about the caller.
  if not private.can_write_job_expense(target_organization_id, caller, caller, job_closed) then
    if job_closed then
      raise exception 'A closed job''s expenses can only be changed by someone who manages the team''s expenses.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to record this expense.' using errcode = 'insufficient_privilege';
  end if;

  -- Someone to pay back has to work here. The foreign key would refuse a stranger anyway; this refuses a
  -- person who has left with a sentence instead of a constraint name. Null is fine -- the business paid it.
  if reimburse_to_user_id is not null and not exists (
    select 1
    from public.organization_members as member
    where member.organization_id = target_organization_id
      and member.user_id = reimburse_to_user_id
      and member.status <> 'removed'
  ) then
    raise exception 'That person is not on this team.' using errcode = 'P0404';
  end if;

  insert into public.job_expenses (
    organization_id, job_id, name, accounting_code, description, expense_date, total_minor,
    reimburse_to_user_id, created_by
  )
  values (
    target_organization_id, target_job_id,
    trim(add_job_expense.name),
    nullif(trim(coalesce(add_job_expense.accounting_code, '')), ''),
    nullif(trim(coalesce(add_job_expense.description, '')), ''),
    add_job_expense.expense_date, add_job_expense.total_minor,
    add_job_expense.reimburse_to_user_id, caller
  )
  returning * into new_expense;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close, new_values
  )
  values (
    target_organization_id, target_job_id, 'expense_added', 'expense', new_expense.id, caller, job_closed,
    jsonb_build_object(
      'name', new_expense.name,
      'accounting_code', new_expense.accounting_code,
      'expense_date', new_expense.expense_date,
      'total_minor', new_expense.total_minor,
      'reimburse_to_user_id', new_expense.reimburse_to_user_id
    )
  );

  return jsonb_build_object('id', new_expense.id, 'after_close', job_closed);
end;
$$;

comment on function public.add_job_expense(uuid, uuid, text, date, bigint, text, text, uuid) is
  'Records an expense on a job -- materials, dump fees, a subcontractor. Needs expenses.manage_team, or '
  'expenses.record on an open job for the person''s own. Every expense is written to job_costing_events, '
  'flagged when the job is already closed. The receipt attaches separately as an attachment.';

revoke all on function public.add_job_expense(uuid, uuid, text, date, bigint, text, text, uuid) from public;
revoke execute on function public.add_job_expense(uuid, uuid, text, date, bigint, text, text, uuid) from anon;
grant execute on function public.add_job_expense(uuid, uuid, text, date, bigint, text, text, uuid) to authenticated;

-- 3. Correcting an expense ----------------------------------------------------------------------------------

-- Who recorded it is deliberately not editable. created_by is what the own-level gate reads; letting it move
-- would let a manager hand their own-level access to someone, or take it away. The record stays owned by the
-- person who entered it, and the trail keeps every change either of them makes.
create or replace function public.update_job_expense(
  target_organization_id uuid,
  target_job_id uuid,
  target_expense_id uuid,
  name text,
  expense_date date,
  total_minor bigint,
  accounting_code text default null,
  description text default null,
  reimburse_to_user_id uuid default null,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_expenses;
  updated public.job_expenses;
begin
  if caller is null then
    raise exception 'You must be signed in to change an expense.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  -- The expense is locked, not the job: two corrections to the same expense queue, and corrections to
  -- different expenses on the same job do not wait for each other.
  select expense.* into existing
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and expense.id = target_expense_id
  for update;
  if not found then
    raise exception 'That expense could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_expense(target_organization_id, caller, existing.created_by, job_closed) then
    if job_closed then
      raise exception 'A closed job''s expenses can only be changed by someone who manages the team''s expenses.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to change this expense.' using errcode = 'insufficient_privilege';
  end if;

  if reimburse_to_user_id is not null and not exists (
    select 1
    from public.organization_members as member
    where member.organization_id = target_organization_id
      and member.user_id = reimburse_to_user_id
      and member.status <> 'removed'
  ) then
    raise exception 'That person is not on this team.' using errcode = 'P0404';
  end if;

  -- created_by is absent on purpose: the expense keeps the person who recorded it.
  update public.job_expenses as expense
  set name = trim(update_job_expense.name),
      accounting_code = nullif(trim(coalesce(update_job_expense.accounting_code, '')), ''),
      description = nullif(trim(coalesce(update_job_expense.description, '')), ''),
      expense_date = update_job_expense.expense_date,
      total_minor = update_job_expense.total_minor,
      reimburse_to_user_id = update_job_expense.reimburse_to_user_id
  where expense.organization_id = target_organization_id
    and expense.id = target_expense_id
  returning * into updated;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values, new_values
  )
  values (
    target_organization_id, target_job_id, 'expense_updated', 'expense', target_expense_id, caller,
    job_closed,
    nullif(trim(coalesce(update_job_expense.reason, '')), ''),
    jsonb_build_object(
      'name', existing.name,
      'accounting_code', existing.accounting_code,
      'expense_date', existing.expense_date,
      'total_minor', existing.total_minor,
      'reimburse_to_user_id', existing.reimburse_to_user_id
    ),
    jsonb_build_object(
      'name', updated.name,
      'accounting_code', updated.accounting_code,
      'expense_date', updated.expense_date,
      'total_minor', updated.total_minor,
      'reimburse_to_user_id', updated.reimburse_to_user_id
    )
  );

  return jsonb_build_object('id', updated.id, 'after_close', job_closed);
end;
$$;

comment on function public.update_job_expense(uuid, uuid, uuid, text, date, bigint, text, text, uuid, text) is
  'Corrects a recorded expense, keeping the person who recorded it. Needs expenses.manage_team, or '
  'expenses.record on an open job for their own. The before and after are written to job_costing_events.';

revoke all on function public.update_job_expense(uuid, uuid, uuid, text, date, bigint, text, text, uuid, text) from public;
revoke execute on function public.update_job_expense(uuid, uuid, uuid, text, date, bigint, text, text, uuid, text) from anon;
grant execute on function public.update_job_expense(uuid, uuid, uuid, text, date, bigint, text, text, uuid, text) to authenticated;

-- 4. Removing an expense ------------------------------------------------------------------------------------

create or replace function public.delete_job_expense(
  target_organization_id uuid,
  target_job_id uuid,
  target_expense_id uuid,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_expenses;
begin
  if caller is null then
    raise exception 'You must be signed in to remove an expense.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  select expense.* into existing
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and expense.id = target_expense_id
  for update;
  if not found then
    raise exception 'That expense could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_expense(target_organization_id, caller, existing.created_by, job_closed) then
    if job_closed then
      raise exception 'A closed job''s expenses can only be changed by someone who manages the team''s expenses.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to remove this expense.' using errcode = 'insufficient_privilege';
  end if;

  -- The trail is written first and keeps the whole row. job_costing_events holds subject_id as a plain id
  -- precisely so the evidence outlives the expense it describes. The receipt files are cleaned up by the
  -- browser through the attachment route before this command runs, because R2 is reachable only from there.
  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values
  )
  values (
    target_organization_id, target_job_id, 'expense_deleted', 'expense', target_expense_id, caller,
    job_closed,
    nullif(trim(coalesce(delete_job_expense.reason, '')), ''),
    jsonb_build_object(
      'name', existing.name,
      'accounting_code', existing.accounting_code,
      'expense_date', existing.expense_date,
      'total_minor', existing.total_minor,
      'reimburse_to_user_id', existing.reimburse_to_user_id
    )
  );

  delete from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.id = target_expense_id;

  return jsonb_build_object('id', target_expense_id, 'after_close', job_closed);
end;
$$;

comment on function public.delete_job_expense(uuid, uuid, uuid, text) is
  'Removes a recorded expense, writing the whole row to job_costing_events first so deleting an expense never '
  'deletes the evidence that it existed. Same permissions as correcting one. Receipt files are removed by the '
  'browser through the attachment route beforehand.';

revoke all on function public.delete_job_expense(uuid, uuid, uuid, text) from public;
revoke execute on function public.delete_job_expense(uuid, uuid, uuid, text) from anon;
grant execute on function public.delete_job_expense(uuid, uuid, uuid, text) to authenticated;

-- 5. The gated read -----------------------------------------------------------------------------------------

-- Everything the Expenses section of a job needs in one call: the expenses themselves, who may change each
-- one, and the total underneath. Definer, because it decides for itself what this reader may see -- the
-- table's own grant already withholds total_minor from everyone, and this is the only door they come through.
--
-- Bounded twice over: the list is capped at 200 rows served by job_expenses_job_date_idx, and the total is
-- aggregated separately so a job with more expenses than that still shows an honest number.
create or replace function public.job_expenses_list(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  page_size constant integer := 200;
  can_cost boolean;
  can_team boolean;
  can_own boolean;
  job_closed boolean;
  expenses jsonb;
  totals jsonb;
  expense_count integer;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view') then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  can_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');
  can_team := private.member_has_permission(target_organization_id, caller, 'expenses.manage_team');
  can_own := private.member_has_permission(target_organization_id, caller, 'expenses.record');

  -- The same own/team split the table's policy applies, restated here because this function is definer and
  -- the policy no longer stands between the reader and the rows.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', visible.id,
          'name', visible.name,
          'accounting_code', visible.accounting_code,
          'description', visible.description,
          'expense_date', visible.expense_date,
          'reimburse_to_user_id', visible.reimburse_to_user_id,
          'reimburse_to_name', visible.reimburse_to_name,
          'created_by', visible.created_by,
          'receipt_count', visible.receipt_count,
          'can_edit', can_team or (visible.created_by = caller and can_own and not job_closed)
        )
        || (case when can_cost then jsonb_build_object('total_minor', visible.total_minor)
              else '{}'::jsonb end)
        order by visible.expense_date desc, visible.id desc
      ),
      '[]'::jsonb
    ),
    count(*)
  into expenses, expense_count
  from (
    select expense.id, expense.name, expense.accounting_code, expense.description, expense.expense_date,
           expense.total_minor, expense.reimburse_to_user_id, expense.created_by,
           profile.full_name as reimburse_to_name,
           (
             select count(*)
             from public.attachments as receipt
             where receipt.organization_id = expense.organization_id
               and receipt.entity_type = 'job_expense'
               and receipt.entity_id = expense.id
           ) as receipt_count
    from public.job_expenses as expense
    left join public.profiles as profile on profile.id = expense.reimburse_to_user_id
    where expense.organization_id = target_organization_id
      and expense.job_id = target_job_id
      and (can_team or (expense.created_by = caller and can_own))
    order by expense.expense_date desc, expense.id desc
    limit page_size
  ) as visible;

  select jsonb_build_object(
    'expense_count', count(*),
    'total_minor', case when can_cost then coalesce(sum(expense.total_minor), 0) else null end
  ) into totals
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and (can_team or (expense.created_by = caller and can_own));

  return jsonb_build_object(
    'expenses', expenses,
    'totals', totals,
    -- More expenses exist than the list shows. The total still counts all of them.
    'has_more', (totals->>'expense_count')::integer > expense_count,
    'job_closed', job_closed,
    'can_add', can_team or (can_own and not job_closed),
    'can_manage_team', can_team,
    'can_see_cost', can_cost
  );
end;
$$;

comment on function public.job_expenses_list(uuid, uuid) is
  'One job''s recorded expenses and their total, newest first. A reader with expenses.manage_team sees '
  'everyone''s and a reader with only expenses.record sees the ones they recorded. Totals need jobs.view_cost; '
  'without it the same rows come back with no money at all.';

revoke all on function public.job_expenses_list(uuid, uuid) from public;
revoke execute on function public.job_expenses_list(uuid, uuid) from anon;
grant execute on function public.job_expenses_list(uuid, uuid) to authenticated;
