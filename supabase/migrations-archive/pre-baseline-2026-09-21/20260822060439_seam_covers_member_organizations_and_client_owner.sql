create or replace function private.member_organizations()
returns setof uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select membership.organization_id
  from public.organization_members as membership
  join public.organizations as organization
    on organization.id = membership.organization_id
  where membership.user_id = (select auth.uid())
    and membership.status = 'active'
    and organization.lifecycle_status = 'active';
$function$;

revoke all on function private.member_organizations() from public, anon;
grant execute on function private.member_organizations() to authenticated;

create or replace function private.validate_client_owner()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if new.owner_user_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.organization_members
    where organization_id = new.organization_id
      and user_id = new.owner_user_id
      and status = 'active'
  ) then
    raise exception 'The client owner must be an active member of the same organization.'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

drop policy if exists "permitted members can view notes" on public.notes;
create policy "permitted members can view notes"
  on public.notes
  for select
  to authenticated
  using (
    (
      created_by = (select auth.uid())
      and private.is_organization_member(organization_id)
    )
    or exists (
      select 1
      from public.note_links as link
      where link.note_id = notes.id
        and private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
    )
  );
