-- Requests and Assessments, Part 1d.
-- The Requests list shows an Overview card counting requests by the status the office actually sees.
-- Three of those statuses — today, upcoming, overdue — are not stored; they come from the assessment's
-- start time compared against today in the organization's own timezone.
--
-- The timezone rule stays in one place: `src/lib/server/requests/status.ts` decides where "today" starts
-- and ends, and hands those two instants in. This function only buckets rows between them. Writing the
-- calendar rule a second time in SQL would let the two copies drift, and the moment they do, today /
-- upcoming / overdue are wrong.
--
-- security invoker, so the caller's row-level security still decides which rows they can see. The
-- organization filter is belt and braces on top of it.
create or replace function public.request_status_counts(
  target_organization_id uuid,
  day_start timestamptz,
  day_end timestamptz
)
returns table(display_status text, total bigint)
language sql
stable
set search_path = pg_catalog, public
security invoker
as $$
  select
    case
      -- A finished or closed request keeps its own status. The calendar has nothing left to say about it.
      when r.status in ('assessment_completed', 'completed', 'converted', 'archived') then r.status
      when a.id is null or a.completed_at is not null then r.status
      when a.starts_at is null then 'unscheduled'
      when a.starts_at >= day_end then 'upcoming'
      when a.starts_at < day_start then 'overdue'
      else 'today'
    end as display_status,
    count(*) as total
  from public.requests r
  left join public.assessments a
    on a.organization_id = r.organization_id
   and a.request_id = r.id
  where r.organization_id = target_organization_id
  group by 1;
$$;

revoke all on function public.request_status_counts(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.request_status_counts(uuid, timestamptz, timestamptz) to authenticated;
