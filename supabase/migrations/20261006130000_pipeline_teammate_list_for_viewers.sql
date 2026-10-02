-- Pipeline part G2: the owner, Task-owner and Salesperson lists only offer people who may hold Pipeline work.
--
-- Those lists used the general team list, so they offered field and finance teammates whom
-- `private.opportunity_validate_owner` and the Task rule then refuse ("That person cannot be given work on
-- the sales pipeline."). They now read `pipeline_mentionable_teammates`, the list the @mention menu already
-- uses (Pipedrive and HubSpot only offer people with access). The Salesperson filter is shown to everyone
-- who can see the board, so the list is opened to `pipeline.view`; it was `pipeline.edit`.
--
-- Unchanged from 20261004090000 except that permission. Same signature, so the grants stand.

create or replace function public.pipeline_mentionable_teammates(target_organization_id uuid)
returns table (user_id uuid, full_name text, avatar_url text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.' using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    membership.user_id,
    coalesce(nullif(btrim(profile.full_name), ''), account.email::text) as full_name,
    profile.avatar_url
  from public.organization_members as membership
  left join public.profiles as profile on profile.id = membership.user_id
  left join auth.users as account on account.id = membership.user_id
  where membership.organization_id = target_organization_id
    and membership.status = 'active'
    and private.member_receives_task_alerts(target_organization_id, membership.user_id)
  order by lower(coalesce(nullif(btrim(profile.full_name), ''), account.email::text, '')), membership.user_id
  limit 200;
end;
$$;

comment on function public.pipeline_mentionable_teammates(uuid) is
  'Active teammates who may see the Pipeline -- the people a card or Task can be given to and a Note can mention. Named by profile name, else sign-in email. Requires pipeline.view.';
