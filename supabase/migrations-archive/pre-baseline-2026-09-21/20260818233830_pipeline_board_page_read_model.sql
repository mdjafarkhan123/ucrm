-- Sales Pipeline, Part 2: one read for a board column.
-- The value column carries no member privilege, so the board can no longer be a plain select. This is
-- the one way a card reaches the browser. It runs with the owner's rights, which means row level
-- security does not run for it, so every rule it skips is re-applied here by hand rather than assumed:
--
--   who is asking      taken from auth.uid(), never from an argument
--   which board        the caller must be a live member of that organization with pipeline.view
--   client details     only when the caller may see that client, the same rule the clients table uses
--   owner name         only when the owner is still a teammate, the same rule the profiles table uses
--   money              only with pipeline.view_value, and null otherwise, never a partial hint
--
-- Paging, ordering and the page cap are unchanged from Part 1, so the board behaves exactly as before.

create or replace function public.pipeline_board_page(
  target_organization_id uuid,
  target_stage text,
  cursor_stage_entered_at timestamptz default null,
  cursor_id uuid default null,
  page_limit integer default 25
)
returns table (
  id uuid,
  title text,
  stage text,
  stage_entered_at timestamptz,
  outcome text,
  created_at timestamptz,
  request_id uuid,
  request_status text,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  property_id uuid,
  property_label text,
  property_address_line1 text,
  property_city text,
  property_state_region text,
  property_postal_code text,
  owner_user_id uuid,
  owner_full_name text,
  owner_avatar_url text,
  estimated_value numeric,
  expected_close_on date,
  next_follow_up_on date
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if target_stage not in (
    'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed'
  ) then
    raise exception 'That is not a board column.' using errcode = 'invalid_parameter_value';
  end if;

  -- One row over the asked-for page is how the caller detects there is more, so the cap is 50 plus one.
  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Asked once for the whole page. can_view_client is still called per row underneath, but only for a
  -- caller who lacks the blanket permission, so the ordinary page pays nothing for it.
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  return query
  select
    opportunity.id,
    opportunity.title,
    opportunity.stage,
    opportunity.stage_entered_at,
    opportunity.outcome,
    opportunity.created_at,
    opportunity.request_id,
    -- Every member may see Requests, and only a member reaches this line.
    request.status,
    opportunity.client_id,
    case when client_visible.allowed then client.display_name end,
    case when client_visible.allowed then client.company_name end,
    opportunity.property_id,
    case when client_visible.allowed then property.label end,
    case when client_visible.allowed then property.address_line1 end,
    case when client_visible.allowed then property.city end,
    case when client_visible.allowed then property.state_region end,
    case when client_visible.allowed then property.postal_code end,
    opportunity.owner_user_id,
    -- A card owned by someone who has left keeps its owner, but their name is not ours to hand out any
    -- more than the profiles table would.
    case when owner_is_teammate.yes then owner_profile.full_name end,
    case when owner_is_teammate.yes then owner_profile.avatar_url end,
    case when caller_sees_money then opportunity.estimated_value end,
    opportunity.expected_close_on,
    opportunity.next_follow_up_on
  from public.opportunities as opportunity
  cross join lateral (
    select
      caller_sees_clients
      or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
  ) as client_visible
  cross join lateral (
    select exists (
      select 1
      from public.organization_members as owner_membership
      where owner_membership.organization_id = opportunity.organization_id
        and owner_membership.user_id = opportunity.owner_user_id
    ) as yes
  ) as owner_is_teammate
  left join public.clients as client
    on client.id = opportunity.client_id
   and client.organization_id = opportunity.organization_id
  left join public.properties as property
    on property.id = opportunity.property_id
   and property.organization_id = opportunity.organization_id
  left join public.requests as request
    on request.id = opportunity.request_id
   and request.organization_id = opportunity.organization_id
  left join public.profiles as owner_profile
    on owner_profile.id = opportunity.owner_user_id
  where opportunity.organization_id = target_organization_id
    and opportunity.stage = target_stage
    and opportunity.outcome = 'open'
    -- Keyset, in the exact shape of opportunities_board_idx: newest arrival first, id breaking ties.
    and (
      cursor_stage_entered_at is null
      or opportunity.stage_entered_at < cursor_stage_entered_at
      or (opportunity.stage_entered_at = cursor_stage_entered_at and opportunity.id > cursor_id)
    )
  order by opportunity.stage_entered_at desc, opportunity.id asc
  limit resolved_limit;
end;
$$;

revoke all on function public.pipeline_board_page(uuid, text, timestamptz, uuid, integer) from public;
revoke execute on function public.pipeline_board_page(uuid, text, timestamptz, uuid, integer) from anon;
grant execute on function public.pipeline_board_page(uuid, text, timestamptz, uuid, integer) to authenticated;
