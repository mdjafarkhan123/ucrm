-- Multi-industry platform foundation B1: Experience identity.
--
-- 1. A reviewable, versioned Industry experience definition. A published version is frozen; a change is a
--    new version. Contractor v1 is the first and only selectable definition: its Business types follow
--    Jobber's published list of the industries it serves.
-- 2. An append-only history of each Organization's experience decisions: who confirmed which experience,
--    Business type and reviewed services, against which Agreement, when and why. The head of that chain is the
--    Organization's current experience profile. Nothing is backfilled here; existing Organizations stay
--    without a profile until Uplift reviews them (P4 migration plan), and a missing profile never means
--    Contractor.
-- 3. One owner command records a decision. It refuses a stale review, an unpublished definition, a Business
--    type the definition does not offer and a change of primary experience (an assisted transition, not
--    built yet).

-- ---------------------------------------------------------------------------------------------------
-- Definitions
-- ---------------------------------------------------------------------------------------------------

create table public.industry_experience_definitions (
	experience_key text not null check (experience_key ~ '^[a-z][a-z_]{1,39}$'),
	version integer not null check (version >= 1),
	name text not null check (char_length(trim(name)) between 1 and 80),
	status text not null check (status in ('draft', 'published', 'retired')),
	capability_families text[] not null check (
		cardinality(capability_families) >= 1
		and capability_families <@ array['shared_platform', 'field_service', 'appointment_business', 'clinical_extension']
	),
	required_safety_controls text[] not null default '{}',
	change_summary text not null check (char_length(trim(change_summary)) between 1 and 1000),
	published_at timestamptz,
	created_at timestamptz not null default now(),
	primary key (experience_key, version),
	check ((status = 'draft') = (published_at is null))
);

comment on table public.industry_experience_definitions is
	'Versioned Industry experience definitions. A published or retired version is frozen; only publishing a draft or retiring a published version may change its status.';

create table public.industry_experience_business_types (
	experience_key text not null,
	definition_version integer not null,
	business_type_key text not null check (business_type_key ~ '^[a-z][a-z_]{1,39}$'),
	label text not null check (char_length(trim(label)) between 1 and 80),
	position integer not null check (position >= 0),
	primary key (experience_key, definition_version, business_type_key),
	foreign key (experience_key, definition_version)
		references public.industry_experience_definitions (experience_key, version)
);

create or replace function private.prevent_frozen_experience_definition_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
	definition_status text;
begin
	if tg_table_name = 'industry_experience_definitions' then
		if tg_op = 'DELETE' then
			if old.status <> 'draft' then
				raise exception 'A published experience definition cannot be removed.' using errcode = 'check_violation';
			end if;
			return old;
		end if;
		if old.status = 'draft' then
			return new;
		end if;
		-- A frozen version may only move published -> retired, with nothing else changing.
		if old.status = 'published' and new.status = 'retired'
			and (new.experience_key, new.version, new.name, new.capability_families, new.required_safety_controls,
				new.change_summary, new.published_at, new.created_at)
				is not distinct from (old.experience_key, old.version, old.name, old.capability_families,
				old.required_safety_controls, old.change_summary, old.published_at, old.created_at) then
			return new;
		end if;
		raise exception 'A published experience definition is frozen. Publish a new version instead.'
			using errcode = 'check_violation';
	end if;

	if tg_op <> 'INSERT' then
		select d.status into definition_status
		from public.industry_experience_definitions d
		where d.experience_key = old.experience_key and d.version = old.definition_version;
		if definition_status is distinct from 'draft' then
			raise exception 'The Business types of a published experience definition are frozen.'
				using errcode = 'check_violation';
		end if;
	end if;
	if tg_op <> 'DELETE' then
		select d.status into definition_status
		from public.industry_experience_definitions d
		where d.experience_key = new.experience_key and d.version = new.definition_version;
		if definition_status is distinct from 'draft' then
			raise exception 'The Business types of a published experience definition are frozen.'
				using errcode = 'check_violation';
		end if;
		return new;
	end if;
	return old;
end;
$$;

-- Business types are added while the definition is a draft, then frozen with it.
create trigger industry_experience_business_types_frozen
	before insert or update or delete on public.industry_experience_business_types
	for each row execute function private.prevent_frozen_experience_definition_change();

-- ---------------------------------------------------------------------------------------------------
-- Contractor v1
-- ---------------------------------------------------------------------------------------------------

