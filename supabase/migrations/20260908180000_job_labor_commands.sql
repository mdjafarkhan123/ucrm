-- Jobs Part 14b: recording labor.
--
-- 14a built public.job_time_entries, the rate profile beside it and the append-only correction trail, and
-- nothing has written a row into any of them since. This file gives them the four things they were waiting
-- for:
--
--   1. public.add_job_time_entry     -- record hours, copying the rate on at that moment
--   2. public.update_job_time_entry  -- correct hours already recorded
--   3. public.delete_job_time_entry  -- remove hours recorded in error
--   4. public.job_labor              -- the gated read behind the Labor section of a job
--
-- and one more the Team screen owes 14a:
--
--   5. public.set_member_cost_rate   -- what an employee costs per hour, behind team.manage
--
-- Three rules from the behavior contract shape every function below:
--
--   * A changed rate applies forward only. The rate is read once, at the moment hours are recorded, and
--     copied onto the row. No later command reads the profile again, so no rate change can re-cost work that
--     is already done. Correcting an entry keeps the rate it was recorded with.
--   * Closing a job locks the crew, not the books. An own-level holder loses the ability to touch a closed
--     job's hours; a team-level holder can still correct them, and every such correction is written to
--     job_costing_events with after_close = true.
--   * Workers never see money. Hours are visible to the person who worked them; the rate on them and the
--     cost they produce are not, in this reader or anywhere else, without jobs.view_cost.

-- 1. Who may write whose hours ------------------------------------------------------------------------------

-- Recording your own hours and recording somebody else's are different permissions, and after a job closes
-- only the second one survives. Every one of the three commands asks the same question, so it is asked in one
-- place: three copies of this rule would be three chances for the delete to disagree with the edit.
create or replace function private.can_write_job_time(
  target_organization_id uuid,
  actor_id uuid,
  subject_user_id uuid,
  job_is_closed boolean
)
returns boolean
language sql
stable
set search_path = pg_catalog, public
as $$
  select private.member_has_permission(target_organization_id, actor_id, 'jobs.view')
    and (
      private.member_has_permission(target_organization_id, actor_id, 'time.track_team')
      or (
        subject_user_id = actor_id
        and not job_is_closed
        and private.member_has_permission(target_organization_id, actor_id, 'time.track_own')
      )
    );
$$;

comment on function private.can_write_job_time(uuid, uuid, uuid, boolean) is
  'Whether this person may record or change these hours: anyone''s with time.track_team, their own with '
  'time.track_own while the job is still open. Closing a job locks the crew out of its hours, not the '
  'manager correcting them.';

revoke all on function private.can_write_job_time(uuid, uuid, uuid, boolean) from public;
revoke execute on function private.can_write_job_time(uuid, uuid, uuid, boolean) from anon, authenticated;

-- 2. Recording hours ------------------------------------------------------------------------------------------

