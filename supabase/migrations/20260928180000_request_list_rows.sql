-- The Requests list's Status filter has to match the badge the office sees, and three of those badges
-- (Today, Upcoming, Overdue) plus half of Unscheduled are worked out from the assessment, not stored on
-- the request. This view puts the request and its assessment on one row so the list can filter on both
-- in a single query. The day boundaries still come from the app (organizationDayRange), exactly as the
-- counts card's request_status_counts takes them, so the calendar rule keeps one home.
create view public.request_list_rows
with (security_invoker = true) as
select
  request.id,
  request.organization_id,
  request.title,
  request.status,
  request.service_type,
  request.created_at,
  request.client_id,
  request.property_id,
  assessment.id as assessment_id,
  assessment.starts_at as assessment_starts_at,
  assessment.ends_at as assessment_ends_at,
  assessment.all_day as assessment_all_day,
  assessment.completed_at as assessment_completed_at,
  (assessment.id is not null and assessment.completed_at is null) as has_open_assessment
from public.requests as request
left join public.assessments as assessment
  on assessment.organization_id = request.organization_id
 and assessment.request_id = request.id;

comment on view public.request_list_rows is
  'What the Requests list reads: the request plus its one assessment on the same row, so the Status filter can match the calendar-derived badge (today, upcoming, overdue, unscheduled). Runs with the caller''s rights; requests and assessments RLS both apply.';

revoke all on public.request_list_rows from anon, public;
grant select on public.request_list_rows to authenticated;
grant all on public.request_list_rows to service_role;
