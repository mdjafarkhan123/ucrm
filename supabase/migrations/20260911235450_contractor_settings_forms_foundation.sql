-- Contractor Settings, Part 4A: Request and booking forms -- foundation.
--
-- Nothing about forms exists yet. This gives each business its own set of forms, each producing one of three
-- outcomes on submission (request / assessment / job -- Jobber's bookingType, collapsed to one field per the
-- approved Part 4 plan), with a Draft -> Published lifecycle copied from Quotes: a mutable draft is edited
-- freely, publishing freezes it forever, and revising after publish opens a brand new draft rather than
-- reopening the old one. Nothing public reads or writes any of this yet -- that is Part 4C/4D.

-- 1. Permission -------------------------------------------------------------------------------------------

insert into public.permissions (key, description, scope_model)
values ('settings.forms.manage', 'Create, edit, publish, and archive request and booking forms', 'none')
on conflict (key) do update set description = excluded.description, scope_model = excluded.scope_model;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'settings.forms.manage'),
  ('admin', 'settings.forms.manage')
on conflict (role, permission_key) do nothing;

-- 2. Form identity ------------------------------------------------------------------------------------------

create table public.forms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- What this form produces when someone eventually submits it. 'request' always lands as a Request for
  -- staff to review; 'assessment' and 'job' are the two instant-booking outcomes -- together they are the
  -- Business's one "booking form" default group below.
  outcome text not null check (outcome in ('request', 'assessment', 'job')),
  -- Internal label shown in the Settings list, e.g. "Kitchen Remodel Request" -- never shown to a customer.
  name text not null check (char_length(trim(name)) between 1 and 120),
  is_enabled boolean not null default true,
  is_default boolean not null default false,
  archived_at timestamptz,
  -- Added below once form_versions exists; composite FKs keep both pointers tenant-scoped.
  draft_version_id uuid,
  current_published_version_id uuid,
  revision integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint forms_organization_id_unique unique (organization_id, id)
);

comment on table public.forms is
  'Business-owned request/booking form identity. Written only by the commands below -- never edited through '
  'RLS directly. Nothing public reads this table; Part 4C adds that once a form can actually be shared.';

-- One default request form and one default booking form (assessment or job) per business, matching the
-- approved blueprint. An archived form can never be a default.
create unique index forms_default_request_idx on public.forms(organization_id)
  where is_default and archived_at is null and outcome = 'request';
create unique index forms_default_booking_idx on public.forms(organization_id)
  where is_default and archived_at is null and outcome in ('assessment', 'job');

create index forms_organization_active_idx on public.forms(organization_id, name)
  where archived_at is null;

revoke insert, update, delete, truncate, references, trigger
  on public.forms
  from anon, authenticated;

alter table public.forms enable row level security;

create policy "form managers can view forms"
on public.forms for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'settings.forms.manage')
);

-- 3. Versioned drafts and publications ---------------------------------------------------------------------

create table public.form_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  form_id uuid not null,
  version_number integer not null,
  status text not null default 'draft' check (status in ('draft', 'published')),
  -- What the customer actually sees. The question/section/photo builder is Part 4B; this is just enough
  -- content for the lifecycle itself to be real and testable.
  title text not null check (char_length(trim(title)) between 1 and 160),
  description text check (description is null or char_length(description) <= 2000),
  revision integer not null default 1,
  published_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint form_versions_organization_id_unique unique (organization_id, id),
  constraint form_versions_form_version_unique unique (form_id, version_number),
  constraint form_versions_form_organization_fk foreign key (organization_id, form_id)
    references public.forms(organization_id, id) on delete cascade,
  -- Published implies the freeze timestamp is set; a draft never has one yet.
  constraint form_versions_published_at_consistency
    check ((status = 'published') = (published_at is not null))
);

comment on table public.form_versions is
  'A form''s own Draft -> Published history, copied from the Quotes pattern. A published row is frozen by '
  'the trigger below; revising after publish opens a new draft rather than reopening the old one.';

create index form_versions_form_idx on public.form_versions(form_id, version_number desc);

alter table public.forms
  add constraint forms_draft_version_fk foreign key (organization_id, draft_version_id)
    references public.form_versions(organization_id, id) on delete restrict,
  add constraint forms_published_version_fk foreign key (organization_id, current_published_version_id)
    references public.form_versions(organization_id, id) on delete restrict;

revoke insert, update, delete, truncate, references, trigger
  on public.form_versions
  from anon, authenticated;

alter table public.form_versions enable row level security;

create policy "form managers can view form versions"
on public.form_versions for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'settings.forms.manage')
);

create or replace function private.form_versions_reject_published_change()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'published' then
    raise exception 'A published form version is immutable.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger form_versions_reject_published_change
before update on public.form_versions
for each row execute function private.form_versions_reject_published_change();

-- 4. Commands -----------------------------------------------------------------------------------------------

