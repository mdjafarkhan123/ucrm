-- Pipeline upgrade B4: a quote email that fails after it was sent stays visible.
--
-- B3 made dropping a Draft on Awaiting response really send the quote. The email can still fail later: the
-- address bounces, the customer's mail server refuses it, or our own sender cancels it before it leaves.
-- Communications already records every one of those on the email itself, and the inbox shows it. The
-- Pipeline never heard, so a card sat in Awaiting response for a customer who had received nothing.
--
-- The historical send is not rewritten: the quote stays sent and the card stays where it is. What changes:
--
--   * the board page says, for a card in Awaiting response, whether the quote's latest email failed;
--   * the moment an email turns failed, the quote's history gets a line and one teammate gets one alert.
--
-- "Failed" is read from the email every time, never stored a second time, so sending the quote again to a
-- working address clears the card by itself.

-- 1. One definition of a failed quote email -------------------------------------------------------------------

-- Null when the email has not failed. A complaint is not a failure: the customer received the quote. A
-- cancelled email never left, whatever the reason, so the customer has nothing.
create or replace function private.quote_email_delivery_failure(email_status text, email_delivery_outcome text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when email_delivery_outcome = 'hard_bounce' then 'bounced'
    when email_delivery_outcome = 'soft_bounce' then 'not_accepted'
    when email_delivery_outcome = 'blocked' then 'blocked'
    when email_status = 'cancelled' then 'not_sent'
  end;
$$;

revoke all on function private.quote_email_delivery_failure(text, text) from public, anon, authenticated;

comment on function private.quote_email_delivery_failure(text, text) is
  'Pipeline B4. Why a quote email did not reach the customer (bounced, not_accepted, blocked, not_sent), or null when it has not failed. Read by the board and by the alert trigger so the two always agree.';

-- 2. The alert kind --------------------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check check (kind = any (array[
  'website_inquiry.received', 'website_inquiry.customer_replied', 'invoice.paid_online',
  'invoice.online_payment_failed', 'invoice.online_overpayment', 'quote.deposit_paid_online',
  'quote.deposit_payment_failed', 'quote.deposit_overpaid', 'invoice.online_refund_failed',
  'invoice.payment_disputed', 'quote.deposit_refund_failed', 'quote.deposit_disputed',
  'review.private_feedback', 'quote.delivery_failed'
]));

-- 3. History line and alert, once, when a quote email turns failed -----------------------------------------

create or replace function private.quote_email_delivery_failure_alert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  failure text := private.quote_email_delivery_failure(new.status, new.delivery_outcome);
  quote_number integer;
  quote_status text;
  client_name text;
  card_owner uuid;
  recipient uuid;
  sentence text;
begin
  -- Only the first turn into failed. A soft bounce that later hardens has already been said.
  if failure is null
     or private.quote_email_delivery_failure(old.status, old.delivery_outcome) is not null then
    return new;
  end if;

  select quote.quote_number, quote.status, nullif(btrim(client.display_name), '')
  into quote_number, quote_status, client_name
  from public.quotes as quote
  left join public.clients as client
    on client.organization_id = quote.organization_id and client.id = quote.client_id
  where quote.organization_id = new.organization_id and quote.id = new.quote_id;
  if not found then
    return new;
  end if;

  sentence := 'The quote email to ' || left(new.recipient_email, 120) || case failure
    when 'bounced' then ' bounced. That address does not accept mail.'
    when 'not_accepted' then ' was not accepted by their mailbox.'
    when 'blocked' then ' was blocked by their mail server.'
    else ' could not be sent.'
  end;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    new.organization_id, 'quote', new.quote_id, 'quote.email_delivery_failed', sentence, null,
    jsonb_build_object(
      'delivery_intent_id', new.id,
      'quote_version_id', new.quote_version_id,
      'recipient_email', new.recipient_email,
      'failure', failure
    )
  );

  -- A quote the customer has since answered, or that was archived, has nobody left to chase.
  if quote_status <> 'awaiting_response' then
    return new;
  end if;

  select opportunity.owner_user_id into card_owner
  from public.opportunities as opportunity
  where opportunity.organization_id = new.organization_id
    and opportunity.quote_id = new.quote_id
    and opportunity.outcome = 'open';

  -- The card's owner is responsible for it. An unassigned card falls to whoever sent the email, and
  -- failing that to the account owner, so a failed quote is never something nobody was told about.
  select membership.user_id into recipient
  from public.organization_members as membership
  where membership.organization_id = new.organization_id
    and membership.status = 'active'
    and (membership.user_id in (card_owner, new.created_by) or membership.role = 'owner')
  order by
    (membership.user_id is not distinct from card_owner) desc,
    (membership.user_id is not distinct from new.created_by) desc,
    membership.user_id
  limit 1;
  if recipient is null then
    return new;
  end if;

  -- In the bell only: the plan asks for an in-app alert, and the person is not emailed about an email.
  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key, email_state
  ) values (
    new.organization_id, recipient, 'quote.delivery_failed', 'quote', new.quote_id,
    left('Quote #' || quote_number || ' did not reach ' || coalesce(client_name, 'the customer'), 200),
    sentence || ' Check the address and send the quote again.',
    'quote_delivery_failed:' || new.id,
    'not_needed'
  )
  on conflict (organization_id, user_id, source_key) do nothing;

  return new;