create or replace function public.add_job_time_entry(
  target_organization_id uuid,
  target_job_id uuid,
  target_user_id uuid,
  started_at timestamptz,
  minutes integer,
  target_visit_id uuid default null,
  notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  job_closed boolean;
  recorded_rate bigint;
  new_entry public.job_time_entries;
begin
  if caller is null then
    raise exception 'You must be signed in to record hours.' using errcode = 'insufficient_privilege';
  end if;

  -- No row lock. Hours are appended to a job, never derived from it, so two people recording time at once
  -- have nothing to fight over -- and locking the job here would make every timesheet entry queue behind
  -- whatever else is editing the job.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  job_closed := current_job.status <> 'active';

  if not private.can_write_job_time(target_organization_id, caller, target_user_id, job_closed) then
    if job_closed then
      raise exception 'A closed job''s hours can only be changed by someone who manages the team''s time.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to record these hours.' using errcode = 'insufficient_privilege';
  end if;

  -- Hours belong to someone who works here. The foreign key would refuse a stranger anyway; this refuses a
  -- person who has left with a sentence instead of a constraint name.
  if not exists (
    select 1
    from public.organization_members as member
    where member.organization_id = target_organization_id
      and member.user_id = target_user_id
      and member.status <> 'removed'
  ) then
    raise exception 'That person is not on this team.' using errcode = 'P0404';
  end if;

  if target_visit_id is not null and not exists (
    select 1
    from public.job_visits as visit
    where visit.organization_id = target_organization_id
      and visit.job_id = target_job_id
      and visit.id = target_visit_id
  ) then
    raise exception 'That visit could not be found on this job.' using errcode = 'P0404';
  end if;

  -- The one and only read of the rate profile in this file. Null is kept as null: nobody has said what this
  -- person costs, and unrated hours are reported as unrated rather than valued at nothing.
  select profile.cost_per_hour_minor into recorded_rate
  from public.organization_member_cost_profiles as profile
  where profile.organization_id = target_organization_id
    and profile.user_id = target_user_id;

  insert into public.job_time_entries (
    organization_id, job_id, visit_id, user_id, started_at, minutes, notes, cost_per_hour_minor, created_by
  )
  values (
    target_organization_id, target_job_id, target_visit_id, target_user_id,
    add_job_time_entry.started_at, add_job_time_entry.minutes,
    nullif(trim(coalesce(add_job_time_entry.notes, '')), ''), recorded_rate, caller
  )
  returning * into new_entry;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close, new_values
  )
  values (
    target_organization_id, target_job_id, 'time_entry_added', 'time_entry', new_entry.id, caller, job_closed,
    jsonb_build_object(
      'user_id', new_entry.user_id,
      'visit_id', new_entry.visit_id,
      'started_at', new_entry.started_at,
      'minutes', new_entry.minutes,
      'cost_per_hour_minor', new_entry.cost_per_hour_minor,
      'cost_total_minor', new_entry.cost_total_minor
    )
  );

  return jsonb_build_object('id', new_entry.id, 'after_close', job_closed);
end;
$$;

comment on function public.add_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text) is
  'Records hours on a job, copying the person''s current cost rate onto the entry so a later rate change '
  'cannot re-cost finished work. Needs time.track_team for anyone else''s hours, time.track_own for their '
  'own on an open job. Every entry is written to job_costing_events, flagged when the job is already closed.';

revoke all on function public.add_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text) from public;
revoke execute on function public.add_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text) from anon;
grant execute on function public.add_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text) to authenticated;

-- 3. Correcting hours -------------------------------------------------------------------------------------------

-- Whose hours these are is deliberately not editable. An entry carries the rate of the person it was recorded
-- for; moving it to someone else would either keep the wrong person's rate or silently re-price the entry at
-- today's rate for the new one. Recording it again for the right person and removing this one says the same
-- thing, honestly, and leaves both halves in the trail.
create or replace function public.update_job_time_entry(
  target_organization_id uuid,
  target_job_id uuid,
  target_entry_id uuid,
  started_at timestamptz,
  minutes integer,
  target_visit_id uuid default null,
  notes text default null,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_time_entries;
  updated public.job_time_entries;
begin
  if caller is null then
    raise exception 'You must be signed in to change hours.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  -- The entry is locked, not the job: two corrections to the same entry queue, and corrections to different
  -- entries on the same job do not wait for each other.
  select entry.* into existing
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and entry.id = target_entry_id
  for update;
  if not found then
    raise exception 'Those hours could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_time(target_organization_id, caller, existing.user_id, job_closed) then
    if job_closed then
      raise exception 'A closed job''s hours can only be changed by someone who manages the team''s time.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to change these hours.' using errcode = 'insufficient_privilege';
  end if;

  if target_visit_id is not null and not exists (
    select 1
    from public.job_visits as visit
    where visit.organization_id = target_organization_id
      and visit.job_id = target_job_id
      and visit.id = target_visit_id
  ) then
    raise exception 'That visit could not be found on this job.' using errcode = 'P0404';
  end if;

  -- cost_per_hour_minor is absent on purpose. The rate stays as recorded; only the duration it applies to can
  -- change, and the generated cost column follows it.
  update public.job_time_entries as entry
  set visit_id = target_visit_id,
      started_at = update_job_time_entry.started_at,
      minutes = update_job_time_entry.minutes,
      notes = nullif(trim(coalesce(update_job_time_entry.notes, '')), '')
  where entry.organization_id = target_organization_id
    and entry.id = target_entry_id
  returning * into updated;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values, new_values
  )
  values (
    target_organization_id, target_job_id, 'time_entry_updated', 'time_entry', target_entry_id, caller,
    job_closed,
    nullif(trim(coalesce(update_job_time_entry.reason, '')), ''),
    jsonb_build_object(
      'visit_id', existing.visit_id,
      'started_at', existing.started_at,
      'minutes', existing.minutes,
      'cost_total_minor', existing.cost_total_minor
    ),
    jsonb_build_object(
      'visit_id', updated.visit_id,
      'started_at', updated.started_at,
      'minutes', updated.minutes,
      'cost_total_minor', updated.cost_total_minor
    )
  );

  return jsonb_build_object('id', updated.id, 'after_close', job_closed);
