-- Time clock Part 7: weekly approval (plan § Weekly approval, docs/time-clock-behavior-contract.md).
--
-- A manager approves every stopped entry up to and including a chosen day, for the people they choose, as
-- Jobber's Approve Timesheets does. Approved entries are locked for people limited to their own time;
-- whoever manages the team's time (time.track_team) can still change them, the entry stays approved, and the
-- change is in its history. There is no undo (plan § Not doing).
--
-- 1. job_time_entries and general_time_entries get approved_at and approved_by. A running timer is never
--    approved: it has no row in either table until it stops.
-- 2. time_entry_history gains the 'approved' action, one row per entry approved.
-- 3. private.change_time_entry and private.remove_time_entry, the only writers that change or remove
--    recorded hours, refuse approved hours to anyone without time.track_team (P0410). Timesheets and the
--    Job's Labor section both go through them, so the lock holds wherever the entry is shown. Moving an entry
--    between a Job and General keeps its approval.
-- 4. timesheet_approval reads what is waiting: each person's unapproved hours up to the day, and the timers
--    still running. approve_time_entries approves.
-- 5. The Timesheets reads and job_labor say which entries are approved, and stop offering own-only readers
--    an Edit or Delete on them.

-- ---------------------------------------------------------------------------------------------------
-- Approval on each entry
-- ---------------------------------------------------------------------------------------------------

alter table public.job_time_entries
	add column approved_at timestamptz,
	add column approved_by uuid references auth.users (id) on delete set null;

alter table public.general_time_entries
	add column approved_at timestamptz,
	add column approved_by uuid references auth.users (id) on delete set null;

comment on column public.job_time_entries.approved_at is
	'When a manager approved these hours (plan § Weekly approval). Null until then. Approved hours are locked for people limited to their own time.';
comment on column public.job_time_entries.approved_by is 'Who approved these hours.';
comment on column public.general_time_entries.approved_at is
	'When a manager approved these hours (plan § Weekly approval). Null until then. Approved hours are locked for people limited to their own time.';
comment on column public.general_time_entries.approved_by is 'Who approved these hours.';

-- What is waiting for approval is found by person and day among the unapproved rows only, which stay few as
-- the approved history grows.
create index job_time_entries_unapproved_idx
	on public.job_time_entries (organization_id, user_id, started_at)
	where approved_at is null;

create index general_time_entries_unapproved_idx
	on public.general_time_entries (organization_id, user_id, started_at)
	where approved_at is null;

alter table public.time_entry_history drop constraint time_entry_history_action_check;
alter table public.time_entry_history
	add constraint time_entry_history_action_check
	check (action in ('added', 'stopped', 'changed', 'deleted', 'approved'));

-- ---------------------------------------------------------------------------------------------------
-- The lock
-- ---------------------------------------------------------------------------------------------------

