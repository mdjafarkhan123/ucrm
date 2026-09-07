-- Jobs, Part 15a-2: narrow the Field role to assigned work only.
-- Step 2 of 4. The order and the reasoning are in 20260910100000_field_assigned_scope_foundation.sql.

-- 4. The eleven table SELECT policies --------------------------------------------------------------------

-- Each one swaps the org-wide has_permission(..., 'jobs.view') for the job-aware can_view_job. The own/team
-- halves of the time-entry and expense policies are untouched -- they answer a different question.
--
-- job_list_rows, job_status_count_rows and the invoice reminder views are security_invoker = true and read
-- these tables, so they narrow along with the tables and are deliberately not rewritten.

drop policy "permitted members can view jobs" on public.jobs;
create policy "permitted members can view jobs"
on public.jobs for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, id)
);

drop policy "permitted members can view job events" on public.job_events;
create policy "permitted members can view job events"
on public.job_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view job lines" on public.job_line_items;
create policy "permitted members can view job lines"
on public.job_line_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view job visits" on public.job_visits;
create policy "permitted members can view job visits"
on public.job_visits for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view job visit assignments" on public.job_visit_assignments;
create policy "permitted members can view job visit assignments"
on public.job_visit_assignments for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view job recurrence rules" on public.job_recurrence_rules;
create policy "permitted members can view job recurrence rules"
on public.job_recurrence_rules for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view job invoice reminders" on public.job_invoice_reminders;
create policy "permitted members can view job invoice reminders"
on public.job_invoice_reminders for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view job payment stages" on public.job_payment_schedule_items;
create policy "permitted members can view job payment stages"
on public.job_payment_schedule_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view visit lines" on public.job_visit_line_items;
create policy "permitted members can view visit lines"
on public.job_visit_line_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
);

drop policy "permitted members can view time entries" on public.job_time_entries;
create policy "permitted members can view time entries"
on public.job_time_entries for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
  and (
    private.has_permission(organization_id, 'time.track_team')
    or (
      user_id = (select auth.uid())
      and private.has_permission(organization_id, 'time.track_own')
    )
  )
);

drop policy "permitted members can view expenses" on public.job_expenses;
create policy "permitted members can view expenses"
on public.job_expenses for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.can_view_job(organization_id, job_id)
  and (
    private.has_permission(organization_id, 'expenses.manage_team')
    or (
      created_by = (select auth.uid())
      and private.has_permission(organization_id, 'expenses.record')
    )
  )
);


