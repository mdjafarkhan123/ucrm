-- Part 3C needs one bounded list whose searchable fields live across membership, profile, and invitation
-- rows. Keeping that join in Postgres gives the API one tenant-scoped round trip and keeps cursor ordering
-- exact; assembling independently paged lists in the browser would skip or duplicate people.
create or replace function public.list_team_directory(
  target_organization_id uuid,
  requested_status text default null,
  search_term text default null,
  page_limit integer default 25,
  cursor_status_order integer default null,
  cursor_created_at timestamptz default null,
  cursor_user_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  clean_search text := nullif(btrim(search_term), '');
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

  if requested_status is not null
     and requested_status not in ('pending', 'active', 'deactivated') then
    raise exception 'The team status filter is invalid.' using errcode = '22023';
  end if;

  if page_limit is null or page_limit < 1 or page_limit > 50 then
    raise exception 'The team page size must be between 1 and 50.' using errcode = '22023';
  end if;

  if clean_search is not null and char_length(clean_search) > 100 then
    raise exception 'The team search must be 100 characters or fewer.' using errcode = '22023';
  end if;

  if (cursor_status_order is null)::integer
     + (cursor_created_at is null)::integer
     + (cursor_user_id is null)::integer not in (0, 3) then
    raise exception 'The team cursor is incomplete.' using errcode = '22023';
  end if;

  with directory as materialized (
    select
      member.user_id,
      member.role,
      member.status,
      case member.status when 'pending' then 1 when 'active' then 2 else 3 end as status_order,
      member.access_revision,
      member.profile_revision,
      member.work_phone,
      member.job_title,
      member.schedule_color,
      member.created_at,
      member.deactivated_at,
      profile.full_name,
      profile.avatar_url,
      invitation.id as invitation_id,
      invitation.invited_email,
      invitation.state as invitation_state,
      invitation.last_delivery_error is not null as invitation_delivery_failed,
      invitation.last_sent_at,
      invitation.expires_at
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
      and member.status in ('pending', 'active', 'deactivated')
      and (requested_status is null or member.status = requested_status)
      and (
        clean_search is null
        or position(lower(clean_search) in lower(coalesce(profile.full_name, ''))) > 0
        or position(lower(clean_search) in lower(coalesce(invitation.invited_email, ''))) > 0
        or position(lower(clean_search) in lower(coalesce(member.job_title, ''))) > 0
        or position(lower(clean_search) in lower(coalesce(member.work_phone, ''))) > 0
      )
  ), page as materialized (
    select *
    from directory
    where cursor_status_order is null
       or status_order > cursor_status_order
       or (status_order = cursor_status_order and created_at < cursor_created_at)
       or (status_order = cursor_status_order and created_at = cursor_created_at
           and user_id > cursor_user_id)
    order by status_order, created_at desc, user_id
    limit page_limit + 1
  ), visible as materialized (
    select * from page
    order by status_order, created_at desc, user_id
    limit page_limit
  ), last_visible as (
    select status_order, created_at, user_id
    from visible
    order by status_order desc, created_at, user_id desc
    limit 1
  )
  select jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'user_id', row.user_id,
          'display_name', row.full_name,
          'avatar_url', row.avatar_url,
          'role', row.role,
          'status', row.status,
          'access_revision', row.access_revision,
          'profile_revision', row.profile_revision,
          'work_phone', row.work_phone,
          'job_title', row.job_title,
          'schedule_color', row.schedule_color,
          'created_at', row.created_at,
          'deactivated_at', row.deactivated_at,
          'invitation', case when row.invitation_id is null then null else jsonb_build_object(
            'id', row.invitation_id,
            'email', row.invited_email,
            'state', row.invitation_state,
            'delivery_failed', row.invitation_delivery_failed,
            'last_sent_at', row.last_sent_at,
            'expires_at', row.expires_at
          ) end
        ) order by row.status_order, row.created_at desc, row.user_id
      ) from visible as row
    ), '[]'::jsonb),
    'next_cursor', case when (select count(*) from page) > page_limit then (
      select jsonb_build_object(
        'status_order', last_visible.status_order,
        'created_at', last_visible.created_at,
        'user_id', last_visible.user_id
      ) from last_visible
    ) else null end,
    'seats_used', private.employee_seats_used(target_organization_id)
  ) into result;

  return result;
end;
$function$;

comment on function public.list_team_directory(uuid, text, text, integer, integer, timestamptz, uuid) is
  'Returns one authorized, searchable, cursor-paged Team directory envelope. It deliberately omits raw '
  'permission maps and Auth-only sign-in details; Part 3D owns access editing.';

revoke all on function public.list_team_directory(uuid, text, text, integer, integer, timestamptz, uuid)
  from public, anon, service_role;
grant execute on function public.list_team_directory(uuid, text, text, integer, integer, timestamptz, uuid)
  to authenticated;
