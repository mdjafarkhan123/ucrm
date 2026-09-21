-- Sales Pipeline, Part 2: the gated function becomes the only write path.
-- The previous migration handed members column level insert and update rights back, which left a second
-- door open: with pipeline.edit a member could set an owner or a date straight from the browser, and even
-- insert an Opportunity, which Part 1 says may only ever happen through the Request trigger.
--
-- Members now hold no write privilege on this table at all. Nothing legitimate loses anything, because
-- every real writer -- the Request trigger, the stage triggers, and
-- public.pipeline_update_opportunity_details -- runs with the table owner's rights.

revoke insert, update on public.opportunities from authenticated;

revoke insert (
  id, organization_id, client_id, property_id, request_id, title, outcome, stage, stage_entered_at,
  created_at, updated_at, owner_user_id, expected_close_on, next_follow_up_on
) on public.opportunities from authenticated;

revoke update (
  owner_user_id, expected_close_on, next_follow_up_on
) on public.opportunities from authenticated;

-- With no write privilege left, these policies can only ever permit something that is already refused.
-- Leaving them behind would suggest members write this table directly, and would quietly re-open the
-- second door the day someone grants a column for an unrelated reason.
drop policy "permitted members can create opportunities" on public.opportunities;
drop policy "permitted members can update opportunities" on public.opportunities;

comment on table public.opportunities is
  'Sales Pipeline opportunities. Members may read this table, never write it. Identity comes from the '
  'Request trigger, stage from the stage triggers, and the Part 2 fields from '
  'public.pipeline_update_opportunity_details. Any future write must arrive through a definer function '
  'that checks the caller, not through a new grant or policy.';
