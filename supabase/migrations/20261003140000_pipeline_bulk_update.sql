-- Pipeline part D6: bulk tools on the Table view.
--
-- The plan allows exactly three bulk changes: change the owner, add a Task, and place cards in a custom
-- follow-up stage. Nothing that talks to a customer, converts, closes, or moves a protected stage is offered
-- in bulk, and this function has no way to do any of those.
--
-- Each card goes through the same function a single card already uses — pipeline_update_opportunity_details,
-- pipeline_create_opportunity_task, pipeline_place_opportunity — so every rule (permission, owner and
-- assignee eligibility, the five-open-Task limit, sections, on-hold stages needing a future Task) is the one
-- the single-card path enforces, never a second copy. One card's refusal does not undo the others: each runs
-- in its own savepoint and the result says, per card, done, unchanged, or refused with the reason a person
-- can act on (HubSpot's and Pipedrive's bulk edits report partial success the same way).
--
-- Cards are taken in id order, so two bulk changes over overlapping cards lock them in the same order and
-- cannot deadlock. At most 50 cards per call: each card's savepoint that writes keeps a subtransaction id
-- until commit, and Postgres caches only 64 per transaction before every other session's snapshots slow down.

create function public.pipeline_bulk_update(
  target_opportunity_ids uuid[],
  bulk_action text,
  new_owner_user_id uuid default null,
  target_custom_stage_id uuid default null,
  new_title text default null,
  new_instructions text default null,
  new_assignee_user_id uuid default null,
  new_due_on date default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  card_ids uuid[];
  card_id uuid;
  placed jsonb;
  results jsonb := '[]'::jsonb;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if bulk_action not in ('owner', 'task', 'place') then
    raise exception 'Unknown bulk change.' using errcode = 'invalid_parameter_value';
  end if;

  select array_agg(distinct listed.id order by listed.id)
  into card_ids
  from unnest(target_opportunity_ids) as listed(id)
  where listed.id is not null;

  if coalesce(cardinality(card_ids), 0) = 0 then
    raise exception 'Pick at least one card.' using errcode = 'invalid_parameter_value';
  end if;
  if cardinality(card_ids) > 50 then
    raise exception 'Change 50 cards or fewer at a time.' using errcode = 'program_limit_exceeded';
  end if;

  foreach card_id in array card_ids loop
    begin
      if bulk_action = 'owner' then
        perform public.pipeline_update_opportunity_details(
          target_opportunity_id => card_id,
          set_owner => true,
          new_owner_user_id => new_owner_user_id
        );
        results := results || jsonb_build_object('id', card_id, 'status', 'done');

      elsif bulk_action = 'task' then
        perform public.pipeline_create_opportunity_task(
          target_opportunity_id => card_id,
          new_title => new_title,
          new_instructions => new_instructions,
          new_assignee_user_id => new_assignee_user_id,
          new_due_on => new_due_on
        );
        results := results || jsonb_build_object('id', card_id, 'status', 'done');

      else
        placed := public.pipeline_place_opportunity(card_id, target_custom_stage_id);
        results := results || jsonb_build_object(
          'id', card_id,
          'status', case when (placed ->> 'applied')::boolean then 'done' else 'unchanged' end
        );
      end if;
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;

      results := results || jsonb_build_object(
        'id', card_id,
        'status', 'refused',
        -- The single-card refusals written for a person pass through as they are. A missing or foreign
        -- card reads the same as one this person may not change, and anything unexpected is not shown.
        'reason', case
          when failed_state in ('23514', '54000') then failed_message
          when failed_state = '42501' then 'This card could not be found.'
          else 'Something went wrong with this card. Try it on its own.'
        end,
        'code', nullif(failed_hint, '')
      );
    end;
  end loop;

  return results;
end;
$$;

revoke all on function public.pipeline_bulk_update(uuid[], text, uuid, uuid, text, text, uuid, date)
  from public, anon;
grant execute on function public.pipeline_bulk_update(uuid[], text, uuid, uuid, text, text, uuid, date)
  to authenticated, service_role;