create or replace function private.assert_approval_allows_change(
	target_organization_id uuid,
	actor_id uuid,
	entry_approved_at timestamptz
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
	if entry_approved_at is not null
		and not private.member_has_permission(target_organization_id, actor_id, 'time.track_team') then
		raise exception 'These hours are approved. Ask a manager to change them.' using errcode = 'P0410';
	end if;
end;
$$;

comment on function private.assert_approval_allows_change(uuid, uuid, timestamptz) is
	'Refuses changing or removing approved hours (P0410) to anyone without time.track_team (plan § Weekly approval). Unapproved hours pass.';

revoke all on function private.assert_approval_allows_change(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function private.assert_approval_allows_change(uuid, uuid, timestamptz) to service_role;

-- The two writers of recorded hours, unchanged except for the lock and for carrying approval across a move.

CREATE OR REPLACE FUNCTION private.change_time_entry(target_organization_id uuid, target_entry_id uuid, actor_id uuid, new_user_id uuid, new_job_id uuid, new_visit_id uuid, new_started_at timestamp with time zone, new_minutes integer, new_notes text, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	job_entry public.job_time_entries;
	general_entry public.general_time_entries;
	old_kind text;
	old_user uuid;
	old_job uuid;
	old_visit uuid;
	old_started timestamptz;
	old_minutes integer;
	old_notes text;
	old_source text;
	old_approved_at timestamptz;
	old_approved_by uuid;
	old_closed boolean := false;
	new_closed boolean := false;
	clean_notes text := nullif(trim(coalesce(new_notes, '')), '');
	clean_reason text := nullif(trim(coalesce(reason, '')), '');
	new_rate bigint;
	updated public.job_time_entries;
	prior jsonb;
	next jsonb;
begin
	-- The entry is locked, not its Job: two corrections to the same entry queue, and corrections to
	-- different entries never wait for each other.
	select entry.* into job_entry
	from public.job_time_entries as entry
	where entry.organization_id = target_organization_id and entry.id = target_entry_id
	for update;
	if found then
		old_kind := 'job';
		old_user := job_entry.user_id;
		old_job := job_entry.job_id;
		old_visit := job_entry.visit_id;
		old_started := job_entry.started_at;
		old_minutes := job_entry.minutes;
		old_notes := job_entry.notes;
		old_source := job_entry.source;
		old_approved_at := job_entry.approved_at;
		old_approved_by := job_entry.approved_by;
		select job.status <> 'active' into old_closed
		from public.jobs as job
		where job.organization_id = target_organization_id and job.id = old_job;
	else
		select entry.* into general_entry
		from public.general_time_entries as entry
		where entry.organization_id = target_organization_id and entry.id = target_entry_id
		for update;
		if not found then
			if exists (
				select 1 from public.running_timers as timer
				where timer.organization_id = target_organization_id and timer.id = target_entry_id
			) then
				raise exception 'This timer is still running. Only its start time and notes can be changed.'
					using errcode = 'P0410';
			end if;
			raise exception 'Those hours could not be found.' using errcode = 'P0404';
		end if;
		old_kind := 'general';
		old_user := general_entry.user_id;
		old_started := general_entry.started_at;
		old_minutes := general_entry.minutes;
		old_notes := general_entry.notes;
		old_source := general_entry.source;
		old_approved_at := general_entry.approved_at;
		old_approved_by := general_entry.approved_by;
	end if;

	-- Allowed to change the hours as they are, and to make them what they become.
	perform private.assert_can_write_time(target_organization_id, actor_id, old_user, old_job);
	perform private.assert_approval_allows_change(target_organization_id, actor_id, old_approved_at);
	perform private.assert_can_write_time(target_organization_id, actor_id, new_user_id, new_job_id);
	if new_user_id is distinct from old_user then
		perform private.assert_team_member(target_organization_id, new_user_id);
	end if;
	if new_job_id is null and new_visit_id is not null then
		raise exception 'General time has no visit.' using errcode = 'invalid_parameter_value';
	end if;
	if new_visit_id is not null and not exists (
		select 1
		from public.job_visits as visit
		where visit.organization_id = target_organization_id
			and visit.job_id = new_job_id
			and visit.id = new_visit_id
	) then
		raise exception 'That visit could not be found on this job.' using errcode = 'P0404';
	end if;
	if new_job_id is not null then
		select job.status <> 'active' into new_closed
		from public.jobs as job
		where job.organization_id = target_organization_id and job.id = new_job_id;
	end if;

	prior := private.time_entry_values(old_kind, old_user, old_job, old_visit, old_started, old_minutes, old_notes);
	next := private.time_entry_values(
		case when new_job_id is null then 'general' else 'job' end,
		new_user_id, new_job_id, new_visit_id, new_started_at, new_minutes, clean_notes
	);
	if prior = next then
		return jsonb_build_object('id', target_entry_id, 'changed', false, 'after_close', old_closed or new_closed);
	end if;

	if old_kind = 'job' and new_job_id is not null then
		-- The rate stays as recorded while the hours stay the same person's. Hours moved to someone else
		-- cost what that person costs, today's rate, as if recorded for them now.
		new_rate := job_entry.cost_per_hour_minor;
		if new_user_id <> old_user then
			select profile.cost_per_hour_minor into new_rate
			from public.organization_member_cost_profiles as profile
			where profile.organization_id = target_organization_id and profile.user_id = new_user_id;
		end if;

		update public.job_time_entries as entry
		set user_id = new_user_id,
			job_id = new_job_id,
			visit_id = new_visit_id,
			started_at = new_started_at,
			minutes = new_minutes,
			notes = clean_notes,
			cost_per_hour_minor = new_rate
		where entry.organization_id = target_organization_id and entry.id = target_entry_id
		returning * into updated;

		if new_job_id = old_job then
			insert into public.job_costing_events (
				organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
				reason, prior_values, new_values
			)
			values (
				target_organization_id, old_job, 'time_entry_updated', 'time_entry', target_entry_id, actor_id,
				old_closed, clean_reason,
				jsonb_build_object(
					'user_id', job_entry.user_id, 'visit_id', job_entry.visit_id, 'started_at', job_entry.started_at,
					'minutes', job_entry.minutes, 'cost_per_hour_minor', job_entry.cost_per_hour_minor,
					'cost_total_minor', job_entry.cost_total_minor
				),
				jsonb_build_object(
					'user_id', updated.user_id, 'visit_id', updated.visit_id, 'started_at', updated.started_at,
					'minutes', updated.minutes, 'cost_per_hour_minor', updated.cost_per_hour_minor,
					'cost_total_minor', updated.cost_total_minor
				)
			);
		else
			-- Hours moved between Jobs leave one Job's costing and join the other's, each recorded there.
			insert into public.job_costing_events (
				organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
				reason, prior_values, new_values
			)
			values
				(
					target_organization_id, old_job, 'time_entry_deleted', 'time_entry', target_entry_id, actor_id,
					old_closed, clean_reason,
					jsonb_build_object(
						'user_id', job_entry.user_id, 'visit_id', job_entry.visit_id,
						'started_at', job_entry.started_at, 'minutes', job_entry.minutes,
						'cost_per_hour_minor', job_entry.cost_per_hour_minor,
						'cost_total_minor', job_entry.cost_total_minor
					),
					null
				),
				(
					target_organization_id, new_job_id, 'time_entry_added', 'time_entry', target_entry_id, actor_id,
					new_closed, clean_reason, null,
					jsonb_build_object(
						'user_id', updated.user_id, 'visit_id', updated.visit_id, 'started_at', updated.started_at,
						'minutes', updated.minutes, 'cost_per_hour_minor', updated.cost_per_hour_minor,
						'cost_total_minor', updated.cost_total_minor, 'source', updated.source
					)
				);
		end if;
	elsif old_kind = 'general' and new_job_id is null then
		update public.general_time_entries as entry
		set user_id = new_user_id,
			started_at = new_started_at,
			minutes = new_minutes,
			notes = clean_notes
		where entry.organization_id = target_organization_id and entry.id = target_entry_id;
	elsif old_kind = 'job' then
		-- From a Job to General: the hours leave the Job's costing and keep their id and how they were made.
		insert into public.job_costing_events (
			organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
			reason, prior_values
		)
		values (
			target_organization_id, old_job, 'time_entry_deleted', 'time_entry', target_entry_id, actor_id,
			old_closed, clean_reason,
			jsonb_build_object(
				'user_id', job_entry.user_id, 'visit_id', job_entry.visit_id, 'started_at', job_entry.started_at,
				'minutes', job_entry.minutes, 'cost_per_hour_minor', job_entry.cost_per_hour_minor,
				'cost_total_minor', job_entry.cost_total_minor
			)
		);
		delete from public.job_time_entries as entry
		where entry.organization_id = target_organization_id and entry.id = target_entry_id;
		insert into public.general_time_entries (
			id, organization_id, user_id, started_at, minutes, notes, source, created_by, created_at,
			approved_at, approved_by
		)
		values (
			target_entry_id, target_organization_id, new_user_id, new_started_at, new_minutes, clean_notes,
			old_source, job_entry.created_by, job_entry.created_at, old_approved_at, old_approved_by
		);
	else
		-- From General to a Job: the hours join that Job's costing at the person's current rate.
		delete from public.general_time_entries as entry
		where entry.organization_id = target_organization_id and entry.id = target_entry_id;
		perform private.record_job_time_entry(
			target_organization_id, new_job_id, new_visit_id, new_user_id, new_started_at, new_minutes,
			clean_notes, old_source, actor_id, new_closed, target_entry_id
		);
		-- Approved hours stay approved wherever they are moved.
		update public.job_time_entries as entry
		set approved_at = old_approved_at, approved_by = old_approved_by
		where entry.organization_id = target_organization_id and entry.id = target_entry_id
			and old_approved_at is not null;
	end if;

	perform private.write_time_history(
		target_organization_id, target_entry_id, new_user_id, 'changed', actor_id, prior, next
	);

	return jsonb_build_object('id', target_entry_id, 'changed', true, 'after_close', old_closed or new_closed);
end;
$function$;

CREATE OR REPLACE FUNCTION private.remove_time_entry(target_organization_id uuid, target_entry_id uuid, actor_id uuid, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	job_entry public.job_time_entries;
	general_entry public.general_time_entries;
	job_closed boolean := false;
begin
	select entry.* into job_entry
	from public.job_time_entries as entry
	where entry.organization_id = target_organization_id and entry.id = target_entry_id
	for update;
	if found then
		perform private.assert_can_write_time(target_organization_id, actor_id, job_entry.user_id, job_entry.job_id);
		perform private.assert_approval_allows_change(target_organization_id, actor_id, job_entry.approved_at);
		select job.status <> 'active' into job_closed
		from public.jobs as job
		where job.organization_id = target_organization_id and job.id = job_entry.job_id;

		-- The costing trail keeps the whole row, so deleting an entry never deletes the evidence it existed.
		insert into public.job_costing_events (
			organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
			reason, prior_values
		)
		values (
			target_organization_id, job_entry.job_id, 'time_entry_deleted', 'time_entry', target_entry_id, actor_id,
			job_closed, nullif(trim(coalesce(reason, '')), ''),
			jsonb_build_object(
				'user_id', job_entry.user_id, 'visit_id', job_entry.visit_id, 'started_at', job_entry.started_at,
				'minutes', job_entry.minutes, 'cost_per_hour_minor', job_entry.cost_per_hour_minor,
				'cost_total_minor', job_entry.cost_total_minor
			)
		);
		delete from public.job_time_entries as entry
		where entry.organization_id = target_organization_id and entry.id = target_entry_id;

		perform private.write_time_history(
			target_organization_id, target_entry_id, job_entry.user_id, 'deleted', actor_id,
			private.time_entry_values(
				'job', job_entry.user_id, job_entry.job_id, job_entry.visit_id, job_entry.started_at,
				job_entry.minutes, job_entry.notes
			),
			null
		);
		return jsonb_build_object('id', target_entry_id, 'after_close', job_closed);
	end if;

	select entry.* into general_entry
	from public.general_time_entries as entry
	where entry.organization_id = target_organization_id and entry.id = target_entry_id
	for update;
	if not found then
		if exists (
			select 1 from public.running_timers as timer
			where timer.organization_id = target_organization_id and timer.id = target_entry_id
		) then
			raise exception 'A running timer cannot be deleted. Stop it first.' using errcode = 'P0410';
		end if;
		raise exception 'Those hours could not be found.' using errcode = 'P0404';
	end if;

	perform private.assert_can_write_time(target_organization_id, actor_id, general_entry.user_id, null);
	perform private.assert_approval_allows_change(target_organization_id, actor_id, general_entry.approved_at);
	delete from public.general_time_entries as entry
	where entry.organization_id = target_organization_id and entry.id = target_entry_id;

	perform private.write_time_history(
		target_organization_id, target_entry_id, general_entry.user_id, 'deleted', actor_id,
		private.time_entry_values(
			'general', general_entry.user_id, null, null, general_entry.started_at, general_entry.minutes,
			general_entry.notes
		),
		null
	);
	return jsonb_build_object('id', target_entry_id, 'after_close', false);
end;
$function$;

-- ---------------------------------------------------------------------------------------------------
-- The reads say which hours are approved
-- ---------------------------------------------------------------------------------------------------

-- Its columns change, so it is replaced rather than redefined. Nothing depends on it but the two plpgsql
-- reads below, which look it up when they run.
drop function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid);

CREATE OR REPLACE FUNCTION private.timesheet_rows(target_organization_id uuid, window_start timestamp with time zone, window_end timestamp with time zone, only_user_id uuid)
 RETURNS TABLE(user_id uuid, kind text, entry_id uuid, job_id uuid, visit_id uuid, started_at timestamp with time zone, ended_at timestamp with time zone, minutes integer, notes text, source text, is_running boolean, approved boolean, "overlaps" boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
	with hours as (
		-- A day either side of the window, so an entry is still compared with one that started the evening
		-- before or runs into the morning after. No entry is longer than a day.
		select entry.user_id, 'job'::text as kind, entry.id as entry_id, entry.job_id, entry.visit_id,
			entry.started_at, entry.started_at + make_interval(mins => entry.minutes) as ended_at, entry.minutes,
			entry.notes, entry.source, false as is_running, entry.approved_at is not null as approved
		from public.job_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.started_at >= window_start - interval '1 day'
			and entry.started_at < window_end + interval '1 day'
			and (only_user_id is null or entry.user_id = only_user_id)
		union all
		select entry.user_id, 'general', entry.id, null, null,
			entry.started_at, entry.started_at + make_interval(mins => entry.minutes), entry.minutes,
			entry.notes, entry.source, false, entry.approved_at is not null
		from public.general_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.started_at >= window_start - interval '1 day'
			and entry.started_at < window_end + interval '1 day'
			and (only_user_id is null or entry.user_id = only_user_id)
		union all
		-- A running timer covers everything from its start until now, however long ago it started: a timer
		-- forgotten for days really does overlap whatever was typed in since.
		select timer.user_id, case when timer.kind = 'visit' then 'job' else 'general' end, timer.id,
			timer.job_id, timer.visit_id, timer.started_at, null, null, timer.notes, 'timer', true, false
		from public.running_timers as timer
		where timer.organization_id = target_organization_id
			and timer.started_at < window_end + interval '1 day'
			and (only_user_id is null or timer.user_id = only_user_id)
	),
	ordered as (
		select hours.*,
			max(coalesce(hours.ended_at, now())) over (
				partition by hours.user_id
				order by hours.started_at, hours.entry_id
				rows between unbounded preceding and 1 preceding
			) as latest_earlier_end,
			lead(hours.started_at) over (
				partition by hours.user_id
				order by hours.started_at, hours.entry_id
			) as next_start
		from hours
	)
	-- Stopped hours are rounded to the minute, so two timers that follow each other can share a few seconds.
	-- Only a shared minute or more counts as an overlap.
	select ordered.user_id, ordered.kind, ordered.entry_id, ordered.job_id, ordered.visit_id,
		ordered.started_at, ordered.ended_at, ordered.minutes, ordered.notes, ordered.source,
		ordered.is_running, ordered.approved,
		coalesce(ordered.latest_earlier_end - ordered.started_at >= interval '1 minute', false)
			or coalesce(coalesce(ordered.ended_at, now()) - ordered.next_start >= interval '1 minute', false)
	from ordered
	where ordered.started_at >= window_start and ordered.started_at < window_end;
$function$;

revoke all on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;
grant execute on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) to service_role;

CREATE OR REPLACE FUNCTION public.timesheet_entries(target_organization_id uuid, target_user_id uuid, range_from date, range_to date)
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
					'approved', listed.approved,
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
					-- Approved hours are locked for people limited to their own time (plan § Weekly approval).
					'can_edit', can_write_own and (can_team or not listed.approved) and (
						listed.job_id is null
						or (listed.job_visible and (can_team or listed.is_running or job.status = 'active'))
					),
					'can_delete', not listed.is_running and can_write_own and (can_team or not listed.approved) and (
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

CREATE OR REPLACE FUNCTION public.timesheet_summary(target_organization_id uuid, anchor_date date DEFAULT NULL::date, span text DEFAULT 'week'::text)
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
			count(*) filter (where not visible.is_running and not visible.approved) as unapproved_count,
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
				'unapproved_count', coalesce(per_person.unapproved_count, 0),
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
		-- Approve: only someone who manages the team's time.
		'can_approve', can_team,
		'people', people
	);
end;
$function$;

CREATE OR REPLACE FUNCTION public.job_labor(target_organization_id uuid, target_job_id uuid)
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
					'approved', visible.approved_at is not null,
					-- Approved hours are the manager's to change, here as on Timesheets.
					'can_edit', can_team or (
						visible.user_id = caller and can_own and not job_closed and visible.approved_at is null
					),
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
					 entry.source, entry.cost_per_hour_minor, entry.cost_total_minor, entry.approved_at,
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

-- ---------------------------------------------------------------------------------------------------
-- Approving
-- ---------------------------------------------------------------------------------------------------

-- Who may approve, and the day as the business's own: the same checks for the read and the command.
create or replace function private.approval_boundary(
	target_organization_id uuid,
	actor_id uuid,
	cutoff date,
	out zone text,
	out today date,
	out boundary timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
	if actor_id is null then
		raise exception 'You must be signed in to approve hours.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_has_permission(target_organization_id, actor_id, 'time.track_team') then
		raise exception 'Only someone who manages the team''s time can approve hours.'
			using errcode = 'insufficient_privilege';
	end if;

	zone := private.organization_timezone(target_organization_id);
	today := (now() at time zone zone)::date;
	if cutoff is null then
		raise exception 'Choose the day to approve up to.' using errcode = 'invalid_parameter_value';
	end if;
	if cutoff > today then
		raise exception 'Choose today or an earlier day.' using errcode = 'invalid_parameter_value';
	end if;
	-- Up to and including the day: everything that started before the next midnight there.
	boundary := (cutoff + 1)::timestamp at time zone zone;
end;
$$;

revoke all on function private.approval_boundary(uuid, uuid, date) from public, anon, authenticated;
grant execute on function private.approval_boundary(uuid, uuid, date) to service_role;

-- The timers still running among these people that started on or before the day: never approved, listed so
-- they can be stopped first.
create or replace function private.running_before(
	target_organization_id uuid,
	zone text,
	boundary timestamptz,
	only_user_ids uuid[]
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'user_id', timer.user_id,
				'name', private.member_display_name(target_organization_id, timer.user_id),
				'kind', timer.kind,
				'job_number', job.job_number,
				'started_at', timer.started_at,
				'started_on', (timer.started_at at time zone zone)::date,
				'over_a_day', now() - timer.started_at > interval '24 hours'
			)
			order by timer.started_at, timer.user_id
		),
		'[]'::jsonb
	)
	from public.running_timers as timer
	left join public.jobs as job on job.organization_id = timer.organization_id and job.id = timer.job_id
	where timer.organization_id = target_organization_id
		and timer.started_at < boundary
		and (only_user_ids is null or timer.user_id = any (only_user_ids));
$$;

revoke all on function private.running_before(uuid, text, timestamptz, uuid[]) from public, anon, authenticated;
grant execute on function private.running_before(uuid, text, timestamptz, uuid[]) to service_role;

create or replace function public.timesheet_approval(target_organization_id uuid, cutoff date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	bounds record;
	people jsonb;
begin
	select * into bounds from private.approval_boundary(target_organization_id, caller, cutoff);

	with waiting as (
		select entry.user_id, entry.minutes, entry.started_at
		from public.job_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.approved_at is null
			and entry.started_at < bounds.boundary
		union all
		select entry.user_id, entry.minutes, entry.started_at
		from public.general_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.approved_at is null
			and entry.started_at < bounds.boundary
	),
	per_person as (
		select waiting.user_id,
			count(*) as entry_count,
			sum(waiting.minutes) as minutes,
			min(waiting.started_at) as first_at
		from waiting
		group by waiting.user_id
	),
	named as (
		select per_person.*,
			private.member_display_name(target_organization_id, per_person.user_id) as name,
			member.status
		from per_person
		left join public.organization_members as member
			on member.organization_id = target_organization_id and member.user_id = per_person.user_id
	)
	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'user_id', named.user_id,
				'name', named.name,
				'status', named.status,
				'is_me', named.user_id = caller,
				'entry_count', named.entry_count,
				'minutes', named.minutes,
				'first_day', (named.first_at at time zone bounds.zone)::date
			)
			order by lower(coalesce(named.name, '')), named.user_id
		),
		'[]'::jsonb
	) into people
	from named;

	return jsonb_build_object(
		'cutoff', cutoff,
		'today', bounds.today,
		'timezone', bounds.zone,
		'people', people,
		'running', private.running_before(target_organization_id, bounds.zone, bounds.boundary, null)
	);
