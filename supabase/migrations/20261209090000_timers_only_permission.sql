-- Time clock Part 6: the "timers only" permission (plan § Permissions, docs/time-clock-behavior-contract.md).
--
-- Three rungs for hours:
--   time.timers_own  Start and stop their own timers and clock in and out, and see their own Timesheets.
--                    Cannot add, change or delete any hours. (new, lowest)
--   time.track_own   The above, plus add and correct their own entries.
--   time.track_team  All of the above for everyone, and the manager actions.
--
-- Seeing one's own hours now takes either of the two lower rungs (private.can_see_own_time). Writing hours is
-- unchanged: private.can_write_job_time and private.can_write_general_time still need time.track_own or
-- time.track_team, and every typed-hours command goes through them. Stopping one's own running timer needs only
-- membership, as before, so a timers-only member's Stop still lands the hours once.
--
-- The Field preset moves to the new rung, like Jobber's Field crew (Jafar, 2026-10-11): existing Field members
-- can no longer type or change their own hours, and the office corrects them. A member given time.track_own by
-- hand keeps it. A member denied time.track_own by hand could not run timers before, so they are denied the
-- new rung too and nothing opens up for them.

insert into public.permissions (key, description, scope_model)
values ('time.timers_own', 'Start and stop their own timers and see their own hours', 'none')
on conflict (key) do nothing;

-- Every role that records its own hours also holds the rung beneath, so Team access reads as a ladder.
insert into public.role_permissions (role, permission_key, access_scope)
select role_permission.role, 'time.timers_own', 'all'
from public.role_permissions as role_permission
where role_permission.permission_key = 'time.track_own'
on conflict (role, permission_key) do nothing;

insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state)
select override.organization_id, override.user_id, 'time.timers_own', 'deny'
from public.organization_member_permission_overrides as override
where override.permission_key = 'time.track_own'
	and override.override_state = 'deny'
on conflict (organization_id, user_id, permission_key) do nothing;

delete from public.role_permissions
where role = 'field' and permission_key = 'time.track_own';

-- ---------------------------------------------------------------------------------------------------
-- Who may see their own hours, and who may run their own timer
-- ---------------------------------------------------------------------------------------------------

