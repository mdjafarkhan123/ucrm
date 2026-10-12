-- Time clock Part 8: Assessment timers (plan § Assessment timers, docs/time-clock-behavior-contract.md).
--
-- On an Assessment scheduled for today, a person taps Start and Stop, like a visit timer. The time appears on
-- Timesheets against the Assessment's Request, pauses the day clock like a visit timer, and has no Job cost.
--
-- 1. Assessment time is time on no Job, so it is kept in general_time_entries with the Request it was for
--    (request_id). Approval, corrections, edit history and the Timesheets totals already cover that table,
--    and it never reaches Job costing or the accountant report. A Request deleted later leaves the hours as
--    General time rather than losing paid hours.
-- 2. running_timers gains kind 'assessment', carrying the Assessment and its Request. Like a visit timer it
--    pauses a running day clock (resume_general) and starts it again when it stops.
-- 3. start_assessment_timer starts the caller's own timer, only on an Assessment they can see, scheduled for
--    the business's today and not yet complete (Jobber allows Assessment timers on the current date only).
--    The checks shared with start_visit_timer (one timer at a time, pausing the day clock, a repeated Start)
--    move into private.start_own_timer.
-- 4. Completing an Assessment stops every timer running on it, as completing a visit does (plan § Timers).
-- 5. The reads and the correction commands say "assessment" for these hours and keep their Request: an
--    Assessment entry can be corrected, moved to General or to a Job, but not moved to another Assessment.

-- ---------------------------------------------------------------------------------------------------
-- Assessment hours: time on no Job, kept with their Request
-- ---------------------------------------------------------------------------------------------------

alter table public.general_time_entries
	add column request_id uuid,
	add constraint general_time_entries_request_fk foreign key (organization_id, request_id)
		references public.requests (organization_id, id) on delete set null (request_id);

comment on column public.general_time_entries.request_id is
	'Set for Assessment time: the Request whose on-site assessment the hours were for. Null for General time. Cleared if the Request is deleted, leaving the hours as General.';

create index general_time_entries_request_idx
	on public.general_time_entries (organization_id, request_id)
	where request_id is not null;

-- ---------------------------------------------------------------------------------------------------
-- The running timer can be an Assessment's
-- ---------------------------------------------------------------------------------------------------

alter table public.running_timers
	drop constraint running_timers_kind_check,
	drop constraint running_timers_kind_shape;

alter table public.running_timers
	add column assessment_id uuid references public.assessments (id) on delete set null,
	add column request_id uuid,
	add constraint running_timers_request_fk foreign key (organization_id, request_id)
		references public.requests (organization_id, id) on delete set null (request_id),
	add constraint running_timers_kind_check check (kind in ('visit', 'general', 'assessment')),
	-- An Assessment timer whose Assessment or Request was deleted keeps running, and its hours still land when
	-- it stops, as a visit timer's do when its visit is deleted.
	add constraint running_timers_kind_shape check (
		(kind = 'visit' and job_id is not null and assessment_id is null and request_id is null)
		or (
			kind = 'general' and job_id is null and visit_id is null and assessment_id is null
			and request_id is null and not resume_general
		)
		or (kind = 'assessment' and job_id is null and visit_id is null)
	);

comment on table public.running_timers is
	'The one timer each person has running in a business: a visit timer, an Assessment timer, or the day clock (kind general). Stopping it deletes the row and records the hours. Written only by the timer commands; read through my_running_timer, job_labor and the Timesheets reads.';
comment on column public.running_timers.resume_general is
	'A visit or Assessment timer started while clocked in. Stopping it starts the day clock again at the same instant; clocking out clears it first.';

-- Completing an Assessment finds its timers; deleting a Request or Assessment clears the link.
create index running_timers_assessment_idx on public.running_timers (assessment_id)
	where assessment_id is not null;
create index running_timers_request_idx on public.running_timers (organization_id, request_id)
	where request_id is not null;

-- ---------------------------------------------------------------------------------------------------
-- What an entry was, with its Request
-- ---------------------------------------------------------------------------------------------------

