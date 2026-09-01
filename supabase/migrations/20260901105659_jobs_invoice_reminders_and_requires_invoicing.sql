-- Jobs Part 11b: invoice reminders and the Requires invoicing derived status.
--
-- An invoice reminder is an internal to-do for our own team -- never a message to the client. When one comes
-- due, the job reads as "Requires invoicing", which is the workflow lever that lets an office batch every job
-- that owes an invoice into one place. This matches Jobber exactly (see the jobber Jobs reference, section
-- "Invoice reminders"); the contract's "Billing timing and collection, kept separate" section is the authority.
--
-- What ships here:
--   * public.job_invoice_reminders -- one deletable, dated row per reminder, the shape the contract describes.
--   * private.create_invoice_reminder -- the one primitive that makes a reminder, used by month-end and custom
--     dates now, and by Part 13's visit-completion and job-close commands later.
--   * The Requires invoicing derived status, folded into the single job_derived_status rule so the list, the
--     overview counts and every future reader agree on what it means.
--   * Commands to add a custom-date reminder, dismiss a due one, and delete a mistaken one.
--   * A trigger on jobs that seeds / clears the month-end reminder from billing_timing, at creation and edit.
--
-- Deliberately NOT here (Part 13 owns the events; the roadmap records the debt):
--   * per_visit reminders fire when a visit is marked complete -- no such command exists yet.
--   * on_completion reminders fire when a job is closed -- closing does not exist yet.
--   * A reminder resolved by actually invoicing (resolution = 'invoiced') -- Invoices do not exist yet.
-- The table, the reminder-kind check and the create primitive already support all three, so Part 13 only wires
-- up callers; it changes no shape here.

-- 1. The reminder ------------------------------------------------------------------------------------------

create table public.job_invoice_reminders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  -- The four kinds the contract lists. per_visit and on_completion are storable now but fired by Part 13.
  reminder_kind text not null check (reminder_kind in (
    'on_completion', 'per_visit', 'monthly_last_day', 'custom_date'
  )),
  -- Only a per_visit reminder points at a visit; the check below enforces that.
  visit_id uuid,
  due_on date not null,
  status text not null default 'pending' check (status in ('pending', 'resolved')),
  -- How a resolved reminder cleared. 'dismissed' by hand today; 'invoiced' when the Invoice seam lands (Part 13).
  resolution text check (resolution in ('dismissed', 'invoiced')),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  note text check (note is null or char_length(note) <= 200),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_invoice_reminders_org_id_unique unique (organization_id, id),
  constraint job_invoice_reminders_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_invoice_reminders_visit_fk foreign key (organization_id, visit_id)
    references public.job_visits(organization_id, id) on delete cascade,
  -- Status and its resolution move together: a pending reminder has neither stamp, a resolved one has both.
  constraint job_invoice_reminders_resolution_pairs check (
    (status = 'resolved') = (resolution is not null)
  ),
  constraint job_invoice_reminders_resolved_stamp check (
    (resolution is null) = (resolved_at is null)
  ),
  -- A visit is attached only when the reminder is the one raised for that visit.
  constraint job_invoice_reminders_visit_only_for_per_visit check (
    visit_id is null or reminder_kind = 'per_visit'
  )
);

comment on table public.job_invoice_reminders is
  'Internal invoice reminders for a job, never client-facing. A pending reminder whose due_on has arrived puts '
  'the job in the Requires invoicing derived status. Cleared by dismissing it or, once Invoices exist, by '
  'invoicing it (resolution = ''invoiced''). Rows are written only by the commands in this file.';

comment on column public.job_invoice_reminders.status is
  'pending until cleared. A pending row with due_on <= today is what the reader turns into Requires invoicing.';

-- The reader's hot question, asked once per job on the list and once per job in the counts: does this job have a
-- reminder that is pending and already due? The partial index makes each check an index probe over only the
-- pending rows, and also serves the detail page''s "show this job''s open reminders" fetch.
create index job_invoice_reminders_pending_due_idx
  on public.job_invoice_reminders(organization_id, job_id, due_on)
  where status = 'pending';

