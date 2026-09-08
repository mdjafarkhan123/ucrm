-- Jobs, Part 15g: keep every combined-history branch inside the target Job's organization.
--
-- The existing indexes lead with organization_id. Resolving the Job's organization once per branch gives the
-- planner that leading predicate instead of making it scan business-wide history before finding one Job.

create or replace function public.job_combined_history(
  target_job_id uuid,
  result_limit integer default 100
)
returns table (
  id uuid,
  source text,
  event_type text,
  summary text,
  actor_id uuid,
  created_at timestamptz,
  metadata jsonb,
  visit_id uuid,
  visit_label text
)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select history.id,
         history.source,
         history.event_type,
         history.summary,
         history.actor_id,
         history.created_at,
         history.metadata,
         history.visit_id,
         history.visit_label
  from (
    select event.id,
           'job_event'::text as source,
           event.event_type,
           null::text as summary,
           event.actor_id,
           event.created_at,
           event.metadata,
           event.related_visit_id as visit_id,
           null::text as visit_label
    from public.job_events as event
    where event.organization_id = (
      select job.organization_id from public.jobs as job where job.id = target_job_id
    )
      and event.job_id = target_job_id

    union all

    select activity.id,
           'field_record'::text as source,
           activity.event_type,
           activity.summary,
           activity.actor_user_id as actor_id,
           activity.created_at,
           activity.metadata,
           null::uuid as visit_id,
           null::text as visit_label
    from public.activity_events as activity
    where activity.organization_id = (
      select job.organization_id from public.jobs as job where job.id = target_job_id
    )
      and activity.entity_type = 'job'
      and activity.entity_id = target_job_id

    union all

    select activity.id,
           'field_record'::text as source,
           activity.event_type,
           activity.summary,
           activity.actor_user_id as actor_id,
           activity.created_at,
           activity.metadata,
           visit.id as visit_id,
           coalesce(
             nullif(trim(visit.title), ''),
             case
               when visit.visit_date is not null then 'Visit on ' || to_char(visit.visit_date, 'Mon FMDD, YYYY')
               else 'Unscheduled visit'
             end
           ) as visit_label
    from public.job_visits as visit
    join public.activity_events as activity
      on activity.entity_type = 'visit'
     and activity.entity_id = visit.id
     and activity.organization_id = visit.organization_id
    where visit.organization_id = (
      select job.organization_id from public.jobs as job where job.id = target_job_id
    )
      and visit.job_id = target_job_id
  ) as history
  order by history.created_at desc, history.id desc
  limit least(greatest(coalesce(result_limit, 100), 1), 100);
$$;

comment on function public.job_combined_history(uuid, integer) is
  'Newest Job lifecycle and internal Job/Visit field-record events in one bounded, tenant-scoped timeline. '
  'Security invoker: the underlying Jobs and linked-record RLS remains the authority.';

revoke all on function public.job_combined_history(uuid, integer) from public;
revoke execute on function public.job_combined_history(uuid, integer) from anon;
grant execute on function public.job_combined_history(uuid, integer) to authenticated;