-- The history's values for any entry. request_id is only written for Assessment hours, so Job and General
-- history rows stay exactly as they were and still compare equal.
create or replace function private.time_entry_values(
	entry_kind text,
	entry_user_id uuid,
	entry_job_id uuid,
	entry_visit_id uuid,
	entry_request_id uuid,
	entry_started_at timestamptz,
	entry_minutes integer,
	entry_notes text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
	select private.time_entry_values(
		entry_kind, entry_user_id, entry_job_id, entry_visit_id, entry_started_at, entry_minutes, entry_notes
	) || case when entry_request_id is null then '{}'::jsonb
		else jsonb_build_object('request_id', entry_request_id) end;
$$;

comment on function private.time_entry_values(text, uuid, uuid, uuid, uuid, timestamptz, integer, text) is
	'What an entry was at one moment, as the history stores it, with the Request for Assessment hours.';

revoke all on function private.time_entry_values(text, uuid, uuid, uuid, uuid, timestamptz, integer, text)
	from public, anon, authenticated;
grant execute on function private.time_entry_values(text, uuid, uuid, uuid, uuid, timestamptz, integer, text)
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- Starting: one place for a visit's and an Assessment's Start
-- ---------------------------------------------------------------------------------------------------

create or replace function private.start_own_timer(
	target_organization_id uuid,
	actor_id uuid,
	timer_kind text,
	target_job_id uuid,
	target_visit_id uuid,
	target_assessment_id uuid,
	target_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing public.running_timers;
	started public.running_timers;
	paused_day boolean := false;
begin
	-- Locked so a Clock out or Stop on another phone waits for this Start rather than racing it.
	select timer.* into existing
	from public.running_timers as timer
	where timer.organization_id = target_organization_id and timer.user_id = actor_id
	for update;
	if found then
		if existing.kind <> 'general' then
			-- The same Start again (a double tap, a second phone) is not a mistake: the timer already runs.
			if existing.kind = timer_kind
				and existing.job_id is not distinct from target_job_id
				and existing.visit_id is not distinct from target_visit_id
				and existing.assessment_id is not distinct from target_assessment_id then
				return jsonb_build_object(
					'started_at', existing.started_at, 'already_running', true,
					'day_clock_paused', existing.resume_general
				);
			end if;
			raise exception 'You already have a timer running. Stop it before starting another.'
				using errcode = 'P0409';
		end if;
		-- Clocked in: the day clock's hours so far are recorded and this timer takes over (plan § Timers). It
		-- starts again when this timer stops.
		perform private.stop_running_timer(target_organization_id, actor_id, actor_id, true);
		paused_day := true;
	end if;

	insert into public.running_timers (
		organization_id, user_id, kind, job_id, visit_id, assessment_id, request_id, started_by, resume_general
	)
	values (
		target_organization_id, actor_id, timer_kind, target_job_id, target_visit_id, target_assessment_id,
		target_request_id, actor_id, paused_day
	)
	on conflict (organization_id, user_id) do nothing
	returning * into started;

	-- Another Start won the race between the read above and this insert.
	if started.user_id is null then
		select timer.* into existing
		from public.running_timers as timer
		where timer.organization_id = target_organization_id and timer.user_id = actor_id;
		if existing.kind = timer_kind
			and existing.job_id is not distinct from target_job_id
			and existing.visit_id is not distinct from target_visit_id
			and existing.assessment_id is not distinct from target_assessment_id then
			return jsonb_build_object(
				'started_at', existing.started_at, 'already_running', true,
				'day_clock_paused', existing.resume_general
			);
		end if;
		raise exception 'You already have a timer running. Stop it before starting another.'
			using errcode = 'P0409';
	end if;

	return jsonb_build_object(
		'started_at', started.started_at, 'already_running', false, 'day_clock_paused', paused_day
	);
end;
$$;

comment on function private.start_own_timer(uuid, uuid, text, uuid, uuid, uuid, uuid) is
	'Starts a person''s own visit or Assessment timer: only one timer at a time (P0409), a running day clock is recorded and resumes when this timer stops, and the same Start again is idempotent. Checks nothing else; start_visit_timer and start_assessment_timer decide who may time what.';

revoke all on function private.start_own_timer(uuid, uuid, text, uuid, uuid, uuid, uuid)
	from public, anon, authenticated;
grant execute on function private.start_own_timer(uuid, uuid, text, uuid, uuid, uuid, uuid) to service_role;

create or replace function public.start_visit_timer(
	target_organization_id uuid,
	target_job_id uuid,
	target_visit_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	current_job public.jobs;
	current_visit public.job_visits;
begin
	if caller is null then
		raise exception 'You must be signed in to start a timer.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_job_is_visible(target_organization_id, caller, target_job_id)
		or not private.can_run_own_timer(target_organization_id, caller) then
		raise exception 'You do not have access to time this visit.' using errcode = 'insufficient_privilege';
	end if;

	select job.* into current_job
	from public.jobs as job
	where job.organization_id = target_organization_id and job.id = target_job_id;
	if not found then
		raise exception 'That job could not be found.' using errcode = 'P0404';
	end if;
	if current_job.status <> 'active' then
		raise exception 'This job is closed, so its visits cannot be timed. Reopen the job first.'
			using errcode = 'P0410';
	end if;

	select visit.* into current_visit
	from public.job_visits as visit
	where visit.organization_id = target_organization_id
		and visit.job_id = target_job_id
		and visit.id = target_visit_id;
	if not found then
		raise exception 'That visit could not be found on this job.' using errcode = 'P0404';
	end if;
	if current_visit.completed_at is not null then
		raise exception 'This visit is already complete. Reopen it to time it again.' using errcode = 'P0410';
	end if;

	return private.start_own_timer(
		target_organization_id, caller, 'visit', target_job_id, target_visit_id, null, null
	);
end;
$$;

comment on function public.start_visit_timer(uuid, uuid, uuid) is
	'Starts the caller''s own timer on a visit. Needs the job to be visible and can_run_own_timer; refuses a closed job or a completed visit (P0410) and a second running timer (P0409). A running day clock is stopped, recorded and resumed when this timer stops. Starting the same visit again is idempotent.';

create or replace function public.start_assessment_timer(target_organization_id uuid, target_assessment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	current_assessment public.assessments;
	zone text;
begin
	if caller is null then
		raise exception 'You must be signed in to start a timer.' using errcode = 'insufficient_privilege';
	end if;
	if not private.can_run_own_timer(target_organization_id, caller) then
		raise exception 'You do not have access to time this assessment.' using errcode = 'insufficient_privilege';
	end if;

	select assessment.* into current_assessment
	from public.assessments as assessment
	where assessment.organization_id = target_organization_id and assessment.id = target_assessment_id;
	if not found then
		raise exception 'That assessment could not be found.' using errcode = 'P0404';
	end if;

	-- Who sees an assessment (private.can_view_assessment): everyone, unless their work is narrowed to what
	-- they are assigned, and then only the assessments they are on.
	if private.member_permission_scope(target_organization_id, caller, 'jobs.view') = 'assigned'
		and not exists (
			select 1
			from public.assessment_assignees as assignee
			where assignee.assessment_id = target_assessment_id and assignee.user_id = caller
		) then
		raise exception 'You do not have access to time this assessment.' using errcode = 'insufficient_privilege';
	end if;

	if current_assessment.completed_at is not null then
		raise exception 'This assessment is already complete. Mark it incomplete to time it again.'
			using errcode = 'P0410';
	end if;
	-- Only today's, as Jobber allows (plan § Assessment timers): the business's own today.
	zone := private.organization_timezone(target_organization_id);
	if current_assessment.starts_at is null
		or (current_assessment.starts_at at time zone zone)::date <> (now() at time zone zone)::date then
		raise exception 'Only an assessment booked for today can be timed.' using errcode = 'P0410';
	end if;

	return private.start_own_timer(
		target_organization_id, caller, 'assessment', null, null, current_assessment.id,
		current_assessment.request_id
	);
end;
$$;

comment on function public.start_assessment_timer(uuid, uuid) is
	'Starts the caller''s own timer on an Assessment booked for the business''s today. Needs can_run_own_timer and the Assessment visible (assigned to it when work is narrowed to assigned); refuses a completed or not-today Assessment (P0410) and a second running timer (P0409). Pauses a running day clock like a visit timer. Starting the same Assessment again is idempotent.';

revoke all on function public.start_assessment_timer(uuid, uuid) from public, anon;
grant execute on function public.start_assessment_timer(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- Stopping: Assessment hours land beside General hours, with their Request
-- ---------------------------------------------------------------------------------------------------

create or replace function private.stop_running_timer_at(
	target_organization_id uuid,
	target_user_id uuid,
	actor_id uuid,
	refuse_over_a_day boolean,
	chosen_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	running public.running_timers;
	stopped_at timestamptz := coalesce(chosen_end, now());
	elapsed_seconds numeric;
	recorded_minutes integer;
	job_closed boolean;
	new_entry public.job_time_entries;
	resumed boolean := false;
begin
	-- The lock is what makes a second Stop (another tap, another phone, the visit being completed) wait and
	-- then find nothing, instead of recording the same hours twice.
	select timer.* into running
	from public.running_timers as timer
	where timer.organization_id = target_organization_id and timer.user_id = target_user_id
	for update;
	if not found then
		return jsonb_build_object('stopped', false, 'already_stopped', true, 'recorded', false);
	end if;

	elapsed_seconds := extract(epoch from (stopped_at - running.started_at));

	if chosen_end is not null then
		-- Someone is saying when work really ended (plan § Forgotten timers). It has to be a time the timer
		-- actually ran, and one entry still holds a day at most.
		if chosen_end > now() then
			raise exception 'The end time cannot be in the future.' using errcode = 'invalid_parameter_value';
		end if;
		if elapsed_seconds <= 0 then
			raise exception 'The end time must be after the timer started.' using errcode = 'invalid_parameter_value';
		end if;
		if elapsed_seconds > 86400 then
			raise exception 'A single entry cannot be longer than 24 hours. Choose an end time within a day of the start.'
				using errcode = 'invalid_parameter_value';
		end if;
	elsif elapsed_seconds > 86400 then
		-- A timer left on longer than a day needs someone to say when work really ended, so it stays running
		-- and flagged rather than being guessed at.
		if refuse_over_a_day then
			raise exception 'This timer has run for more than 24 hours, so it cannot be stopped as it is. Ask a manager to set the time work really ended.'
				using errcode = 'P0410';
		end if;
		return jsonb_build_object('stopped', false, 'over_a_day', true, 'recorded', false);
	end if;

	delete from public.running_timers as timer
	where timer.organization_id = target_organization_id and timer.user_id = target_user_id;

	-- Stopping a visit or Assessment timer resumes the day clock it paused (plan § Timers). An end chosen in
	-- the past ends the day instead: restarting General time from then would only make another forgotten timer.
	if running.kind in ('visit', 'assessment') and running.resume_general and chosen_end is null then
		insert into public.running_timers (organization_id, user_id, kind, started_at, started_by)
		values (target_organization_id, target_user_id, 'general', stopped_at, actor_id);
		resumed := true;
	end if;

	-- Under a minute is a mistaken tap, not work (plan § Timers): nothing is recorded, and the caller says so.
	if elapsed_seconds < 60 then
		return jsonb_build_object(
			'stopped', true, 'recorded', false, 'too_short', true, 'kind', running.kind,
			'day_clock_resumed', resumed
		);
	end if;

	recorded_minutes := least(1440, greatest(1, round(elapsed_seconds / 60)::integer));

	-- General and Assessment time belong to no Job and have no Job cost (plan § Hours on the Job).
	if running.kind in ('general', 'assessment') then
		insert into public.general_time_entries (
			id, organization_id, user_id, started_at, minutes, notes, source, created_by, request_id
		)
		values (
			running.id, target_organization_id, target_user_id, running.started_at, recorded_minutes,
			running.notes, 'timer', actor_id, running.request_id
		);

		perform private.write_time_history(
			target_organization_id, running.id, target_user_id, 'stopped', actor_id, null,
			private.time_entry_values(
				case when running.request_id is null then 'general' else 'assessment' end, target_user_id, null,
				null, running.request_id, running.started_at, recorded_minutes, running.notes
			)
		);

		return jsonb_build_object(
			'stopped', true,
			'recorded', true,
			'kind', running.kind,
			'entry_id', running.id,
			'job_id', null,
			'request_id', running.request_id,
			'minutes', recorded_minutes,
			'day_clock_resumed', resumed
		);
	end if;

	select job.status <> 'active' into job_closed
	from public.jobs as job
	where job.organization_id = target_organization_id and job.id = running.job_id;

	-- No permission check here: the timer was started by someone allowed to, and stopping it is not changing
	-- hours. A Job closed while the timer ran still gets them, flagged after_close in its costing history.
	new_entry := private.record_job_time_entry(
		target_organization_id, running.job_id, running.visit_id, target_user_id, running.started_at,
		recorded_minutes, running.notes, 'timer', actor_id, coalesce(job_closed, false), running.id
	);

	perform private.write_time_history(
		target_organization_id, new_entry.id, target_user_id, 'stopped', actor_id, null,
		private.time_entry_values(
			'job', target_user_id, new_entry.job_id, new_entry.visit_id, new_entry.started_at, new_entry.minutes,
			new_entry.notes
		)
	);

	return jsonb_build_object(
		'stopped', true,
		'recorded', true,
		'kind', 'visit',
		'entry_id', new_entry.id,
		'job_id', running.job_id,
		'request_id', null,
		'minutes', recorded_minutes,
		'day_clock_resumed', resumed
	);
end;
$$;

comment on function private.stop_running_timer_at(uuid, uuid, uuid, boolean, timestamptz) is
	'Stops a person''s running timer and records its hours once, under the timer''s own id: a visit timer through record_job_time_entry, the day clock and an Assessment timer into general_time_entries (an Assessment''s with its request_id), each with a "stopped" history row. chosen_end null means now: a timer over a day then refuses (P0410) or stays running, as the caller asks, and a visit or Assessment timer that paused the day clock starts it again. A chosen end must be in the past, after the start and within a day of it, and nothing resumes after it. Under a minute records nothing. Checks nothing; callers decide who may stop.';

-- ---------------------------------------------------------------------------------------------------
-- Completing an Assessment stops its timers
-- ---------------------------------------------------------------------------------------------------

-- A trigger, so every way an Assessment is completed (the Request page, the pipeline) stops its timers, as
-- complete_job_visit does for a visit. A timer left on for more than a day stays running and flagged for a
-- manager to correct.
create or replace function private.stop_timers_on_completed_assessment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
	timed_user uuid;
begin
	for timed_user in
		select timer.user_id
		from public.running_timers as timer
		where timer.organization_id = new.organization_id and timer.assessment_id = new.id
	loop
		perform private.stop_running_timer(new.organization_id, timed_user, (select auth.uid()), false);
	end loop;
	return null;
end;
$$;

comment on function private.stop_timers_on_completed_assessment() is
	'Completing an Assessment stops every timer running on it and records their hours once (plan § Timers, § Assessment timers).';

revoke all on function private.stop_timers_on_completed_assessment() from public, anon, authenticated;

create trigger assessments_stop_timers_on_complete
	after update of completed_at on public.assessments
	for each row
	when (old.completed_at is null and new.completed_at is not null)
	execute function private.stop_timers_on_completed_assessment();

-- ---------------------------------------------------------------------------------------------------
-- The person's own timer names its Assessment
-- ---------------------------------------------------------------------------------------------------

create or replace function public.my_running_timer(target_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	timer jsonb;
	clocked_in boolean := false;
begin
	if caller is null then
		raise exception 'You must be signed in.' using errcode = 'insufficient_privilege';
	end if;
	if not exists (
		select 1
		from public.organization_members as member
		where member.organization_id = target_organization_id
			and member.user_id = caller
			and member.status <> 'removed'
	) then
		raise exception 'You do not have access to this business.' using errcode = 'insufficient_privilege';
	end if;

	select
		jsonb_build_object(
			'kind', running.kind,
			'job_id', running.job_id,
			'job_number', job.job_number,
			'job_title', job.title,
			'visit_id', running.visit_id,
			'visit_date', visit.visit_date,
			'assessment_id', running.assessment_id,
			'request_id', running.request_id,
			'request_title', request.title,
			'started_at', running.started_at,
			'day_clock_paused', running.resume_general
		),
		running.kind = 'general' or running.resume_general
	into timer, clocked_in
	from public.running_timers as running
	left join public.jobs as job on job.organization_id = running.organization_id and job.id = running.job_id
	left join public.job_visits as visit
		on visit.organization_id = running.organization_id and visit.id = running.visit_id
	left join public.requests as request
		on request.organization_id = running.organization_id and request.id = running.request_id
	where running.organization_id = target_organization_id and running.user_id = caller;

	return jsonb_build_object(
		'timer', timer,
		'clocked_in', coalesce(clocked_in, false),
		'can_time', private.can_run_own_timer(target_organization_id, caller),
		-- The phone's clock may be wrong. The running duration is counted from the server's own clock.
		'server_now', now()
	);
end;
$$;

comment on function public.my_running_timer(uuid) is
	'The caller''s own running timer (or null) with its Job and visit, or its Assessment and Request, whether they are clocked in for the day, whether they may run a timer, and the server time to count from. Only ever the caller''s own row.';

-- ---------------------------------------------------------------------------------------------------
-- A running Assessment timer's start and notes
-- ---------------------------------------------------------------------------------------------------

create or replace function public.update_running_timer(
	target_organization_id uuid,
	target_user_id uuid,
	work_day date,
	start_time time,
	notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	running public.running_timers;
	new_started timestamptz;
	clean_notes text := nullif(trim(coalesce(notes, '')), '');
	prior jsonb;
	next jsonb;
begin
	if caller is null then
		raise exception 'You must be signed in to change a timer.' using errcode = 'insufficient_privilege';
	end if;
	if work_day is null or start_time is null then
		raise exception 'Choose the day and time the timer started.' using errcode = 'invalid_parameter_value';
	end if;

	select timer.* into running
	from public.running_timers as timer
	where timer.organization_id = target_organization_id and timer.user_id = target_user_id
	for update;
	if not found then
		raise exception 'This timer has already stopped.' using errcode = 'P0404';
	end if;

	-- A visit timer is changed like hours on its Job while the Job is open: the timer still runs, so it is
	-- not yet hours on a closed Job. Day clock and Assessment timers are changed like General hours.
	if running.kind = 'visit' then
		if not private.member_job_is_visible(target_organization_id, caller, running.job_id)
			or not private.can_write_job_time(target_organization_id, caller, target_user_id, false) then
			raise exception 'You do not have access to change this timer.' using errcode = 'insufficient_privilege';
		end if;
	else
		perform private.assert_can_write_time(target_organization_id, caller, target_user_id, null);
	end if;

	new_started := private.local_instant(target_organization_id, work_day, start_time);
	if new_started > now() then
		raise exception 'A running timer cannot start in the future.' using errcode = 'invalid_parameter_value';
	end if;

	prior := private.time_entry_values(
		case running.kind when 'visit' then 'job' when 'assessment' then 'assessment' else 'general' end,
		running.user_id, running.job_id, running.visit_id, running.request_id, running.started_at, null,
		running.notes
	);
	next := prior || jsonb_build_object('started_at', new_started, 'notes', clean_notes);
	if prior = next then
		return jsonb_build_object('id', running.id, 'changed', false, 'started_at', running.started_at);
	end if;

	update public.running_timers as timer
	set started_at = new_started, notes = clean_notes
	where timer.organization_id = target_organization_id and timer.user_id = target_user_id;

	perform private.write_time_history(
		target_organization_id, running.id, target_user_id, 'changed', caller, prior, next
	);

	return jsonb_build_object('id', running.id, 'changed', true, 'started_at', new_started);
end;
$$;

comment on function public.update_running_timer(uuid, uuid, date, time, text) is
	'Changes a running timer''s start (a day and time on the business''s clock, not in the future) and notes, the only things that can change while it runs. Needs time.track_team, or time.track_own for the caller''s own; a visit timer also needs its Job visible. Writes a "changed" history row under the timer''s id, which the entry keeps when it stops.';

-- ---------------------------------------------------------------------------------------------------
-- Correcting and removing: Assessment hours keep their Request
-- ---------------------------------------------------------------------------------------------------

-- A new parameter, so the old signature goes. Its only callers are the two public commands below.
drop function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text);

create or replace function private.change_time_entry(
	target_organization_id uuid,
	target_entry_id uuid,
	actor_id uuid,
	new_user_id uuid,
	new_job_id uuid,
	new_visit_id uuid,
	new_request_id uuid,
	new_started_at timestamptz,
	new_minutes integer,
	new_notes text,
	reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	job_entry public.job_time_entries;
	general_entry public.general_time_entries;
	old_kind text;
	old_user uuid;
	old_job uuid;
	old_visit uuid;
	old_request uuid;
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
		old_request := general_entry.request_id;
		old_kind := case when old_request is null then 'general' else 'assessment' end;
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
	-- Assessment hours stay on their own Assessment, or become General or Job hours. Hours are never put on
	-- an Assessment by hand (plan § Timesheets page: Add entry is a Job or General).
	if new_request_id is not null then
		if new_job_id is not null then
			raise exception 'Hours cannot be on a job and an assessment at once.'
				using errcode = 'invalid_parameter_value';
		end if;
		if new_request_id is distinct from old_request then
			raise exception 'Only an assessment''s own hours can stay on it.' using errcode = 'invalid_parameter_value';
		end if;
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

	prior := private.time_entry_values(
		old_kind, old_user, old_job, old_visit, old_request, old_started, old_minutes, old_notes
	);
	next := private.time_entry_values(
		case when new_job_id is not null then 'job' when new_request_id is not null then 'assessment' else 'general' end,
		new_user_id, new_job_id, new_visit_id, new_request_id, new_started_at, new_minutes, clean_notes
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
	elsif old_kind <> 'job' and new_job_id is null then
		update public.general_time_entries as entry
		set user_id = new_user_id,
			request_id = new_request_id,
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
		-- From General or an Assessment to a Job: the hours join that Job's costing at the person's current rate.
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
$$;

comment on function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text) is
	'The one writer that corrects recorded hours, for Timesheets and a Job''s Labor alike: person, Job or General, visit, Assessment (only the entry''s own, kept or cleared), start, minutes and notes. Moves hours between a Job and General keeping their id, writes the Job costing trail and a "changed" history row. Refuses approved hours to anyone without time.track_team (P0410). Checks permission with assert_can_write_time for the hours before and after.';

revoke all on function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text)
	from public, anon, authenticated;
grant execute on function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text)
	to service_role;

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
set search_path = 'pg_catalog', 'public'
as $$
declare
	caller uuid := (select auth.uid());
	entry_user uuid;
begin
	if caller is null then
		raise exception 'You must be signed in to change hours.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
		raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
	end if;

	select entry.user_id into entry_user
	from public.job_time_entries as entry
	where entry.organization_id = target_organization_id
		and entry.job_id = target_job_id
		and entry.id = target_entry_id;
	if not found then
		raise exception 'Those hours could not be found.' using errcode = 'P0404';
	end if;

	-- Whose hours they are does not change from the Labor section.
	return private.change_time_entry(
		target_organization_id, target_entry_id, caller, entry_user, target_job_id, target_visit_id, null,
		update_job_time_entry.started_at, update_job_time_entry.minutes, update_job_time_entry.notes,
		update_job_time_entry.reason
	);
end;
$$;

comment on function public.update_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text, text) is
	'Corrects recorded hours on this Job, keeping the person and the rate the entry was recorded with. Needs time.track_team for anyone else''s, time.track_own for their own on an open job. Goes through private.change_time_entry: costing trail and edit history.';

-- Timesheets' correction gains the Assessment, so the old signature goes.
drop function public.update_time_entry(uuid, uuid, uuid, uuid, uuid, date, time, time, text);

create or replace function public.update_time_entry(
	target_organization_id uuid,
	target_entry_id uuid,
	target_user_id uuid,
	target_job_id uuid,
	target_visit_id uuid,
	work_day date,
	start_time time,
	end_time time,
	notes text default null,
	target_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	span record;
begin
	if caller is null then
		raise exception 'You must be signed in to change hours.' using errcode = 'insufficient_privilege';
	end if;

	select * into span from private.local_time_span(target_organization_id, work_day, start_time, end_time);

	return private.change_time_entry(
		target_organization_id, target_entry_id, caller, target_user_id, target_job_id, target_visit_id,
		target_request_id, span.span_started_at, span.span_minutes, notes, null
	);
end;
$$;

comment on function public.update_time_entry(uuid, uuid, uuid, uuid, uuid, date, time, time, text, uuid) is
	'Corrects an entry from Timesheets: person, Job or General (null), visit, day, start and end on the business''s clock, notes, and for Assessment hours their own Request (kept) or null (made General). See private.change_time_entry.';

revoke all on function public.update_time_entry(uuid, uuid, uuid, uuid, uuid, date, time, time, text, uuid)
	from public, anon;
grant execute on function public.update_time_entry(uuid, uuid, uuid, uuid, uuid, date, time, time, text, uuid)
	to authenticated, service_role;

create or replace function private.remove_time_entry(
	target_organization_id uuid,
	target_entry_id uuid,
	actor_id uuid,
	reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
			case when general_entry.request_id is null then 'general' else 'assessment' end,
			general_entry.user_id, null, null, general_entry.request_id, general_entry.started_at,
			general_entry.minutes, general_entry.notes
		),
		null
	);
	return jsonb_build_object('id', target_entry_id, 'after_close', false);
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- The reads say which hours were an Assessment's
-- ---------------------------------------------------------------------------------------------------

-- History names the Request by title only for a reader who may open it, as Timesheets does.
create or replace function private.describe_time_values(target_organization_id uuid, entry_values jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select case when entry_values is null then null else entry_values || jsonb_build_object(
		'user_name', private.member_display_name(target_organization_id, (entry_values->>'user_id')::uuid),
		'job_number', (
			select job.job_number
			from public.jobs as job
			where job.organization_id = target_organization_id and job.id = (entry_values->>'job_id')::uuid
		),
		'visit_date', (
			select visit.visit_date
			from public.job_visits as visit
			where visit.organization_id = target_organization_id and visit.id = (entry_values->>'visit_id')::uuid
		),
		'request_title', (
			select request.title
			from public.requests as request
			where request.organization_id = target_organization_id
				and request.id = (entry_values->>'request_id')::uuid
				and private.can_view_request(target_organization_id, request.id)
		)
	) end;
$$;

-- Its columns change, so it is replaced rather than redefined. Nothing depends on it but the two plpgsql
-- reads below, which look it up when they run.
drop function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid);

create or replace function private.timesheet_rows(
	target_organization_id uuid,
	window_start timestamptz,
	window_end timestamptz,
	only_user_id uuid
)
returns table (
	user_id uuid,
	kind text,
	entry_id uuid,
	job_id uuid,
	visit_id uuid,
	request_id uuid,
	started_at timestamptz,
	ended_at timestamptz,
	minutes integer,
	notes text,
	source text,
	is_running boolean,
	approved boolean,
	"overlaps" boolean
)
language sql
stable
security definer
set search_path = ''
as $$
	with hours as (
		-- A day either side of the window, so an entry is still compared with one that started the evening
		-- before or runs into the morning after. No entry is longer than a day.
		select entry.user_id, 'job'::text as kind, entry.id as entry_id, entry.job_id, entry.visit_id,
			null::uuid as request_id,
			entry.started_at, entry.started_at + make_interval(mins => entry.minutes) as ended_at, entry.minutes,
			entry.notes, entry.source, false as is_running, entry.approved_at is not null as approved
		from public.job_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.started_at >= window_start - interval '1 day'
			and entry.started_at < window_end + interval '1 day'
			and (only_user_id is null or entry.user_id = only_user_id)
		union all
		select entry.user_id, case when entry.request_id is null then 'general' else 'assessment' end, entry.id,
			null, null, entry.request_id,
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
		select timer.user_id,
			case timer.kind when 'visit' then 'job' when 'assessment' then 'assessment' else 'general' end,
			timer.id, timer.job_id, timer.visit_id, timer.request_id, timer.started_at, null, null, timer.notes,
			'timer', true, false
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
	select ordered.user_id, ordered.kind, ordered.entry_id, ordered.job_id, ordered.visit_id, ordered.request_id,
		ordered.started_at, ordered.ended_at, ordered.minutes, ordered.notes, ordered.source,
		ordered.is_running, ordered.approved,
		coalesce(ordered.latest_earlier_end - ordered.started_at >= interval '1 minute', false)
			or coalesce(coalesce(ordered.ended_at, now()) - ordered.next_start >= interval '1 minute', false)
	from ordered
	where ordered.started_at >= window_start and ordered.started_at < window_end;
$$;

comment on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) is
	'Every entry and running timer that started in the window, for one person or everyone: kind job, general or assessment, its Job, visit or Request, approval, and whether it shares a minute or more with another of that person''s entries. The one source for timesheet_summary and timesheet_entries.';

revoke all on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;
grant execute on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) to service_role;

create or replace function public.timesheet_entries(
	target_organization_id uuid,
	target_user_id uuid,
	range_from date,
	range_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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

	-- Every hour of theirs is listed, so the totals add up. A Job or Request the reader may not open (a Field
	-- member no longer on it) is named by its number only, or as "Assessment", and is not a link.
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
					'request', case when listed.request_id is null then null else jsonb_build_object(
						'id', listed.request_id,
						'visible', listed.request_visible,
						'title', case when listed.request_visible then request.title end
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
			) as job_visible,
			hours.request_id is not null
				and private.can_view_request(target_organization_id, hours.request_id) as request_visible
		from private.timesheet_rows(target_organization_id, window_start, window_end, target_user_id) as hours
		order by hours.started_at, hours.entry_id
		limit page_size
	) as listed
	left join public.jobs as job
		on job.organization_id = target_organization_id and job.id = listed.job_id
	left join public.clients as client
		on client.organization_id = target_organization_id and client.id = job.client_id
	left join public.job_visits as visit
		on visit.organization_id = target_organization_id and visit.id = listed.visit_id
	left join public.requests as request
		on request.organization_id = target_organization_id and request.id = listed.request_id;

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
$$;

comment on function public.timesheet_entries(uuid, uuid, date, date) is
	'One person''s entries and running timer for a day or a week (at most 7 days) in the business''s time zone: what each was for (a Job, an Assessment''s Request, or General), times, notes, approval, warnings, and whether the reader may edit or delete it. A Job or Request the reader cannot open is named without its title. time.track_team reads anyone; the lower rungs only the caller.';
