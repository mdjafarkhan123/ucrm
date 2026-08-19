-- Sales Pipeline, Part 1: Opportunity foundation.
-- Every Request owns exactly one Opportunity. The board position is never a second editable status:
-- one derivation function decides it from Request and Assessment truth, triggers apply it, and no
-- application path can write it. Standalone Opportunities exist before a Request and start at New Request.

-- 1. Stage derivation ---------------------------------------------------------------------------------

-- The only place that decides where a card sits. Backfill, insert, and every recompute call this.
-- No timezone is involved: the four Request-side stages are pure state, not calendar positions.
create or replace function private.request_pipeline_stage(
  request_status text,
  has_assessment boolean,
  assessment_starts_at timestamptz,
  assessment_completed_at timestamptz
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    -- The Request is no longer live commercial work, so it leaves the board but keeps its identity.
    when request_status in ('completed', 'converted', 'archived') then 'request_closed'
    when assessment_completed_at is not null or request_status = 'assessment_completed'
      then 'assessment_completed'
    when not has_assessment then 'new_request'
    when assessment_starts_at is null then 'assessment_unscheduled'
    else 'assessment_scheduled'
  end;
$$;

revoke all on function private.request_pipeline_stage(text, boolean, timestamptz, timestamptz) from public;

-- 2. Tables --------------------------------------------------------------------------------------------

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  -- Optional until the work has a known address. A standalone Opportunity may not have one yet.
  property_id uuid,
  -- Null means standalone: created before a Request exists.
  request_id uuid,
  title text not null check (char_length(trim(title)) between 2 and 160),
  outcome text not null default 'open' check (outcome in ('open', 'won', 'lost')),
  -- Derived, never authored. Triggers own both of these columns.
  stage text not null default 'new_request' check (stage in (
    'new_request',
    'assessment_unscheduled',
    'assessment_scheduled',
    'assessment_completed',
    'request_closed'
  )),
  stage_entered_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Immutable history needs a tenant-safe composite parent.
  constraint opportunities_organization_id_unique unique (organization_id, id),
  -- Exactly one Opportunity per Request, including two concurrent attempts. Standalone rows keep
  -- request_id null, and Postgres treats those nulls as distinct, so they never collide.
  constraint opportunities_request_unique unique (organization_id, request_id),
  constraint opportunities_client_organization_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict,
  constraint opportunities_property_organization_fk foreign key (organization_id, property_id)
    references public.properties(organization_id, id) on delete restrict,
  constraint opportunities_request_organization_fk foreign key (organization_id, request_id)
    references public.requests(organization_id, id) on delete cascade
);

-- One index serves every board column and its keyset cursor. Partial, because closed and decided
-- Opportunities are the part of the table that grows forever and the board never asks for them.
create index opportunities_board_idx
  on public.opportunities(organization_id, stage, stage_entered_at desc, id)
  where outcome = 'open' and stage <> 'request_closed';

create index opportunities_organization_client_idx on public.opportunities(organization_id, client_id);

create index opportunities_organization_property_idx
  on public.opportunities(organization_id, property_id)
  where property_id is not null;

create table public.opportunity_stage_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  opportunity_id uuid not null,
  -- Null on the very first event, when the Opportunity came into existence.
  from_stage text,
  to_stage text not null,
  -- Kept even after the member leaves, so stage age and audit never lose their history.
  actor_user_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  constraint opportunity_stage_events_opportunity_fk
    foreign key (organization_id, opportunity_id)
    references public.opportunities(organization_id, id) on delete cascade
);

create index opportunity_stage_events_opportunity_idx
  on public.opportunity_stage_events(organization_id, opportunity_id, occurred_at desc);

create trigger opportunities_set_updated_at
before update on public.opportunities
for each row execute function public.set_updated_at();

-- 3. Stage is applied, never authored --------------------------------------------------------------------

-- Runs before every insert and update and overwrites whatever the caller sent. Reading the Request and
-- Assessment here is what makes it impossible for the board to disagree with them.
create or replace function private.opportunity_apply_stage()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  resolved_stage text;
  request_row record;
begin
  if new.request_id is null then
    -- A standalone Opportunity sits at the front of the board until a Request gives it real state.
    resolved_stage := 'new_request';
  else
    select
      request.status as status,
      assessment.id is not null as has_assessment,
      assessment.starts_at as starts_at,
      assessment.completed_at as completed_at
    into request_row
    from public.requests as request
    left join public.assessments as assessment
      on assessment.request_id = request.id
    where request.id = new.request_id
      and request.organization_id = new.organization_id;

    resolved_stage := private.request_pipeline_stage(
      request_row.status,
      coalesce(request_row.has_assessment, false),
      request_row.starts_at,
      request_row.completed_at
    );
  end if;

  new.stage := resolved_stage;

  if tg_op = 'INSERT' then
    new.stage_entered_at := coalesce(new.stage_entered_at, now());
  elsif new.stage is distinct from old.stage then
    new.stage_entered_at := now();
  else
    new.stage_entered_at := old.stage_entered_at;
  end if;

  return new;
end;
$$;