end;
$$;

comment on function public.update_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text, text) is
  'Corrects recorded hours, keeping the rate the entry was recorded with. Whose hours they are cannot change. '
  'Needs time.track_team for anyone else''s, time.track_own for their own on an open job. The before and '
  'after are written to job_costing_events.';

revoke all on function public.update_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text, text) from public;
revoke execute on function public.update_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text, text) from anon;
grant execute on function public.update_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text, text) to authenticated;

-- 4. Removing hours ---------------------------------------------------------------------------------------------

create or replace function public.delete_job_time_entry(
  target_organization_id uuid,
  target_job_id uuid,
  target_entry_id uuid,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_time_entries;
begin
  if caller is null then
    raise exception 'You must be signed in to remove hours.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  select entry.* into existing
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and entry.id = target_entry_id
  for update;
  if not found then
    raise exception 'Those hours could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_time(target_organization_id, caller, existing.user_id, job_closed) then
    if job_closed then
      raise exception 'A closed job''s hours can only be changed by someone who manages the team''s time.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to remove these hours.' using errcode = 'insufficient_privilege';
  end if;

  -- The trail is written first and keeps the whole row. job_costing_events holds subject_id as a plain id
  -- precisely so the evidence outlives the entry it describes.
  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values
  )
  values (
    target_organization_id, target_job_id, 'time_entry_deleted', 'time_entry', target_entry_id, caller,
    job_closed,
    nullif(trim(coalesce(delete_job_time_entry.reason, '')), ''),
    jsonb_build_object(
      'user_id', existing.user_id,
      'visit_id', existing.visit_id,
      'started_at', existing.started_at,
      'minutes', existing.minutes,
      'cost_per_hour_minor', existing.cost_per_hour_minor,
      'cost_total_minor', existing.cost_total_minor
    )
  );

  delete from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.id = target_entry_id;

  return jsonb_build_object('id', target_entry_id, 'after_close', job_closed);
end;
$$;

comment on function public.delete_job_time_entry(uuid, uuid, uuid, text) is
  'Removes recorded hours, writing the whole entry to job_costing_events first so deleting an entry never '
  'deletes the evidence that it existed. Same permissions as correcting one.';

revoke all on function public.delete_job_time_entry(uuid, uuid, uuid, text) from public;
revoke execute on function public.delete_job_time_entry(uuid, uuid, uuid, text) from anon;
grant execute on function public.delete_job_time_entry(uuid, uuid, uuid, text) to authenticated;

-- 5. The gated read -----------------------------------------------------------------------------------------------

