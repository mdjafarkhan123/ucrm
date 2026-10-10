-- Multi-industry platform foundation B2: Package fit.
--
-- A published Package edition declares which Industry experiences may buy it, and serves an experience only
-- when every capability and managed service in it fits that experience. The builder shows the gaps and
-- publication refuses them; a customer moves only onto an edition sold to its experience; a temporary
-- exception switches on only a capability its experience allows. Public listings filter by experience in
-- the app (src/lib/server/packages/public-packages.ts).
--
-- 1. Each capability belongs to one capability family. A family is eligible for an experience when its
--    published definition lists it (industry_experience_definitions.capability_families). Only capabilities
--    whose meaning is genuinely common are shared_platform; everything built for Contractor work is
--    field_service until another experience proves it fits there too.
-- 2. Each managed service names the experiences Uplift delivers it for. Today that is Contractor alone, so it
--    is also the default for a new service; the service list gains a choice when a second experience exists.
-- 3. Each edition names its audience. Every existing edition is a Contractor package, so the column arrives
--    with Contractor filled in (ADD COLUMN does not rewrite a frozen edition through its trigger); after that
--    a new draft starts with no audience and cannot publish until Jafar chooses one.

-- ---------------------------------------------------------------------------------------------------
-- Capability families, service and edition audiences
-- ---------------------------------------------------------------------------------------------------

alter table public.package_capabilities add column capability_family text;

update public.package_capabilities
set capability_family = case
	when capability_key in (
		'core.team', 'communications.inbox', 'website_chat', 'marketing',
		'communications.missed_call_text_back', 'integrations.api'
	) then 'shared_platform'
	else 'field_service'
end;

alter table public.package_capabilities
	alter column capability_family set not null,
	add constraint package_capabilities_capability_family_check check (
		capability_family in ('shared_platform', 'field_service', 'appointment_business', 'clinical_extension')
	);

comment on column public.package_capabilities.capability_family is
	'The capability family an Industry experience definition must list before an edition sold to it may include this capability.';

alter table public.package_services
	add column experience_keys text[] not null default array['contractor']
		check (cardinality(experience_keys) <= 20);

comment on column public.package_services.experience_keys is
	'The Industry experiences Uplift delivers this service for. An edition sold to another experience cannot include it.';

alter table public.package_editions
	add column experience_keys text[] not null default array['contractor']
		check (cardinality(experience_keys) <= 20);
alter table public.package_editions alter column experience_keys set default '{}';

comment on column public.package_editions.experience_keys is
	'The Industry experiences that may buy this edition. Fixed once published, like every other term.';

create index package_editions_experience_keys_idx on public.package_editions using gin (experience_keys);

-- ---------------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------------

-- The newest published definition of each experience: what Uplift sells to today.
create or replace function private.offered_experience_definitions()
returns setof public.industry_experience_definitions
language sql
stable
set search_path = ''
as $$
	select distinct on (d.experience_key) d.*
	from public.industry_experience_definitions d
	where d.status = 'published'
	order by d.experience_key, d.version desc;
$$;

create or replace function private.experience_names(target_keys text[])
returns text
language sql
stable
set search_path = ''
as $$
	select coalesce(string_agg(coalesce(d.name, k), ' or ' order by coalesce(d.name, k)), 'unknown')
	from unnest(target_keys) k
	left join private.offered_experience_definitions() d on d.experience_key = k;
$$;

-- The experience whose packages an Organization may move onto: its confirmed experience profile, or, before
-- Uplift has reviewed it, the audience of the edition it agreed to. Nothing is guessed: an Organization with
-- neither gets an empty answer and every package change is refused until Uplift confirms its experience.
create or replace function private.organization_offer_experiences(target_organization_id uuid)
returns text[]
language sql
stable
set search_path = ''
as $$
	select coalesce(
		(
			select array[d.experience_key]
			from public.organization_experience_decisions d
			where d.organization_id = target_organization_id
				and not exists (
					select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id
				)
		),
		(
			select e.experience_keys
			from public.organization_package_agreements a
			join public.package_editions e on e.id = a.edition_id
			where a.organization_id = target_organization_id and a.cancelled_at is null and a.effective_from <= now()
			order by a.effective_from desc, a.created_at desc
			limit 1
		),
		'{}'
	);
$$;

-- Whether an Organization's experience allows a capability. A confirmed profile is judged by the definition
-- version Uplift confirmed; otherwise every experience its agreed edition was sold to must allow it.
create or replace function private.capability_fits_organization(target_organization_id uuid, target_capability_key text)
returns boolean
language sql
stable
set search_path = ''
as $$
	with family as (
		select c.capability_family from public.package_capabilities c where c.capability_key = target_capability_key
	), head as (
		select d.experience_key, d.definition_version
		from public.organization_experience_decisions d
		where d.organization_id = target_organization_id
			and not exists (
				select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id
			)
	)
	select case
		when exists (select 1 from head) then exists (
			select 1 from head h
			join public.industry_experience_definitions d
				on d.experience_key = h.experience_key and d.version = h.definition_version
			where (select capability_family from family) = any(d.capability_families)
		)
		else coalesce((
			select cardinality(offered.keys) > 0 and bool_and((select capability_family from family) = any(d.capability_families))
			from (select private.organization_offer_experiences(target_organization_id) as keys) offered
			left join lateral unnest(offered.keys) k on true
			left join private.offered_experience_definitions() d on d.experience_key = k
			group by offered.keys
		), false)
	end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Publish checks: the existing checks, plus who may buy the edition and whether everything in it fits them
