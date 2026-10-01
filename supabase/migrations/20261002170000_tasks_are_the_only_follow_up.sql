-- Pipeline part C1: Tasks are the only follow-up.
--
-- An Opportunity used to carry a "next follow-up" date beside its Tasks, so two things could disagree about
-- when to chase a customer. The plan (docs/sales-pipeline-behavior-contract.md, § Ownership and visibility)
-- keeps only Tasks: every open card's date becomes an open Task on that day, then the date goes.
--
-- The board's default order becomes the Task order: overdue Task, due today, no Task, future Task. To read
-- that order a page at a time without working out every card's next Task first, each Opportunity keeps the
-- due date of its next open Task, kept in step by a trigger on `tasks` — the same shape as a deal's "next
-- activity date" in Pipedrive. Expected close becomes an alternate sort.

-- 1. Dates become Tasks -------------------------------------------------------------------------------------
--
-- Only open cards. A Lost card's Tasks are completed by the Lost action and a Won card's never follow it into
-- the Job, so a date on a decided card has nothing left to chase and is dropped with the column.
--
-- An Opportunity may hold at most five open Tasks. A card already at five cannot take a sixth, and quietly
-- dropping its date would lose a promise somebody made to a customer, so the whole change stops instead and
-- nothing is altered. A card that already has an open Task on that same day needs no second one.

do $$
declare
  full_cards integer;
begin
  select count(*) into full_cards
  from public.opportunities as opportunity
  where opportunity.outcome = 'open'
    and opportunity.next_follow_up_on is not null
    and not exists (
      select 1 from public.tasks as task
      where task.opportunity_id = opportunity.id
        and task.status = 'open'
        and task.due_on = opportunity.next_follow_up_on
    )
    and (
      select count(*) from public.tasks as task
      where task.opportunity_id = opportunity.id and task.status = 'open'
    ) >= 5;

  if full_cards > 0 then
    raise exception '% open opportunities have a follow-up date and already hold five open Tasks. Decide what happens to those dates before running this again.', full_cards;
  end if;
end;
$$;

-- The card's owner takes the Task when they may still see the Pipeline (the rule every Task assignee meets);
-- otherwise it is left unassigned rather than given to somebody who cannot see it. No alert is sent: nobody
-- was newly asked to do anything.
insert into public.tasks (organization_id, opportunity_id, title, assignee_user_id, due_on)
select
  opportunity.organization_id,
  opportunity.id,
  'Follow up',
  case when opportunity.owner_user_id is not null
            and private.member_has_permission(
              opportunity.organization_id, opportunity.owner_user_id, 'pipeline.view')
       then opportunity.owner_user_id end,
  opportunity.next_follow_up_on
from public.opportunities as opportunity
where opportunity.outcome = 'open'
  and opportunity.next_follow_up_on is not null
  and not exists (
    select 1 from public.tasks as task
    where task.opportunity_id = opportunity.id
      and task.status = 'open'
      and task.due_on = opportunity.next_follow_up_on
  );

-- 2. Each card keeps its next Task's date ------------------------------------------------------------------

alter table public.opportunities add column next_task_due_on date;

comment on column public.opportunities.next_task_due_on is
  'The earliest due date among this card''s open Tasks, or null when it has no open Task with a date. Written only by private.opportunity_sync_next_task, from the tasks table; the board orders by it.';

grant select (next_task_due_on) on table public.opportunities to authenticated;

update public.opportunities as opportunity
set next_task_due_on = next_task.due_on
from (
  select task.opportunity_id, min(task.due_on) as due_on
  from public.tasks as task
  where task.status = 'open'
  group by task.opportunity_id
) as next_task
where next_task.opportunity_id = opportunity.id
  and next_task.due_on is not null;

