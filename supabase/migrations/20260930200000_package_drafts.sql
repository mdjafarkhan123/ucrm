-- Package builder P6 (ADR 0003 decision 3): Jafar's commands for package drafts.
--
-- A package has at most one draft. Jafar creates a package (optionally copying another package's latest
-- terms), opens a draft of a published package, saves the whole draft in one transaction naming the
-- revision he loaded, and deletes a draft nobody uses. Publishing is package-builder P7.
--
-- Drafts may hold unready capabilities and missing requirements: the builder explains them, and P7's
-- publish refuses them. Every draft always carries the core capabilities and one row per allowance, so an
-- edition's rows are the whole answer to "what does this package include".

alter table public.packages
	add column creation_idempotency_key text unique
		check (creation_idempotency_key is null or char_length(trim(creation_idempotency_key)) between 8 and 200);

alter table public.package_editions
	add column updated_by_email text
		check (updated_by_email is null or char_length(trim(updated_by_email)) between 3 and 320);

-- ---------------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------------

-- The editable terms of one edition, in the shape the builder saves.
create or replace function private.package_edition_terms(target_edition_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
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
$$;

-- Replaces a draft's capability and allowance rows from saved terms. Core capabilities are always
-- included; an allowance whose capability is left out is stored as not included.
create or replace function private.write_package_draft_rows(target_edition_id uuid, terms jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
	unknown_key text;
begin
	select k into unknown_key
	from jsonb_array_elements_text(coalesce(terms -> 'capabilities', '[]'::jsonb)) as k
	where not exists (select 1 from public.package_capabilities c where c.capability_key = k)
	limit 1;
	if unknown_key is not null then
		raise exception 'The capability % does not exist.', unknown_key using errcode = 'check_violation';
	end if;

	select a ->> 'key' into unknown_key
	from jsonb_array_elements(coalesce(terms -> 'allowances', '[]'::jsonb)) as a
	where not exists (select 1 from public.package_allowances pa where pa.allowance_key = a ->> 'key')
	limit 1;
	if unknown_key is not null then
		raise exception 'The allowance % does not exist.', unknown_key using errcode = 'check_violation';
	end if;

	delete from public.package_edition_capabilities where edition_id = target_edition_id;
	insert into public.package_edition_capabilities (edition_id, capability_key)
	select target_edition_id, c.capability_key
	from public.package_capabilities c
	where c.kind = 'core'
		or c.capability_key in (
			select jsonb_array_elements_text(coalesce(terms -> 'capabilities', '[]'::jsonb))
		);

	delete from public.package_edition_allowances where edition_id = target_edition_id;
	insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
	select
		target_edition_id,
		pa.allowance_key,
		case when included.capability_key is null and pa.capability_key is not null then 'not_included'
			else coalesce(given.state, 'not_included') end,
		case when included.capability_key is null and pa.capability_key is not null then null
			when given.state = 'numeric' then given.value end
	from public.package_allowances pa
	left join lateral (
		select a ->> 'state' as state, (a ->> 'value')::integer as value
		from jsonb_array_elements(coalesce(terms -> 'allowances', '[]'::jsonb)) as a
		where a ->> 'key' = pa.allowance_key
		limit 1
	) as given on true
	left join public.package_edition_capabilities included
		on included.edition_id = target_edition_id and included.capability_key = pa.capability_key;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Readers
-- ---------------------------------------------------------------------------------------------------

-- The Packages page: every package with its draft and published edition, and how many organizations
-- have agreed to any of its editions.
create or replace function public.owner_package_catalog()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(row_json order by display_order, created_at), '[]'::jsonb)
	from (
		select
			p.display_order,
			p.created_at,
			jsonb_build_object(
				'id', p.id,
				'slug', p.slug,
				'visibility', p.visibility,
				'display_order', p.display_order,
				'archived_at', p.archived_at,
				'created_at', p.created_at,
				'draft', (
					select jsonb_build_object(
						'edition_id', d.id, 'revision', d.revision, 'name', d.name,
						'monthly_price_usd_cents', d.monthly_price_usd_cents,
						'yearly_price_usd_cents', d.yearly_price_usd_cents,
						'updated_at', d.updated_at
					)
					from public.package_editions d
					where d.package_id = p.id and d.status = 'draft'
				),
				'published', (
					select jsonb_build_object(
						'edition_id', pe.id, 'edition_number', pe.edition_number, 'name', pe.name,
						'monthly_price_usd_cents', pe.monthly_price_usd_cents,
						'yearly_price_usd_cents', pe.yearly_price_usd_cents,
						'published_at', pe.published_at
					)
					from public.package_editions pe
					where pe.package_id = p.id and pe.status = 'published'
				),
				'organization_count', (
					select count(distinct a.organization_id)
					from public.organization_package_agreements a
					join public.package_editions ae on ae.id = a.edition_id
					where ae.package_id = p.id
				)
			) as row_json
		from public.packages p
	) as rows;
$$;

-- The builder: one package, its draft and published terms, and the capability and allowance reference
-- data the form is built from.
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
			'ever_published', exists (
				select 1 from public.package_editions e where e.package_id = p.id and e.status <> 'draft'
			),
			'organization_count', (
				select count(distinct a.organization_id)
				from public.organization_package_agreements a
				join public.package_editions ae on ae.id = a.edition_id
				where ae.package_id = p.id
			),
			'email_template_count', (
				select count(*) from public.platform_email_template_packages t where t.package_id = p.id
			)
		),
		'draft', (
			select private.package_edition_terms(d.id)
			from public.package_editions d where d.package_id = p.id and d.status = 'draft'
		),
		'published', (
			select private.package_edition_terms(pe.id)
			from public.package_editions pe where pe.package_id = p.id and pe.status = 'published'
		),
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
		)
	)
	from public.packages p
	where p.id = target_package_id;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------------

