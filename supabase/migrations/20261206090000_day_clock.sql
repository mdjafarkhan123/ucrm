-- Time clock Part 3 (docs/time-clock-behavior-contract.md § Timers, § Forgotten timers): a person clocks in
-- and out for the day, and a visit timer pauses that day clock and resumes it when it stops.
--
-- 1. running_timers also holds the day clock, as kind 'general' with no Job. A visit timer started while
--    clocked in carries resume_general, so stopping it starts General time again at the same instant. The
--    one-row-per-person primary key still makes "only one timer at a time" true.
-- 2. public.general_time_entries holds General hours. They belong to no Job, so they never reach Job costing
--    or the accountant report, which read job_time_entries only. Timesheets (Part 4) shows both tables.
-- 3. private.stop_running_timer records General hours and resumes a paused day clock; start_visit_timer
--    pauses a running day clock; clock_in and clock_out are the day clock's commands; my_running_timer says
--    whether the person is clocked in.

-- ---------------------------------------------------------------------------------------------------
-- The day clock is a running timer with no Job
-- ---------------------------------------------------------------------------------------------------

alter table public.running_timers drop constraint running_timers_kind_check;

alter table public.running_timers
	alter column job_id drop not null,
	add column resume_general boolean not null default false,
	add constraint running_timers_kind_check check (kind in ('visit', 'general')),
	add constraint running_timers_kind_shape check (
		(kind = 'visit' and job_id is not null)
		or (kind = 'general' and job_id is null and visit_id is null and not resume_general)
	);

comment on table public.running_timers is
	'The one timer each person has running in a business: a visit timer, or the day clock (kind general, no Job). Stopping it deletes the row and records the hours. Written only by the timer commands; read through my_running_timer and job_labor.';

comment on column public.running_timers.resume_general is
	'A visit timer started while clocked in. Stopping it starts the day clock again at the same instant; clocking out clears it first.';

-- General time has no Job to be visible through, so only the own/team time split applies to it.
drop policy "permitted members can view running timers" on public.running_timers;
create policy "permitted members can view running timers" on public.running_timers
	for select to authenticated
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
				and (select private.current_permission_scope('time.track_own')) <> 'none'
			)
		)
	);

-- ---------------------------------------------------------------------------------------------------
-- General hours
-- ---------------------------------------------------------------------------------------------------

create table public.general_time_entries (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	user_id uuid not null,
	started_at timestamptz not null,
	minutes integer not null check (minutes between 1 and 1440),
	notes text check (notes is null or char_length(notes) <= 2000),
	source text not null default 'manual' check (source in ('manual', 'timer')),
	created_by uuid references auth.users (id) on delete set null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	constraint general_time_entries_organization_id_unique unique (organization_id, id),
	constraint general_time_entries_member_fk foreign key (organization_id, user_id)
		references public.organization_members (organization_id, user_id) on delete cascade
);

comment on table public.general_time_entries is
	'Paid time that belongs to no Job, such as travel or the shop: the day clock''s hours. Never part of Job costing. Timesheets shows these beside job_time_entries.';
comment on column public.general_time_entries.source is
	'manual: typed in by a person. timer: recorded by stopping the day clock.';

-- A person's own days, and everyone's days in a date range: the two ways Timesheets reads hours.
create index general_time_entries_member_started_idx
	on public.general_time_entries (organization_id, user_id, started_at desc, id desc);
create index general_time_entries_started_idx
	on public.general_time_entries (organization_id, started_at, id);

create trigger general_time_entries_set_updated_at
	before update on public.general_time_entries
	for each row execute function public.set_updated_at();

alter table public.general_time_entries enable row level security;
revoke all on table public.general_time_entries from anon, authenticated;

-- The same own/team split as job_time_entries, for any future direct read. Nothing is granted today, so
-- every read goes through definer functions.
create policy "permitted members can view general time" on public.general_time_entries
	for select to authenticated
	using (
		organization_id = (select private.current_organization())
		and (
			(select private.current_permission_scope('time.track_team')) <> 'none'
			or (
				user_id = (select auth.uid())
				and (select private.current_permission_scope('time.track_own')) <> 'none'
			)
		)
	);

