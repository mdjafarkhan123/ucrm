-- Pipeline part D2: the board can be searched and filtered by lead source.
--
-- Search covers what the plan names: the card's title, the client's name and company, a contact's name,
-- the service address, any phone or email the client carries, and the Quote number. Requests have no
-- number in UCRM, so there is none to search. Lead source is the client's own `lead_source`.
--
-- Shape, decided with the performance-review design branch on 2026-10-01: no new index, no search column,
-- no read model. The board only ever reads one organization's OPEN cards, a working set that closes as it
-- is won or lost, and the page query already joins the client, the property, and the quote. So a search
-- is a filter over rows the board walks anyway, plus two index lookups per card for contacts and contact
-- methods (both already indexed on organization_id, client_id). The cost grows with open cards per
-- organization, not with clients.
--
-- One private function writes the filter for both the page and the counts, so a column's heading and the
-- cards under it can never be answering different questions.
--
-- A client the caller may not see cannot be found by name, address, phone, email, or lead source, and its
-- card carries no lead source: the same rule that already blanks those details on the card.

-- 1. The filter, written once ------------------------------------------------------------------------
--
-- Returns SQL for the caller to append. It names `opportunity`, `client`, `property`, `quote`, and
-- `client_visible`, which both callers join under those names. Every value is quoted here with %L.
--
-- `search_like` arrives as a finished pattern (%term%, with the term's own wildcards escaped by the
-- route). `search_digits` is the term's digits when it reads as a phone number, matched against the
-- stored digits-only form so "(555) 010-2030" finds "555-010-2030". `search_number` is the term when it
-- reads as a record number.

create function private.pipeline_board_filter_clause(
  search_like text,
  search_digits text,
  search_number bigint,
  lead_source_filter text
) returns text
language plpgsql
immutable
set search_path to 'pg_catalog'
as $_$
declare
  clause text := '';
  digits_match text := '';
  number_match text := '';
begin
  if search_like is not null and search_like <> '' then
    if search_digits ~ '^[0-9]{3,20}$' then
      digits_match := format(
        $d$ or (method.kind = 'phone' and method.normalized_value like %L)$d$,
        '%' || search_digits || '%');
    end if;
    if search_number is not null then
      number_match := format(' or quote.quote_number = %L::bigint', search_number);
    end if;

    clause := clause || format($s$
      and (
        opportunity.title ilike %1$L
        %3$s
        or (client_visible.allowed and (
          client.display_name ilike %1$L
          or client.company_name ilike %1$L
          or concat_ws(' ', property.address_line1, property.address_line2, property.city,
               property.state_region, property.postal_code) ilike %1$L
          or exists (
            select 1
            from public.client_contacts as contact
            where contact.organization_id = opportunity.organization_id
              and contact.client_id = opportunity.client_id
              and concat_ws(' ', contact.first_name, contact.last_name) ilike %1$L
          )
          or exists (
            select 1
            from public.client_contact_methods as method
            where method.organization_id = opportunity.organization_id
              and method.client_id = opportunity.client_id
              and (method.value ilike %1$L %2$s)
          )
        ))
      )$s$, search_like, digits_match, number_match);
  end if;

  if lead_source_filter is not null and lead_source_filter <> '' then
    clause := clause || format(
      ' and client_visible.allowed and client.lead_source = %L', lead_source_filter);
  end if;

  return clause;
end;
$_$;

revoke all on function private.pipeline_board_filter_clause(text, text, bigint, text) from public, anon, authenticated;

-- 2. The board page takes the two filters and sends the lead source ----------------------------------
--
-- Unchanged from 20261002180000 except the four new arguments, the filter clause, and the new
-- `client_lead_source` column, returned last. The old signature is dropped rather than left as an
-- overload; a call that names only the old arguments still resolves to this one.

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
  cursor_date date default null,
  search_like text default null,
  search_digits text default null,
  search_number bigint default null,
  lead_source_filter text default null
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
  progress_at timestamptz,
  client_lead_source text
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
      opportunity.progress_at,
      case when client_visible.allowed then client.lead_source end
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

  -- Search and lead source, in the same words the column headings count with.
  filters := filters || private.pipeline_board_filter_clause(
    search_like, search_digits, search_number, lead_source_filter);

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

revoke all on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid, date, date, text, text, bigint, text) from public, anon;
grant execute on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid, date, date, text, text, bigint, text) to authenticated, service_role;

-- 3. The headings count the same filtered set --------------------------------------------------------
--
-- Unchanged from 20261001220000 except the four new arguments. The client, property, and quote are joined
-- only when a search or a lead source is asked for, so the board's ordinary opening count still reads the
-- opportunities index alone.

drop function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz);

create function public.pipeline_stage_counts(
  target_organization_id uuid,
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null,
  search_like text default null,
  search_digits text default null,
  search_number bigint default null,
  lead_source_filter text default null
) returns table (stage_key text, open_count bigint, value_total numeric)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  filters text := '';
  record_filter text;
  joins text := '';
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

  -- Search and lead source read the client, the property, and the quote, under the names the board page
  -- joins them by. Joined only when asked for.
  record_filter := private.pipeline_board_filter_clause(
    search_like, search_digits, search_number, lead_source_filter);
  if record_filter <> '' then
    joins := format($joins$
    cross join lateral (
      select
        %L::boolean
        or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.properties as property
      on property.id = opportunity.property_id
     and property.organization_id = opportunity.organization_id
    left join public.quotes as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    $joins$, private.member_has_permission(target_organization_id, caller_id, 'customers.view'));
    filters := filters || record_filter;
  end if;

  counted := format($body$
    select
      opportunity.board_column as stage_key,
      count(*) as open_count,
      case when %L::boolean then sum(opportunity.estimated_value) end as value_total
    from public.opportunities as opportunity
    %s
    -- Matches the partial board indexes exactly: same tenant, same predicate.
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
      and opportunity.board_column <> 'request_closed'
  $body$, caller_sees_money, joins, target_organization_id);

  -- Every column is listed — the seven protected stages and each custom stage that is switched on, by its
  -- id — so one that filtered down to nothing still reports zero and keeps its heading, instead of going
  -- missing from the board. A card counts under the column it is drawn in, never under both.
  return query execute format($head$
    select
      board_stage.stage_key,
      coalesce(counted.open_count, 0)::bigint,
      counted.value_total
    from (
      select unnest(array[
        'new_request',
        'assessment_unscheduled',
        'assessment_scheduled',
        'assessment_completed',
        'quote_draft',
        'quote_awaiting_response',
        'quote_changes_requested'
      ])
      union all
      select custom_stage.id::text
      from public.pipeline_custom_stages as custom_stage
      where custom_stage.organization_id = %L
        and custom_stage.disabled_at is null
    ) as board_stage(stage_key)
    left join (
  $head$, target_organization_id) || counted || filters || $tail$
      group by opportunity.board_column
    ) as counted on counted.stage_key = board_stage.stage_key
  $tail$;
end;
$_$;

revoke all on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz, text, text, bigint, text) from public, anon;
grant execute on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz, text, text, bigint, text) to authenticated, service_role;
