-- Time clock Part 5 (docs/time-clock-behavior-contract.md § Timesheets page, § Forgotten timers): hours are
-- added, corrected and removed from Timesheets, every change is kept in a history people can read, and a
-- manager clocks a team member in or stops a forgotten timer at the time work really ended.
--
-- 1. public.time_entry_history is the edit history: who did what to an entry, when, and the values before
--    and after. It never holds money; Job costing keeps job_costing_events for that.
-- 2. running_timers gets an id and notes. The id becomes the entry's id when the timer stops, so a running
--    timer's corrections and the entry's later ones read as one history.
-- 3. private.change_time_entry and private.remove_time_entry are the one place recorded hours are corrected
--    or removed, for Timesheets and for a Job's Labor section alike. A change between a Job and General moves
--    the row to the other table under the same id.
-- 4. Timesheets speaks in the business's own day and clock times; private.local_time_span turns them into
--    instants. 24 hours is the most one entry holds (plan § Forgotten timers).
-- 5. Commands: add_time_entry, update_time_entry, delete_time_entry, update_running_timer, clock_in_member,
--    stop_timer_at, and the read time_entry_history. timesheet_rows, timesheet_entries and timesheet_summary
--    now say what the reader may change.

-- ---------------------------------------------------------------------------------------------------
-- One id from Start to the last correction
-- ---------------------------------------------------------------------------------------------------

alter table public.running_timers
	add column id uuid not null default gen_random_uuid(),
	add column notes text check (notes is null or char_length(notes) <= 2000),
	add constraint running_timers_id_unique unique (id);

comment on column public.running_timers.id is
	'Becomes the recorded entry''s id when the timer stops, so its history continues on the entry.';
comment on column public.running_timers.notes is
	'Notes typed while the timer runs. Carried onto the entry when it stops.';

-- ---------------------------------------------------------------------------------------------------
-- The edit history
-- ---------------------------------------------------------------------------------------------------

create table public.time_entry_history (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	-- A job_time_entries or general_time_entries id, or a running timer's that will become one. A plain id:
	-- the history outlives a deleted entry.
	entry_id uuid not null,
	-- Whose hours, after the change (before it, for a deletion).
	user_id uuid not null,
	action text not null check (action in ('added', 'stopped', 'changed', 'deleted')),
	actor_id uuid references auth.users (id) on delete set null,
	prior_values jsonb,
	new_values jsonb,
	-- The moment of writing, not of the transaction: a stop and the change after it in one transaction still
	-- read in the order they happened.
	created_at timestamptz not null default clock_timestamp()
);

comment on table public.time_entry_history is
	'Who added, stopped, changed or deleted each time entry, when, and its values before and after (plan § Timesheets page, Edit history). Never holds money. Written only by the time commands; read through time_entry_history().';

create index time_entry_history_entry_idx
	on public.time_entry_history (organization_id, entry_id, created_at, id);

alter table public.time_entry_history enable row level security;
revoke all on table public.time_entry_history from anon, authenticated;