create or replace function private.can_see_own_time(target_organization_id uuid, actor_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
	select private.member_has_permission(target_organization_id, actor_id, 'time.timers_own')
		or private.member_has_permission(target_organization_id, actor_id, 'time.track_own');
$$;

comment on function private.can_see_own_time(uuid, uuid) is
	'Whether a member may see their own hours: time.timers_own or time.track_own. Seeing is not changing: writing hours still needs time.track_own (can_write_job_time, can_write_general_time).';

revoke all on function private.can_see_own_time(uuid, uuid) from public, anon;
grant execute on function private.can_see_own_time(uuid, uuid) to authenticated, service_role;

create or replace function private.can_run_own_timer(target_organization_id uuid, actor_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
	select private.member_has_permission(target_organization_id, actor_id, 'jobs.view')
		and (
			private.member_has_permission(target_organization_id, actor_id, 'time.timers_own')
			or private.member_has_permission(target_organization_id, actor_id, 'time.track_own')
			or private.member_has_permission(target_organization_id, actor_id, 'time.track_team')
		);
$$;

-- ---------------------------------------------------------------------------------------------------
-- Reading: the own-hours half of each who-sees-whom rule takes either lower rung
-- ---------------------------------------------------------------------------------------------------

alter policy "permitted members can view time entries" on public.job_time_entries
	using (
		organization_id = (select private.current_organization())
		and (
			(select private.current_permission_scope('jobs.view')) = 'all'
			or (
				(select private.current_permission_scope('jobs.view')) = 'assigned'
				and private.is_assigned_to_job(organization_id, job_id)
			)
		)
		and (
			(select private.current_permission_scope('time.track_team')) <> 'none'
			or (
				user_id = (select auth.uid())
				and (
					(select private.current_permission_scope('time.track_own')) <> 'none'
					or (select private.current_permission_scope('time.timers_own')) <> 'none'
				)
			)
		)
	);

alter policy "permitted members can view running timers" on public.running_timers
	using (
		organization_id = (select private.current_organization())
		and (
			job_id is null
			or (select private.current_permission_scope('jobs.view')) = 'all'
			or (
				(select private.current_permission_scope('jobs.view')) = 'assigned'
				and private.is_assigned_to_job(organization_id, job_id)
			)
		)
		and (
			(select private.current_permission_scope('time.track_team')) <> 'none'
			or (
				user_id = (select auth.uid())
				and (
					(select private.current_permission_scope('time.track_own')) <> 'none'
					or (select private.current_permission_scope('time.timers_own')) <> 'none'
				)
			)
		)
	);

alter policy "permitted members can view general time" on public.general_time_entries
	using (
		organization_id = (select private.current_organization())
		and (
			(select private.current_permission_scope('time.track_team')) <> 'none'
			or (
				user_id = (select auth.uid())
				and (
					(select private.current_permission_scope('time.track_own')) <> 'none'
					or (select private.current_permission_scope('time.timers_own')) <> 'none'
				)
			)
		)
	);

-- The functions below are unchanged except that reading one's own hours uses can_see_own (either lower rung),
-- while can_own (time.track_own) still decides can_add, can_edit and can_delete.

create or replace function public.job_labor(target_organization_id uuid, target_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
	caller uuid := (select auth.uid());
	page_size constant integer := 200;
	can_cost boolean;
	can_team boolean;
	can_own boolean;
	can_see_own boolean;
	job_closed boolean;
	entries jsonb;
	running jsonb;
	totals jsonb;
	entry_count integer;
begin
	if caller is null then
		raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
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
	can_see_own := private.can_see_own_time(target_organization_id, caller);

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
					'source', visible.source,
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
					 entry.source, entry.cost_per_hour_minor, entry.cost_total_minor,
					 profile.full_name as user_name,
					 visit.visit_date
		from public.job_time_entries as entry
		left join public.profiles as profile on profile.id = entry.user_id
		left join public.job_visits as visit
			on visit.organization_id = entry.organization_id and visit.id = entry.visit_id
		where entry.organization_id = target_organization_id
			and entry.job_id = target_job_id
			and (can_team or (entry.user_id = caller and can_see_own))
		order by entry.started_at desc, entry.id desc
		limit page_size
	) as visible;

	-- Timers still running on this job, under the same own/team split. Their hours are not in the totals yet:
	-- labour is counted once the timer stops.
	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'user_id', timer.user_id,
				'user_name', profile.full_name,
				'visit_id', timer.visit_id,
				'visit_date', visit.visit_date,
				'started_at', timer.started_at
			)
			order by timer.started_at
		),
		'[]'::jsonb
	) into running
	from public.running_timers as timer
	left join public.profiles as profile on profile.id = timer.user_id
	left join public.job_visits as visit
		on visit.organization_id = timer.organization_id and visit.id = timer.visit_id
	where timer.organization_id = target_organization_id
		and timer.job_id = target_job_id
		and (can_team or (timer.user_id = caller and can_see_own));

	select jsonb_build_object(
		'entry_count', count(*),
		'minutes', coalesce(sum(entry.minutes), 0),
		'unrated_count', count(*) filter (where entry.cost_per_hour_minor is null),
		'cost_total_minor', case when can_cost then coalesce(sum(entry.cost_total_minor), 0) else null end
	) into totals
	from public.job_time_entries as entry
	where entry.organization_id = target_organization_id
		and entry.job_id = target_job_id
		and (can_team or (entry.user_id = caller and can_see_own));

	return jsonb_build_object(
		'entries', entries,
		'running', running,
		'totals', totals,
		-- More hours exist than the list shows. The totals still count all of them.
		'has_more', (totals->>'entry_count')::integer > entry_count,
		'job_closed', job_closed,
		'can_add', can_team or (can_own and not job_closed),
		'can_track_team', can_team,
		'can_see_cost', can_cost,
		'server_now', now()
	);
end;
$function$;

