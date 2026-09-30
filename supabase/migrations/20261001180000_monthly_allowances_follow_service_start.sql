-- Package builder P13: email and website chat allowances restart on the package's service start day.
--
-- 1. The monthly window is counted from the agreement's service start day (ADR 0003 decision 7), on
--    monthly and yearly packages alike, instead of the day the organization was created. Organizations
--    without a recorded service start keep their creation day. Access comes from the package coverage
--    rule (paid-through or started free access, plus the grace week), so grace-week usage lands in the new
--    month and confirming a late payment never opens a second fresh month.
-- 2. The window is month-end safe: a service start on the 31st restarts on the last day of shorter months,
--    and the day of the restart is inside the new window (the old age() arithmetic left it uncovered).
-- 3. A new period never overlaps the previous one, and the hourly sweep opens next month's periods two
--    hours before the restart, so website chats are not refused and email does not wait at the boundary.
-- 4. The protected essential-email reserve is always 10% of the operational email allowance (Jafar,
--    2026-09-30). It is no longer a separate package allowance.

-- ---------------------------------------------------------------------------------------------------
-- 1–2. The window.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.current_communication_allowance_window(
	target_organization_id uuid,
	at timestamptz default now()
)
returns table (window_starts_at timestamptz, window_ends_at timestamptz, commercial_event_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
	with zone as (
		select coalesce((select s.commercial_timezone from public.organization_commercial_settings s
			where s.organization_id = target_organization_id), 'UTC') as name
	), organization as (
		select o.id, o.created_at
		from public.organizations o
		where o.id = target_organization_id and o.lifecycle_status = 'active'
	), today as (
		select (at at time zone (select name from zone))::date as value
	), anchor as (
		select coalesce(
			(
				select a.service_anchor_date
				from public.organization_package_agreements a
				where a.organization_id = target_organization_id and a.effective_from <= at
				order by a.effective_from desc, a.created_at desc
				limit 1
			),
			(select (o.created_at at time zone (select name from zone))::date from organization o)
		) as value
	), month_count as (
		-- Whole months from the anchor to today, stepped back one when this month's restart day is still ahead.
		select m.value - case
			when ((select value from anchor) + make_interval(months => m.value))::date > (select value from today)
			then 1 else 0 end as value
		from (
			select (
				(extract(year from (select value from today)) - extract(year from (select value from anchor))) * 12
				+ extract(month from (select value from today)) - extract(month from (select value from anchor))
			)::integer as value
		) m
	)
	select
		(((select value from anchor) + make_interval(months => (select value from month_count)))::timestamp
			at time zone (select name from zone)),
		(((select value from anchor) + make_interval(months => (select value from month_count) + 1))::timestamp
			at time zone (select name from zone)),
		(select st.last_event_id from public.organization_commercial_state st
			where st.organization_id = target_organization_id)
	from organization
	cross join private.organization_access_coverage(target_organization_id, at) coverage
	where (select value from anchor) is not null
		and coverage.pauses_at > at;
$$;

comment on function private.current_communication_allowance_window(uuid, timestamptz) is
	'The monthly allowance window containing `at`: whole months from the agreement''s service start day (the organization''s creation day when none is recorded), in its commercial time zone. No row when the organization is inactive or not covered at `at`.';

-- ---------------------------------------------------------------------------------------------------
-- 3. Opening periods. A new period starts where the previous one ended when the window would overlap it.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.ensure_communication_allowance_periods(
	target_organization_id uuid,
	at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	allowance_window record;
	previous_end timestamptz;
begin
	select * into allowance_window
	from private.current_communication_allowance_window(target_organization_id, at);
	if not found then
		return;
	end if;

	if not exists (
		select 1 from public.communication_email_allowance_periods p
		where p.organization_id = target_organization_id and p.starts_at <= at and p.ends_at > at
	) then
		select max(p.ends_at) into previous_end
		from public.communication_email_allowance_periods p
		where p.organization_id = target_organization_id and p.ends_at <= at;
		insert into public.communication_email_allowance_periods (
			organization_id, starts_at, ends_at, opened_by_commercial_event_id
		) values (
			target_organization_id,
			greatest(allowance_window.window_starts_at, coalesce(previous_end, allowance_window.window_starts_at)),
			allowance_window.window_ends_at,
			allowance_window.commercial_event_id
		)
		on conflict (organization_id, starts_at) do nothing;
	end if;

	if not exists (
		select 1 from public.website_chat_allowance_periods p
		where p.organization_id = target_organization_id and p.starts_at <= at and p.ends_at > at
	) then
		select max(p.ends_at) into previous_end
		from public.website_chat_allowance_periods p
		where p.organization_id = target_organization_id and p.ends_at <= at;
		insert into public.website_chat_allowance_periods (
			organization_id, starts_at, ends_at, opened_by_commercial_event_id
		) values (
			target_organization_id,
			greatest(allowance_window.window_starts_at, coalesce(previous_end, allowance_window.window_starts_at)),
			allowance_window.window_ends_at,
			allowance_window.commercial_event_id
		)
		on conflict (organization_id, starts_at) do nothing;
	end if;
end;
$$;

comment on function private.ensure_communication_allowance_periods(uuid, timestamptz) is
	'Opens the allowance window containing `at` for email and website chat, if the organization is covered then and no period already contains it. Never overlaps an earlier period. Idempotent.';

create or replace function private.ensure_marketing_allowance_period(
	target_organization_id uuid,
	at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	allowance_window record;
	previous_end timestamptz;
	period_id uuid;
begin
	-- The returned row is locked, so it is also this organization's launch queue: a second launch waits
	-- here instead of reading an allowance total the first launch is about to change.
	select p.id into period_id
	from public.marketing_email_allowance_periods p
	where p.organization_id = target_organization_id and p.starts_at <= at and p.ends_at > at
	for update;
	if found then
		return period_id;
	end if;

	select * into allowance_window
	from private.current_communication_allowance_window(target_organization_id, at);
	if not found then
		return null;
	end if;

	select max(p.ends_at) into previous_end
	from public.marketing_email_allowance_periods p
	where p.organization_id = target_organization_id and p.ends_at <= at;

	insert into public.marketing_email_allowance_periods (
		organization_id, starts_at, ends_at, opened_by_commercial_event_id
	) values (
		target_organization_id,
		greatest(allowance_window.window_starts_at, coalesce(previous_end, allowance_window.window_starts_at)),
		allowance_window.window_ends_at,
		allowance_window.commercial_event_id
	) on conflict (organization_id, starts_at) do nothing;

	select p.id into period_id
	from public.marketing_email_allowance_periods p
	where p.organization_id = target_organization_id and p.starts_at <= at and p.ends_at > at
	for update;

	return period_id;
end;
$$;

-- The sweep opens the current periods and, two hours ahead, the next ones, so the restart has no gap.
create or replace function private.open_due_communication_allowance_periods()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
	due record;
	opened_count integer := 0;
begin
	for due in
		select o.id, moment.at
		from public.organizations o
		cross join (values (now()), (now() + interval '2 hours')) as moment (at)
		where o.lifecycle_status = 'active'
			and (
				not exists (
					select 1 from public.website_chat_allowance_periods p
					where p.organization_id = o.id and p.starts_at <= moment.at and p.ends_at > moment.at
				)
				or not exists (
					select 1 from public.communication_email_allowance_periods p
					where p.organization_id = o.id and p.starts_at <= moment.at and p.ends_at > moment.at
				)
			)
		order by o.id, moment.at
	loop
		perform private.ensure_communication_allowance_periods(due.id, due.at);
		opened_count := opened_count + 1;
	end loop;

	return opened_count;
end;
$$;

comment on function private.open_due_communication_allowance_periods() is
	'Hourly sweep: opens every active organization''s current allowance periods and, two hours ahead, the next ones, so a monthly restart never leaves chat or email without a period.';

-- ---------------------------------------------------------------------------------------------------
-- 4. The essential-email reserve is 10% of the operational email allowance.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.essential_email_reserve(operational_value integer)
returns integer
language sql
immutable
set search_path = ''
as $$
	select ceil(operational_value * 0.10)::integer;
$$;

comment on function private.essential_email_reserve(integer) is
	'The protected essential-email reserve for an operational email allowance: 10%, rounded up (Jafar, 2026-09-30).';

create or replace function private.resolve_communication_email_allowance(target_organization_id uuid, at timestamptz default now())
returns table (
	period_id uuid, period_starts_at timestamptz, period_ends_at timestamptz,
	operational_limit_state text, operational_limit_value integer,
	essential_limit_state text, essential_limit_value integer
)
language sql
stable
security definer
set search_path = ''
as $$
	with active_period as (
		select p.id, p.starts_at, p.ends_at
		from public.communication_email_allowance_periods p
		where p.organization_id = target_organization_id and p.starts_at <= at and p.ends_at > at
		order by p.starts_at desc
		limit 1
	)
	select period.id, period.starts_at, period.ends_at,
		operational.state, operational.value,
		operational.state, case when operational.state = 'numeric' then private.essential_email_reserve(operational.value) end
	from active_period period
	cross join private.organization_allowance(target_organization_id, 'operational_email_recipients', at) operational;
$$;

create or replace function public.get_organization_communication_email_allowances(
	target_organization_id uuid,
	at timestamptz default now()
)
returns table (
	limit_key text, period_id uuid, period_starts_at timestamptz, period_ends_at timestamptz,
	effective_state text, effective_value integer, effective_source text,
	fallback_state text, fallback_value integer,
	override_state text, override_value integer, override_starts_at timestamptz, override_expires_at timestamptz,
	override_reason text, override_author_email text
)
language sql
stable
security definer
set search_path = ''
as $$
	with period as (
		select p.period_id, p.period_starts_at, p.period_ends_at
		from private.resolve_communication_email_allowance(target_organization_id, at) p
	), operational as (
		select
			period.period_id, period.period_starts_at, period.period_ends_at,
			effective.state, effective.value, effective.source,
			edition_allowance.allowance_state as fallback_state, edition_allowance.allowance_value as fallback_value,
			x.allowance_state, x.allowance_value, x.starts_at, x.ends_at, x.reason, x.actor_owner_email
		from private.organization_allowance(target_organization_id, 'operational_email_recipients', at) effective
		left join period on true
		left join public.package_edition_allowances edition_allowance
			on edition_allowance.edition_id = private.organization_agreement_edition(target_organization_id, at)
			and edition_allowance.allowance_key = 'operational_email_recipients'
		left join lateral (
			select * from public.organization_package_exceptions x
			where x.organization_id = target_organization_id
				and x.allowance_key = 'operational_email_recipients' and x.ends_at > at
			order by x.starts_at desc, x.created_at desc
			limit 1
		) x on true
	)
	-- The essential reserve follows the operational allowance; it has no exception of its own.
	select 'essential_email_recipients'::text, o.period_id, o.period_starts_at, o.period_ends_at,
		o.state, case when o.state = 'numeric' then private.essential_email_reserve(o.value) end, o.source,
		o.fallback_state, case when o.fallback_state = 'numeric' then private.essential_email_reserve(o.fallback_value) end,
		null::text, null::integer, null::timestamptz, null::timestamptz, null::text, null::text
	from operational o
	union all
	select 'operational_email_recipients'::text, o.period_id, o.period_starts_at, o.period_ends_at,
		o.state, o.value, o.source, o.fallback_state, o.fallback_value,
		o.allowance_state, o.allowance_value, o.starts_at, o.ends_at, o.reason, o.actor_owner_email
	from operational o;
$$;

-- The separate allowance goes. Published editions' terms are frozen, so their rows are removed with the
-- freeze trigger off for this one schema change; no exception uses the key.
alter table public.package_edition_allowances disable trigger package_edition_allowances_frozen;
delete from public.package_edition_allowances where allowance_key = 'essential_email_recipients';
alter table public.package_edition_allowances enable trigger package_edition_allowances_frozen;
delete from public.package_allowances where allowance_key = 'essential_email_recipients';
