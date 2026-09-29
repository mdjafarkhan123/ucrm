-- Package builder P3a (ADR 0003): new storage for capability readiness, packages, editions, customer
-- agreements, and temporary exceptions, and the switch of every access and limit check onto it.
--
-- Features keep asking the same questions: `organization_access_snapshot` and the limit functions keep
-- their names and signatures and now read the organization's latest agreement already in effect, its
-- edition's capabilities and allowances, and any active exception. The old package tables stay in place,
-- unread, until P3b removes them with the onboarding and email-template links that still point at them.

-- ---------------------------------------------------------------------------------------------------
-- Capability readiness: reference data. Only a verified build changes `sellable`, by migration.
-- ---------------------------------------------------------------------------------------------------

create table public.package_capabilities (
	capability_key text primary key check (capability_key ~ '^[a-z][a-z0-9_.-]{1,79}$'),
	label text not null check (char_length(trim(label)) between 2 and 80),
	description text not null check (char_length(trim(description)) between 1 and 240),
	-- core: in every package. extra: Jafar chooses it. planned: named for the builder, not buildable yet.
	kind text not null check (kind in ('core', 'extra', 'planned')),
	sellable boolean not null default false,
	sort_order smallint not null check (sort_order > 0),
	check (kind <> 'planned' or not sellable)
);

comment on table public.package_capabilities is
	'What a package can include. Keys are the entitlement names features already check; sellable changes only by migration after a verified build.';

create table public.package_capability_requirements (
	capability_key text not null references public.package_capabilities (capability_key),
	required_capability_key text not null references public.package_capabilities (capability_key),
	primary key (capability_key, required_capability_key),
	check (capability_key <> required_capability_key)
);

create index package_capability_requirements_required_idx
	on public.package_capability_requirements (required_capability_key);

create table public.package_allowances (
	allowance_key text primary key check (allowance_key ~ '^[a-z][a-z0-9_]{1,79}$'),
	-- The capability the allowance belongs to; null means it applies to every package.
	capability_key text references public.package_capabilities (capability_key),
	label text not null check (char_length(trim(label)) between 2 and 80),
	unit text not null check (unit in ('seats', 'recipients', 'widgets', 'conversations', 'recipes')),
	resets_monthly boolean not null,
	sort_order smallint not null check (sort_order > 0)
);

create index package_allowances_capability_idx on public.package_allowances (capability_key);

-- Automation safety controls apply to every organization alike (ADR 0003 decision 4). Seeded unlimited,
-- which is what every test organization has today; package-builder P14 sets the agreed values.
create table public.platform_automation_safety_limits (
	limit_key text primary key check (limit_key in (
		'automation_max_conditions_per_recipe', 'automation_max_steps_per_recipe',
		'automation_max_customer_messages_per_enrollment', 'automation_min_customer_message_spacing_minutes',
		'automation_max_delay_days', 'automation_max_enrollment_duration_days'
	)),
	limit_state text not null check (limit_state in ('unlimited', 'numeric')),
	limit_value integer,
	updated_at timestamptz not null default now(),
	check ((limit_state = 'unlimited' and limit_value is null)
		or (limit_state = 'numeric' and limit_value is not null and limit_value > 0))
);

insert into public.package_capabilities (capability_key, label, description, kind, sellable, sort_order) values
	('core.dashboard', 'Dashboard', 'Dashboard and workspace overview', 'core', true, 1),
	('core.customers_properties', 'Customers and properties', 'Customers and their properties', 'core', true, 2),
	('core.requests_assessments', 'Requests', 'Requests and assessments', 'core', true, 3),
	('core.quotes', 'Quotes', 'Quotes and the price list', 'core', true, 4),
	('core.jobs', 'Jobs', 'Jobs and work records', 'core', true, 5),
	('core.schedule', 'Scheduling', 'Visits and the normal schedule', 'core', true, 6),
	('core.invoices_payments', 'Invoices and payments', 'Invoices and recording customer payments', 'core', true, 7),
	('core.team', 'Team', 'Team members and their access', 'core', true, 8),
	('portal.client', 'Customer access', 'Customers view and act on their quotes and invoices', 'core', true, 9),
	('sales.pipeline', 'Sales pipeline', 'Sales pipeline and opportunities', 'extra', false, 20),
	('communications.inbox', 'Shared inbox', 'Shared customer conversations in one inbox', 'extra', false, 21),
	('website_chat', 'Website chat', 'Chat widget on the contractor''s website', 'extra', false, 22),
	('marketing', 'Marketing email', 'Marketing email campaigns', 'extra', false, 23),
	('growth.reputation', 'Review requests', 'Google review requests and private feedback', 'extra', false, 24),
	('automations', 'Custom automations', 'Automation recipes and enrollments', 'extra', false, 25),
	('reporting.advanced', 'Advanced reports', 'Advanced reporting', 'planned', false, 40),
	('communications.missed_call_text_back', 'Missed-call text-back', 'Text back callers the team missed', 'planned', false, 41),
	('dispatch.advanced', 'Advanced dispatch', 'Advanced dispatch and routing', 'planned', false, 42),
	('integrations.api', 'API and integrations', 'API and integrations', 'planned', false, 43);

insert into public.package_capability_requirements (capability_key, required_capability_key) values
	('website_chat', 'communications.inbox');

