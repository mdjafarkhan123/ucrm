-- Time clock Part 2 (docs/time-clock-behavior-contract.md § Timers, § Hours on the Job): a person starts a
-- timer on a visit and stops it, and the hours land once on that Job's Labor, exactly as hand-typed hours do.
--
-- 1. public.running_timers holds the one timer each person has running in a business. The primary key is
--    what makes "only one timer at a time" true, including when two phones press Start together.
-- 2. job_time_entries.source says whether hours were typed or timed.
-- 3. private.record_job_time_entry is the single place hours are written to a Job (rate copied on, costing
--    history appended). add_job_time_entry now calls it, so typed and timed hours cannot drift apart.
-- 4. start_visit_timer, stop_my_timer and my_running_timer are the commands and the read. Stopping is a
--    delete of the running row, so pressing Stop twice, or on two devices, records the hours once.
-- 5. complete_job_visit stops every timer running on the visit; job_labor lists running timers.

-- ---------------------------------------------------------------------------------------------------
-- Typed or timed
-- ---------------------------------------------------------------------------------------------------

alter table public.job_time_entries
	add column source text not null default 'manual' check (source in ('manual', 'timer'));

comment on column public.job_time_entries.source is
	'manual: typed in by a person. timer: recorded by stopping a running timer.';

-- ---------------------------------------------------------------------------------------------------
-- The running timer
-- ---------------------------------------------------------------------------------------------------

create table public.running_timers (
	organization_id uuid not null,
	user_id uuid not null,
	kind text not null default 'visit' check (kind in ('visit')),
	job_id uuid not null,
	-- Kept when the visit is later deleted or rebuilt: the timer then carries on against the Job, and its
	-- hours still land there when it stops.
	visit_id uuid,
	started_at timestamptz not null default now(),
	started_by uuid references auth.users (id) on delete set null,
	primary key (organization_id, user_id),
	constraint running_timers_member_fk foreign key (organization_id, user_id)
		references public.organization_members (organization_id, user_id) on delete cascade,
	constraint running_timers_job_fk foreign key (organization_id, job_id)
		references public.jobs (organization_id, id) on delete cascade,
	constraint running_timers_visit_fk foreign key (organization_id, visit_id)
		references public.job_visits (organization_id, id) on delete set null (visit_id)
);

comment on table public.running_timers is
	'The one timer each person has running in a business. Stopping it deletes the row and writes the hours to job_time_entries. Written only by the timer commands; read through my_running_timer and job_labor.';

create index running_timers_job_idx on public.running_timers (organization_id, job_id);
create index running_timers_visit_idx on public.running_timers (organization_id, visit_id)
	where visit_id is not null;

alter table public.running_timers enable row level security;
revoke all on table public.running_timers from anon, authenticated;

-- The same own/team split as job_time_entries, for any future direct read. Today nothing is granted, so
-- every read goes through the definer functions below.
create policy "permitted members can view running timers" on public.running_timers
	for select to authenticated
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
				and (select private.current_permission_scope('time.track_own')) <> 'none'
			)
		)
	);

-- ---------------------------------------------------------------------------------------------------
-- Who may run their own timer
-- ---------------------------------------------------------------------------------------------------

