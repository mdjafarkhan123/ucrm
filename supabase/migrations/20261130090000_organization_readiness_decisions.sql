-- Multi-industry platform foundation B8: Uplift signs off the real-world things a business may do to its own
-- customers, one area at a time.
--
-- Paying and finishing Setup open the Business Workspace for private preparation. Sending to customers, taking
-- requests from new customers and starting automations each wait for their own Uplift sign-off. There are four
-- areas (public_intake, customer_messaging, customer_billing, customer_automation); the checks inside each
-- area live in the app's catalogue, like the experience registry. Every sign-off decision is a full snapshot of
-- the area's checks, kept in an append-only chain per Organization and area; the head of the chain is the
-- current answer. An area with no decision is closed.
--
-- Businesses that existed before this change keep working: each gets a 'carried_over' ready decision per
-- area, so nothing stops and nothing is claimed to have been reviewed. Uplift can still review any of them.

-- ---------------------------------------------------------------------------------------------------
-- Decisions
-- ---------------------------------------------------------------------------------------------------

create table public.organization_readiness_decisions (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	area_key text not null check (
		area_key in ('public_intake', 'customer_messaging', 'customer_billing', 'customer_automation')
	),
	-- ready: open for real customers. not_ready: tasks remain. held: Uplift deliberately stopped it.
	status text not null check (status in ('ready', 'not_ready', 'held')),
	-- One entry per check: {"key": text, "state": "open" | "done" | "not_applicable", "note": text?}.
	-- Empty only for a carried-over decision, which reviewed nothing.
	checks jsonb not null default '[]' check (jsonb_typeof(checks) = 'array'),
	-- What Uplift tells itself (never shown to the business).
	reason text not null check (char_length(trim(reason)) between 1 and 1000),
	-- What the business reads when this area is not ready; required when held.
	business_message text check (business_message is null or char_length(trim(business_message)) between 1 and 500),
	source text not null check (source in ('review', 'carried_over')),
	actor_email text not null check (char_length(trim(actor_email)) between 3 and 320),
	previous_decision_id uuid references public.organization_readiness_decisions (id),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	decided_at timestamptz not null default clock_timestamp(),
	check (status <> 'held' or business_message is not null),
	check (source <> 'carried_over' or (status = 'ready' and checks = '[]'::jsonb))
);

comment on table public.organization_readiness_decisions is
	'Append-only chain of Uplift''s sign-offs per Organization and area. The head of each chain is the current answer; an area with no decision is closed.';

create unique index organization_readiness_decisions_chain_idx
	on public.organization_readiness_decisions (organization_id, area_key, previous_decision_id) nulls not distinct;
create index organization_readiness_decisions_history_idx
	on public.organization_readiness_decisions (organization_id, area_key, decided_at desc);
create index organization_readiness_decisions_previous_idx
	on public.organization_readiness_decisions (previous_decision_id);

create or replace function private.prevent_readiness_decision_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	raise exception 'A readiness decision cannot be changed. Record a new decision instead.'
		using errcode = 'check_violation';
end;
$$;

create trigger organization_readiness_decisions_append_only
	before update on public.organization_readiness_decisions
	for each row execute function private.prevent_readiness_decision_change();

-- A check list is well formed, and a ready decision has nothing left open.
create or replace function private.readiness_checks_are_valid(checks jsonb, require_all_closed boolean)
returns boolean
language sql
immutable
set search_path = ''
as $$
	select jsonb_typeof(checks) = 'array'
		and not exists (
			select 1
			from jsonb_array_elements(checks) item
			where jsonb_typeof(item) <> 'object'
				or jsonb_typeof(item -> 'key') is distinct from 'string'
				or (item ->> 'key') !~ '^[a-z][a-z_]{1,59}$'
				or (item ->> 'state') is null
				or (item ->> 'state') not in ('open', 'done', 'not_applicable')
				or (require_all_closed and (item ->> 'state') = 'open')
		)
		and (
			select count(distinct item ->> 'key') = count(*)
			from jsonb_array_elements(checks) item
		);
