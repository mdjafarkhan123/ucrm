-- Files and Media, Part 5I: job expense receipts move onto the File Manager.
--
-- Recording a brand-new expense has no id yet for a receipt to attach to -- the File Manager can only check
-- and file a File against a record that already exists -- so the create-time dialog stages the picked
-- receipt in the browser and uploads it once the expense itself has been written and its id is known.
-- Correcting an existing expense already has a real id and writes each receipt change immediately, the same
-- way every other record's file card does.
--
-- job_expenses_list's own receipt_count is the one read left pointing at the pre-catalog `attachments`
-- table. Every existing attachment already has a matching file_links row (20260921160000's backfill keeps
-- both in step), so counting file_links instead is a strict superset going forward: it keeps every receipt
-- migration already counted and starts counting the ones the new dialog writes, which the old table never
-- sees. No table, column, constraint, policy or grant changes; rolling back is restoring the previous
-- function body from 20260101000000.

create or replace function "public"."job_expenses_list"(
  "target_organization_id" "uuid",
  "target_job_id" "uuid"
) returns "jsonb"
    language "plpgsql" stable security definer
    set "search_path" to 'pg_catalog', 'public'
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
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
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
             from public.file_links link
             where link.organization_id = expense.organization_id
               and link.entity_type = 'job_expense'
               and link.entity_id = expense.id
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
    'has_more', (totals->>'expense_count')::integer > expense_count,
    'job_closed', job_closed,
    'can_add', can_team or (can_own and not job_closed),
    'can_manage_team', can_team,
    'can_see_cost', can_cost
  );
end;
$$;

comment on function "public"."job_expenses_list"("target_organization_id" "uuid", "target_job_id" "uuid") is
  'One job''s expenses, page-limited, with each one''s receipt count read from file_links (the catalog every receipt lands in now, old and new) rather than the pre-catalog attachments table.';