-- ---------------------------------------------------------------------------------------------------

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
	), audience as (
		select k as experience_key, d.name, d.capability_families
		from edition e
		cross join unnest(e.experience_keys) k
		left join private.offered_experience_definitions() d on d.experience_key = k
	), problems as (
		select 0 as rank, 'audience' as code, null::text as key,
			'Choose which kind of business can buy this package.' as message
		from edition e
		where cardinality(e.experience_keys) = 0
		union all
		select 0, 'audience_unknown', a.experience_key,
			'Uplift does not offer the "' || a.experience_key || '" Industry experience. Untick it to publish.'
		from audience a
		where a.name is null
		union all
		select 1, 'price', null::text,
			'Offer monthly or yearly billing, or both.'
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
		union all
		select 6, 'capability_fit', c.capability_key || ':' || a.experience_key,
			pc.label || ' is not part of the ' || a.name || ' experience. Leave it out, or stop selling this package to '
				|| a.name || ' businesses.'
		from chosen c
		join public.package_capabilities pc on pc.capability_key = c.capability_key
		cross join audience a
		where a.name is not null and not (pc.capability_family = any(a.capability_families))
		union all
		select 7, 'service_fit', ps.service_key || ':' || a.experience_key,
			ps.name || ' is not delivered for ' || a.name || ' businesses. Leave it out, or stop selling this package to '
				|| a.name || ' businesses.'
		from services sv
		join public.package_services ps on ps.service_key = sv.service_key
		cross join audience a
		where a.name is not null and not (a.experience_key = any(ps.experience_keys))
	)
	select coalesce(
		jsonb_agg(jsonb_build_object('code', code, 'key', key, 'message', message) order by rank, key),
		'[]'::jsonb
	)
	from problems;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Existing commands, each changed only where marked by the audience they now carry or check
