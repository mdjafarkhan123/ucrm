-- Jobs, Part 4: identity, numbering, lifecycle, permissions, and the tenant boundary.
--
-- What starts here: a job number allocator, the jobs table, the guards that make its state machine and its
-- identity unchangeable, a job history table, the five permission keys whose behavior exists, and the
-- read rules. What does not start here: scope lines, visits, recurrence, billing schedules, invoicing, and
-- every lifecycle command. Those arrive in Parts 5 and after, each behind its own approval gate.
--
-- Contract: docs/jobs-behavior-contract.md, approved by Jafar 2026-09-01. Two rules from it are enforced by
-- the database rather than by a screen: job type can never change after creation, and only `active` and
-- `closed` are stored. Everything Jobber shows as a status that we can compute -- Late, Unscheduled, Action
-- required, Requires invoicing, Archived, Ending soon -- is computed by the reader, so the clock passing
-- never writes a row.

-- 1. Job numbers -------------------------------------------------------------------------------------------

-- Same shape as organization_quote_counters: one row per organization, RLS on, no policy, no grant. Nobody
-- reads it but the allocator, so a member cannot learn how much work an organization has by counting.
create table public.organization_job_counters (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  next_job_number integer not null default 1 check (next_job_number >= 1),
  updated_at timestamptz not null default now()
);

comment on table public.organization_job_counters is
  'Per-organization job number allocation. Written only by private.allocate_job_number under a row lock; '
  'numbers are never reused and never decrease.';

alter table public.organization_job_counters enable row level security;
revoke all on public.organization_job_counters from anon, authenticated;

-- The update takes the row lock, so two creations arriving together are serialised here and cannot be handed
-- the same number.
create or replace function private.allocate_job_number(target_organization_id uuid)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  allocated integer;
begin
  insert into public.organization_job_counters (organization_id)
  values (target_organization_id)
  on conflict (organization_id) do nothing;

  update public.organization_job_counters
  set next_job_number = next_job_number + 1, updated_at = now()
  where organization_id = target_organization_id
  returning next_job_number - 1 into allocated;

  if allocated is null then
    raise exception 'That organization cannot be given a job number.' using errcode = 'foreign_key_violation';
  end if;

  return allocated;
end;
$$;

revoke all on function private.allocate_job_number(uuid) from public;
revoke execute on function private.allocate_job_number(uuid) from anon, authenticated;

-- 2. The job ------------------------------------------------------------------------------------------------

-- The agreement, not the appointment. Visits are their own rows and arrive in Part 7; nothing here pretends
-- to hold a date.
create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  property_id uuid not null,
  -- Null for a job somebody started directly. Set, and permanent, for one converted from a quote.
  quote_id uuid,
  quote_version_id uuid,
  job_number integer not null check (job_number >= 1),
  title text not null check (char_length(trim(title)) between 2 and 160),
  job_type text not null check (job_type in ('one_off', 'recurring')),
  -- An ongoing agreement dispatched when work is needed. It is a recurring job that generates no visits, so
  -- it is a flag on the type rather than a third type nothing else understands.
  is_as_needed boolean not null default false,
  status text not null default 'active' check (status in ('active', 'closed')),
  price_basis text not null check (price_basis in ('job_total', 'per_visit', 'fixed_per_period')),
  billing_timing text not null default 'on_closure' check (billing_timing in (
    'on_closure', 'per_completed_visit', 'month_end', 'custom_dates', 'manual'
  )),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  instructions text check (instructions is null or char_length(instructions) <= 4000),
  -- Job level, with an organization default behind it, exactly as Jobber does it. Not a per-visit setting.
  arrival_window_minutes integer check (arrival_window_minutes is null or arrival_window_minutes between 15 and 240),
  arrival_window_style text check (arrival_window_style is null or arrival_window_style in ('after_start', 'centered')),
  contract_start_date date,
  contract_end_date date,
  -- Maintained by the scope and billing commands in Parts 5 and 11. They are here now so the grant below can
  -- fence them off from the start rather than after somebody has already read them.
  subtotal_minor bigint not null default 0 check (subtotal_minor between 0 and 1000000000000),
  discount_minor bigint not null default 0 check (discount_minor between 0 and 1000000000000),
  tax_minor bigint not null default 0 check (tax_minor between 0 and 1000000000000),
  total_minor bigint not null default 0 check (total_minor between 0 and 1000000000000),
  cost_minor bigint not null default 0 check (cost_minor between 0 and 1000000000000),
  -- A caller sends the revision it read; a stale one is refused so two people editing a job cannot silently
  -- overwrite each other.
  revision integer not null default 0 check (revision >= 0),
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  reopened_at timestamptz,
  -- The conversion command's receipt, kept on the row it produced, which is how every other command in this
  -- repository already does idempotency.
  conversion_idempotency_key text,
  conversion_request_hash text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint jobs_organization_id_unique unique (organization_id, id),
  constraint jobs_number_unique unique (organization_id, job_number),
  constraint jobs_client_organization_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict,
  constraint jobs_property_organization_fk foreign key (organization_id, property_id)
    references public.properties(organization_id, id) on delete restrict,
  constraint jobs_quote_organization_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete restrict,
  -- As-needed is a recurring arrangement. A one-off job that fires when needed is a contradiction.
  constraint jobs_as_needed_is_recurring check (not is_as_needed or job_type = 'recurring'),
  -- The contract's price basis table, enforced: a whole-job price belongs to one-off work, and per-visit or
  -- fixed-per-period pricing belongs to repeating work.
  constraint jobs_price_basis_matches_type check (
    (job_type = 'one_off' and price_basis = 'job_total')
    or (job_type = 'recurring' and price_basis in ('per_visit', 'fixed_per_period'))
  ),
  constraint jobs_contract_dates_ordered check (
    contract_start_date is null or contract_end_date is null or contract_end_date >= contract_start_date
  ),
  constraint jobs_arrival_window_complete check (
    (arrival_window_minutes is null) = (arrival_window_style is null)
  ),
  -- A closed job knows when it closed and an active one does not claim to. The stamp and the status cannot
  -- drift apart.
  constraint jobs_closed_stamp_matches_status check (
    (status = 'closed') = (closed_at is not null)
  ),
  constraint jobs_quote_version_needs_quote check (
    quote_version_id is null or quote_id is not null
  ),
  constraint jobs_conversion_receipt_consistent check (
    (conversion_idempotency_key is null) = (conversion_request_hash is null)
  ),
  constraint jobs_conversion_needs_quote check (
    conversion_idempotency_key is null or quote_id is not null
  )
);