-- Everything the Labor section of a job needs in one call: the hours themselves, who may change each one, and
-- the totals underneath. Definer, because it decides for itself what this reader may see -- the table's own
-- grant already withholds the rate and the cost from everyone, and this is the only door they come through.
--
-- Bounded twice over: the list is capped at 200 rows served by job_time_entries_job_started_idx, and the
-- totals are aggregated separately so a job with more hours than that still shows honest numbers.
create or replace function public.job_labor(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  page_size constant integer := 200;
  can_cost boolean;
  can_team boolean;
  can_own boolean;
  job_closed boolean;
  entries jsonb;
  totals jsonb;
  entry_count integer;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view') then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  can_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');
  can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');
  can_own := private.member_has_permission(target_organization_id, caller, 'time.track_own');

  -- The same own/team split the table's policy applies, restated here because this function is definer and
  -- the policy no longer stands between the reader and the rows.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', visible.id,
          'user_id', visible.user_id,
          'user_name', visible.user_name,
          'visit_id', visible.visit_id,
          'visit_date', visible.visit_date,
          'started_at', visible.started_at,
          'minutes', visible.minutes,
          'notes', visible.notes,
          'can_edit', can_team or (visible.user_id = caller and can_own and not job_closed),
          'is_unrated', visible.cost_per_hour_minor is null
        )
        || (case when can_cost then jsonb_build_object(
              'cost_per_hour_minor', visible.cost_per_hour_minor,
              'cost_total_minor', visible.cost_total_minor
            ) else '{}'::jsonb end)
        order by visible.started_at desc, visible.id desc
      ),
      '[]'::jsonb
    ),
    count(*)
  into entries, entry_count
  from (
    select entry.id, entry.user_id, entry.visit_id, entry.started_at, entry.minutes, entry.notes,
           entry.cost_per_hour_minor, entry.cost_total_minor,
           profile.full_name as user_name,
           visit.visit_date
    from public.job_time_entries as entry
    left join public.profiles as profile on profile.id = entry.user_id
    left join public.job_visits as visit
      on visit.organization_id = entry.organization_id and visit.id = entry.visit_id
    where entry.organization_id = target_organization_id
      and entry.job_id = target_job_id
      and (can_team or (entry.user_id = caller and can_own))
    order by entry.started_at desc, entry.id desc
    limit page_size
  ) as visible;

  select jsonb_build_object(
    'entry_count', count(*),
    'minutes', coalesce(sum(entry.minutes), 0),
    'unrated_count', count(*) filter (where entry.cost_per_hour_minor is null),
    'cost_total_minor', case when can_cost then coalesce(sum(entry.cost_total_minor), 0) else null end
  ) into totals
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and (can_team or (entry.user_id = caller and can_own));

  return jsonb_build_object(
    'entries', entries,
    'totals', totals,
    -- More hours exist than the list shows. The totals still count all of them.
    'has_more', (totals->>'entry_count')::integer > entry_count,
    'job_closed', job_closed,
    'can_add', can_team or (can_own and not job_closed),
    'can_track_team', can_team,
    'can_see_cost', can_cost
  );
end;
$$;

comment on function public.job_labor(uuid, uuid) is
  'One job''s recorded hours and their totals, newest first. A reader with time.track_team sees everyone''s '
  'and a reader with only time.track_own sees their own. Rates and costs need jobs.view_cost; without it the '
  'same rows come back with hours and no money at all.';

revoke all on function public.job_labor(uuid, uuid) from public;
revoke execute on function public.job_labor(uuid, uuid) from anon;
grant execute on function public.job_labor(uuid, uuid) to authenticated;

-- 6. What an employee costs ---------------------------------------------------------------------------------------

-- The write half of organization_member_cost_profiles, which 14a created and left unwritable. Behind
-- team.manage, the same key that guards every other change to a person's record, and separate from
-- update_team_member_profile because a name and a wage are not the same kind of fact: one is who they are,
-- the other is what we pay them.
create or replace function public.set_member_cost_rate(
  target_organization_id uuid,
  target_user_id uuid,
  new_cost_per_hour_minor bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
begin
  if caller is null or not private.member_has_permission(target_organization_id, caller, 'team.manage') then
    raise exception 'You do not have access to change what an employee costs.'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1
    from public.organization_members as member
    where member.organization_id = target_organization_id
      and member.user_id = target_user_id
      and member.status <> 'removed'
  ) then
    raise exception 'That team member was not found.' using errcode = 'P0404';
  end if;

  insert into public.organization_member_cost_profiles (
    organization_id, user_id, cost_per_hour_minor, updated_by
  )
  values (target_organization_id, target_user_id, new_cost_per_hour_minor, caller)
  on conflict (organization_id, user_id) do update
  set cost_per_hour_minor = excluded.cost_per_hour_minor,
      updated_by = excluded.updated_by,
      updated_at = now();

  -- No costing event and no re-pricing pass. A rate change is forward-only by construction: every entry
  -- already carries the rate it was recorded with, and nothing here reaches back to them.
  return jsonb_build_object('cost_per_hour_minor', new_cost_per_hour_minor);
