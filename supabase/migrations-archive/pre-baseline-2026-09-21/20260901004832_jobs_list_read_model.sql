-- Jobs Part 6: the list's read model.
--
-- The Jobs list shows a status Jobber shows too, but ours is never stored: Upcoming, Today, Late,
-- Unscheduled, Action required, Requires invoicing, Archived and Ending soon are all read off the row and
-- the clock. Whoever derives them has to be one place, or two screens will eventually disagree about what
-- "Late" means. That place is the database, so the list, the overview counts and every later reader see the
-- same label from the same rule.
--
-- Visits, invoice reminders and billing do not exist yet (Parts 9 and 11). Until they do, every label that
-- needs them reads as Unscheduled, which is the truth: an active job nobody has put on the calendar.

-- 1. Today, where the contractor is ---------------------------------------------------------------------

-- A calendar label is only right in the organization's own timezone; midnight in Austin is not midnight in
-- UTC. `organization_settings` is gated to settings.business.view, so an ordinary member cannot read the
-- timezone directly and this definer helper reads it for them. It returns a date and nothing else, so it
-- discloses no setting a member could not already infer from a calendar.
create or replace function private.organization_today(target_organization_id uuid)
returns date
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select (now() at time zone coalesce(
    nullif(btrim(settings.timezone), ''),
    'UTC'
  ))::date
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id
  union all
  select (now() at time zone 'UTC')::date
  limit 1;
$$;

comment on function private.organization_today(uuid) is
  'Today''s date in the organization''s own timezone. Definer because organization_settings is gated to '
  'settings.business.view and every member needs the calendar day to read a job''s status.';

revoke all on function private.organization_today(uuid) from public;
revoke execute on function private.organization_today(uuid) from anon;
-- The list view calls this as the reader, the same way the RLS policies call private.has_permission.
grant execute on function private.organization_today(uuid) to authenticated;

-- 2. The one rule that names a job's operational state ----------------------------------------------------

-- Immutable and parameterised rather than a lookup of its own: the caller supplies the calendar day, so the
-- rule can be reasoned about and tested without a clock, and a page of rows costs one timezone read.
--
-- Priority matters. A closed job is archived whatever its dates say. A recurring agreement running out is
-- the fact the contractor has to act on before anything else. The visit-driven labels (Late, Today,
-- Upcoming, Action required) and Requires invoicing sit between those and Unscheduled; their inputs arrive
-- in Parts 9 and 11, and until then the fall-through is Unscheduled.
create or replace function private.job_derived_status(
  stored_status text,
  job_type text,
  contract_end_date date,
  today date
)
returns text
language sql
immutable
as $$
  select case
    when stored_status = 'closed' then 'archived'
    when job_type = 'recurring'
      and contract_end_date is not null
      and contract_end_date >= today
      and contract_end_date <= today + 30 then 'ending_soon'
    else 'unscheduled'
  end;
$$;

comment on function private.job_derived_status(text, text, date, date) is
  'The job status a person reads, derived and never stored. Archived beats everything; a recurring '
  'agreement ending within 30 days beats the schedule labels; everything else is Unscheduled until visits '
  'and invoice reminders exist.';

revoke all on function private.job_derived_status(text, text, date, date) from public;
revoke execute on function private.job_derived_status(text, text, date, date) from anon;
grant execute on function private.job_derived_status(text, text, date, date) to authenticated;

-- 3. The list's rows -------------------------------------------------------------------------------------

-- A security-invoker view, so the reader's own RLS and column grants apply exactly as they would on the
-- tables: jobs stays fenced off from its money columns, and a member without customers.view sees the job
-- with an empty client name rather than a name they may not read. The view is a plain projection, so the
-- planner inlines it and the list's keyset paging still runs on jobs_active_idx and
-- jobs_organization_created_idx.
create view public.job_list_rows
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
    private.organization_today(job.organization_id)
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
left join public.clients as client
  on client.organization_id = job.organization_id and client.id = job.client_id
left join public.properties as property
  on property.organization_id = job.organization_id and property.id = job.property_id;

comment on view public.job_list_rows is
  'What the Jobs list draws: identity, client and property context, and the derived status. No money — '
  'that comes from public.job_money, which checks jobs.view_price and jobs.view_cost for itself.';

revoke all on public.job_list_rows from anon, authenticated;
grant select on public.job_list_rows to authenticated;

-- 4. The overview counts ---------------------------------------------------------------------------------

-- The five tiles at the top of the list, counted live like the Quotes overview so they can never be stale.
-- It counts the same view the list draws, so a tile and the rows behind it can never disagree about what a
-- status means. Security invoker, so the reader's own RLS on jobs decides which rows are counted and a
-- member of another organization counts nothing.
create or replace function public.job_status_counts(target_organization_id uuid)
returns table(derived_status text, total bigint)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select listed.derived_status, count(*) as total
  from public.job_list_rows as listed
  where listed.organization_id = target_organization_id
  group by 1;
$$;

comment on function public.job_status_counts(uuid) is
  'Live count of this organization''s jobs by derived status, for the Jobs overview card.';

revoke all on function public.job_status_counts(uuid) from public, anon;
grant execute on function public.job_status_counts(uuid) to authenticated;

notify pgrst, 'reload schema';
