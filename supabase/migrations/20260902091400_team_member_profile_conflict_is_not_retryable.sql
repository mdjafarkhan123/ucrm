-- A stale profile revision is a business conflict, not a database serialization failure. PostgREST retries
-- 40001, so the outdated request stayed pending forever. P0409 is the app's non-retryable conflict code.
create or replace function public.update_team_member_profile(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  new_full_name text,
  new_work_phone text,
  new_job_title text,
  new_schedule_color text,
  expected_profile_revision integer
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  current_full_name text;
  clean_full_name text;
  clean_work_phone text;
  clean_job_title text;
  clean_schedule_color text;
  changed_fields text[] := '{}'::text[];
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );
  perform private.assert_membership_is_editable(membership);

  if expected_profile_revision is null or expected_profile_revision <> membership.profile_revision then
    raise exception 'Someone else changed this person''s details while you were editing.'
      using errcode = 'P0409';
  end if;

  clean_full_name := nullif(btrim(coalesce(new_full_name, '')), '');
  clean_work_phone := nullif(btrim(coalesce(new_work_phone, '')), '');
  clean_job_title := nullif(btrim(coalesce(new_job_title, '')), '');
  clean_schedule_color := nullif(btrim(coalesce(new_schedule_color, '')), '');

  select profile.full_name into current_full_name
  from public.profiles as profile
  where profile.id = target_user_id;

  if clean_full_name is not null and clean_full_name is distinct from current_full_name then
    if char_length(clean_full_name) > 160 then
      raise exception 'That name is too long.' using errcode = 'check_violation';
    end if;

    update public.profiles as profile
    set full_name = clean_full_name,
        updated_at = now()
    where profile.id = target_user_id;

    changed_fields := changed_fields || 'full_name'::text;
  end if;

  if clean_work_phone is distinct from membership.work_phone then
    changed_fields := changed_fields || 'work_phone'::text;
  end if;

  if clean_job_title is distinct from membership.job_title then
    changed_fields := changed_fields || 'job_title'::text;
  end if;

  if clean_schedule_color is distinct from membership.schedule_color then
    changed_fields := changed_fields || 'schedule_color'::text;
  end if;

  if array_length(changed_fields, 1) is null then
    return membership;
  end if;

  update public.organization_members as membership_row
  set work_phone = clean_work_phone,
      job_title = clean_job_title,
      schedule_color = clean_schedule_color,
      profile_revision = membership_row.profile_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.profile_updated', 'member', actor_user_id, target_user_id,
    jsonb_build_object('changed_fields', to_jsonb(changed_fields))
  );

  return membership;
end;
$$;

comment on function public.update_team_member_profile(uuid, uuid, uuid, text, text, text, text, integer) is
  'Saves one member''s business details. Work phone, job title and colour belong to this organization; the '
  'name belongs to the person, so a null name leaves it untouched instead of erasing it everywhere.';

revoke all on function public.update_team_member_profile(uuid, uuid, uuid, text, text, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.update_team_member_profile(uuid, uuid, uuid, text, text, text, text, integer)
  to service_role;
