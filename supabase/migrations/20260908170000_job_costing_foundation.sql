-- Jobs Part 14a: the foundation under labor, expenses and job costing.
--
-- What this migration establishes, and deliberately nothing more: where an employee's hourly cost lives,
-- the two tables that record what a job actually consumed, the append-only trail that keeps corrections
-- honest, and the permission keys that separate recording work from seeing what it cost. The commands and
-- screens that write these rows arrive in 14b (labor) and 14c (expenses); the profit panel arrives in 14d.
--
-- Two rules from the behavior contract shape every table below:
--
--   1. Money never sits in a grant. `authenticated` reads the shape of a record -- who, when, how long --
--      and never the money on it. Cost reaches a route only through a reader that checks jobs.view_cost
--      itself, exactly as jobs, job_line_items and quotes already do. A money column added here later stays
--      unreadable until someone names it in a grant on purpose.
--   2. A changed labor rate applies forward only. That is not enforced by remembering rate history; it is
--      enforced by copying the rate onto the time entry at the moment it is recorded. A past entry has no
--      link to the current rate, so no rate change can reach backwards and re-cost finished work. Jobber
--      states the same rule: "The labor cost will apply to their future time sheet hours, not any past
--      time sheets."

-- 1. Where an employee's hourly cost lives -------------------------------------------------------------

-- Its own table, not a column on organization_members. A loaded labor rate is wage, benefits and taxes --
-- private pay data -- and organization_members is read across the app by anyone who can see a teammate's
-- name. Keeping the rate in a separate, fully revoked table means the widely readable row stays widely
-- readable and the private number is reachable only through a permission-checked reader.
create table public.organization_member_cost_profiles (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  -- Null is a real state and not the same as zero: nobody has told us what this person costs yet. Costing
  -- reports those hours as unrated rather than quietly valuing them at nothing.
  cost_per_hour_minor bigint check (cost_per_hour_minor is null or cost_per_hour_minor between 0 and 100000000),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id),
  constraint organization_member_cost_profiles_member_fk foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade
);

comment on table public.organization_member_cost_profiles is
  'An employee''s hourly cost to the business, including wage, benefits and taxes. Separate from '
  'organization_members because that row is readable by anyone who can see a teammate; this number is not. '
  'Job costing never reads it live -- it reads the copy taken onto each time entry when the time was '
  'recorded, so a rate change applies forward only.';

alter table public.organization_member_cost_profiles enable row level security;

-- Who may know what a teammate costs: whoever administers the team, and whoever is allowed to see cost on
-- a job. Both are already-shipped keys; this part invents no new answer to that question.
create policy "permitted members can view cost profiles"
on public.organization_member_cost_profiles for select to authenticated
using (
  private.is_organization_member(organization_id)
  and (
    private.has_permission(organization_id, 'team.manage')
    or private.has_permission(organization_id, 'jobs.view_cost')
  )
);

revoke all on public.organization_member_cost_profiles from anon, authenticated;

-- The rate itself is not here. That a profile row exists is not sensitive; what it says is.
grant select (
  organization_id, user_id, updated_by, created_at, updated_at
) on public.organization_member_cost_profiles to authenticated;

-- 2. Recorded labor ---------------------------------------------------------------------------------------

-- The twin of public.pricing_line_total_minor, and immutable for the same reason: a generated column can
-- only be built on arithmetic that can never change its answer. One rounding pass, at the same moment for
-- every entry, so no screen or route ever reaches its own conclusion about what an hour cost.
create or replace function public.labor_cost_total_minor(
  minutes integer,
  cost_per_hour_minor bigint
)
returns bigint
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when minutes is null or cost_per_hour_minor is null then null
    else round(cost_per_hour_minor::numeric * minutes / 60)::bigint
  end;
$$;

comment on function public.labor_cost_total_minor(integer, bigint) is
  'Minutes at an hourly rate, in minor units. Null when the rate is unknown, which is not the same as zero: '
  'unrated hours are reported as unrated rather than valued at nothing.';

