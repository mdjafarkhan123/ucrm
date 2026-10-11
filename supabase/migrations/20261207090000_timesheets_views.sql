-- Time clock Part 4 (docs/time-clock-behavior-contract.md § Timesheets page): the Timesheets page shows
-- everyone's hours for a day or a week, and one person's entries when their row is opened.
--
-- 1. private.timesheet_rows is the one list of a window's hours: Job hours (job_time_entries, typed or
--    timed), General hours (general_time_entries) and the timers still running. It flags an entry that
--    overlaps another of the same person's by a minute or more.
-- 2. public.timesheet_summary is the page itself: one row per person with a total for each day, how many
--    entries overlap, and the timer they have running now. Its size is people x days, never entries.
-- 3. public.timesheet_entries is one person's entries for the same window, read when their row is opened.
--
-- No new index: both tables already have (organization_id, started_at, id) for everyone's window and
-- (organization_id, user_id, started_at desc, id desc) for one person's.

-- ---------------------------------------------------------------------------------------------------
-- A window's hours, with overlaps flagged
-- ---------------------------------------------------------------------------------------------------

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
		select timer.user_id, case when timer.kind = 'visit' then 'job' else 'general' end, null,
			timer.job_id, timer.visit_id, timer.started_at, null, null, null, 'timer', true
		from public.running_timers as timer
		where timer.organization_id = target_organization_id
			and timer.started_at < window_end + interval '1 day'
			and (only_user_id is null or timer.user_id = only_user_id)
	),
	ordered as (
		select hours.*,
			max(coalesce(hours.ended_at, now())) over (
				partition by hours.user_id
				order by hours.started_at, hours.entry_id nulls last
				rows between unbounded preceding and 1 preceding
			) as latest_earlier_end,
			lead(hours.started_at) over (
				partition by hours.user_id
				order by hours.started_at, hours.entry_id nulls last
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
	'Every hour in a window for Timesheets: Job hours, General hours and running timers (is_running, no end), each flagged when it shares a minute or more with another of the same person''s. Checks nothing; callers decide whose rows may be read.';

revoke all on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;
grant execute on function private.timesheet_rows(uuid, timestamptz, timestamptz, uuid) to service_role;

-- The business's own days. Hours belong to the day their timer started there (plan § Timers).
create or replace function private.organization_timezone(target_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(
		(
			select nullif(btrim(settings.timezone), '')
			from public.organization_settings as settings
			where settings.organization_id = target_organization_id
		),
		'UTC'
	);
$$;

comment on function private.organization_timezone(uuid) is
	'The business''s time zone name, or UTC when none is set. Definer because organization_settings is gated to settings.business.view and every member''s hours are dated by it.';

revoke all on function private.organization_timezone(uuid) from public, anon;
grant execute on function private.organization_timezone(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- The page: one row per person
-- ---------------------------------------------------------------------------------------------------

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
						'kind', timer.kind,
						'job_id', timer.job_id,
						'job_number', job.job_number,
						'started_at', timer.started_at,
						'started_on', (timer.started_at at time zone zone)::date,
						'long_running', now() - timer.started_at > interval '12 hours'
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
		'people', people
	);
end;
$$;

comment on function public.timesheet_summary(uuid, date, text) is
	'Timesheets for the business-time-zone day (span day) or Sunday-to-Saturday week (span week) holding anchor_date, today when null: one row per person with minutes per day, entry and overlap counts, and their running timer. time.track_team sees every active member who can_run_own_timer plus anyone with hours in the window or a running timer; time.track_own sees only themselves. Running timers are not in the totals: hours count once they stop.';

revoke all on function public.timesheet_summary(uuid, date, text) from public, anon;
grant execute on function public.timesheet_summary(uuid, date, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- One person's entries, read when their row is opened
-- ---------------------------------------------------------------------------------------------------

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
					'job', case when listed.job_id is null then null else jsonb_build_object(
						'id', listed.job_id,
						'number', job.job_number,
						'visible', listed.job_visible,
						'title', case when listed.job_visible then job.title end,
						'client_name', case when listed.job_visible then client.display_name end
					) end,
					'visit_date', case when listed.job_visible then visit.visit_date end
				)
				order by listed.started_at, listed.entry_id nulls last
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
		order by hours.started_at, hours.entry_id nulls last
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
	'One person''s Timesheets entries for a day or a week, oldest first, with running timers (no end) and overlap flags. time.track_team reads anyone''s; time.track_own only the caller''s. A Job the reader cannot open shows its number only. At most 400 entries, flagged truncated.';

revoke all on function public.timesheet_entries(uuid, uuid, date, date) from public, anon;
grant execute on function public.timesheet_entries(uuid, uuid, date, date) to authenticated, service_role;
