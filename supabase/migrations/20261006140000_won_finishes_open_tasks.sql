-- Pipeline G2: winning a card finishes the follow-up Tasks still open on it.
--
-- A Task is a sales follow-up. Once the work is won there is nothing left to chase, but the Task stayed open:
-- a dated one sat on its assignee's Schedule for good, and an undated one stayed open where no screen shows
-- it, because a Won card has left the board and its Brief no longer opens. Jobber does not carry Tasks into
-- the Job; Jafar chose on 2026-10-02 to finish them at the win, the way a Lost Request already does, and to
-- let a Task be ticked off from the Schedule as well.
--
-- A card becomes Won in three places (an approved quote, a Request made into a Job, a Request made into a
-- Job from the job form), so the rule lives on the card itself rather than in each command: whichever
-- command sets the outcome, the Tasks follow.
--
--   * Won: every Task still open is completed and stamped with the Won event, exactly as Lost stamps its
--     own. A Task a person already finished keeps their name and no event id.
--   * Won reopened (an approved quote nobody has made a Job from): only the Tasks that Won event finished
--     come back. A closed card refuses new Tasks, so no more than the five it held can return.
--
-- Growth: one update per win, over at most ten Tasks, found by the card's own index.

create function private.opportunity_won_settles_tasks() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.outcome = 'won' then
    -- The five-completed limit is deliberately not re-checked, as with Lost: it bounds active board work,
    -- and this card is leaving the board.
    update public.tasks
    set status = 'completed',
        completed_at = coalesce(new.outcome_at, now()),
        completed_by = null,
        completed_by_outcome_event_id = new.current_outcome_event_id
    where organization_id = new.organization_id
      and opportunity_id = new.id
      and status = 'open';

  elsif old.outcome = 'won' and new.outcome = 'open' and old.current_outcome_event_id is not null then
    update public.tasks
    set status = 'open', completed_at = null, completed_by = null, completed_by_outcome_event_id = null
    where organization_id = new.organization_id
      and opportunity_id = new.id
      and completed_by_outcome_event_id = old.current_outcome_event_id;
  end if;

  return null;
end;
$$;

revoke all on function private.opportunity_won_settles_tasks() from public, anon, authenticated;

create trigger opportunities_won_settles_tasks
after update of outcome on public.opportunities
for each row
when (old.outcome is distinct from new.outcome and (new.outcome = 'won' or old.outcome = 'won'))
execute function private.opportunity_won_settles_tasks();

-- Cards won before this rule existed: finish what was left open on them, dated at the win.
update public.tasks as task
set status = 'completed',
    completed_at = coalesce(opportunity.outcome_at, now()),
    completed_by = null,
    completed_by_outcome_event_id = opportunity.current_outcome_event_id
from public.opportunities as opportunity
where opportunity.organization_id = task.organization_id
  and opportunity.id = task.opportunity_id
  and opportunity.outcome = 'won'
  and task.status = 'open';
