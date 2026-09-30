-- Package builder P8b: what the Access tab on Jafar's organization page shows. For each feature and limit,
-- the package's value, the exception running now (if any), the result, and — for counted limits — what is
-- in use. It reads the same agreement and exceptions the app enforces, so the tab never guesses.

create or replace function public.owner_organization_entitlements(target_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	with edition as (
		select private.organization_agreement_edition(target_organization_id, now()) as id
	),
	capability_exceptions as (
		select distinct on (x.capability_key) x.capability_key, x.capability_state, x.ends_at
		from public.organization_package_exceptions x
		where x.organization_id = target_organization_id and x.capability_key is not null
			and x.starts_at <= now() and x.ends_at > now()
		order by x.capability_key, x.starts_at desc, x.created_at desc
	),
	allowance_exceptions as (
		select distinct on (x.allowance_key) x.allowance_key, x.allowance_state, x.allowance_value, x.ends_at
		from public.organization_package_exceptions x
		where x.organization_id = target_organization_id and x.allowance_key is not null
			and x.starts_at <= now() and x.ends_at > now()
		order by x.allowance_key, x.starts_at desc, x.created_at desc
	)
	select jsonb_build_object(
		'capabilities', (
			select coalesce(jsonb_agg(jsonb_build_object(
				'key', c.capability_key, 'label', c.label, 'description', c.description, 'kind', c.kind,
				'in_package', ec.capability_key is not null,
				'exception', case when x.capability_key is null then null
					else jsonb_build_object('state', x.capability_state, 'ends_at', x.ends_at) end,
				'effective', coalesce(x.capability_state = 'on', ec.capability_key is not null)
			) order by c.sort_order), '[]'::jsonb)
			from public.package_capabilities c
			left join public.package_edition_capabilities ec
				on ec.edition_id = (select id from edition) and ec.capability_key = c.capability_key
			left join capability_exceptions x on x.capability_key = c.capability_key
		),
		'allowances', (
			select coalesce(jsonb_agg(jsonb_build_object(
				'key', a.allowance_key, 'label', a.label, 'unit', a.unit, 'resets_monthly', a.resets_monthly,
				'package', jsonb_build_object(
					'state', coalesce(ea.allowance_state, 'not_included'), 'value', ea.allowance_value
				),
				'exception', case when x.allowance_key is null then null
					else jsonb_build_object('state', x.allowance_state, 'value', x.allowance_value, 'ends_at', x.ends_at) end,
				'in_use', private.package_allowance_in_use(target_organization_id, a.allowance_key)
			) order by a.sort_order), '[]'::jsonb)
			from public.package_allowances a
			left join public.package_edition_allowances ea
				on ea.edition_id = (select id from edition) and ea.allowance_key = a.allowance_key
			left join allowance_exceptions x on x.allowance_key = a.allowance_key
		)
	)
	from public.organizations o
	where o.id = target_organization_id;
$$;

revoke all on function public.owner_organization_entitlements(uuid) from public, anon, authenticated;
grant execute on function public.owner_organization_entitlements(uuid) to service_role;