end;
$$;

comment on function public.set_member_cost_rate(uuid, uuid, bigint) is
  'Sets what an employee costs the business per hour, behind team.manage. Null means unknown, which is not '
  'zero: their hours are reported as unrated. Applies forward only -- recorded hours keep the rate they '
  'were recorded with.';

revoke all on function public.set_member_cost_rate(uuid, uuid, bigint) from public;
revoke execute on function public.set_member_cost_rate(uuid, uuid, bigint) from anon;
grant execute on function public.set_member_cost_rate(uuid, uuid, bigint) to authenticated;

-- 7. The Team member screen reads the rate ------------------------------------------------------------------------

-- Unchanged from 20260823014051 except for the two keys at the end. The gate above already proves team.manage,
-- which is one of the two answers the cost profile's own policy accepts, so reading the rate here tells this
-- caller nothing they could not read directly.
create or replace function public.get_team_member_detail(
  target_organization_id uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  result jsonb;
begin
  if (select auth.uid()) is null or not exists (
    select 1
    from private.permitted_organizations('team.manage') as permitted(organization_id)
    where permitted.organization_id = target_organization_id
  ) then
    raise exception 'Team management is not available for this organization.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'user_id', member.user_id,
    'display_name', profile.full_name,
    'avatar_url', profile.avatar_url,
    'role', member.role,
    'status', member.status,
    'access_revision', member.access_revision,
    'profile_revision', member.profile_revision,
    'work_phone', member.work_phone,
    'job_title', member.job_title,
    'schedule_color', member.schedule_color,
    'created_at', member.created_at,
    'deactivated_at', member.deactivated_at,
    'invitation', case when invitation.id is null then null else jsonb_build_object(
      'id', invitation.id,
      'email', invitation.invited_email,
      'state', invitation.state,
      'delivery_failed', invitation.last_delivery_error is not null,
      'last_sent_at', invitation.last_sent_at,
      'expires_at', invitation.expires_at
    ) end,
    'cost_per_hour_minor', cost.cost_per_hour_minor,
    'cost_rate_updated_at', cost.updated_at
  ) into result
  from public.organization_members as member
  left join public.profiles as profile on profile.id = member.user_id
  left join public.organization_member_cost_profiles as cost
    on cost.organization_id = member.organization_id and cost.user_id = member.user_id
  left join lateral (
    select candidate.id, candidate.invited_email, candidate.state, candidate.last_delivery_error,
           candidate.last_sent_at, candidate.expires_at
    from public.organization_member_invitations as candidate
    where candidate.organization_id = member.organization_id
      and candidate.invited_user_id = member.user_id
      and candidate.state in ('reserving', 'invited', 'accepting')
    order by candidate.created_at desc, candidate.id desc
    limit 1
  ) as invitation on true
  where member.organization_id = target_organization_id
    and member.user_id = target_user_id
    and member.status <> 'removed';

  if result is null then
    raise exception 'That team member was not found.' using errcode = 'P0002';
  end if;

  return result;
end;
$function$;

comment on function public.get_team_member_detail(uuid, uuid) is
  'Returns one tenant-authorized Team member for the read-first details route, including their hourly cost '
  'rate; access editing remains separate.';

revoke all on function public.get_team_member_detail(uuid, uuid) from public, anon, service_role;
grant execute on function public.get_team_member_detail(uuid, uuid) to authenticated;

-- 8. Housekeeping 14a left ------------------------------------------------------------------------------------------

-- Every other table in this schema keeps its own updated_at rather than trusting each command to remember.
create trigger job_time_entries_set_updated_at
before update on public.job_time_entries
for each row execute function public.set_updated_at();

create trigger job_expenses_set_updated_at
before update on public.job_expenses
for each row execute function public.set_updated_at();

create trigger organization_member_cost_profiles_set_updated_at
before update on public.organization_member_cost_profiles
for each row execute function public.set_updated_at();
