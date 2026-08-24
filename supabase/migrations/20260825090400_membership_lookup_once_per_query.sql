-- Team & access, part 3A, layer 2c: the two things layer 2 missed, and one thing it should not change.
--
-- 1. There was never a fifth helper. There were seven.
--
-- Layer 2 threaded `status = 'active'` through the five membership helpers this campaign knew about.
-- Verifying it turned up two more that reason about membership on their own:
--
--   * private.member_organizations(), added by the Quotes campaign on 2026-08-20 for the same
--     once-per-query reason permitted_organizations exists. It had no status filter, because status did
--     not exist yet, so the request pricing read policy that depends on it still let a deactivated member
--     read priced request lines after layer 2. It is corrected below.
--
--   * private.validate_client_owner(), the trigger that keeps a client's owner inside the organization.
--     It accepted any membership row, so a client could be assigned to somebody who no longer works here.
--     Work is only ever handed to an active member, so it is corrected below too.
--
-- 2. The notes author branch stays per-row, and that is a measured decision, not an oversight.
--
-- Layer 2b closed a real hole: the notes read policy let an author read their own notes with no membership
-- check at all, so a deactivated or permanently removed person kept reading every note they had ever
-- written. The fix uses private.is_organization_member, which takes a column and is therefore evaluated
-- once per row. Converting it to the set-returning form looked like the obvious follow-up. Measured on
-- 5,000 notes hanging off one client, a 25-row page:
--
--   author branch with no membership check (the hole)      6,765 ms
--   private.is_organization_member(organization_id)        6,963 ms   +3%
--   organization_id in (select member_organizations())    10,059 ms   +49%
--
-- The plans say why. Making the first branch hashable lets the planner hash the whole OR, which hoists the
-- EXISTS into a hashed subplan and evaluates private.can_view_linked_entity across every row of
-- note_links in the database -- work that no longer shrinks when the page does. The per-row form keeps a
-- nested loop that evaluates lazily. So the security fix stays as layer 2b wrote it, at a measured 3%.
--
-- The 6.7 s baseline is not this campaign's: it is can_view_linked_entity called once per row, twice per
-- note. That is the separately tracked app-wide per-row helper problem, it belongs to whoever owns the
-- collaboration policies, and these numbers are recorded against it in Memory/deferred/INDEX.md.

-- Correction 1: the sixth helper joins the seam.
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

-- Correction 2: work is handed to people who still work here.
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

-- The notes policy, restored to the measured-cheaper per-row form from layer 2b.
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
