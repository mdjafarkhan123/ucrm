-- Pipeline part C2: the inactivity warning reads its own progress clock.
--
-- A card used to turn red one day after it arrived in its column, whatever was happening with the customer.
-- The plan (docs/sales-pipeline-behavior-contract.md, § First-release board) keeps time in the column as
-- neutral context and warns only when nothing has really moved for that stage's number of days. That needs
-- a second clock: `stage_entered_at` restarts on a manual custom-stage move (ADR 0004, point 8), and the
-- plan says such a move is not progress.
--
-- `progress_at` restarts only on real progress: the stage changing because of a Request, Assessment, or
-- Quote action; an assessment being booked, moved, or completed; a quote version going out (UCRM's own
-- send or one marked as sent outside it); and a Task being completed. Owner, value, and date edits, Notes,
-- creating or reassigning a Task, and custom-stage moves leave it alone. Customer replies and logged calls
-- join in part C3. The board works out the warning itself from this and the stage's day count, so a card
-- never has to be rewritten just because time passed — the same shape as Pipedrive's "rotting" deals.

alter table public.opportunities add column progress_at timestamptz;

comment on column public.opportunities.progress_at is
  'When this card last made real progress: a real stage change, an assessment booked or completed, a quote version sent, or a Task completed. Set by private.opportunity_apply_stage and private.opportunity_record_progress only; the inactivity warning counts from here.';

grant select (progress_at) on table public.opportunities to authenticated;

-- Existing cards start from the latest real progress already on record: a real stage change (a custom
-- move's row has equal stages and does not count), a completed Task, or a published quote version. A card
-- with none of these has made no progress since it was created.
update public.opportunities as opportunity
set progress_at = greatest(
  opportunity.created_at,
  (select max(event.occurred_at)
     from public.opportunity_stage_events as event
     where event.opportunity_id = opportunity.id
       and event.from_stage is distinct from event.to_stage),
  (select max(task.completed_at)
     from public.tasks as task
     where task.organization_id = opportunity.organization_id
       and task.opportunity_id = opportunity.id
       and task.status = 'completed'),
  (select max(version.published_at)
     from public.quote_versions as version
     where opportunity.quote_id is not null
       and version.quote_id = opportunity.quote_id)
);

alter table public.opportunities
  alter column progress_at set default now(),
  alter column progress_at set not null;

-- 1. A real stage change is progress ----------------------------------------------------------------------
--
-- The 20261002100000 version with only the `progress_at` lines added.

create or replace function private.opportunity_apply_stage() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  resolved_stage text;
  request_row record;
  quote_status text;
begin
  if new.quote_id is not null then
    select quote.status into quote_status
    from public.quotes as quote
    where quote.id = new.quote_id and quote.organization_id = new.organization_id;

    resolved_stage := case quote_status
      when 'draft' then 'quote_draft'
      when 'awaiting_response' then 'quote_awaiting_response'
      when 'changes_requested' then 'quote_changes_requested'
      -- approved, declined, archived, converted: decided or parked, off the active board either way.
      else 'request_closed'
    end;
  elsif new.job_id is not null then
    -- A Direct job is closed from birth. It holds no place on the board, the same as any decided card.
    resolved_stage := 'request_closed';
  elsif new.request_id is null then
    -- A standalone Opportunity sits at the front of the board until a Request gives it real state.
    resolved_stage := 'new_request';
  else
    select
      request.status as status,
      assessment.id is not null as has_assessment,
      assessment.starts_at as starts_at,
      assessment.completed_at as completed_at
    into request_row
    from public.requests as request
    left join public.assessments as assessment
      on assessment.request_id = request.id
    where request.id = new.request_id
      and request.organization_id = new.organization_id;

    resolved_stage := private.request_pipeline_stage(
      request_row.status,
      coalesce(request_row.has_assessment, false),
      request_row.starts_at,
      request_row.completed_at
    );
  end if;

  new.stage := resolved_stage;

  -- `stage_entered_at` is when the card arrived in the column it is drawn in, so it restarts on a real
  -- stage change and on a move into, out of, or between custom stages. `progress_at` restarts only on the
  -- real change; anything else that writes it goes through private.opportunity_record_progress.
  if tg_op = 'INSERT' then
    new.stage_entered_at := coalesce(new.stage_entered_at, now());
    new.progress_at := coalesce(new.progress_at, now());
  elsif new.stage is distinct from old.stage then
    -- A real Request, Assessment, or Quote action always wins over where somebody placed the card: it
    -- goes to the protected stage that action established.
    new.custom_stage_id := null;
    new.stage_entered_at := now();
    new.progress_at := now();
  elsif new.custom_stage_id is distinct from old.custom_stage_id then
    new.stage_entered_at := now();
  else
    new.stage_entered_at := old.stage_entered_at;
  end if;

  return new;
end;
$$;

-- 2. Progress that does not change the stage -------------------------------------------------------------
--
-- One trigger function for the three tables. Each case names the cards it moved forward; only open cards
-- are touched, since a decided card has no warning to clear.

create function private.opportunity_record_progress() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  if tg_table_name = 'tasks' then
    update public.opportunities
    set progress_at = now()
    where id = new.opportunity_id
      and organization_id = new.organization_id
      and outcome = 'open';
  elsif tg_table_name = 'assessments' then
    update public.opportunities
    set progress_at = now()
    where request_id = new.request_id
      and organization_id = new.organization_id
      and outcome = 'open';
  elsif tg_table_name = 'quotes' then
    update public.opportunities
    set progress_at = now()
    where quote_id = new.id
      and organization_id = new.organization_id
      and outcome = 'open';
  end if;

  return null;
end;
$$;

revoke all on function private.opportunity_record_progress() from public, anon, authenticated;

-- Completing a Task. Creating, editing, reassigning, or deleting one is not progress.
create trigger tasks_record_opportunity_progress
  after update of status on public.tasks
  for each row
  when (old.status = 'open' and new.status = 'completed' and new.opportunity_id is not null)
  execute function private.opportunity_record_progress();

-- Booking, moving, or completing an assessment. Booking and completing also change the stage; moving an
-- already-booked visit does not, and is still real contact with the customer.
create trigger assessments_record_opportunity_progress
  after update of starts_at, completed_at on public.assessments
  for each row
  when (
    (new.starts_at is not null and old.starts_at is distinct from new.starts_at)
    or (new.completed_at is not null and old.completed_at is distinct from new.completed_at)
  )
  execute function private.opportunity_record_progress();

-- A quote version going out, by email or marked as sent outside UCRM. Sending a revision keeps the card in
-- Awaiting response, so this is the only thing that notices it.
create trigger quotes_record_opportunity_progress
  after update of current_published_version_id on public.quotes
  for each row
  when (
    new.current_published_version_id is not null
    and old.current_published_version_id is distinct from new.current_published_version_id
  )
  execute function private.opportunity_record_progress();

-- 3. The board page sends the progress clock ---------------------------------------------------------
--
-- Unchanged from 20261002170000 except the new `progress_at` column, returned last.

drop function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid, date, date);

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
  quote_delivery_failure text,
  progress_at timestamptz
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
      last_email.failure,
      opportunity.progress_at
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