create or replace function public.time_entry_history(target_organization_id uuid, target_entry_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	caller uuid := (select auth.uid());
	can_team boolean;
	entry_owner uuid;
	events jsonb;
begin
	if caller is null then
		raise exception 'You must be signed in to see this history.' using errcode = 'insufficient_privilege';
	end if;
	can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');

	-- Whose hours these are now: the entry, the running timer, or the last history row of a deleted entry.
	select coalesce(
		(select entry.user_id from public.job_time_entries as entry
			where entry.organization_id = target_organization_id and entry.id = target_entry_id),
		(select entry.user_id from public.general_time_entries as entry
			where entry.organization_id = target_organization_id and entry.id = target_entry_id),
		(select timer.user_id from public.running_timers as timer
			where timer.organization_id = target_organization_id and timer.id = target_entry_id),
		(select history.user_id from public.time_entry_history as history
			where history.organization_id = target_organization_id and history.entry_id = target_entry_id
			order by history.created_at desc, history.id desc
			limit 1)
	) into entry_owner;

	-- The same who-sees-whom rule as Timesheets, and the same answer for a stranger's entry as a missing one.
	if entry_owner is null or not (
		can_team
		or (entry_owner = caller and private.can_see_own_time(target_organization_id, caller))
	) then
		raise exception 'Those hours could not be found.' using errcode = 'P0404';
	end if;

	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'id', history.id,
				'action', history.action,
				'at', history.created_at,
				'actor_name', case when history.actor_id is null then null
					else private.member_display_name(target_organization_id, history.actor_id) end,
				'is_me', history.actor_id = caller,
				'prior', private.describe_time_values(target_organization_id, history.prior_values),
				'new', private.describe_time_values(target_organization_id, history.new_values)
			)
			order by history.created_at, history.id
		),
		'[]'::jsonb
	) into events
	from (
		select *
		from public.time_entry_history as history
		where history.organization_id = target_organization_id and history.entry_id = target_entry_id
		order by history.created_at, history.id
		limit 200
	) as history;

	return jsonb_build_object(
		'entry_id', target_entry_id,
		'timezone', private.organization_timezone(target_organization_id),
		'events', events
	);
end;
$function$;

