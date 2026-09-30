-- Package builder P13: an allowance counts only while its feature is on.
--
-- Website chat widgets, accepted website chats, and marketing email belong to a feature. A limit
-- exception used to work even when the package (or a feature exception) left that feature out, so a
-- website could still open chats nobody on the team was allowed to answer. The one allowance resolver now
-- answers "not included" whenever the allowance's feature is off, using the same rule as
-- private.organization_has_capability: the newest active feature exception wins, else the agreed edition.
-- It stays SECURITY INVOKER and names nothing in `private`, because members call it.

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
