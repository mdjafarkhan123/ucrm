-- Pipeline part G1: three slow spots found by measuring a 20,000-open-card company.
-- Evidence: docs/sales-pipeline-performance-verification.md
--
-- 1. A member who may only see the clients they are assigned to. The board, the column headings, the lead
--    source list, and Sales Outcomes asked `private.can_view_client` once for every card, and several
--    times for every card they drew. Each call re-plans three nested lookups (about 0.5 ms), so one column
--    took 115 ms instead of 7, a search 2 to 10 seconds, and the lead source list 10 seconds. The rule is
--    the same one, asked once per request: each card is checked against
--    `private.current_user_assigned_client_ids()`, the set the clients read policy already uses
--    (20260924210000). A member belongs to one organization, and the `permitted_organizations` gate at the
--    top of each function has already proven it is this one, so no part of the rule is dropped.
--
-- 2. Search. The contact-name and contact-method lookups named the organization only through the card,
--    so the planner hashed them over every organization's contacts: 57,000 rows read for a 2,000-card
--    company, growing with the whole platform instead of with the company searching. They now name the
--    organization directly and read that company's rows only.
--
-- 3. The Conversion report had the same fault on Quotes, fixed the same way.
--
-- No behavior changes: the same cards, names, and totals come back for every member.

-- 1. Search names the organization itself ------------------------------------------------------------

drop function private.pipeline_board_filter_clause(text, text, bigint, text);

CREATE FUNCTION private.pipeline_board_filter_clause(search_like text, search_digits text, search_number bigint, lead_source_filter text, target_organization_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
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
            where contact.organization_id = %4$L
              and contact.client_id = opportunity.client_id
              and concat_ws(' ', contact.first_name, contact.last_name) ilike %1$L
          )
          or exists (
            select 1
            from public.client_contact_methods as method
            where method.organization_id = %4$L
              and method.client_id = opportunity.client_id
              and (method.value ilike %1$L %2$s)
          )
        ))
      )$s$, search_like, digits_match, number_match, target_organization_id);
  end if;

  if lead_source_filter is not null and btrim(lead_source_filter) <> '' then
    clause := clause || format(
      ' and client_visible.allowed and lower(btrim(client.lead_source)) = lower(btrim(%L))',
      lead_source_filter);
  end if;

  return clause;
end;
$function$;

revoke all on function private.pipeline_board_filter_clause(text, text, bigint, text, uuid) from public, anon, authenticated;

-- 2. The four reads, each asking the client rule once -------------------------------------------------