create or replace function public.timesheet_entries(target_organization_id uuid, target_user_id uuid, range_from date, range_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	caller uuid := (select auth.uid());
	page_size constant integer := 400;
	can_team boolean;
	can_own boolean;
	can_see_own boolean;
	can_write_own boolean;
	jobs_scope text;
	zone text;
	window_start timestamptz;
	window_end timestamptz;
	entries jsonb;
	entry_count integer;
begin
	if caller is null then
		raise exception 'You must be signed in to see Timesheets.' using errcode = 'insufficient_privilege';
	end if;
	can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');
	can_own := private.member_has_permission(target_organization_id, caller, 'time.track_own');
	can_see_own := private.can_see_own_time(target_organization_id, caller);
	-- Someone limited to their own time cannot read a teammate's, and is told the same as for a stranger.
	if not (can_team or (can_see_own and target_user_id = caller)) then
		raise exception 'You do not have access to these hours.' using errcode = 'insufficient_privilege';
	end if;
	if range_from is null or range_to is null or range_to < range_from or range_to - range_from > 6 then
		raise exception 'Choose a day or a week.' using errcode = 'invalid_parameter_value';
	end if;

	-- The same rule the commands apply (private.assert_can_write_time), worked out once for the list.
	can_write_own := can_team or (can_own and target_user_id = caller);
	jobs_scope := private.member_permission_scope(target_organization_id, caller, 'jobs.view');
	zone := private.organization_timezone(target_organization_id);
	window_start := range_from::timestamp at time zone zone;
	window_end := (range_to + 1)::timestamp at time zone zone;

	-- Every hour of theirs is listed, so the totals add up. A Job the reader may not open (a Field member
	-- no longer on it) is named by its number only, without its title or client, and is not a link.
	select
		coalesce(
			jsonb_agg(
				jsonb_build_object(
					'id', listed.entry_id,
					'kind', listed.kind,
					'is_running', listed.is_running,
					'source', listed.source,
					'started_at', listed.started_at,
					'ended_at', listed.ended_at,
					'started_on', (listed.started_at at time zone zone)::date,
					'minutes', listed.minutes,
					'notes', listed.notes,
					'overlaps', listed.overlaps,
					'long_running', listed.is_running and now() - listed.started_at > interval '12 hours',
					'over_a_day', listed.is_running and now() - listed.started_at > interval '24 hours',
					'job', case when listed.job_id is null then null else jsonb_build_object(
						'id', listed.job_id,
						'number', job.job_number,
						'visible', listed.job_visible,
						'closed', job.status <> 'active',
						'title', case when listed.job_visible then job.title end,
						'client_name', case when listed.job_visible then client.display_name end
					) end,
					'visit_id', case when listed.job_visible then listed.visit_id end,
					'visit_date', case when listed.job_visible then visit.visit_date end,
					-- Running timers change only their start and notes, and are never deleted; a closed Job's
					-- hours are its manager's to change.
					'can_edit', can_write_own and (
						listed.job_id is null
						or (listed.job_visible and (can_team or listed.is_running or job.status = 'active'))
					),
					'can_delete', not listed.is_running and can_write_own and (
						listed.job_id is null or (listed.job_visible and (can_team or job.status = 'active'))
					),
					'edited', exists (
						select 1
						from public.time_entry_history as history
						where history.organization_id = target_organization_id
							and history.entry_id = listed.entry_id
							and history.action = 'changed'
					)
				)
				order by listed.started_at, listed.entry_id
			),
			'[]'::jsonb
		),
		count(*)
	into entries, entry_count
	from (
		select hours.*,
			hours.job_id is not null and (
				jobs_scope = 'all'
				or (
					jobs_scope = 'assigned'
					and exists (
						select 1
						from public.job_visit_assignments as assignment
						where assignment.organization_id = target_organization_id
							and assignment.user_id = caller
							and assignment.job_id = hours.job_id
					)
				)
			) as job_visible
		from private.timesheet_rows(target_organization_id, window_start, window_end, target_user_id) as hours
		order by hours.started_at, hours.entry_id
		limit page_size
	) as listed
	left join public.jobs as job
		on job.organization_id = target_organization_id and job.id = listed.job_id
	left join public.clients as client
		on client.organization_id = target_organization_id and client.id = job.client_id
	left join public.job_visits as visit
		on visit.organization_id = target_organization_id and visit.id = listed.visit_id;

	return jsonb_build_object(
		'user_id', target_user_id,
		'from', range_from,
		'to', range_to,
		'timezone', zone,
		'server_now', now(),
		'entries', entries,
		-- A guard against a runaway week, not a page size: a real week is a few dozen entries.
		'truncated', entry_count >= page_size
	);
end;
$function$;

create or replace function public.timesheet_summary(target_organization_id uuid, anchor_date date DEFAULT NULL::date, span text DEFAULT 'week'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	caller uuid := (select auth.uid());
	can_team boolean;
	can_own boolean;
	can_see_own boolean;
	zone text;
	today date;
	range_from date;
	range_to date;
	window_start timestamptz;
	window_end timestamptz;
	people jsonb;
begin
	if caller is null then
		raise exception 'You must be signed in to see Timesheets.' using errcode = 'insufficient_privilege';
	end if;
	can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');
	can_own := private.member_has_permission(target_organization_id, caller, 'time.track_own');
	can_see_own := private.can_see_own_time(target_organization_id, caller);
	if not (can_team or can_see_own) then
		raise exception 'You do not have access to Timesheets.' using errcode = 'insufficient_privilege';
	end if;
	if span is null or span not in ('day', 'week') then
		raise exception 'Choose a day or a week.' using errcode = 'invalid_parameter_value';
	end if;

	-- The window is the business's own day or week, so the page needs no time zone of its own to ask for
	-- "today". The week starts on Sunday, as the Schedule's does (plan § Timesheets page).
	zone := private.organization_timezone(target_organization_id);
	today := (now() at time zone zone)::date;
	range_from := coalesce(anchor_date, today);
	if span = 'week' then
		range_from := range_from - extract(dow from range_from)::integer;
	end if;
	range_to := case when span = 'week' then range_from + 6 else range_from end;
	window_start := range_from::timestamp at time zone zone;
	window_end := (range_to + 1)::timestamp at time zone zone;

	-- Who sees whom (plan § Timesheets page): someone limited to their own time sees only themselves.
	with visible as (
		select *
		from private.timesheet_rows(
			target_organization_id, window_start, window_end, case when can_team then null else caller end
		)
	),
	per_day as (
		select visible.user_id, (visible.started_at at time zone zone)::date as day, sum(visible.minutes) as minutes
		from visible
		where not visible.is_running
		group by visible.user_id, (visible.started_at at time zone zone)::date
	),
	per_person as (
		select visible.user_id,
			count(*) filter (where not visible.is_running) as entry_count,
			coalesce(sum(visible.minutes) filter (where not visible.is_running), 0) as total_minutes,
			count(*) filter (where visible.overlaps) as overlap_count
		from visible
		group by visible.user_id
	),
	-- Everyone working here now who may time their work, and anyone else with hours in this window or a
	-- timer still running: a member who has left still appears for weeks they worked (plan § Timesheets
	-- page), and someone who cannot time their own work appears only when a manager recorded hours for them.
	roster as (
		select member.user_id, member.status, member.display_name_at_removal
		from public.organization_members as member
		where member.organization_id = target_organization_id
			and (can_team or member.user_id = caller)
			and (
				(member.status = 'active' and private.can_run_own_timer(target_organization_id, member.user_id))
				or exists (select 1 from per_person where per_person.user_id = member.user_id)
				or exists (
					select 1
					from public.running_timers as timer
					where timer.organization_id = target_organization_id and timer.user_id = member.user_id
				)
			)
	)
	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'user_id', roster.user_id,
				'name', coalesce(
					case when roster.status = 'removed' then roster.display_name_at_removal end,
					nullif(btrim(profile.full_name), ''),
					roster.display_name_at_removal,
					account.email
				),
				'avatar_url', case when roster.status <> 'removed' then profile.avatar_url end,
				'status', roster.status,
				'is_me', roster.user_id = caller,
				'days', coalesce(
					(
						select jsonb_object_agg(per_day.day::text, per_day.minutes)
						from per_day
						where per_day.user_id = roster.user_id
					),
					'{}'::jsonb
				),
				'total_minutes', coalesce(per_person.total_minutes, 0),
				'entry_count', coalesce(per_person.entry_count, 0),
				'overlap_count', coalesce(per_person.overlap_count, 0),
				-- What they are on the clock for right now, whatever day it started.
				'running', (
					select jsonb_build_object(
						'id', timer.id,
						'kind', timer.kind,
						'job_id', timer.job_id,
						'job_number', job.job_number,
						'started_at', timer.started_at,
						'started_on', (timer.started_at at time zone zone)::date,
						'long_running', now() - timer.started_at > interval '12 hours',
						'over_a_day', now() - timer.started_at > interval '24 hours',
						-- Clocked in for the day: the day clock runs, or a visit timer will resume it.
						'clocked_in', timer.kind = 'general' or timer.resume_general
					)
					from public.running_timers as timer
					left join public.jobs as job
						on job.organization_id = timer.organization_id and job.id = timer.job_id
					where timer.organization_id = target_organization_id and timer.user_id = roster.user_id
				)
			)
			order by roster.status = 'active' desc,
				lower(coalesce(
					case when roster.status = 'removed' then roster.display_name_at_removal end,
					nullif(btrim(profile.full_name), ''),
					roster.display_name_at_removal,
					account.email,
					''
				)),
				roster.user_id
		),
		'[]'::jsonb
	) into people
	from roster
	left join per_person on per_person.user_id = roster.user_id
	left join public.profiles as profile on profile.id = roster.user_id
	left join auth.users as account on account.id = roster.user_id;

	return jsonb_build_object(
		'span', span,
		'from', range_from,
		'to', range_to,
		'timezone', zone,
		'today', today,
		'server_now', now(),
		'can_view_team', can_team,
		-- Add entry: for anyone with time.track_team, for themselves with time.track_own.
		'can_add', can_team or can_own,
		'people', people
	);
