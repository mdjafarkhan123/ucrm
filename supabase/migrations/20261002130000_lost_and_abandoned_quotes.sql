-- Pipeline B5: Lost and abandoned quotes.
--
-- Until now a quote card could not be marked Lost from the board, and every archived quote was counted as
-- Lost -- including a draft nobody ever sent, which is a quote the contractor gave up writing, not a deal a
-- customer turned down. This part draws that line:
--
--   * A quote the customer has seen can be marked Lost from its card, with an optional reason. That archives
--     the quote, the same way marking a Request Lost archives the Request.
--   * Archiving a draft that was never sent takes its card off the board as "Abandoned before sending". It
--     writes no Lost event and is in no Lost count.
--   * A Lost quote's value is the total the customer last saw, and it stops following the quote.
--   * A Lost record can be given a reason afterwards -- the only way a customer's decline ever gets one.
--   * Reopening a Lost quote restores the quote to where it stood.
--
-- Growth: every read here is one opportunity, its quote, and its current outcome event, each by primary key.
-- The Sales Outcomes page gains two primary-key joins per row on a page of at most 51 rows.

-- ---------------------------------------------------------------------------------------------------------
-- 1. A reason given after the fact is recorded as that: who classified the loss, and when.
-- ---------------------------------------------------------------------------------------------------------

alter table public.opportunity_outcome_events
  add column classified_at timestamptz,
  add column classified_by uuid references auth.users (id) on delete set null,
  add constraint opportunity_outcome_events_classified_is_lost
    check (classified_at is null or event_type = 'lost');

comment on column public.opportunity_outcome_events.classified_at is
  'When public.pipeline_set_lost_reason last set this Lost event''s reason and note. Null when they are as given at the moment of loss. What happened and when never changes; only its internal classification does.';
comment on column public.opportunity_outcome_events.classified_by is
  'Who last set this Lost event''s reason through public.pipeline_set_lost_reason.';
comment on table public.opportunity_outcome_events is
  'Won/Lost/Reopened history for Sales Pipeline opportunities. Members may only read this table. Rows are written by public.pipeline_mark_opportunity_lost, public.pipeline_reopen_opportunity, the Quote status trigger, and the Job commands, which run as the table owner. A row is never deleted or re-dated; the one permitted change is public.pipeline_set_lost_reason classifying a Lost event''s reason and note.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. What a Lost quote was worth: the total the customer last saw, held still from then on.
-- ---------------------------------------------------------------------------------------------------------

create function private.quote_last_sent_total_minor(target_quote_id uuid) returns bigint
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select version.total_minor
  from public.quotes as quote
  join public.quote_versions as version
    on version.id = quote.current_published_version_id
   and version.organization_id = quote.organization_id
  where quote.id = target_quote_id;
$$;

comment on function private.quote_last_sent_total_minor(uuid) is
  'The total of the version the customer last received, ignoring any revision still being drafted. Null for a quote that was never sent.';

revoke all on function private.quote_last_sent_total_minor(uuid) from public, anon, authenticated;

