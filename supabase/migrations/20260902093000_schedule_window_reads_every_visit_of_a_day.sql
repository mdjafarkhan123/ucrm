-- Schedule Part 2: the calendar's date-window read must find completed visits too.
--
-- job_visits_calendar_idx was created ahead of the Schedule with a `where completed_at is null` predicate.
-- That predicate was written for a calendar that only ever asked about outstanding work. The approved
-- Schedule behaviour contract asks for the opposite: Completed is one of the four derived visit statuses the
-- calendar draws and filters by, so the window read is
--
--   where organization_id = $1 and visit_date between $2 and $3
--
-- with no completion filter at all. Postgres cannot use a partial index for a query whose predicate it does
-- not imply, so that read would fall back to scanning job_visits across every tenant in the table.
--
-- Nothing today depends on the partial shape. Every `completed_at is null` reader in the schema
-- (move_job_visits, reschedule_job_visits, apply_visit_to_future, the recurrence rewrite) is scoped to one
-- job and is served by job_visits_job_idx (organization_id, job_id, position, id). So this replaces the
-- index rather than adding a second overlapping one: two indexes on the same leading columns would double
-- the write cost of every visit command to serve one read.
--
-- Column order follows the query: organization_id is an equality, visit_date is a range. Ordering inside the
-- window (start_time, then position) is left to the sort -- a week or a month of one contractor's visits is a
-- few hundred rows, and carrying two more columns in the index would cost every write for a sort that small.
--
-- Nulls are in the index, so the Unscheduled backlog read (`visit_date is null`) that Part 3 adds is served
-- by the same index without another one.
--
-- Built non-concurrently: this is a pre-launch schema with small visit tables. A rebuild of this index on a
-- loaded production table would need `create index concurrently` outside a transaction.

drop index if exists public.job_visits_calendar_idx;

create index job_visits_calendar_idx
  on public.job_visits(organization_id, visit_date);

comment on index public.job_visits_calendar_idx is
  'The Schedule''s bounded date-window read: one organization, a range of visit_date, every completion '
  'state. Also serves the unscheduled backlog read, where visit_date is null.';
