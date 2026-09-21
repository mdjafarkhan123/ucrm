-- Invoices Part 5b-5: the ready-to-bill queue.
--
-- Every "time to bill this" signal in the app is already an invoice reminder (Jobs 11b). A pending reminder
-- whose date has arrived is what puts a job in the Requires invoicing derived status, and Jobber uses exactly
-- that flag as the workflow lever that gathers everything owing an invoice into one place. This part is the
-- cross-client version of that: one page of jobs that owe an invoice today, oldest first, with the amount
-- still waiting to be billed on each.
--
-- Two reads and nothing else. No new table, no stored total, no background job:
--
--   1. private.job_uninvoiced_work -- how much of one job is still billable, and in what units.
--   2. public.ready_to_bill_page   -- one keyset page of jobs with a due reminder.
--   3. public.ready_to_bill_count  -- the same predicate, counted, for the entry point's badge.
--
-- Deliberately NOT here: batch selection (Part 8 owns it), extra sort options, a client filter, and any
-- attempt to surface jobs that never raised a reminder. A job billed "manually" opted out of reminders on
-- purpose; a job billed "on dates we pick ourselves" with no dates entered is a hole in the job's billing
-- setup, not something this queue can invent a due date for.

-- 1. How much of one job is still waiting to be billed -------------------------------------------------------
--
-- The three price bases each already have an answer somewhere in the app, and this states the same three rules
-- once so the queue cannot drift from the screen that does the billing:
--
--   job_total        -- the whole job, once. Any claim at all and there is nothing left; that is the same
--                       rule claim_invoice_sources and 5a's picker enforce.
--   per_visit        -- one copy of the job's priced lines per completed, unbilled visit. The same subtotal x
--                       count the job page's "Visits ready to bill" card shows.
--   fixed_per_period -- one copy per due, still-pending calendar reminder. The same subtotal x count the job
--                       page's "Periods ready to bill" card shows.
--
-- Cost is bounded by one job: an index probe into invoice_sources_job_idx for the whole-job test, and a scan
-- of that job's own visits (job_visits_job_idx) or its own pending reminders
-- (job_invoice_reminders_pending_due_idx) for the other two. Nothing here grows with the organization.
create or replace function private.job_uninvoiced_work(
  target_organization_id uuid,
  target_job_id uuid,
  job_price_basis text,
  job_subtotal_minor bigint,
  job_total_minor bigint,
  as_of date
)
returns table(unit_kind text, unit_count integer, uninvoiced_minor bigint)
language sql
stable
set search_path = pg_catalog, public
as $$
  select
    case job_price_basis
      when 'per_visit' then 'visits'
      when 'fixed_per_period' then 'periods'
      else 'job'
    end as unit_kind,
    units.count::integer as unit_count,
    (case when job_price_basis = 'job_total' then job_total_minor else job_subtotal_minor end
      * units.count)::bigint as uninvoiced_minor
  from (
    select case job_price_basis
      when 'per_visit' then (
        select count(*)
        from public.job_visits as visit
        where visit.organization_id = target_organization_id
          and visit.job_id = target_job_id
          and visit.completed_at is not null
          and not exists (
            select 1
            from public.invoice_sources as claim
            where claim.organization_id = visit.organization_id
              and claim.visit_id = visit.id
              and claim.source_kind = 'visit'
          )
      )
      when 'fixed_per_period' then (
        select count(*)
        from public.job_invoice_reminders as reminder
        where reminder.organization_id = target_organization_id
          and reminder.job_id = target_job_id
          and reminder.status = 'pending'
          and reminder.due_on <= as_of
          and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      )
      else (
        select case when exists (
          select 1
          from public.invoice_sources as claim
          where claim.organization_id = target_organization_id
            and claim.job_id = target_job_id
        ) then 0 else 1 end
      )
    end as count
  ) as units;
$$;

comment on function private.job_uninvoiced_work(uuid, uuid, text, bigint, bigint, date) is
  'How much of one job is still billable and in what units, stating the same three rules the billing screens '
  'already use: a whole job once, one copy per completed unbilled visit, or one copy per due pending period. '
  'Bounded to a single job. Callers own the permission check.';

revoke all on function private.job_uninvoiced_work(uuid, uuid, text, bigint, bigint, date) from public;
revoke execute on function private.job_uninvoiced_work(uuid, uuid, text, bigint, bigint, date)
  from anon, authenticated;