end;
$$;

comment on function public.timesheet_approval(uuid, date) is
	'What approving up to and including cutoff (a business-time-zone day, not after today) would cover: one row per person with unapproved stopped hours that started on or before it (count, minutes, first day), and the timers still running that started by then. Needs time.track_team.';

revoke all on function public.timesheet_approval(uuid, date) from public, anon;
grant execute on function public.timesheet_approval(uuid, date) to authenticated, service_role;

create or replace function public.approve_time_entries(
	target_organization_id uuid,
	cutoff date,
	target_user_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	bounds record;
	approved_count integer;
	approved_minutes bigint;
	people_count integer;
begin
	select * into bounds from private.approval_boundary(target_organization_id, caller, cutoff);
	if target_user_ids is null or cardinality(target_user_ids) = 0 then
		raise exception 'Choose who to approve.' using errcode = 'invalid_parameter_value';
	end if;
	if cardinality(target_user_ids) > 500 then
		raise exception 'Choose fewer people.' using errcode = 'invalid_parameter_value';
	end if;

	-- Only what is still unapproved. A second manager approving at the same moment waits on the same rows,
	-- then finds them approved and leaves them, so each entry is approved, and logged, once.
	with approved_job as (
		update public.job_time_entries as entry
		set approved_at = now(), approved_by = caller
		where entry.organization_id = target_organization_id
			and entry.user_id = any (target_user_ids)
			and entry.approved_at is null
			and entry.started_at < bounds.boundary
		returning entry.id, entry.user_id, entry.minutes
	),
	approved_general as (
		update public.general_time_entries as entry
		set approved_at = now(), approved_by = caller
		where entry.organization_id = target_organization_id
			and entry.user_id = any (target_user_ids)
			and entry.approved_at is null
			and entry.started_at < bounds.boundary
		returning entry.id, entry.user_id, entry.minutes
	),
	approved as (
		select * from approved_job
		union all
		select * from approved_general
	),
	logged as (
		insert into public.time_entry_history (organization_id, entry_id, user_id, action, actor_id)
		select target_organization_id, approved.id, approved.user_id, 'approved', caller
		from approved
	)
	select count(*), coalesce(sum(approved.minutes), 0), count(distinct approved.user_id)
	into approved_count, approved_minutes, people_count
	from approved;

	return jsonb_build_object(
		'cutoff', cutoff,
		'approved_count', approved_count,
		'approved_minutes', approved_minutes,
		'people_count', people_count,
		'running', private.running_before(target_organization_id, bounds.zone, bounds.boundary, target_user_ids)
	);
end;
$$;

comment on function public.approve_time_entries(uuid, date, uuid[]) is
	'Approves every unapproved stopped entry of the chosen people that started on or before cutoff (a business-time-zone day, not after today), writing one "approved" history row per entry. Running timers are never approved; those that started by then are returned so they can be stopped first. Needs time.track_team. No undo.';

revoke all on function public.approve_time_entries(uuid, date, uuid[]) from public, anon;
grant execute on function public.approve_time_entries(uuid, date, uuid[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- Comments for the commands and reads that changed
-- ---------------------------------------------------------------------------------------------------

comment on function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text) is
	'Corrects recorded hours: person, Job (null for General), visit, start, minutes and notes. Checks the actor may change the hours as they are and as they become, and that approved hours are changed only with time.track_team; a running timer is refused (P0410). Moving between a Job and General moves the row under the same id, approval included; costing history is written on each Job touched; a different person is re-priced at their current rate. Writes one "changed" history row, or nothing when nothing changed.';

comment on function private.remove_time_entry(uuid, uuid, uuid, text) is
	'Removes recorded Job or General hours after checking the actor may change them, and that approved hours are removed only with time.track_team. Job hours are written whole to the costing trail first; every removal gets a "deleted" history row. A running timer is refused (P0410).';

comment on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) is
	'Every hour in a window for Timesheets: Job hours, General hours and running timers (is_running, no end, listed under the timer''s id), whether each is approved, and each flagged when it shares a minute or more with another of the same person''s. Checks nothing; callers decide whose rows may be read.';

comment on function public.job_labor(uuid, uuid) is
	'One job''s recorded hours and their totals, newest first, each saying whether it is approved. A reader with time.track_team sees and changes everyone''s; a reader with time.track_own or time.timers_own sees their own, and only time.track_own may add or change them, while the job is open and the hours are not approved. Rates and costs need jobs.view_cost; without it the same rows come back with hours and no money at all.';

comment on function public.timesheet_entries(uuid, uuid, date, date) is
	'One person''s Timesheets entries for a day or a week, oldest first, with running timers (no end, under the timer''s id), overlap flags, whether each was edited or approved, and whether the reader may change or delete it. time.track_team reads and changes anyone''s, approved or not; time.track_own or time.timers_own only the caller''s, and only time.track_own may change them while unapproved. A Job the reader cannot open shows its number only. At most 400 entries, flagged truncated.';

comment on function public.timesheet_summary(uuid, date, text) is
	'Timesheets for the business-time-zone day (span day) or Sunday-to-Saturday week (span week) holding anchor_date, today when null: one row per person with minutes per day, entry, unapproved and overlap counts, and their running timer (with whether they are clocked in). time.track_team sees every active member who can_run_own_timer plus anyone with hours in the window or a running timer, and may approve; time.track_own or time.timers_own sees only themselves, and can_add needs time.track_own. Running timers are not in the totals: hours count once they stop.';