-- Duration is stored as minutes against a start, not as a start/end pair. A pair invites two ways to say
-- the same thing and a timezone argument at every edit; minutes has one meaning everywhere. The end time a
-- screen shows is started_at + minutes, derived where it is displayed.
create table public.job_time_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  -- Which visit the time was spent on, when the person recording it knows. Job-level time is normal too:
  -- travel, prep and office work belong to the job without belonging to one visit.
  visit_id uuid,
  -- Whose hours these are. Not the same as who typed them in: a manager records time for a crew member,
  -- and the cost belongs to the crew member.
  user_id uuid not null,
  started_at timestamptz not null,
  -- A day is the ceiling. Anything longer is a mistake, and a mistake that silently multiplies a rate.
  minutes integer not null check (minutes between 1 and 1440),
  notes text check (notes is null or char_length(notes) <= 2000),
  -- The rate copied at the moment of recording. Null means this person had no rate on file then, and the
  -- entry stays honestly unpriced rather than being valued at zero.
  cost_per_hour_minor bigint check (cost_per_hour_minor is null or cost_per_hour_minor between 0 and 100000000),
  cost_total_minor bigint
    generated always as (public.labor_cost_total_minor(minutes, cost_per_hour_minor)) stored,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_time_entries_organization_id_unique unique (organization_id, id),
  constraint job_time_entries_job_organization_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_time_entries_visit_organization_fk foreign key (organization_id, visit_id)
    references public.job_visits(organization_id, id) on delete set null (visit_id),
  -- Cascade, matching job_visit_assignments, because restrict here would be a trap: purging an organization
  -- cascades into members and into this table at once, and Postgres does not promise which goes first.
  -- Offboarding does not reach it anyway -- removing a teammate sets status = 'removed' and keeps the row,
  -- so their recorded hours and the job's cost history survive the person leaving.
  constraint job_time_entries_member_fk foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade
);

comment on table public.job_time_entries is
  'Hours worked on a job, and what those hours cost. The rate is copied on at recording time, so changing '
  'someone''s rate never re-prices finished work.';

alter table public.job_time_entries enable row level security;

-- The own/team split follows the shipped conversations precedent (view_assigned vs view_team) rather than
-- inventing scoped permissions: a crew member reaches their own hours, a manager reaches everyone's. Both
-- still need to be able to open the job the time is on.
create policy "permitted members can view time entries"
on public.job_time_entries for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
  and (
    private.has_permission(organization_id, 'time.track_team')
    or (
      user_id = (select auth.uid())
      and private.has_permission(organization_id, 'time.track_own')
    )
  )
);

revoke all on public.job_time_entries from anon, authenticated;

-- Hours are visible to the person who worked them. What the hour cost is not: a crew member reading their
-- own entry sees duration and notes, never their loaded rate or the money it produced.
grant select (
  id, organization_id, job_id, visit_id, user_id, started_at, minutes, notes,
  created_by, created_at, updated_at
) on public.job_time_entries to authenticated;

create index job_time_entries_job_started_idx
  on public.job_time_entries(organization_id, job_id, started_at desc, id desc);

-- The rolling 30-day window a recurring job is costed over, and "my hours this week", read through here.
create index job_time_entries_member_started_idx
  on public.job_time_entries(organization_id, user_id, started_at desc, id desc);

create index job_time_entries_visit_idx
  on public.job_time_entries(organization_id, visit_id)
  where visit_id is not null;

-- 3. Recorded expenses -------------------------------------------------------------------------------------

-- Jobber's expense record, matched field for field from the captured screens: what it was, the accounting
-- code, a description, the date, the total, and who to pay back. The receipt is not a column -- it is an
-- attachment, using the shipped R2 subsystem, which is why documents and PDFs come free.
create table public.job_expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  name text not null check (char_length(trim(name)) between 2 and 160),
  accounting_code text check (accounting_code is null or char_length(trim(accounting_code)) between 1 and 64),
  description text check (description is null or char_length(description) <= 2000),
  expense_date date not null,
  total_minor bigint not null check (total_minor between 0 and 1000000000000),
  -- Null means "not reimbursable" -- the business paid it directly. A named member means we owe them.
  reimburse_to_user_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_expenses_organization_id_unique unique (organization_id, id),
  constraint job_expenses_job_organization_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  -- The expense outlives the person we owed: clearing the name keeps the cost on the job, where a delete
  -- would quietly make the job look cheaper than it was.
  constraint job_expenses_reimburse_member_fk foreign key (organization_id, reimburse_to_user_id)
    references public.organization_members(organization_id, user_id)
    on delete set null (reimburse_to_user_id)
);