-- 2. Finding the page before paying for it ---------------------------------------------------------------------
--
-- The queue is ordered by the oldest due reminder on each job, so the money that has been waiting longest is at
-- the top. The obvious shape -- gather every due reminder, keep one row per job, join the amounts, then sort and
-- take 25 -- was written and measured first, and it cost 4.2 SECONDS on a 40,000-job organization with a
-- 90,000-reminder backlog. The reason is that the per-job amount is a lateral join, so Postgres computed it for
-- all 40,000 candidate jobs before the LIMIT ever narrowed anything.
--
-- So the page is found before it is priced. The candidate CTE below returns exactly the 25 reminder rows the page
-- shows and nothing else; only then is each one joined to its job, its client, its property and its amount. Three
-- properties make that first step cheap:
--
--   * ready_to_bill_queue_idx is (organization_id, due_on, id) where status = 'pending', so the scan arrives in
--     the queue's own order and stops as soon as 25 rows qualify, whatever the backlog behind them.
--   * "the oldest due reminder on this job" is expressed as "no earlier pending due reminder exists on it",
--     which is one probe into job_invoice_reminders_pending_due_idx per row scanned, instead of a de-duplication
--     pass over the whole backlog.
--   * the keyset cursor is (due_on, reminder id), a unique pair, so paging deeper costs the same as page one.
--
-- Search is the one narrowing the index cannot serve: a search term has to look at the job and client behind
-- each candidate, so it walks the backlog. It is bounded by that backlog and it is a deliberate user action,
-- not what the screen does on load. Measured with this part.
create or replace function public.ready_to_bill_page(
  target_organization_id uuid,
  search_like text default null,
  search_number bigint default null,
  cursor_due_on date default null,
  cursor_reminder_id uuid default null,
  page_limit integer default 25
)
returns table(
  job_id uuid,
  job_number integer,
  title text,
  job_type text,
  price_basis text,
  billing_timing text,
  currency_code text,
  oldest_due_on date,
  cursor_reminder uuid,
  due_reminder_count integer,
  unit_kind text,
  unit_count integer,
  uninvoiced_minor bigint,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  property_label text,
  property_address_line1 text,
  property_city text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  today date;
begin
  if caller is null then
    raise exception 'You must be signed in to see what is ready to bill.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to bill work here.' using errcode = 'insufficient_privilege';
  end if;
  -- The queue's whole point is the amount waiting, so a reader without job prices would get a list of blanks.
  -- The same honest refusal client_billable_work gives.
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to job prices, so there is nothing to compare here.'
      using errcode = 'insufficient_privilege';
  end if;

  if page_limit is null or page_limit < 1 or page_limit > 50 then
    page_limit := 25;
  end if;
  today := private.organization_today(target_organization_id);

  return query
  with candidate as (
    select reminder.id as reminder_id, reminder.job_id, reminder.due_on
    from public.job_invoice_reminders as reminder
    where reminder.organization_id = target_organization_id
      and reminder.status = 'pending'
      and reminder.due_on <= today
      and (
        cursor_due_on is null or cursor_reminder_id is null
        or (reminder.due_on, reminder.id) > (cursor_due_on, cursor_reminder_id)
      )
      -- One row per job: this reminder is the job's oldest still-open due one.
      and not exists (
        select 1
        from public.job_invoice_reminders as earlier
        where earlier.organization_id = reminder.organization_id
          and earlier.job_id = reminder.job_id
          and earlier.status = 'pending'
          and earlier.due_on <= today
          and (earlier.due_on, earlier.id) < (reminder.due_on, reminder.id)
      )
      and (
        search_like is null
        or exists (
          select 1
          from public.jobs as candidate_job
          left join public.clients as candidate_client
            on candidate_client.organization_id = candidate_job.organization_id
            and candidate_client.id = candidate_job.client_id
          where candidate_job.organization_id = reminder.organization_id
            and candidate_job.id = reminder.job_id
            and (
              candidate_job.title ilike search_like
              or candidate_client.display_name ilike search_like
              or candidate_client.company_name ilike search_like
              or (search_number is not null and candidate_job.job_number = search_number)
            )
        )
      )
    order by reminder.due_on, reminder.id
    limit page_limit
  )
  select
    job.id,
    job.job_number,
    job.title,
    job.job_type,
    job.price_basis,
    job.billing_timing,
    job.currency_code,
    candidate.due_on,
    candidate.reminder_id,
    (
      select count(*)::integer
      from public.job_invoice_reminders as counted
      where counted.organization_id = job.organization_id
        and counted.job_id = job.id
        and counted.status = 'pending'
        and counted.due_on <= today
    ),
    work.unit_kind,
    work.unit_count,
    work.uninvoiced_minor,
    job.client_id,
    client.display_name,
    client.company_name,
    property.label,
    property.address_line1,
    property.city
  from candidate
  join public.jobs as job
    on job.organization_id = target_organization_id and job.id = candidate.job_id
  left join public.clients as client
    on client.organization_id = job.organization_id and client.id = job.client_id
  left join public.properties as property
    on property.organization_id = job.organization_id and property.id = job.property_id
  cross join lateral private.job_uninvoiced_work(
    job.organization_id, job.id, job.price_basis, job.subtotal_minor, job.total_minor, today
  ) as work
  order by candidate.due_on, candidate.reminder_id;
end;
$$;

comment on function public.ready_to_bill_page(uuid, text, bigint, date, uuid, integer) is
  'One keyset page of jobs that owe an invoice today -- a pending reminder whose date has arrived -- oldest '
  'first, with the amount still waiting on each. The page is selected before the amounts are computed, so the '
  'per-job work is paid for 25 times, not once per job in the organization. Definer; checks invoices.create '
  'and jobs.view_price and scopes every row to the one organization.';

revoke all on function public.ready_to_bill_page(uuid, text, bigint, date, uuid, integer) from public, anon;
grant execute on function public.ready_to_bill_page(uuid, text, bigint, date, uuid, integer) to authenticated;

-- 3. The badge on the entry point ------------------------------------------------------------------------------
--
-- Distinct jobs, over exactly the predicate the list pages through, so the number on the button and the number
-- of rows behind it can never disagree. Unlike the page, this one cannot stop early -- a count is the whole set
-- by definition -- so it is an index-only scan of the organization's due reminders and nothing more: no join,
-- no job, no amount. Measured at 68 ms against a 90,000-reminder backlog, which is a backlog far past what a
-- contractor who invoices at all would ever carry.
create or replace function public.ready_to_bill_count(target_organization_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  today date;
  total integer;
begin
  if caller is null
    or not private.member_has_permission(target_organization_id, caller, 'invoices.create')
    or not private.member_has_permission(target_organization_id, caller, 'jobs.view_price')
  then
    -- A badge is not the place for a refusal: a member who may not bill simply has nothing waiting.
    return 0;
  end if;

  today := private.organization_today(target_organization_id);

  select count(distinct reminder.job_id)::integer into total
  from public.job_invoice_reminders as reminder
  where reminder.organization_id = target_organization_id
    and reminder.status = 'pending'
    and reminder.due_on <= today;

  return coalesce(total, 0);
end;
$$;

comment on function public.ready_to_bill_count(uuid) is
  'How many jobs owe an invoice today, counted over the same predicate ready_to_bill_page lists. Returns 0 '
  'rather than refusing when the caller may not bill, so the entry point can simply not appear.';

revoke all on function public.ready_to_bill_count(uuid) from public, anon;
grant execute on function public.ready_to_bill_count(uuid) to authenticated;

-- 4. The one index this part adds --------------------------------------------------------------------------------
--
-- The existing job_invoice_reminders_pending_due_idx is keyed (organization_id, job_id, due_on): perfect for
-- "does THIS job owe an invoice", which is what the job list and the derived status ask, and useless for "which
-- job has owed one the longest", which is what a queue asks. This one is keyed by date instead, so the page scan
-- arrives already sorted and stops at 25 rows.
--
-- Its cost is one more partial index on a table written when a visit is completed, a month rolls over, or a bill
-- resolves a reminder -- single-row writes, never bulk -- and it only ever holds the pending rows, which is the
-- small live part of the table. Earned: without it the same page sorts the whole backlog on every load.
create index if not exists ready_to_bill_queue_idx
  on public.job_invoice_reminders(organization_id, due_on, id)
  where status = 'pending';

comment on index public.ready_to_bill_queue_idx is
  'Serves the ready-to-bill queue''s ordering and keyset seek: pending reminders in due-date order within one '
  'organization, so a page reads 25 rows however long the backlog behind them is.';
