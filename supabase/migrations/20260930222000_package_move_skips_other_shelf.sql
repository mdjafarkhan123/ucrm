-- Package builder P7: the Packages page lists current and archived packages apart, so moving a package
-- swaps it with the nearest package on the same list. An archived package in between no longer makes a
-- move look like it did nothing.

create or replace function public.move_package(
	target_package_id uuid,
	direction text,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	ordered uuid[];
	shelf boolean[];
	position_now integer;
	neighbour_position integer;
	neighbour_id uuid;
	step integer := case when direction = 'up' then -1 else 1 end;
begin
	if direction not in ('up', 'down') then
		raise exception 'Choose up or down.' using errcode = 'check_violation';
	end if;

	perform 1 from public.packages p order by p.id for update;
	select array_agg(p.id order by p.display_order, p.created_at, p.id),
		array_agg(p.archived_at is not null order by p.display_order, p.created_at, p.id)
	into ordered, shelf
	from public.packages p;
	position_now := array_position(ordered, target_package_id);
	if position_now is null then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;

	neighbour_position := position_now + step;
	while neighbour_position between 1 and cardinality(ordered)
		and shelf[neighbour_position] <> shelf[position_now] loop
		neighbour_position := neighbour_position + step;
	end loop;
	if neighbour_position < 1 or neighbour_position > cardinality(ordered) then
		return jsonb_build_object('applied', false);
	end if;
	neighbour_id := ordered[neighbour_position];
	ordered[neighbour_position] := target_package_id;
	ordered[position_now] := neighbour_id;

	update public.packages p set display_order = o.position
	from unnest(ordered) with ordinality as o (id, position)
	where p.id = o.id and p.display_order <> o.position;

	insert into public.package_catalog_events (package_id, event_type, detail, actor_email)
	values (target_package_id, 'moved', jsonb_build_object('direction', direction), trim(actor_owner_email));

	if private.package_is_listed(target_package_id) and private.package_is_listed(neighbour_id) then
		perform private.flag_package_website_update(target_package_id);
	end if;
	return jsonb_build_object('applied', true);
end;
$$;