-- One open reminder per visit: a visit cannot accumulate duplicate reminders if Part 13's completion command
-- runs twice.
create unique index job_invoice_reminders_one_open_per_visit_idx
  on public.job_invoice_reminders(organization_id, visit_id)
  where visit_id is not null and status = 'pending';

-- One open calendar reminder per job per day, so re-seeding month-end or re-adding the same custom date is a
-- no-op rather than a duplicate.
create unique index job_invoice_reminders_one_open_per_day_idx
  on public.job_invoice_reminders(organization_id, job_id, due_on)
  where status = 'pending' and reminder_kind in ('monthly_last_day', 'custom_date');

-- Supports the visit foreign key's cascade and the per-visit lookups.
create index job_invoice_reminders_visit_idx
  on public.job_invoice_reminders(organization_id, visit_id)
  where visit_id is not null;

create trigger job_invoice_reminders_set_updated_at
before update on public.job_invoice_reminders
for each row execute function public.set_updated_at();

-- 2. Row level security ------------------------------------------------------------------------------------

alter table public.job_invoice_reminders enable row level security;

-- A reminder carries no money, only a date and a to-do, so anyone who may see the job may see its reminders.
create policy "permitted members can view job invoice reminders"
on public.job_invoice_reminders for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

revoke all on public.job_invoice_reminders from anon, authenticated;
grant select on public.job_invoice_reminders to authenticated;

-- 3. The one primitive that makes a reminder ---------------------------------------------------------------