-- Creates a package with a draft. With copy_from_package_id, the draft starts from that package's latest
-- terms (its draft, or else its published edition); otherwise from the core capabilities alone.
create or replace function public.create_package_draft(
	slug text,
	name text,
	actor_owner_email text,
	idempotency_key text,
	copy_from_package_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
		monthly_price_usd_cents, yearly_price_usd_cents, updated_by_email
	) values (
		new_package_id, 'draft', trim(create_package_draft.name), source_edition.promise,
		coalesce(source_edition.highlights, '[]'::jsonb), coalesce(source_edition.included_services, '[]'::jsonb),
		source_edition.exclusions, source_edition.monthly_price_usd_cents, source_edition.yearly_price_usd_cents,
		trim(actor_owner_email)
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

	return jsonb_build_object('applied', true, 'package_id', new_package_id);
end;
$$;

-- Opens a draft of a published package, starting from its published terms. Returns the existing draft
-- when there already is one.
create or replace function public.open_package_draft(target_package_id uuid, actor_owner_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
		monthly_price_usd_cents, yearly_price_usd_cents, updated_by_email
	) values (
		target_package_id, 'draft', source_edition.name, source_edition.promise, source_edition.highlights,
		source_edition.included_services, source_edition.exclusions, source_edition.monthly_price_usd_cents,
		source_edition.yearly_price_usd_cents, trim(actor_owner_email)
	)
	returning id into draft_id;

	insert into public.package_edition_capabilities (edition_id, capability_key)
	select draft_id, c.capability_key from public.package_edition_capabilities c where c.edition_id = source_edition.id;
	insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
	select draft_id, a.allowance_key, a.allowance_state, a.allowance_value
	from public.package_edition_allowances a where a.edition_id = source_edition.id;

	return jsonb_build_object('applied', true, 'edition_id', draft_id);
end;
$$;

-- Saves the whole draft in one transaction. When the draft moved past loaded_revision (another tab saved
-- first), nothing is written and the newer draft comes back for the editor to compare.
create or replace function public.save_package_draft(
	target_package_id uuid,
	draft_edition_id uuid,
	loaded_revision integer,
	terms jsonb,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	draft public.package_editions;
	new_slug text := nullif(trim(coalesce(terms ->> 'slug', '')), '');
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
		revision = draft.revision + 1,
		updated_by_email = trim(actor_owner_email)
	where id = draft.id;

	perform private.write_package_draft_rows(draft.id, terms);

	return jsonb_build_object('saved', true, 'draft', private.package_edition_terms(draft.id));
end;
$$;

-- Deletes a draft. A package that was never published goes with it, unless an email template is limited
-- to it. A published package keeps its published edition and customers; only the draft goes.
create or replace function public.delete_package_draft(
	target_package_id uuid,
	draft_edition_id uuid,
	loaded_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	draft public.package_editions;
	package_removed boolean;
begin
	perform 1 from public.packages p where p.id = target_package_id for update;

	select e.* into draft from public.package_editions e
	where e.id = draft_edition_id and e.package_id = target_package_id
	for update;
	if draft.id is null or draft.status <> 'draft' then
		raise exception 'This draft no longer exists. It may have been published or deleted in another tab.'
			using errcode = 'P0002';
	end if;
	if draft.revision <> loaded_revision then
		return jsonb_build_object('deleted', false, 'reason', 'stale', 'draft', private.package_edition_terms(draft.id));
	end if;

	package_removed := not exists (
		select 1 from public.package_editions e where e.package_id = target_package_id and e.id <> draft.id
	);
	if package_removed and exists (
		select 1 from public.platform_email_template_packages t where t.package_id = target_package_id
	) then
		raise exception 'An email template is limited to this package. Change that template first.'
			using errcode = 'check_violation';
	end if;

	delete from public.package_editions where id = draft.id;
	if package_removed then
		delete from public.packages where id = target_package_id;
	end if;

	return jsonb_build_object('deleted', true, 'package_removed', package_removed);
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Only the owner service role runs the commands and readers.
-- ---------------------------------------------------------------------------------------------------

revoke all on function private.package_edition_terms(uuid) from public, anon, authenticated;
revoke all on function private.write_package_draft_rows(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.owner_package_catalog() from public, anon, authenticated;
revoke all on function public.owner_package_builder(uuid) from public, anon, authenticated;
revoke all on function public.create_package_draft(text, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.open_package_draft(uuid, text) from public, anon, authenticated;
revoke all on function public.save_package_draft(uuid, uuid, integer, jsonb, text) from public, anon, authenticated;
revoke all on function public.delete_package_draft(uuid, uuid, integer) from public, anon, authenticated;

grant execute on function private.package_edition_terms(uuid) to service_role;
grant execute on function private.write_package_draft_rows(uuid, jsonb) to service_role;
grant execute on function public.owner_package_catalog() to service_role;
grant execute on function public.owner_package_builder(uuid) to service_role;
grant execute on function public.create_package_draft(text, text, text, text, uuid) to service_role;
grant execute on function public.open_package_draft(uuid, text) to service_role;
grant execute on function public.save_package_draft(uuid, uuid, integer, jsonb, text) to service_role;
grant execute on function public.delete_package_draft(uuid, uuid, integer) to service_role;