-- What an entry was at one moment, as the history stores it. minutes is null while a timer runs.
create or replace function private.time_entry_values(
	entry_kind text,
	entry_user_id uuid,
	entry_job_id uuid,
	entry_visit_id uuid,
	entry_started_at timestamptz,
	entry_minutes integer,
	entry_notes text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
	select jsonb_build_object(
		'kind', entry_kind,
		'user_id', entry_user_id,
		'job_id', entry_job_id,
		'visit_id', entry_visit_id,
		'started_at', entry_started_at,
		'minutes', entry_minutes,
		'notes', entry_notes
	);
$$;

revoke all on function private.time_entry_values(text, uuid, uuid, uuid, timestamptz, integer, text)
	from public, anon, authenticated;
grant execute on function private.time_entry_values(text, uuid, uuid, uuid, timestamptz, integer, text)
	to service_role;

create or replace function private.write_time_history(
	target_organization_id uuid,
	target_entry_id uuid,
	target_user_id uuid,
	history_action text,
	actor uuid,
	prior jsonb,
	next jsonb
)
returns void
language sql
security definer
set search_path = ''
as $$
	insert into public.time_entry_history (
		organization_id, entry_id, user_id, action, actor_id, prior_values, new_values
	)
	values (target_organization_id, target_entry_id, target_user_id, history_action, actor, prior, next);
$$;

revoke all on function private.write_time_history(uuid, uuid, uuid, text, uuid, jsonb, jsonb)
	from public, anon, authenticated;
grant execute on function private.write_time_history(uuid, uuid, uuid, text, uuid, jsonb, jsonb)
	to service_role;

-- Hours recorded before this history existed: Job hours from their costing trail, General hours (two days
-- old at most) from the row itself. Notes were never in the costing trail, so those keys are left out
-- rather than claimed empty.
insert into public.time_entry_history (
	organization_id, entry_id, user_id, action, actor_id, prior_values, new_values, created_at
)
select event.organization_id,
	event.subject_id,
	entry.user_id,
	case
		when event.event_type = 'time_entry_added' and event.new_values->>'source' = 'timer' then 'stopped'
		when event.event_type = 'time_entry_added' then 'added'
		else 'changed'
	end,
	event.actor_id,
	case when event.prior_values is null then null else jsonb_build_object(
		'kind', 'job',
		'user_id', coalesce(event.prior_values->'user_id', to_jsonb(entry.user_id)),
		'job_id', event.job_id,
		'visit_id', event.prior_values->'visit_id',
		'started_at', event.prior_values->'started_at',
		'minutes', event.prior_values->'minutes'
	) end,
	case when event.new_values is null then null else jsonb_build_object(
		'kind', 'job',
		'user_id', coalesce(event.new_values->'user_id', to_jsonb(entry.user_id)),
		'job_id', event.job_id,
		'visit_id', event.new_values->'visit_id',
		'started_at', event.new_values->'started_at',
		'minutes', event.new_values->'minutes'
	) end,
	event.created_at
from public.job_costing_events as event
join public.job_time_entries as entry
	on entry.organization_id = event.organization_id and entry.id = event.subject_id
where event.subject_kind = 'time_entry'
	and event.event_type in ('time_entry_added', 'time_entry_updated');

insert into public.time_entry_history (
	organization_id, entry_id, user_id, action, actor_id, new_values, created_at
)
select entry.organization_id, entry.id, entry.user_id,
	case when entry.source = 'timer' then 'stopped' else 'added' end,
	entry.created_by,
	private.time_entry_values('general', entry.user_id, null, null, entry.started_at, entry.minutes, entry.notes),
	entry.created_at
from public.general_time_entries as entry;

-- ---------------------------------------------------------------------------------------------------
-- Who may change which hours
-- ---------------------------------------------------------------------------------------------------

create or replace function private.can_write_general_time(
	target_organization_id uuid,
	actor_id uuid,
	subject_user_id uuid
)
returns boolean
language sql
stable
set search_path = ''
as $$
	select private.member_has_permission(target_organization_id, actor_id, 'time.track_team')
		or (
			subject_user_id = actor_id
			and private.member_has_permission(target_organization_id, actor_id, 'time.track_own')
		);
$$;

comment on function private.can_write_general_time(uuid, uuid, uuid) is
	'Whether this person may record or change these General hours: anyone''s with time.track_team, their own with time.track_own. General time has no Job, so no Job visibility or closing applies.';

revoke all on function private.can_write_general_time(uuid, uuid, uuid) from public, anon;
grant execute on function private.can_write_general_time(uuid, uuid, uuid) to authenticated, service_role;

-- Raises the refusal for touching hours on a Job, or General hours, the way the Job's Labor section always
-- has: a closed Job is a rule (P0410), anything else reads as no access.
create or replace function private.assert_can_write_time(
	target_organization_id uuid,
	actor_id uuid,
	subject_user_id uuid,
	target_job_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	job_closed boolean;
begin
	if target_job_id is null then
		if not private.can_write_general_time(target_organization_id, actor_id, subject_user_id) then
			raise exception 'You do not have access to change these hours.' using errcode = 'insufficient_privilege';
		end if;
		return;
	end if;

	if not private.member_job_is_visible(target_organization_id, actor_id, target_job_id) then
		raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
	end if;
	select job.status <> 'active' into job_closed
	from public.jobs as job
	where job.organization_id = target_organization_id and job.id = target_job_id;
	if not found then
		raise exception 'That job could not be found.' using errcode = 'P0404';
	end if;
	if not private.can_write_job_time(target_organization_id, actor_id, subject_user_id, job_closed) then
		if job_closed then
			raise exception 'A closed job''s hours can only be changed by someone who manages the team''s time.'
				using errcode = 'P0410';
		end if;
		raise exception 'You do not have access to change these hours.' using errcode = 'insufficient_privilege';
	end if;
end;
$$;

revoke all on function private.assert_can_write_time(uuid, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function private.assert_can_write_time(uuid, uuid, uuid, uuid) to service_role;

-- Hours belong to someone who works here.
create or replace function private.assert_team_member(target_organization_id uuid, target_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
	if not exists (
		select 1
		from public.organization_members as member
		where member.organization_id = target_organization_id
			and member.user_id = target_user_id
			and member.status <> 'removed'
	) then
		raise exception 'That person is not on this team.' using errcode = 'P0404';
	end if;
end;
$$;

revoke all on function private.assert_team_member(uuid, uuid) from public, anon, authenticated;
grant execute on function private.assert_team_member(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- The business's clock
-- ---------------------------------------------------------------------------------------------------

create or replace function private.local_instant(target_organization_id uuid, local_day date, local_time time)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
	select (local_day + local_time) at time zone private.organization_timezone(target_organization_id);
$$;

revoke all on function private.local_instant(uuid, date, time) from public, anon, authenticated;
grant execute on function private.local_instant(uuid, date, time) to service_role;

-- A day, a start and an end on the business's clock, as an entry stores them. An end at or before the
-- start is the next morning: a 10 pm to 2 am call-out is one entry.
create or replace function private.local_time_span(
	target_organization_id uuid,
	work_day date,
	start_time time,
	end_time time,
	out span_started_at timestamptz,
	out span_minutes integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	ended timestamptz;
begin
	if work_day is null or start_time is null or end_time is null then
		raise exception 'Choose the day, the start time and the end time.' using errcode = 'invalid_parameter_value';
	end if;
	if start_time = end_time then
		raise exception 'The end time must be different from the start time.'
			using errcode = 'invalid_parameter_value';
	end if;

	span_started_at := private.local_instant(target_organization_id, work_day, start_time);
	ended := private.local_instant(
		target_organization_id,
		case when end_time > start_time then work_day else work_day + 1 end,
		end_time
	);
	span_minutes := round(extract(epoch from (ended - span_started_at)) / 60)::integer;

	if span_minutes < 1 or span_minutes > 1440 then
		raise exception 'A single entry cannot be longer than 24 hours.' using errcode = 'invalid_parameter_value';
	end if;
end;
$$;

revoke all on function private.local_time_span(uuid, date, time, time) from public, anon, authenticated;
grant execute on function private.local_time_span(uuid, date, time, time) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- The one writer of hours onto a Job, now able to keep an id it is handed
-- ---------------------------------------------------------------------------------------------------

drop function private.record_job_time_entry(uuid, uuid, uuid, uuid, timestamptz, integer, text, text, uuid, boolean);

create or replace function private.record_job_time_entry(
	target_organization_id uuid,
	target_job_id uuid,
	target_visit_id uuid,
	target_user_id uuid,
	entry_started_at timestamptz,
	entry_minutes integer,
	entry_notes text,
	entry_source text,
	actor_id uuid,
	job_closed boolean,
	entry_id uuid
)
returns public.job_time_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
	recorded_rate bigint;
	new_entry public.job_time_entries;
begin
	-- The one and only read of the rate profile for hours. Null is kept as null: nobody has said what this
	-- person costs, and unrated hours are reported as unrated rather than valued at nothing.
	select profile.cost_per_hour_minor into recorded_rate
	from public.organization_member_cost_profiles as profile
	where profile.organization_id = target_organization_id
		and profile.user_id = target_user_id;

	insert into public.job_time_entries (
		id, organization_id, job_id, visit_id, user_id, started_at, minutes, notes, cost_per_hour_minor,
		created_by, source
	)
	values (
		coalesce(entry_id, gen_random_uuid()), target_organization_id, target_job_id, target_visit_id,
		target_user_id, entry_started_at, entry_minutes, nullif(trim(coalesce(entry_notes, '')), ''),
		recorded_rate, actor_id, entry_source
	)
	returning * into new_entry;

	insert into public.job_costing_events (
		organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close, new_values
	)
	values (
		target_organization_id, target_job_id, 'time_entry_added', 'time_entry', new_entry.id, actor_id,
		job_closed,
		jsonb_build_object(
			'user_id', new_entry.user_id,
			'visit_id', new_entry.visit_id,
			'started_at', new_entry.started_at,
			'minutes', new_entry.minutes,
			'cost_per_hour_minor', new_entry.cost_per_hour_minor,
			'cost_total_minor', new_entry.cost_total_minor,
			'source', new_entry.source
		)
	);

	return new_entry;
end;
$$;

comment on function private.record_job_time_entry(uuid, uuid, uuid, uuid, timestamptz, integer, text, text, uuid, boolean, uuid) is
	'Writes hours onto a Job: copies the person''s current cost rate onto the entry and appends the costing history row. Keeps entry_id when given (a stopped timer, an entry moved from General). Checks nothing and writes no edit history; every caller decides who may record and what the history says.';

revoke all on function private.record_job_time_entry(uuid, uuid, uuid, uuid, timestamptz, integer, text, text, uuid, boolean, uuid)
	from public, anon, authenticated;
grant execute on function private.record_job_time_entry(uuid, uuid, uuid, uuid, timestamptz, integer, text, text, uuid, boolean, uuid)
	to service_role;

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
set search_path = 'pg_catalog', 'public'
as $$
declare
	caller uuid := (select auth.uid());
	current_job public.jobs;
	job_closed boolean;
	new_entry public.job_time_entries;
begin
	if caller is null then
		raise exception 'You must be signed in to record hours.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
		raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
	end if;

	-- No row lock. Hours are appended to a job, never derived from it, so two people recording time at once
	-- have nothing to fight over.
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

	perform private.assert_team_member(target_organization_id, target_user_id);

	if target_visit_id is not null and not exists (
		select 1
		from public.job_visits as visit
		where visit.organization_id = target_organization_id
			and visit.job_id = target_job_id
			and visit.id = target_visit_id
	) then
		raise exception 'That visit could not be found on this job.' using errcode = 'P0404';
	end if;

	new_entry := private.record_job_time_entry(
		target_organization_id, target_job_id, target_visit_id, target_user_id,
		add_job_time_entry.started_at, add_job_time_entry.minutes, add_job_time_entry.notes, 'manual', caller,
		job_closed, null
	);

	perform private.write_time_history(
		target_organization_id, new_entry.id, new_entry.user_id, 'added', caller, null,
		private.time_entry_values(
			'job', new_entry.user_id, new_entry.job_id, new_entry.visit_id, new_entry.started_at, new_entry.minutes,
			new_entry.notes
		)
	);

	return jsonb_build_object('id', new_entry.id, 'after_close', job_closed);
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Stopping, now or at the time work really ended
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

	-- Stopping a visit timer resumes the day clock it paused (plan § Timers). An end chosen in the past ends
	-- the day instead: restarting General time from then would only make another forgotten timer.
	if running.kind = 'visit' and running.resume_general and chosen_end is null then
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

	-- General time belongs to no Job and has no Job cost (plan § Hours on the Job).
	if running.kind = 'general' then
		insert into public.general_time_entries (
			id, organization_id, user_id, started_at, minutes, notes, source, created_by
		)
		values (
			running.id, target_organization_id, target_user_id, running.started_at, recorded_minutes,
			running.notes, 'timer', actor_id
		);

		perform private.write_time_history(
			target_organization_id, running.id, target_user_id, 'stopped', actor_id, null,
			private.time_entry_values(
				'general', target_user_id, null, null, running.started_at, recorded_minutes, running.notes
			)
		);

		return jsonb_build_object(
			'stopped', true,
			'recorded', true,
			'kind', 'general',
			'entry_id', running.id,
			'job_id', null,
			'minutes', recorded_minutes,
			'day_clock_resumed', false
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
		'minutes', recorded_minutes,
		'day_clock_resumed', resumed
	);
end;
$$;

comment on function private.stop_running_timer_at(uuid, uuid, uuid, boolean, timestamptz) is
	'Stops a person''s running timer and records its hours once, under the timer''s own id: a visit timer through record_job_time_entry, the day clock into general_time_entries, each with a "stopped" history row. chosen_end null means now: a timer over a day then refuses (P0410) or stays running, as the caller asks, and a visit timer that paused the day clock starts it again. A chosen end must be in the past, after the start and within a day of it, and nothing resumes after it. Under a minute records nothing. Checks nothing; callers decide who may stop.';

revoke all on function private.stop_running_timer_at(uuid, uuid, uuid, boolean, timestamptz)
	from public, anon, authenticated;
grant execute on function private.stop_running_timer_at(uuid, uuid, uuid, boolean, timestamptz) to service_role;

-- Every existing caller (Stop, Clock out, a visit's Start pausing the day clock, completing a visit) stops
-- now, and goes through the same code.
create or replace function private.stop_running_timer(
	target_organization_id uuid,
	target_user_id uuid,
	actor_id uuid,
	refuse_over_a_day boolean
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
	select private.stop_running_timer_at(target_organization_id, target_user_id, actor_id, refuse_over_a_day, null);
$$;

comment on function private.stop_running_timer(uuid, uuid, uuid, boolean) is
	'Stops a person''s running timer now. See stop_running_timer_at.';

-- ---------------------------------------------------------------------------------------------------
-- Correcting and removing recorded hours: the one place for Timesheets and a Job's Labor alike
-- ---------------------------------------------------------------------------------------------------

create or replace function private.change_time_entry(
	target_organization_id uuid,
	target_entry_id uuid,
	actor_id uuid,
	new_user_id uuid,
	new_job_id uuid,
	new_visit_id uuid,
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
	old_started timestamptz;
	old_minutes integer;
	old_notes text;
	old_source text;
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
	end if;

	-- Allowed to change the hours as they are, and to make them what they become.
	perform private.assert_can_write_time(target_organization_id, actor_id, old_user, old_job);
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
			id, organization_id, user_id, started_at, minutes, notes, source, created_by, created_at
		)
		values (
			target_entry_id, target_organization_id, new_user_id, new_started_at, new_minutes, clean_notes,
			old_source, job_entry.created_by, job_entry.created_at
		);
	else
		-- From General to a Job: the hours join that Job's costing at the person's current rate.
		delete from public.general_time_entries as entry
		where entry.organization_id = target_organization_id and entry.id = target_entry_id;
		perform private.record_job_time_entry(
			target_organization_id, new_job_id, new_visit_id, new_user_id, new_started_at, new_minutes,
			clean_notes, old_source, actor_id, new_closed, target_entry_id
		);
	end if;

	perform private.write_time_history(
		target_organization_id, target_entry_id, new_user_id, 'changed', actor_id, prior, next
	);

	return jsonb_build_object('id', target_entry_id, 'changed', true, 'after_close', old_closed or new_closed);
end;
$$;

comment on function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text) is
	'Corrects recorded hours: person, Job (null for General), visit, start, minutes and notes. Checks the actor may change the hours as they are and as they become; a running timer is refused (P0410). Moving between a Job and General moves the row under the same id; costing history is written on each Job touched; a different person is re-priced at their current rate. Writes one "changed" history row, or nothing when nothing changed.';

revoke all on function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text)
	from public, anon, authenticated;
grant execute on function private.change_time_entry(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, integer, text, text)
	to service_role;

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
$$;

comment on function private.remove_time_entry(uuid, uuid, uuid, text) is
	'Removes recorded Job or General hours after checking the actor may change them. Job hours are written whole to the costing trail first; every removal gets a "deleted" history row. A running timer is refused (P0410).';

revoke all on function private.remove_time_entry(uuid, uuid, uuid, text) from public, anon, authenticated;
grant execute on function private.remove_time_entry(uuid, uuid, uuid, text) to service_role;

-- The Job's Labor section keeps its commands and their shape; they now go through the same correction, so the
-- edit history on Timesheets includes what was changed there (plan § Timesheets page: one set of hours).
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
		target_organization_id, target_entry_id, caller, entry_user, target_job_id, target_visit_id,
		update_job_time_entry.started_at, update_job_time_entry.minutes, update_job_time_entry.notes,
		update_job_time_entry.reason
	);
end;
$$;

comment on function public.update_job_time_entry(uuid, uuid, uuid, timestamptz, integer, uuid, text, text) is
	'Corrects recorded hours on this Job, keeping the person and the rate the entry was recorded with. Needs time.track_team for anyone else''s, time.track_own for their own on an open job. Goes through private.change_time_entry: costing trail and edit history.';

create or replace function public.delete_job_time_entry(
	target_organization_id uuid,
	target_job_id uuid,
	target_entry_id uuid,
	reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'public'
as $$
declare
	caller uuid := (select auth.uid());
begin
	if caller is null then
		raise exception 'You must be signed in to remove hours.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
		raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
	end if;
	if not exists (
		select 1
		from public.job_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.job_id = target_job_id
			and entry.id = target_entry_id
	) then
		raise exception 'Those hours could not be found.' using errcode = 'P0404';
	end if;

	return private.remove_time_entry(target_organization_id, target_entry_id, caller, delete_job_time_entry.reason);
end;
$$;

comment on function public.delete_job_time_entry(uuid, uuid, uuid, text) is
	'Removes recorded hours from this Job, writing the whole entry to job_costing_events first and a "deleted" row to the edit history. Same permissions as correcting one.';

-- ---------------------------------------------------------------------------------------------------
-- Timesheets commands
-- ---------------------------------------------------------------------------------------------------

create or replace function public.add_time_entry(
	target_organization_id uuid,
	target_user_id uuid,
	target_job_id uuid,
	target_visit_id uuid,
	work_day date,
	start_time time,
	end_time time,
	notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	span record;
	new_id uuid;
	clean_notes text := nullif(trim(coalesce(notes, '')), '');
begin
	if caller is null then
		raise exception 'You must be signed in to record hours.' using errcode = 'insufficient_privilege';
	end if;

	select * into span from private.local_time_span(target_organization_id, work_day, start_time, end_time);

	-- Job hours are recorded exactly as the Job's Labor section records them.
	if target_job_id is not null then
		return public.add_job_time_entry(
			target_organization_id, target_job_id, target_user_id, span.span_started_at, span.span_minutes,
			target_visit_id, clean_notes
		);
	end if;

	if target_visit_id is not null then
		raise exception 'General time has no visit.' using errcode = 'invalid_parameter_value';
	end if;
	perform private.assert_can_write_time(target_organization_id, caller, target_user_id, null);
	perform private.assert_team_member(target_organization_id, target_user_id);

	insert into public.general_time_entries (organization_id, user_id, started_at, minutes, notes, source, created_by)
	values (target_organization_id, target_user_id, span.span_started_at, span.span_minutes, clean_notes, 'manual', caller)
	returning id into new_id;

	perform private.write_time_history(
		target_organization_id, new_id, target_user_id, 'added', caller, null,
		private.time_entry_values(
			'general', target_user_id, null, null, span.span_started_at, span.span_minutes, clean_notes
		)
	);

	return jsonb_build_object('id', new_id, 'after_close', false);
end;
$$;

comment on function public.add_time_entry(uuid, uuid, uuid, uuid, date, time, time, text) is
	'Adds hours from Timesheets: a Job (and optionally its visit) or General when target_job_id is null, on a day with start and end times on the business''s clock (an end at or before the start is the next morning; 24 hours at most). Job hours go through add_job_time_entry; General hours need time.track_team, or time.track_own for the caller''s own.';

revoke all on function public.add_time_entry(uuid, uuid, uuid, uuid, date, time, time, text) from public, anon;
grant execute on function public.add_time_entry(uuid, uuid, uuid, uuid, date, time, time, text)
	to authenticated, service_role;

create or replace function public.update_time_entry(
	target_organization_id uuid,
	target_entry_id uuid,
	target_user_id uuid,
	target_job_id uuid,
	target_visit_id uuid,
	work_day date,
	start_time time,
	end_time time,
	notes text default null
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
		span.span_started_at, span.span_minutes, notes, null
	);
end;
$$;

comment on function public.update_time_entry(uuid, uuid, uuid, uuid, uuid, date, time, time, text) is
	'Corrects an entry from Timesheets: person, Job or General (null), visit, day, start and end on the business''s clock, and notes. See private.change_time_entry.';

revoke all on function public.update_time_entry(uuid, uuid, uuid, uuid, uuid, date, time, time, text)
	from public, anon;
grant execute on function public.update_time_entry(uuid, uuid, uuid, uuid, uuid, date, time, time, text)
	to authenticated, service_role;

create or replace function public.delete_time_entry(target_organization_id uuid, target_entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
begin
	if caller is null then
		raise exception 'You must be signed in to remove hours.' using errcode = 'insufficient_privilege';
	end if;
	return private.remove_time_entry(target_organization_id, target_entry_id, caller, null);
end;
$$;

comment on function public.delete_time_entry(uuid, uuid) is
	'Removes Job or General hours from Timesheets. A running timer cannot be deleted (P0410). See private.remove_time_entry.';

revoke all on function public.delete_time_entry(uuid, uuid) from public, anon;
grant execute on function public.delete_time_entry(uuid, uuid) to authenticated, service_role;

-- While a timer runs only its start time and notes can be changed (plan § Timesheets page).
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
	-- not yet hours on a closed Job.
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
		case when running.kind = 'visit' then 'job' else 'general' end, running.user_id, running.job_id,
		running.visit_id, running.started_at, null, running.notes
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

revoke all on function public.update_running_timer(uuid, uuid, date, time, text) from public, anon;
grant execute on function public.update_running_timer(uuid, uuid, date, time, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- Manager actions: clock someone in, stop a timer at the time work really ended
-- ---------------------------------------------------------------------------------------------------

create or replace function private.clock_in_for(target_organization_id uuid, target_user_id uuid, actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing public.running_timers;
	started public.running_timers;
begin
	for attempt in 1..2 loop
		select timer.* into existing
		from public.running_timers as timer
		where timer.organization_id = target_organization_id and timer.user_id = target_user_id
		for update;

		if found then
			-- Clocking in twice (a double tap, a second phone) is not a mistake: the day clock already runs.
			if existing.kind = 'general' then
				return jsonb_build_object(
					'clocked_in', true, 'already_clocked_in', true, 'started_at', existing.started_at,
					'paused_by_visit', false
				);
			end if;
			-- A visit timer is running, and only one timer runs at a time: the day clock starts the moment
			-- that visit's timer stops.
			update public.running_timers as timer
			set resume_general = true
			where timer.organization_id = target_organization_id and timer.user_id = target_user_id;
			return jsonb_build_object(
				'clocked_in', true, 'already_clocked_in', existing.resume_general, 'started_at', null,
				'paused_by_visit', true
			);
		end if;

		insert into public.running_timers (organization_id, user_id, kind, started_by)
		values (target_organization_id, target_user_id, 'general', actor_id)
		on conflict (organization_id, user_id) do nothing
		returning * into started;

		if started.user_id is not null then
			return jsonb_build_object(
				'clocked_in', true, 'already_clocked_in', false, 'started_at', started.started_at,
				'paused_by_visit', false
			);
		end if;
		-- Another tap started a timer between the read and the insert: read it again and answer for it.
	end loop;

	raise exception 'The day clock could not be started. Try again.' using errcode = 'P0409';
end;
$$;

comment on function private.clock_in_for(uuid, uuid, uuid) is
	'Starts a person''s day clock (General time). Idempotent when already clocked in; while a visit timer runs it marks that timer to start the day clock when it stops. Checks nothing; callers decide who may clock whom in.';

revoke all on function private.clock_in_for(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function private.clock_in_for(uuid, uuid, uuid) to service_role;

create or replace function public.clock_in(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
begin
	if caller is null then
		raise exception 'You must be signed in to clock in.' using errcode = 'insufficient_privilege';
	end if;
	if not private.can_run_own_timer(target_organization_id, caller) then
		raise exception 'You do not have access to clock in.' using errcode = 'insufficient_privilege';
	end if;

	return private.clock_in_for(target_organization_id, caller, caller);
end;
$$;

create or replace function public.clock_in_member(target_organization_id uuid, target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
begin
	if caller is null then
		raise exception 'You must be signed in to clock someone in.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_has_permission(target_organization_id, caller, 'time.track_team') then
		raise exception 'You do not have access to clock team members in.' using errcode = 'insufficient_privilege';
	end if;
	if not exists (
		select 1
		from public.organization_members as member
		where member.organization_id = target_organization_id
			and member.user_id = target_user_id
			and member.status = 'active'
	) then
		raise exception 'That person is not on this team.' using errcode = 'P0404';
	end if;

	return private.clock_in_for(target_organization_id, target_user_id, caller);
end;
$$;

comment on function public.clock_in_member(uuid, uuid) is
	'A manager (time.track_team) clocks an active team member in for the day (plan § Timesheets page, Manager actions). Same behaviour as their own Clock in.';

revoke all on function public.clock_in_member(uuid, uuid) from public, anon;
grant execute on function public.clock_in_member(uuid, uuid) to authenticated, service_role;

create or replace function public.stop_timer_at(
	target_organization_id uuid,
	target_user_id uuid,
	end_day date default null,
	end_time time default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	chosen_end timestamptz;
begin
	if caller is null then
		raise exception 'You must be signed in to stop a timer.' using errcode = 'insufficient_privilege';
	end if;
	-- Someone who can correct this person's hours chooses the real end time (plan § Forgotten timers): a
	-- manager for anyone, a person who records their own hours for their own.
	if not private.can_write_general_time(target_organization_id, caller, target_user_id) then
		raise exception 'You do not have access to stop this timer.' using errcode = 'insufficient_privilege';
	end if;
	if (end_day is null) <> (end_time is null) then
		raise exception 'Choose the day and the time work ended.' using errcode = 'invalid_parameter_value';
	end if;
	if end_day is not null then
		chosen_end := private.local_instant(target_organization_id, end_day, end_time);
	end if;

	-- The day is over, like Clock out: a paused day clock does not start again.
	update public.running_timers as timer
	set resume_general = false
	where timer.organization_id = target_organization_id and timer.user_id = target_user_id and timer.resume_general;

	return private.stop_running_timer_at(target_organization_id, target_user_id, caller, true, chosen_end);
end;
$$;

comment on function public.stop_timer_at(uuid, uuid, date, time) is
	'Clocks a person out: stops whatever timer they have running, now or at a chosen day and time on the business''s clock, and nothing resumes. Needs time.track_team, or time.track_own for the caller''s own. Without a chosen end a timer over 24 hours is refused (P0410); a chosen end must be in the past, after the start and within a day of it.';

revoke all on function public.stop_timer_at(uuid, uuid, date, time) from public, anon;
grant execute on function public.stop_timer_at(uuid, uuid, date, time) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- Reading an entry's history
-- ---------------------------------------------------------------------------------------------------

-- A person's name as Timesheets shows it, also for someone who has left.
create or replace function private.member_display_name(target_organization_id uuid, target_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(
		case when member.status = 'removed' then member.display_name_at_removal end,
		nullif(btrim(profile.full_name), ''),
		member.display_name_at_removal,
		account.email
	)
	from (select target_user_id as user_id) as wanted
	left join public.organization_members as member
		on member.organization_id = target_organization_id and member.user_id = wanted.user_id
	left join public.profiles as profile on profile.id = wanted.user_id
	left join auth.users as account on account.id = wanted.user_id;
$$;

revoke all on function private.member_display_name(uuid, uuid) from public, anon, authenticated;
grant execute on function private.member_display_name(uuid, uuid) to service_role;

-- History values with the names a reader needs: the person, and the Job by number only. A Job's title can
-- belong to work the reader may not open, and the number is what tells two entries apart.
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
		)
	) end;
$$;

revoke all on function private.describe_time_values(uuid, jsonb) from public, anon, authenticated;
grant execute on function private.describe_time_values(uuid, jsonb) to service_role;

create or replace function public.time_entry_history(target_organization_id uuid, target_entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
		or (entry_owner = caller and private.member_has_permission(target_organization_id, caller, 'time.track_own'))
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
$$;

comment on function public.time_entry_history(uuid, uuid) is
	'An entry''s edit history, oldest first: who added, stopped, changed or deleted it, when, and the values before and after, with names and Job numbers. time.track_team reads anyone''s; time.track_own only the caller''s own entries.';

revoke all on function public.time_entry_history(uuid, uuid) from public, anon;
grant execute on function public.time_entry_history(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- Timesheets reads say what the reader may change
-- ---------------------------------------------------------------------------------------------------

-- A running timer is listed under its own id and notes, so it can be opened and corrected like an entry.
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
	started_at timestamptz,
	ended_at timestamptz,
	minutes integer,
	notes text,
	source text,
	is_running boolean,
	overlaps boolean
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
			entry.started_at, entry.started_at + make_interval(mins => entry.minutes) as ended_at, entry.minutes,
			entry.notes, entry.source, false as is_running
		from public.job_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.started_at >= window_start - interval '1 day'
			and entry.started_at < window_end + interval '1 day'
			and (only_user_id is null or entry.user_id = only_user_id)
		union all
		select entry.user_id, 'general', entry.id, null, null,
			entry.started_at, entry.started_at + make_interval(mins => entry.minutes), entry.minutes,
			entry.notes, entry.source, false
		from public.general_time_entries as entry
		where entry.organization_id = target_organization_id
			and entry.started_at >= window_start - interval '1 day'
			and entry.started_at < window_end + interval '1 day'
			and (only_user_id is null or entry.user_id = only_user_id)
		union all
		-- A running timer covers everything from its start until now, however long ago it started: a timer
		-- forgotten for days really does overlap whatever was typed in since.
		select timer.user_id, case when timer.kind = 'visit' then 'job' else 'general' end, timer.id,
			timer.job_id, timer.visit_id, timer.started_at, null, null, timer.notes, 'timer', true
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
		ordered.is_running,
		coalesce(ordered.latest_earlier_end - ordered.started_at >= interval '1 minute', false)
			or coalesce(coalesce(ordered.ended_at, now()) - ordered.next_start >= interval '1 minute', false)
	from ordered
	where ordered.started_at >= window_start and ordered.started_at < window_end;
$$;

comment on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) is
	'Every hour in a window for Timesheets: Job hours, General hours and running timers (is_running, no end, listed under the timer''s id), each flagged when it shares a minute or more with another of the same person''s. Checks nothing; callers decide whose rows may be read.';

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
	-- Someone limited to their own time cannot read a teammate's, and is told the same as for a stranger.
	if not (can_team or (can_own and target_user_id = caller)) then
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
$$;

comment on function public.timesheet_entries(uuid, uuid, date, date) is
	'One person''s Timesheets entries for a day or a week, oldest first, with running timers (no end, under the timer''s id), overlap flags, whether each was edited, and whether the reader may change or delete it. time.track_team reads anyone''s; time.track_own only the caller''s. A Job the reader cannot open shows its number only. At most 400 entries, flagged truncated.';

create or replace function public.timesheet_summary(
	target_organization_id uuid,
	anchor_date date default null,
	span text default 'week'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	can_team boolean;
	can_own boolean;
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
	if not (can_team or can_own) then
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
$$;

comment on function public.timesheet_summary(uuid, date, text) is
	'Timesheets for the business-time-zone day (span day) or Sunday-to-Saturday week (span week) holding anchor_date, today when null: one row per person with minutes per day, entry and overlap counts, and their running timer (with whether they are clocked in). time.track_team sees every active member who can_run_own_timer plus anyone with hours in the window or a running timer; time.track_own sees only themselves. Running timers are not in the totals: hours count once they stop.';