create or replace function public.create_form(
  target_organization_id uuid,
  new_outcome text,
  new_name text,
  new_title text,
  new_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_name text;
  clean_title text;
  clean_description text;
  new_form public.forms;
  new_version public.form_versions;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  if new_outcome not in ('request', 'assessment', 'job') then
    raise exception 'Choose what this form creates: a request, an assessment, or a job.'
      using errcode = 'check_violation';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 120 then
    raise exception 'Give this form a name up to 120 characters.' using errcode = 'check_violation';
  end if;

  clean_title := nullif(trim(coalesce(new_title, '')), '');
  if clean_title is null or char_length(clean_title) > 160 then
    raise exception 'Give this form a title customers will see, up to 160 characters.'
      using errcode = 'check_violation';
  end if;

  clean_description := nullif(trim(coalesce(new_description, '')), '');
  if clean_description is not null and char_length(clean_description) > 2000 then
    raise exception 'The form description is too long.' using errcode = 'check_violation';
  end if;

  insert into public.forms (organization_id, outcome, name, created_by, updated_by)
  values (target_organization_id, new_outcome, clean_name, (select auth.uid()), (select auth.uid()))
  returning * into new_form;

  insert into public.form_versions (
    organization_id, form_id, version_number, status, title, description, created_by, updated_by
  ) values (
    target_organization_id, new_form.id, 1, 'draft', clean_title, clean_description,
    (select auth.uid()), (select auth.uid())
  )
  returning * into new_version;

  update public.forms set draft_version_id = new_version.id where id = new_form.id;

  return jsonb_build_object(
    'form_id', new_form.id, 'outcome', new_form.outcome, 'name', new_form.name,
    'is_enabled', new_form.is_enabled, 'is_default', new_form.is_default, 'revision', new_form.revision,
    'draft_version_id', new_version.id, 'draft_version_number', new_version.version_number,
    'draft_revision', new_version.revision
  );
end;
$$;

revoke all on function public.create_form(uuid, text, text, text, text) from public;
revoke execute on function public.create_form(uuid, text, text, text, text) from anon;
grant execute on function public.create_form(uuid, text, text, text, text) to authenticated;

create or replace function public.update_form_identity(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer,
  new_name text,
  new_is_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
  clean_name text;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id
  for update;

  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if form_row.archived_at is not null then
    raise exception 'Restore this form before editing it.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from form_row.revision then
    raise exception 'Someone else changed this form while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 120 then
    raise exception 'Give this form a name up to 120 characters.' using errcode = 'check_violation';
  end if;

  update public.forms
  set name = clean_name, is_enabled = coalesce(new_is_enabled, form_row.is_enabled),
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = form_row.id
  returning * into form_row;

  return jsonb_build_object(
    'form_id', form_row.id, 'name', form_row.name, 'is_enabled', form_row.is_enabled,
    'revision', form_row.revision
  );
end;
$$;

revoke all on function public.update_form_identity(uuid, uuid, integer, text, boolean) from public;
revoke execute on function public.update_form_identity(uuid, uuid, integer, text, boolean) from anon;
grant execute on function public.update_form_identity(uuid, uuid, integer, text, boolean) to authenticated;

create or replace function public.set_form_default(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id
  for update;

  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if form_row.archived_at is not null then
    raise exception 'An archived form cannot be the default. Restore it first.'
      using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from form_row.revision then
    raise exception 'Someone else changed this form while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  if form_row.is_default then
    return jsonb_build_object('form_id', form_row.id, 'is_default', true, 'revision', form_row.revision);
  end if;

  -- Clear the current default in the same group: "request" stands alone; "assessment" and "job" share the
  -- one "booking" default slot, matching "one default request form and one default booking form."
  update public.forms
  set is_default = false, revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where organization_id = target_organization_id
    and archived_at is null
    and is_default
    and id <> form_row.id
    and (outcome = 'request') = (form_row.outcome = 'request');

  update public.forms
  set is_default = true, revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = form_row.id
  returning * into form_row;

  return jsonb_build_object('form_id', form_row.id, 'is_default', true, 'revision', form_row.revision);
end;
$$;

revoke all on function public.set_form_default(uuid, uuid, integer) from public;
revoke execute on function public.set_form_default(uuid, uuid, integer) from anon;
grant execute on function public.set_form_default(uuid, uuid, integer) to authenticated;

create or replace function public.archive_form(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id
  for update;

  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from form_row.revision then
    raise exception 'Someone else changed this form while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;
  if form_row.archived_at is not null then
    return jsonb_build_object('form_id', form_row.id, 'archived', true, 'revision', form_row.revision);
  end if;

  update public.forms
  set archived_at = now(), is_default = false, is_enabled = false,
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = form_row.id
  returning * into form_row;

  return jsonb_build_object('form_id', form_row.id, 'archived', true, 'revision', form_row.revision);
end;
$$;

revoke all on function public.archive_form(uuid, uuid, integer) from public;
revoke execute on function public.archive_form(uuid, uuid, integer) from anon;
grant execute on function public.archive_form(uuid, uuid, integer) to authenticated;

create or replace function public.restore_form(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id
  for update;

  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from form_row.revision then
    raise exception 'Someone else changed this form while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;
  if form_row.archived_at is null then
    return jsonb_build_object('form_id', form_row.id, 'archived', false, 'revision', form_row.revision);
  end if;

  update public.forms
  set archived_at = null, revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = form_row.id
  returning * into form_row;

  return jsonb_build_object('form_id', form_row.id, 'archived', false, 'revision', form_row.revision);
end;
$$;

revoke all on function public.restore_form(uuid, uuid, integer) from public;
revoke execute on function public.restore_form(uuid, uuid, integer) from anon;
grant execute on function public.restore_form(uuid, uuid, integer) to authenticated;

create or replace function public.update_form_draft(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer,
  new_title text,
  new_description text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
  draft_row public.form_versions;
  clean_title text;
  clean_description text;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id;
  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if form_row.draft_version_id is null then
    raise exception 'This form has no draft to edit. Start a new draft first.'
      using errcode = 'check_violation';
  end if;

  select * into draft_row from public.form_versions
  where id = form_row.draft_version_id and organization_id = target_organization_id
  for update;

  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this draft while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  clean_title := nullif(trim(coalesce(new_title, '')), '');
  if clean_title is null or char_length(clean_title) > 160 then
    raise exception 'Give this form a title customers will see, up to 160 characters.'
      using errcode = 'check_violation';
  end if;

  clean_description := nullif(trim(coalesce(new_description, '')), '');
  if clean_description is not null and char_length(clean_description) > 2000 then
    raise exception 'The form description is too long.' using errcode = 'check_violation';
  end if;

  update public.form_versions
  set title = clean_title, description = clean_description,
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = draft_row.id
  returning * into draft_row;

  return jsonb_build_object(
    'form_id', form_row.id, 'draft_version_id', draft_row.id,
    'title', draft_row.title, 'description', draft_row.description, 'revision', draft_row.revision
  );
end;
$$;

revoke all on function public.update_form_draft(uuid, uuid, integer, text, text) from public;
revoke execute on function public.update_form_draft(uuid, uuid, integer, text, text) from anon;
grant execute on function public.update_form_draft(uuid, uuid, integer, text, text) to authenticated;

create or replace function public.publish_form_draft(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
  draft_row public.form_versions;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id
  for update;
  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if form_row.archived_at is not null then
    raise exception 'An archived form cannot be published. Restore it first.'
      using errcode = 'check_violation';
  end if;
  if form_row.draft_version_id is null then
    raise exception 'This form has no draft to publish.' using errcode = 'check_violation';
  end if;

  select * into draft_row from public.form_versions
  where id = form_row.draft_version_id and organization_id = target_organization_id
  for update;

  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this draft while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  update public.form_versions
  set status = 'published', published_at = now(),
      updated_by = (select auth.uid()), updated_at = now()
  where id = draft_row.id
  returning * into draft_row;

  update public.forms
  set current_published_version_id = draft_row.id, draft_version_id = null,
      updated_by = (select auth.uid()), updated_at = now()
  where id = form_row.id;

  return jsonb_build_object(
    'form_id', form_row.id, 'published_version_id', draft_row.id,
    'version_number', draft_row.version_number, 'published_at', draft_row.published_at
  );
end;
$$;

revoke all on function public.publish_form_draft(uuid, uuid, integer) from public;
revoke execute on function public.publish_form_draft(uuid, uuid, integer) from anon;
grant execute on function public.publish_form_draft(uuid, uuid, integer) to authenticated;

create or replace function public.create_form_draft(
  target_organization_id uuid,
  target_form_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
  published_row public.form_versions;
  new_version public.form_versions;
  next_version_number integer;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id
  for update;
  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if form_row.archived_at is not null then
    raise exception 'Restore this form before starting a new draft.' using errcode = 'check_violation';
  end if;
  if form_row.draft_version_id is not null then
    raise exception 'This form already has a draft in progress.' using errcode = 'check_violation';
  end if;
  if form_row.current_published_version_id is null then
    raise exception 'This form has no published version to revise.' using errcode = 'check_violation';
  end if;

  select * into published_row from public.form_versions
  where id = form_row.current_published_version_id and organization_id = target_organization_id;

  select coalesce(max(version_number), 0) + 1 into next_version_number
  from public.form_versions
  where form_id = form_row.id;

  insert into public.form_versions (
    organization_id, form_id, version_number, status, title, description, created_by, updated_by
  ) values (
    target_organization_id, form_row.id, next_version_number, 'draft',
    published_row.title, published_row.description, (select auth.uid()), (select auth.uid())
  )
  returning * into new_version;

  update public.forms set draft_version_id = new_version.id where id = form_row.id;

  return jsonb_build_object(
    'form_id', form_row.id, 'draft_version_id', new_version.id,
    'draft_version_number', new_version.version_number, 'revision', new_version.revision
  );
end;
$$;

revoke all on function public.create_form_draft(uuid, uuid) from public;
revoke execute on function public.create_form_draft(uuid, uuid) from anon;
grant execute on function public.create_form_draft(uuid, uuid) to authenticated;
