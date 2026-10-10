-- Multi-industry platform foundation B6: the database's own capability check follows the experience too.
--
-- The app's access answer (organization_access_snapshot) now narrows every capability by the Organization's
-- Industry experience. Background work and SQL functions ask `private.organization_has_capability` instead,
-- so it gives the same answer: a capability is on only when the Package gives it AND the experience's
-- capability families allow it. `capability_fits_organization` now runs as its owner because the experience
-- tables are not readable by members; it answers yes or no and exposes no row.

alter function private.capability_fits_organization(uuid, text) security definer;

create or replace function private.organization_has_capability(
	target_organization_id uuid,
	target_capability_key text,
	at timestamptz
)
returns boolean
language sql
stable
set search_path = ''
as $$
	select coalesce(
		(
			select x.capability_state = 'on'
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id
				and x.capability_key = target_capability_key
				and x.starts_at <= at and x.ends_at > at
			order by x.starts_at desc, x.created_at desc
			limit 1
		),
		exists (
			select 1
			from public.package_edition_capabilities c
			where c.edition_id = private.organization_agreement_edition(target_organization_id, at)
				and c.capability_key = target_capability_key
		)
	) and private.capability_fits_organization(target_organization_id, target_capability_key);
$$;

revoke all on function private.capability_fits_organization(uuid, text) from public, anon;
grant execute on function private.capability_fits_organization(uuid, text) to authenticated, service_role;