create trigger opportunities_apply_stage
before insert or update on public.opportunities
for each row execute function private.opportunity_apply_stage();

-- History is written in one place, so a transition cannot be recorded twice or missed.
create or replace function private.opportunity_record_stage_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.opportunity_stage_events (
    organization_id, opportunity_id, from_stage, to_stage, actor_user_id, occurred_at
  )
  values (
    new.organization_id,
    new.id,
    case when tg_op = 'INSERT' then null else old.stage end,
    new.stage,
    (select auth.uid()),
    new.stage_entered_at
  );
  return null;
end;
$$;

create trigger opportunities_record_created_stage
after insert on public.opportunities
for each row execute function private.opportunity_record_stage_event();

create trigger opportunities_record_stage_change
after update on public.opportunities
for each row
when (old.stage is distinct from new.stage)
execute function private.opportunity_record_stage_event();

-- 4. Automatic identity and recompute -----------------------------------------------------------------

-- Security definer on purpose: a member who may create a Request but has no Pipeline permission must
-- still get the Opportunity created. Identity is not a permission-gated feature.
create or replace function private.opportunity_for_new_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.opportunities (organization_id, client_id, property_id, request_id, title)
  values (new.organization_id, new.client_id, new.property_id, new.id, new.title)
  on conflict (organization_id, request_id) do nothing;
  return null;
end;
$$;

create trigger requests_create_opportunity
after insert on public.requests
for each row execute function private.opportunity_for_new_request();

-- Touching the row is enough: the before-update trigger recomputes the stage from current truth.
create or replace function private.opportunity_resync_from_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_request_id uuid;
begin
  -- NEW does not exist on a delete, so the two cases stay apart.
  if tg_table_name = 'requests' then
    target_request_id := new.id;
  elsif tg_op = 'DELETE' then
    target_request_id := old.request_id;
  else
    target_request_id := new.request_id;
  end if;

  update public.opportunities
  set updated_at = now()
  where request_id = target_request_id;

  return null;
end;
$$;

create trigger requests_resync_opportunity_stage
after update of status on public.requests
for each row
when (old.status is distinct from new.status)
execute function private.opportunity_resync_from_request();

create trigger assessments_resync_opportunity_stage
after insert or delete on public.assessments
for each row execute function private.opportunity_resync_from_request();

create trigger assessments_resync_opportunity_stage_on_change
after update of starts_at, completed_at on public.assessments
for each row
when (
  old.starts_at is distinct from new.starts_at
  or old.completed_at is distinct from new.completed_at
)
execute function private.opportunity_resync_from_request();

revoke all on function private.opportunity_apply_stage() from public;
revoke all on function private.opportunity_record_stage_event() from public;
revoke all on function private.opportunity_for_new_request() from public;
revoke all on function private.opportunity_resync_from_request() from public;

-- 5. Permissions ----------------------------------------------------------------------------------------

insert into public.permissions (key, description)
values
  ('pipeline.view', 'See the sales pipeline and its opportunities'),
  ('pipeline.edit', 'Create and change opportunities on the sales pipeline')
on conflict (key) do update set description = excluded.description;

-- Field and finance are deliberately absent. A crew member does not work a sales board, and finance
-- starts at the invoice.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'pipeline.view'),
  ('owner', 'pipeline.edit'),
  ('admin', 'pipeline.view'),
  ('admin', 'pipeline.edit'),
  ('office', 'pipeline.view'),
  ('office', 'pipeline.edit'),
  ('sales', 'pipeline.view'),
  ('sales', 'pipeline.edit')
on conflict (role, permission_key) do nothing;

-- 6. Row level security ------------------------------------------------------------------------------------

alter table public.opportunities enable row level security;
alter table public.opportunity_stage_events enable row level security;

create policy "permitted members can view opportunities"
on public.opportunities for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'pipeline.view')
);

create policy "permitted members can create opportunities"
on public.opportunities for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'pipeline.edit')
);

create policy "permitted members can update opportunities"
on public.opportunities for update to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'pipeline.edit')
)
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'pipeline.edit')
);

-- Read only. History is written by triggers alone, and nothing may rewrite it.
create policy "permitted members can view opportunity stage events"
on public.opportunity_stage_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'pipeline.view')
);

revoke all on public.opportunities, public.opportunity_stage_events from anon;
revoke all on public.opportunities, public.opportunity_stage_events from authenticated;

-- No delete in Part 1. Removing commercial history is its own decision with its own permission.
grant select, insert, update on public.opportunities to authenticated;
grant select on public.opportunity_stage_events to authenticated;

-- 7. Backfill --------------------------------------------------------------------------------------------

-- Idempotent: the unique constraint makes a second run, or a Request created while this runs, a no-op.
-- The insert trigger overwrites the placeholder stage with the real one, and stage_entered_at carries the
-- best age the existing data can honestly support.
insert into public.opportunities (
  organization_id, client_id, property_id, request_id, title, stage_entered_at, created_at
)
select
  request.organization_id,
  request.client_id,
  request.property_id,
  request.id,
  request.title,
  greatest(request.created_at, request.updated_at),
  request.created_at
from public.requests as request
on conflict (organization_id, request_id) do nothing;
