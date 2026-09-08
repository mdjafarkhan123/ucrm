-- Jobs, Part 15c-1: reusable checklists, and one set of answers per visit.
--
-- Jobber's shape, verified against help.getjobber.com/hc/en-us/articles/115009740048-Checklists on
-- 2026-09-08, is three layers and this file is those three layers:
--
--   1. A template lives in Settings and is reused. Question types are short answer, long answer, dropdown,
--      checkbox, numerical answer, date picker -- plus image upload and signature, which are deliberately
--      absent here. Signature is Part 15d's whole subject and image upload duplicates the visit photos
--      15a-1 already shipped; building either one twice is the overengineering the plan rejected.
--   2. A template is attached to a job, and "a job-attached checklist is available on visits".
--   3. Each visit carries its own answers. Filling Tuesday's visit does not touch Friday's.
--
-- Two rules from that page decide the storage, and neither is ours to invent:
--
--   "When a checklist is added to an existing job, past visits aren't updated." A visit completed before
--   the checklist arrived must not suddenly grow outstanding work. job_checklists.attached_at against
--   job_visits.completed_at answers that with no new column and no backfill.
--
--   Editing a template must not rewrite answers a crew already gave. Jobber does not document what happens
--   there, so this does not guess at their behavior -- it takes the pattern this codebase already uses when
--   a job's priced lines are copied onto a visit (20260908160000): attaching a checklist SNAPSHOTS its
--   questions onto the job. A later template edit changes the next attachment and nothing that exists. That
--   is what "versioned" means here; a formal version table would be a second mechanism for the same
--   guarantee.
--
-- Completion is NOT gated in this file, on purpose. Jobber: "If a visit is marked complete while a
-- checklist still has required fields left blank, the team member will get a prompt to go back and finish
-- it. Tap the Checklist to navigate back to the form, or tap Complete visit to complete the visit and leave
-- the checklist unfinished." A warning is a screen, not a constraint, so complete_job_visit is untouched and
-- public.visit_checklist_rows below reports outstanding_required for the prompt to read.

-- 1. Authoring a template is its own permission ------------------------------------------------------------

-- Jobber does not document who may author a checklist, so this copies the shape every other reusable
-- library in Settings already has here -- settings.price_book.manage, settings.taxes.manage -- down to the
-- key's name and its owner-and-administrator grant. Inventing a different scope model for this one page
-- would be the guesswork rule 2 forbids.
--
-- Reading a template needs no key at all: the attach picker on a job must list them, the crew has to see
-- the questions on their visit, and a blank form definition is not sensitive. Only writing one is gated.
insert into public.permissions (key, description)
values (
  'settings.checklists.manage',
  'Build, edit and archive the reusable checklists in Settings'
)
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'settings.checklists.manage'),
  ('admin', 'settings.checklists.manage')
on conflict (role, permission_key) do nothing;

-- 2. The question shape, in one place --------------------------------------------------------------------

-- Both the template item and its frozen copy on a job carry the same six columns and the same rules. The
-- rules live in these two functions so the template and the snapshot cannot drift into disagreeing about
-- what a valid dropdown is.
create or replace function private.checklist_item_shape_is_valid(
  item_type text,
  options text[]
)
returns boolean
language sql
immutable
-- Pinned rather than left to the caller: a check constraint calls this, and a constraint must not resolve
-- its operators through whatever search_path the writing session happens to carry.
set search_path = pg_catalog
as $$
  -- A dropdown without choices is unanswerable; choices on anything else are a mistake that would silently
  -- never render.
  select case
    when item_type = 'dropdown' then options is not null and cardinality(options) between 1 and 50
    else options is null
  end;
$$;

comment on function private.checklist_item_shape_is_valid(text, text[]) is
  'Whether a checklist question is internally consistent: only a dropdown carries choices, and a dropdown '
  'without choices cannot be answered.';