CREATE OR REPLACE FUNCTION public.pipeline_board_page(target_organization_id uuid, target_stage text, page_limit integer DEFAULT 25, sort_key text DEFAULT 'attention'::text, sort_direction text DEFAULT 'desc'::text, owner_filter text DEFAULT 'all'::text, filter_owner_user_id uuid DEFAULT NULL::uuid, created_from timestamp with time zone DEFAULT NULL::timestamp with time zone, created_to timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_sort_key text DEFAULT NULL::text, cursor_phase integer DEFAULT NULL::integer, cursor_timestamp timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_value numeric DEFAULT NULL::numeric, cursor_id uuid DEFAULT NULL::uuid, board_today date DEFAULT NULL::date, cursor_date date DEFAULT NULL::date, search_like text DEFAULT NULL::text, search_digits text DEFAULT NULL::text, search_number bigint DEFAULT NULL::bigint, lead_source_filter text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, title text, stage text, stage_entered_at timestamp with time zone, outcome text, created_at timestamp with time zone, request_id uuid, request_status text, client_id uuid, client_display_name text, client_company_name text, property_id uuid, property_label text, property_address_line1 text, property_city text, property_state_region text, property_postal_code text, owner_user_id uuid, owner_full_name text, owner_avatar_url text, estimated_value numeric, expected_close_on date, next_task_due_on date, task_id uuid, task_title text, task_due_on date, quote_id uuid, quote_status text, assessment_starts_at timestamp with time zone, assessment_ends_at timestamp with time zone, custom_stage_id uuid, quote_delivery_failed_at timestamp with time zone, quote_delivery_failed_email text, quote_delivery_failure text, progress_at timestamp with time zone, client_lead_source text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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

  -- Every card ('all', for the table), one named logical column, the seven real stages, or one of this
  -- organization's custom stages. Written
  -- out rather than assembled from a caller's list, so 'assessment' is the only grouping that exists and no
  -- other combination is reachable. Every one is a value of `board_column`, the column a card is drawn in:
  -- its custom stage when somebody placed it in one, its real stage otherwise. So a protected column never
  -- shows a card that is sitting in a custom stage, and all of them read through the same indexes.
  if target_stage = 'all' then
    -- The table view: every card the board draws, in one list. Spelled exactly as the partial predicate
    -- of the opportunities_board_all_* indexes, so the planner matches it and stops at the page.
    stage_predicate := $p$ and opportunity.board_column <> 'request_closed'$p$;
  elsif target_stage = 'assessment' then
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
  -- Asked once for the whole page. A caller without it is checked against the set of clients they are
  -- assigned to, read once per query rather than once per card.
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
      -- A teammate who never typed a name is shown by sign-in email, as the owner menu shows them; only an
      -- owner who has left the team comes back without a name. The email is looked up only for the
      -- unnamed, one primary-key read each.
      case when owner_is_teammate.yes then coalesce(
        nullif(btrim(owner_profile.full_name), ''),
        (select owner_account.email::text from auth.users as owner_account
          where owner_account.id = opportunity.owner_user_id)
      ) end,
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
        or opportunity.client_id in (select private.current_user_assigned_client_ids()) as allowed
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
    search_like, search_digits, search_number, lead_source_filter, target_organization_id);

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
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_stage_counts(target_organization_id uuid, owner_filter text DEFAULT 'all'::text, filter_owner_user_id uuid DEFAULT NULL::uuid, created_from timestamp with time zone DEFAULT NULL::timestamp with time zone, created_to timestamp with time zone DEFAULT NULL::timestamp with time zone, search_like text DEFAULT NULL::text, search_digits text DEFAULT NULL::text, search_number bigint DEFAULT NULL::bigint, lead_source_filter text DEFAULT NULL::text)
 RETURNS TABLE(stage_key text, open_count bigint, value_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    search_like, search_digits, search_number, lead_source_filter, target_organization_id);
  if record_filter <> '' then
    joins := format($joins$
    cross join lateral (
      select
        %L::boolean
        or opportunity.client_id in (select private.current_user_assigned_client_ids()) as allowed
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
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_lead_sources(target_organization_id uuid)
 RETURNS TABLE(lead_source text, open_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  sees_every_client boolean;
begin
  -- The same rule the board page applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  sees_every_client :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  return query
    select
      mode() within group (order by btrim(client.lead_source)) as lead_source,
      count(*)::bigint as open_count
    from public.opportunities as opportunity
    join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    -- Matches the partial board indexes: same tenant, same predicate.
    where opportunity.organization_id = target_organization_id
      and opportunity.outcome = 'open'
      and opportunity.board_column <> 'request_closed'
      and btrim(coalesce(client.lead_source, '')) <> ''
      and (sees_every_client
           or opportunity.client_id in (select private.current_user_assigned_client_ids()))
    group by lower(btrim(client.lead_source))
    order by 2 desc, 1
    limit 100;
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_outcome_page(target_organization_id uuid, outcome_type text, page_limit integer DEFAULT 25, sort_key text DEFAULT 'outcome_at'::text, sort_direction text DEFAULT 'desc'::text, outcome_from timestamp with time zone DEFAULT NULL::timestamp with time zone, outcome_to timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_sort_key text DEFAULT NULL::text, cursor_phase integer DEFAULT NULL::integer, cursor_timestamp timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_numeric numeric DEFAULT NULL::numeric, cursor_text text DEFAULT NULL::text, cursor_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, title text, outcome text, created_at timestamp with time zone, outcome_at timestamp with time zone, client_id uuid, client_display_name text, client_company_name text, estimated_value numeric, source_kind text, quote_id uuid, quote_number integer, lost_reason text, lost_note text, customer_declined boolean, customer_message text, customer_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  select_body text;
  filters text := '';
  keyset text;
  ordering text;
  sort_expr text;
  phase integer;
  fetched integer;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if outcome_type not in ('won', 'lost', 'direct_job') then
    raise exception 'That is not a Sales Outcomes type.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_key not in ('title', 'client', 'created', 'outcome_at', 'total')
     or sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a way to sort Sales Outcomes.' using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat rows.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  if sort_key = 'total' and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;
  if sort_key = 'client' and not caller_sees_clients then
    raise exception 'You do not have access to client names on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.outcome_at,
      opportunity.client_id,
      case when client_visible.allowed then client.display_name end,
      case when client_visible.allowed then client.company_name end,
      case when %L::boolean then opportunity.estimated_value end,
      case
        when opportunity.job_id is not null then 'job'
        when opportunity.quote_id is not null then 'quote'
        else 'request'
      end,
      opportunity.quote_id,
      quote.quote_number,
      outcome_event.reason,
      outcome_event.note,
      -- The customer said no, as opposed to the team giving up on it. Their words stay beside the reason.
      opportunity.outcome = 'lost' and quote.decision is not distinct from 'declined',
      case when opportunity.outcome = 'lost' and quote.decision = 'declined' then quote.decision_note end,
      -- What they picked when they declined online. A decline staff recorded by phone has none.
      case when opportunity.outcome = 'lost' and quote.decision = 'declined' then customer_answer.customer_reason end
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
        or opportunity.client_id in (select private.current_user_assigned_client_ids()) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.quotes as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    left join public.quote_decisions as customer_answer
      on customer_answer.organization_id = quote.organization_id
     and customer_answer.quote_id = quote.id
     and customer_answer.is_current
    left join public.opportunity_outcome_events as outcome_event
      on outcome_event.id = opportunity.current_outcome_event_id
     and outcome_event.organization_id = opportunity.organization_id
     and outcome_event.event_type = 'lost'
    where opportunity.organization_id = %L
      and opportunity.outcome_kind = %L
  $body$, caller_sees_money, caller_sees_clients, target_organization_id, outcome_type);

  if outcome_from is not null then
    filters := filters || format(' and opportunity.outcome_at >= %L', outcome_from);
  end if;
  if outcome_to is not null then
    filters := filters || format(' and opportunity.outcome_at < %L', outcome_to);
  end if;

  -- Total pages in two phases, the same way the board's value sort does: a null estimate cannot sit in a
  -- keyset row comparison, so the estimated rows and the unestimated ones are two separate ordered reads
  -- rather than one NULLS LAST that a cursor could not resume.
  if sort_key = 'total' then
    phase := coalesce(cursor_phase, 1);
    if phase not in (1, 2) then
      raise exception 'That page marker belongs to a different order.'
        using errcode = 'invalid_parameter_value';
    end if;

    if phase = 1 then
      if sort_direction = 'desc' then
        ordering := ' order by opportunity.estimated_value desc, opportunity.id desc';
        keyset := case
          when cursor_id is null then ''
          else format(
            ' and (opportunity.estimated_value, opportunity.id) < (%1$L::numeric, %2$L::uuid)',
            cursor_numeric, cursor_id)
        end;
      else
        ordering := ' order by opportunity.estimated_value asc, opportunity.id asc';
        keyset := case
          when cursor_id is null then ''
          else format(
            ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
            cursor_numeric, cursor_id)
        end;
      end if;

      return query execute select_body || filters
        || ' and opportunity.estimated_value is not null' || keyset || ordering
        || format(' limit %s', resolved_limit);
      get diagnostics fetched = row_count;

      if fetched < resolved_limit then
        return query execute select_body || filters
          || ' and opportunity.estimated_value is null'
          || ' order by opportunity.id asc'
          || format(' limit %s', resolved_limit - fetched);
      end if;
      return;
    end if;

    return query execute select_body || filters
      || ' and opportunity.estimated_value is null'
      || case when cursor_id is null then ''
              else format(' and opportunity.id > %L::uuid', cursor_id) end
      || ' order by opportunity.id asc'
      || format(' limit %s', resolved_limit);
    return;
  end if;

  -- Every other sort is a single ordered read. Title, Created and Outcome date are never null; Client can
  -- be null only when the backing client row itself has been removed, which NULLS LAST is enough for --
  -- this is a report column, not money, and that edge is rare enough not to earn Total's two-phase split.
  sort_expr := case sort_key
    when 'title' then 'opportunity.title'
    when 'client' then 'client.display_name'
    when 'created' then 'opportunity.created_at'
    else 'opportunity.outcome_at'
  end;

  if sort_key in ('title', 'client') then
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc nulls last, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) < (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc nulls last, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) > (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    end if;
  else
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    end if;
  end if;

  return query execute select_body || filters || keyset || ordering
    || format(' limit %s', resolved_limit);
end;
$function$;

-- 3. The Conversion report reads one organization's Quotes -------------------------------------------

-- Its "Quote with no Request behind it" test named the organization only through the card, so every
-- organization's Quotes were hashed (62,700 rows for an 8,300-card company).

CREATE OR REPLACE FUNCTION public.pipeline_conversion_report(target_organization_id uuid, report_from timestamp with time zone DEFAULT NULL::timestamp with time zone, report_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_every_client boolean;
  request_totals jsonb;
  quote_totals jsonb;
  sources jsonb;
  stages jsonb;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Lead source is the client's own detail. The board blanks it on a card whose client the member may not
  -- see; a breakdown cannot be blanked row by row, so it is given only to a member who sees every client.
  caller_sees_every_client :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  -- Each piece of work created in the window, with its result read across the Request and its Quote.
  with work as (
    select
      card.request_id is not null as is_request,
      card.client_id,
      -- "Quoted" means a Quote that was not abandoned before sending.
      quote_card.id is not null
        and not (quote_card.outcome = 'open' and quote_card.stage = 'request_closed') as quoted,
      case
        when card.outcome = 'won' or quote_card.outcome = 'won' then 'won'
        when card.stage <> 'request_closed'
          or (quote_card.outcome = 'open' and quote_card.stage <> 'request_closed') then 'open'
        when card.outcome = 'lost' or quote_card.outcome = 'lost' then 'lost'
        else 'closed'
      end as result,
      case
        when card.outcome = 'won' then card.estimated_value
        when quote_card.outcome = 'won' then quote_card.estimated_value
      end as won_value
    from public.opportunities as card
    left join public.quotes as quote
      on quote.organization_id = card.organization_id
     and quote.request_id = card.request_id
    left join public.opportunities as quote_card
      on quote_card.organization_id = quote.organization_id
     and quote_card.quote_id = quote.id
    where card.organization_id = target_organization_id
      and card.job_id is null
      and (
        card.request_id is not null
        -- A Quote with no Request behind it, unless it was abandoned before sending.
        or (card.quote_id is not null
            and not (card.outcome = 'open' and card.stage = 'request_closed')
            and not exists (
              select 1 from public.quotes as own_quote
              where own_quote.organization_id = target_organization_id
                and own_quote.id = card.quote_id
                and own_quote.request_id is not null
            ))
      )
      and (report_from is null or card.created_at >= report_from)
      and (report_to is null or card.created_at < report_to)
  ),
  by_source as (
    select
      mode() within group (order by btrim(client.lead_source)) as lead_source,
      count(*) as total,
      count(*) filter (where work.result = 'won') as won,
      count(*) filter (where work.result = 'lost') as lost,
      count(*) filter (where work.result = 'closed') as closed,
      count(*) filter (where work.result = 'open') as still_open,
      sum(work.won_value) as won_value
    from work
    join public.clients as client
      on client.organization_id = target_organization_id and client.id = work.client_id
    where caller_sees_every_client
    group by lower(btrim(coalesce(client.lead_source, '')))
  )
  select
    (
      select jsonb_build_object(
        'total', count(*),
        'quoted', count(*) filter (where work.quoted),
        'won', count(*) filter (where work.result = 'won'),
        'lost', count(*) filter (where work.result = 'lost'),
        'closed', count(*) filter (where work.result = 'closed'),
        'open', count(*) filter (where work.result = 'open'),
        'open_unquoted', count(*) filter (where work.result = 'open' and not work.quoted)
      )
      from work
      where work.is_request
    ),
    (
      -- Free text, so the list is capped; the busiest sources are the ones worth reading.
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'lead_source', nullif(top.lead_source, ''),
          'total', top.total,
          'won', top.won,
          'lost', top.lost,
          'closed', top.closed,
          'open', top.still_open
        ) || case when caller_sees_money
               then jsonb_build_object('won_value', top.won_value) else '{}'::jsonb end
        order by top.total desc, top.lead_source), '[]'::jsonb)
      from (
        select * from by_source order by by_source.total desc, by_source.lead_source limit 50
      ) as top
    )
  into request_totals, sources;

  -- Per-Quote win rate: every Quote card created in the window, whether or not a Request came first.
  select jsonb_build_object(
    'total', count(*),
    'won', count(*) filter (where card.outcome = 'won'),
    'lost', count(*) filter (where card.outcome = 'lost'),
    'open', count(*) filter (where card.outcome = 'open' and card.stage <> 'request_closed'),
    'abandoned', count(*) filter (where card.outcome = 'open' and card.stage = 'request_closed')
  )
  into quote_totals
  from public.opportunities as card
  where card.organization_id = target_organization_id
    and card.quote_id is not null
    and (report_from is null or card.created_at >= report_from)
    and (report_to is null or card.created_at < report_to);

  -- Time in stage. Each stage event is an arrival in a column: a custom stage when it names one, the
  -- built-in stage otherwise (ADR 0004: a row with equal stages is a custom move). The stay ends at the
  -- card's next arrival, or runs to now when the card is still there. A card that comes back to a stage
  -- adds to its own time there, so each card counts once per stage (HubSpot's cumulative time in stage).
  with arrivals as (
    select
      event.opportunity_id,
      event.to_stage,
      event.to_custom_stage_id,
      event.occurred_at,
      event.is_undo,
      lead(event.is_undo) over card_history as taken_back
    from public.opportunity_stage_events as event
    join public.opportunities as card
      on card.organization_id = event.organization_id and card.id = event.opportunity_id
    where event.organization_id = target_organization_id
      and (report_from is null or card.created_at >= report_from)
      and (report_to is null or card.created_at < report_to)
    window card_history as (partition by event.opportunity_id order by event.occurred_at, event.id)
  ),
  stays as (
    select
      arrivals.opportunity_id,
      arrivals.to_stage,
      arrivals.to_custom_stage_id,
      arrivals.occurred_at,
      lead(arrivals.occurred_at) over (
        partition by arrivals.opportunity_id order by arrivals.occurred_at
      ) as left_at
    from arrivals
    -- An Undo and the move it took back never happened as far as a report is concerned.
    where not arrivals.is_undo and not coalesce(arrivals.taken_back, false)
  ),
  per_card as (
    select
      stays.to_stage,
      stays.to_custom_stage_id,
      sum(extract(epoch from (coalesce(stays.left_at, now()) - stays.occurred_at))) / 86400.0 as days,
      bool_or(stays.left_at is null) as still_there
    from stays
    where stays.to_stage <> 'request_closed'
    group by stays.opportunity_id, stays.to_stage, stays.to_custom_stage_id
  ),
  per_stage as (
    select
      case when per_card.to_custom_stage_id is null then per_card.to_stage end as stage,
      per_card.to_custom_stage_id as custom_stage_id,
      count(*) as cards,
      count(*) filter (where per_card.still_there) as still_there,
      percentile_cont(0.5) within group (order by per_card.days) as median_days,
      avg(per_card.days) as average_days
    from per_card
    group by 1, 2
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'stage', per_stage.stage,
      'custom_stage_id', per_stage.custom_stage_id,
      'name', custom.name,
      'section', custom.section,
      'after_stage', custom.after_stage,
      'position', custom.position,
      'disabled', custom.disabled_at is not null,
      'cards', per_stage.cards,
      'still_there', per_stage.still_there,
      'median_days', round(per_stage.median_days::numeric, 1),
      'average_days', round(per_stage.average_days::numeric, 1)
    )), '[]'::jsonb)
  into stages
  from per_stage
  left join public.pipeline_custom_stages as custom
    on custom.organization_id = target_organization_id and custom.id = per_stage.custom_stage_id;

  return jsonb_build_object(
    'requests', request_totals,
    'quotes', quote_totals,
    'sources', sources,
    'stages', stages,
    'can_view_sources', caller_sees_every_client,
    'can_view_value', caller_sees_money
  );
end;
$function$;