create function private.opportunity_sync_next_task()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  affected uuid[];
begin
  -- A Task that moved to another card changes both cards.
  if tg_op = 'INSERT' then
    affected := array[new.opportunity_id];
  elsif tg_op = 'DELETE' then
    affected := array[old.opportunity_id];
  else
    affected := array[old.opportunity_id, new.opportunity_id];
  end if;

  -- Written only when it really changed, so adding an undated Task or a later one touches nothing.
  update public.opportunities as opportunity
  set next_task_due_on = (
    select min(task.due_on)
    from public.tasks as task
    where task.organization_id = opportunity.organization_id
      and task.opportunity_id = opportunity.id
      and task.status = 'open'
  )
  where opportunity.id = any (affected)
    and opportunity.next_task_due_on is distinct from (
      select min(task.due_on)
      from public.tasks as task
      where task.organization_id = opportunity.organization_id
        and task.opportunity_id = opportunity.id
        and task.status = 'open'
    );

  return null;
end;
$$;

revoke all on function private.opportunity_sync_next_task() from public, anon, authenticated;

create trigger tasks_sync_next_task_on_insert
  after insert on public.tasks
  for each row execute function private.opportunity_sync_next_task();

create trigger tasks_sync_next_task_on_update
  after update of status, due_on, opportunity_id on public.tasks
  for each row
  when (
    old.status is distinct from new.status
    or old.due_on is distinct from new.due_on
    or old.opportunity_id is distinct from new.opportunity_id
  )
  execute function private.opportunity_sync_next_task();

create trigger tasks_sync_next_task_on_delete
  after delete on public.tasks
  for each row execute function private.opportunity_sync_next_task();

-- 3. Board indexes for the two new orders ------------------------------------------------------------------
--
-- One index serves all three Task phases: due on or before today, no dated Task (`is null`), and due later.
-- Cards with no dated Task are read longest-waiting first through opportunities_board_idx.

create index opportunities_board_task_idx
  on public.opportunities (organization_id, board_column, next_task_due_on, id)
  where outcome = 'open' and board_column <> 'request_closed';

create index opportunities_board_close_idx
  on public.opportunities (organization_id, board_column, expected_close_on, id)
  where outcome = 'open' and board_column <> 'request_closed';

-- 4. The board page --------------------------------------------------------------------------------------
--
-- Unchanged from 20261002120000 except: `next_follow_up_on` is replaced by `next_task_due_on`; the sorts
-- 'attention' (the Task order) and 'expected_close_on' are added; and `board_today` (today in the
-- organization's own timezone, worked out by the route) and `cursor_date` are new parameters.

drop function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid);

