-- Package builder P7 (ADR 0003 decisions 2, 3, 4, 8): publish, visibility, display order, archive, restore,
-- the website-update reminder, and the catalog history.
--
-- Publishing names the draft and revision Jafar reviewed and freezes that draft as the next edition; the
-- previous published edition becomes superseded and stays readable for customers still on it. Publishing
-- refuses unsellable capabilities, missing requirements, and allowances that contradict the chosen
-- capabilities. Visibility, order, and archiving change the package, never an edition's terms.
--
-- The marketing site is maintained by hand, so any change to what the public catalog lists leaves a
-- reminder on the package until Jafar confirms the site matches. Every catalog action appends one history
-- row; history rows are never edited.

alter table public.packages
	add column website_update_pending_since timestamptz;

comment on column public.packages.website_update_pending_since is
	'Set when a change alters what the public catalog lists; cleared when Jafar confirms the marketing site matches.';

create table public.package_catalog_events (
	id uuid primary key default gen_random_uuid(),
	package_id uuid not null references public.packages (id) on delete cascade,
	event_type text not null check (event_type in (
		'created', 'published', 'visibility_changed', 'moved', 'archived', 'restored', 'draft_discarded',
		'website_confirmed'
	)),
	edition_number integer check (edition_number is null or edition_number > 0),
	detail jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
	actor_email text check (actor_email is null or char_length(trim(actor_email)) between 3 and 320),
	created_at timestamptz not null default now()
);

create index package_catalog_events_package_idx on public.package_catalog_events (package_id, created_at desc);

comment on table public.package_catalog_events is
	'Append-only history of package catalog actions. Rows go only with a never-published package that is deleted.';

create or replace function private.prevent_package_catalog_event_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	raise exception 'Package history cannot be changed.' using errcode = 'check_violation';
end;
$$;

create trigger package_catalog_events_append_only
	before update on public.package_catalog_events
	for each row execute function private.prevent_package_catalog_event_change();

alter table public.package_catalog_events enable row level security;
revoke all on public.package_catalog_events from anon, authenticated;
grant all on public.package_catalog_events to service_role;
revoke all on function private.prevent_package_catalog_event_change() from public, anon, authenticated;

-- The test package was published when the package system was replaced.
insert into public.package_catalog_events (package_id, event_type, edition_number, detail, actor_email, created_at)
select p.id, 'published', e.edition_number, jsonb_build_object('name', e.name), p.created_by_email, e.published_at
from public.packages p
join public.package_editions e on e.package_id = p.id and e.status = 'published';

-- ---------------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------------

-- Whether the public catalog lists this package: public, not archived, and published.
create or replace function private.package_is_listed(target_package_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
	select exists (
		select 1
		from public.packages p
		join public.package_editions e on e.package_id = p.id and e.status = 'published'
		where p.id = target_package_id and p.visibility = 'public' and p.archived_at is null
	);
$$;

-- Leaves the website reminder on a package, keeping the earliest unconfirmed change.
create or replace function private.flag_package_website_update(target_package_id uuid)
returns void
language sql
set search_path = ''
as $$
	update public.packages
	set website_update_pending_since = coalesce(website_update_pending_since, now())
	where id = target_package_id;
$$;

-- What stops an edition from being published, in words Jafar can act on. An empty array means ready.
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
	)
	select coalesce(
		jsonb_agg(jsonb_build_object('code', code, 'key', key, 'message', message) order by rank, key),
		'[]'::jsonb
	)
	from problems;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Readers: the catalog and builder gain the reminder, publish readiness, and history.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.package_history(target_package_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
	select coalesce(jsonb_agg(jsonb_build_object(
		'id', h.id, 'event_type', h.event_type, 'edition_number', h.edition_number, 'detail', h.detail,
		'actor_email', h.actor_email, 'created_at', h.created_at
	) order by h.created_at desc), '[]'::jsonb)
	from (
		select * from public.package_catalog_events ev
		where ev.package_id = target_package_id
		order by ev.created_at desc
		limit 100
	) as h;
$$;

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
				'website_update_pending_since', p.website_update_pending_since,
				'website_changes', case when p.website_update_pending_since is null then '[]'::jsonb else (
					select coalesce(jsonb_agg(jsonb_build_object(
						'event_type', ev.event_type, 'edition_number', ev.edition_number, 'detail', ev.detail,
						'created_at', ev.created_at
					) order by ev.created_at), '[]'::jsonb)
					from public.package_catalog_events ev
					where ev.package_id = p.id and ev.created_at >= p.website_update_pending_since
						and ev.event_type in ('published', 'visibility_changed', 'moved', 'archived', 'restored')
				) end,
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
		)
	)
	from public.packages p
	where p.id = target_package_id;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------------

