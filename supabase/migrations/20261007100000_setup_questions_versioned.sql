-- Client onboarding A3: the setup wizard's stages and questions move from code into the database, as
-- published versions Jafar will edit (A4 stages, A5 questions).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §2.1. Decision:
-- docs/adr/0006-setup-questions-live-in-published-versions.md, which revises ADR 0005 decision 3.
--
-- 1. setup_versions: at most one draft and one published version. Publishing freezes a version, the same
--    way a package edition is frozen (ADR 0003); an older one becomes superseded and stays as history.
-- 2. setup_stages: a version's task-list stages, in order. A stage with a service shows only to clients
--    whose package edition includes that service (A4).
-- 3. setup_items: each stage's ordered items. An item is a heading (a titled group, the way Google Forms,
--    Jotform and Tally place section titles inside a page) or a question. A question's fact_key is how
--    answers are stored (ADR 0005 decision 2), so it is unique within a version: a fact is asked once.
--    A built-in question is one the app copies into CRM settings or provider registration; its answer
--    type, choices and size limits stay in src/lib/setup/catalogue.ts and are never stored here, so they
--    cannot be changed by editing setup. Every other question carries its own answer type.
-- Nobody but the server reads these tables; clients read the published version through
-- public.setup_published_catalogue().

-- 1. Versions --------------------------------------------------------------------------------------------

create table public.setup_versions (
	id uuid primary key default gen_random_uuid(),
	version_number integer not null unique check (version_number > 0),
	status text not null check (status in ('draft', 'published', 'superseded')),
	published_at timestamptz,
	published_by_email text,
	superseded_at timestamptz,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	constraint setup_versions_published_check check ((status = 'draft') = (published_at is null)),
	constraint setup_versions_superseded_check check ((status = 'superseded') = (superseded_at is not null))
);

create unique index setup_versions_one_draft_idx on public.setup_versions ((true)) where status = 'draft';
create unique index setup_versions_one_published_idx on public.setup_versions ((true))
	where status = 'published';

comment on table public.setup_versions is
	'Versions of the client setup wizard. Clients see the one published version; Jafar edits the draft.';

create trigger setup_versions_set_updated_at before update on public.setup_versions
	for each row execute function public.set_updated_at();

-- 2. Stages ----------------------------------------------------------------------------------------------

create table public.setup_stages (
	version_id uuid not null references public.setup_versions (id) on delete cascade,
	-- Stable across versions: organization_setup_sections and support chats refer to it.
	stage_key text not null check (stage_key ~ '^[a-z][a-z0-9_]*$' and char_length(stage_key) <= 40),
	title text not null check (char_length(btrim(title)) between 2 and 80),
	description text not null default '' check (char_length(description) <= 300),
	-- Null shows the stage to every client.
	service_key text references public.package_services (service_key),
	position integer not null check (position > 0),
	primary key (version_id, stage_key),
	constraint setup_stages_position_key unique (version_id, position) deferrable initially deferred
);

create index setup_stages_service_key_idx on public.setup_stages (service_key) where service_key is not null;

-- 3. Items -----------------------------------------------------------------------------------------------

create table public.setup_items (
	id uuid primary key default gen_random_uuid(),
	version_id uuid not null,
	stage_key text not null,
	position integer not null check (position > 0),
	item_type text not null check (item_type in ('heading', 'question')),
	fact_key text check (
		fact_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' and char_length(fact_key) <= 80
	),
	-- A heading's title, or the question itself.
	label text not null check (char_length(btrim(label)) between 1 and 200),
	hint text check (hint is null or char_length(hint) between 1 and 300),
	built_in boolean not null default false,
	required boolean not null default false,
	-- Offers "I don't have this yet" and "I need Uplift's help".
	can_defer boolean not null default false,
	-- Only for questions that are not built in. A5 adds the remaining answer types.
	kind text check (kind in ('text', 'longtext', 'email', 'phone', 'choice')),
	options jsonb check (options is null or (jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 2 and 50)),
	max_length integer check (max_length between 1 and 2000),
	foreign key (version_id, stage_key) references public.setup_stages (version_id, stage_key) on delete cascade,
	constraint setup_items_position_key unique (version_id, stage_key, position) deferrable initially deferred,
	constraint setup_items_fact_key unique (version_id, fact_key),
	constraint setup_items_heading_check check (
		item_type = 'question' or (
			fact_key is null and not built_in and not required and not can_defer
			and kind is null and options is null and max_length is null
		)
	),
	constraint setup_items_question_check check (
		item_type = 'heading' or (fact_key is not null and (built_in = (kind is null)))
	),
	constraint setup_items_choice_check check ((kind = 'choice') = (options is not null))
);

