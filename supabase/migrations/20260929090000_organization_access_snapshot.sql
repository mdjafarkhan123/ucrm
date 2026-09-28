-- Every gated API resolved a member's access with ~17 Data API calls in six sequential rounds (measured
-- 2026-09-10: ~136 access reads for one Jobs page). This returns the same rows in one call. It is
-- SECURITY INVOKER, so the caller's own RLS decides what it can see exactly as the separate reads did,
-- and it caches nothing: the TypeScript resolver still applies every rule to these rows.
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
		select o.id, o.name, o.slug, o.lifecycle_status, o.package_key, o.scheduled_package_key,
			o.scheduled_package_effective_at
		from public.organizations o
		where o.id = target_organization_id
	),
	assignment as (
		select a.package_version_id, a.effective_at
		from public.organization_package_assignments a
		where a.organization_id = target_organization_id
		order by a.effective_at desc, a.id desc
		limit 1
	),
	version as (
		select v.id, v.package_id, v.version_number, v.display_name, v.public_description,
			v.price_usd_cents, v.currency, v.billing_period, v.status
		from public.platform_package_versions v
		where v.id = (select package_version_id from assignment)
	),
	membership as (
		select m.user_id, m.role
		from public.organization_members m
		where m.organization_id = target_organization_id
			and m.user_id = target_user_id
	)
	select case when not exists (select 1 from org) then null else jsonb_build_object(
		'organization', (select to_jsonb(org) from org),
		'assignment', (select to_jsonb(assignment) from assignment),
		'package_version', (select to_jsonb(version) from version),
		-- Versioned: the one package the version belongs to. Legacy: every package, keyed later by
		-- the organization's current or scheduled key.
		'platform_packages', coalesce((
			select jsonb_agg(to_jsonb(p))
			from (
				select pp.package_id, pp.package_key, pp.display_name, pp.sort_order, pp.status,
					pp.public_description, pp.price_usd_cents, pp.currency, pp.billing_period
				from public.platform_packages pp
				where not exists (select 1 from assignment)
					or pp.package_id = (select package_id from version)
			) p
		), '[]'::jsonb),
		'features', coalesce((
			select jsonb_agg(jsonb_build_object('feature_key', f.feature_key, 'description', f.description))
			from public.features f
		), '[]'::jsonb),
		'package_features', coalesce((
			select jsonb_agg(jsonb_build_object('package_key', pf.package_key, 'feature_key', pf.feature_key))
			from public.package_features pf
			where not exists (select 1 from assignment)
		), '[]'::jsonb),
		'package_version_features', coalesce((
			select jsonb_agg(jsonb_build_object(
				'package_version_id', vf.package_version_id, 'feature_key', vf.feature_key))
			from public.platform_package_version_features vf
			where vf.package_version_id = (select package_version_id from assignment)
		), '[]'::jsonb),
		'feature_overrides', coalesce((
			select jsonb_agg(jsonb_build_object(
				'feature_key', fo.feature_key, 'override_state', fo.override_state,
				'starts_at', fo.starts_at, 'expires_at', fo.expires_at, 'reason', fo.reason,
				'is_legacy_import', fo.is_legacy_import))
			from public.organization_feature_overrides fo
			where fo.organization_id = target_organization_id
		), '[]'::jsonb),
		'limit_overrides', coalesce((
			select jsonb_agg(jsonb_build_object(
				'limit_key', lo.limit_key, 'limit_state', lo.limit_state, 'limit_value', lo.limit_value,
				'is_unlimited', lo.is_unlimited, 'starts_at', lo.starts_at, 'expires_at', lo.expires_at))
			from public.organization_limit_overrides lo
			where lo.organization_id = target_organization_id
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
		'free_access_events', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', fe.id, 'target_grant_id', fe.target_grant_id, 'action', fe.action,
				'starts_at', fe.starts_at, 'access_until_date', fe.access_until_date,
				'occurred_at', fe.occurred_at))
			from public.organization_free_access_events fe
			where fe.organization_id = target_organization_id
		), '[]'::jsonb),
		'employee_seat_limit', (
			select to_jsonb(l) from public.effective_employee_seat_limit(target_organization_id, at) l limit 1
		),
		'website_chat_widgets_limit', (
			select to_jsonb(l) from public.effective_website_chat_widgets_limit(target_organization_id, at) l limit 1
		),
		'marketing_email_limit', (
			select to_jsonb(l) from public.effective_marketing_email_limit(target_organization_id, at) l limit 1
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

revoke all on function public.organization_access_snapshot(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.organization_access_snapshot(uuid, uuid, timestamptz) to authenticated, service_role;
