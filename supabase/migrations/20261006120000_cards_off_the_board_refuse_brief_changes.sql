-- Pipeline G2 follow-up: the Brief's commands refuse every card that has left the board, not only Won and Lost.
--
-- 20261006110000 closed the commands for a card with an outcome. Two kinds of card leave the board and keep
-- no outcome: a Request that became a Quote (its Quote has its own card), and a draft Quote archived before
-- it was sent (Abandoned before sending). Their stage resolves to `request_closed`, no screen opens their
-- Brief, and a Task started on one would sit on the Schedule with nowhere to finish it. The helper now
-- refuses those too, in one sentence that is true for all of them.

create or replace function private.pipeline_assert_card_open(target_opportunity_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (
    select 1
    from public.opportunities as opportunity
    where opportunity.id = target_opportunity_id
      and (opportunity.outcome <> 'open' or opportunity.stage = 'request_closed')
  ) then
    raise exception 'This card has left the board, so it can no longer be changed here.'
      using errcode = 'check_violation', hint = 'card_closed';
  end if;
end;
$$;
