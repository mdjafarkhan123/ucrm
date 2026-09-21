-- Sales Pipeline, Part 5B: the forward-only drag gate.
-- The board itself never decides a stage (opportunity_apply_stage still owns that). This migration only
-- answers one question before any write happens: is dropping this card on that column a real, staff-
-- performable move? A "yes" hands the API route back which record to act on; the route then performs the
-- actual domain command (assessment upsert/complete, or `publish_quote`) through its normal, already-
-- protected write path. This function writes nothing itself.

-- 1. The transition table ------------------------------------------------------------------------------

-- The one allow-list for staff dragging. Forward only, and only where a single existing domain command
-- can satisfy the target stage's entry rule in one step:
--   * New requests -> Assessment unscheduled/scheduled: turning on (and optionally booking) the visit.
--   * Assessment unscheduled -> scheduled or completed; Assessment scheduled -> completed.
--   * Quote Draft -> Awaiting response: sending it.
-- Deliberately absent, confirmed with Jafar 2026-08-23:
--   * New requests -> Assessment completed: needs two commands (create, then complete), not one.
--   * Awaiting response -> Changes requested: only the client's own decision can do this; the card moves
--     there by itself when they do. Staff cannot drag it there.
--   * Changes requested -> Draft (Revise) or -> Awaiting response (Republish): both are real staff
--     actions, but backward on the board. They stay Quote-page actions; the card jumps back on its own
--     once staff uses them, the same way un-completing an assessment already moves a card backward today.
--   * Any other backward move.
create or replace function private.pipeline_drag_transition_allowed(from_stage text, to_stage text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select (from_stage, to_stage) in (
    ('new_request', 'assessment_unscheduled'),
    ('new_request', 'assessment_scheduled'),
    ('assessment_unscheduled', 'assessment_scheduled'),
    ('assessment_unscheduled', 'assessment_completed'),
    ('assessment_scheduled', 'assessment_completed'),
    ('quote_draft', 'quote_awaiting_response')
  );
$$;

revoke all on function private.pipeline_drag_transition_allowed(text, text) from public;

-- 2. Lock and authorize ---------------------------------------------------------------------------------

-- Mirrors `private.pipeline_lock_opportunity_for_outcome` exactly, kept as its own function rather than
-- reused so Part 5A's closed outcome engine stays untouched. Wording is drag-specific; behavior is not.
create or replace function private.pipeline_lock_opportunity_for_drag(target_opportunity_id uuid)
returns public.opportunities
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_row public.opportunities;
begin
  select * into target_row
  from public.opportunities
  where id = target_opportunity_id
  for update;

  if target_row.id is null
     or not private.member_has_permission(
       target_row.organization_id, (select auth.uid()), 'pipeline.edit'
     ) then
    raise exception 'You do not have access to move this card.' using errcode = 'insufficient_privilege';
  end if;

  return target_row;
end;
$$;

revoke all on function private.pipeline_lock_opportunity_for_drag(uuid) from public;
revoke execute on function private.pipeline_lock_opportunity_for_drag(uuid) from anon, authenticated;

-- 3. The drag gate itself ---------------------------------------------------------------------------------

-- Read-only: `opportunities` grants no direct select to `authenticated` (20260818232309), so the API
-- route cannot otherwise learn a card's current stage or which record backs it. This answers both, and
-- refuses before the route ever touches `assessments` or calls `publish_quote`. It performs no write, so
-- the assessment/quote command that follows still owns its own atomicity and its own guards.
create or replace function public.pipeline_drag_opportunity(
  target_opportunity_id uuid,
  to_stage text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  opportunity_row public.opportunities;
begin
  opportunity_row := private.pipeline_lock_opportunity_for_drag(target_opportunity_id);

  if not private.pipeline_drag_transition_allowed(opportunity_row.stage, to_stage) then
    raise exception 'That card cannot be moved there.' using errcode = 'check_violation';
  end if;

  return jsonb_build_object(
    'organization_id', opportunity_row.organization_id,
    'request_id', opportunity_row.request_id,
    'quote_id', opportunity_row.quote_id,
    'from_stage', opportunity_row.stage
  );
end;
$$;

revoke all on function public.pipeline_drag_opportunity(uuid, text) from public;
revoke execute on function public.pipeline_drag_opportunity(uuid, text) from anon;
grant execute on function public.pipeline_drag_opportunity(uuid, text) to authenticated;
