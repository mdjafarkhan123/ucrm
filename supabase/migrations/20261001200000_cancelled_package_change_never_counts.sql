-- Package builder P15: a cancelled package change never counts.
--
-- When Jafar cancels a scheduled package change, the agreement row stays (with cancelled_at) so it shows
-- in the history. private.organization_agreement_edition already skips it, but the allowance resolver
-- (rewritten in P13) and the monthly allowance window (P13) did not: once the cancelled change's start
-- date arrived, seats, email, chat, and automation limits followed the package the customer never moved
-- to, and the monthly restart day could follow its service start. Both now skip cancelled agreements.
-- Bodies are otherwise unchanged.

create or replace function public.organization_allowance(
	target_organization_id uuid,
	target_allowance_key text,
	at timestamptz default now()
)
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
security invoker
set search_path = ''
as $$
	with agreement_edition as (
		select a.edition_id
		from public.organization_package_agreements a
		where a.organization_id = target_organization_id and a.effective_from <= at and a.cancelled_at is null
		order by a.effective_from desc, a.created_at desc
		limit 1
	), allowance_feature as (
		select pa.capability_key
		from public.package_allowances pa
		where pa.allowance_key = target_allowance_key
	), feature_on as (
		select
			(select capability_key from allowance_feature) is null
			or coalesce(
				(
					select x.capability_state = 'on'
					from public.organization_package_exceptions x
					where x.organization_id = target_organization_id
						and x.capability_key = (select capability_key from allowance_feature)
						and x.starts_at <= at and x.ends_at > at
					order by x.starts_at desc, x.created_at desc
					limit 1
				),
				exists (
					select 1 from public.package_edition_capabilities c
					where c.edition_id = (select edition_id from agreement_edition)
						and c.capability_key = (select capability_key from allowance_feature)
				)
			) as value
	), exception_row as (
		select x.allowance_state, x.allowance_value
		from public.organization_package_exceptions x
		where x.organization_id = target_organization_id
			and x.allowance_key = target_allowance_key
			and x.starts_at <= at and x.ends_at > at
		order by x.starts_at desc, x.created_at desc
		limit 1
	), edition_row as (
		select ea.allowance_state, ea.allowance_value
		from public.package_edition_allowances ea
		where ea.edition_id = (select edition_id from agreement_edition)
			and ea.allowance_key = target_allowance_key
	), resolved as (
		select
			case when not (select value from feature_on) then 'not_included'
				else coalesce(x.allowance_state, e.allowance_state, 'not_included') end as state,
			case when not (select value from feature_on) then null
				when x.allowance_state is not null then x.allowance_value
				else e.allowance_value end as value,
			(select value from feature_on) and x.allowance_state is not null as from_exception
		from (select 1) as one
		left join exception_row x on true
		left join edition_row e on true
	)
	select r.state, r.value, r.state = 'unlimited', case when r.from_exception then 'override' else 'package' end
	from resolved r;
$$;

comment on function public.organization_allowance(uuid, text, timestamptz) is
	'One package allowance for an organization: not included while the allowance''s feature is off; otherwise an active exception wins over the agreed edition, and with neither it is not included. SECURITY INVOKER: row security limits a member to their own organization.';

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
				where a.organization_id = target_organization_id and a.effective_from <= at and a.cancelled_at is null
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
