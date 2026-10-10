-- Multi-industry platform foundation B9: a business's public forms follow Uplift's sign-off.
--
-- A form only receives answers or offers booking times while the business's "Web requests and online
-- booking" area (public_intake) is open, which means its latest decision says ready. A business with no
-- decision is closed. Businesses that existed before B8 were carried over open, so their live forms keep
-- working. Customer replies, issued quote and invoice links and payments are never checked here.

create or replace function private.organization_area_is_open(target_organization_id uuid, target_area_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce((
		select d.status = 'ready'
		from public.organization_readiness_decisions d
		where d.organization_id = target_organization_id
			and d.area_key = target_area_key
			and not exists (
				select 1 from public.organization_readiness_decisions later where later.previous_decision_id = d.id
			)
	), false);
$$;

revoke all on function private.organization_area_is_open(uuid, text) from public, anon, authenticated;
grant execute on function private.organization_area_is_open(uuid, text) to service_role;

-- Add the check to the two public form functions in place, so the rest of each function stays exactly as it
-- is. Each replacement must change exactly one place, or the migration stops.
do $$
declare
	definition text;
	changed text;
begin
	definition := pg_get_functiondef('public.submit_form_response(text,text,text,jsonb,jsonb,text[],uuid,timestamptz,timestamptz)'::regprocedure);
	changed := replace(
		definition,
		'where slug = target_organization_slug and lifecycle_status = ''active'';',
		'where slug = target_organization_slug and lifecycle_status = ''active''
    and private.organization_area_is_open(id, ''public_intake'');'
	);
	if changed = definition then
		raise exception 'submit_form_response was not changed';
	end if;
	execute changed;

	definition := pg_get_functiondef('public.get_public_form_available_slots(text,text,date,date)'::regprocedure);
	changed := replace(
		definition,
		'and o.lifecycle_status = ''active'';',
		'and o.lifecycle_status = ''active''
    and private.organization_area_is_open(o.id, ''public_intake'');'
	);
	if changed = definition then
		raise exception 'get_public_form_available_slots was not changed';
	end if;
	execute changed;
end;
$$;