-- A Lost card keeps the value it was lost at. Reopening it puts the card back on the live total.
create or replace function private.sync_opportunity_value_for_quote(target_organization_id uuid, target_quote_id uuid) returns void
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $$
  update public.opportunities
  set estimated_value = private.quote_current_total_minor(target_quote_id) / 100.0
  where organization_id = target_organization_id
    and quote_id = target_quote_id
    and outcome <> 'lost';
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 3. What a quote's own status change does to its card.
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.opportunity_resync_from_quote() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  inserted_event public.opportunity_outcome_events;
begin
  select * into opportunity_row
  from public.opportunities
  where organization_id = new.organization_id and quote_id = new.id
  for update;

  if opportunity_row.id is null then
    return null;
  end if;

  -- A declined or archived quote is no longer being chased, so its follow-up Tasks go with it (Jobber).
  if new.status in ('declined', 'archived') then
    delete from public.tasks
    where organization_id = opportunity_row.organization_id
      and opportunity_id = opportunity_row.id;
  end if;

  if new.status = 'approved' and opportunity_row.outcome = 'open' then
    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      prior_quote_status, idempotency_key
    ) values (
      opportunity_row.organization_id, opportunity_row.id, 'won', now(), (select auth.uid()),
      old.status, gen_random_uuid()::text
    ) returning * into inserted_event;

    update public.opportunities
    set outcome = 'won', outcome_at = inserted_event.occurred_at,
        current_outcome_event_id = inserted_event.id, updated_at = now()
    where id = opportunity_row.id;

  elsif new.status = 'archived' and new.sent_at is null and opportunity_row.outcome = 'open' then
    -- Abandoned before sending: no customer ever saw this quote, so nobody lost anything. The card stays
    -- without an outcome and leaves the board because its stage re-resolves to closed. The quote's own
    -- archived state is the record of it.
    update public.opportunities set updated_at = now() where id = opportunity_row.id;

  elsif new.status in ('declined', 'archived') and opportunity_row.outcome = 'open' then
    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      prior_quote_status, idempotency_key
    ) values (
      opportunity_row.organization_id, opportunity_row.id, 'lost', now(), (select auth.uid()),
      old.status, gen_random_uuid()::text
    ) returning * into inserted_event;

    update public.opportunities
    set outcome = 'lost', outcome_at = inserted_event.occurred_at,
        current_outcome_event_id = inserted_event.id,
        estimated_value = private.quote_last_sent_total_minor(new.id) / 100.0,
        updated_at = now()
    where id = opportunity_row.id;

  elsif new.status in ('draft', 'awaiting_response', 'changes_requested')
        and opportunity_row.outcome <> 'open' then
    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      restores_event_id, idempotency_key
    ) values (
      opportunity_row.organization_id, opportunity_row.id, 'reopened', now(), (select auth.uid()),
      opportunity_row.current_outcome_event_id, gen_random_uuid()::text
    ) returning * into inserted_event;

    update public.opportunities
    set outcome = 'open', outcome_at = null, current_outcome_event_id = null,
        estimated_value = private.quote_current_total_minor(new.id) / 100.0,
        updated_at = now()
    where id = opportunity_row.id;

  else
    update public.opportunities set updated_at = now() where id = opportunity_row.id;
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 4. Mark as lost, for a Request card and now for a sent quote's card.
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.pipeline_mark_opportunity_lost(
  target_opportunity_id uuid,
  idempotency_key text,
  reason text default null,
  note text default null,
  occurred_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  request_row public.requests;
  quote_row public.quotes;
  backing_quote_id uuid;
  existing_event public.opportunity_outcome_events;
  inserted_event public.opportunity_outcome_events;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  clean_reason text := nullif(trim(coalesce(reason, '')), '');
  clean_note text := nullif(trim(coalesce(note, '')), '');
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'An outcome cannot be dated in the future.' using errcode = 'check_violation';
  end if;
  if clean_reason is not null and clean_reason not in (
    'price_too_high', 'chose_another_contractor', 'no_response', 'project_postponed',
    'work_not_a_fit', 'duplicate_or_test_request', 'other'
  ) then
    raise exception 'Choose a valid lost reason.' using errcode = 'check_violation';
  end if;
  if clean_reason = 'other' and clean_note is null then
    raise exception 'Add a short note for "Other".' using errcode = 'check_violation';
  end if;

  -- Every Quote command locks the quote and then its card. Taking the quote first here keeps that one
  -- order, so this cannot deadlock against an archive or a decline landing at the same moment. The id is
  -- read only for a caller who may change this card.
  select opportunity.quote_id into backing_quote_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id
    and private.member_has_permission(opportunity.organization_id, (select auth.uid()), 'pipeline.edit');

  if backing_quote_id is not null then
    select * into quote_row from public.quotes where id = backing_quote_id for update;
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  -- A retry of the same command returns the first result untouched, even if the opportunity has since
  -- moved on. This must run before the "must be open" check below, or a legitimate retry after the first
  -- call already applied would be rejected as a conflicting command instead of recognised as a repeat.
  select * into existing_event
  from public.opportunity_outcome_events
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and opportunity_outcome_events.idempotency_key = pipeline_mark_opportunity_lost.idempotency_key;
  if found then
    return jsonb_build_object(
      'applied', false, 'event_id', existing_event.id, 'outcome', 'lost',
      'outcome_at', existing_event.occurred_at
    );
  end if;

  if opportunity_row.outcome <> 'open' then
    raise exception 'Only an open opportunity can be marked lost.' using errcode = 'check_violation';
  end if;

  if opportunity_row.quote_id is not null then
    if quote_row.id is null or quote_row.organization_id <> opportunity_row.organization_id then
      raise exception 'The backing quote could not be found.' using errcode = 'foreign_key_violation';
    end if;
    -- Marking Lost archives the quote, so it asks for what archiving a quote asks for.
    if not private.member_has_permission(
      quote_row.organization_id, (select auth.uid()), 'quotes.edit'
    ) then
      raise exception 'You do not have access to archive this quote.'
        using errcode = 'insufficient_privilege';
    end if;
    if quote_row.sent_at is null then
      raise exception 'This quote was never sent, so there is nothing to lose. Archive it from the quote instead.'
        using errcode = 'check_violation';
    end if;
    if quote_row.status not in ('draft', 'awaiting_response', 'changes_requested') then
      raise exception 'This quote cannot be marked lost right now.' using errcode = 'check_violation';
    end if;

    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      reason, note, prior_quote_status, idempotency_key
    ) values (
      opportunity_row.organization_id, target_opportunity_id, 'lost', command_time, (select auth.uid()),
      clean_reason, clean_note, quote_row.status, idempotency_key
    ) returning * into inserted_event;

    -- The card is decided before the quote is archived, so the quote's own status trigger finds nothing
    -- left to decide and writes no second, reasonless Lost event. It still removes the card's Tasks.
    update public.opportunities
    set outcome = 'lost', outcome_at = command_time, current_outcome_event_id = inserted_event.id,
        estimated_value = private.quote_last_sent_total_minor(quote_row.id) / 100.0
    where id = target_opportunity_id;

    update public.quotes
    set previous_status = quote_row.status,
        status = 'archived',
        archived_at = now(),
        archive_reason = null
    where id = quote_row.id;

    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      quote_row.organization_id, 'quote', quote_row.id, 'quote.marked_lost',
      'Marked as lost on the Pipeline and archived', (select auth.uid()),
      jsonb_build_object('outcome_event_id', inserted_event.id, 'reason', clean_reason)
    );

    return jsonb_build_object(
      'applied', true, 'event_id', inserted_event.id, 'outcome', 'lost', 'outcome_at', command_time
    );
  end if;

  if opportunity_row.request_id is null then
    -- A Direct job is closed from birth and never open, so this is unreachable; refusing plainly is safer
    -- than guessing.
    raise exception 'This record cannot be marked lost.' using errcode = 'check_violation';
  end if;

  select * into request_row
  from public.requests
  where id = opportunity_row.request_id and organization_id = opportunity_row.organization_id
  for update;

  if request_row.id is null then
    raise exception 'The backing request could not be found.' using errcode = 'foreign_key_violation';
  end if;
  if request_row.status in ('archived', 'converted') then
    raise exception 'This request cannot be marked lost right now.' using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.outcome_transition_request_id', request_row.id::text, true);

  update public.requests
  set status = 'archived'
  where id = request_row.id;

  insert into public.opportunity_outcome_events (
    organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
    reason, note, prior_request_status, idempotency_key
  ) values (
    opportunity_row.organization_id, target_opportunity_id, 'lost', command_time, (select auth.uid()),
    clean_reason, clean_note, request_row.status, idempotency_key
  ) returning * into inserted_event;

  update public.opportunities
  set outcome = 'lost', outcome_at = command_time, current_outcome_event_id = inserted_event.id
  where id = target_opportunity_id;

  -- Only Tasks still open at this moment are this Lost event's to claim. A Task a person already finished
  -- keeps its own completed_by and no event id, so Reopen will never touch it. The five-completed limit is
  -- deliberately not re-checked here: it bounds active board work, and this card is leaving the board.
  update public.tasks
  set status = 'completed', completed_at = command_time, completed_by = null,
      completed_by_outcome_event_id = inserted_event.id
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and status = 'open';

  return jsonb_build_object(
    'applied', true, 'event_id', inserted_event.id, 'outcome', 'lost', 'outcome_at', command_time
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 5. Reopen, for a Lost Request and now for a Lost quote.
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.pipeline_reopen_opportunity(
  target_opportunity_id uuid,
  idempotency_key text,
  reopen_explanation text,
  occurred_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  quote_row public.quotes;
  backing_quote_id uuid;
  restored_status text;
  lost_event public.opportunity_outcome_events;
  existing_event public.opportunity_outcome_events;
  inserted_event public.opportunity_outcome_events;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  clean_explanation text := nullif(trim(coalesce(reopen_explanation, '')), '');
  open_count integer;
  reopening_count integer;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if clean_explanation is null or char_length(clean_explanation) > 500 then
    raise exception 'A short explanation is required to reopen.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'An outcome cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  -- Quote first, then its card: the same order every Quote command takes them in.
  select opportunity.quote_id into backing_quote_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id
    and private.member_has_permission(opportunity.organization_id, (select auth.uid()), 'pipeline.edit');

  if backing_quote_id is not null then
    select * into quote_row from public.quotes where id = backing_quote_id for update;
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  select * into existing_event
  from public.opportunity_outcome_events
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and opportunity_outcome_events.idempotency_key = pipeline_reopen_opportunity.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'outcome', 'open');
  end if;

  if opportunity_row.outcome <> 'lost' or opportunity_row.current_outcome_event_id is null then
    raise exception 'Only a lost opportunity can be reopened.' using errcode = 'check_violation';
  end if;

  select * into lost_event
  from public.opportunity_outcome_events
  where id = opportunity_row.current_outcome_event_id
    and organization_id = opportunity_row.organization_id
  for update;

  if lost_event.id is null then
    raise exception 'No lost event was found to reopen.' using errcode = 'foreign_key_violation';
  end if;

  if opportunity_row.quote_id is not null then
    if quote_row.id is null or quote_row.organization_id <> opportunity_row.organization_id then
      raise exception 'The backing quote could not be found.' using errcode = 'foreign_key_violation';
    end if;
    if not private.member_has_permission(
      quote_row.organization_id, (select auth.uid()), 'quotes.edit'
    ) then
      raise exception 'You do not have access to restore this quote.'
        using errcode = 'insufficient_privilege';
    end if;
    if quote_row.status not in ('archived', 'declined') then
      raise exception 'This quote has already moved on. Open the quote to carry on with it.'
        using errcode = 'check_violation';
    end if;

    -- Back to where it stood the moment before it was lost. An archived quote remembers that itself; a
    -- declined one is remembered by its Lost event.
    restored_status := case
      when quote_row.status = 'archived'
        and quote_row.previous_status in ('draft', 'awaiting_response', 'changes_requested')
        then quote_row.previous_status
      else lost_event.prior_quote_status
    end;
    if restored_status is null
       or restored_status not in ('draft', 'awaiting_response', 'changes_requested') then
      restored_status := 'awaiting_response';
    end if;
    -- A draft needs a draft to edit, and a sent quote has none.
    if restored_status = 'draft' and quote_row.draft_version_id is null then
      restored_status := 'awaiting_response';
    elsif restored_status <> 'draft' and quote_row.draft_version_id is not null then
      restored_status := 'draft';
    end if;

    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      reopen_explanation, restores_event_id, idempotency_key
    ) values (
      opportunity_row.organization_id, target_opportunity_id, 'reopened', command_time, (select auth.uid()),
      clean_explanation, lost_event.id, idempotency_key
    ) returning * into inserted_event;

    -- Open before the quote changes, so the quote's own status trigger writes no second, unexplained
    -- Reopened event. The card goes back to following the quote's live total.
    update public.opportunities
    set outcome = 'open', outcome_at = null, current_outcome_event_id = null,
        estimated_value = private.quote_current_total_minor(quote_row.id) / 100.0
    where id = target_opportunity_id;

    -- The customer's "no" stays in the quote's history. It simply stops being the answer.
    update public.quote_decisions
    set is_current = false
    where organization_id = quote_row.organization_id
      and quote_id = quote_row.id
      and is_current
      and outcome = 'declined';

    update public.quotes
    set status = restored_status,
        previous_status = null,
        archived_at = null,
        archive_reason = null,
        decision = case when decision = 'declined' then null else decision end,
        decided_at = case when decision = 'declined' then null else decided_at end,
        decision_method = case when decision = 'declined' then null else decision_method end,
        decision_note = case when decision = 'declined' then null else decision_note end,
        decided_by = case when decision = 'declined' then null else decided_by end
    where id = quote_row.id;

    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      quote_row.organization_id, 'quote', quote_row.id, 'quote.reopened',
      'Reopened from Sales Outcomes', (select auth.uid()),
      jsonb_build_object('outcome_event_id', inserted_event.id, 'explanation', clean_explanation)
    );

    return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'outcome', 'open');
  end if;

  if opportunity_row.request_id is null then
    raise exception 'This record cannot be reopened.' using errcode = 'check_violation';
  end if;

  -- Almost always zero: at most five Tasks could have been open when Lost fired. This only fires when
  -- something opened new Tasks on an already-closed card, which the write path does not block today.
  select
    count(*) filter (where status = 'open'),
    count(*) filter (where completed_by_outcome_event_id = lost_event.id)
  into open_count, reopening_count
  from public.tasks
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id;

  if open_count + reopening_count > 5 then
    raise exception 'Reopening would leave more than five open tasks. Close some open tasks first.'
      using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.outcome_transition_request_id', opportunity_row.request_id::text, true);

  update public.requests
  set status = lost_event.prior_request_status
  where id = opportunity_row.request_id;

  insert into public.opportunity_outcome_events (
    organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
    reopen_explanation, restores_event_id, idempotency_key
  ) values (
    opportunity_row.organization_id, target_opportunity_id, 'reopened', command_time, (select auth.uid()),
    clean_explanation, lost_event.id, idempotency_key
  ) returning * into inserted_event;

  update public.opportunities
  set outcome = 'open', outcome_at = null, current_outcome_event_id = null
  where id = target_opportunity_id;

  update public.tasks
  set status = 'open', completed_at = null, completed_by = null, completed_by_outcome_event_id = null
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and completed_by_outcome_event_id = lost_event.id;

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'outcome', 'open');
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 6. Give a Lost record its reason afterwards.
-- ---------------------------------------------------------------------------------------------------------