comment on table public.jobs is
  'Job identity and lifecycle. The agreement, never the appointment. Members may read this table and never '
  'write it: rows are created by private.create_job and changed by the commands added in later parts, each '
  'through its own checked function.';

comment on column public.jobs.status is
  'The only two stored states. Upcoming, Today, Late, Unscheduled, Action required, Requires invoicing, '
  'Archived and Ending soon are derived by the reader from visits, reminders and the clock.';

-- One quote may produce one job, and this is what makes that true when two conversions race: the loser fails
-- on the index rather than creating a second job.
create unique index jobs_quote_lineage_idx
  on public.jobs(organization_id, quote_id)
  where quote_id is not null;

create unique index jobs_conversion_key_idx
  on public.jobs(organization_id, conversion_idempotency_key)
  where conversion_idempotency_key is not null;

-- The list page's default view and its keyset paging: this organization's open work, newest first.
create index jobs_active_idx
  on public.jobs(organization_id, created_at desc, id)
  where status = 'active';

-- The whole list including closed work, for the status filter and its paging.
create index jobs_organization_created_idx on public.jobs(organization_id, created_at desc, id);

create index jobs_client_idx on public.jobs(organization_id, client_id, created_at desc, id);
create index jobs_property_idx on public.jobs(organization_id, property_id);
create index jobs_created_by_idx on public.jobs(created_by) where created_by is not null;
create index jobs_closed_by_idx on public.jobs(closed_by) where closed_by is not null;
create index jobs_quote_version_idx on public.jobs(quote_version_id) where quote_version_id is not null;

create trigger jobs_set_updated_at
before update on public.jobs
for each row execute function public.set_updated_at();

-- 3. What can never change, and what can change into what ---------------------------------------------------

-- Jobber locks job type at creation and so do we, because type decides how the job is priced, scheduled and
-- billed; a switch would silently invalidate all three. The guard lives here rather than in a command so a
-- future command, a fixup script, or a mistake in a migration cannot get around it.
create or replace function private.jobs_guard_identity_and_transitions()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'A job cannot be moved to another organization.' using errcode = 'check_violation';
  end if;
  if new.job_number is distinct from old.job_number then
    raise exception 'A job number cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.job_type is distinct from old.job_type or new.is_as_needed is distinct from old.is_as_needed then
    raise exception 'A job type cannot be changed after the job is created. Create a new job instead.'
      using errcode = 'check_violation';
  end if;
  if new.client_id is distinct from old.client_id then
    raise exception 'A job cannot be moved to another client.' using errcode = 'check_violation';
  end if;
  -- Lineage is permanent in both directions: a converted job can never forget its quote, and a direct job can
  -- never claim one it did not come from.
  if new.quote_id is distinct from old.quote_id or new.quote_version_id is distinct from old.quote_version_id then
    raise exception 'Quote lineage cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'A job creation time cannot be changed.' using errcode = 'check_violation';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'active' and new.status = 'closed')
      or (old.status = 'closed' and new.status = 'active')
    ) then
      raise exception 'A job cannot go from % to %.', old.status, new.status
        using errcode = 'check_violation';
    end if;

    if new.status = 'closed' and new.closed_at is null then
      new.closed_at := now();
    end if;
    if new.status = 'active' then
      new.closed_at := null;
      new.closed_by := null;
      new.reopened_at := now();
    end if;
  end if;

  return new;