insert into public.industry_experience_definitions
	(experience_key, version, name, status, capability_families, change_summary)
values (
	'contractor', 1, 'Contractor', 'draft', array['shared_platform', 'field_service'],
	'The existing Contractor edition: Requests, Quotes, Jobs, Visits and Invoices, following Jobber. Business types follow Jobber''s published list of the industries it serves.'
);

insert into public.industry_experience_business_types
	(experience_key, definition_version, business_type_key, label, position)
values
	('contractor', 1, 'hvac', 'HVAC', 10),
	('contractor', 1, 'plumbing', 'Plumbing', 20),
	('contractor', 1, 'electrical', 'Electrical', 30),
	('contractor', 1, 'roofing', 'Roofing', 40),
	('contractor', 1, 'landscaping', 'Landscaping', 50),
	('contractor', 1, 'lawn_care', 'Lawn care', 60),
	('contractor', 1, 'tree_care', 'Arborist and tree care', 70),
	('contractor', 1, 'pool_spa_service', 'Pool and spa service', 80),
	('contractor', 1, 'residential_cleaning', 'Residential cleaning', 90),
	('contractor', 1, 'commercial_cleaning', 'Commercial cleaning and janitorial', 100),
	('contractor', 1, 'construction_renovation', 'Construction and renovation', 110),
	('contractor', 1, 'general_contracting', 'General contracting', 120),
	('contractor', 1, 'handyman', 'Handyman services', 130),
	('contractor', 1, 'junk_removal', 'Junk removal', 140),
	('contractor', 1, 'painting', 'Painting', 150),
	('contractor', 1, 'pressure_washing', 'Pressure washing', 160),
	('contractor', 1, 'window_cleaning', 'Window cleaning', 170),
	('contractor', 1, 'snow_removal', 'Snow removal', 180),
	('contractor', 1, 'other_field_service', 'Other field service', 190);

update public.industry_experience_definitions
set status = 'published', published_at = now()
where experience_key = 'contractor' and version = 1;

create trigger industry_experience_definitions_frozen
	before update or delete on public.industry_experience_definitions
	for each row execute function private.prevent_frozen_experience_definition_change();

-- ---------------------------------------------------------------------------------------------------
-- Organization experience decisions
-- ---------------------------------------------------------------------------------------------------

create table public.organization_experience_decisions (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	experience_key text not null,
	definition_version integer not null,
	-- Null means the Business type is not yet confirmed. It is never guessed from trade text.
	business_type_key text,
	-- The services Uplift reviewed, in its own words.
	service_shape text not null check (char_length(trim(service_shape)) between 1 and 1000),
	-- The Agreement in force when the decision was recorded; null when the Organization had none.
	package_agreement_id uuid references public.organization_package_agreements (id),
	source text not null check (source in ('review', 'migration', 'provisioning')),
	reason text not null check (char_length(trim(reason)) between 1 and 1000),
	actor_email text not null check (char_length(trim(actor_email)) between 3 and 320),
	-- The decision this one replaces. One chain per Organization: a stale review cannot fork it.
	previous_decision_id uuid references public.organization_experience_decisions (id),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	decided_at timestamptz not null default clock_timestamp(),
	foreign key (experience_key, definition_version)
		references public.industry_experience_definitions (experience_key, version),
	foreign key (experience_key, definition_version, business_type_key)
		references public.industry_experience_business_types (experience_key, definition_version, business_type_key)
);

comment on table public.organization_experience_decisions is
	'Append-only history of each Organization''s confirmed Industry experience. The head of each Organization''s chain (the decision no later one replaces) is its current experience profile.';

create unique index organization_experience_decisions_chain_idx
	on public.organization_experience_decisions (organization_id, previous_decision_id) nulls not distinct;
create index organization_experience_decisions_history_idx
	on public.organization_experience_decisions (organization_id, decided_at desc);
create index organization_experience_decisions_previous_idx
	on public.organization_experience_decisions (previous_decision_id);
create index organization_experience_decisions_agreement_idx
	on public.organization_experience_decisions (package_agreement_id);
create index organization_experience_decisions_business_type_idx
	on public.organization_experience_decisions (experience_key, definition_version, business_type_key);

create or replace function private.prevent_experience_decision_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	raise exception 'An experience decision cannot be changed. Record a new decision instead.'
		using errcode = 'check_violation';
end;
$$;