create function public.pipeline_set_lost_reason(
  target_opportunity_id uuid,
  reason text default null,
  note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  clean_reason text := nullif(trim(coalesce(reason, '')), '');
  clean_note text := nullif(trim(coalesce(note, '')), '');
begin
  if clean_reason is not null and clean_reason not in (
    'price_too_high', 'chose_another_contractor', 'no_response', 'project_postponed',
    'work_not_a_fit', 'duplicate_or_test_request', 'other'
  ) then
    raise exception 'Choose a valid lost reason.' using errcode = 'check_violation';
  end if;
  if clean_reason = 'other' and clean_note is null then
    raise exception 'Add a short note for "Other".' using errcode = 'check_violation';
  end if;
  if char_length(coalesce(clean_note, '')) > 1000 then
    raise exception 'That note is too long.' using errcode = 'check_violation';
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  if opportunity_row.outcome <> 'lost' or opportunity_row.current_outcome_event_id is null then
    raise exception 'Only a lost opportunity has a lost reason.' using errcode = 'check_violation';
  end if;

  update public.opportunity_outcome_events
  set reason = clean_reason,
      note = clean_note,
      classified_at = now(),
      classified_by = (select auth.uid())
  where id = opportunity_row.current_outcome_event_id
    and organization_id = opportunity_row.organization_id
    and event_type = 'lost';

  if not found then
    raise exception 'No lost event was found to classify.' using errcode = 'foreign_key_violation';
  end if;

  return jsonb_build_object(
    'event_id', opportunity_row.current_outcome_event_id, 'reason', clean_reason, 'note', clean_note
  );
end;
$$;

comment on function public.pipeline_set_lost_reason(uuid, text, text) is
  'Sets or clears the reason and note on an opportunity''s current Lost event. Needs pipeline.edit. This is how a customer''s decline, which arrives with no reason, is classified by staff afterwards. Setting the same values again changes nothing but the classified stamp.';

revoke all on function public.pipeline_set_lost_reason(uuid, text, text) from public, anon;
grant execute on function public.pipeline_set_lost_reason(uuid, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 7. Sales Outcomes says why each record was lost, and what the customer said when they declined. The
--    function returns a new shape, so it is dropped and granted again.
-- ---------------------------------------------------------------------------------------------------------

drop function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid);

CREATE OR REPLACE FUNCTION "public"."pipeline_outcome_page"("target_organization_id" "uuid", "outcome_type" "text", "page_limit" integer DEFAULT 25, "sort_key" "text" DEFAULT 'outcome_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "outcome_from" timestamp with time zone DEFAULT NULL::timestamp with time zone, "outcome_to" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_sort_key" "text" DEFAULT NULL::"text", "cursor_phase" integer DEFAULT NULL::integer, "cursor_timestamp" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_numeric" numeric DEFAULT NULL::numeric, "cursor_text" "text" DEFAULT NULL::"text", "cursor_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "title" "text", "outcome" "text", "created_at" timestamp with time zone, "outcome_at" timestamp with time zone, "client_id" "uuid", "client_display_name" "text", "client_company_name" "text", "estimated_value" numeric, "source_kind" "text", "quote_id" "uuid", "quote_number" integer, "lost_reason" "text", "lost_note" "text", "customer_declined" boolean, "customer_message" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $_$
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
      case when opportunity.outcome = 'lost' and quote.decision = 'declined' then quote.decision_note end
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
        or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.quotes as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
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
$_$;

revoke all on function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid) from public, anon;
grant execute on function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 8. Existing records. A draft that was archived without ever being sent was counted as Lost under the old
--    rule. It is Abandoned before sending: its card loses the outcome, and the Lost event that never
--    described a real loss is removed. An event some later Reopen points back to is kept, as history.
-- ---------------------------------------------------------------------------------------------------------

update public.opportunities as opportunity
set outcome = 'open', outcome_at = null, current_outcome_event_id = null
from public.quotes as quote
where quote.id = opportunity.quote_id
  and quote.organization_id = opportunity.organization_id
  and opportunity.outcome = 'lost'
  and quote.status = 'archived'
  and quote.sent_at is null;

delete from public.opportunity_outcome_events as outcome_event
using public.opportunities as opportunity, public.quotes as quote
where opportunity.id = outcome_event.opportunity_id
  and opportunity.organization_id = outcome_event.organization_id
  and quote.id = opportunity.quote_id
  and quote.organization_id = opportunity.organization_id
  and outcome_event.event_type = 'lost'
  and opportunity.outcome = 'open'
  and quote.status = 'archived'
  and quote.sent_at is null
  and not exists (
    select 1
    from public.opportunity_outcome_events as later
    where later.organization_id = outcome_event.organization_id
      and later.restores_event_id = outcome_event.id
  );

-- A Lost quote that was sent keeps the total the customer last saw.
update public.opportunities as opportunity
set estimated_value = private.quote_last_sent_total_minor(opportunity.quote_id) / 100.0
where opportunity.outcome = 'lost'
  and opportunity.quote_id is not null
  and opportunity.estimated_value is distinct from private.quote_last_sent_total_minor(opportunity.quote_id) / 100.0;