-- Publishes the draft Jafar reviewed. Returns stale with the newer draft when it moved past
-- reviewed_revision, not_ready with the problems when it cannot be sold, and applied false when this
-- exact draft was already published (a retried request).
create or replace function public.publish_package_draft(
	target_package_id uuid,
	draft_edition_id uuid,
	reviewed_revision integer,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	draft public.package_editions;
	problems jsonb;
	next_number integer;
	previous_number integer;
begin
	perform 1 from public.packages p where p.id = target_package_id for update;
	if not found then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;

	select e.* into draft from public.package_editions e
	where e.id = draft_edition_id and e.package_id = target_package_id;
	if draft.id is null then
		raise exception 'This draft no longer exists. It may have been deleted in another tab.'
			using errcode = 'P0002';
	end if;
	if draft.status <> 'draft' then
		if draft.revision = reviewed_revision then
			return jsonb_build_object('published', true, 'applied', false, 'edition_number', draft.edition_number);
		end if;
		raise exception 'This draft was already published in another tab.' using errcode = 'P0002';
	end if;
	if draft.revision <> reviewed_revision then
		return jsonb_build_object('published', false, 'reason', 'stale', 'draft', private.package_edition_terms(draft.id));
	end if;

	problems := private.package_publish_problems(draft.id);
	if jsonb_array_length(problems) > 0 then
		return jsonb_build_object('published', false, 'reason', 'not_ready', 'problems', problems);
	end if;

	select coalesce(max(e.edition_number), 0) + 1 into next_number
	from public.package_editions e where e.package_id = target_package_id;

	update public.package_editions set status = 'superseded', superseded_at = now()
	where package_id = target_package_id and status = 'published'
	returning edition_number into previous_number;

	update public.package_editions
	set status = 'published', edition_number = next_number, published_at = now()
	where id = draft.id;

	insert into public.package_catalog_events (package_id, event_type, edition_number, detail, actor_email)
	values (target_package_id, 'published', next_number,
		jsonb_build_object('name', draft.name, 'replaces_edition_number', previous_number), trim(actor_owner_email));

	if private.package_is_listed(target_package_id) then
		perform private.flag_package_website_update(target_package_id);
	end if;

	return jsonb_build_object('published', true, 'applied', true, 'edition_number', next_number);
end;
$$;

-- Public packages are listed for new customers once published; private ones are assigned by Jafar only.
create or replace function public.set_package_visibility(
	target_package_id uuid,
	new_visibility text,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_visibility text;
	was_listed boolean;
begin
	if new_visibility not in ('public', 'private') then
		raise exception 'Choose public or private.' using errcode = 'check_violation';
	end if;
	select p.visibility into current_visibility from public.packages p where p.id = target_package_id for update;
	if current_visibility is null then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;
	if current_visibility = new_visibility then
		return jsonb_build_object('applied', false);
	end if;

	was_listed := private.package_is_listed(target_package_id);
	update public.packages set visibility = new_visibility where id = target_package_id;

	insert into public.package_catalog_events (package_id, event_type, detail, actor_email)
	values (target_package_id, 'visibility_changed',
		jsonb_build_object('from', current_visibility, 'to', new_visibility), trim(actor_owner_email));

	if was_listed <> private.package_is_listed(target_package_id) then
		perform private.flag_package_website_update(target_package_id);
	end if;
	return jsonb_build_object('applied', true);
end;
$$;

-- Moves a package one place up or down the catalog. Every package is renumbered 1..n in its current order
-- so equal or missing positions cannot make a move silently do nothing.
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
	position_now integer;
	neighbour_position integer;
	neighbour_id uuid;
begin
	if direction not in ('up', 'down') then
		raise exception 'Choose up or down.' using errcode = 'check_violation';
	end if;

	perform 1 from public.packages p order by p.id for update;
	select array_agg(p.id order by p.display_order, p.created_at, p.id) into ordered from public.packages p;
	position_now := array_position(ordered, target_package_id);
	if position_now is null then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;

	neighbour_position := position_now + case when direction = 'up' then -1 else 1 end;
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
	values (target_package_id, 'moved',
		jsonb_build_object('from', position_now, 'to', neighbour_position), trim(actor_owner_email));

	if private.package_is_listed(target_package_id) and private.package_is_listed(neighbour_id) then
		perform private.flag_package_website_update(target_package_id);
	end if;
	return jsonb_build_object('applied', true);
end;
$$;

-- Archiving stops new customers choosing the package; customers already on it keep their edition and
-- access. Restoring brings it back. A never-published package has nothing to archive; delete its draft.
create or replace function public.set_package_archived(
	target_package_id uuid,
	archived boolean,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_archived_at timestamptz;
	was_listed boolean;
begin
	select p.archived_at into current_archived_at from public.packages p where p.id = target_package_id for update;
	if not found then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;
	if (current_archived_at is not null) = archived then
		return jsonb_build_object('applied', false);
	end if;
	if archived and not exists (
		select 1 from public.package_editions e where e.package_id = target_package_id and e.status <> 'draft'
	) then
		raise exception 'This package was never published, so there is nothing to archive. Delete the draft instead.'
			using errcode = 'check_violation';
	end if;

	was_listed := private.package_is_listed(target_package_id);
	update public.packages set archived_at = case when archived then now() end where id = target_package_id;

	insert into public.package_catalog_events (package_id, event_type, actor_email)
	values (target_package_id, case when archived then 'archived' else 'restored' end, trim(actor_owner_email));

	if was_listed <> private.package_is_listed(target_package_id) then
		perform private.flag_package_website_update(target_package_id);
	end if;
	return jsonb_build_object('applied', true);
end;
$$;

-- Jafar confirms the marketing site matches. Names the reminder he saw; a newer change keeps it open.
create or replace function public.confirm_package_website_update(
	target_package_id uuid,
	seen_pending_since timestamptz,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	pending timestamptz;
begin
	select p.website_update_pending_since into pending from public.packages p where p.id = target_package_id for update;
	if not found then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;
	if pending is null then
		return jsonb_build_object('confirmed', true, 'applied', false);
	end if;
	if pending <> seen_pending_since then
		return jsonb_build_object('confirmed', false, 'reason', 'stale');
	end if;

	update public.packages set website_update_pending_since = null where id = target_package_id;
	insert into public.package_catalog_events (package_id, event_type, detail, actor_email)
	values (target_package_id, 'website_confirmed', jsonb_build_object('pending_since', pending),
		trim(actor_owner_email));
	return jsonb_build_object('confirmed', true, 'applied', true);
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- P6 commands, unchanged except that creating a package and discarding a published package's draft now
-- leave a history row.
-- ---------------------------------------------------------------------------------------------------

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

	insert into public.package_catalog_events (package_id, event_type, detail, actor_email)
	values (new_package_id, 'created',
		jsonb_build_object('name', trim(create_package_draft.name), 'copied_from_package_id', copy_from_package_id),
		trim(actor_owner_email));

	return jsonb_build_object('applied', true, 'package_id', new_package_id);
end;
$$;

create or replace function public.delete_package_draft(
	target_package_id uuid,
	draft_edition_id uuid,
	loaded_revision integer,
	actor_owner_email text default null
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
	else
		insert into public.package_catalog_events (package_id, event_type, detail, actor_email)
		values (target_package_id, 'draft_discarded', jsonb_build_object('name', draft.name),
			nullif(trim(coalesce(actor_owner_email, '')), ''));
	end if;

	return jsonb_build_object('deleted', true, 'package_removed', package_removed);
end;
$$;

drop function public.delete_package_draft(uuid, uuid, integer);

-- ---------------------------------------------------------------------------------------------------
-- Only the owner service role runs the commands and readers.
-- ---------------------------------------------------------------------------------------------------

revoke all on function private.package_is_listed(uuid) from public, anon, authenticated;
revoke all on function private.flag_package_website_update(uuid) from public, anon, authenticated;
revoke all on function private.package_publish_problems(uuid) from public, anon, authenticated;
revoke all on function private.package_history(uuid) from public, anon, authenticated;
revoke all on function public.publish_package_draft(uuid, uuid, integer, text) from public, anon, authenticated;
revoke all on function public.set_package_visibility(uuid, text, text) from public, anon, authenticated;
revoke all on function public.move_package(uuid, text, text) from public, anon, authenticated;
revoke all on function public.set_package_archived(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.confirm_package_website_update(uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.delete_package_draft(uuid, uuid, integer, text) from public, anon, authenticated;

grant execute on function private.package_is_listed(uuid) to service_role;
grant execute on function private.flag_package_website_update(uuid) to service_role;
grant execute on function private.package_publish_problems(uuid) to service_role;
grant execute on function private.package_history(uuid) to service_role;
grant execute on function public.publish_package_draft(uuid, uuid, integer, text) to service_role;
grant execute on function public.set_package_visibility(uuid, text, text) to service_role;
grant execute on function public.move_package(uuid, text, text) to service_role;
grant execute on function public.set_package_archived(uuid, boolean, text) to service_role;
grant execute on function public.confirm_package_website_update(uuid, timestamptz, text) to service_role;
grant execute on function public.delete_package_draft(uuid, uuid, integer, text) to service_role;