-- ---------------------------------------------------------------------------------------------------
-- Stopping: the one place a running timer becomes hours
-- ---------------------------------------------------------------------------------------------------

create or replace function private.stop_running_timer(
	target_organization_id uuid,
	target_user_id uuid,
	actor_id uuid,
	refuse_over_a_day boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	running public.running_timers;
	stopped_at timestamptz := now();
	elapsed_seconds numeric;
	recorded_minutes integer;
	job_closed boolean;
	new_entry public.job_time_entries;
	new_general_id uuid;
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

	-- A day is the most one entry can hold. A timer left on longer needs someone to say when work really
	-- ended (plan § Forgotten timers), so it stays running and flagged rather than being guessed at.
	if elapsed_seconds > 86400 then
		if refuse_over_a_day then
			raise exception 'This timer has run for more than 24 hours, so it cannot be stopped as it is. Ask a manager to set the time work really ended.'
				using errcode = 'P0410';
		end if;
		return jsonb_build_object('stopped', false, 'over_a_day', true, 'recorded', false);
	end if;

	delete from public.running_timers as timer
	where timer.organization_id = target_organization_id and timer.user_id = target_user_id;

	-- Stopping a visit timer resumes the day clock it paused (plan § Timers). General time starts the instant
	-- the visit's ends, so the two never overlap and nothing between them is lost.
	if running.kind = 'visit' and running.resume_general then
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
		insert into public.general_time_entries (organization_id, user_id, started_at, minutes, source, created_by)
		values (target_organization_id, target_user_id, running.started_at, recorded_minutes, 'timer', actor_id)
		returning id into new_general_id;

		return jsonb_build_object(
			'stopped', true,
			'recorded', true,
			'kind', 'general',
			'entry_id', new_general_id,
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
		recorded_minutes, null, 'timer', actor_id, coalesce(job_closed, false)
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

comment on function private.stop_running_timer(uuid, uuid, uuid, boolean) is
	'Stops a person''s running timer and records its hours once: a visit timer through record_job_time_entry, the day clock into general_time_entries. A visit timer that paused the day clock starts it again at the same instant. Under a minute records nothing; over a day either refuses (P0410) or leaves the timer running, as the caller asks. Checks nothing; callers decide who may stop.';

-- ---------------------------------------------------------------------------------------------------
-- A visit timer pauses the day clock
-- ---------------------------------------------------------------------------------------------------

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
	existing public.running_timers;
	started public.running_timers;
	paused_day boolean := false;
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

	-- Locked so a Clock out or Stop on another phone waits for this Start rather than racing it.
	select timer.* into existing
	from public.running_timers as timer
	where timer.organization_id = target_organization_id and timer.user_id = caller
	for update;
	if found then
		if existing.kind = 'visit' then
			-- The same Start again (a double tap, a second phone) is not a mistake: the timer already runs.
			if existing.visit_id is not distinct from target_visit_id and existing.job_id = target_job_id then
				return jsonb_build_object(
					'started_at', existing.started_at, 'already_running', true,
					'day_clock_paused', existing.resume_general
				);
			end if;
			raise exception 'You already have a timer running. Stop it before starting another.'
				using errcode = 'P0409';
		end if;
		-- Clocked in: the day clock's hours so far are recorded and the visit takes over (plan § Timers). It
		-- starts again when this visit's timer stops.
		perform private.stop_running_timer(target_organization_id, caller, caller, true);
		paused_day := true;
	end if;

	insert into public.running_timers (organization_id, user_id, kind, job_id, visit_id, started_by, resume_general)
	values (target_organization_id, caller, 'visit', target_job_id, target_visit_id, caller, paused_day)
	on conflict (organization_id, user_id) do nothing
	returning * into started;

	-- Another Start won the race between the read above and this insert.
	if started.user_id is null then
		select timer.* into existing
		from public.running_timers as timer
		where timer.organization_id = target_organization_id and timer.user_id = caller;
		if existing.kind = 'visit'
			and existing.visit_id is not distinct from target_visit_id
			and existing.job_id = target_job_id then
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

comment on function public.start_visit_timer(uuid, uuid, uuid) is
	'Starts the caller''s own timer on a visit. Needs the job to be visible and can_run_own_timer; refuses a closed job or a completed visit (P0410) and a second visit timer (P0409). A running day clock is stopped, recorded and resumed when this timer stops. Starting the same visit again is idempotent.';

-- ---------------------------------------------------------------------------------------------------
-- Clock in and clock out
-- ---------------------------------------------------------------------------------------------------

create or replace function public.clock_in(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
	existing public.running_timers;
	started public.running_timers;
begin
	if caller is null then
		raise exception 'You must be signed in to clock in.' using errcode = 'insufficient_privilege';
	end if;
	if not private.can_run_own_timer(target_organization_id, caller) then
		raise exception 'You do not have access to clock in.' using errcode = 'insufficient_privilege';
	end if;

	for attempt in 1..2 loop
		select timer.* into existing
		from public.running_timers as timer
		where timer.organization_id = target_organization_id and timer.user_id = caller
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
			where timer.organization_id = target_organization_id and timer.user_id = caller;
			return jsonb_build_object(
				'clocked_in', true, 'already_clocked_in', existing.resume_general, 'started_at', null,
				'paused_by_visit', true
			);
		end if;

		insert into public.running_timers (organization_id, user_id, kind, started_by)
		values (target_organization_id, caller, 'general', caller)
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

	raise exception 'Your day clock could not be started. Try again.' using errcode = 'P0409';
end;
$$;

comment on function public.clock_in(uuid) is
	'Starts the caller''s day clock (General time). Needs can_run_own_timer. Idempotent when already clocked in; while a visit timer runs it marks that timer to start the day clock when it stops.';

revoke all on function public.clock_in(uuid) from public, anon;
grant execute on function public.clock_in(uuid) to authenticated, service_role;

create or replace function public.clock_out(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
begin
	if caller is null then
		raise exception 'You must be signed in to clock out.' using errcode = 'insufficient_privilege';
	end if;
	-- Membership is the only gate, as for stop_my_timer: someone whose permission was removed during the day
	-- can still end it.
	if not exists (
		select 1
		from public.organization_members as member
		where member.organization_id = target_organization_id
			and member.user_id = caller
			and member.status <> 'removed'
	) then
		raise exception 'You do not have access to this business.' using errcode = 'insufficient_privilege';
	end if;

	-- The working day is over (plan § Timers): a running visit timer stops too, and nothing resumes after it.
	-- stop_running_timer takes the row lock; a refusal over 24 hours rolls this back with it.
	update public.running_timers as timer
	set resume_general = false
	where timer.organization_id = target_organization_id and timer.user_id = caller and timer.resume_general;

	return private.stop_running_timer(target_organization_id, caller, caller, true);
end;
$$;

comment on function public.clock_out(uuid) is
	'Ends the caller''s working day: stops whatever timer runs (day clock or visit) and records its hours once; nothing resumes. A second call says already_stopped. Refuses a timer over 24 hours (P0410).';

revoke all on function public.clock_out(uuid) from public, anon;
grant execute on function public.clock_out(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- The person's own timer says whether they are clocked in
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
			'started_at', running.started_at,
			'day_clock_paused', running.resume_general
		),
		running.kind = 'general' or running.resume_general
	into timer, clocked_in
	from public.running_timers as running
	left join public.jobs as job on job.organization_id = running.organization_id and job.id = running.job_id
	left join public.job_visits as visit
		on visit.organization_id = running.organization_id and visit.id = running.visit_id
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
	'The caller''s own running timer (or null), whether they are clocked in for the day, whether they may run a timer, and the server time to count from. Only ever the caller''s own row.';