comment on table public.setup_items is
	'Headings and questions of each setup stage. Built-in questions take their answer type from src/lib/setup/catalogue.ts.';

-- 4. A published version is frozen --------------------------------------------------------------------

create or replace function private.prevent_frozen_setup_version_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	if tg_op = 'DELETE' then
		if old.status <> 'draft' then
			raise exception 'A published setup version cannot be deleted.' using errcode = 'check_violation';
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

	raise exception 'A published setup version cannot be changed. Publish a new version instead.'
		using errcode = 'check_violation';
end;
$$;

create trigger setup_versions_frozen
	before update or delete on public.setup_versions
	for each row execute function private.prevent_frozen_setup_version_change();

create or replace function private.prevent_frozen_setup_content_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
	target_version_id uuid := case when tg_op = 'DELETE' then old.version_id else new.version_id end;
	target_status text;
begin
	select status into target_status from public.setup_versions where id = target_version_id;
	-- A cascade from deleting a draft finds no version left; that delete was already allowed.
	if target_status is null or target_status = 'draft' then
		return case when tg_op = 'DELETE' then old else new end;
	end if;
	raise exception 'A published setup version''s stages and questions cannot be changed.'
		using errcode = 'check_violation';
end;
$$;

create trigger setup_stages_frozen
	before insert or update or delete on public.setup_stages
	for each row execute function private.prevent_frozen_setup_content_change();

create trigger setup_items_frozen
	before insert or update or delete on public.setup_items
	for each row execute function private.prevent_frozen_setup_content_change();

-- Access ---------------------------------------------------------------------------------------------------

alter table public.setup_versions enable row level security;
alter table public.setup_stages enable row level security;
alter table public.setup_items enable row level security;

revoke all on table public.setup_versions from public, anon, authenticated;
revoke all on table public.setup_stages from public, anon, authenticated;
revoke all on table public.setup_items from public, anon, authenticated;

grant all on table public.setup_versions to service_role;
grant all on table public.setup_stages to service_role;
grant all on table public.setup_items to service_role;

-- 5. Reading the published version -------------------------------------------------------------------
--
-- The questions are not private: any signed-in person may read what setup asks. Answers stay behind their
-- own administrator-only policies (ADR 0005).
create or replace function public.setup_published_catalogue()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'version_id', v.id,
		'version_number', v.version_number,
		'stages', coalesce((
			select jsonb_agg(jsonb_build_object(
				'key', s.stage_key,
				'title', s.title,
				'description', s.description,
				'service_key', s.service_key,
				'items', coalesce((
					select jsonb_agg(jsonb_build_object(
						'type', i.item_type,
						'fact_key', i.fact_key,
						'label', i.label,
						'hint', i.hint,
						'built_in', i.built_in,
						'required', i.required,
						'can_defer', i.can_defer,
						'kind', i.kind,
						'options', i.options,
						'max_length', i.max_length
					) order by i.position)
					from public.setup_items i
					where i.version_id = s.version_id and i.stage_key = s.stage_key
				), '[]'::jsonb)
			) order by s.position)
			from public.setup_stages s
			where s.version_id = v.id
		), '[]'::jsonb)
	)
	from public.setup_versions v
	where v.status = 'published';
$$;

revoke all on function public.setup_published_catalogue() from public, anon;
grant execute on function public.setup_published_catalogue() to authenticated, service_role;

revoke all on function private.prevent_frozen_setup_version_change() from public, anon, authenticated;
revoke all on function private.prevent_frozen_setup_content_change() from public, anon, authenticated;

-- 6. Version 1: exactly the questions src/lib/setup/catalogue.ts asked before this change -----------------

do $$
declare
	v uuid;
