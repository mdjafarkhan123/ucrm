-- Sales Pipeline, Part 2, item 4: the board summary answers for the filtered board, and carries money.
--
-- The column headings and the cards have to be describing the same set. Item 3 taught the column read to
-- filter; a summary that kept counting the whole board would put "New request 412" above eleven visible
-- cards. So the summary takes the same salesperson and created-date parameters the columns take, and the
-- board asks its one summary question once per board load rather than one count per column.
--
-- It also gains the column value total, which is why it stops being a security invoker function. Members
-- hold no privilege on opportunities.estimated_value at all (20260818232309 and 20260818233632), so an
-- invoker sum() would simply be refused. Definer means this function re-applies by hand every rule the
-- select policy would have applied, exactly as pipeline_board_page does:
--
--   tenant and access    the caller's own private.permitted_organizations('pipeline.view')
--   money                private.member_has_permission(..., 'pipeline.view_value'), or no total at all
--
-- Client visibility is deliberately not one of them. A member who cannot see a client still sees that
-- client's card on the board with its details blanked, so the card is still counted. Counting only the
-- clients somebody may read would make the heading disagree with the column beneath it.
--
-- A null total means "nobody has estimated anything here", which is not the same as zero: a single real
-- $0.00 estimate sums to 0 and is shown as money. The caller can tell the third case, "you may not see
-- money", apart from both, because /api/pipeline/summary answers can_view_value separately.
--
-- The statement is assembled the same way the column read is, for the same reason: an "or the filter is
-- null" clause costs the index scan. Every value is inlined with %L, which is quoting, not trust —
-- owner_filter is checked against a fixed list before it is used at all.

drop function if exists public.pipeline_stage_counts(uuid);

create function public.pipeline_stage_counts(
  target_organization_id uuid,
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null
)
returns table (stage_key text, open_count bigint, value_total numeric)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  filters text := '';
  counted text;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to filter the board.'
      using errcode = 'invalid_parameter_value';
  end if;

  if owner_filter = 'member' and filter_owner_user_id is null then
    raise exception 'Filtering by salesperson needs a salesperson.'
      using errcode = 'invalid_parameter_value';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  if owner_filter = 'unassigned' then
    filters := filters || ' and opportunity.owner_user_id is null';
  elsif owner_filter = 'member' then
    filters := filters || format(' and opportunity.owner_user_id = %L', filter_owner_user_id);
  end if;

  -- Calendar boundaries are worked out in the organization's timezone before they get here, so this only
  -- ever sees two instants, and the upper one is the first moment of the day after. The same two the
  -- columns are paging with, so the heading and the cards cannot drift apart.
  if created_from is not null then
    filters := filters || format(' and opportunity.created_at >= %L', created_from);
  end if;
  if created_to is not null then
    filters := filters || format(' and opportunity.created_at < %L', created_to);
  end if;

  counted := format($body$
    select
      opportunity.stage as stage_key,
      count(*) as open_count,
      case when %L::boolean then sum(opportunity.estimated_value) end as value_total
    from public.opportunities as opportunity
    -- Matches the partial board indexes exactly: same tenant, same predicate.
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
      and opportunity.stage <> 'request_closed'
  $body$, caller_sees_money, target_organization_id);

  -- Every protected stage is listed, so a column that filtered down to nothing still reports zero and
  -- keeps its heading, instead of going missing from the board.
  return query execute $head$
    select
      board_stage.stage_key,
      coalesce(counted.open_count, 0)::bigint,
      counted.value_total
    from unnest(array[
      'new_request',
      'assessment_unscheduled',
      'assessment_scheduled',
      'assessment_completed'
    ]) as board_stage(stage_key)
    left join (
  $head$ || counted || filters || $tail$
      group by opportunity.stage
    ) as counted on counted.stage_key = board_stage.stage_key
  $tail$;
end;
$function$;

revoke all on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz)
  from public;
revoke execute on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz)
  from anon;
grant execute on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz)
  to authenticated;
