-- Requests and Assessments, Part 1a.
-- An assessment is the optional on-site visit that scopes work before a quote exists.
-- Jobber's model: zero or one per request, schedulable, assignable to team members, completable.

create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  -- Both null means unscheduled. Jobber's schedule-state model never has one without the other.
  starts_at timestamptz,
  ends_at timestamptz,
  all_day boolean not null default false,
  instructions text,
  -- Null means not complete. One timestamp instead of Jobber's isComplete + completedAt, which can disagree.
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assessments_request_unique unique (request_id),
  constraint assessments_schedule_pairing check (
    (starts_at is null and ends_at is null) or (starts_at is not null and ends_at is not null)
  ),
  constraint assessments_schedule_order check (ends_at is null or ends_at > starts_at),
  constraint assessments_instructions_length check (instructions is null or char_length(instructions) <= 2000)
);

-- requests had no unique constraint on (organization_id, id), and the composite foreign key below needs
-- one. The primary key on id alone does not satisfy it.
alter table public.requests add constraint requests_organization_id_unique unique (organization_id, id);

-- Tenant-safe parentage: an assessment cannot point at a request in another organization.
alter table public.assessments add constraint assessments_request_organization_fk
  foreign key (organization_id, request_id)
  references public.requests(organization_id, id) on delete cascade;

-- Partial: the schedule views only ever ask for assessments that are still outstanding.
create index assessments_organization_starts_idx
  on public.assessments(organization_id, starts_at)
  where completed_at is null;

create index assessments_organization_updated_idx on public.assessments(organization_id, updated_at desc);
create index assessments_organization_request_idx on public.assessments(organization_id, request_id);

create table public.assessment_assignees (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (assessment_id, user_id),
  -- Assignees must belong to the same organization as the assessment. The composite foreign key makes
  -- that impossible to get wrong, rather than leaving it to application code.
  constraint assessment_assignees_member_fk foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade
);

create index assessment_assignees_organization_user_idx
  on public.assessment_assignees(organization_id, user_id);
create index assessment_assignees_assessment_idx on public.assessment_assignees(assessment_id);

create trigger assessments_set_updated_at
before update on public.assessments
for each row execute function public.set_updated_at();

-- upcoming / today / overdue are derived from the assessment's starts_at at read time, never stored.
-- Jafar's decision 2026-08-18: storing them would need a nightly per-timezone job and rows would be
-- wrong between runs. public.requests had zero rows when this ran.
alter table public.requests drop constraint requests_status_check;
alter table public.requests add constraint requests_status_check
  check (status in ('new', 'unscheduled', 'assessment_completed', 'completed', 'converted', 'archived'));

alter table public.assessments enable row level security;
alter table public.assessment_assignees enable row level security;

create policy "members can view assessments"
on public.assessments for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create assessments"
on public.assessments for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can update assessments"
on public.assessments for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

create policy "members can delete assessments"
on public.assessments for delete to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view assessment assignees"
on public.assessment_assignees for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create assessment assignees"
on public.assessment_assignees for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can delete assessment assignees"
on public.assessment_assignees for delete to authenticated
using (private.is_organization_member(organization_id));

grant select, insert, update, delete on public.assessments to authenticated;
grant select, insert, delete on public.assessment_assignees to authenticated;