-- What counts as answered. A required question that is blank is the outstanding work the completion prompt
-- warns about, so "answered" has to mean the same thing everywhere it is counted.
create or replace function private.checklist_answer_is_complete(
  item_type text,
  value jsonb
)
returns boolean
language sql
immutable
-- Pinned rather than left to the caller: a check constraint calls this, and a constraint must not resolve
-- its operators through whatever search_path the writing session happens to carry.
set search_path = pg_catalog
as $$
  select case
    -- An unticked box is not an answer to "did you do it". Jobber's required checkbox has to be checked.
    when value is null then false
    when item_type = 'checkbox' then value = to_jsonb(true)
    when jsonb_typeof(value) = 'string' then length(trim(value #>> '{}')) > 0
    else jsonb_typeof(value) <> 'null'
  end;
$$;

comment on function private.checklist_answer_is_complete(text, jsonb) is
  'Whether one answer counts as given. A blank string and an unticked required checkbox are both blank; '
  'every other present value counts. The single definition behind the outstanding-work warning.';

-- Whether a value is a legal answer to its question at all. Enforced in the write command rather than by a
-- constraint, because the type it must match lives on a different table.
create or replace function private.checklist_value_matches_type(
  item_type text,
  options text[],
  value jsonb
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when value is null or jsonb_typeof(value) = 'null' then true
    when item_type = 'checkbox' then jsonb_typeof(value) = 'boolean'
    when item_type = 'number' then jsonb_typeof(value) = 'number'
    when item_type = 'date' then
      jsonb_typeof(value) = 'string'
      and (value #>> '{}') ~ '^\d{4}-\d{2}-\d{2}$'
    when item_type = 'dropdown' then
      jsonb_typeof(value) = 'string'
      and (value #>> '{}') = any (coalesce(options, array[]::text[]))
    when item_type in ('short_text', 'long_text') then
      jsonb_typeof(value) = 'string'
      and length(value #>> '{}') <= case item_type when 'short_text' then 500 else 5000 end
    else false
  end;
$$;

comment on function private.checklist_value_matches_type(text, text[], jsonb) is
  'Whether an answer is legal for its question type -- a boolean for a checkbox, a listed choice for a '
  'dropdown, an ISO date for a date. Lives in a function, not a check constraint, because the question type '
  'sits on a different table from the answer.';

-- 3. The reusable template -------------------------------------------------------------------------------

create table public.checklist_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  -- Archived, never deleted: jobs already carry their own snapshot, but a template that vanishes from the
  -- library also vanishes from every "where did this come from" answer.
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checklist_templates_organization_id_unique unique (organization_id, id)
);

comment on table public.checklist_templates is
  'A reusable checklist built once in Settings and attached to many jobs. Editing one never changes a job '
  'that already carries it -- attaching takes a snapshot.';

create index checklist_templates_organization_idx
  on public.checklist_templates (organization_id, archived_at, name);

create table public.checklist_template_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  template_id uuid not null,
  position integer not null check (position >= 0),
  label text not null check (char_length(trim(label)) between 1 and 200),
  -- Jobber's list minus image upload and signature. Adding one later is a check-constraint change here and
  -- a renderer in the dialog; nothing else in this file assumes the set is closed at six.
  item_type text not null check (
    item_type in ('checkbox', 'short_text', 'long_text', 'number', 'dropdown', 'date')
  ),
  required boolean not null default false,
  options text[],
  constraint checklist_template_items_organization_id_unique unique (organization_id, id),
  constraint checklist_template_items_template_fk foreign key (organization_id, template_id)
    references public.checklist_templates(organization_id, id) on delete cascade,
  constraint checklist_template_items_shape check (
    private.checklist_item_shape_is_valid(item_type, options)
  )
);

comment on table public.checklist_template_items is
  'The questions on a reusable checklist, in position order.';

create index checklist_template_items_template_idx
  on public.checklist_template_items (organization_id, template_id, position);

-- 4. The snapshot a job carries ---------------------------------------------------------------------------

create table public.job_checklists (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  -- Where it came from, for display only. Null once the template is deleted; the questions below survive it
  -- because they are this job's own copy.
  source_template_id uuid references public.checklist_templates(id) on delete set null,
  name text not null check (char_length(trim(name)) between 1 and 120),
  -- The line Jobber's "past visits aren't updated" is drawn against: a visit completed before this stamp
  -- never shows this checklist.
  attached_at timestamptz not null default now(),
  attached_by uuid references auth.users(id) on delete set null,
  constraint job_checklists_organization_id_unique unique (organization_id, id),
  constraint job_checklists_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade
);

comment on table public.job_checklists is
  'One checklist attached to one job, frozen at the moment it was attached. Its questions are this job''s '
  'own copy, so editing the template it came from cannot rewrite answers a crew already gave.';

create index job_checklists_job_idx on public.job_checklists (organization_id, job_id, attached_at);
create index job_checklists_source_template_idx
  on public.job_checklists (source_template_id) where source_template_id is not null;

create table public.job_checklist_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Denormalized from the checklist above so the read policy can test assignment with one index probe
  -- instead of a correlated join, the shape 15a-4 measured and every job-family table now follows.
  job_id uuid not null,
  job_checklist_id uuid not null,
  position integer not null check (position >= 0),
  label text not null check (char_length(trim(label)) between 1 and 200),
  item_type text not null check (
    item_type in ('checkbox', 'short_text', 'long_text', 'number', 'dropdown', 'date')
  ),
  required boolean not null default false,
  options text[],
  constraint job_checklist_items_organization_id_unique unique (organization_id, id),
  constraint job_checklist_items_checklist_fk foreign key (organization_id, job_checklist_id)
    references public.job_checklists(organization_id, id) on delete cascade,
  constraint job_checklist_items_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_checklist_items_shape check (
    private.checklist_item_shape_is_valid(item_type, options)
  )
);

comment on table public.job_checklist_items is
  'The frozen questions of a job''s checklist. One copy per job, not per visit: a recurring job with two '
  'hundred visits stores its ten questions once and only the answers multiply.';

create index job_checklist_items_checklist_idx
  on public.job_checklist_items (organization_id, job_checklist_id, position);

-- 5. The answers, one set per visit ------------------------------------------------------------------------

create table public.visit_checklist_answers (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  visit_id uuid not null,
  item_id uuid not null,
  -- The typed answer: true, 12.5, "2026-09-08", "Left side gate". Cleared answers are deleted rather than
  -- stored as null, so a row present is an answer given and the outstanding count is a plain count.
  value jsonb not null,
  answered_by uuid references auth.users(id) on delete set null,
  answered_at timestamptz not null default now(),
  primary key (visit_id, item_id),
  constraint visit_checklist_answers_visit_fk foreign key (organization_id, visit_id)
    references public.job_visits(organization_id, id) on delete cascade,
  constraint visit_checklist_answers_item_fk foreign key (organization_id, item_id)
    references public.job_checklist_items(organization_id, id) on delete cascade,
  constraint visit_checklist_answers_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade
);

comment on table public.visit_checklist_answers is
  'One visit''s answers to its job''s checklist questions. The whole point of the per-visit split: the same '
  'question is answered again, independently, on every visit.';

-- The foreign key's own index, and the reverse lookup when an item is removed.
create index visit_checklist_answers_item_idx
  on public.visit_checklist_answers (organization_id, item_id);
create index visit_checklist_answers_job_idx
  on public.visit_checklist_answers (organization_id, job_id);

-- 6. Who sees what ------------------------------------------------------------------------------------------

alter table public.checklist_templates enable row level security;
alter table public.checklist_template_items enable row level security;
alter table public.job_checklists enable row level security;
alter table public.job_checklist_items enable row level security;
alter table public.visit_checklist_answers enable row level security;

-- A template is a blank form. Anyone in the business may read one -- the crew has to see the questions on
-- their visit, and whoever edits a job has to pick one from the list. Writing is settings.checklists.manage, and all
-- writing goes through the commands below, so no write policy is granted here.
create policy "members can view checklist templates"
on public.checklist_templates for select to authenticated
using (organization_id = (select private.current_organization()));

create policy "members can view checklist template items"
on public.checklist_template_items for select to authenticated
using (organization_id = (select private.current_organization()));

-- A job's checklist is part of the job, so it is visible exactly when the job is -- including the assigned
-- narrowing a Field member carries. Spelled out rather than calling can_view_job, so the scope half stays
-- hoistable to one evaluation per statement (15a-4).
create policy "permitted members can view job checklists"
on public.job_checklists for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

create policy "permitted members can view job checklist items"
on public.job_checklist_items for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

create policy "permitted members can view visit checklist answers"
on public.visit_checklist_answers for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

-- 7. Building and changing a template ------------------------------------------------------------------------

-- Both write commands rebuild the question list wholesale from one array. That is safe here in a way it
-- would not be for answers: a job already holds its own snapshot, so replacing a template's questions loses
-- nothing that anyone has filled in.
create or replace function private.replace_checklist_template_items(
  target_organization_id uuid,
  target_template_id uuid,
  items jsonb
)
returns integer
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  written integer;
begin
  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) = 0 then
    raise exception 'A checklist needs at least one question.' using errcode = 'P0400';
  end if;
  if jsonb_array_length(items) > 100 then
    raise exception 'A checklist can hold up to 100 questions.' using errcode = 'P0400';
  end if;

  delete from public.checklist_template_items
  where organization_id = target_organization_id and template_id = target_template_id;

  insert into public.checklist_template_items (
    organization_id, template_id, position, label, item_type, required, options
  )
  select
    target_organization_id,
    target_template_id,
    (ordinality - 1)::integer,
    trim(item.value ->> 'label'),
    item.value ->> 'item_type',
    coalesce((item.value ->> 'required')::boolean, false),
    case
      when item.value ->> 'item_type' = 'dropdown' then (
        select array_agg(trim(choice.value #>> '{}') order by choice.ordinality)
        from jsonb_array_elements(item.value -> 'options') with ordinality as choice(value, ordinality)
        where length(trim(choice.value #>> '{}')) > 0
      )
      else null
    end
  from jsonb_array_elements(items) with ordinality as item(value, ordinality);

  get diagnostics written = row_count;
  return written;
end;
$$;

comment on function private.replace_checklist_template_items(uuid, uuid, jsonb) is
  'Rewrites a template''s questions from one array, in array order. Safe to replace wholesale because a job '
  'that uses this template already holds its own frozen copy.';

revoke all on function private.replace_checklist_template_items(uuid, uuid, jsonb) from public;
revoke execute on function private.replace_checklist_template_items(uuid, uuid, jsonb) from anon, authenticated;

create or replace function public.create_checklist_template(
  target_organization_id uuid,
  name text,
  items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  new_template public.checklist_templates;
begin
  if caller is null then
    raise exception 'You must be signed in to build a checklist.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'settings.checklists.manage') then
    raise exception 'You do not have access to build checklists.' using errcode = 'insufficient_privilege';
  end if;

  insert into public.checklist_templates (organization_id, name, created_by)
  values (target_organization_id, trim(create_checklist_template.name), caller)
  returning * into new_template;

  perform private.replace_checklist_template_items(target_organization_id, new_template.id, items);

  return jsonb_build_object('id', new_template.id);
end;
$$;

comment on function public.create_checklist_template(uuid, text, jsonb) is
  'Builds a reusable checklist. Needs settings.checklists.manage.';

revoke all on function public.create_checklist_template(uuid, text, jsonb) from public;
revoke execute on function public.create_checklist_template(uuid, text, jsonb) from anon;
grant execute on function public.create_checklist_template(uuid, text, jsonb) to authenticated;

create or replace function public.update_checklist_template(
  target_organization_id uuid,
  target_template_id uuid,
  name text,
  items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  existing public.checklist_templates;
  jobs_using integer;
begin
  if caller is null then
    raise exception 'You must be signed in to change a checklist.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'settings.checklists.manage') then
    raise exception 'You do not have access to change checklists.' using errcode = 'insufficient_privilege';
  end if;

  select template.* into existing
  from public.checklist_templates as template
  where template.organization_id = target_organization_id and template.id = target_template_id
  for update;
  if not found then
    raise exception 'That checklist could not be found.' using errcode = 'P0404';
  end if;

  update public.checklist_templates
  set name = trim(update_checklist_template.name),
      updated_at = now()
  where organization_id = target_organization_id and id = target_template_id;

  perform private.replace_checklist_template_items(target_organization_id, target_template_id, items);

  -- Not a warning the database can raise, but the number the screen needs to say "this does not change the
  -- 12 jobs already using it".
  select count(*) into jobs_using
  from public.job_checklists
  where organization_id = target_organization_id and source_template_id = target_template_id;

  return jsonb_build_object('id', target_template_id, 'jobs_already_using', jobs_using);
end;
$$;

comment on function public.update_checklist_template(uuid, uuid, text, jsonb) is
  'Renames a checklist and replaces its questions. Jobs that already carry it keep the questions they were '
  'given; the count of those jobs comes back so the screen can say so.';

revoke all on function public.update_checklist_template(uuid, uuid, text, jsonb) from public;
revoke execute on function public.update_checklist_template(uuid, uuid, text, jsonb) from anon;
grant execute on function public.update_checklist_template(uuid, uuid, text, jsonb) to authenticated;

create or replace function public.set_checklist_template_archived(
  target_organization_id uuid,
  target_template_id uuid,
  archived boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  updated public.checklist_templates;
begin
  if caller is null then
    raise exception 'You must be signed in to change a checklist.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'settings.checklists.manage') then
    raise exception 'You do not have access to change checklists.' using errcode = 'insufficient_privilege';
  end if;

  update public.checklist_templates as template
  set archived_at = case when archived then now() else null end,
      updated_at = now()
  where template.organization_id = target_organization_id and template.id = target_template_id
  returning * into updated;
  if not found then
    raise exception 'That checklist could not be found.' using errcode = 'P0404';
  end if;

  return jsonb_build_object('id', updated.id, 'archived', updated.archived_at is not null);
end;
$$;

comment on function public.set_checklist_template_archived(uuid, uuid, boolean) is
  'Archives a checklist out of the library, or restores it. Never deletes: the jobs that used it keep '
  'pointing at where their questions came from.';

revoke all on function public.set_checklist_template_archived(uuid, uuid, boolean) from public;
revoke execute on function public.set_checklist_template_archived(uuid, uuid, boolean) from anon;
grant execute on function public.set_checklist_template_archived(uuid, uuid, boolean) to authenticated;

-- 8. Attaching to a job, and taking it off -------------------------------------------------------------------

-- Attaching changes what the job's crew is asked to record, which is a change to the job -- so it is
-- jobs.edit, matching Jobber attaching a checklist "while creating a job or editing scheduled visits".
create or replace function public.attach_job_checklist(
  target_organization_id uuid,
  target_job_id uuid,
  target_template_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  source_template public.checklist_templates;
  new_checklist public.job_checklists;
  copied integer;
begin
  if caller is null then
    raise exception 'You must be signed in to attach a checklist.' using errcode = 'insufficient_privilege';
  end if;
  if not private.can_view_job(target_organization_id, target_job_id)
    or not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to change this job.' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.jobs
    where organization_id = target_organization_id and id = target_job_id and status = 'active'
  ) then
    raise exception 'A closed job cannot take a new checklist.' using errcode = 'P0410';
  end if;

  select library.* into source_template
  from public.checklist_templates as library
  where library.organization_id = target_organization_id and library.id = target_template_id;
  if not found then
    raise exception 'That checklist could not be found.' using errcode = 'P0404';
  end if;
  if source_template.archived_at is not null then
    raise exception 'That checklist is archived.' using errcode = 'P0400';
  end if;

  -- The same checklist twice on one job is two identical forms on every visit, which is never what anyone
  -- meant. Refused with a sentence rather than a unique constraint, because a job may legitimately carry
  -- two DIFFERENT checklists.
  if exists (
    select 1 from public.job_checklists
    where organization_id = target_organization_id
      and job_id = target_job_id
      and source_template_id = target_template_id
  ) then
    raise exception 'That checklist is already on this job.' using errcode = 'P0409';
  end if;

  insert into public.job_checklists (organization_id, job_id, source_template_id, name, attached_by)
  values (target_organization_id, target_job_id, target_template_id, source_template.name, caller)
  returning * into new_checklist;

  -- The snapshot. Everything after this point is the job's own copy.
  insert into public.job_checklist_items (
    organization_id, job_id, job_checklist_id, position, label, item_type, required, options
  )
  select
    target_organization_id, target_job_id, new_checklist.id,
    item.position, item.label, item.item_type, item.required, item.options
  from public.checklist_template_items as item
  where item.organization_id = target_organization_id and item.template_id = target_template_id;

  get diagnostics copied = row_count;
  if copied = 0 then
    raise exception 'That checklist has no questions on it yet.' using errcode = 'P0400';
  end if;

  return jsonb_build_object('id', new_checklist.id, 'question_count', copied);
end;
$$;

comment on function public.attach_job_checklist(uuid, uuid, uuid) is
  'Copies a template''s questions onto a job. Needs jobs.edit. The copy is what every visit answers, so a '
  'later template edit never reaches this job. Visits already completed do not show it.';

revoke all on function public.attach_job_checklist(uuid, uuid, uuid) from public;
revoke execute on function public.attach_job_checklist(uuid, uuid, uuid) from anon;
grant execute on function public.attach_job_checklist(uuid, uuid, uuid) to authenticated;

create or replace function public.remove_job_checklist(
  target_organization_id uuid,
  target_job_id uuid,
  target_checklist_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  answers_lost integer;
begin
  if caller is null then
    raise exception 'You must be signed in to remove a checklist.' using errcode = 'insufficient_privilege';
  end if;
  if not private.can_view_job(target_organization_id, target_job_id)
    or not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to change this job.' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into answers_lost
  from public.visit_checklist_answers as answer
  join public.job_checklist_items as item
    on item.organization_id = answer.organization_id and item.id = answer.item_id
  where answer.organization_id = target_organization_id
    and item.job_checklist_id = target_checklist_id;

  delete from public.job_checklists
  where organization_id = target_organization_id
    and job_id = target_job_id
    and id = target_checklist_id;
  if not found then
    raise exception 'That checklist could not be found on this job.' using errcode = 'P0404';
  end if;

  -- The count is returned, not protected: the screen asks before calling this, and refusing here would
  -- leave a job stuck with a checklist attached by mistake. The cascade takes the answers with it.
  return jsonb_build_object('id', target_checklist_id, 'answers_removed', answers_lost);
end;
$$;

comment on function public.remove_job_checklist(uuid, uuid, uuid) is
  'Takes a checklist off a job, with the answers every visit gave it. Returns how many answers went, so the '
  'screen can warn before asking for this.';

revoke all on function public.remove_job_checklist(uuid, uuid, uuid) from public;
revoke execute on function public.remove_job_checklist(uuid, uuid, uuid) from anon;
grant execute on function public.remove_job_checklist(uuid, uuid, uuid) to authenticated;

-- 9. Answering, one visit at a time ---------------------------------------------------------------------------

-- Answering is field_records.record, the crew key from 15a-1 -- recording what you did on your own job is
-- exactly what that key is for, and Jobber's base Field crew preset fills checklists while holding no jobs
-- edit right at all. There is no own/team split on an answer: a checklist belongs to the visit, not to a
-- person, and two crew on the same visit are filling in one shared form.
create or replace function public.save_visit_checklist_answers(
  target_organization_id uuid,
  target_visit_id uuid,
  answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  visit public.job_visits;
  job_active boolean;
  entry record;
  item public.job_checklist_items;
  saved integer := 0;
  cleared integer := 0;
begin
  if caller is null then
    raise exception 'You must be signed in to fill in a checklist.' using errcode = 'insufficient_privilege';
  end if;
  if jsonb_typeof(answers) <> 'array' then
    raise exception 'Those answers could not be read.' using errcode = 'P0400';
  end if;

  select job_visit.* into visit
  from public.job_visits as job_visit
  where job_visit.organization_id = target_organization_id and job_visit.id = target_visit_id;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_view_visit(target_organization_id, target_visit_id) then
    raise exception 'You do not have access to this visit.' using errcode = 'insufficient_privilege';
  end if;

  select job.status = 'active' into job_active
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = visit.job_id;

  -- Closing a job locks the crew, not the books -- the rule Part 14 already applies to hours and expenses,
  -- read here for answers. A completed visit is NOT locked: Jobber's whole completion prompt exists so a
  -- person can complete now and finish the form afterwards.
  if job_active then
    if not private.member_has_permission(target_organization_id, caller, 'field_records.record')
      and not private.member_has_permission(target_organization_id, caller, 'field_records.manage_team') then
      raise exception 'You do not have access to fill in this checklist.' using errcode = 'insufficient_privilege';
    end if;
  elsif not private.member_has_permission(target_organization_id, caller, 'field_records.manage_team') then
    raise exception 'A closed job''s checklists can only be changed by someone who manages the team''s records.'
      using errcode = 'P0410';
  end if;

  for entry in
    select
      (element.value ->> 'item_id')::uuid as item_id,
      element.value -> 'value' as value
    from jsonb_array_elements(answers) as element(value)
  loop
    -- The item has to belong to this visit's job. Without this, an item id from another tenant's job would
    -- be refused only by the foreign key, and one from ANOTHER job in the same tenant would not be refused
    -- at all.
    select checklist_item.* into item
    from public.job_checklist_items as checklist_item
    where checklist_item.organization_id = target_organization_id
      and checklist_item.id = entry.item_id
      and checklist_item.job_id = visit.job_id;
    if not found then
      raise exception 'That checklist question is not on this visit''s job.' using errcode = 'P0404';
    end if;

    -- A visit completed before the checklist arrived never shows it, so it cannot be answered either.
    if exists (
      select 1
      from public.job_checklists as checklist
      where checklist.organization_id = target_organization_id
        and checklist.id = item.job_checklist_id
        and visit.completed_at is not null
        and visit.completed_at < checklist.attached_at
    ) then
      raise exception 'That checklist was added after this visit was completed.' using errcode = 'P0410';
    end if;

    -- Emptiness is tested BEFORE the type check, and the order is load-bearing: "" is not one of a
    -- dropdown's choices and is not an ISO date, so validating first would refuse the one gesture that
    -- takes an answer back. Clearing a question is always allowed; only a value that stays has to fit.
    if entry.value is null or jsonb_typeof(entry.value) = 'null'
      or (jsonb_typeof(entry.value) = 'string' and length(trim(entry.value #>> '{}')) = 0) then
      delete from public.visit_checklist_answers
      where visit_id = target_visit_id and item_id = item.id;
      cleared := cleared + 1;
    else
      if not private.checklist_value_matches_type(item.item_type, item.options, entry.value) then
        raise exception 'That answer does not fit the question "%".', item.label using errcode = 'P0400';
      end if;

      insert into public.visit_checklist_answers (
        organization_id, job_id, visit_id, item_id, value, answered_by, answered_at
      )
      values (
        target_organization_id, visit.job_id, target_visit_id, item.id, entry.value, caller, now()
      )
      on conflict (visit_id, item_id) do update
      set value = excluded.value,
          answered_by = excluded.answered_by,
          answered_at = excluded.answered_at;
      saved := saved + 1;
    end if;
  end loop;

  return jsonb_build_object('saved', saved, 'cleared', cleared);
end;
$$;

comment on function public.save_visit_checklist_answers(uuid, uuid, jsonb) is
  'Saves one visit''s checklist answers. Partial by design -- only the questions in the array are touched, '
  'and an empty answer clears that one question rather than the form. Needs field_records.record.';

revoke all on function public.save_visit_checklist_answers(uuid, uuid, jsonb) from public;
revoke execute on function public.save_visit_checklist_answers(uuid, uuid, jsonb) from anon;
grant execute on function public.save_visit_checklist_answers(uuid, uuid, jsonb) to authenticated;

-- 10. The reads --------------------------------------------------------------------------------------------

create or replace function public.checklist_templates_list(
  target_organization_id uuid,
  include_archived boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  templates jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to view checklists.' using errcode = 'insufficient_privilege';
  end if;
  if target_organization_id is distinct from private.current_organization() then
    raise exception 'You do not have access to these checklists.' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', template.id,
        'name', template.name,
        'archived', template.archived_at is not null,
        'updated_at', template.updated_at,
        'items', coalesce(questions.items, '[]'::jsonb)
      )
      order by template.name
    ),
    '[]'::jsonb
  )
  into templates
  from public.checklist_templates as template
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', item.id,
        'position', item.position,
        'label', item.label,
        'item_type', item.item_type,
        'required', item.required,
        'options', coalesce(to_jsonb(item.options), 'null'::jsonb)
      )
      order by item.position
    ) as items
    from public.checklist_template_items as item
    where item.organization_id = template.organization_id and item.template_id = template.id
  ) as questions on true
  where template.organization_id = target_organization_id
    and (include_archived or template.archived_at is null);

  return jsonb_build_object(
    'templates', templates,
    'can_manage', private.member_has_permission(target_organization_id, caller, 'settings.checklists.manage')
  );
end;
$$;

comment on function public.checklist_templates_list(uuid, boolean) is
  'The Settings library, with each checklist''s questions. Readable by any member -- the job attach picker '
  'and the crew both need it -- and reports whether this reader may change them.';

revoke all on function public.checklist_templates_list(uuid, boolean) from public;
revoke execute on function public.checklist_templates_list(uuid, boolean) from anon;
grant execute on function public.checklist_templates_list(uuid, boolean) to authenticated;

create or replace function public.job_checklists_list(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  checklists jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.can_view_job(target_organization_id, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', checklist.id,
        'name', checklist.name,
        'source_template_id', checklist.source_template_id,
        'attached_at', checklist.attached_at,
		'answers_count', coalesce(answer_counts.total, 0),
        'items', coalesce(questions.items, '[]'::jsonb)
      )
      order by checklist.attached_at
    ),
    '[]'::jsonb
  )
  into checklists
  from public.job_checklists as checklist
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', item.id,
        'position', item.position,
        'label', item.label,
        'item_type', item.item_type,
        'required', item.required,
        'options', coalesce(to_jsonb(item.options), 'null'::jsonb)
      )
      order by item.position
    ) as items
    from public.job_checklist_items as item
    where item.organization_id = checklist.organization_id and item.job_checklist_id = checklist.id
  ) as questions on true
  left join lateral (
    select count(*) as total
    from public.visit_checklist_answers as answer
    join public.job_checklist_items as item
      on item.organization_id = answer.organization_id and item.id = answer.item_id
    where answer.organization_id = checklist.organization_id
      and item.job_checklist_id = checklist.id
  ) as answer_counts on true
  where checklist.organization_id = target_organization_id
    and checklist.job_id = target_job_id;

  return jsonb_build_object(
    'checklists', checklists,
    'can_edit', private.member_has_permission(target_organization_id, caller, 'jobs.edit')
  );
end;
$$;

comment on function public.job_checklists_list(uuid, uuid) is
  'The checklists attached to one job, with their frozen questions and saved-answer count for the removal '
  'warning -- the job page''s card and the source of every visit''s form.';

revoke all on function public.job_checklists_list(uuid, uuid) from public;
revoke execute on function public.job_checklists_list(uuid, uuid) from anon;
grant execute on function public.job_checklists_list(uuid, uuid) to authenticated;

-- One visit's forms with that visit's own answers, and the outstanding-required count the completion prompt
-- reads. Bounded by one job's questions, not by the job's visits.
create or replace function public.visit_checklist_rows(
  target_organization_id uuid,
  target_visit_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  visit public.job_visits;
  checklists jsonb;
  outstanding integer;
begin
  if caller is null then
    raise exception 'You must be signed in to view this visit.' using errcode = 'insufficient_privilege';
  end if;

  select job_visit.* into visit
  from public.job_visits as job_visit
  where job_visit.organization_id = target_organization_id and job_visit.id = target_visit_id;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;
  if not private.can_view_visit(target_organization_id, target_visit_id) then
    raise exception 'You do not have access to this visit.' using errcode = 'insufficient_privilege';
  end if;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', checklist.id,
          'name', checklist.name,
          'items', coalesce(questions.items, '[]'::jsonb)
        )
        order by checklist.attached_at
      ),
      '[]'::jsonb
    ),
    coalesce(sum(questions.outstanding), 0)
  into checklists, outstanding
  from public.job_checklists as checklist
  left join lateral (
    select
      jsonb_agg(
        jsonb_build_object(
          'id', item.id,
          'position', item.position,
          'label', item.label,
          'item_type', item.item_type,
          'required', item.required,
          'options', coalesce(to_jsonb(item.options), 'null'::jsonb),
          'value', coalesce(answer.value, 'null'::jsonb),
          'answered_at', answer.answered_at,
          'answered_by', answer.answered_by
        )
        order by item.position
      ) as items,
      count(*) filter (
        where item.required
          and not private.checklist_answer_is_complete(item.item_type, answer.value)
      ) as outstanding
    from public.job_checklist_items as item
    left join public.visit_checklist_answers as answer
      on answer.visit_id = target_visit_id and answer.item_id = item.id
    where item.organization_id = checklist.organization_id and item.job_checklist_id = checklist.id
  ) as questions on true
  where checklist.organization_id = target_organization_id
    and checklist.job_id = visit.job_id
    -- Jobber: "when a checklist is added to an existing job, past visits aren't updated".
    and (visit.completed_at is null or visit.completed_at >= checklist.attached_at);

  return jsonb_build_object(
    'checklists', checklists,
    'outstanding_required', outstanding,
    'can_answer', private.member_has_permission(target_organization_id, caller, 'field_records.record')
      or private.member_has_permission(target_organization_id, caller, 'field_records.manage_team')
  );
end;
$$;

comment on function public.visit_checklist_rows(uuid, uuid) is
  'One visit''s checklists with its own answers, plus how many required questions are still blank. The '
  'completion prompt reads outstanding_required; it warns, it never blocks.';

revoke all on function public.visit_checklist_rows(uuid, uuid) from public;
revoke execute on function public.visit_checklist_rows(uuid, uuid) from anon;
grant execute on function public.visit_checklist_rows(uuid, uuid) to authenticated;
