-- Package builder P5b: what the contractor's app shows about its own access — the grace-week banner and
-- the paused screen. A paused organization is invisible to its members through row-level security, so
-- this reads past it for the caller's own active membership only, and returns contractor-safe facts.
-- Only owners and admins learn that a pause or a coming pause is about payment (Jafar, 2026-09-30).

create or replace function public.contractor_account_standing()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	membership record;
	coverage record;
	can_manage boolean;
begin
	select m.organization_id, m.role, o.name, o.lifecycle_status
	into membership
	from public.organization_members m
	join public.organizations o on o.id = m.organization_id
	where m.user_id = (select auth.uid()) and m.status = 'active'
	order by m.created_at
	limit 1;

	if membership.organization_id is null then
		return null;
	end if;
	can_manage := membership.role in ('owner', 'admin');

	if membership.lifecycle_status = 'active' then
		if can_manage then
			select * into coverage from private.organization_access_coverage(membership.organization_id);
			if coverage.covered_through < private.organization_commercial_today(membership.organization_id)
				and coverage.pauses_at > now() then
				return jsonb_build_object(
					'state', 'grace',
					'organization_name', membership.name,
					'can_manage', true,
					'covered_through', coverage.covered_through,
					'last_access_day', coverage.covered_through + 7
				);
			end if;
		end if;
		return jsonb_build_object('state', 'active', 'organization_name', membership.name, 'can_manage', can_manage);
	end if;

	return jsonb_build_object(
		'state', 'paused',
		'organization_name', membership.name,
		'can_manage', can_manage,
		'reason', case
			when not can_manage then null
			when (private.organization_nonpayment_pause(membership.organization_id)).id is not null then 'payment'
			else 'other'
		end
	);
end;
$$;

comment on function public.contractor_account_standing() is
	'The signed-in member''s own organization standing: active, grace (owners and admins only, with the last day of access), or paused (with a payment reason for owners and admins only).';

revoke all on function public.contractor_account_standing() from public, anon;
grant execute on function public.contractor_account_standing() to authenticated;