end;
$$;

revoke all on function private.quote_email_delivery_failure_alert() from public, anon, authenticated;

create trigger communication_delivery_intents_quote_delivery_failed
after update of status, delivery_outcome on public.communication_delivery_intents
for each row
when (
  new.channel = 'email'
  and new.quote_version_id is not null
  and (new.status is distinct from old.status or new.delivery_outcome is distinct from old.delivery_outcome)
)
execute function private.quote_email_delivery_failure_alert();

-- 4. The board page carries the failure ---------------------------------------------------------------------
--
-- Three more columns, so the function is dropped and made again; everything else in it is unchanged from
-- 20261001220000. The recipient address follows the same rule as the client's name: hidden from a member
-- who may not see that client.

drop function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid);

create function public.pipeline_board_page(
  target_organization_id uuid,
  target_stage text,
  page_limit integer default 25,
  sort_key text default 'stage_entered_at',
  sort_direction text default 'desc',
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null,
  cursor_sort_key text default null,
  cursor_phase integer default null,
  cursor_timestamp timestamptz default null,
  cursor_value numeric default null,
  cursor_id uuid default null
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
  next_follow_up_on date,
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
  sorting_by_value boolean;
  phase integer;
  select_body text;
  stage_predicate text;
  filters text := '';
  keyset text;
  ordering text;
  fetched integer;
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

  if sort_key not in ('stage_entered_at', 'created_at', 'estimated_value')
     or sort_direction not in ('asc', 'desc')
     or owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to sort or filter the board.'
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

  sorting_by_value := sort_key = 'estimated_value';

  -- Ordering by money is reading money. Withholding the amounts while handing over the ranking would
  -- give the column away one comparison at a time.
  if sorting_by_value and not caller_sees_money then
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
      opportunity.next_follow_up_on,
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

  if not sorting_by_value then
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

  -- Value sorting, phase by phase. Phase 1 is the estimated cards in the caller's chosen direction;
  -- phase 2 is the unestimated ones, always oldest id first, which is the order they already sit in.
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
          cursor_value, cursor_id)
      end;
    else
      ordering := ' order by opportunity.estimated_value asc, opportunity.id asc';
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
      end;
    end if;

    return query execute select_body || filters
      || ' and opportunity.estimated_value is not null' || keyset || ordering
      || format(' limit %s', resolved_limit);
    get diagnostics fetched = row_count;

    -- The estimated side is finished, so the rest of this page comes from the unestimated side, from its
    -- beginning. No unestimated card can have been returned before this point, so there is nothing to
    -- page past.
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
end;
$_$;

revoke all on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid) from public, anon;
grant execute on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid) to authenticated, service_role;