end;
$function$;

comment on function public.job_labor(uuid, uuid) is
	'One job''s recorded hours and their totals, newest first. A reader with time.track_team sees everyone''s; a reader with time.track_own or time.timers_own sees their own, and only time.track_own may add or change them. Rates and costs need jobs.view_cost; without it the same rows come back with hours and no money at all.';

comment on function public.time_entry_history(uuid, uuid) is
	'An entry''s edit history, oldest first: who added, stopped, changed or deleted it, when, and the values before and after, with names and Job numbers. time.track_team reads anyone''s; time.track_own or time.timers_own only the caller''s own entries.';

comment on function public.timesheet_entries(uuid, uuid, date, date) is
	'One person''s Timesheets entries for a day or a week, oldest first, with running timers (no end, under the timer''s id), overlap flags, whether each was edited, and whether the reader may change or delete it. time.track_team reads anyone''s; time.track_own or time.timers_own only the caller''s, and only time.track_own may change them. A Job the reader cannot open shows its number only. At most 400 entries, flagged truncated.';

comment on function public.timesheet_summary(uuid, date, text) is
	'Timesheets for the business-time-zone day (span day) or Sunday-to-Saturday week (span week) holding anchor_date, today when null: one row per person with minutes per day, entry and overlap counts, and their running timer (with whether they are clocked in). time.track_team sees every active member who can_run_own_timer plus anyone with hours in the window or a running timer; time.track_own or time.timers_own sees only themselves, and can_add needs time.track_own. Running timers are not in the totals: hours count once they stop.';
