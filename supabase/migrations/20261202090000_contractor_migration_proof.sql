-- Multi-industry platform foundation B10: test migration of an existing Contractor.
--
-- 1. A repeatable inventory of one business: for every table that holds its records, how many rows, a
--    fingerprint of their identifiers and a fingerprint of their contents, plus a readable summary of what
--    customers can still reach. Secrets are never copied (links are only counted; their token hashes stay put).
-- 2. Snapshots: an inventory taken on purpose and kept, so "before" and "after" can be compared later.
-- 3. A recovery switch: the business's access can be put back on the path it used before experience
--    decisions existed (judged by the one experience its agreed package is sold to), and returned again. The
--    switch is an append-only history. Nothing is deleted, and no decision, agreement or customer record is
--    rewritten by either direction.
-- 4. One shared answer for "which experience decision is in force", used by the access snapshot and both
--    database capability checks, so they cannot disagree about a switched-back business.

-- ---------------------------------------------------------------------------------------------------
-- Recovery switch
-- ---------------------------------------------------------------------------------------------------

create table public.organization_experience_path_changes (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	-- 'experience': follow the confirmed profile. 'previous_contractor': ignore the profile and judge access
	-- by the experience the agreed package is sold to, as before profiles existed.
	path text not null check (path in ('experience', 'previous_contractor')),
	reason text not null check (char_length(trim(reason)) between 1 and 1000),
	actor_email text not null check (char_length(trim(actor_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	changed_at timestamptz not null default clock_timestamp()
);

comment on table public.organization_experience_path_changes is
	'Append-only history of which access path a business follows. The newest row decides; no row means the confirmed profile is followed.';

create index organization_experience_path_changes_history_idx
	on public.organization_experience_path_changes (organization_id, changed_at desc, id desc);

create trigger organization_experience_path_changes_append_only
	before update or delete on public.organization_experience_path_changes
	for each row execute function private.prevent_experience_decision_change();

create or replace function private.organization_experience_path(target_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce((
		select c.path
		from public.organization_experience_path_changes c
		where c.organization_id = target_organization_id
		order by c.changed_at desc, c.id desc
		limit 1
	), 'experience');
$$;

revoke all on function private.organization_experience_path(uuid) from public, anon;
grant execute on function private.organization_experience_path(uuid) to authenticated, service_role;

-- The experience decision in force: the head of the business's decision chain, unless the business is
-- switched back, in which case no decision is in force and the edition-based answer applies.
create or replace function private.organization_active_experience_head(target_organization_id uuid)
returns table (experience_key text, definition_version integer)
language sql
stable
security definer
set search_path = ''
as $$
	select d.experience_key, d.definition_version
	from public.organization_experience_decisions d
	where d.organization_id = target_organization_id
		and private.organization_experience_path(target_organization_id) = 'experience'
		and not exists (
			select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id
		);
$$;

revoke all on function private.organization_active_experience_head(uuid) from public, anon;
grant execute on function private.organization_active_experience_head(uuid) to authenticated, service_role;

-- Offered experiences and the capability check read the shared answer instead of walking the chain.
create or replace function private.organization_offer_experiences(target_organization_id uuid)
returns text[]
language sql
stable
set search_path = ''
as $$
	select coalesce(
		(select array[h.experience_key] from private.organization_active_experience_head(target_organization_id) h),
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

create or replace function private.capability_fits_organization(target_organization_id uuid, target_capability_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	with family as (
		select c.capability_family from public.package_capabilities c where c.capability_key = target_capability_key
	), head as (
		select h.experience_key, h.definition_version
		from private.organization_active_experience_head(target_organization_id) h
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

-- The access snapshot's experience answer. Identical to before, except that a switched-back business skips
-- its decision chain and is judged by its agreed package's audience.
create or replace function public.organization_experience_basis(target_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	allowed boolean;
	decision_count integer;
	head_row record;
	definition_row record;
	audience text[];
begin
	select coalesce((select auth.role()) = 'service_role', false) or exists (
		select 1 from public.organization_members m
		where m.organization_id = target_organization_id
			and m.user_id = (select auth.uid())
			and m.status = 'active'
	) into allowed;
	if not allowed then
		return jsonb_build_object('state', 'none', 'reason', 'not_a_member');
	end if;

	select count(*) into decision_count
	from public.organization_experience_decisions d
	where d.organization_id = target_organization_id;

	if decision_count > 0 and private.organization_experience_path(target_organization_id) = 'experience' then
		-- The head is the decision no later one replaces. More or fewer than one means the chain is broken.
		if (
			select count(*) from public.organization_experience_decisions d
			where d.organization_id = target_organization_id
				and not exists (select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id)
		) <> 1 then
			return jsonb_build_object('state', 'none', 'reason', 'unresolved_history');
		end if;
		select d.experience_key, d.definition_version into head_row
		from public.organization_experience_decisions d
		where d.organization_id = target_organization_id
			and not exists (select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id);
		select x.experience_key, x.version, x.capability_families into definition_row
		from public.industry_experience_definitions x
		where x.experience_key = head_row.experience_key and x.version = head_row.definition_version;
		if definition_row.experience_key is null then
			return jsonb_build_object('state', 'none', 'reason', 'unknown_definition');
		end if;
		return jsonb_build_object(
			'state', 'confirmed', 'experience', definition_row.experience_key,
			'definition_version', definition_row.version, 'families', to_jsonb(definition_row.capability_families));
	end if;

	-- No profile in force: judge against the one experience the agreed edition is sold to, never a guess.
	select e.experience_keys into audience
	from public.organization_package_agreements a
	join public.package_editions e on e.id = a.edition_id
	where a.organization_id = target_organization_id and a.cancelled_at is null and a.effective_from <= now()
	order by a.effective_from desc, a.created_at desc
	limit 1;
	if audience is null or cardinality(audience) <> 1 then
		return jsonb_build_object('state', 'none', 'reason', 'no_single_experience');
	end if;
	select d.experience_key, d.version, d.capability_families into definition_row
	from private.offered_experience_definitions() d
	where d.experience_key = audience[1];
	if definition_row.experience_key is null then
		return jsonb_build_object('state', 'none', 'reason', 'unknown_definition');
	end if;
	return jsonb_build_object(
		'state', 'planned', 'experience', definition_row.experience_key,
		'definition_version', definition_row.version, 'families', to_jsonb(definition_row.capability_families));
end;
$$;

revoke all on function public.organization_experience_basis(uuid) from public, anon;
grant execute on function public.organization_experience_basis(uuid) to authenticated, service_role;

-- One owner command. Asking for the path the business already follows changes nothing.
create or replace function public.record_organization_experience_path(
	target_organization_id uuid,
	target_path text,
	change_reason text,
	actor_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing_change public.organization_experience_path_changes%rowtype;
	inserted_id uuid;
begin
	select * into existing_change
	from public.organization_experience_path_changes c
	where c.idempotency_key = record_organization_experience_path.idempotency_key;
	if found then
		if existing_change.organization_id <> target_organization_id then
			raise exception 'This request key was already used for another organization.' using errcode = 'unique_violation';
		end if;
		return jsonb_build_object('applied', false, 'change_id', existing_change.id, 'path', existing_change.path);
	end if;

	perform 1 from public.organizations o where o.id = target_organization_id for update;
	if not found then
		raise exception 'Organization was not found.' using errcode = 'foreign_key_violation';
	end if;

	if target_path not in ('experience', 'previous_contractor') then
		raise exception 'That access path is not offered.' using errcode = 'check_violation';
	end if;
	if private.organization_experience_path(target_organization_id) = target_path then
		return jsonb_build_object('applied', false, 'change_id', null, 'path', target_path);
	end if;

	insert into public.organization_experience_path_changes (
		organization_id, path, reason, actor_email, idempotency_key
	) values (
		target_organization_id, target_path, trim(change_reason), lower(trim(actor_email)),
		record_organization_experience_path.idempotency_key
	)
	returning id into inserted_id;

	return jsonb_build_object('applied', true, 'change_id', inserted_id, 'path', target_path);
end;
$$;

revoke all on function public.record_organization_experience_path(uuid, text, text, text, text)
	from public, anon, authenticated;
grant execute on function public.record_organization_experience_path(uuid, text, text, text, text)
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- Inventory
-- ---------------------------------------------------------------------------------------------------

-- Tables this migration's own commands write to, left out so taking a snapshot or switching a business
-- never counts as a change to its records.
create or replace function private.organization_inventory_excluded_tables()
returns text[]
language sql
immutable
set search_path = ''
as $$
	select array[
		'public.organization_experience_decisions',
		'public.organization_experience_path_changes',
		'public.organization_migration_snapshots',
		'public.access_audit_events'
	];
$$;

create or replace function private.organization_inventory(target_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	scanned record;
	stat record;
	tables jsonb := '{}'::jsonb;
	summary jsonb;
	excluded text[] := private.organization_inventory_excluded_tables();
begin
	for scanned in
		select c.table_schema, c.table_name,
			exists (
				select 1 from information_schema.columns i
				where i.table_schema = c.table_schema and i.table_name = c.table_name and i.column_name = 'id'
			) as has_id
		from information_schema.columns c
		join information_schema.tables t
			on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
		where c.column_name = 'organization_id'
			and c.data_type = 'uuid'
			and c.table_schema in ('public', 'private')
			and (c.table_schema || '.' || c.table_name) <> all (excluded)
		order by c.table_schema, c.table_name
	loop
		execute format(
			'select count(*)::integer as n, %s as ids, md5(string_agg(md5(t::text), '','' order by md5(t::text))) as content '
			'from %I.%I t where t.organization_id = $1',
			case when scanned.has_id then 'md5(string_agg(t.id::text, '','' order by t.id::text))' else 'null::text' end,
			scanned.table_schema, scanned.table_name
		) into stat using target_organization_id;
		if stat.n > 0 then
			tables := tables || jsonb_build_object(
				scanned.table_schema || '.' || scanned.table_name,
				jsonb_build_object('rows', stat.n, 'ids', stat.ids, 'content', stat.content)
			);
		end if;
	end loop;

	-- A readable summary. Links are only counted: "usable" means not revoked and not past its expiry.
	select jsonb_build_object(
		'organization', (
			select jsonb_build_object('id', o.id, 'slug', o.slug, 'lifecycle_status', o.lifecycle_status)
			from public.organizations o where o.id = target_organization_id
		),
		'current_agreement_id', (
			select a.id from public.organization_package_agreements a
			where a.organization_id = target_organization_id and a.cancelled_at is null and a.effective_from <= now()
			order by a.effective_from desc, a.created_at desc limit 1
		),
		'members', coalesce((
			select jsonb_object_agg(role, n) from (
				select m.role, count(*)::integer as n
				from public.organization_members m
				where m.organization_id = target_organization_id and m.status = 'active'
				group by m.role
			) roles
		), '{}'::jsonb),
		'customer_links', jsonb_build_object(
			'quote', (
				select jsonb_build_object('issued', count(*), 'usable', count(*) filter (where revoked_at is null and expires_at > now()))
				from public.quote_access_links l where l.organization_id = target_organization_id),
			'invoice', (
				select jsonb_build_object('issued', count(*), 'usable', count(*) filter (where revoked_at is null and expires_at > now()))
				from public.invoice_access_links l where l.organization_id = target_organization_id),
			'job_report', (
				select jsonb_build_object('issued', count(*), 'usable', count(*) filter (where revoked_at is null and expires_at > now()))
				from public.job_report_access_links l where l.organization_id = target_organization_id),
			'payment_receipt', (
				select jsonb_build_object('issued', count(*), 'usable', count(*) filter (where revoked_at is null and expires_at > now()))
				from public.payment_receipt_access_links l where l.organization_id = target_organization_id),
			'file_share', (
				select jsonb_build_object('issued', count(*), 'usable', count(*) filter (where revoked_at is null and expires_at > now()))
				from public.file_shares l where l.organization_id = target_organization_id)
		),
		'forms', (
			select jsonb_build_object(
				'total', count(*),
				'live', count(*) filter (where f.is_enabled and f.current_published_version_id is not null and f.archived_at is null)
			)
			from public.forms f where f.organization_id = target_organization_id
		),
		'open_areas', coalesce((
			select jsonb_agg(d.area_key order by d.area_key)
			from public.organization_readiness_decisions d
			where d.organization_id = target_organization_id and d.status = 'ready'
				and not exists (select 1 from public.organization_readiness_decisions later where later.previous_decision_id = d.id)
		), '[]'::jsonb),
		'experience_path', private.organization_experience_path(target_organization_id)
	) into summary;

	return jsonb_build_object('taken_at', now(), 'summary', summary, 'tables', tables);
end;
$$;

revoke all on function private.organization_inventory(uuid) from public, anon, authenticated;
grant execute on function private.organization_inventory(uuid) to service_role;
revoke all on function private.organization_inventory_excluded_tables() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- Snapshots
-- ---------------------------------------------------------------------------------------------------

create table public.organization_migration_snapshots (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	label text not null check (char_length(trim(label)) between 1 and 80),
	inventory jsonb not null,
	actor_email text not null check (char_length(trim(actor_email)) between 3 and 320),
	taken_at timestamptz not null default clock_timestamp()
);

comment on table public.organization_migration_snapshots is
	'Inventories of one business taken on purpose, so before and after a switch can be compared. Append-only.';

create index organization_migration_snapshots_history_idx
	on public.organization_migration_snapshots (organization_id, taken_at desc, id desc);

create trigger organization_migration_snapshots_append_only
	before update on public.organization_migration_snapshots
	for each row execute function private.prevent_experience_decision_change();

create or replace function public.take_organization_migration_snapshot(
	target_organization_id uuid,
	snapshot_label text,
	actor_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	inserted_id uuid;
begin
	perform 1 from public.organizations o where o.id = target_organization_id;
	if not found then
		raise exception 'Organization was not found.' using errcode = 'foreign_key_violation';
	end if;
	insert into public.organization_migration_snapshots (organization_id, label, inventory, actor_email)
	values (
		target_organization_id, trim(snapshot_label), private.organization_inventory(target_organization_id),
		lower(trim(actor_email))
	)
	returning id into inserted_id;
	return jsonb_build_object('snapshot_id', inserted_id);
end;
$$;

revoke all on function public.take_organization_migration_snapshot(uuid, text, text) from public, anon, authenticated;
grant execute on function public.take_organization_migration_snapshot(uuid, text, text) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- Row security: Uplift reads and writes through the service role only.
-- ---------------------------------------------------------------------------------------------------

alter table public.organization_experience_path_changes enable row level security;
alter table public.organization_migration_snapshots enable row level security;

revoke all on public.organization_experience_path_changes, public.organization_migration_snapshots
	from anon, authenticated;
grant all on public.organization_experience_path_changes, public.organization_migration_snapshots
	to service_role;