end;
$$;

create trigger jobs_guard_identity_and_transitions
before update on public.jobs
for each row execute function private.jobs_guard_identity_and_transitions();

-- 4. Job history ----------------------------------------------------------------------------------------------

-- Safe facts, never a second copy of the job. Later parts append to it and the Automation event spine reads
-- from the same commands that write it.
create table public.job_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  event_type text not null check (char_length(trim(event_type)) between 2 and 64),
  actor_id uuid references auth.users(id) on delete set null,
  prior_status text check (prior_status is null or prior_status in ('active', 'closed')),
  new_status text check (new_status is null or new_status in ('active', 'closed')),
  related_quote_id uuid,
  related_visit_id uuid,
  related_invoice_id uuid,
  -- Redacted metadata only: counts, reasons and ids. Never customer content and never money a reader is not
  -- entitled to see.
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint job_events_organization_id_unique unique (organization_id, id),
  constraint job_events_job_organization_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade
);

comment on table public.job_events is
  'Job lifecycle and activity history. Append only in practice: no command updates or deletes a row, and no '
  'grant lets a member write one.';

create index job_events_job_idx on public.job_events(organization_id, job_id, created_at desc, id);
create index job_events_actor_idx on public.job_events(actor_id) where actor_id is not null;

-- 5. The one row writer ------------------------------------------------------------------------------------------

-- Quote conversion (Part 5) and direct creation (Part 7) both need a job to exist with a number, a first
-- history row, and every guard above satisfied. That is one job of work, so it is one function, called by
-- those commands after they have checked their own permission and their own inputs. It is private: it checks
-- tenancy, not authorisation, and nothing outside the database may call it.
create or replace function private.create_job(
  target_organization_id uuid,
  target_client_id uuid,
  target_property_id uuid,
  new_title text,
  new_job_type text,
  new_price_basis text,
  new_currency_code text,
  actor uuid,
  new_is_as_needed boolean default false,
  new_billing_timing text default 'on_closure',
  new_instructions text default null,
  source_quote_id uuid default null,
  source_quote_version_id uuid default null,
  idempotency_key text default null,
  request_hash text default null
)
returns public.jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created public.jobs;
  clean_title text := nullif(trim(coalesce(new_title, '')), '');
begin
  if clean_title is null or char_length(clean_title) < 2 or char_length(clean_title) > 160 then
    raise exception 'A job needs a title between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  -- The property has to belong to the client, and both have to belong to the organization. The composite
  -- foreign keys already stop a cross-tenant row; this stops a same-tenant mismatch with a sentence a person
  -- can act on.
  if not exists (
    select 1 from public.properties
    where id = target_property_id
      and organization_id = target_organization_id
      and client_id = target_client_id
  ) then
    raise exception 'That property does not belong to that client.' using errcode = 'check_violation';
  end if;

  insert into public.jobs (
    organization_id, client_id, property_id, quote_id, quote_version_id, job_number, title,
    job_type, is_as_needed, price_basis, billing_timing, currency_code, instructions,
    conversion_idempotency_key, conversion_request_hash, created_by
  ) values (
    target_organization_id,
    target_client_id,
    target_property_id,
    source_quote_id,
    source_quote_version_id,
    private.allocate_job_number(target_organization_id),
    clean_title,
    new_job_type,
    coalesce(new_is_as_needed, false),
    new_price_basis,
    coalesce(new_billing_timing, 'on_closure'),
    new_currency_code,
    nullif(trim(coalesce(new_instructions, '')), ''),
    idempotency_key,
    request_hash,
    actor
  )
  returning * into created;

  insert into public.job_events (
    organization_id, job_id, event_type, actor_id, new_status, related_quote_id, metadata
  ) values (
    target_organization_id,
    created.id,
    'job_created',
    actor,
    'active',
    source_quote_id,
    jsonb_build_object('job_type', new_job_type, 'from_quote', source_quote_id is not null)
  );

  return created;