insert into public.package_allowances (allowance_key, capability_key, label, unit, resets_monthly, sort_order) values
	('employee_seats', 'core.team', 'Team seats', 'seats', false, 1),
	('operational_email_recipients', null, 'Operational email', 'recipients', true, 2),
	('essential_email_recipients', null, 'Essential email', 'recipients', true, 3),
	('website_chat_widgets', 'website_chat', 'Website chat widgets', 'widgets', false, 4),
	('website_chat_accepted_conversations', 'website_chat', 'Accepted website chats', 'conversations', true, 5),
	('marketing_email_recipients', 'marketing', 'Marketing email', 'recipients', true, 6),
	('automation_active_recipes', 'automations', 'Active automations', 'recipes', false, 7);

insert into public.platform_automation_safety_limits (limit_key, limit_state, limit_value) values
	('automation_max_conditions_per_recipe', 'unlimited', null),
	('automation_max_steps_per_recipe', 'unlimited', null),
	('automation_max_customer_messages_per_enrollment', 'unlimited', null),
	('automation_min_customer_message_spacing_minutes', 'unlimited', null),
	('automation_max_delay_days', 'unlimited', null),
	('automation_max_enrollment_duration_days', 'unlimited', null);

-- ---------------------------------------------------------------------------------------------------
-- Packages and editions
-- ---------------------------------------------------------------------------------------------------

create table public.packages (
	id uuid primary key default gen_random_uuid(),
	slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 2 and 60),
	visibility text not null default 'private' check (visibility in ('public', 'private')),
	display_order integer not null default 0,
	archived_at timestamptz,
	created_by_email text check (created_by_email is null or char_length(trim(created_by_email)) between 3 and 320),
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create trigger packages_set_updated_at before update on public.packages
	for each row execute function public.set_updated_at();

create table public.package_editions (
	id uuid primary key default gen_random_uuid(),
	package_id uuid not null references public.packages (id),
	-- Assigned when the draft is published; a draft has none.
	edition_number integer check (edition_number > 0),
	status text not null default 'draft' check (status in ('draft', 'published', 'superseded')),
	-- Whole-draft saves name the revision they loaded (ADR 0003 decision 3).
	revision integer not null default 1 check (revision > 0),
	name text not null check (char_length(trim(name)) between 2 and 80),
	promise text check (promise is null or char_length(trim(promise)) between 1 and 300),
	highlights jsonb not null default '[]'::jsonb check (jsonb_typeof(highlights) = 'array'),
	included_services jsonb not null default '[]'::jsonb check (jsonb_typeof(included_services) = 'array'),
	exclusions text check (exclusions is null or char_length(trim(exclusions)) between 1 and 2000),
	monthly_price_usd_cents integer check (monthly_price_usd_cents is null or monthly_price_usd_cents >= 0),
	yearly_price_usd_cents integer check (yearly_price_usd_cents is null or yearly_price_usd_cents >= 0),
	published_at timestamptz,
	superseded_at timestamptz,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (package_id, edition_number),
	check (
		(status = 'draft' and edition_number is null and published_at is null and superseded_at is null)
		or (status = 'published' and edition_number is not null and published_at is not null and superseded_at is null
			and (monthly_price_usd_cents is not null or yearly_price_usd_cents is not null))
		or (status = 'superseded' and edition_number is not null and published_at is not null and superseded_at is not null)
	)
);

-- At most one draft and one published edition per package.
create unique index package_editions_one_draft_idx on public.package_editions (package_id) where status = 'draft';
create unique index package_editions_one_published_idx on public.package_editions (package_id) where status = 'published';

create trigger package_editions_set_updated_at before update on public.package_editions
	for each row execute function public.set_updated_at();

create table public.package_edition_capabilities (
	edition_id uuid not null references public.package_editions (id) on delete cascade,
	capability_key text not null references public.package_capabilities (capability_key),
	primary key (edition_id, capability_key)
);

create index package_edition_capabilities_capability_idx on public.package_edition_capabilities (capability_key);

create table public.package_edition_allowances (
	edition_id uuid not null references public.package_editions (id) on delete cascade,
	allowance_key text not null references public.package_allowances (allowance_key),
	allowance_state text not null check (allowance_state in ('numeric', 'unlimited', 'not_included')),
	allowance_value integer,
	primary key (edition_id, allowance_key),
	check ((allowance_state = 'numeric' and allowance_value is not null and allowance_value >= 0)
		or (allowance_state <> 'numeric' and allowance_value is null))
);

create index package_edition_allowances_allowance_idx on public.package_edition_allowances (allowance_key);

-- A published edition's terms never change: only its move from published to superseded is allowed, and
-- only a draft may be deleted (ADR 0003 decision 2).
create or replace function private.prevent_frozen_package_edition_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	if tg_op = 'DELETE' then
		if old.status <> 'draft' then
			raise exception 'A published package edition cannot be deleted.' using errcode = 'check_violation';
		end if;
		return old;
	end if;

	if old.status = 'draft' then
		return new;
	end if;

	if old.status = 'published' and new.status = 'superseded'
		and (to_jsonb(new) - array['status', 'superseded_at', 'updated_at'])
			= (to_jsonb(old) - array['status', 'superseded_at', 'updated_at']) then
		return new;
	end if;

	raise exception 'A published package edition cannot be changed. Publish a new edition instead.'
		using errcode = 'check_violation';
end;
$$;

create trigger package_editions_frozen
	before update or delete on public.package_editions
	for each row execute function private.prevent_frozen_package_edition_change();

create or replace function private.prevent_frozen_package_edition_terms_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
	target_edition_id uuid := case when tg_op = 'DELETE' then old.edition_id else new.edition_id end;
	target_status text;
