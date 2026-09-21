-- Sales Pipeline, Part 2: ownership, estimated value, and planning dates.
-- Four fields join the Opportunity: who is accountable, what the work is worth, when it should close,
-- and when someone should chase it. None of them is stage. Stage stays derived from Request and
-- Assessment truth by the Part 1 triggers, and nothing here writes stage or stage_entered_at.
--
-- Money is the reason this migration is shaped the way it is. Members hold a real Supabase session in
-- the browser, so a permission enforced only in our API routes would not stop anyone reading the column
-- straight from PostgREST. The value column is therefore taken away from members at the database level
-- and handed back only through one function that asks whether this member may see money.

-- 1. Columns ---------------------------------------------------------------------------------------

alter table public.opportunities
  -- Points at the user, not at the membership row, so ownership survives someone leaving the team.
  -- The user themselves is only ever removed when the whole account goes, and then the name is gone
  -- anyway, so the reference falls back to unassigned rather than deleting commercial history.
  add column owner_user_id uuid references auth.users(id) on delete set null,
  -- Exact decimal. Null means nobody has estimated this yet, and that is never the same as zero.
  add column estimated_value numeric(12, 2),
  add column expected_close_on date,
  add column next_follow_up_on date;

alter table public.opportunities
  add constraint opportunities_estimated_value_positive
    check (estimated_value is null or estimated_value >= 0),
  -- A guard against a mistyped year, not a business rule.
  add constraint opportunities_expected_close_on_range
    check (expected_close_on is null or expected_close_on between date '2000-01-01' and date '2100-01-01'),
  add constraint opportunities_next_follow_up_on_range
    check (next_follow_up_on is null or next_follow_up_on between date '2000-01-01' and date '2100-01-01');

-- Two jobs: the salesperson filter, and the lookup Postgres needs when an auth user is deleted and
-- every owned row has to be found. Partial, because unassigned rows are never the answer to either.
create index opportunities_owner_idx
  on public.opportunities(owner_user_id)
  where owner_user_id is not null;

-- 2. Seeing money is its own permission ---------------------------------------------------------------

-- customers.view_financials is about one client's revenue and balance. Being allowed to work the board
-- is not the same as being allowed to see what the pipeline is worth, so this says so plainly.
insert into public.permissions (key, description)
values ('pipeline.view_value', 'See estimated values and totals on the sales pipeline')
on conflict (key) do update set description = excluded.description;

-- The same roles that already reach the board, so nothing changes for anyone today. The point of the
-- permission is that it can now be switched off for one person through the member overrides.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'pipeline.view_value'),
  ('admin', 'pipeline.view_value'),
  ('office', 'pipeline.view_value'),
  ('sales', 'pipeline.view_value')
on conflict (role, permission_key) do nothing;

-- private.has_permission only ever answers for the caller. Owner eligibility asks the same question
-- about somebody else, so this is the same rule with the user as an argument. Membership is required in
-- both branches: an override left behind by a former member grants nothing.
create or replace function private.member_has_permission(
  target_organization_id uuid,
  target_user_id uuid,
  target_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = target_user_id
      and coalesce(
        (
          select override.override_state = 'grant'
          from public.organization_member_permission_overrides as override
          where override.organization_id = membership.organization_id
            and override.user_id = membership.user_id
            and override.permission_key = target_permission_key
        ),
        exists (
          select 1
          from public.role_permissions as role_permission
          where role_permission.role = membership.role
            and role_permission.permission_key = target_permission_key
        )
      )
  );
$$;

-- Only the definer functions below call this. Supabase grants execute on new public-facing functions
-- by default, so every role that should not call one is named explicitly here and further down.
revoke all on function private.member_has_permission(uuid, uuid, text) from public;
revoke execute on function private.member_has_permission(uuid, uuid, text) from anon, authenticated;

-- 3. Only a real teammate can be made the owner ----------------------------------------------------------

