-- Contractor Settings, Part 4B-2c fix: restore default_content seeding in create_form.
--
-- 20260913160000_contractor_settings_booking_rules_foundation.sql redefined create_form to add the
-- booking-rules insert, but its `insert into form_versions` dropped the `content` column and the
-- `default_content` seed that 20260912120000_contractor_settings_forms_builder_content.sql had added.
-- Every form created since then saves content = '{}' (the column default) instead of a usable request
-- builder, and the builder page crashes on open (cloneContent: "clone.sections is not iterable"). This
-- restores the exact seed from 20260912120000 while keeping the booking-rules insert from 20260913160000.

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

  -- Only the two instant-booking outcomes ever have booking rules; a 'request' form is reviewed by staff and
  -- never books a slot, so it never gets this row.
  if new_outcome in ('assessment', 'job') then
    insert into public.form_booking_rules (form_id, organization_id)
    values (new_form.id, target_organization_id);
  end if;

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