create function public.pipeline_board_page(
  target_organization_id uuid,
  target_stage text,
  page_limit integer default 25,
  sort_key text default 'attention',
  sort_direction text default 'desc',
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null,
  cursor_sort_key text default null,
  cursor_phase integer default null,
  cursor_timestamp timestamptz default null,
  cursor_value numeric default null,
  cursor_id uuid default null,
  board_today date default null,
  cursor_date date default null
) returns table (
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
  next_task_due_on date,
  task_id uuid,
  task_title text,
  task_due_on date,
  quote_id uuid,
  quote_status text,
  assessment_starts_at timestamptz,
  assessment_ends_at timestamptz,
  custom_stage_id uuid,
  quote_delivery_failed_at timestamptz,
  quote_delivery_failed_email text,
  quote_delivery_failure text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  phase integer;
  select_body text;
  stage_predicate text;
  filters text := '';
  keyset text;
  ordering text;
  fetched integer;
  remaining integer;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  -- One named logical column, the seven real stages, or one of this organization's custom stages. Written
  -- out rather than assembled from a caller's list, so 'assessment' is the only grouping that exists and no
  -- other combination is reachable. Every one is a value of `board_column`, the column a card is drawn in:
  -- its custom stage when somebody placed it in one, its real stage otherwise. So a protected column never
  -- shows a card that is sitting in a custom stage, and all of them read through the same indexes.
  if target_stage = 'assessment' then
    -- Spelled exactly as opportunities_board_assessment_group_idx spells it: the planner matches the two
    -- expressions before attempting a harder proof, and a mismatch here silently costs the index.
    stage_predicate :=
      $p$ and opportunity.board_column in
        ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed')$p$;
  elsif target_stage in (
    'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed',
    'quote_draft', 'quote_awaiting_response', 'quote_changes_requested'
  ) then
    stage_predicate := format(' and opportunity.board_column = %L', target_stage);
  elsif target_stage ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and exists (
          select 1
          from public.pipeline_custom_stages as custom_stage
          where custom_stage.organization_id = target_organization_id
            and custom_stage.id = target_stage::uuid
            and custom_stage.disabled_at is null
        ) then
    -- Through uuid and back, so the text compared is the one spelling `board_column` holds.
    stage_predicate := format(' and opportunity.board_column = %L', target_stage::uuid::text);
  else
    raise exception 'That is not a board column.' using errcode = 'invalid_parameter_value';
  end if;

  if sort_key not in ('attention', 'stage_entered_at', 'created_at', 'estimated_value', 'expected_close_on')
     or sort_direction not in ('asc', 'desc')
     or owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to sort or filter the board.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- "Overdue" and "due today" are questions about the contractor's calendar, which only the route knows.
  if sort_key = 'attention' and board_today is null then
    raise exception 'Sorting by Task needs today''s date.'
      using errcode = 'invalid_parameter_value';
  end if;

  if owner_filter = 'member' and filter_owner_user_id is null then
    raise exception 'Filtering by salesperson needs a salesperson.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat cards, so it is refused instead. The column a cursor belongs to is
  -- checked by the route, which is the only place that knows the logical-column vocabulary.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- One row over the asked-for page is how the caller detects there is more, so the cap is 50 plus one.
  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Asked once for the whole page. can_view_client is still called per row underneath, but only for a
  -- caller who lacks the blanket permission, so the ordinary page pays nothing for it.
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  -- Ordering by money is reading money. Withholding the amounts while handing over the ranking would
  -- give the column away one comparison at a time.
  if sort_key = 'estimated_value' and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.stage,
      opportunity.stage_entered_at,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.request_id,
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
      case when owner_is_teammate.yes then owner_profile.full_name end,
      case when owner_is_teammate.yes then owner_profile.avatar_url end,
      case when %L::boolean then opportunity.estimated_value end,
      opportunity.expected_close_on,
      opportunity.next_task_due_on,
      open_task.id,
      open_task.title,
      open_task.due_on,
      opportunity.quote_id,
      quote.status,
      assessment.starts_at,
      assessment.ends_at,
      opportunity.custom_stage_id,
      case when last_email.failure is not null then last_email.failed_at end,
      case when last_email.failure is not null and client_visible.allowed then last_email.recipient_email end,
      last_email.failure
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
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
    left join lateral (
      select task.id, task.title, task.due_on
      from public.tasks as task
      where task.organization_id = opportunity.organization_id
        and task.opportunity_id = opportunity.id
        and task.status = 'open'
      order by task.due_on nulls last, task.created_at, task.id
      limit 1
    ) as open_task on true
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.properties as property
      on property.id = opportunity.property_id
     and property.organization_id = opportunity.organization_id
    left join public.requests as request
      on request.id = opportunity.request_id
     and request.organization_id = opportunity.organization_id
    left join public.quotes as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    left join public.profiles as owner_profile
      on owner_profile.id = opportunity.owner_user_id
    left join public.assessments as assessment
      on assessment.request_id = opportunity.request_id
     and assessment.organization_id = opportunity.organization_id
    left join lateral (
      -- The quote's most recent email, and whether it failed. Asked only for a card still waiting on the
      -- customer, so no other column pays for it. A send to two addresses shares one moment, and the
      -- failed one is picked first: one address the quote never reached is enough to say so.
      select
        email.recipient_email,
        coalesce(email.delivery_outcome_at, email.updated_at) as failed_at,
        private.quote_email_delivery_failure(email.status, email.delivery_outcome) as failure
      from public.communication_delivery_intents as email
      where opportunity.stage = 'quote_awaiting_response'
        and email.organization_id = opportunity.organization_id
        and email.quote_id = opportunity.quote_id
        and email.quote_version_id is not null
        and email.channel = 'email'
      order by email.created_at desc,
        (private.quote_email_delivery_failure(email.status, email.delivery_outcome) is not null) desc,
        email.id desc
      limit 1
    ) as last_email on true
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
  $body$, caller_sees_money, caller_sees_clients, target_organization_id) || stage_predicate;

  -- Only the clauses this request actually needs. "Or the filter is null" reads the same and costs the
  -- index scan.
  if owner_filter = 'unassigned' then
    filters := filters || ' and opportunity.owner_user_id is null';
  elsif owner_filter = 'member' then
    filters := filters || format(' and opportunity.owner_user_id = %L', filter_owner_user_id);
  end if;

  -- Calendar boundaries are worked out in the organization's timezone before they get here, so this only
  -- ever sees two instants. The upper bound is exclusive: it is the first moment of the day after.
  if created_from is not null then
    filters := filters || format(' and opportunity.created_at >= %L', created_from);
  end if;
  if created_to is not null then
    filters := filters || format(' and opportunity.created_at < %L', created_to);
  end if;

  -- The Task order, in three phases read one after another until the page is full: 1 is a Task due today or
  -- earlier, oldest due first, so overdue comes before today; 2 is no dated Task, longest in this column
  -- first; 3 is a Task due later, soonest first. The direction does not apply: this is a work queue.
  if sort_key = 'attention' then
    phase := coalesce(cursor_phase, 1);
    if phase not in (1, 2, 3) then
      raise exception 'That page marker belongs to a different order.'
        using errcode = 'invalid_parameter_value';
    end if;

    remaining := resolved_limit;
    while phase <= 3 and remaining > 0 loop
      -- Only the phase the cursor was cut from pages past it; a later phase starts from its beginning.
      if phase = 1 then
        keyset := case when cursor_id is null or cursor_phase is distinct from 1 then '' else format(
          ' and (opportunity.next_task_due_on, opportunity.id) > (%L::date, %L::uuid)',
          cursor_date, cursor_id) end;
        return query execute select_body || filters
          || format(' and opportunity.next_task_due_on <= %L::date', board_today) || keyset
          || ' order by opportunity.next_task_due_on asc, opportunity.id asc'
          || format(' limit %s', remaining);
      elsif phase = 2 then
        keyset := case when cursor_id is null or cursor_phase is distinct from 2 then '' else format(
          ' and (opportunity.stage_entered_at, opportunity.id) > (%L::timestamptz, %L::uuid)',
          cursor_timestamp, cursor_id) end;
        return query execute select_body || filters
          || ' and opportunity.next_task_due_on is null' || keyset
          || ' order by opportunity.stage_entered_at asc, opportunity.id asc'
          || format(' limit %s', remaining);
      else
        keyset := case when cursor_id is null or cursor_phase is distinct from 3 then '' else format(
          ' and (opportunity.next_task_due_on, opportunity.id) > (%L::date, %L::uuid)',
          cursor_date, cursor_id) end;
        return query execute select_body || filters
          || format(' and opportunity.next_task_due_on > %L::date', board_today) || keyset
          || ' order by opportunity.next_task_due_on asc, opportunity.id asc'
          || format(' limit %s', remaining);
      end if;
      get diagnostics fetched = row_count;
      remaining := remaining - fetched;
      phase := phase + 1;
    end loop;
    return;
  end if;

  if sort_key in ('stage_entered_at', 'created_at') then
    -- Ties break the same way the sort runs, so the pair reads as one index range rather than as a
    -- filter over everything above it. This is also what keeps the grouped column's order globally
    -- correct: one keyset across all three assessment states, never three lists stitched together.
    if sort_direction = 'desc' then
      ordering := format(' order by opportunity.%1$I desc, opportunity.id desc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by opportunity.%1$I asc, opportunity.id asc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    end if;

    return query execute select_body || filters || keyset || ordering
      || format(' limit %s', resolved_limit);
    return;
  end if;

  -- Value and expected close sort the same way, phase by phase. Phase 1 is the cards that have one, in the
  -- caller's chosen direction; phase 2 is the ones that do not, always oldest id first, which is the order
  -- they already sit in.
  phase := coalesce(cursor_phase, 1);
  if phase not in (1, 2) then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  if phase = 1 then
    if sort_direction = 'desc' then
      ordering := format(' order by opportunity.%1$I desc, opportunity.id desc', sort_key);
      keyset := case
        when cursor_id is null then ''
        when sort_key = 'estimated_value' then format(
          ' and (opportunity.estimated_value, opportunity.id) < (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
        else format(
          ' and (opportunity.expected_close_on, opportunity.id) < (%1$L::date, %2$L::uuid)',
          cursor_date, cursor_id)
      end;
    else
      ordering := format(' order by opportunity.%1$I asc, opportunity.id asc', sort_key);
      keyset := case
        when cursor_id is null then ''
        when sort_key = 'estimated_value' then format(
          ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
        else format(
          ' and (opportunity.expected_close_on, opportunity.id) > (%1$L::date, %2$L::uuid)',
          cursor_date, cursor_id)
      end;
    end if;

    return query execute select_body || filters
      || format(' and opportunity.%I is not null', sort_key) || keyset || ordering
      || format(' limit %s', resolved_limit);
    get diagnostics fetched = row_count;

    -- The filled side is finished, so the rest of this page comes from the empty side, from its
    -- beginning. No card from that side can have been returned before this point, so there is nothing to
    -- page past.
    if fetched < resolved_limit then
      return query execute select_body || filters
        || format(' and opportunity.%I is null', sort_key)
        || ' order by opportunity.id asc'
        || format(' limit %s', resolved_limit - fetched);
    end if;
    return;
  end if;

  return query execute select_body || filters
    || format(' and opportunity.%I is null', sort_key)
    || case when cursor_id is null then ''
            else format(' and opportunity.id > %L::uuid', cursor_id) end
    || ' order by opportunity.id asc'
    || format(' limit %s', resolved_limit);
end;
$_$;

revoke all on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid, date, date) from public, anon;
grant execute on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid, date, date) to authenticated, service_role;

-- 5. The Brief's details lose the follow-up date ----------------------------------------------------------

drop function public.pipeline_update_opportunity_details(uuid, boolean, uuid, boolean, numeric, boolean, date, boolean, date);

create function public.pipeline_update_opportunity_details(
  target_opportunity_id uuid,
  set_owner boolean default false,
  new_owner_user_id uuid default null,
  set_value boolean default false,
  new_estimated_value numeric default null,
  set_expected_close boolean default false,
  new_expected_close_on date default null
) returns table (
  id uuid,
  owner_user_id uuid,
  estimated_value numeric,
  expected_close_on date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  target_organization_id uuid;
  target_quote_id uuid;
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
begin
  -- Definer rights skip row level security, so membership is checked here by hand rather than assumed.
  select opportunity.organization_id, opportunity.quote_id
  into target_organization_id, target_quote_id
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

  if set_value and target_quote_id is not null then
    raise exception 'A quote-backed opportunity''s value comes from the quote and cannot be edited here.'
      using errcode = 'check_violation';
  end if;

  return query
  update public.opportunities as opportunity
  set
    owner_user_id = case when set_owner then new_owner_user_id else opportunity.owner_user_id end,
    estimated_value = case when set_value then new_estimated_value else opportunity.estimated_value end,
    expected_close_on =
      case when set_expected_close then new_expected_close_on else opportunity.expected_close_on end
  where opportunity.id = target_opportunity_id
  returning
    opportunity.id,
    opportunity.owner_user_id,
    -- Nothing is returned to somebody who may not see money, not even the value they did not change.
    case when caller_sees_money then opportunity.estimated_value end,
    opportunity.expected_close_on,
    opportunity.updated_at;
end;
$$;

revoke all on function public.pipeline_update_opportunity_details(uuid, boolean, uuid, boolean, numeric, boolean, date) from public, anon;
grant execute on function public.pipeline_update_opportunity_details(uuid, boolean, uuid, boolean, numeric, boolean, date) to authenticated, service_role;

-- 6. The duplicate field goes ----------------------------------------------------------------------------

alter table public.opportunities drop column next_follow_up_on;