begin
	insert into public.setup_versions (version_number, status) values (1, 'draft') returning id into v;

	insert into public.setup_stages (version_id, stage_key, title, description, service_key, position) values
		(v, 'business', 'Your business',
			'The name, people and contact details Uplift builds everything else around.', null, 1);

	insert into public.setup_items (
		version_id, stage_key, position, item_type, fact_key, label, hint, built_in, required, can_defer, kind,
		max_length
	) values
		(v, 'business', 1, 'heading', null, 'Business identity', 'How your business is known. Plain facts are enough — Uplift writes the polished wording.', false, false, false, null, null),
		(v, 'business', 2, 'question', 'business.public_name', 'Business name customers know you by', 'Exactly as it appears on your van, cards or signs.', true, true, false, null, null),
		(v, 'business', 3, 'question', 'business.legal_name', 'Legal name, if different', 'Leave empty if it is the same as the name above.', true, false, false, null, null),
		(v, 'business', 4, 'question', 'business.trade', 'Trade', null, true, true, false, null, null),
		(v, 'business', 5, 'question', 'business.type', 'Type of business', null, true, true, false, null, null),
		(v, 'business', 6, 'heading', null, 'Who Uplift talks to', 'The person we contact during setup, and who gives the final go-ahead before launch.', false, false, false, null, null),
		(v, 'business', 7, 'question', 'business.contact_name', 'Main contact name', null, true, true, false, null, null),
		(v, 'business', 8, 'question', 'business.contact_email', 'Main contact email', null, true, true, false, null, null),
		(v, 'business', 9, 'question', 'business.contact_phone', 'Main contact phone', null, true, true, false, null, null),
		(v, 'business', 10, 'question', 'business.approver_name', 'Final approver name, if someone else', 'Leave empty if the main contact approves the finished work.', true, false, false, null, null),
		(v, 'business', 11, 'question', 'business.approver_email', 'Final approver email', null, true, false, false, null, null),
		(v, 'business', 12, 'heading', null, 'How customers reach you', 'The phone and email shown to customers. No business number or address yet? Say so and Uplift will help.', false, false, false, null, null),
		(v, 'business', 13, 'question', 'business.public_phone', 'Public phone number', null, true, true, true, null, null),
		(v, 'business', 14, 'question', 'business.public_email', 'Public email address', null, true, true, true, null, null),
		(v, 'business', 15, 'heading', null, 'Where you’re based', 'Where you run the business from — your home is fine. It stays private unless you say otherwise.', false, false, false, null, null),
		(v, 'business', 16, 'question', 'business.country', 'Country', null, true, true, false, null, null),
		(v, 'business', 17, 'question', 'business.address_line1', 'Street address', null, true, true, true, null, null),
		(v, 'business', 18, 'question', 'business.address_line2', 'Flat, unit or suite, if any', null, true, false, false, null, null),
		(v, 'business', 19, 'question', 'business.address_city', 'Town or city', null, true, true, false, null, null),
		(v, 'business', 20, 'question', 'business.address_region', 'State, province or county', null, true, false, false, null, null),
		(v, 'business', 21, 'question', 'business.address_postal_code', 'Postcode or ZIP code', null, true, true, false, null, null),
		(v, 'business', 22, 'question', 'business.address_customers_visit', 'Do customers come to this address?', 'A shop, showroom or office counts. A home you only work out from does not.', true, true, false, null, null),
		(v, 'business', 23, 'question', 'business.address_public', 'Can this address be shown publicly?', 'If you keep it private, customers only see your town and the areas you cover.', true, true, false, null, null),
		(v, 'business', 24, 'heading', null, 'Language, time and money', 'How words, times and prices appear across your system. Check each one — none of them becomes your default until you have confirmed it here.', false, false, false, null, null),
		(v, 'business', 25, 'question', 'business.language', 'Language your customers read', 'Uplift writes your website and customer messages in this language.', true, true, false, null, null),
		(v, 'business', 26, 'question', 'business.timezone', 'Time zone', 'Sets the times on your schedule, bookings and reminders.', true, true, false, null, null),
		(v, 'business', 27, 'question', 'business.currency', 'Currency you charge in', 'Used on every quote, invoice and payment.', true, true, false, null, null),
		(v, 'business', 28, 'heading', null, 'Opening hours', 'When customers can reach you. Uplift uses these on your website, your Google profile and your reminders.', false, false, false, null, null),
		(v, 'business', 29, 'question', 'business.hours', 'Normal weekly hours', null, true, true, false, null, null),
		(v, 'business', 30, 'question', 'business.hours_exceptions', 'Holidays and one-off days', 'Days in the next year when you are closed or keep different hours — public holidays, Christmas week, a planned break.', true, false, false, null, null),
		(v, 'business', 31, 'question', 'business.hours_seasonal', 'Seasonal changes, if any', 'For example: closed in January, or longer hours from June to August.', false, false, false, 'longtext', 500);

	update public.setup_versions set status = 'published', published_at = now(),
		published_by_email = 'migration'
	where id = v;
end;
$$;