-- Fires only when the owner actually changes, which is what keeps history safe: a card owned by someone
-- who has since left the team is never re-checked and never quietly cleared.
create or replace function private.opportunity_validate_owner()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.member_has_permission(new.organization_id, new.owner_user_id, 'pipeline.view') then
    raise exception 'That person cannot be given work on the sales pipeline.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger opportunities_validate_owner
before insert or update of owner_user_id on public.opportunities
for each row
when (new.owner_user_id is not null)
execute function private.opportunity_validate_owner();

revoke all on function private.opportunity_validate_owner() from public;
revoke execute on function private.opportunity_validate_owner() from anon, authenticated;

-- 4. The write boundary ------------------------------------------------------------------------------

-- One way in for all four fields. Explicit set_ flags keep "leave this alone" and "clear this" apart,
-- so editing the follow-up date can never wipe a value the editor could not even see.
create or replace function public.pipeline_update_opportunity_details(
  target_opportunity_id uuid,
  set_owner boolean default false,
  new_owner_user_id uuid default null,
  set_value boolean default false,
  new_estimated_value numeric default null,
  set_expected_close boolean default false,
  new_expected_close_on date default null,
  set_next_follow_up boolean default false,
  new_next_follow_up_on date default null
)
returns table (
  id uuid,
  owner_user_id uuid,
  estimated_value numeric,
  expected_close_on date,
  next_follow_up_on date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid;
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
begin
  -- Definer rights skip row level security, so membership is checked here by hand rather than assumed.
  select opportunity.organization_id
  into target_organization_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id;

  if target_organization_id is null
     or not private.member_has_permission(target_organization_id, caller_id, 'pipeline.edit') then
    -- Same answer either way: a stranger learns nothing about whether the record exists.
    raise exception 'You do not have access to change this opportunity.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  if set_value and not caller_sees_money then
    raise exception 'You do not have access to change values on the sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  update public.opportunities as opportunity
  set
    owner_user_id = case when set_owner then new_owner_user_id else opportunity.owner_user_id end,
    estimated_value = case when set_value then new_estimated_value else opportunity.estimated_value end,
    expected_close_on =
      case when set_expected_close then new_expected_close_on else opportunity.expected_close_on end,
    next_follow_up_on =
      case when set_next_follow_up then new_next_follow_up_on else opportunity.next_follow_up_on end
  where opportunity.id = target_opportunity_id
  returning
    opportunity.id,
    opportunity.owner_user_id,
    -- Nothing is returned to somebody who may not see money, not even the value they did not change.
    case when caller_sees_money then opportunity.estimated_value end,
    opportunity.expected_close_on,
    opportunity.next_follow_up_on,
    opportunity.updated_at;
end;
$$;

revoke all on function public.pipeline_update_opportunity_details(
  uuid, boolean, uuid, boolean, numeric, boolean, date, boolean, date
) from public;

-- Signed out callers have no business here at all; a signed in one still has to pass the checks above.
revoke execute on function public.pipeline_update_opportunity_details(
  uuid, boolean, uuid, boolean, numeric, boolean, date, boolean, date
) from anon;

grant execute on function public.pipeline_update_opportunity_details(
  uuid, boolean, uuid, boolean, numeric, boolean, date, boolean, date
) to authenticated;

-- 5. Members lose the value column entirely --------------------------------------------------------------

-- Postgres cannot subtract one column from a table wide grant, so the table grants are replaced by a
-- column list. estimated_value is simply not on it, in or out, which is what makes the rule real
-- rather than a promise our API keeps.
--
-- Note for later migrations: a new column on this table is invisible to members until it is added to
-- these grants.
revoke select, insert, update on public.opportunities from authenticated;

grant select (
  id, organization_id, client_id, property_id, request_id, title, outcome, stage, stage_entered_at,
  created_at, updated_at, owner_user_id, expected_close_on, next_follow_up_on
) on public.opportunities to authenticated;

grant insert (
  id, organization_id, client_id, property_id, request_id, title, outcome, stage, stage_entered_at,
  created_at, updated_at, owner_user_id, expected_close_on, next_follow_up_on
) on public.opportunities to authenticated;

grant update (
  owner_user_id, expected_close_on, next_follow_up_on
) on public.opportunities to authenticated;