-- ---------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.package_edition_terms(target_edition_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
	select jsonb_build_object(
		'edition_id', e.id,
		'status', e.status,
		'edition_number', e.edition_number,
		'revision', e.revision,
		'name', e.name,
		'promise', e.promise,
		'highlights', e.highlights,
		'included_services', e.included_services,
		'exclusions', e.exclusions,
		'monthly_price_usd_cents', e.monthly_price_usd_cents,
		'yearly_price_usd_cents', e.yearly_price_usd_cents,
		'updated_at', e.updated_at,
		'updated_by_email', e.updated_by_email,
		'experience_keys', to_jsonb(e.experience_keys),
		'capabilities', coalesce((
			select jsonb_agg(c.capability_key order by pc.sort_order)
			from public.package_edition_capabilities c
			join public.package_capabilities pc on pc.capability_key = c.capability_key
			where c.edition_id = e.id
		), '[]'::jsonb),
		'allowances', coalesce((
			select jsonb_agg(
				jsonb_build_object('key', a.allowance_key, 'state', a.allowance_state, 'value', a.allowance_value)
				order by pa.sort_order
			)
			from public.package_edition_allowances a
			join public.package_allowances pa on pa.allowance_key = a.allowance_key
			where a.edition_id = e.id
		), '[]'::jsonb)
	)
	from public.package_editions e
	where e.id = target_edition_id;
$function$;

CREATE OR REPLACE FUNCTION public.save_package_draft(target_package_id uuid, draft_edition_id uuid, loaded_revision integer, terms jsonb, actor_owner_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	draft public.package_editions;
	new_slug text := nullif(trim(coalesce(terms ->> 'slug', '')), '');
	new_experiences text[];
	unknown_experience text;
begin
	select e.* into draft from public.package_editions e
	where e.id = draft_edition_id and e.package_id = target_package_id
	for update;
	if draft.id is null or draft.status <> 'draft' then
		raise exception 'This draft no longer exists. It may have been published or deleted in another tab.'
			using errcode = 'P0002';
	end if;

	if draft.revision <> loaded_revision then
		return jsonb_build_object('saved', false, 'reason', 'stale', 'draft', private.package_edition_terms(draft.id));
	end if;

	-- Multi-industry foundation B2: the Industry experiences that may buy this edition, sorted and unique.
	new_experiences := case when terms ? 'experience_keys'
		then array(select distinct k from jsonb_array_elements_text(terms -> 'experience_keys') k order by k)
		else draft.experience_keys end;
	select k into unknown_experience from unnest(new_experiences) k
	where not exists (
		select 1 from public.industry_experience_definitions d where d.experience_key = k and d.status = 'published'
	)
	limit 1;
	if unknown_experience is not null then
		raise exception 'Uplift does not offer the "%" Industry experience.', unknown_experience using errcode = 'check_violation';
	end if;

	if new_slug is not null and new_slug <> (select p.slug from public.packages p where p.id = target_package_id) then
		if exists (select 1 from public.package_editions e where e.package_id = target_package_id and e.status <> 'draft') then
			raise exception 'The web address cannot change after the package has been published.'
				using errcode = 'check_violation';
		end if;
		if exists (select 1 from public.packages p where p.slug = new_slug and p.id <> target_package_id) then
			raise exception 'Another package already uses the web address "%".', new_slug using errcode = 'unique_violation';
		end if;
		update public.packages set slug = new_slug where id = target_package_id;
	end if;

	update public.package_editions set
		name = trim(terms ->> 'name'),
		promise = nullif(trim(coalesce(terms ->> 'promise', '')), ''),
		highlights = coalesce(terms -> 'highlights', '[]'::jsonb),
		included_services = coalesce(terms -> 'included_services', '[]'::jsonb),
		exclusions = nullif(trim(coalesce(terms ->> 'exclusions', '')), ''),
		monthly_price_usd_cents = (terms ->> 'monthly_price_usd_cents')::integer,
		yearly_price_usd_cents = (terms ->> 'yearly_price_usd_cents')::integer,
		experience_keys = new_experiences,
		revision = draft.revision + 1,
		updated_by_email = trim(actor_owner_email)
	where id = draft.id;

	perform private.write_package_draft_rows(draft.id, terms);

	return jsonb_build_object('saved', true, 'draft', private.package_edition_terms(draft.id));
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_package_draft(slug text, name text, actor_owner_email text, idempotency_key text, copy_from_package_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	existing_id uuid;
	source_edition public.package_editions;
	new_package_id uuid;
	new_edition_id uuid;
	next_order integer;
begin
	select p.id into existing_id from public.packages p
	where p.creation_idempotency_key = create_package_draft.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'package_id', existing_id);
	end if;

	if copy_from_package_id is not null then
		select e.* into source_edition
		from public.package_editions e
		where e.package_id = copy_from_package_id and e.status in ('draft', 'published')
		order by (e.status = 'draft') desc
		limit 1;
		if source_edition.id is null then
			raise exception 'The package to copy was not found.' using errcode = 'P0002';
		end if;
	end if;

	if exists (select 1 from public.packages p where p.slug = create_package_draft.slug) then
		raise exception 'Another package already uses the web address "%".', create_package_draft.slug
			using errcode = 'unique_violation';
	end if;

	select coalesce(max(p.display_order), 0) + 1 into next_order from public.packages p;

	insert into public.packages (slug, visibility, display_order, created_by_email, creation_idempotency_key)
	values (create_package_draft.slug, 'private', next_order, trim(actor_owner_email), idempotency_key)
	returning id into new_package_id;

	insert into public.package_editions (
		package_id, status, name, promise, highlights, included_services, exclusions,
		monthly_price_usd_cents, yearly_price_usd_cents, updated_by_email, experience_keys
	) values (
		new_package_id, 'draft', trim(create_package_draft.name), source_edition.promise,
		coalesce(source_edition.highlights, '[]'::jsonb), coalesce(source_edition.included_services, '[]'::jsonb),
		source_edition.exclusions, source_edition.monthly_price_usd_cents, source_edition.yearly_price_usd_cents,
		trim(actor_owner_email), coalesce(source_edition.experience_keys, '{}')
	)
	returning id into new_edition_id;

	if source_edition.id is null then
		perform private.write_package_draft_rows(new_edition_id, '{}'::jsonb);
	else
		insert into public.package_edition_capabilities (edition_id, capability_key)
		select new_edition_id, c.capability_key
		from public.package_edition_capabilities c where c.edition_id = source_edition.id;
		insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
		select new_edition_id, a.allowance_key, a.allowance_state, a.allowance_value
		from public.package_edition_allowances a where a.edition_id = source_edition.id;
	end if;

	insert into public.package_catalog_events (package_id, event_type, detail, actor_email)
	values (new_package_id, 'created',
		jsonb_build_object('name', trim(create_package_draft.name), 'copied_from_package_id', copy_from_package_id),
		trim(actor_owner_email));

	return jsonb_build_object('applied', true, 'package_id', new_package_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.open_package_draft(target_package_id uuid, actor_owner_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	draft_id uuid;
	source_edition public.package_editions;
begin
	perform 1 from public.packages p where p.id = target_package_id for update;
	if not found then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;

	select e.id into draft_id from public.package_editions e
	where e.package_id = target_package_id and e.status = 'draft';
	if draft_id is not null then
		return jsonb_build_object('applied', false, 'edition_id', draft_id);
	end if;

	select e.* into source_edition from public.package_editions e
	where e.package_id = target_package_id and e.status = 'published';
	if source_edition.id is null then
		raise exception 'This package has nothing to start a draft from.' using errcode = 'P0002';
	end if;

	insert into public.package_editions (
		package_id, status, name, promise, highlights, included_services, exclusions,
		monthly_price_usd_cents, yearly_price_usd_cents, updated_by_email, experience_keys
	) values (
		target_package_id, 'draft', source_edition.name, source_edition.promise, source_edition.highlights,
		source_edition.included_services, source_edition.exclusions, source_edition.monthly_price_usd_cents,
		source_edition.yearly_price_usd_cents, trim(actor_owner_email), source_edition.experience_keys
	)
	returning id into draft_id;

	insert into public.package_edition_capabilities (edition_id, capability_key)
	select draft_id, c.capability_key from public.package_edition_capabilities c where c.edition_id = source_edition.id;
	insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
	select draft_id, a.allowance_key, a.allowance_state, a.allowance_value
	from public.package_edition_allowances a where a.edition_id = source_edition.id;

	return jsonb_build_object('applied', true, 'edition_id', draft_id);
end;
$function$;

CREATE OR REPLACE FUNCTION private.package_service_list()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
	select coalesce(jsonb_agg(jsonb_build_object(
		'key', s.service_key,
		'name', s.name,
		'description', s.description,
		'archived_at', s.archived_at,
		'experience_keys', to_jsonb(s.experience_keys),
		-- Packages whose current draft or published edition includes it, so Jafar sees what an archive affects.
		'package_count', (
			select count(distinct e.package_id) from public.package_editions e
			where e.status in ('draft', 'published')
				and e.included_services @> jsonb_build_array(jsonb_build_object('service_key', s.service_key))
		)
	) order by s.archived_at nulls first, s.sort_order), '[]'::jsonb)
	from public.package_services s;
$function$;

CREATE OR REPLACE FUNCTION public.owner_package_builder(target_package_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
				'sellable', c.sellable, 'family', c.capability_family,
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
		'services', private.package_service_list(),
		'experiences', (
			select coalesce(jsonb_agg(jsonb_build_object(
				'key', d.experience_key, 'name', d.name, 'capability_families', to_jsonb(d.capability_families)
			) order by d.name), '[]'::jsonb)
			from private.offered_experience_definitions() d
		)
	)
	from public.packages p
	where p.id = target_package_id;
$function$;

CREATE OR REPLACE FUNCTION private.package_change_plan(target_organization_id uuid, target_edition_id uuid, target_billing_interval text, target_timing text, target_offer_id uuid DEFAULT NULL::uuid, target_offer_code text DEFAULT NULL::text, keep_offer boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
	tz text;
	today date;
	commercial public.organization_commercial_state;
	current_agreement public.organization_package_agreements;
	scheduled public.organization_package_agreements;
	current_edition public.package_editions;
	current_package public.packages;
	proposed public.package_editions;
	proposed_package public.packages;
	price integer;
	blockers jsonb := '[]'::jsonb;
	offered_to text[];
	effective_date date;
	effective_from timestamptz;
	interval_changes boolean;
	current_charge public.organization_billing_charges;
	replaced jsonb := '[]'::jsonb;
	replaced_locked boolean := false;
	previous_anchor date;
	credit integer := 0;
	remaining_days integer;
	regular_start date;
	regular_end date;
	new_charge jsonb;
	next_charge jsonb;
	next_start date;
	next_anchor date;
	allowances jsonb;
	over_limits jsonb;
	capabilities jsonb;
	offer_row public.package_offers;
	offer_terms jsonb;
	offer_starts date;
	window_anchor date;
	can_keep boolean;
	available jsonb;
	asks_offer boolean := target_offer_id is not null
		or nullif(trim(coalesce(target_offer_code, '')), '') is not null;
begin
	if target_timing is null or target_timing not in ('next_renewal', 'now') then
		raise exception 'Choose when the change starts.' using errcode = 'check_violation';
	end if;
	if target_billing_interval is null or target_billing_interval not in ('month', 'year') then
		raise exception 'Choose monthly or yearly billing.' using errcode = 'check_violation';
	end if;

	select * into proposed from public.package_editions e where e.id = target_edition_id;
	if proposed.id is null then
		raise exception 'That package edition was not found.' using errcode = 'foreign_key_violation';
	end if;
	select * into proposed_package from public.packages p where p.id = proposed.package_id;

	select coalesce((select s.commercial_timezone from public.organization_commercial_settings s
		where s.organization_id = target_organization_id), 'UTC') into tz;
	today := (now() at time zone tz)::date;
	select * into commercial from public.organization_commercial_state s where s.organization_id = target_organization_id;

	select * into current_agreement from public.organization_package_agreements a
	where a.organization_id = target_organization_id and a.effective_from <= now() and a.cancelled_at is null
	order by a.effective_from desc, a.created_at desc
	limit 1;
	select * into scheduled from public.organization_package_agreements a
	where a.organization_id = target_organization_id and a.effective_from > now() and a.cancelled_at is null
	order by a.effective_from
	limit 1;
	select * into current_edition from public.package_editions e where e.id = current_agreement.edition_id;
	select * into current_package from public.packages p where p.id = current_edition.package_id;

	price := case target_billing_interval
		when 'month' then proposed.monthly_price_usd_cents else proposed.yearly_price_usd_cents end;
	interval_changes := current_agreement.billing_interval is distinct from target_billing_interval;

	if proposed.status <> 'published' then
		blockers := blockers || jsonb_build_object('code', 'edition_not_current',
			'message', 'This edition has been replaced by a newer one. Choose the current edition.');
	end if;
	if proposed_package.archived_at is not null then
		blockers := blockers || jsonb_build_object('code', 'package_archived',
			'message', 'This package is archived. Restore it before moving a customer onto it.');
	end if;
	-- Multi-industry foundation B2: a customer moves only onto an edition sold to its Industry experience.
	offered_to := private.organization_offer_experiences(target_organization_id);
	if cardinality(offered_to) = 0 then
		blockers := blockers || jsonb_build_object('code', 'experience_unconfirmed',
			'message', 'This business has no confirmed Industry experience. Confirm it on the Experience tab first.');
	elsif not proposed.experience_keys @> offered_to then
		blockers := blockers || jsonb_build_object('code', 'experience_mismatch',
			'message', 'This package is not sold to ' || private.experience_names(offered_to)
				|| ' businesses. Choose a package made for them.');
	end if;
	if price is null then
		blockers := blockers || jsonb_build_object('code', 'price_missing',
			'message', 'This package has no ' || case target_billing_interval when 'month' then 'monthly' else 'yearly' end
				|| ' price.');
	end if;
	if current_agreement.edition_id = proposed.id and not interval_changes and not asks_offer then
		blockers := blockers || jsonb_build_object('code', 'same_terms',
			'message', 'The customer already has this package and billing. Choose an offer to add one.');
	end if;
	if scheduled.id is not null then
		blockers := blockers || jsonb_build_object('code', 'change_scheduled',
			'message', 'A change is already scheduled for ' || to_char((scheduled.effective_from at time zone tz)::date, 'YYYY-MM-DD')
				|| '. Cancel it first.');
	end if;

	if target_timing = 'next_renewal' then
		if commercial.paid_through_date is null then
			blockers := blockers || jsonb_build_object('code', 'no_renewal_date',
				'message', 'This customer has no paid period yet, so there is no renewal date. Move them now instead.');
		elsif commercial.paid_through_date < today then
			blockers := blockers || jsonb_build_object('code', 'renewal_passed',
				'message', 'Their renewal date has already passed. Move them now instead.');
		else
			effective_date := commercial.paid_through_date + 1;
			effective_from := effective_date::timestamp at time zone tz;
		end if;
	else
		effective_date := today;
		effective_from := now();
	end if;

	if effective_date is not null then
		if target_timing = 'now' then
			select * into current_charge from public.organization_billing_charges c
			where c.organization_id = target_organization_id and c.period_start <= today and c.period_end >= today
				and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
			order by c.period_start desc, c.created_at desc
			limit 1;
		end if;

		-- A kept offer keeps its window with the new price. A new offer starts with the first full period
		-- under the new terms; a part period after a same-billing move now is charged at the normal price.
		can_keep := current_agreement.offer_terms is not null and not interval_changes
			and (current_agreement.offer_terms ->> 'ends_before')::date > effective_date;
		if keep_offer and asks_offer then
			blockers := blockers || jsonb_build_object('code', 'offer_choice',
				'message', 'Choose a new offer or keep the current one, not both.');
		elsif keep_offer then
			if current_agreement.offer_terms is null or (current_agreement.offer_terms ->> 'ends_before')::date <= effective_date then
				blockers := blockers || jsonb_build_object('code', 'no_offer_to_keep',
					'message', 'There is no intro offer left to keep on the day the change starts.');
			elsif interval_changes then
				blockers := blockers || jsonb_build_object('code', 'offer_interval',
					'message', 'An intro offer can only be kept when the billing stays '
						|| case current_agreement.billing_interval when 'month' then 'monthly' else 'yearly' end || '.');
			elsif price is not null then
				offer_terms := current_agreement.offer_terms || jsonb_build_object(
					'normal_price_usd_cents', price,
					'intro_price_usd_cents', private.package_offer_intro_price(current_agreement.offer_terms, price));
			end if;
		elsif asks_offer then
			select * into offer_row from public.package_offers o
			where (target_offer_id is not null and o.id = target_offer_id)
				or (target_offer_id is null and o.code = upper(trim(target_offer_code)));
			if offer_row.id is null then
				blockers := blockers || jsonb_build_object('code', 'offer_not_found',
					'message', case when target_offer_id is null
						then 'No offer has the code ' || upper(trim(target_offer_code)) || '.'
						else 'That offer was not found.' end);
			else
				blockers := blockers || private.package_offer_problems(
					offer_row, target_organization_id, proposed.package_id, target_billing_interval);
				if target_timing = 'now' and (interval_changes or current_charge.id is null) then
					offer_starts := today;
					window_anchor := today;
				elsif target_timing = 'now' then
					offer_starts := current_charge.period_end + 1;
					window_anchor := current_charge.anchor_date;
				else
					offer_starts := effective_date;
					window_anchor := case when interval_changes then effective_date else coalesce((
						select c.anchor_date from public.organization_billing_charges c
						where c.organization_id = target_organization_id and c.period_end = effective_date - 1
							and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
						order by c.period_start desc
						limit 1
					), effective_date) end;
				end if;
				if price is not null then
					offer_terms := private.package_offer_terms(
						to_jsonb(offer_row), price, target_billing_interval, window_anchor, offer_starts);
				end if;
			end if;
		end if;

		-- Charges already waiting for dates after the change starts were priced on the old terms.
		select
			coalesce(jsonb_agg(jsonb_build_object(
				'id', c.id, 'period_start', c.period_start, 'period_end', c.period_end,
				'amount_usd_cents', c.amount_usd_cents) order by c.period_start), '[]'::jsonb),
			coalesce(bool_or(private.billing_charge_applied(c.id) > 0
				or exists (select 1 from public.organization_billing_coverage_confirmations cc where cc.charge_id = c.id)), false)
		into replaced, replaced_locked
		from public.organization_billing_charges c
		where c.organization_id = target_organization_id
			and c.period_start > case when target_timing = 'now' then today else effective_date - 1 end
			and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id);

		if replaced_locked then
			blockers := blockers || jsonb_build_object('code', 'future_charge_paid',
				'message', 'A later charge already has money applied at the old price. Remove that money from it first.');
		end if;

		if current_charge.id is not null then
			remaining_days := current_charge.period_end - today + 1;
			credit := round(current_charge.amount_usd_cents::numeric * remaining_days
				/ (current_charge.period_end - current_charge.period_start + 1))::integer;
			if not interval_changes then
				regular_start := private.billing_period_start(current_charge.anchor_date, today, target_billing_interval);
				regular_end := private.billing_period_end(current_charge.anchor_date, today, target_billing_interval);
				new_charge := jsonb_build_object(
					'kind', 'change', 'anchor_date', current_charge.anchor_date, 'period_start', today,
					'period_end', current_charge.period_end,
					'amount_usd_cents', round(coalesce(private.agreement_period_price(price, offer_terms, today), 0)::numeric
						* remaining_days / (regular_end - regular_start + 1))::integer);
			else
				new_charge := jsonb_build_object(
					'kind', 'period', 'anchor_date', today, 'period_start', today,
					'period_end', private.billing_period_end(today, today, target_billing_interval),
					'amount_usd_cents', coalesce(private.agreement_period_price(price, offer_terms, today), 0));
			end if;
		end if;

		-- The waiting charge comes back at the new price, except after a monthly-yearly switch made now:
		-- the new period starting today already covers those dates.
		if jsonb_array_length(replaced) > 0 and not (current_charge.id is not null and interval_changes) then
			next_start := (replaced -> 0 ->> 'period_start')::date;
			select c.anchor_date into previous_anchor from public.organization_billing_charges c
			where c.organization_id = target_organization_id and c.period_end = next_start - 1
				and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
			order by c.period_start desc
			limit 1;
			next_anchor := case
				when new_charge is not null then (new_charge ->> 'anchor_date')::date
				when previous_anchor is not null and not interval_changes then previous_anchor
				else next_start
			end;
			next_charge := jsonb_build_object(
				'period_start', next_start,
				'period_end', private.billing_period_end(next_anchor, next_start, target_billing_interval),
				'amount_usd_cents', coalesce(private.agreement_period_price(price, offer_terms, next_start), 0));
		end if;
	end if;

	-- Allowances on both sides. An exception active when the change starts still applies on top.
	select
		jsonb_agg(row_json order by sort_order),
		coalesce(jsonb_agg(row_json order by sort_order) filter (where (row_json ->> 'excess')::integer > 0), '[]'::jsonb)
	into allowances, over_limits
	from (
		select pa.sort_order, jsonb_build_object(
			'allowance_key', pa.allowance_key, 'label', pa.label, 'unit', pa.unit, 'resets_monthly', pa.resets_monthly,
			'current', jsonb_build_object('state', coalesce(ce.allowance_state, 'not_included'), 'value', ce.allowance_value),
			'proposed', jsonb_build_object('state', coalesce(pe.allowance_state, 'not_included'), 'value', pe.allowance_value),
			'exception', case when x.id is null then null
				else jsonb_build_object('state', x.allowance_state, 'value', x.allowance_value, 'ends_at', x.ends_at) end,
			'in_use', usage.in_use,
			'excess', case
				when usage.in_use is null then 0
				when coalesce(x.allowance_state, pe.allowance_state, 'not_included') = 'unlimited' then 0
				else greatest(usage.in_use - case coalesce(x.allowance_state, pe.allowance_state, 'not_included')
					when 'numeric' then coalesce(x.allowance_value, pe.allowance_value) else 0 end, 0)
			end
		) as row_json
		from public.package_allowances pa
		left join public.package_edition_allowances ce
			on ce.edition_id = current_agreement.edition_id and ce.allowance_key = pa.allowance_key
		left join public.package_edition_allowances pe
			on pe.edition_id = proposed.id and pe.allowance_key = pa.allowance_key
		left join lateral (
			select * from public.organization_package_exceptions e
			where e.organization_id = target_organization_id and e.allowance_key = pa.allowance_key
				and e.starts_at <= coalesce(effective_from, now()) and e.ends_at > coalesce(effective_from, now())
			order by e.starts_at desc, e.created_at desc
			limit 1
		) x on true
		cross join lateral (
			select private.package_allowance_in_use(target_organization_id, pa.allowance_key) as in_use
		) usage
	) as allowance_rows;

	if jsonb_array_length(over_limits) > 0 then
		blockers := blockers || jsonb_build_object('code', 'over_limits',
			'message', 'Resolve what is over the new package''s limits first.');
	end if;

	select jsonb_agg(jsonb_build_object(
		'capability_key', c.capability_key, 'label', c.label, 'kind', c.kind,
		'current', exists (select 1 from public.package_edition_capabilities ec
			where ec.edition_id = current_agreement.edition_id and ec.capability_key = c.capability_key),
		'proposed', exists (select 1 from public.package_edition_capabilities ec
			where ec.edition_id = proposed.id and ec.capability_key = c.capability_key),
		'exception', (
			select e.capability_state from public.organization_package_exceptions e
			where e.organization_id = target_organization_id and e.capability_key = c.capability_key
				and e.starts_at <= coalesce(effective_from, now()) and e.ends_at > coalesce(effective_from, now())
			order by e.starts_at desc, e.created_at desc
			limit 1
		)
	) order by c.sort_order)
	into capabilities
	from public.package_capabilities c;

	-- Automatic offers this customer could take on the proposed package and billing.
	select coalesce(jsonb_agg(private.package_offer_shown(o, target_billing_interval, price)
		order by private.package_offer_intro_price(to_jsonb(o), price), o.created_at desc), '[]'::jsonb)
	into available
	from public.package_offers o
	join public.package_offer_packages op on op.offer_id = o.id and op.package_id = proposed.package_id
	where o.apply_mode = 'automatic' and price is not null
		and jsonb_array_length(private.package_offer_problems(o, target_organization_id, proposed.package_id,
			target_billing_interval)) = 0;

	return jsonb_build_object(
		'organization_id', target_organization_id,
		'commercial_timezone', tz,
		'today', today,
		'paid_through_date', commercial.paid_through_date,
		'timing', target_timing,
		'effective_date', effective_date,
		'effective_from', effective_from,
		'current', case when current_agreement.id is null then null else jsonb_build_object(
			'agreement_id', current_agreement.id, 'edition_id', current_edition.id, 'name', current_edition.name,
			'edition_number', current_edition.edition_number, 'package_slug', current_package.slug,
			'billing_interval', current_agreement.billing_interval,
			'agreed_price_usd_cents', current_agreement.agreed_price_usd_cents,
			'offer_terms', current_agreement.offer_terms) end,
		'proposed', jsonb_build_object(
			'edition_id', proposed.id, 'name', proposed.name, 'edition_number', proposed.edition_number,
			'package_slug', proposed_package.slug, 'visibility', proposed_package.visibility,
			'billing_interval', target_billing_interval, 'price_usd_cents', price),
		'capabilities', coalesce(capabilities, '[]'::jsonb),
		'allowances', coalesce(allowances, '[]'::jsonb),
		'over_limits', over_limits,
		'money', jsonb_build_object(
			'credit_usd_cents', credit,
			'credit_from', case when credit > 0 then today end,
			'credit_through', case when credit > 0 then current_charge.period_end end,
			'credit_source_charge_id', case when credit > 0 then current_charge.id end,
			'new_charge', new_charge,
			'credit_applied_usd_cents', least(credit, coalesce((new_charge ->> 'amount_usd_cents')::integer, 0)),
			'replaced_charges', replaced,
			'next_charge', next_charge
		),
		'offer', jsonb_build_object(
			'proposed', offer_terms,
			'kept', keep_offer and offer_terms is not null,
			'can_keep', coalesce(can_keep, false),
			'available', coalesce(available, '[]'::jsonb)
		),
		'blockers', blockers
	);
end;
$function$;

CREATE OR REPLACE FUNCTION public.add_organization_package_exception(target_organization_id uuid, capability_key text, capability_state text, allowance_key text, allowance_state text, allowance_value integer, starts_at timestamp with time zone, ends_at timestamp with time zone, reason text, actor_owner_email text, idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	existing_id uuid;
	capability public.package_capabilities;
	allowance public.package_allowances;
	effective_start timestamptz := greatest(starts_at, now());
	missing_label text;
	dependent_label text;
	overlapping public.organization_package_exceptions;
	in_use integer;
	new_limit integer;
	inserted public.organization_package_exceptions;
begin
	perform private.lock_organization_billing(target_organization_id);

	select x.id into existing_id from public.organization_package_exceptions x
	where x.idempotency_key = add_organization_package_exception.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'exception_id', existing_id);
	end if;

	if (capability_key is null) = (allowance_key is null) then
		raise exception 'Choose one feature or one limit for the exception.' using errcode = 'check_violation';
	end if;
	if reason is null or char_length(trim(reason)) = 0 then
		raise exception 'Give a reason for the exception.' using errcode = 'check_violation';
	end if;
	if starts_at is null or ends_at is null then
		raise exception 'Choose when the exception starts and ends.' using errcode = 'check_violation';
	end if;
	if ends_at <= effective_start then
		raise exception 'The exception must end after it starts, and in the future.' using errcode = 'check_violation';
	end if;

	if capability_key is not null then
		select * into capability from public.package_capabilities c where c.capability_key = add_organization_package_exception.capability_key;
		if capability.capability_key is null then
			raise exception 'That feature was not found.' using errcode = 'foreign_key_violation';
		end if;
		if capability.kind = 'core' then
			raise exception '% is in every package and cannot be changed by an exception.', capability.label
				using errcode = 'check_violation';
		end if;
		if capability.kind = 'planned' then
			raise exception '% is not built yet, so it cannot be switched on or off.', capability.label
				using errcode = 'check_violation';
		end if;
		if capability_state is null or capability_state not in ('on', 'off') then
			raise exception 'Choose whether the feature is switched on or off.' using errcode = 'check_violation';
		end if;

		if capability_state = 'on' then
			if not private.capability_fits_organization(target_organization_id, capability.capability_key) then
				raise exception '% is not part of this business''s Industry experience, so it cannot be switched on.',
					capability.label using errcode = 'check_violation';
			end if;
			select c.label into missing_label
			from public.package_capability_requirements r
			join public.package_capabilities c on c.capability_key = r.required_capability_key
			where r.capability_key = capability.capability_key
				and not private.organization_has_capability(target_organization_id, r.required_capability_key, effective_start)
			limit 1;
			if missing_label is not null then
				raise exception '% needs %. Switch % on first.', capability.label, missing_label, missing_label
					using errcode = 'check_violation';
			end if;
		else
			select c.label into dependent_label
			from public.package_capability_requirements r
			join public.package_capabilities c on c.capability_key = r.capability_key
			where r.required_capability_key = capability.capability_key
				and private.organization_has_capability(target_organization_id, r.capability_key, effective_start)
			limit 1;
			if dependent_label is not null then
				raise exception '% needs %. Switch % off first.', dependent_label, capability.label, dependent_label
					using errcode = 'check_violation';
			end if;
		end if;
	else
		select * into allowance from public.package_allowances a where a.allowance_key = add_organization_package_exception.allowance_key;
		if allowance.allowance_key is null then
			raise exception 'That limit was not found.' using errcode = 'foreign_key_violation';
		end if;
		if allowance_state is null or allowance_state not in ('numeric', 'unlimited', 'not_included') then
			raise exception 'Choose a number, unlimited, or not included.' using errcode = 'check_violation';
		end if;
		if allowance_state = 'numeric' and (allowance_value is null or allowance_value < 0) then
			raise exception 'Enter a number of zero or more.' using errcode = 'check_violation';
		end if;
		in_use := private.package_allowance_in_use(target_organization_id, allowance.allowance_key);
		new_limit := case when allowance_state = 'numeric' then allowance_value else 0 end;
		if in_use is not null and allowance_state <> 'unlimited' and in_use > new_limit then
			raise exception '% % are in use now, so the limit cannot be lower than that.', in_use, allowance.unit
				using errcode = 'check_violation';
		end if;
	end if;

	select * into overlapping from public.organization_package_exceptions x
	where x.organization_id = target_organization_id
		and (x.capability_key = add_organization_package_exception.capability_key
			or x.allowance_key = add_organization_package_exception.allowance_key)
		and x.starts_at < add_organization_package_exception.ends_at and x.ends_at > effective_start
	order by x.starts_at
	limit 1;
	if overlapping.id is not null then
		raise exception 'An exception for this already runs until %. End it first or choose dates after it.',
			to_char(overlapping.ends_at, 'YYYY-MM-DD HH24:MI') || ' UTC'
			using errcode = 'check_violation';
	end if;

	insert into public.organization_package_exceptions (
		organization_id, capability_key, capability_state, allowance_key, allowance_state, allowance_value,
		reason, starts_at, ends_at, actor_owner_email, idempotency_key
	) values (
		target_organization_id, add_organization_package_exception.capability_key,
		case when add_organization_package_exception.capability_key is not null then capability_state end,
		add_organization_package_exception.allowance_key,
		case when add_organization_package_exception.allowance_key is not null then allowance_state end,
		case when add_organization_package_exception.allowance_key is not null and allowance_state = 'numeric'
			then allowance_value end,
		trim(reason), effective_start, ends_at, actor_owner_email, idempotency_key
	)
	returning * into inserted;

	perform public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => case when inserted.capability_key is not null then 'feature_exception_changed' else 'limit_exception_changed' end,
		idempotency_key => idempotency_key,
		summary => coalesce(capability.label, allowance.label) || ' exception added until '
			|| to_char(inserted.ends_at, 'YYYY-MM-DD HH24:MI') || ' UTC.',
		paid_through_effect => 'unchanged',
		actor_owner_email => actor_owner_email,
		private_reason => trim(reason),
		safe_kind => case when inserted.capability_key is not null then 'feature_access_changed' else 'limit_access_changed' end,
		safe_payload => case when inserted.capability_key is not null
			then jsonb_build_object('feature_key', inserted.capability_key, 'effective_at', inserted.starts_at)
			else jsonb_build_object('limit_key', inserted.allowance_key, 'limit_state', inserted.allowance_state,
				'limit_value', inserted.allowance_value, 'effective_at', inserted.starts_at)
		end
	);

	return jsonb_build_object('applied', true, 'exception_id', inserted.id);
end;
$function$;