comment on table public.job_expenses is
  'A cost incurred on a job that is not labor and not a line item -- materials, dump fees, subcontractors. '
  'Receipts hang off this row as attachments with entity_type ''job_expense'', so a receipt can be a photo '
  'or a PDF without this table knowing anything about files.';

alter table public.job_expenses enable row level security;

-- Same own/team shape as time. A crew member who buys materials can see what they submitted; reading
-- everyone's expenses is a manager's job.
create policy "permitted members can view expenses"
on public.job_expenses for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
  and (
    private.has_permission(organization_id, 'expenses.manage_team')
    or (
      created_by = (select auth.uid())
      and private.has_permission(organization_id, 'expenses.record')
    )
  )
);

revoke all on public.job_expenses from anon, authenticated;

-- total_minor is missing from this grant on purpose, the same as every other money column in the app.
grant select (
  id, organization_id, job_id, name, accounting_code, description, expense_date,
  reimburse_to_user_id, created_by, created_at, updated_at
) on public.job_expenses to authenticated;

create index job_expenses_job_date_idx
  on public.job_expenses(organization_id, job_id, expense_date desc, id desc);

create index job_expenses_created_by_idx
  on public.job_expenses(organization_id, created_by, expense_date desc);

create index job_expenses_reimburse_idx
  on public.job_expenses(organization_id, reimburse_to_user_id, expense_date desc)
  where reimburse_to_user_id is not null;

-- 4. The correction trail ---------------------------------------------------------------------------------

-- Closing a job locks the crew out of its costs; it does not close the books. Late receipts and honest
-- corrections are normal, so an authorized manager can still fix an entry after the job closes -- and every
-- such change lands here, with its before and after, permanently.
--
-- Its own table rather than job_events because these rows carry money. job_events feeds an activity view
-- with no notion of a cost-gated row; putting corrected amounts in it would leak cost into a general feed.
create table public.job_costing_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  event_type text not null check (char_length(trim(event_type)) between 2 and 64),
  -- Which record changed. Kept as a plain id, not a foreign key: the trail has to outlive the row it
  -- describes, or deleting an entry would delete the evidence that it was deleted.
  subject_kind text not null check (subject_kind in ('time_entry', 'expense')),
  subject_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  -- True once the job was already closed when this happened. This is what makes an after-the-fact
  -- correction visible as one instead of blending into ordinary activity.
  after_close boolean not null default false,
  reason text check (reason is null or char_length(reason) <= 2000),
  prior_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now(),
  constraint job_costing_events_job_organization_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade
);

comment on table public.job_costing_events is
  'Append-only history of every labor and expense change on a job, including corrections made after the '
  'job closed. Carries money in prior_values/new_values, so it is never granted to authenticated and is '
  'read only through a jobs.view_cost reader.';

alter table public.job_costing_events enable row level security;

-- No policy and no grant: nothing reads this table directly. The reader that serves it to a screen arrives
-- with the commands in 14b/14c and checks jobs.view_cost itself.
revoke all on public.job_costing_events from anon, authenticated;

create index job_costing_events_job_created_idx
  on public.job_costing_events(organization_id, job_id, created_at desc, id desc);

create index job_costing_events_subject_idx
  on public.job_costing_events(organization_id, subject_kind, subject_id, created_at desc);

-- Append-only in the same way invoice_events is: refused at the table, not merely ungranted.
create or replace function private.job_costing_events_are_append_only()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Job costing history cannot be changed or removed.' using errcode = 'insufficient_privilege';
end;
$$;

revoke all on function private.job_costing_events_are_append_only() from public;
revoke execute on function private.job_costing_events_are_append_only() from anon, authenticated;

create trigger job_costing_events_are_append_only
before update or delete on public.job_costing_events
for each row execute function private.job_costing_events_are_append_only();

-- 5. A receipt is a real attachment ------------------------------------------------------------------------

-- Widening the polymorphic seam is three edits, not one -- the entity_type lists, the visibility pair, and
-- the existence check -- a lesson already paid for in 20260820110125. Only attachments is widened here: a
-- receipt is a file on an expense, and an expense is not a place for notes, tags or an activity feed.
alter table public.attachments drop constraint attachments_entity_type_check;
alter table public.attachments add constraint attachments_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote', 'job_expense')) not valid;
alter table public.attachments validate constraint attachments_entity_type_check;

