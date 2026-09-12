-- Contractor Settings, Part 4B-1: request-form builder content.
--
-- Part 4A gave each form version a title + description and nothing else, deliberately leaving the actual
-- builder content (contact block, custom sections/questions, photos, confirmation) to 4B. This adds that as
-- ONE jsonb document on the version -- the "schema as data" model every mature form builder uses (Jobber,
-- Typeform, Google Forms) -- so the whole definition freezes atomically at publish and revising still opens a
-- fresh draft. Structure is validated by Zod in the /api layer before any write (CLAUDE.md rule 12); the
-- database only guards that content is a json object and is not absurdly large. Booking rules (services,
-- availability, approval, service areas) are 4B-2 and are not touched here.

-- 1. Content column ----------------------------------------------------------------------------------------

alter table public.form_versions
  add column content jsonb not null default '{}'::jsonb;

-- Every existing and future row (the default is an object) satisfies this; the app enforces the real shape.
alter table public.form_versions
  add constraint form_versions_content_is_object
    check (jsonb_typeof(content) = 'object');

comment on column public.form_versions.content is
  'The customer-facing form definition (contact block, custom sections/questions, photos, confirmation) as '
  'one validated jsonb document. Written only by the definer commands below; the /api layer validates its '
  'full shape with Zod before calling them.';

-- 2. Seed a usable default on creation --------------------------------------------------------------------
-- create_form previously seeded only title/description. A brand-new form now also starts with a sensible
-- request builder: name + email required, phone shown/optional, company hidden, address shown/optional, no
-- custom sections, photos off, and default confirmation copy -- so a form is never published empty.

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
  default_content jsonb := jsonb_build_object(
    'contact', jsonb_build_object(
      'name', jsonb_build_object('required', true),
      'email', jsonb_build_object('shown', true, 'required', true, 'marketing_consent', false),
      'phone', jsonb_build_object('shown', true, 'required', false, 'marketing_consent', false),
      'company', jsonb_build_object('shown', false, 'required', false),
      'address', jsonb_build_object('shown', true, 'required', false)
    ),
    'sections', jsonb_build_array(),
    'photos', jsonb_build_object('enabled', false, 'max', 10),
    'confirmation', jsonb_build_object(
      'title', 'Thanks — we got your request',
      'message', 'We''ll be in touch shortly to talk about your project.',
      'redirect_url', null
    )
  );
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
    organization_id, form_id, version_number, status, title, description, content, created_by, updated_by
  ) values (
    target_organization_id, new_form.id, 1, 'draft', clean_title, clean_description, default_content,
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

-- 3. Carry content forward when revising a published form -------------------------------------------------
-- create_form_draft seeds the new draft from the published version. It must now copy content too, so a
-- revision starts from what customers currently see rather than an empty builder.

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
    organization_id, form_id, version_number, status, title, description, content, created_by, updated_by
  ) values (
    target_organization_id, form_row.id, next_version_number, 'draft',
    published_row.title, published_row.description, published_row.content,
    (select auth.uid()), (select auth.uid())
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

-- 4. Save the whole draft (title + description + content) atomically --------------------------------------
-- A form draft is one document edited in the builder and then published, so one command saves all of it under
-- the same revision check. The old 5-argument signature is dropped in favor of the 6-argument one; 4A shipped
-- no app callers of it yet. The database guards only type and gross size -- the /api layer has already
-- validated the full content shape with Zod before this runs.

drop function if exists public.update_form_draft(uuid, uuid, integer, text, text);

create or replace function public.update_form_draft(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer,
  new_title text,
  new_description text,
  new_content jsonb
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

  if new_content is null or jsonb_typeof(new_content) <> 'object' then
    raise exception 'The form content is missing or malformed.' using errcode = 'check_violation';
  end if;
  -- Gross safety bound only; the real per-field caps live in the Zod schema the /api route runs first.
  if length(new_content::text) > 65536 then
    raise exception 'This form has too much content. Remove some questions and try again.'
      using errcode = 'check_violation';
  end if;

  update public.form_versions
  set title = clean_title, description = clean_description, content = new_content,
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = draft_row.id
  returning * into draft_row;

  return jsonb_build_object(
    'form_id', form_row.id, 'draft_version_id', draft_row.id,
    'title', draft_row.title, 'description', draft_row.description,
    'content', draft_row.content, 'revision', draft_row.revision
  );
end;
$$;

revoke all on function public.update_form_draft(uuid, uuid, integer, text, text, jsonb) from public;
revoke execute on function public.update_form_draft(uuid, uuid, integer, text, text, jsonb) from anon;
grant execute on function public.update_form_draft(uuid, uuid, integer, text, text, jsonb) to authenticated;

-- 5. Harden the 4A immutability trigger -------------------------------------------------------------------
-- The published-version guard shipped in 4A without a fixed search_path (a function_search_path_mutable
-- advisory). It only reads the trigger pseudo-record and raises, so pinning search_path changes no behavior
-- and clears the warning on the forms subsystem.

alter function private.form_versions_reject_published_change() set search_path = pg_catalog;