create or replace function private.can_run_own_timer(target_organization_id uuid, actor_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
	select private.member_has_permission(target_organization_id, actor_id, 'jobs.view')
		and (
			private.member_has_permission(target_organization_id, actor_id, 'time.track_own')
			or private.member_has_permission(target_organization_id, actor_id, 'time.track_team')
		);
$$;

comment on function private.can_run_own_timer(uuid, uuid) is
	'Whether a member may start and stop their own timer. The one place the timer permission is decided.';

revoke all on function private.can_run_own_timer(uuid, uuid) from public, anon;
grant execute on function private.can_run_own_timer(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- The one writer of hours onto a Job
-- ---------------------------------------------------------------------------------------------------

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
	job_closed boolean
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
		organization_id, job_id, visit_id, user_id, started_at, minutes, notes, cost_per_hour_minor, created_by,
		source
	)
	values (
		target_organization_id, target_job_id, target_visit_id, target_user_id, entry_started_at, entry_minutes,
		nullif(trim(coalesce(entry_notes, '')), ''), recorded_rate, actor_id, entry_source
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

comment on function private.record_job_time_entry(uuid, uuid, uuid, uuid, timestamptz, integer, text, text, uuid, boolean) is
	'Writes hours onto a Job: copies the person''s current cost rate onto the entry and appends the costing history row. Checks nothing; every caller decides who may record first. Used by add_job_time_entry and by stopping a timer.';

revoke all on function private.record_job_time_entry(uuid, uuid, uuid, uuid, timestamptz, integer, text, text, uuid, boolean)
	from public, anon, authenticated;
grant execute on function private.record_job_time_entry(uuid, uuid, uuid, uuid, timestamptz, integer, text, text, uuid, boolean)
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

	new_entry := private.record_job_time_entry(
		target_organization_id, target_job_id, target_visit_id, target_user_id,
		add_job_time_entry.started_at, add_job_time_entry.minutes, add_job_time_entry.notes, 'manual', caller,
		job_closed
	);

	return jsonb_build_object('id', new_entry.id, 'after_close', job_closed);
end;
$$;

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
	elapsed_seconds numeric;
	recorded_minutes integer;
	job_closed boolean;
	new_entry public.job_time_entries;
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

	elapsed_seconds := extract(epoch from (now() - running.started_at));

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

	-- Under a minute is a mistaken tap, not work (plan § Timers): nothing is recorded, and the caller says so.
	if elapsed_seconds < 60 then
		return jsonb_build_object('stopped', true, 'recorded', false, 'too_short', true);
	end if;

	recorded_minutes := least(1440, greatest(1, round(elapsed_seconds / 60)::integer));

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
		'entry_id', new_entry.id,
		'job_id', running.job_id,
		'minutes', recorded_minutes
	);
end;
$$;

comment on function private.stop_running_timer(uuid, uuid, uuid, boolean) is
	'Stops a person''s running timer and records its hours once through record_job_time_entry. Under a minute records nothing; over a day either refuses (P0410) or leaves the timer running, as the caller asks. Checks nothing; callers decide who may stop.';

revoke all on function private.stop_running_timer(uuid, uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function private.stop_running_timer(uuid, uuid, uuid, boolean) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- Commands
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

	insert into public.running_timers (organization_id, user_id, kind, job_id, visit_id, started_by)
	values (target_organization_id, caller, 'visit', target_job_id, target_visit_id, caller)
	on conflict (organization_id, user_id) do nothing
	returning * into started;

	if started.user_id is null then
		select timer.* into existing
		from public.running_timers as timer
		where timer.organization_id = target_organization_id and timer.user_id = caller;
		-- The same Start again (a double tap, a second phone) is not a mistake: the timer already runs.
		if existing.visit_id is not distinct from target_visit_id and existing.job_id = target_job_id then
			return jsonb_build_object('started_at', existing.started_at, 'already_running', true);
		end if;
		raise exception 'You already have a timer running. Stop it before starting another.'
			using errcode = 'P0409';
	end if;

	return jsonb_build_object('started_at', started.started_at, 'already_running', false);
end;
$$;

comment on function public.start_visit_timer(uuid, uuid, uuid) is
	'Starts the caller''s own timer on a visit. Needs the job to be visible and can_run_own_timer; refuses a closed job or a completed visit (P0410) and a second running timer (P0409). Starting the same visit again is idempotent.';

revoke all on function public.start_visit_timer(uuid, uuid, uuid) from public, anon;
grant execute on function public.start_visit_timer(uuid, uuid, uuid) to authenticated, service_role;

create or replace function public.stop_my_timer(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	caller uuid := (select auth.uid());
begin
	if caller is null then
		raise exception 'You must be signed in to stop a timer.' using errcode = 'insufficient_privilege';
	end if;
	-- Membership is the only gate. Someone whose permission was removed while their timer ran can still
	-- stop it; refusing would leave hours running that nobody can end but a manager.
	if not exists (
		select 1
		from public.organization_members as member
		where member.organization_id = target_organization_id
			and member.user_id = caller
			and member.status <> 'removed'
	) then
		raise exception 'You do not have access to this business.' using errcode = 'insufficient_privilege';
	end if;

	return private.stop_running_timer(target_organization_id, caller, caller, true);
end;
$$;

comment on function public.stop_my_timer(uuid) is
	'Stops the caller''s own running timer and records its hours once. A second call finds nothing and says already_stopped. Refuses a timer over 24 hours (P0410).';

revoke all on function public.stop_my_timer(uuid) from public, anon;
grant execute on function public.stop_my_timer(uuid) to authenticated, service_role;

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

	select jsonb_build_object(
		'kind', running.kind,
		'job_id', running.job_id,
		'job_number', job.job_number,
		'job_title', job.title,
		'visit_id', running.visit_id,
		'visit_date', visit.visit_date,
		'started_at', running.started_at
	) into timer
	from public.running_timers as running
	join public.jobs as job on job.organization_id = running.organization_id and job.id = running.job_id
	left join public.job_visits as visit
		on visit.organization_id = running.organization_id and visit.id = running.visit_id
	where running.organization_id = target_organization_id and running.user_id = caller;

	return jsonb_build_object(
		'timer', timer,
		'can_time', private.can_run_own_timer(target_organization_id, caller),
		-- The phone's clock may be wrong. The running duration is counted from the server's own clock.
		'server_now', now()
	);
end;
$$;

comment on function public.my_running_timer(uuid) is
	'The caller''s own running timer (or null), whether they may run one, and the server time to count from. Only ever the caller''s own row.';

revoke all on function public.my_running_timer(uuid) from public, anon;
grant execute on function public.my_running_timer(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- Completing a visit stops every timer on it
-- ---------------------------------------------------------------------------------------------------

create or replace function public.complete_job_visit(
	target_organization_id uuid,
	target_job_id uuid,
	target_visit_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'public'
as $$
declare
	caller uuid := (select auth.uid());
	current_job public.jobs;
	current_visit public.job_visits;
	remaining_incomplete integer;
	new_reminder_id uuid;
	final_visit boolean := false;
	timed_user uuid;
begin
	if caller is null then
		raise exception 'You must be signed in to complete a visit.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
		raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
	end if;
	if not private.member_has_permission(target_organization_id, caller, 'jobs.complete') then
		raise exception 'You do not have access to complete this visit.' using errcode = 'insufficient_privilege';
	end if;

	select job.* into current_job
	from public.jobs as job
	where job.organization_id = target_organization_id and job.id = target_job_id
	for update;
	if not found then
		raise exception 'That job could not be found.' using errcode = 'P0404';
	end if;
	if current_job.status = 'closed' then
		raise exception 'A closed job''s visits cannot be changed. Reopen the job first.' using errcode = 'P0410';
	end if;

	select visit.* into current_visit
	from public.job_visits as visit
	where visit.organization_id = target_organization_id
		and visit.job_id = target_job_id
		and visit.id = target_visit_id
	for update;
	if not found then
		raise exception 'That visit could not be found.' using errcode = 'P0404';
	end if;

	if current_visit.completed_at is not null then
		return jsonb_build_object(
			'applied', true, 'already_completed', true, 'revision', current_visit.revision, 'final_visit', false
		);
	end if;

	update public.job_visits
	set completed_at = now(), completed_by = caller, revision = revision + 1, updated_at = now()
	where organization_id = target_organization_id and id = target_visit_id
	returning * into current_visit;

	-- Time clock (plan § Timers): finishing the visit ends everyone's timer on it, so nobody has to press Stop
	-- first. A timer left on for more than a day stays running and flagged for a manager to correct.
	for timed_user in
		select timer.user_id
		from public.running_timers as timer
		where timer.organization_id = target_organization_id and timer.visit_id = target_visit_id
	loop
		perform private.stop_running_timer(target_organization_id, timed_user, caller, false);
	end loop;

	-- Internal to-do, raised the moment the billable event happens; private.create_invoice_reminder is the
	-- one primitive every reminder is born through (Part 11b), and it is already a no-op if one is open.
	if current_job.billing_timing = 'per_completed_visit' then
		new_reminder_id := private.create_invoice_reminder(
			target_organization_id,
			target_job_id,
			'per_visit',
			private.organization_today(target_organization_id),
			caller,
			target_visit_id
		);
	end if;

	select count(*) into remaining_incomplete
	from public.job_visits as visit
	where visit.organization_id = target_organization_id
		and visit.job_id = target_job_id
		and visit.completed_at is null;

	-- Only a one-off job asks the question. A recurring job's incomplete visits are its future occurrences,
	-- not open work to close out.
	final_visit := remaining_incomplete = 0 and current_job.job_type = 'one_off';

	insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
	values (
		target_organization_id,
		target_job_id,
		'visit_completed',
		caller,
		target_visit_id,
		jsonb_build_object('final_visit', final_visit)
	);

	return jsonb_build_object(
		'applied', true,
		'already_completed', false,
		'revision', current_visit.revision,
		'final_visit', final_visit,
		'reminder_id', new_reminder_id
	);
end;
$$;

comment on function public.complete_job_visit(uuid, uuid, uuid) is
	'Marks a visit complete. Checks jobs.complete, refuses on a closed job (P0410), is idempotent on an already-completed visit, stops every timer running on the visit (recording each once), fires the per_visit reminder when the job bills per completed visit, and reports final_visit when this was the last incomplete visit of a one-off job.';

-- ---------------------------------------------------------------------------------------------------
-- A Job's Labor shows who is on the clock for it
-- ---------------------------------------------------------------------------------------------------

create or replace function public.job_labor(target_organization_id uuid, target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'pg_catalog', 'public'
as $$
declare
	caller uuid := (select auth.uid());
	page_size constant integer := 200;
	can_cost boolean;
	can_team boolean;
	can_own boolean;
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
			and (can_team or (entry.user_id = caller and can_own))
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
		and (can_team or (timer.user_id = caller and can_own));

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
$$;