create or replace function private.can_view_job_expense(
  target_organization_id uuid,
  target_expense_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.has_permission(target_organization_id, 'jobs.view')
    and exists (
      select 1
      from public.job_expenses
      where id = target_expense_id
        and organization_id = target_organization_id
        and (
          private.has_permission(target_organization_id, 'expenses.manage_team')
          or (
            created_by = (select auth.uid())
            and private.has_permission(target_organization_id, 'expenses.record')
          )
        )
    );
$$;

revoke all on function private.can_view_job_expense(uuid, uuid) from public;
grant execute on function private.can_view_job_expense(uuid, uuid) to authenticated;

create or replace function private.can_view_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    case target_entity_type
      when 'client' then private.can_view_client(target_organization_id, target_entity_id)
      when 'property' then private.can_view_property(target_organization_id, target_entity_id)
      when 'request' then private.can_view_request(target_organization_id, target_entity_id)
      when 'quote' then private.can_view_quote(target_organization_id, target_entity_id)
      when 'job_expense' then private.can_view_job_expense(target_organization_id, target_entity_id)
      else false
    end,
    false
  );
$$;

create or replace function private.can_manage_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.can_view_linked_entity(target_organization_id, target_entity_type, target_entity_id)
    and case target_entity_type
      when 'client' then private.has_permission(target_organization_id, 'customers.edit')
      when 'property' then private.has_permission(target_organization_id, 'property.manage')
      when 'request' then true
      when 'quote' then private.has_permission(target_organization_id, 'quotes.edit')
      -- Reaching the expense at all already proved this is the submitter or a manager; attaching the
      -- receipt to it needs nothing further.
      when 'job_expense' then true
      else false
    end;
$$;

create or replace function private.linked_entity_exists(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case target_entity_type
    when 'client' then exists (
      select 1 from public.clients
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'property' then exists (
      select 1 from public.properties
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'request' then exists (
      select 1 from public.requests
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'quote' then exists (
      select 1 from public.quotes
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'job_expense' then exists (
      select 1 from public.job_expenses
      where id = target_entity_id and organization_id = target_organization_id
    )
    else false
  end;
$$;

-- 6. Permissions ---------------------------------------------------------------------------------------------

-- Four keys, because recording work and seeing what it cost are different questions. jobs.view_cost already
-- exists and keeps its meaning: rates, costs, profit and margin. These four only decide who may write.
--
-- The own/team pair mirrors conversations.view_assigned / conversations.view_team, the shape this codebase
-- already uses for "mine" versus "everyone's". The alternative -- the dormant access_scope machinery from
-- 20260822055549 -- would make this the first domain to switch it on, for no behavior the pair cannot
-- express.
insert into public.permissions (key, description)
values
  ('time.track_own', 'Record and change their own hours on a job'),
  ('time.track_team', 'Record and change anyone''s hours on a job'),
  ('expenses.record', 'Record an expense on a job and change their own'),
  ('expenses.manage_team', 'Change or remove anyone''s job expenses')
on conflict (key) do update set description = excluded.description;

-- Field is deliberately here. A crew member logging their own hours and the materials they bought is the
-- whole point of the own/team split -- and none of it lets them see a rate, a cost or a margin, which stays
-- behind jobs.view_cost.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'time.track_own'),
  ('owner', 'time.track_team'),
  ('owner', 'expenses.record'),
  ('owner', 'expenses.manage_team'),

  ('admin', 'time.track_own'),
  ('admin', 'time.track_team'),
  ('admin', 'expenses.record'),
  ('admin', 'expenses.manage_team'),

  ('office', 'time.track_own'),
  ('office', 'time.track_team'),
  ('office', 'expenses.record'),
  ('office', 'expenses.manage_team'),

  ('finance', 'time.track_own'),
  ('finance', 'time.track_team'),
  ('finance', 'expenses.record'),
  ('finance', 'expenses.manage_team'),

  ('field', 'time.track_own'),
  ('field', 'expenses.record')
on conflict (role, permission_key) do nothing;
