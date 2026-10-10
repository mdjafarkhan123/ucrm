-- Multi-industry platform foundation B6: Workspace access.
--
-- Until now the access answer came from the Package alone. This adds the Organization's Industry experience
-- to that same answer, so menu, pages and APIs all read one result. Nothing is a second query: the access
-- snapshot every request already makes now also carries
--
--   * `experience` -- which experience governs the Organization and which capability families it makes
--     eligible: the confirmed profile when Uplift has reviewed one, otherwise the one experience the agreed
--     edition is sold to, otherwise nothing (the app then fails closed);
--   * `capability_families` -- the family of every capability, so the app can intersect the two.
--
-- Members cannot read the experience tables directly, so the answer comes from one function that only a
-- member of the Organization (or the server's service role) can ask.

create or replace function public.organization_experience_basis(target_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	allowed boolean;
	decision_count integer;
	head_row record;
	definition_row record;
	audience text[];
begin
	select coalesce((select auth.role()) = 'service_role', false) or exists (
		select 1 from public.organization_members m
		where m.organization_id = target_organization_id
			and m.user_id = (select auth.uid())
			and m.status = 'active'
	) into allowed;
	if not allowed then
		return jsonb_build_object('state', 'none', 'reason', 'not_a_member');
	end if;

	select count(*) into decision_count
	from public.organization_experience_decisions d
	where d.organization_id = target_organization_id;

	if decision_count > 0 then
		-- The head is the decision no later one replaces. More or fewer than one means the chain is broken.
		if (
			select count(*) from public.organization_experience_decisions d
			where d.organization_id = target_organization_id
				and not exists (select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id)
		) <> 1 then
			return jsonb_build_object('state', 'none', 'reason', 'unresolved_history');
		end if;
		select d.experience_key, d.definition_version into head_row
		from public.organization_experience_decisions d
		where d.organization_id = target_organization_id
			and not exists (select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id);
		select x.experience_key, x.version, x.capability_families into definition_row
		from public.industry_experience_definitions x
		where x.experience_key = head_row.experience_key and x.version = head_row.definition_version;
		if definition_row.experience_key is null then
			return jsonb_build_object('state', 'none', 'reason', 'unknown_definition');
		end if;
		return jsonb_build_object(
			'state', 'confirmed', 'experience', definition_row.experience_key,
			'definition_version', definition_row.version, 'families', to_jsonb(definition_row.capability_families));
	end if;

	-- No profile yet: judge against the one experience the agreed edition is sold to, never a guess.
	select e.experience_keys into audience
	from public.organization_package_agreements a
	join public.package_editions e on e.id = a.edition_id
	where a.organization_id = target_organization_id and a.cancelled_at is null and a.effective_from <= now()
	order by a.effective_from desc, a.created_at desc
	limit 1;
	if audience is null or cardinality(audience) <> 1 then
		return jsonb_build_object('state', 'none', 'reason', 'no_single_experience');
	end if;
	select d.experience_key, d.version, d.capability_families into definition_row
	from private.offered_experience_definitions() d
	where d.experience_key = audience[1];
	if definition_row.experience_key is null then
		return jsonb_build_object('state', 'none', 'reason', 'unknown_definition');
	end if;
	return jsonb_build_object(
		'state', 'planned', 'experience', definition_row.experience_key,
		'definition_version', definition_row.version, 'families', to_jsonb(definition_row.capability_families));
end;
$$;

revoke all on function public.organization_experience_basis(uuid) from public, anon;
grant execute on function public.organization_experience_basis(uuid) to authenticated, service_role;

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
		where a.organization_id = target_organization_id and a.effective_from <= at and a.cancelled_at is null
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
		'capability_families', coalesce((
			select jsonb_object_agg(c.capability_key, c.capability_family) from public.package_capabilities c
		), '{}'::jsonb),
		'experience', public.organization_experience_basis(target_organization_id),
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

