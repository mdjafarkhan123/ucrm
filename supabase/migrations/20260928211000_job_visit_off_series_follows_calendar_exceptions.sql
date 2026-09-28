-- Follow-up to 20260928210000. Measuring a visit's time against the repeat rule flagged every visit that
-- "apply to later visits" had moved to a new time, although that action changes the series itself (Jobber's
-- "update future visits"; a calendar's this-and-following edit). The marker now follows the calendar
-- exception model instead: a generated visit is off series when its date left its series_date, or when its
-- time was changed on that visit alone. Copying a time forward clears the second part for the source and
-- every later visit it reached.

drop trigger job_visits_track_series_update on public.job_visits;

alter table public.job_visits
  drop column off_series,
  add column time_changed_alone boolean not null default false,
  add column off_series boolean generated always as (
    source = 'generated'
    and (series_date is null or visit_date is distinct from series_date or time_changed_alone)
  ) stored;

comment on column public.job_visits.time_changed_alone is
  'True once a generated visit''s start, end or all-day setting is changed on that visit alone. Set by job_visits_track_series; cleared when apply_visit_to_future copies a time forward over it.';
comment on column public.job_visits.off_series is
  'True when a generated visit is an exception to its repeat series: moved off its series_date, unscheduled, or given its own time.';

create or replace function private.job_visits_track_series()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.source is distinct from 'generated' then
    new.series_date := null;
    new.time_changed_alone := false;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.series_date := coalesce(new.series_date, new.visit_date);
  elsif new.all_day is distinct from old.all_day
    or new.start_time is distinct from old.start_time
    or new.end_time is distinct from old.end_time then
    new.time_changed_alone := true;
  end if;
  return new;
end;
$$;

comment on function private.job_visits_track_series() is
  'Stamps a generated visit''s series_date on insert and marks time_changed_alone when its time changes. apply_visit_to_future clears that mark afterwards for a time copied forward.';

create trigger job_visits_track_series_update
  before update of start_time, end_time, all_day, source on public.job_visits
  for each row execute function private.job_visits_track_series();

CREATE OR REPLACE FUNCTION "public"."apply_visit_to_future"("target_organization_id" "uuid", "target_job_id" "uuid", "source_visit_id" "uuid", "copy_time_of_day" boolean, "copy_assigned_team" boolean, "new_idempotency_key" "text", "new_request_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  source_visit public.job_visits;
  receipt_id uuid;
  existing_receipt public.job_command_receipts;
  target_ids uuid[];
  updated_count integer;
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  if not coalesce(copy_time_of_day, false) and not coalesce(copy_assigned_team, false) then
    raise exception 'Choose at least one setting to apply to the later visits.'
      using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  select visit.* into source_visit
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = source_visit_id;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;
  if source_visit.visit_date is null then
    raise exception 'Give this visit a date before applying it to later visits.'
      using errcode = 'check_violation';
  end if;

  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'apply_visit_to_future', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'apply_visit_to_future'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'These settings were already applied differently.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  select coalesce(array_agg(visit.id order by visit.visit_date, visit.position), array[]::uuid[])
  into target_ids
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id <> source_visit_id
    and visit.completed_at is null
    and visit.visit_date is not null
    and visit.visit_date > source_visit.visit_date;

  updated_count := coalesce(array_length(target_ids, 1), 0);

  if updated_count > 0 then
    if coalesce(copy_time_of_day, false) then
      update public.job_visits
      set start_time = source_visit.start_time,
          end_time = source_visit.end_time,
          all_day = source_visit.all_day,
          revision = revision + 1,
          updated_at = now()
      where organization_id = target_organization_id
        and id = any(target_ids);

      -- Copying a time forward changes the series from this visit on, as Jobber's "update future visits"
      -- does, so neither the source nor the later visits count as changed on their own any more.
      update public.job_visits
      set time_changed_alone = false
      where organization_id = target_organization_id
        and (id = any(target_ids) or id = source_visit_id)
        and time_changed_alone;
    end if;

    if coalesce(copy_assigned_team, false) then
      delete from public.job_visit_assignments
      where organization_id = target_organization_id
        and visit_id = any(target_ids);

      insert into public.job_visit_assignments (organization_id, visit_id, user_id)
      select target_organization_id, target_visit, assignment.user_id
      from unnest(target_ids) as target_visit
      cross join public.job_visit_assignments as assignment
      where assignment.organization_id = target_organization_id
        and assignment.visit_id = source_visit_id
      on conflict do nothing;

      if not coalesce(copy_time_of_day, false) then
        update public.job_visits
        set revision = revision + 1,
            updated_at = now()
        where organization_id = target_organization_id
          and id = any(target_ids);
      end if;
    end if;
  end if;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visits_updated_forward',
    caller,
    source_visit_id,
    jsonb_build_object(
      'count', updated_count,
      'time_of_day', coalesce(copy_time_of_day, false),
      'assigned_team', coalesce(copy_assigned_team, false)
    )
  );

  final_result := jsonb_build_object('applied', true, 'updated_count', updated_count);
  update public.job_command_receipts set result = final_result where id = receipt_id;
  return final_result;
end;
$$;