create trigger organization_experience_decisions_append_only
	before update on public.organization_experience_decisions
	for each row execute function private.prevent_experience_decision_change();

-- ---------------------------------------------------------------------------------------------------
-- Owner command
-- ---------------------------------------------------------------------------------------------------

create or replace function public.record_organization_experience_decision(
	target_organization_id uuid,
	target_experience_key text,
	target_definition_version integer,
	target_business_type_key text,
	reviewed_service_shape text,
	decision_reason text,
	expected_previous_decision_id uuid,
	idempotency_key text,
	actor_email text,
	decision_source text default 'review'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing_decision public.organization_experience_decisions%rowtype;
	current_decision public.organization_experience_decisions%rowtype;
	current_agreement_id uuid;
	inserted_id uuid;
begin
	select * into existing_decision
	from public.organization_experience_decisions d
	where d.idempotency_key = record_organization_experience_decision.idempotency_key;
	if found then
		if existing_decision.organization_id <> target_organization_id then
			raise exception 'This request key was already used for another organization.' using errcode = 'unique_violation';
		end if;
		return jsonb_build_object('applied', false, 'decision_id', existing_decision.id);
	end if;

	perform 1 from public.organizations o where o.id = target_organization_id for update;
	if not found then
		raise exception 'Organization was not found.' using errcode = 'foreign_key_violation';
	end if;

	if not exists (
		select 1 from public.industry_experience_definitions d
		where d.experience_key = target_experience_key
			and d.version = target_definition_version
			and d.status = 'published'
	) then
		raise exception 'Only a published experience definition can be confirmed.' using errcode = 'check_violation';
	end if;

	if nullif(trim(target_business_type_key), '') is not null and not exists (
		select 1 from public.industry_experience_business_types t
		where t.experience_key = target_experience_key
			and t.definition_version = target_definition_version
			and t.business_type_key = trim(target_business_type_key)
	) then
		raise exception 'That Business type is not offered by this experience definition.' using errcode = 'check_violation';
	end if;

	-- The current decision is the head of the Organization's chain: the one no later decision replaces.
	select * into current_decision
	from public.organization_experience_decisions d
	where d.organization_id = target_organization_id
		and not exists (
			select 1 from public.organization_experience_decisions later where later.previous_decision_id = d.id
		);

	if current_decision.id is distinct from expected_previous_decision_id then
		raise exception 'This organization''s experience changed while you were reviewing it. Reload and review again.'
			using errcode = 'P0409';
	end if;
	if current_decision.id is not null and current_decision.experience_key <> target_experience_key then
		raise exception 'Changing the primary experience needs an assisted transition review, which is not available yet.'
			using errcode = 'check_violation';
	end if;

	select a.id into current_agreement_id
	from public.organization_package_agreements a
	where a.organization_id = target_organization_id
		and a.cancelled_at is null
		and a.effective_from <= now()
	order by a.effective_from desc, a.created_at desc
	limit 1;

	insert into public.organization_experience_decisions (
		organization_id, experience_key, definition_version, business_type_key, service_shape,
		package_agreement_id, source, reason, actor_email, previous_decision_id, idempotency_key
	) values (
		target_organization_id, target_experience_key, target_definition_version,
		nullif(trim(target_business_type_key), ''), trim(reviewed_service_shape), current_agreement_id,
		decision_source, trim(decision_reason), lower(trim(actor_email)), current_decision.id,
		record_organization_experience_decision.idempotency_key
	)
	returning id into inserted_id;

	return jsonb_build_object('applied', true, 'decision_id', inserted_id);
end;
$$;

revoke all on function public.record_organization_experience_decision(uuid, text, integer, text, text, text, uuid, text, text, text)
	from public, anon, authenticated;
grant execute on function public.record_organization_experience_decision(uuid, text, integer, text, text, text, uuid, text, text, text)
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- Row security: Uplift reads and writes through the service role. Business Workspace access to the
-- profile arrives with experience-aware access (B5); until then no member role reads these tables.
-- ---------------------------------------------------------------------------------------------------

alter table public.industry_experience_definitions enable row level security;
alter table public.industry_experience_business_types enable row level security;
alter table public.organization_experience_decisions enable row level security;

revoke all on public.industry_experience_definitions, public.industry_experience_business_types,
	public.organization_experience_decisions from anon, authenticated;
grant all on public.industry_experience_definitions, public.industry_experience_business_types,
	public.organization_experience_decisions to service_role;
