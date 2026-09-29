-- Package builder P3a fix: the member-facing access check could not run.
--
-- `organization_access_snapshot` and the seat, chat-widget, and automation limit functions run as the
-- signed-in member (SECURITY INVOKER, so row security applies). Their bodies called
-- `private.organization_allowance`, and members have no access to the `private` schema, so every gated
-- screen answered "Access could not be verified". The allowance resolver moves to `public`, still SECURITY
-- INVOKER, so a member reaches only their own organization's agreement, edition, and exceptions through row
-- security. `private.organization_allowance` stays as a thin alias for the trusted functions that use it.

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
		where a.organization_id = target_organization_id and a.effective_from <= at
		order by a.effective_from desc, a.created_at desc
		limit 1
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
			coalesce(x.allowance_state, e.allowance_state, 'not_included') as state,
			case when x.allowance_state is not null then x.allowance_value else e.allowance_value end as value,
			x.allowance_state is not null as from_exception
		from (select 1) as one
		left join exception_row x on true
		left join edition_row e on true
	)
	select r.state, r.value, r.state = 'unlimited', case when r.from_exception then 'override' else 'package' end
	from resolved r;
$$;

comment on function public.organization_allowance(uuid, text, timestamptz) is
	'One package allowance for an organization: an active exception wins over the agreed edition; with neither it is not included. SECURITY INVOKER: row security limits a member to their own organization.';

revoke all on function public.organization_allowance(uuid, text, timestamptz) from public, anon;
grant execute on function public.organization_allowance(uuid, text, timestamptz) to authenticated, service_role;

create or replace function private.organization_allowance(
	target_organization_id uuid,
	target_allowance_key text,
	at timestamptz
)
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	select * from public.organization_allowance(target_organization_id, target_allowance_key, at);
$$;

create or replace function public.effective_employee_seat_limit(target_organization_id uuid, at timestamptz default now())
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	select * from public.organization_allowance(target_organization_id, 'employee_seats', at);
$$;

create or replace function public.effective_website_chat_widgets_limit(target_organization_id uuid, at timestamptz default now())
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	select * from public.organization_allowance(target_organization_id, 'website_chat_widgets', at);
$$;

create or replace function public.effective_automation_limits(target_organization_id uuid, at timestamptz default now())
returns table (limit_key text, state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	select 'automation_active_recipes'::text, a.state, a.value, a.is_unlimited, a.source
	from public.organization_allowance(target_organization_id, 'automation_active_recipes', at) a
	union all
	select s.limit_key, s.limit_state, s.limit_value, s.limit_state = 'unlimited', 'platform'
	from public.platform_automation_safety_limits s
	order by 1;
$$;

create or replace function public.organization_access_snapshot(
	target_organization_id uuid,
	target_user_id uuid default null,
	at timestamptz default now()
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
	with org as (
		select o.id, o.name, o.slug, o.lifecycle_status
		from public.organizations o
		where o.id = target_organization_id
	),
	agreement as (
		select a.id, a.edition_id, a.billing_interval, a.agreed_price_usd_cents, a.offer_terms,
			a.service_anchor_date, a.effective_from
		from public.organization_package_agreements a
		where a.organization_id = target_organization_id and a.effective_from <= at
		order by a.effective_from desc, a.created_at desc
		limit 1
	),
	edition as (
		select e.id, e.package_id, e.edition_number, e.status, e.name, e.promise
		from public.package_editions e
		where e.id = (select edition_id from agreement)
	),
	package as (
		select p.id, p.slug, p.visibility, p.archived_at
		from public.packages p
		where p.id = (select package_id from edition)
	),
	membership as (
		select m.user_id, m.role
		from public.organization_members m
		where m.organization_id = target_organization_id
			and m.user_id = target_user_id
	)
	select case when not exists (select 1 from org) then null else jsonb_build_object(
		'organization', (select to_jsonb(org) from org),
		'agreement', (select to_jsonb(agreement) from agreement),
		'edition', (select to_jsonb(edition) from edition),
		'package', (select to_jsonb(package) from package),
		'capabilities', coalesce((
			select jsonb_agg(c.capability_key order by c.sort_order) from public.package_capabilities c
		), '[]'::jsonb),
		'edition_capabilities', coalesce((
			select jsonb_agg(ec.capability_key)
			from public.package_edition_capabilities ec
			where ec.edition_id = (select edition_id from agreement)
		), '[]'::jsonb),
		'capability_exceptions', coalesce((
			select jsonb_agg(jsonb_build_object(
				'capability_key', x.capability_key, 'state', x.capability_state,
				'starts_at', x.starts_at, 'ends_at', x.ends_at, 'reason', x.reason)
				order by x.starts_at desc, x.created_at desc)
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id and x.capability_key is not null
				and x.starts_at <= at and x.ends_at > at
		), '[]'::jsonb),
		'allowance_exceptions', coalesce((
			select jsonb_agg(jsonb_build_object(
				'allowance_key', x.allowance_key, 'state', x.allowance_state, 'value', x.allowance_value,
				'starts_at', x.starts_at, 'ends_at', x.ends_at)
				order by x.starts_at desc, x.created_at desc)
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id and x.allowance_key is not null
				and x.starts_at <= at and x.ends_at > at
		), '[]'::jsonb),
		'commercial_state', (
			select jsonb_build_object(
				'paid_through_date', cs.paid_through_date, 'paid_through_source', cs.paid_through_source,
				'grace_ends_at', cs.grace_ends_at)
			from public.organization_commercial_state cs
			where cs.organization_id = target_organization_id
		),
		'commercial_settings', (
			select jsonb_build_object('commercial_timezone', st.commercial_timezone)
			from public.organization_commercial_settings st
			where st.organization_id = target_organization_id
		),
		-- Free access is rebuilt in package-builder P5; until then the old grants are still read.
		'free_access_events', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', fe.id, 'target_grant_id', fe.target_grant_id, 'action', fe.action,
				'starts_at', fe.starts_at, 'access_until_date', fe.access_until_date,
				'occurred_at', fe.occurred_at))
			from public.organization_free_access_events fe
			where fe.organization_id = target_organization_id
		), '[]'::jsonb),
		'employee_seat_limit', (
			select to_jsonb(l) from public.organization_allowance(target_organization_id, 'employee_seats', at) l
		),
		'website_chat_widgets_limit', (
			select to_jsonb(l) from public.organization_allowance(target_organization_id, 'website_chat_widgets', at) l
		),
		'marketing_email_limit', (
			select to_jsonb(l) from public.organization_allowance(target_organization_id, 'marketing_email_recipients', at) l
		),
		'membership', (select to_jsonb(membership) from membership),
		'role_permissions', coalesce((
			select jsonb_agg(jsonb_build_object('permission_key', rp.permission_key, 'access_scope', rp.access_scope))
			from public.role_permissions rp
			where rp.role = (select role from membership)
		), '[]'::jsonb),
		'member_permission_overrides', coalesce((
			select jsonb_agg(jsonb_build_object(
				'permission_key', mo.permission_key, 'override_state', mo.override_state,
				'access_scope', mo.access_scope))
			from public.organization_member_permission_overrides mo
			where mo.organization_id = target_organization_id
				and mo.user_id = target_user_id
		), '[]'::jsonb)
	) end;
$$;
