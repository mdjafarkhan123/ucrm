-- Client onboarding A2: Jafar's list of the services Uplift sells, and package editions that tick them.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §2.1 and
-- docs/package-builder-behavior-contract.md §Included services. Jafar keeps one service list (Website, Google
-- Business Profile, Calls and texting, Reviews, Marketing, and any he adds). Each package edition picks services
-- from it with its own customer-facing wording, frozen with the edition. The setup wizard (A4) shows a stage
-- when the client's edition includes that stage's service, so the service key is what the wizard reads.
--
-- Shape: each `package_editions.included_services` entry gains `service_key`. The array is already frozen with a
-- published edition by `package_editions_frozen`, and every reader and copier passes it through whole, so no
-- other function changes. A service is never deleted, only archived: a frozen edition may still name it.
-- Renaming a service changes Jafar's list only; the wording a published edition promised stays as it was.

-- 1. The list ---------------------------------------------------------------------------------------------

create table public.package_services (
	-- Stable once created; setup stages and frozen editions refer to it, so a rename never changes it.
	service_key text primary key check (service_key ~ '^[a-z][a-z0-9_]{1,59}$'),
	name text not null check (char_length(trim(name)) between 2 and 80),
	-- The wording a package starts from when Jafar ticks the service. Each edition keeps its own copy.
	description text not null default '' check (char_length(description) <= 300),
	sort_order integer not null,
	-- No longer offered in new packages. Editions that already include it keep it.
	archived_at timestamptz,
	updated_by_email text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create unique index package_services_name_idx on public.package_services (lower(trim(name)));

comment on table public.package_services is
	'The services Uplift sells. Package editions tick them in included_services; setup stages show by them.';

create trigger package_services_set_updated_at before update on public.package_services
	for each row execute function public.set_updated_at();

alter table public.package_services enable row level security;
revoke all on public.package_services from anon, authenticated;
grant all on public.package_services to service_role;

insert into public.package_services (service_key, name, description, sort_order) values
	('website', 'Premium website',
		'A premium, mobile-friendly website built, hosted and looked after by Uplift, with on-site SEO, on your own domain.', 1),
	('google_profile', 'Google Business Profile management',
		'Uplift sets up, improves and keeps your Google Business Profile up to date. You stay the owner.', 2),
	('calls_texting', 'Calls and texting',
		'A business number, call forwarding and missed-call text-back, set up by Uplift.', 3),
	('reviews', 'Review requests',
		'Customers are asked for an honest Google review after finished work, with reminders.', 4),
	('marketing', 'Marketing campaigns',
		'Ready-made referral and returning-customer campaigns, sent only after you approve each one.', 5);

-- 2. Reading and changing the list ---------------------------------------------------------------------

create or replace function private.package_service_list()
returns jsonb
language sql
stable
set search_path = ''
as $$
	select coalesce(jsonb_agg(jsonb_build_object(
		'key', s.service_key,
		'name', s.name,
		'description', s.description,
		'archived_at', s.archived_at,
		-- Packages whose current draft or published edition includes it, so Jafar sees what an archive affects.
		'package_count', (
			select count(distinct e.package_id) from public.package_editions e
			where e.status in ('draft', 'published')
				and e.included_services @> jsonb_build_array(jsonb_build_object('service_key', s.service_key))
		)
	) order by s.archived_at nulls first, s.sort_order), '[]'::jsonb)
	from public.package_services s;
$$;

create or replace function public.owner_package_services()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select private.package_service_list();
$$;

-- Adds a service (no key) or renames and rewords one. A new key comes from the name and never changes.
create or replace function public.save_package_service(
	target_service_key text,
	service_name text,
	service_description text,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	clean_name text := trim(service_name);
	base_key text;
	new_key text;
	suffix integer := 1;
begin
	if exists (
		select 1 from public.package_services s
		where lower(trim(s.name)) = lower(clean_name)
			and s.service_key is distinct from target_service_key
	) then
		raise exception 'You already have a service called "%".', clean_name using errcode = 'unique_violation';
	end if;

	if target_service_key is null then
		base_key := left(trim(both '_' from regexp_replace(lower(clean_name), '[^a-z0-9]+', '_', 'g')), 50);
		if base_key !~ '^[a-z][a-z0-9_]{1,}$' then
			base_key := 'service_' || coalesce(nullif(base_key, ''), 'new');
		end if;
		new_key := base_key;
		while exists (select 1 from public.package_services s where s.service_key = new_key) loop
			suffix := suffix + 1;
			new_key := base_key || '_' || suffix;
		end loop;

		insert into public.package_services (service_key, name, description, sort_order, updated_by_email)
		values (
			new_key, clean_name, trim(coalesce(service_description, '')),
			coalesce((select max(s.sort_order) from public.package_services s), 0) + 1,
			trim(actor_owner_email)
		);
	else
		update public.package_services set
			name = clean_name,
			description = trim(coalesce(service_description, '')),
			updated_by_email = trim(actor_owner_email)
		where service_key = target_service_key;
		if not found then
			raise exception 'This service no longer exists.' using errcode = 'P0002';
		end if;
	end if;

	return private.package_service_list();
end;
$$;

create or replace function public.set_package_service_archived(
	target_service_key text,
	archived boolean,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
	update public.package_services set
		archived_at = case when archived then coalesce(archived_at, now()) else null end,
		updated_by_email = trim(actor_owner_email)
	where service_key = target_service_key;
	if not found then
		raise exception 'This service no longer exists.' using errcode = 'P0002';
	end if;
	return private.package_service_list();
end;
$$;

-- 3. Publishing checks the ticked services --------------------------------------------------------------

create or replace function private.package_publish_problems(target_edition_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
	with edition as (
		select e.* from public.package_editions e where e.id = target_edition_id
	), chosen as (
		select c.capability_key from public.package_edition_capabilities c where c.edition_id = target_edition_id
	), services as (
		select entry ->> 'service_key' as service_key, entry ->> 'name' as name
		from edition e, jsonb_array_elements(e.included_services) entry
	), problems as (
		select 1 as rank, 'price' as code, null::text as key,
			'Offer monthly or yearly billing, or both.' as message
		from edition e
		where e.monthly_price_usd_cents is null and e.yearly_price_usd_cents is null
		union all
		select 2, 'not_sellable', pc.capability_key,
			pc.label || ' is not ready to sell yet. Leave it out to publish.'
		from chosen c
		join public.package_capabilities pc on pc.capability_key = c.capability_key
		where not pc.sellable
		union all
		select 3, 'missing_requirement', r.capability_key,
			pc.label || ' needs ' || required.label || '.'
		from chosen c
		join public.package_capability_requirements r on r.capability_key = c.capability_key
		join public.package_capabilities pc on pc.capability_key = r.capability_key
		join public.package_capabilities required on required.capability_key = r.required_capability_key
		where not exists (select 1 from chosen c2 where c2.capability_key = r.required_capability_key)
		union all
		select 4, 'allowance', pa.allowance_key,
			case when ea.allowance_state is null or ea.allowance_state = 'not_included'
				then pa.label || ' needs a number or Unlimited.'
				else pa.label || ' must be at least 1. Leave the capability out instead of allowing none.' end
		from public.package_allowances pa
		left join public.package_edition_allowances ea
			on ea.edition_id = target_edition_id and ea.allowance_key = pa.allowance_key
		where (pa.capability_key is null or pa.capability_key in (select capability_key from chosen))
			and (ea.allowance_state is null or ea.allowance_state = 'not_included'
				or (ea.allowance_state = 'numeric' and ea.allowance_value < 1))
		union all
		select 5, 'service', coalesce(sv.service_key, sv.name),
			case
				when ps.service_key is null then
					'"' || coalesce(sv.name, 'A service') || '" is not on your service list. Tick a service from the list instead.'
				else ps.name || ' is archived. Restore it on your service list, or leave it out to publish.'
			end
		from services sv
		left join public.package_services ps on ps.service_key = sv.service_key
		where ps.service_key is null or ps.archived_at is not null
	)
	select coalesce(
		jsonb_agg(jsonb_build_object('code', code, 'key', key, 'message', message) order by rank, key),
		'[]'::jsonb
	)
	from problems;
$$;

-- 4. The builder receives the list -------------------------------------------------------------------

create or replace function public.owner_package_builder(target_package_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'package', jsonb_build_object(
			'id', p.id,
			'slug', p.slug,
			'visibility', p.visibility,
			'archived_at', p.archived_at,
			'website_update_pending_since', p.website_update_pending_since,
			'ever_published', exists (
				select 1 from public.package_editions e where e.package_id = p.id and e.status <> 'draft'
			),
			'organization_count', private.package_customer_count(p.id),
			'email_template_count', (
				select count(*) from public.platform_email_template_packages t where t.package_id = p.id
			)
		),
		'draft', (
			select private.package_edition_terms(d.id)
				|| jsonb_build_object('publish_problems', private.package_publish_problems(d.id))
			from public.package_editions d where d.package_id = p.id and d.status = 'draft'
		),
		'published', (
			select private.package_edition_terms(pe.id)
			from public.package_editions pe where pe.package_id = p.id and pe.status = 'published'
		),
		'history', private.package_history(p.id),
		'capabilities', (
			select coalesce(jsonb_agg(jsonb_build_object(
				'key', c.capability_key, 'label', c.label, 'description', c.description, 'kind', c.kind,
				'sellable', c.sellable,
				'requires', coalesce((
					select jsonb_agg(r.required_capability_key order by r.required_capability_key)
					from public.package_capability_requirements r where r.capability_key = c.capability_key
				), '[]'::jsonb)
			) order by c.sort_order), '[]'::jsonb)
			from public.package_capabilities c
		),
		'allowances', (
			select coalesce(jsonb_agg(jsonb_build_object(
				'key', a.allowance_key, 'capability_key', a.capability_key, 'label', a.label, 'unit', a.unit,
				'resets_monthly', a.resets_monthly
			) order by a.sort_order), '[]'::jsonb)
			from public.package_allowances a
		),
		'services', private.package_service_list()
	)
	from public.packages p
	where p.id = target_package_id;
$$;

revoke all on function private.package_service_list() from public, anon, authenticated;
revoke all on function public.owner_package_services() from public, anon, authenticated;
revoke all on function public.save_package_service(text, text, text, text) from public, anon, authenticated;
revoke all on function public.set_package_service_archived(text, boolean, text) from public, anon, authenticated;
grant execute on function public.owner_package_services() to service_role;
grant execute on function public.save_package_service(text, text, text, text) to service_role;
grant execute on function public.set_package_service_archived(text, boolean, text) to service_role;