-- Every reminder, whoever raises it, is born here: the month-end seeder and the custom-date command below, and
-- Part 13's visit-completion and job-close commands later. It checks tenancy, not authorisation -- its callers
-- own the permission check -- and leans on the partial unique indexes to make a duplicate raise a no-op that
-- returns the id already there.
create or replace function private.create_invoice_reminder(
  target_organization_id uuid,
  target_job_id uuid,
  new_kind text,
  new_due_on date,
  actor uuid,
  new_visit_id uuid default null,
  new_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reminder_id uuid;
begin
  insert into public.job_invoice_reminders (
    organization_id, job_id, reminder_kind, visit_id, due_on, note, created_by
  ) values (
    target_organization_id,
    target_job_id,
    new_kind,
    new_visit_id,
    new_due_on,
    nullif(trim(coalesce(new_note, '')), ''),
    actor
  )
  on conflict do nothing
  returning id into reminder_id;

  -- A duplicate hit one of the partial unique indexes and inserted nothing; hand back the open row that won.
  if reminder_id is null then
    select id into reminder_id
    from public.job_invoice_reminders
    where organization_id = target_organization_id
      and job_id = target_job_id
      and status = 'pending'
      and (
        (new_visit_id is not null and visit_id = new_visit_id)
        or (new_visit_id is null and due_on = new_due_on and reminder_kind = new_kind)
      )
    limit 1;
  else
    insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
    values (
      target_organization_id,
      target_job_id,
      'invoice_reminder_added',
      actor,
      new_visit_id,
      jsonb_build_object('reminder_kind', new_kind, 'due_on', new_due_on)
    );
  end if;

  return reminder_id;
end;
$$;

comment on function private.create_invoice_reminder(uuid, uuid, text, date, uuid, uuid, text) is
  'Raises one invoice reminder and logs it, or returns the open reminder already there. Checks tenancy only; '
  'the caller owns the permission check. Used by month-end, custom dates, and (Part 13) visit and close events.';

revoke all on function private.create_invoice_reminder(uuid, uuid, text, date, uuid, uuid, text) from public;
revoke execute on function private.create_invoice_reminder(uuid, uuid, text, date, uuid, uuid, text)
  from anon, authenticated;

-- 4. The Requires invoicing rule, folded into the single derived-status rule -------------------------------

-- Adds one input -- does this job have a due, pending reminder -- to the rule Part 6 established. Priority,
-- reconciling the Part 6 note ("a recurring agreement running out is the fact to act on before anything else")
-- with Jobber's definition of Archived ("a closed job that no longer needs invoicing"):
--   1. A closed job that still owes an invoice is the loudest thing on the screen -> requires_invoicing.
--   2. A closed job with nothing due -> archived.
--   3. An active recurring agreement ending within 30 days -> ending_soon.
--   4. An active job with a due reminder -> requires_invoicing.
--   5. Everything else -> unscheduled (until visit-driven labels are wired; still deferred).
create or replace function private.job_derived_status(
  stored_status text,
  job_type text,
  contract_end_date date,
  today date,
  has_due_reminder boolean
)
returns text
language sql
immutable
as $$
  select case
    when stored_status = 'closed' and has_due_reminder then 'requires_invoicing'
    when stored_status = 'closed' then 'archived'
    when job_type = 'recurring'
      and contract_end_date is not null
      and contract_end_date >= today
      and contract_end_date <= today + 30 then 'ending_soon'
    when has_due_reminder then 'requires_invoicing'
    else 'unscheduled'
  end;
$$;

comment on function private.job_derived_status(text, text, date, date, boolean) is
  'The job status a person reads, derived and never stored. A due invoice reminder shows as Requires invoicing '
  '(and outranks Archived on a closed-but-unbilled job); Archived otherwise wins on a closed job; a recurring '
  'agreement ending within 30 days beats an active Requires invoicing; everything else is Unscheduled.';

revoke all on function private.job_derived_status(text, text, date, date, boolean) from public;
revoke execute on function private.job_derived_status(text, text, date, date, boolean) from anon;
grant execute on function private.job_derived_status(text, text, date, date, boolean) to authenticated;

-- 5. The list and the counts learn the reminder, each in the shape its access pattern needs -----------------

-- The paged list and the overview counts ask the same question -- "is a reminder due on this job" -- but want
-- opposite shapes for it. The list reads at most one page, so a per-row EXISTS over the pending partial index
-- costs 25 probes and the first page stays on jobs_active_idx (measured: 23 ms). The counts read every job, so
-- a per-row EXISTS becomes 50,000 probes (measured: 915 ms); a set the query joins once is 124 ms, next to
-- Part 6's 115 ms with no reminders at all. So the list view keeps the EXISTS and the counts get their own lean
-- view built on the set-join. Both call the same private.job_derived_status rule, so a tile and its rows can
-- never disagree about a status.
create or replace view public.job_list_rows
with (security_invoker = true) as
select
  job.id,
  job.organization_id,
  job.job_number,
  job.title,
  job.job_type,
  job.is_as_needed,
  job.status,
  job.price_basis,
  job.billing_timing,
  job.currency_code,
  job.contract_start_date,
  job.contract_end_date,
  job.quote_id,
  job.created_at,
  private.job_derived_status(
    job.status,
    job.job_type,
    job.contract_end_date,
    calendar.today,
    exists (
      select 1
      from public.job_invoice_reminders as reminder
      where reminder.organization_id = job.organization_id
        and reminder.job_id = job.id
        and reminder.status = 'pending'
        and reminder.due_on <= calendar.today
    )
  ) as derived_status,
  job.client_id,
  client.display_name as client_display_name,
  client.company_name as client_company_name,
  job.property_id,
  property.label as property_label,
  property.address_line1 as property_address_line1,
  property.city as property_city,
  property.state_region as property_state_region,
  property.postal_code as property_postal_code
from public.jobs as job
left join private.organization_calendars() as calendar
  on calendar.organization_id = job.organization_id
left join public.clients as client
  on client.organization_id = job.organization_id and client.id = job.client_id
left join public.properties as property
  on property.organization_id = job.organization_id and property.id = job.property_id;

comment on view public.job_list_rows is
  'What the Jobs list draws: identity, client and property context, and the derived status (now including '
  'Requires invoicing from due reminders). No money - that comes from public.job_money.';

-- Counts view: only organization_id and derived_status, the due check done as one joined set over the pending
-- reminders (via their partial index), collapsed to one row per job, so counting every job stays linear.
create or replace view public.job_status_count_rows
with (security_invoker = true) as
select
  job.organization_id,
  private.job_derived_status(
    job.status,
    job.job_type,
    job.contract_end_date,
    calendar.today,
    due_reminder.job_id is not null
  ) as derived_status
from public.jobs as job
left join private.organization_calendars() as calendar
  on calendar.organization_id = job.organization_id
left join (
  select reminder.organization_id, reminder.job_id
  from public.job_invoice_reminders as reminder
  join private.organization_calendars() as cal
    on cal.organization_id = reminder.organization_id
  where reminder.status = 'pending'
    and reminder.due_on <= cal.today
  group by reminder.organization_id, reminder.job_id
) as due_reminder
  on due_reminder.organization_id = job.organization_id and due_reminder.job_id = job.id;

comment on view public.job_status_count_rows is
  'One row per job with just its organization and derived status, the due-reminder check done as a single '
  'joined set. Feeds public.job_status_counts; the rich per-row job_list_rows feeds the paged list.';

revoke all on public.job_status_count_rows from anon, authenticated;
grant select on public.job_status_count_rows to authenticated;

-- Repoint the counts at the lean bulk view.
create or replace function public.job_status_counts(target_organization_id uuid)
returns table(derived_status text, total bigint)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select counted.derived_status, count(*) as total
  from public.job_status_count_rows as counted
  where counted.organization_id = target_organization_id
  group by 1;
$$;

comment on function public.job_status_counts(uuid) is
  'Live count of this organization''s jobs by derived status, for the Jobs overview card. Counts '
  'job_status_count_rows, whose due-reminder check is a bulk set-join so counting every job stays linear.';

revoke all on function public.job_status_counts(uuid) from public, anon;
grant execute on function public.job_status_counts(uuid) to authenticated;

-- The view now binds the five-argument rule, so the old four-argument version is unused: drop it so nothing
-- can call the version that cannot see reminders.
drop function if exists private.job_derived_status(text, text, date, date);

-- 6. Month-end seeding, kept bounded without a cron --------------------------------------------------------

-- The last calendar day of the month a date falls in.
create or replace function private.month_end_of(any_day date)
returns date
language sql
immutable
set search_path = pg_catalog, public
as $$
  select (date_trunc('month', any_day) + interval '1 month' - interval '1 day')::date;
$$;

revoke all on function private.month_end_of(date) from public;

-- Ensures a recurring "invoice at month end" job carries exactly one open month-end reminder: this month's,
-- while the contract still runs. It is called when month-end billing is chosen and again each time that
-- reminder is dismissed, so the series rolls forward one month at a time without a scheduled job and without
-- ever storing an unbounded pile of future rows. Bounded by contract_end_date when the job has one.
create or replace function private.seed_next_month_end_reminder(
  target_organization_id uuid,
  target_job_id uuid,
  actor uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  job_row public.jobs;
  last_due date;
  next_due date;
begin
  select * into job_row
  from public.jobs
  where organization_id = target_organization_id and id = target_job_id;

  if not found or job_row.billing_timing <> 'month_end' or job_row.status <> 'active' then
    return;
  end if;

  -- Already has an open month-end reminder: nothing to roll forward yet.
  if exists (
    select 1 from public.job_invoice_reminders
    where organization_id = target_organization_id
      and job_id = target_job_id
      and reminder_kind = 'monthly_last_day'
      and status = 'pending'
  ) then
    return;
  end if;

  -- The next month-end after the last one this job already carried (pending or resolved), so dismissing this
  -- month's reminder rolls forward to next month rather than re-raising the same date. The first ever one is
  -- this month's.
  select max(due_on) into last_due
  from public.job_invoice_reminders
  where organization_id = target_organization_id
    and job_id = target_job_id
    and reminder_kind = 'monthly_last_day';

  if last_due is null then
    next_due := private.month_end_of(private.organization_today(target_organization_id));
  else
    next_due := private.month_end_of((last_due + interval '1 day')::date);
  end if;

  -- Do not schedule a reminder past the agreement's end.
  if job_row.contract_end_date is not null and next_due > job_row.contract_end_date then
    return;
  end if;

  perform private.create_invoice_reminder(
    target_organization_id, target_job_id, 'monthly_last_day', next_due, actor
  );
end;
$$;

comment on function private.seed_next_month_end_reminder(uuid, uuid, uuid) is
  'Keeps exactly one open month-end reminder on a month-end-billed active job, this month''s, honoring the '
  'contract end. Called by the jobs billing trigger and again on dismissing the current one, so the series '
  'rolls forward with no cron and no unbounded backlog.';

revoke all on function private.seed_next_month_end_reminder(uuid, uuid, uuid) from public;
revoke execute on function private.seed_next_month_end_reminder(uuid, uuid, uuid) from anon, authenticated;

-- 7. The month-end reminder follows the billing choice, at creation and at every edit ----------------------

-- A recurring job is created already billed at month end (that is its default), and 11a lets any job be moved
-- onto or off month-end billing later. Both paths write the same column, so a trigger on that column is the one
-- place that keeps the reminder in step -- rather than teaching every writer (create_job, set_job_billing, any
-- future one) to remember. The seeder is idempotent, so firing on an unchanged save costs nothing; moving off
-- month-end clears the open reminder that no longer reflects the policy. Custom-date reminders are the user's
-- own and are never touched here. Definer, because it runs inside definer commands and writes gated tables.
create or replace function private.jobs_sync_month_end_reminder()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.billing_timing = 'month_end' and new.status = 'active' then
    perform private.seed_next_month_end_reminder(new.organization_id, new.id, (select auth.uid()));
  elsif tg_op = 'UPDATE' and new.billing_timing <> 'month_end' then
    delete from public.job_invoice_reminders
    where organization_id = new.organization_id
      and job_id = new.id
      and reminder_kind = 'monthly_last_day'
      and status = 'pending';
  end if;
  return null;
end;
$$;

comment on function private.jobs_sync_month_end_reminder() is
  'Keeps a month-end-billed job carrying its open month-end reminder, and clears it when the job moves off '
  'month-end billing. Fires on creation and on any change to billing_timing, so no writer has to remember.';

-- Fires on insert (the column list only narrows UPDATE) and on any update that touches billing_timing.
create trigger jobs_sync_month_end_reminder
after insert or update of billing_timing on public.jobs
for each row execute function private.jobs_sync_month_end_reminder();

-- 8. Adding a custom-date reminder -------------------------------------------------------------------------

create or replace function public.add_job_invoice_reminder(
  target_organization_id uuid,
  target_job_id uuid,
  new_due_on date,
  new_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  reminder_id uuid;
begin
  if caller is null then
    raise exception 'You must be signed in to add an invoice reminder.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;
  if new_due_on is null then
    raise exception 'Choose a date for this reminder.' using errcode = 'check_violation';
  end if;

  select * into job_row
  from public.jobs
  where organization_id = target_organization_id and id = target_job_id;

  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  reminder_id := private.create_invoice_reminder(
    target_organization_id, target_job_id, 'custom_date', new_due_on, caller, null, new_note
  );

  return jsonb_build_object('id', reminder_id);
end;
$$;

comment on function public.add_job_invoice_reminder(uuid, uuid, date, text) is
  'Adds a custom-date invoice reminder to a job. Needs jobs.edit. Re-adding the same open date is a no-op that '
  'returns the existing reminder.';

revoke all on function public.add_job_invoice_reminder(uuid, uuid, date, text) from public;
revoke execute on function public.add_job_invoice_reminder(uuid, uuid, date, text) from anon;
grant execute on function public.add_job_invoice_reminder(uuid, uuid, date, text) to authenticated;

-- 9. Dismissing a due reminder -----------------------------------------------------------------------------

-- Marks a reminder handled, keeping the row as history rather than deleting it, which is how an office proves a
-- job was billed outside the system. For a month-end reminder it rolls the series forward by seeding next
-- month's.
create or replace function public.dismiss_job_invoice_reminder(
  target_organization_id uuid,
  target_reminder_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  reminder_row public.job_invoice_reminders;
begin
  if caller is null then
    raise exception 'You must be signed in to change an invoice reminder.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  update public.job_invoice_reminders
  set status = 'resolved', resolution = 'dismissed', resolved_at = now(), resolved_by = caller
  where organization_id = target_organization_id
    and id = target_reminder_id
    and status = 'pending'
  returning * into reminder_row;

  if not found then
    raise exception 'That reminder was already handled or does not exist.' using errcode = 'P0404';
  end if;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    reminder_row.job_id,
    'invoice_reminder_dismissed',
    caller,
    jsonb_build_object('reminder_kind', reminder_row.reminder_kind, 'due_on', reminder_row.due_on)
  );

  if reminder_row.reminder_kind = 'monthly_last_day' then
    perform private.seed_next_month_end_reminder(target_organization_id, reminder_row.job_id, caller);
  end if;

  return jsonb_build_object('id', reminder_row.id, 'status', 'resolved');
end;
$$;

comment on function public.dismiss_job_invoice_reminder(uuid, uuid) is
  'Marks a pending invoice reminder handled (resolution = dismissed), keeping it as history. Rolls a month-end '
  'reminder forward to next month. Needs jobs.edit.';

revoke all on function public.dismiss_job_invoice_reminder(uuid, uuid) from public;
revoke execute on function public.dismiss_job_invoice_reminder(uuid, uuid) from anon;
grant execute on function public.dismiss_job_invoice_reminder(uuid, uuid) to authenticated;

-- 10. Deleting a mistaken reminder -------------------------------------------------------------------------

-- Removes a reminder that should never have existed -- a custom date typed wrong. Only manual custom-date
-- reminders can be deleted; auto and event-raised reminders are managed by their policy, not erased by hand.
create or replace function public.delete_job_invoice_reminder(
  target_organization_id uuid,
  target_reminder_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  reminder_row public.job_invoice_reminders;
begin
  if caller is null then
    raise exception 'You must be signed in to delete an invoice reminder.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into reminder_row
  from public.job_invoice_reminders
  where organization_id = target_organization_id and id = target_reminder_id;

  if not found then
    raise exception 'That reminder does not exist.' using errcode = 'P0404';
  end if;
  if reminder_row.reminder_kind <> 'custom_date' then
    raise exception 'Only a custom-date reminder can be deleted. Dismiss the others instead.'
      using errcode = 'check_violation';
  end if;

  delete from public.job_invoice_reminders
  where organization_id = target_organization_id and id = target_reminder_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    reminder_row.job_id,
    'invoice_reminder_deleted',
    caller,
    jsonb_build_object('due_on', reminder_row.due_on)
  );

  return jsonb_build_object('id', target_reminder_id, 'deleted', true);
end;
$$;

comment on function public.delete_job_invoice_reminder(uuid, uuid) is
  'Deletes a mistaken custom-date reminder. Other kinds must be dismissed, not deleted. Needs jobs.edit.';

revoke all on function public.delete_job_invoice_reminder(uuid, uuid) from public;
revoke execute on function public.delete_job_invoice_reminder(uuid, uuid) from anon;
grant execute on function public.delete_job_invoice_reminder(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
