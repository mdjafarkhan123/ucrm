-- Files and Media, Part 6D, safe-pause bridge.
--
-- The previous migration (20260923130000) dropped set_organization_logo because Part 6D's plan is to stop
-- calling it: a logo File is meant to promote itself once it clears processing, via the new branch added to
-- finalize_file_processing in that same migration. But the branding settings page, its PUT commit route,
-- and the client upload flow have not been swapped over to that new pipeline yet -- that work is paused
-- mid-session. Until it lands, the live page still calls this function by name, so it is recreated here,
-- unchanged from its original definition, purely to keep today's logo upload/replace/remove working. Drop
-- it again in the same migration that finishes wiring the branding page to the File Manager upload.

CREATE OR REPLACE FUNCTION "public"."set_organization_logo"("target_organization_id" "uuid", "new_object_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  previous_object_key text;
  new_revision integer;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_object_key is null
     or new_object_key !~ ('^' || target_organization_id::text || '/logo/')
  then
    raise exception 'That logo upload is invalid.' using errcode = 'check_violation';
  end if;

  select logo_object_key into previous_object_key
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  update public.organization_settings
  set
    logo_object_key = new_object_key,
    branding_revision = branding_revision + 1,
    branding_updated_by = (select auth.uid()),
    branding_updated_at = now()
  where organization_id = target_organization_id
  returning branding_revision into new_revision;

  insert into public.organization_settings_audit (
    organization_id, section, changed_fields, actor_user_id
  )
  values (target_organization_id, 'branding', array['logo'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'branding_revision', new_revision,
    'logo_object_key', new_object_key,
    'previous_object_key', previous_object_key
  );
end;
$$;