end;
$$;

revoke all on function private.create_job(
  uuid, uuid, uuid, text, text, text, text, uuid, boolean, text, text, uuid, uuid, text, text
) from public;
revoke execute on function private.create_job(
  uuid, uuid, uuid, text, text, text, text, uuid, boolean, text, text, uuid, uuid, text, text
) from anon, authenticated;

-- 6. Permissions -------------------------------------------------------------------------------------------------

-- Only the keys whose behavior exists are seeded. jobs.schedule, jobs.complete, jobs.close and jobs.delete
-- arrive with the parts that build scheduling, completion, closing and deletion; seeding them now would put
-- switches in the Team access editor that turn nothing on.
insert into public.permissions (key, description)
values
  ('jobs.view', 'See jobs and their contents'),
  ('jobs.view_price', 'See job prices, totals and billing'),
  ('jobs.view_cost', 'See internal cost and profit on a job'),
  ('jobs.create', 'Start a job, including from an approved quote'),
  ('jobs.edit', 'Change a job''s details, scope and billing')
on conflict (key) do update set description = excluded.description;

-- Field is here, unlike quotes, because a crew member has to be able to open the job they are standing in
-- front of. They see the work; price and cost stay with the office and finance.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'jobs.view'),
  ('owner', 'jobs.view_price'),
  ('owner', 'jobs.view_cost'),
  ('owner', 'jobs.create'),
  ('owner', 'jobs.edit'),

  ('admin', 'jobs.view'),
  ('admin', 'jobs.view_price'),
  ('admin', 'jobs.view_cost'),
  ('admin', 'jobs.create'),
  ('admin', 'jobs.edit'),

  ('office', 'jobs.view'),
  ('office', 'jobs.view_price'),
  ('office', 'jobs.create'),
  ('office', 'jobs.edit'),

  ('sales', 'jobs.view'),
  ('sales', 'jobs.view_price'),
  ('sales', 'jobs.create'),
  ('sales', 'jobs.edit'),

  ('finance', 'jobs.view'),
  ('finance', 'jobs.view_price'),
  ('finance', 'jobs.view_cost'),

  ('field', 'jobs.view')
on conflict (role, permission_key) do nothing;

-- 7. Row level security ---------------------------------------------------------------------------------------

alter table public.jobs enable row level security;
alter table public.job_events enable row level security;

create policy "permitted members can view jobs"
on public.jobs for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

create policy "permitted members can view job events"
on public.job_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

revoke all on public.jobs from anon, authenticated;
revoke all on public.job_events from anon, authenticated;

-- Money is not in this grant. Postgres cannot subtract a column from a table-wide grant, so every column a
-- reader is entitled to is named instead, and a money column added later is unreadable until somebody adds it
-- here on purpose: it fails loudly rather than leaking quietly.
grant select (
  id, organization_id, client_id, property_id, quote_id, quote_version_id, job_number, title,
  job_type, is_as_needed, status, price_basis, billing_timing, currency_code, instructions,
  arrival_window_minutes, arrival_window_style, contract_start_date, contract_end_date,
  revision, closed_at, closed_by, reopened_at, created_by, created_at, updated_at
) on public.jobs to authenticated;

grant select on public.job_events to authenticated;

-- 8. The gated reader that gives the money back -------------------------------------------------------------------

-- The totals for a set of jobs, keyed by job id. One permission check for the whole call rather than one per
-- row, the same shape as quote_version_money.
create or replace function public.job_money(target_job_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  if target_job_ids is null or cardinality(target_job_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct job.organization_id) into organizations
  from public.jobs as job
  where job.id = any(target_job_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those jobs do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to these jobs.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(org, caller, 'jobs.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(job.id::text,
      (case when can_price then jsonb_build_object(
         'subtotal_minor', job.subtotal_minor,
         'discount_minor', job.discount_minor,
         'tax_minor', job.tax_minor,
         'total_minor', job.total_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'cost_minor', job.cost_minor,
         'profit_minor', job.total_minor - job.tax_minor - job.cost_minor
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.jobs as job
  where job.organization_id = org
    and job.id = any(target_job_ids);

  return answer;
end;
$$;

comment on function public.job_money(uuid[]) is
  'Money for a set of jobs, keyed by job id. Prices need jobs.view_price and cost and profit need '
  'jobs.view_cost; a reader holding neither gets an empty object.';

revoke all on function public.job_money(uuid[]) from public;
revoke execute on function public.job_money(uuid[]) from anon;
grant execute on function public.job_money(uuid[]) to authenticated;

notify pgrst, 'reload schema';
