-- The directory is cursor-paged, but a detail route needs one exact member. Keeping this lookup in the
-- database preserves the same tenant and permission boundary as the directory without making the browser
-- walk pages or receiving an unbounded list.
create or replace function public.get_team_member_detail(
  target_organization_id uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  result jsonb;
begin
  if (select auth.uid()) is null or not exists (
    select 1
    from private.permitted_organizations('team.manage') as permitted(organization_id)
    where permitted.organization_id = target_organization_id
  ) then
    raise exception 'Team management is not available for this organization.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'user_id', member.user_id,
    'display_name', profile.full_name,
    'avatar_url', profile.avatar_url,
    'role', member.role,
    'status', member.status,
    'access_revision', member.access_revision,
    'profile_revision', member.profile_revision,
    'work_phone', member.work_phone,
    'job_title', member.job_title,
    'schedule_color', member.schedule_color,
    'created_at', member.created_at,
    'deactivated_at', member.deactivated_at,
    'invitation', case when invitation.id is null then null else jsonb_build_object(
      'id', invitation.id,
      'email', invitation.invited_email,
      'state', invitation.state,
      'delivery_failed', invitation.last_delivery_error is not null,
      'last_sent_at', invitation.last_sent_at,
      'expires_at', invitation.expires_at
    ) end
  ) into result
  from public.organization_members as member
  left join public.profiles as profile on profile.id = member.user_id
  left join lateral (
    select candidate.id, candidate.invited_email, candidate.state, candidate.last_delivery_error,
           candidate.last_sent_at, candidate.expires_at
    from public.organization_member_invitations as candidate
    where candidate.organization_id = member.organization_id
      and candidate.invited_user_id = member.user_id
      and candidate.state in ('reserving', 'invited', 'accepting')
    order by candidate.created_at desc, candidate.id desc
    limit 1
  ) as invitation on true
  where member.organization_id = target_organization_id
    and member.user_id = target_user_id
    and member.status in ('pending', 'active', 'deactivated');

  if result is null then
    raise exception 'That team member was not found.' using errcode = 'P0002';
  end if;

  return result;
end;
$function$;

comment on function public.get_team_member_detail(uuid, uuid) is
  'Returns one tenant-authorized Team member for the read-first details route; access editing remains separate.';

revoke all on function public.get_team_member_detail(uuid, uuid) from public, anon, service_role;
grant execute on function public.get_team_member_detail(uuid, uuid) to authenticated;