$$;

-- ---------------------------------------------------------------------------------------------------
-- Owner command
-- ---------------------------------------------------------------------------------------------------

create or replace function public.record_organization_readiness_decision(
	target_organization_id uuid,
	target_area_key text,
	target_status text,
	target_checks jsonb,
	decision_reason text,
	business_message text,
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
	existing_decision public.organization_readiness_decisions%rowtype;
	current_decision public.organization_readiness_decisions%rowtype;
	inserted_id uuid;
begin
	select * into existing_decision
	from public.organization_readiness_decisions d
	where d.idempotency_key = record_organization_readiness_decision.idempotency_key;
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

	if not private.readiness_checks_are_valid(target_checks, target_status = 'ready') then
		raise exception 'A ready area cannot have a check still open.' using errcode = 'check_violation';
	end if;
	if target_status = 'ready' and jsonb_array_length(target_checks) = 0 and decision_source <> 'carried_over' then
		raise exception 'A ready decision needs its checks.' using errcode = 'check_violation';
	end if;

	select * into current_decision
	from public.organization_readiness_decisions d
	where d.organization_id = target_organization_id
		and d.area_key = target_area_key
		and not exists (
			select 1 from public.organization_readiness_decisions later where later.previous_decision_id = d.id
		);

	if current_decision.id is distinct from expected_previous_decision_id then
		raise exception 'This area changed while you were reviewing it. Reload and review again.'
			using errcode = 'P0409';
	end if;

	insert into public.organization_readiness_decisions (
		organization_id, area_key, status, checks, reason, business_message, source, actor_email,
		previous_decision_id, idempotency_key
	) values (
		target_organization_id, target_area_key, target_status, target_checks, trim(decision_reason),
		nullif(trim(business_message), ''), decision_source, lower(trim(actor_email)), current_decision.id,
		record_organization_readiness_decision.idempotency_key
	)
	returning id into inserted_id;

	return jsonb_build_object('applied', true, 'decision_id', inserted_id);
end;
$$;

revoke all on function public.record_organization_readiness_decision(uuid, text, text, jsonb, text, text, uuid, text, text, text)
	from public, anon, authenticated;
grant execute on function public.record_organization_readiness_decision(uuid, text, text, jsonb, text, text, uuid, text, text, text)
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- What a Team member may read: the current answer per area, without Uplift's private reason or reviewer.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.organization_readiness_for_member(target_organization_id uuid)
returns table (
	area_key text,
	status text,
	source text,
	checks jsonb,
	business_message text,
	decided_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
	select d.area_key, d.status, d.source, d.checks, d.business_message, d.decided_at
	from public.organization_readiness_decisions d
	where private.is_organization_member(target_organization_id)
		and d.organization_id = target_organization_id
		and not exists (
			select 1 from public.organization_readiness_decisions later where later.previous_decision_id = d.id
		);
$$;

revoke all on function public.organization_readiness_for_member(uuid) from public, anon;
grant execute on function public.organization_readiness_for_member(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- Row security: Uplift reads and writes through the service role; members read through the function above.
-- ---------------------------------------------------------------------------------------------------

alter table public.organization_readiness_decisions enable row level security;
revoke all on public.organization_readiness_decisions from anon, authenticated;
grant all on public.organization_readiness_decisions to service_role;

-- ---------------------------------------------------------------------------------------------------
-- Businesses that existed before sign-offs keep working: one carried-over ready decision per area.
-- ---------------------------------------------------------------------------------------------------

insert into public.organization_readiness_decisions (
	organization_id, area_key, status, checks, reason, source, actor_email, idempotency_key
)
select
	o.id,
	a.area_key,
	'ready',
	'[]'::jsonb,
	'Carried over: this business was already working before Uplift signed off these areas. Nothing was reviewed.',
	'carried_over',
	'system@uplift.invalid',
	'carried-over-' || a.area_key || '-' || o.id
from public.organizations o
cross join (
	values ('public_intake'), ('customer_messaging'), ('customer_billing'), ('customer_automation')
) as a (area_key);