begin
	select status into target_status from public.package_editions where id = target_edition_id;
	-- A cascade from deleting a draft edition finds no row left; that delete was already allowed.
	if target_status is null or target_status = 'draft' then
		return case when tg_op = 'DELETE' then old else new end;
	end if;
	raise exception 'A published package edition''s capabilities and allowances cannot be changed.'
		using errcode = 'check_violation';
end;
$$;

create trigger package_edition_capabilities_frozen
	before insert or update or delete on public.package_edition_capabilities
	for each row execute function private.prevent_frozen_package_edition_terms_change();

create trigger package_edition_allowances_frozen
	before insert or update or delete on public.package_edition_allowances
	for each row execute function private.prevent_frozen_package_edition_terms_change();

-- ---------------------------------------------------------------------------------------------------
-- Agreements and exceptions
-- ---------------------------------------------------------------------------------------------------

create table public.organization_package_agreements (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	edition_id uuid not null references public.package_editions (id),
	billing_interval text not null check (billing_interval in ('month', 'year')),
	agreed_price_usd_cents integer not null check (agreed_price_usd_cents >= 0),
	-- Frozen introductory-offer terms (package-builder P11); null when no offer applies.
	offer_terms jsonb check (offer_terms is null or jsonb_typeof(offer_terms) = 'object'),
	-- The first confirmed coverage start; monthly allowances restart from it (ADR 0003 decision 7).
	service_anchor_date date,
	effective_from timestamptz not null,
	source text not null check (source in ('test_reset', 'activation', 'package_change', 'correction')),
	reason text not null check (char_length(trim(reason)) between 1 and 500),
	actor_owner_email text check (actor_owner_email is null or char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text unique check (idempotency_key is null or char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now()
);

create index organization_package_agreements_current_idx
	on public.organization_package_agreements (organization_id, effective_from desc, created_at desc);
create index organization_package_agreements_edition_idx on public.organization_package_agreements (edition_id);

create or replace function private.validate_organization_package_agreement()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	if tg_op = 'UPDATE' then
		raise exception 'A package agreement cannot be changed. Record a new agreement instead.'
			using errcode = 'check_violation';
	end if;
	if not exists (select 1 from public.package_editions e where e.id = new.edition_id and e.status = 'published') then
		raise exception 'An organization can only agree to a published package edition.'
			using errcode = 'check_violation';
	end if;
	return new;
end;
$$;

create trigger organization_package_agreements_validate
	before insert or update on public.organization_package_agreements
	for each row execute function private.validate_organization_package_agreement();

create table public.organization_package_exceptions (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	capability_key text references public.package_capabilities (capability_key),
	capability_state text check (capability_state in ('on', 'off')),
	allowance_key text references public.package_allowances (allowance_key),
	allowance_state text check (allowance_state in ('numeric', 'unlimited', 'not_included')),
	allowance_value integer,
	reason text not null check (char_length(trim(reason)) between 1 and 1000),
	starts_at timestamptz not null,
	ends_at timestamptz not null,
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	created_at timestamptz not null default now(),
	check (ends_at > starts_at),
	check (
		(capability_key is not null and capability_state is not null
			and allowance_key is null and allowance_state is null and allowance_value is null)
		or (allowance_key is not null and allowance_state is not null
			and capability_key is null and capability_state is null
			and ((allowance_state = 'numeric' and allowance_value is not null and allowance_value >= 0)
				or (allowance_state <> 'numeric' and allowance_value is null)))
	)
);

create index organization_package_exceptions_org_idx
	on public.organization_package_exceptions (organization_id, starts_at desc);
create index organization_package_exceptions_capability_idx on public.organization_package_exceptions (capability_key);
create index organization_package_exceptions_allowance_idx on public.organization_package_exceptions (allowance_key);

-- ---------------------------------------------------------------------------------------------------
-- Row security: reference data is public; a member reads only its own organization's agreement terms.
-- Every write goes through owner commands (service role), so no role may write directly.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.can_read_package_edition(target_edition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1
		from public.package_editions e
		join public.packages p on p.id = e.package_id
		where e.id = target_edition_id
			and e.status = 'published' and p.visibility = 'public' and p.archived_at is null
	) or exists (
		select 1
		from public.organization_package_agreements a
		where a.edition_id = target_edition_id
			and private.is_organization_member(a.organization_id)
	);
$$;

create or replace function private.can_read_package(target_package_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select exists (
		select 1 from public.packages p
		where p.id = target_package_id and p.visibility = 'public' and p.archived_at is null
	) or exists (
		select 1
		from public.organization_package_agreements a
		join public.package_editions e on e.id = a.edition_id
		where e.package_id = target_package_id
			and private.is_organization_member(a.organization_id)
	);
$$;

revoke all on function private.can_read_package_edition(uuid) from public, anon;
revoke all on function private.can_read_package(uuid) from public, anon;
grant execute on function private.can_read_package_edition(uuid) to anon, authenticated, service_role;
grant execute on function private.can_read_package(uuid) to anon, authenticated, service_role;

alter table public.package_capabilities enable row level security;
alter table public.package_capability_requirements enable row level security;
alter table public.package_allowances enable row level security;
alter table public.platform_automation_safety_limits enable row level security;
alter table public.packages enable row level security;
alter table public.package_editions enable row level security;
alter table public.package_edition_capabilities enable row level security;
alter table public.package_edition_allowances enable row level security;
alter table public.organization_package_agreements enable row level security;
alter table public.organization_package_exceptions enable row level security;

revoke all on public.package_capabilities, public.package_capability_requirements, public.package_allowances,
	public.platform_automation_safety_limits, public.packages, public.package_editions,
	public.package_edition_capabilities, public.package_edition_allowances,
	public.organization_package_agreements, public.organization_package_exceptions
	from anon, authenticated;

grant select on public.package_capabilities, public.package_capability_requirements, public.package_allowances,
	public.packages, public.package_editions, public.package_edition_capabilities, public.package_edition_allowances
	to anon, authenticated;
grant select on public.platform_automation_safety_limits, public.organization_package_agreements,
	public.organization_package_exceptions to authenticated;
grant all on public.package_capabilities, public.package_capability_requirements, public.package_allowances,
	public.platform_automation_safety_limits, public.packages, public.package_editions,
	public.package_edition_capabilities, public.package_edition_allowances,
	public.organization_package_agreements, public.organization_package_exceptions
	to service_role;

create policy "anyone can view package capabilities" on public.package_capabilities
	for select to anon, authenticated using (true);
create policy "anyone can view package capability requirements" on public.package_capability_requirements
	for select to anon, authenticated using (true);
create policy "anyone can view package allowances" on public.package_allowances
	for select to anon, authenticated using (true);
create policy "members can view automation safety limits" on public.platform_automation_safety_limits
	for select to authenticated using (true);
create policy "public or agreed packages are visible" on public.packages
	for select to anon, authenticated using (private.can_read_package(id));
create policy "public or agreed package editions are visible" on public.package_editions
	for select to anon, authenticated using (private.can_read_package_edition(id));
create policy "visible edition capabilities" on public.package_edition_capabilities
	for select to anon, authenticated using (private.can_read_package_edition(edition_id));
create policy "visible edition allowances" on public.package_edition_allowances
	for select to anon, authenticated using (private.can_read_package_edition(edition_id));
create policy "members can view their organization package agreements" on public.organization_package_agreements
	for select to authenticated using (private.is_organization_member(organization_id));
create policy "members can view their organization package exceptions" on public.organization_package_exceptions
	for select to authenticated using (private.is_organization_member(organization_id));

-- ---------------------------------------------------------------------------------------------------
-- The private test package: Raad LTD's effective access on 2026-09-29, so every test login keeps the
-- same screens. Every organization is test data (Jafar, 2026-09-29).
-- ---------------------------------------------------------------------------------------------------

with test_package as (
	insert into public.packages (slug, visibility, display_order, created_by_email)
	values ('test-package', 'private', 1, 'dev.jafarkhan@gmail.com')
	returning id
)
insert into public.package_editions (package_id, status, edition_number, name, promise, monthly_price_usd_cents, published_at)
select id, 'draft', null, 'Test package', 'Every working capability, for testing the app.', 24900, null
from test_package;

insert into public.package_edition_capabilities (edition_id, capability_key)
select e.id, c.capability_key
from public.package_editions e
join public.packages p on p.id = e.package_id and p.slug = 'test-package'
cross join public.package_capabilities c
where c.capability_key <> 'communications.missed_call_text_back';

insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
select e.id, v.allowance_key, v.allowance_state, v.allowance_value
from public.package_editions e
join public.packages p on p.id = e.package_id and p.slug = 'test-package'
cross join (values
	('employee_seats', 'numeric', 50),
	('operational_email_recipients', 'unlimited', null),
	('essential_email_recipients', 'unlimited', null),
	('website_chat_widgets', 'numeric', 5),
	('website_chat_accepted_conversations', 'numeric', 20),
	('marketing_email_recipients', 'unlimited', null),
	('automation_active_recipes', 'unlimited', null)
) as v (allowance_key, allowance_state, allowance_value);

update public.package_editions e
set status = 'published', edition_number = 1, published_at = now()
from public.packages p
where p.id = e.package_id and p.slug = 'test-package';

insert into public.organization_package_agreements (
	organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason,
	actor_owner_email
)
select o.id, e.id, 'month', e.monthly_price_usd_cents, now(), 'test_reset',
	'Moved onto the private test package when the package system was replaced (Jafar, 2026-09-29).',
	'dev.jafarkhan@gmail.com'
from public.organizations o
cross join public.package_editions e
join public.packages p on p.id = e.package_id and p.slug = 'test-package';

-- ---------------------------------------------------------------------------------------------------
-- Resolvers. SECURITY INVOKER, so a member's call sees only what RLS lets it see and a SECURITY DEFINER
-- caller sees everything, exactly as the functions they replace did.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.organization_agreement_edition(target_organization_id uuid, at timestamptz)
returns uuid
language sql
stable
set search_path = ''
as $$
	select a.edition_id
	from public.organization_package_agreements a
	where a.organization_id = target_organization_id and a.effective_from <= at
	order by a.effective_from desc, a.created_at desc
	limit 1;
$$;

-- An active exception wins over the edition; with neither, the allowance is not included.
create or replace function private.organization_allowance(
	target_organization_id uuid,
	target_allowance_key text,
	at timestamptz
)
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	with exception_row as (
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
		where ea.edition_id = private.organization_agreement_edition(target_organization_id, at)
			and ea.allowance_key = target_allowance_key
	), resolved as (
		select
			coalesce(x.allowance_state, e.allowance_state, 'not_included') as state,
			case when x.allowance_state is not null then x.allowance_value else e.allowance_value end as value,
			x.allowance_state is not null as from_exception
		from (select 1) as one
		left join exception_row x on true
		left join edition_row e on true
	)
	select r.state, r.value, r.state = 'unlimited', case when r.from_exception then 'override' else 'package' end
	from resolved r;
$$;

create or replace function private.organization_has_capability(
	target_organization_id uuid,
	target_capability_key text,
	at timestamptz
)
returns boolean
language sql
stable
set search_path = ''
as $$
	select coalesce(
		(
			select x.capability_state = 'on'
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id
				and x.capability_key = target_capability_key
				and x.starts_at <= at and x.ends_at > at
			order by x.starts_at desc, x.created_at desc
			limit 1
		),
		exists (
			select 1
			from public.package_edition_capabilities c
			where c.edition_id = private.organization_agreement_edition(target_organization_id, at)
				and c.capability_key = target_capability_key
		)
	);
$$;

revoke all on function private.organization_agreement_edition(uuid, timestamptz) from public, anon;
revoke all on function private.organization_allowance(uuid, text, timestamptz) from public, anon;
revoke all on function private.organization_has_capability(uuid, text, timestamptz) from public, anon;
grant execute on function private.organization_agreement_edition(uuid, timestamptz) to authenticated, service_role;
grant execute on function private.organization_allowance(uuid, text, timestamptz) to authenticated, service_role;
grant execute on function private.organization_has_capability(uuid, text, timestamptz) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- The existing limit and feature functions, same names and signatures, reading the new storage.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.effective_employee_seat_limit(target_organization_id uuid, at timestamptz default now())
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	select * from private.organization_allowance(target_organization_id, 'employee_seats', at);
$$;

create or replace function public.effective_website_chat_widgets_limit(target_organization_id uuid, at timestamptz default now())
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	select * from private.organization_allowance(target_organization_id, 'website_chat_widgets', at);
$$;

create or replace function private.effective_marketing_email_limit(target_organization_id uuid, at timestamptz default now())
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
security definer
set search_path = ''
as $$
	select * from private.organization_allowance(target_organization_id, 'marketing_email_recipients', at);
$$;

create or replace function private.effective_website_chat_conversation_limit(target_organization_id uuid, at timestamptz default now())
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
security definer
set search_path = ''
as $$
	select * from private.organization_allowance(target_organization_id, 'website_chat_accepted_conversations', at);
$$;

create or replace function private.resolve_communication_email_allowance(target_organization_id uuid, at timestamptz default now())
returns table (
	period_id uuid, period_starts_at timestamptz, period_ends_at timestamptz,
	operational_limit_state text, operational_limit_value integer,
	essential_limit_state text, essential_limit_value integer
)
language sql
stable
security definer
set search_path = ''
as $$
	with active_period as (
		select period.id, period.starts_at, period.ends_at
		from public.communication_email_allowance_periods as period
		where period.organization_id = target_organization_id and period.starts_at <= at and period.ends_at > at
		order by period.starts_at desc
		limit 1
	)
	select period.id, period.starts_at, period.ends_at,
		operational.state, operational.value, essential.state, essential.value
	from active_period as period
	cross join private.organization_allowance(target_organization_id, 'operational_email_recipients', at) as operational
	cross join private.organization_allowance(target_organization_id, 'essential_email_recipients', at) as essential;
$$;

create or replace function private.organization_has_automations_feature(p_organization_id uuid, p_at timestamptz default now())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select private.organization_has_capability(p_organization_id, 'automations', p_at);
$$;

-- The active-recipe allowance is a package term; the other six are platform-wide safety controls.
create or replace function public.effective_automation_limits(target_organization_id uuid, at timestamptz default now())
returns table (limit_key text, state text, value integer, is_unlimited boolean, source text)
language sql
stable
set search_path = ''
as $$
	select 'automation_active_recipes'::text, a.state, a.value, a.is_unlimited, a.source
	from private.organization_allowance(target_organization_id, 'automation_active_recipes', at) a
	union all
	select s.limit_key, s.limit_state, s.limit_value, s.limit_state = 'unlimited', 'platform'
	from public.platform_automation_safety_limits s
	order by 1;
$$;

create or replace function public.get_organization_automation_limits(p_organization_id uuid, at timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	with edition_default as (
		select ea.allowance_state, ea.allowance_value
		from public.package_edition_allowances ea
		where ea.edition_id = private.organization_agreement_edition(p_organization_id, at)
			and ea.allowance_key = 'automation_active_recipes'
	), exception_row as (
		select x.*, (x.starts_at <= at and x.ends_at > at) as is_active
		from public.organization_package_exceptions x
		where x.organization_id = p_organization_id and x.allowance_key = 'automation_active_recipes'
			and x.ends_at > at
		order by x.starts_at desc, x.created_at desc
		limit 1
	)
	select coalesce(jsonb_agg(
		jsonb_build_object(
			'limit_key', e.limit_key,
			'package_default', case
				when e.limit_key = 'automation_active_recipes' then jsonb_build_object(
					'state', coalesce((select allowance_state from edition_default), 'not_included'),
					'value', (select allowance_value from edition_default))
				else jsonb_build_object('state', e.state, 'value', e.value)
			end,
			'effective', jsonb_build_object(
				'state', e.state, 'value', e.value, 'is_unlimited', e.is_unlimited, 'source', e.source),
			'exception', case
				when e.limit_key <> 'automation_active_recipes' or not exists (select 1 from exception_row) then null
				else (
					select jsonb_build_object(
						'state', x.allowance_state, 'value', x.allowance_value,
						'is_unlimited', x.allowance_state = 'unlimited', 'is_active', x.is_active,
						'reason', x.reason, 'actor_owner_email', x.actor_owner_email,
						'starts_at', x.starts_at, 'expires_at', x.ends_at)
					from exception_row x
				)
			end
		)
		order by e.limit_key
	), '[]'::jsonb)
	from public.effective_automation_limits(p_organization_id, at) e;
$$;

create or replace function public.get_organization_communication_email_allowances(
	target_organization_id uuid,
	at timestamptz default now()
)
returns table (
	limit_key text, period_id uuid, period_starts_at timestamptz, period_ends_at timestamptz,
	effective_state text, effective_value integer, effective_source text,
	fallback_state text, fallback_value integer,
	override_state text, override_value integer, override_starts_at timestamptz, override_expires_at timestamptz,
	override_reason text, override_author_email text
)
language sql
stable
security definer
set search_path = ''
as $$
	with keys (limit_key) as (
		values ('operational_email_recipients'::text), ('essential_email_recipients'::text)
	), period as (
		select p.period_id, p.period_starts_at, p.period_ends_at
		from private.resolve_communication_email_allowance(target_organization_id, at) p
	)
	select
		k.limit_key, period.period_id, period.period_starts_at, period.period_ends_at,
		effective.state, effective.value, effective.source,
		edition_allowance.allowance_state, edition_allowance.allowance_value,
		x.allowance_state, x.allowance_value, x.starts_at, x.ends_at, x.reason, x.actor_owner_email
	from keys k
	cross join lateral private.organization_allowance(target_organization_id, k.limit_key, at) effective
	left join period on true
	left join public.package_edition_allowances edition_allowance
		on edition_allowance.edition_id = private.organization_agreement_edition(target_organization_id, at)
		and edition_allowance.allowance_key = k.limit_key
	left join lateral (
		select * from public.organization_package_exceptions x
		where x.organization_id = target_organization_id and x.allowance_key = k.limit_key and x.ends_at > at
		order by x.starts_at desc, x.created_at desc
		limit 1
	) x on true
	order by k.limit_key;
$$;

create or replace function public.get_organization_communication_website_chat_allowance(
	target_organization_id uuid,
	at timestamptz default now()
)
returns table (
	limit_key text, period_id uuid, period_starts_at timestamptz, period_ends_at timestamptz,
	effective_state text, effective_value integer, effective_source text,
	fallback_state text, fallback_value integer,
	override_state text, override_value integer, override_starts_at timestamptz, override_expires_at timestamptz,
	override_reason text, override_author_email text
)
language sql
stable
security definer
set search_path = ''
as $$
	select
		'website_chat_accepted_conversations'::text, null::uuid, null::timestamptz, null::timestamptz,
		effective.state, effective.value, effective.source,
		edition_allowance.allowance_state, edition_allowance.allowance_value,
		x.allowance_state, x.allowance_value, x.starts_at, x.ends_at, x.reason, x.actor_owner_email
	from private.organization_allowance(target_organization_id, 'website_chat_accepted_conversations', at) effective
	left join public.package_edition_allowances edition_allowance
		on edition_allowance.edition_id = private.organization_agreement_edition(target_organization_id, at)
		and edition_allowance.allowance_key = 'website_chat_accepted_conversations'
	left join lateral (
		select * from public.organization_package_exceptions x
		where x.organization_id = target_organization_id
			and x.allowance_key = 'website_chat_accepted_conversations' and x.ends_at > at
		order by x.starts_at desc, x.created_at desc
		limit 1
	) x on true;
$$;

-- ---------------------------------------------------------------------------------------------------
-- The per-request access snapshot: the organization's agreement, its edition and capabilities, and the
-- active exceptions replace the assignment, version, and legacy package rows.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.organization_access_snapshot(
	target_organization_id uuid,
	target_user_id uuid default null,
	at timestamptz default now()
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
	with org as (
		select o.id, o.name, o.slug, o.lifecycle_status
		from public.organizations o
		where o.id = target_organization_id
	),
	agreement as (
		select a.id, a.edition_id, a.billing_interval, a.agreed_price_usd_cents, a.offer_terms,
			a.service_anchor_date, a.effective_from
		from public.organization_package_agreements a
		where a.organization_id = target_organization_id and a.effective_from <= at
		order by a.effective_from desc, a.created_at desc
		limit 1
	),
	edition as (
		select e.id, e.package_id, e.edition_number, e.status, e.name, e.promise
		from public.package_editions e
		where e.id = (select edition_id from agreement)
	),
	package as (
		select p.id, p.slug, p.visibility, p.archived_at
		from public.packages p
		where p.id = (select package_id from edition)
	),
	membership as (
		select m.user_id, m.role
		from public.organization_members m
		where m.organization_id = target_organization_id
			and m.user_id = target_user_id
	)
	select case when not exists (select 1 from org) then null else jsonb_build_object(
		'organization', (select to_jsonb(org) from org),
		'agreement', (select to_jsonb(agreement) from agreement),
		'edition', (select to_jsonb(edition) from edition),
		'package', (select to_jsonb(package) from package),
		'capabilities', coalesce((
			select jsonb_agg(c.capability_key order by c.sort_order) from public.package_capabilities c
		), '[]'::jsonb),
		'edition_capabilities', coalesce((
			select jsonb_agg(ec.capability_key)
			from public.package_edition_capabilities ec
			where ec.edition_id = (select edition_id from agreement)
		), '[]'::jsonb),
		'capability_exceptions', coalesce((
			select jsonb_agg(jsonb_build_object(
				'capability_key', x.capability_key, 'state', x.capability_state,
				'starts_at', x.starts_at, 'ends_at', x.ends_at, 'reason', x.reason)
				order by x.starts_at desc, x.created_at desc)
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id and x.capability_key is not null
				and x.starts_at <= at and x.ends_at > at
		), '[]'::jsonb),
		'allowance_exceptions', coalesce((
			select jsonb_agg(jsonb_build_object(
				'allowance_key', x.allowance_key, 'state', x.allowance_state, 'value', x.allowance_value,
				'starts_at', x.starts_at, 'ends_at', x.ends_at)
				order by x.starts_at desc, x.created_at desc)
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id and x.allowance_key is not null
				and x.starts_at <= at and x.ends_at > at
		), '[]'::jsonb),
		'commercial_state', (
			select jsonb_build_object(
				'paid_through_date', cs.paid_through_date, 'paid_through_source', cs.paid_through_source,
				'grace_ends_at', cs.grace_ends_at)
			from public.organization_commercial_state cs
			where cs.organization_id = target_organization_id
		),
		'commercial_settings', (
			select jsonb_build_object('commercial_timezone', st.commercial_timezone)
			from public.organization_commercial_settings st
			where st.organization_id = target_organization_id
		),
		-- Free access is rebuilt in package-builder P5; until then the old grants are still read.
		'free_access_events', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', fe.id, 'target_grant_id', fe.target_grant_id, 'action', fe.action,
				'starts_at', fe.starts_at, 'access_until_date', fe.access_until_date,
				'occurred_at', fe.occurred_at))
			from public.organization_free_access_events fe
			where fe.organization_id = target_organization_id
		), '[]'::jsonb),
		'employee_seat_limit', (
			select to_jsonb(l) from private.organization_allowance(target_organization_id, 'employee_seats', at) l
		),
		'website_chat_widgets_limit', (
			select to_jsonb(l) from private.organization_allowance(target_organization_id, 'website_chat_widgets', at) l
		),
		'marketing_email_limit', (
			select to_jsonb(l) from private.organization_allowance(target_organization_id, 'marketing_email_recipients', at) l
		),
		'membership', (select to_jsonb(membership) from membership),
		'role_permissions', coalesce((
			select jsonb_agg(jsonb_build_object('permission_key', rp.permission_key, 'access_scope', rp.access_scope))
			from public.role_permissions rp
			where rp.role = (select role from membership)
		), '[]'::jsonb),
		'member_permission_overrides', coalesce((
			select jsonb_agg(jsonb_build_object(
				'permission_key', mo.permission_key, 'override_state', mo.override_state,
				'access_scope', mo.access_scope))
			from public.organization_member_permission_overrides mo
			where mo.organization_id = target_organization_id
				and mo.user_id = target_user_id
		), '[]'::jsonb)
	) end;
$$;

-- The directory's "expiring soon" flag reads the new exceptions; everything else is unchanged.
CREATE OR REPLACE FUNCTION "public"."owner_organization_directory"("search_term" "text" DEFAULT NULL::"text", "attention_reason" "text" DEFAULT NULL::"text", "cursor_created_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_id" "uuid" DEFAULT NULL::"uuid", "page_size" integer DEFAULT 50) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
  with org_context as (
    select
      o.id,
      o.name,
      o.slug,
      o.lifecycle_status,
      o.created_at,
      o.updated_at,
      coalesce(cs.commercial_timezone, 'UTC') as commercial_timezone,
      (now() at time zone coalesce(cs.commercial_timezone, 'UTC'))::date as today_date,
      st.paid_through_date,
      st.grace_ends_at
    from public.organizations o
    left join public.organization_commercial_settings cs on cs.organization_id = o.id
    left join public.organization_commercial_state st on st.organization_id = o.id
  ),
  member_counts as (
    select
      organization_id,
      count(*) as member_count,
      count(*) filter (where role = 'owner') as owner_count
    from public.organization_members
    group by organization_id
  ),
  free_access_latest as (
    select distinct on (event.organization_id, coalesce(event.target_grant_id, event.id))
      event.organization_id,
      event.action,
      event.starts_at,
      event.access_until_date
    from public.organization_free_access_events event
    order by event.organization_id, coalesce(event.target_grant_id, event.id), event.occurred_at desc, event.id desc
  ),
  free_access_summary as (
    select
      oc.id as organization_id,
      coalesce(bool_or(
        fal.action <> 'end'
        and fal.starts_at <= oc.today_date
        and (fal.access_until_date is null or fal.access_until_date >= oc.today_date)
      ), false) as free_access_active,
      coalesce(bool_or(
        fal.action <> 'end'
        and fal.starts_at <= oc.today_date
        and fal.access_until_date is not null
        and fal.access_until_date >= oc.today_date
        and (fal.access_until_date - oc.today_date) <= 7
      ), false) as free_access_expiring_soon
    from org_context oc
    left join free_access_latest fal on fal.organization_id = oc.id
    group by oc.id
  ),
  package_exception_summary as (
    select
      oc.id as organization_id,
      exists (
        select 1 from public.organization_package_exceptions x
        where x.organization_id = oc.id
          and x.starts_at <= now()
          and x.ends_at > now()
          and ((x.ends_at at time zone oc.commercial_timezone)::date - oc.today_date) between 0 and 7
      ) as package_exception_expiring_soon
    from org_context oc
  ),
  setup_recovery_summary as (
    select
      oc.id as organization_id,
      exists (
        select 1 from public.platform_operation_attempts op
        where op.target_kind = 'organization'
          and op.target_id = oc.id
          and op.status in ('pending', 'retrying')
      ) as setup_or_recovery_failed
    from org_context oc
  ),
  owner_emails as (
    select
      m.organization_id,
      array_agg(distinct u.email) filter (where u.email is not null) as owner_email_list
    from public.organization_members m
    join auth.users u on u.id = m.user_id
    where m.role = 'owner'
    group by m.organization_id
  ),
  computed as (
    select
      oc.id,
      oc.name,
      oc.slug,
      oc.lifecycle_status,
      oc.created_at,
      oc.updated_at,
      coalesce(mc.member_count, 0) as member_count,
      coalesce(mc.owner_count, 0) as owner_count,
      (
        oc.paid_through_date is not null
        and (oc.paid_through_date >= oc.today_date or (oc.grace_ends_at is not null and oc.grace_ends_at >= now()))
      ) as paid_through_eligible,
      coalesce(fas.free_access_active, false) as free_access_active,
      coalesce(fas.free_access_expiring_soon, false) as free_access_expiring_soon,
      coalesce(pes.package_exception_expiring_soon, false) as package_exception_expiring_soon,
      coalesce(srs.setup_or_recovery_failed, false) as setup_or_recovery_failed,
      exists (
        select 1 from public.communication_email_setup_requests_waiting w
        where w.organization_id = oc.id
      ) as email_setup_requested,
      coalesce(oe.owner_email_list, array[]::text[]) as owner_email_list
    from org_context oc
    left join member_counts mc on mc.organization_id = oc.id
    left join free_access_summary fas on fas.organization_id = oc.id
    left join package_exception_summary pes on pes.organization_id = oc.id
    left join setup_recovery_summary srs on srs.organization_id = oc.id
    left join owner_emails oe on oe.organization_id = oc.id
  ),
  reasoned as (
    select
      c.*,
      (c.lifecycle_status = 'active' and not c.paid_through_eligible and not c.free_access_active)
        as is_access_overdue,
      (c.free_access_expiring_soon or c.package_exception_expiring_soon) as is_expiring_soon,
      (c.owner_count = 0) as is_administrator_missing,
      (c.owner_count > 1) as is_administrator_ownership_unclear,
      c.setup_or_recovery_failed as is_setup_or_recovery_failed,
      (c.lifecycle_status = 'pending_setup') as is_legacy_review,
      c.email_setup_requested as is_email_setup_requested
    from computed c
  ),
  tagged as (
    select
      r.*,
      array_remove(
        array[
          case when is_access_overdue then 'access_overdue' end,
          case when is_administrator_missing then 'administrator_missing' end,
          case when is_administrator_ownership_unclear then 'administrator_ownership_unclear' end,
          case when is_setup_or_recovery_failed then 'setup_or_recovery_failed' end,
          case when is_expiring_soon then 'expiring_soon' end,
          case when is_legacy_review then 'legacy_review' end,
          case when is_email_setup_requested then 'email_setup_requested' end
        ],
        null
      ) as attention_reasons
    from reasoned r
  ),
  matching as (
    select t.*
    from tagged t
    where
      search_term is null
      or trim(search_term) = ''
      or t.name ilike '%' || search_term || '%'
      or t.slug ilike '%' || search_term || '%'
      or exists (select 1 from unnest(t.owner_email_list) as email where email ilike '%' || search_term || '%')
  ),
  filtered as (
    select m.*
    from matching m
    where attention_reason is null or attention_reason = any(m.attention_reasons)
  ),
  page as (
    select f.*
    from filtered f
    where cursor_created_at is null or (f.created_at, f.id) < (cursor_created_at, cursor_id)
    order by f.created_at desc, f.id desc
    limit least(greatest(coalesce(page_size, 50), 1), 100)
  ),
  page_meta as (
    select count(*) as returned_count from page
  ),
  page_last as (
    select created_at, id from page order by created_at asc, id asc limit 1
  ),
  totals as (
    select
      count(*) as all_count,
      count(*) filter (where lifecycle_status = 'active') as active_count,
      count(*) filter (where lifecycle_status = 'suspended') as suspended_count,
      count(*) filter (where lifecycle_status = 'pending_setup') as pending_setup_count,
      count(*) filter (where is_access_overdue) as access_overdue_count,
      count(*) filter (where is_expiring_soon) as expiring_soon_count,
      count(*) filter (where is_administrator_missing) as administrator_missing_count,
      count(*) filter (where is_administrator_ownership_unclear) as administrator_ownership_unclear_count,
      count(*) filter (where is_setup_or_recovery_failed) as setup_or_recovery_failed_count,
      count(*) filter (where is_legacy_review) as legacy_review_count,
      count(*) filter (where is_email_setup_requested) as email_setup_requested_count
    from tagged
  ),
  matching_totals as (
    select count(*) as matching_count from filtered
  )
  select jsonb_build_object(
    'organizations', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'name', p.name,
            'slug', p.slug,
            'lifecycle_status', p.lifecycle_status,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'member_count', p.member_count,
            'attention_reasons', to_jsonb(p.attention_reasons)
          )
          order by p.created_at desc, p.id desc
        )
        from page p
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select returned_count from page_meta) >= least(greatest(coalesce(page_size, 50), 1), 100)
        then (select jsonb_build_object('created_at', pl.created_at, 'id', pl.id) from page_last pl)
      else null
    end,
    'totals', jsonb_build_object(
      'all', (select all_count from totals),
      'active', (select active_count from totals),
      'suspended', (select suspended_count from totals),
      'pending_setup', (select pending_setup_count from totals),
      'matching', (select matching_count from matching_totals),
      'attention', jsonb_build_object(
        'access_overdue', (select access_overdue_count from totals),
        'expiring_soon', (select expiring_soon_count from totals),
        'administrator_missing', (select administrator_missing_count from totals),
        'administrator_ownership_unclear', (select administrator_ownership_unclear_count from totals),
        'setup_or_recovery_failed', (select setup_or_recovery_failed_count from totals),
        'legacy_review', (select legacy_review_count from totals),
        'email_setup_requested', (select email_setup_requested_count from totals)
      )
    )
  );
$$;
