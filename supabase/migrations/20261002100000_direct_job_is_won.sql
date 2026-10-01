-- Pipeline B2: a Job made from scratch is a Direct job.
--
-- A contractor who books work with no Request and no Quote has still won that work, so Sales Outcomes should
-- count it. It was never a deal on the board, though, so it must not look like one: it gets one closed-only
-- Pipeline record of its own kind, written by the same job create that already records a Request-to-Job win
-- (B1). It never appears on the board, never joins the board's Won tile, and is reported under its own label
-- so it cannot inflate how many Requests and Quotes were won.
--
-- Growth: one record per from-scratch job, and a busy contractor makes far more of those than deals. Every
-- closed-outcome read therefore keys on `outcome_kind` (won, lost, direct_job) instead of `outcome`, the same
-- way A2 re-keyed the board on `board_column`, so a Won or Lost page never walks past Direct job rows.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Identity. A Direct job record belongs to its job the way a card belongs to its request or quote.
-- ---------------------------------------------------------------------------------------------------------

alter table public.opportunities
  add column job_id uuid,
  add constraint opportunities_job_organization_fk
    foreign key (organization_id, job_id)
    references public.jobs (organization_id, id) on delete cascade,
  drop constraint opportunities_single_source,
  add constraint opportunities_single_source check (num_nonnulls(request_id, quote_id, job_id) <= 1),
  -- Closed-only: there is no open Direct job to work, lose, or reopen.
  add constraint opportunities_direct_job_is_won check (job_id is null or outcome = 'won');

alter table public.opportunities
  add column outcome_kind text generated always as (
    case
      when outcome = 'open' then null
      when job_id is not null then 'direct_job'
      else outcome
    end
  ) stored;

comment on column public.opportunities.job_id is
  'Set only on a Direct job record: the job that was created with no request or quote behind it. Written once by private.record_direct_job_win and removed with the job.';
comment on column public.opportunities.outcome_kind is
  'How a closed record is reported: won or lost for a deal that was on the board, direct_job for a job made from scratch. Null while open. Every closed-outcome read and index keys on this.';
comment on table public.opportunities is
  'Sales Pipeline opportunities. Members may read this table, never write it. Identity comes from the Request trigger, the Quote conversion, or private.record_direct_job_win for a job made from scratch; stage from the stage triggers; the Part 2 fields from public.pipeline_update_opportunity_details; and outcome from public.pipeline_mark_opportunity_lost / public.pipeline_reopen_opportunity and the Quote and Job commands. Any future write must arrive through a definer function that checks the caller, not through a new grant or policy.';

grant select (job_id, outcome_kind) on table public.opportunities to authenticated;

-- One record per job. Also the index the foreign key is checked through when a job is removed.
create unique index opportunities_job_unique
  on public.opportunities (organization_id, job_id)
  where job_id is not null;

-- The closed-outcome indexes, re-keyed from `outcome` to `outcome_kind`.
drop index public.opportunities_outcome_idx;
drop index public.opportunities_outcome_created_idx;
drop index public.opportunities_outcome_value_idx;
drop index public.opportunities_outcome_unvalued_idx;

create index opportunities_outcome_idx
  on public.opportunities (organization_id, outcome_kind, outcome_at, id)
  where outcome_kind is not null;

create index opportunities_outcome_created_idx
  on public.opportunities (organization_id, outcome_kind, created_at, id)
  where outcome_kind is not null;

create index opportunities_outcome_value_idx
  on public.opportunities (organization_id, outcome_kind, estimated_value, id)
  where outcome_kind is not null and estimated_value is not null;

create index opportunities_outcome_unvalued_idx
  on public.opportunities (organization_id, outcome_kind, id)
  where outcome_kind is not null and estimated_value is null;

-- ---------------------------------------------------------------------------------------------------------
-- 2. A Direct job record holds no place on the board and has no stage history to keep.
-- ---------------------------------------------------------------------------------------------------------

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
  -- stage change and on a move into, out of, or between custom stages.
  if tg_op = 'INSERT' then
    new.stage_entered_at := coalesce(new.stage_entered_at, now());
  elsif new.stage is distinct from old.stage then
    -- A real Request, Assessment, or Quote action always wins over where somebody placed the card: it
    -- goes to the protected stage that action established.
    new.custom_stage_id := null;
    new.stage_entered_at := now();
  elsif new.custom_stage_id is distinct from old.custom_stage_id then
    new.stage_entered_at := now();
  else
    new.stage_entered_at := old.stage_entered_at;
  end if;

  return new;
end;
$$;

-- Stage history is how long a card sat in each column. A Direct job was never in one.
drop trigger opportunities_record_created_stage on public.opportunities;
create trigger opportunities_record_created_stage
  after insert on public.opportunities
  for each row
  when (new.job_id is null)
  execute function private.opportunity_record_stage_event();

-- ---------------------------------------------------------------------------------------------------------
-- 3. The one writer of a Direct job record.
-- ---------------------------------------------------------------------------------------------------------

create function private.record_direct_job_win(
  job public.jobs,
  won_value numeric,
  actor uuid,
  idempotency_key text,
  won_at timestamptz
) returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  record_id uuid;
  won_event_id uuid;
begin
  -- A job that came from a request or a quote already has its win on that card.
  if job.request_id is not null or job.quote_id is not null then
    return;
  end if;

  insert into public.opportunities (
    organization_id, client_id, job_id, title, outcome, outcome_at, estimated_value,
    stage_entered_at, created_at
  ) values (
    job.organization_id, job.client_id, job.id, job.title, 'won', won_at, won_value, won_at, won_at
  )
  on conflict (organization_id, job_id) where job_id is not null do nothing
  returning id into record_id;

  if record_id is null then
    return;
  end if;

  insert into public.opportunity_outcome_events (
    organization_id, opportunity_id, event_type, occurred_at, actor_user_id, idempotency_key
  ) values (
    job.organization_id, record_id, 'won', won_at, actor, idempotency_key
  ) returning id into won_event_id;

  update public.opportunities set current_outcome_event_id = won_event_id where id = record_id;
end;
$$;

comment on function private.record_direct_job_win(public.jobs, numeric, uuid, text, timestamptz) is
  'Writes the one closed-only Direct job record for a job made with no request or quote, with its value frozen at that moment (null when nothing on the job is priced). Does nothing for a job that has a source, or that already has its record.';

revoke all on function private.record_direct_job_win(public.jobs, numeric, uuid, text, timestamptz) from public, anon, authenticated;

-- The record is named after its job, so a renamed job is not listed under its old name.
create function private.direct_job_record_follow_title() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  update public.opportunities
  set title = new.title
  where organization_id = new.organization_id and job_id = new.id;
  return null;
end;
$$;

revoke all on function private.direct_job_record_follow_title() from public, anon, authenticated;

create trigger jobs_direct_job_record_follow_title
  after update of title on public.jobs
  for each row
  when (old.title is distinct from new.title and new.quote_id is null and new.request_id is null)
  execute function private.direct_job_record_follow_title();

-- ---------------------------------------------------------------------------------------------------------
-- 4. The direct job create records the Direct job. Same signature, so its grants stand.
--    Also corrects B1: a job holding only text or heading lines has nothing priced, so its win is Unvalued
--    rather than worth zero.
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."create_job_with_visits"("target_organization_id" "uuid", "target_client_id" "uuid", "target_property_id" "uuid", "new_title" "text", "new_instructions" "text", "invoice_on_close" boolean, "scope_lines" "jsonb", "visits" "jsonb", "new_idempotency_key" "text", "new_request_hash" "text", "new_job_type" "text" DEFAULT 'one_off'::"text", "new_is_as_needed" boolean DEFAULT false, "new_recurrence" "jsonb" DEFAULT NULL::"jsonb", "source_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  receipt_id uuid;
  existing_receipt public.job_command_receipts;
  organization_currency text;
  created_job public.jobs;
  visit_element jsonb;
  new_visit public.job_visits;
  assignee_element jsonb;
  visit_count integer;
  line_count integer;
  calculated jsonb;
  final_result jsonb;
  job_type text := coalesce(nullif(trim(coalesce(new_job_type, '')), ''), 'one_off');
  as_needed boolean := coalesce(new_is_as_needed, false);
  has_rule boolean := new_recurrence is not null and jsonb_typeof(new_recurrence) = 'object';
  request_row public.requests;
  request_opportunity public.opportunities;
  request_photo_ids uuid[] := '{}'::uuid[];
  won_event public.opportunity_outcome_events;
  priced_line_count integer;
  won_value numeric;
begin
  if caller is null then
    raise exception 'You must be signed in to create a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.create') then
    raise exception 'You do not have access to create a job here.'
      using errcode = 'insufficient_privilege';
  end if;

  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A job fingerprint is required.' using errcode = 'check_violation';
  end if;

  if job_type not in ('one_off', 'recurring') then
    raise exception 'A job is either one-off or recurring.' using errcode = 'check_violation';
  end if;

  visit_count := coalesce(jsonb_array_length(visits), 0);

  -- The three shapes, each refused in the words of the thing the person actually did. A one-off is the visits
  -- they typed; a recurring job is the rule they set; an as-needed job is deliberately empty and stays empty.
  if job_type = 'one_off' then
    if has_rule or as_needed then
      raise exception 'A one-off job does not repeat. Create a recurring job instead.'
        using errcode = 'check_violation';
    end if;
    if visit_count < 1 or visit_count > 20 then
      raise exception 'A one-off job is created with between 1 and 20 visits.' using errcode = 'check_violation';
    end if;
  elsif as_needed then
    if has_rule or visit_count > 0 then
      raise exception 'An as-needed job starts with no schedule and no visits.' using errcode = 'check_violation';
    end if;
  else
    if not has_rule then
      raise exception 'A recurring job needs a repeat schedule.' using errcode = 'check_violation';
    end if;
    if visit_count > 0 then
      raise exception 'A recurring job builds its own visits from the schedule.'
        using errcode = 'check_violation';
    end if;
  end if;

  -- Claim the idempotency key before doing any work. on conflict do nothing waits for a racing transaction
  -- to commit and then returns no row, so the loser reads the winner's committed result instead of building
  -- a second job.
  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'create_job', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'create_job'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'That job was already started with different details.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  -- A job made from a request. Lock order matches the outcome engine and convert_request_to_quote: the
  -- pipeline card first, then its request, so two commands racing on the same work queue up instead of
  -- deadlocking. The replay check above has already answered a doubled click, so reaching here with a
  -- request that is no longer live work is a genuine second attempt.
  if source_request_id is not null then
    select * into request_opportunity
    from public.opportunities
    where organization_id = target_organization_id
      and request_id = source_request_id
    for update;

    select * into request_row
    from public.requests
    where organization_id = target_organization_id
      and id = source_request_id
    for update;

    if request_row.id is null then
      raise exception 'You do not have access to create a job from this request.'
        using errcode = 'insufficient_privilege';
    end if;
    if request_row.status = 'converted' then
      raise exception 'This request has already been converted.' using errcode = 'P0409';
    end if;
    if request_row.status not in ('new', 'unscheduled', 'assessment_completed') then
      raise exception 'This request cannot be turned into a job right now.' using errcode = 'check_violation';
    end if;
    if request_row.client_id is distinct from target_client_id then
      raise exception 'A job made from a request stays with that request''s client.'
        using errcode = 'check_violation';
    end if;

    -- The only photos this job may inherit are the ones already on the request's own priced lines.
    select coalesce(array_agg(line.image_file_id), '{}'::uuid[]) into request_photo_ids
    from public.request_pricing_lines as line
    where line.organization_id = target_organization_id
      and line.request_id = source_request_id
      and line.image_file_id is not null;
  end if;

  select settings.currency_code into organization_currency
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  organization_currency := coalesce(organization_currency, 'USD');

  -- The job row, its number, its guards and its first history event. A one-off is priced as a whole and
  -- reminded on close; repeating work defaults to a fixed amount each period, which is the shape Jobber opens
  -- on too. Part 11 owns changing that -- this only has to be a defensible starting point the guards accept.
  created_job := private.create_job(
    target_organization_id,
    target_client_id,
    target_property_id,
    new_title,
    job_type,
    case when job_type = 'one_off' then 'job_total' else 'fixed_per_period' end,
    organization_currency,
    caller,
    as_needed,
    case
      when job_type = 'recurring' then 'month_end'
      when coalesce(invoice_on_close, true) then 'on_closure'
      else 'manual'
    end,
    new_instructions,
    null,
    null,
    null,
    null,
    source_request_id
  );

  -- The job's own scope. The 100-line cap is a table trigger; the shape of each line is a table constraint.
  insert into public.job_line_items (
    organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_file_id
  )
  select
    created_job.organization_id,
    created_job.id,
    (row_number() over (order by (line.value->>'position')::integer, ordinality) - 1)::integer,
    nullif(line.value->>'source_catalog_item_id', '')::uuid,
    coalesce(line.value->>'line_kind', 'priced'),
    nullif(line.value->>'category', ''),
    coalesce((line.value->>'is_labor')::boolean, false),
    line.value->>'name',
    nullif(line.value->>'description', ''),
    nullif(line.value->>'unit_label', ''),
    (line.value->>'quantity')::numeric,
    (line.value->>'unit_price_minor')::bigint,
    (line.value->>'unit_cost_minor')::bigint,
    coalesce((line.value->>'is_taxable')::boolean, true),
    case
      when nullif(line.value->>'image_file_id', '')::uuid = any(request_photo_ids)
        then private.live_line_photo(
          created_job.organization_id, nullif(line.value->>'image_file_id', '')::uuid
        )
    end
  from jsonb_array_elements(coalesce(scope_lines, '[]'::jsonb)) with ordinality as line(value, ordinality);

  get diagnostics line_count = row_count;

  if source_request_id is not null then
    perform private.sync_line_photo_links(created_job.organization_id, 'job', created_job.id);
  end if;

  if has_rule then
    -- Generated visits carry the schedule's own time and no assignees; who goes is decided per visit, exactly
    -- as it is for a one-off.
    visit_count := private.write_job_recurrence(created_job.organization_id, created_job.id, new_recurrence);

    insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
    values (
      created_job.organization_id,
      created_job.id,
      'visits_generated',
      caller,
      jsonb_build_object('visit_count', visit_count, 'reason', 'created')
    );
  else
    -- The visits, in the order the form listed them, each with its own people. A visit's shape is checked by
    -- the table's constraints; an assignee who is not a member of this organization is refused by the
    -- assignment's composite foreign key.
    for visit_element in select value from jsonb_array_elements(coalesce(visits, '[]'::jsonb)) as v(value)
    loop
      insert into public.job_visits (
        organization_id, job_id, position, visit_date, start_time, end_time, all_day, title, instructions,
        source
      ) values (
        created_job.organization_id,
        created_job.id,
        (visit_element->>'position')::integer,
        nullif(visit_element->>'visit_date', '')::date,
        nullif(visit_element->>'start_time', '')::time,
        nullif(visit_element->>'end_time', '')::time,
        coalesce((visit_element->>'all_day')::boolean, false),
        nullif(trim(visit_element->>'title'), ''),
        nullif(trim(visit_element->>'instructions'), ''),
        'manual'
      )
      returning * into new_visit;

      if jsonb_typeof(visit_element->'assignee_ids') = 'array' then
        for assignee_element in select value from jsonb_array_elements(visit_element->'assignee_ids') as a(value)
        loop
          insert into public.job_visit_assignments (organization_id, visit_id, user_id)
          values (created_job.organization_id, new_visit.id, (assignee_element #>> '{}')::uuid)
          on conflict do nothing;
        end loop;
      end if;
    end loop;
  end if;

  calculated := private.store_job_money(created_job.id);

  -- What this job is worth to the Pipeline, frozen as it stands at this moment. A job saved with nothing
  -- priced on it has no total yet, so its win is Unvalued rather than worth a made-up zero. Nothing later
  -- rewrites it.
  select count(*) into priced_line_count
  from public.job_line_items as line
  where line.organization_id = created_job.organization_id
    and line.job_id = created_job.id
    and line.line_kind = 'priced';

  won_value := case
    when priced_line_count > 0
      then least((calculated->>'total_minor')::numeric / 100, 9999999999.99)
  end;

  if source_request_id is not null then
    -- This one update is also what takes the request card off the board: the resync trigger recomputes its
    -- stage from the new status, exactly as it does when a request becomes a quote.
    update public.requests set status = 'converted' where id = request_row.id;

    -- Won once. A card that is already decided keeps the decision it has.
    if request_opportunity.id is not null and request_opportunity.outcome = 'open' then
      insert into public.opportunity_outcome_events (
        organization_id, opportunity_id, event_type, occurred_at, actor_user_id, idempotency_key
      ) values (
        request_opportunity.organization_id, request_opportunity.id, 'won', now(), caller,
        new_idempotency_key
      ) returning * into won_event;

      update public.opportunities
      set outcome = 'won',
          outcome_at = won_event.occurred_at,
          current_outcome_event_id = won_event.id,
          estimated_value = won_value,
          updated_at = now()
      where id = request_opportunity.id;
    end if;

    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      request_row.organization_id, 'request', request_row.id, 'request.converted_to_job',
      'Turned this request into a job',
      caller,
      jsonb_build_object('job_id', created_job.id, 'job_number', created_job.job_number)
    );
  else
    -- A job made from scratch has no request or quote behind it, so there is no card to close. It is still
    -- booked work, and Sales Outcomes counts it as a Direct job.
    perform private.record_direct_job_win(created_job, won_value, caller, new_idempotency_key, now());
  end if;

  final_result := jsonb_build_object(
    'applied', true,
    'job_id', created_job.id,
    'job_number', created_job.job_number,
    'job_type', job_type,
    'is_as_needed', as_needed,
    'visit_count', visit_count,
    'line_count', line_count,
    'total_minor', (calculated->>'total_minor')::bigint,
    'request_id', source_request_id
  );

  update public.job_command_receipts set result = final_result where id = receipt_id;

  return final_result;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 5. Jobs made from scratch before today get their record, dated when the job was created and valued at the
--    job total as it stands now -- the closest thing to the moment that is still known.
-- ---------------------------------------------------------------------------------------------------------

do $$
declare
  job public.jobs;
begin
  for job in
    select * from public.jobs where quote_id is null and request_id is null order by created_at
  loop
    perform private.record_direct_job_win(
      job,
      case
        when exists (
          select 1 from public.job_line_items as line
          where line.organization_id = job.organization_id
            and line.job_id = job.id
            and line.line_kind = 'priced'
        ) then least(job.total_minor::numeric / 100, 9999999999.99)
      end,
      job.created_by,
      'direct-job-backfill:' || job.id::text,
      job.created_at
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 6. Sales Outcomes lists Direct jobs under their own type; Won and the board's tiles stay deals only.
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."pipeline_outcome_page"("target_organization_id" "uuid", "outcome_type" "text", "page_limit" integer DEFAULT 25, "sort_key" "text" DEFAULT 'outcome_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "outcome_from" timestamp with time zone DEFAULT NULL::timestamp with time zone, "outcome_to" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_sort_key" "text" DEFAULT NULL::"text", "cursor_phase" integer DEFAULT NULL::integer, "cursor_timestamp" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_numeric" numeric DEFAULT NULL::numeric, "cursor_text" "text" DEFAULT NULL::"text", "cursor_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "title" "text", "outcome" "text", "created_at" timestamp with time zone, "outcome_at" timestamp with time zone, "client_id" "uuid", "client_display_name" "text", "client_company_name" "text", "estimated_value" numeric)
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
      case when %L::boolean then opportunity.estimated_value end
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
        or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
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

CREATE OR REPLACE FUNCTION "public"."pipeline_outcome_tiles"("target_organization_id" "uuid", "tile_from" timestamp with time zone, "tile_to" timestamp with time zone) RETURNS TABLE("outcome_key" "text", "closed_count" bigint, "value_total" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  -- Both outcome types are always returned, zero-filled, so a tile with nothing in the window still shows
  -- "Won (0)" instead of going missing.
  return query
  select
    outcome_type.outcome_key,
    coalesce(counted.closed_count, 0)::bigint,
    counted.value_total
  from unnest(array['won', 'lost']) as outcome_type(outcome_key)
  left join (
    select
      opportunity.outcome_kind as outcome_key,
      count(*) as closed_count,
      case when caller_sees_money then sum(opportunity.estimated_value) end as value_total
    from public.opportunities as opportunity
    where opportunity.organization_id = target_organization_id
      -- Deals only. A Direct job is booked work that was never a card, so it is not in the board's tiles.
      and opportunity.outcome_kind in ('won', 'lost')
      and opportunity.outcome_at >= tile_from
      and opportunity.outcome_at < tile_to
    group by opportunity.outcome_kind
  ) as counted on counted.outcome_key = outcome_type.outcome_key;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 7. The financial sales outcomes ledger names a Direct job and its job, and its summary counts Direct jobs
--    apart from Won. Both return a new shape, so they are dropped and granted again.
-- ---------------------------------------------------------------------------------------------------------

drop function public.financial_sales_outcomes_page(uuid, date, date, timestamptz, uuid, integer, text);
drop function public.financial_sales_outcomes_summary(uuid, date, date);

CREATE OR REPLACE FUNCTION "public"."financial_sales_outcomes_page"("target_organization_id" "uuid", "report_from" "date", "report_to" "date", "cursor_outcome_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_opportunity_id" "uuid" DEFAULT NULL::"uuid", "page_limit" integer DEFAULT 100, "sort_direction" "text" DEFAULT 'asc'::"text") RETURNS TABLE("opportunity_id" "uuid", "outcome" "text", "outcome_at" timestamp with time zone, "outcome_on" "date", "created_on" "date", "source_kind" "text", "request_id" "uuid", "quote_id" "uuid", "quote_number" integer, "title" "text", "client_id" "uuid", "client_display_name" "text", "client_company_name" "text", "currency_code" "text", "estimated_value_minor" bigint, "lost_reason" "text", "outcome_event_id" "uuid", "job_id" "uuid")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  can_view_value boolean;
  zone text;
  organization_currency text;
  window_start timestamptz;
  window_end timestamptz;
  resolved_limit integer;
begin
  if not private.member_has_permission(target_organization_id, caller, 'pipeline.view') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_outcome_at is null) <> (cursor_opportunity_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_value := private.member_has_permission(target_organization_id, caller, 'pipeline.view_value');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC'), settings.currency_code
  into zone, organization_currency
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select opportunity.id,
    opportunity.outcome,
    opportunity.outcome_at,
    (opportunity.outcome_at at time zone zone)::date,
    (opportunity.created_at at time zone zone)::date,
    case
      when opportunity.job_id is not null then 'direct_job'
      when opportunity.quote_id is not null then 'quote'
      else 'request'
    end,
    opportunity.request_id,
    opportunity.quote_id,
    quote.quote_number,
    opportunity.title,
    opportunity.client_id,
    client.display_name,
    client.company_name,
    coalesce(quote.currency_code, organization_currency),
    case when can_view_value then round(opportunity.estimated_value * 100)::bigint end,
    outcome_event.reason,
    opportunity.current_outcome_event_id,
    opportunity.job_id
  from public.opportunities as opportunity
  left join public.quotes as quote
    on quote.organization_id = opportunity.organization_id and quote.id = opportunity.quote_id
  left join public.clients as client
    on client.organization_id = opportunity.organization_id and client.id = opportunity.client_id
  left join public.opportunity_outcome_events as outcome_event
    on outcome_event.organization_id = opportunity.organization_id
   and outcome_event.id = opportunity.current_outcome_event_id
   and outcome_event.event_type = 'lost'
  where opportunity.organization_id = target_organization_id
    and opportunity.outcome_kind is not null
    and opportunity.outcome_at >= window_start and opportunity.outcome_at < window_end
    and (
      cursor_outcome_at is null
      or (sort_direction = 'asc'
        and (opportunity.outcome_at, opportunity.id) > (cursor_outcome_at, cursor_opportunity_id))
      or (sort_direction = 'desc'
        and (opportunity.outcome_at, opportunity.id) < (cursor_outcome_at, cursor_opportunity_id))
    )
  order by
    case when sort_direction = 'asc' then opportunity.outcome_at end asc,
    case when sort_direction = 'asc' then opportunity.id end asc,
    case when sort_direction = 'desc' then opportunity.outcome_at end desc,
    case when sort_direction = 'desc' then opportunity.id end desc
  limit resolved_limit;
end;
$$;

comment on function public.financial_sales_outcomes_page(uuid, date, date, timestamptz, uuid, integer, text) is
  'Keyset-paged sales outcomes ledger for a report range: every Opportunity currently Won or Lost with its outcome instant inside the range, traceable to its Request, Quote, or -- for a Direct job -- its Job. A Direct job row has outcome won and source_kind direct_job. Values are sales estimates, never revenue. Requires pipeline.view; estimated_value_minor is null without pipeline.view_value. Every row is explicitly organization scoped.';

revoke all on function public.financial_sales_outcomes_page(uuid, date, date, timestamptz, uuid, integer, text) from public, anon;
grant execute on function public.financial_sales_outcomes_page(uuid, date, date, timestamptz, uuid, integer, text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."financial_sales_outcomes_summary"("target_organization_id" "uuid", "report_from" "date", "report_to" "date") RETURNS TABLE("won_count" bigint, "lost_count" bigint, "won_unvalued_count" bigint, "lost_unvalued_count" bigint, "won_value_minor" bigint, "lost_value_minor" bigint, "direct_job_count" bigint, "direct_job_unvalued_count" bigint, "direct_job_value_minor" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  can_view_value boolean;
  zone text;
  window_start timestamptz;
  window_end timestamptz;
begin
  if not private.member_has_permission(target_organization_id, caller, 'pipeline.view') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_value := private.member_has_permission(target_organization_id, caller, 'pipeline.view_value');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;

  return query
  select count(*) filter (where opportunity.outcome_kind = 'won'),
    count(*) filter (where opportunity.outcome_kind = 'lost'),
    count(*) filter (where opportunity.outcome_kind = 'won' and opportunity.estimated_value is null),
    count(*) filter (where opportunity.outcome_kind = 'lost' and opportunity.estimated_value is null),
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome_kind = 'won'), 0)::bigint
    end,
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome_kind = 'lost'), 0)::bigint
    end,
    count(*) filter (where opportunity.outcome_kind = 'direct_job'),
    count(*) filter (where opportunity.outcome_kind = 'direct_job' and opportunity.estimated_value is null),
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome_kind = 'direct_job'), 0)::bigint
    end
  from public.opportunities as opportunity
  where opportunity.organization_id = target_organization_id
    and opportunity.outcome_kind is not null
    and opportunity.outcome_at >= window_start and opportunity.outcome_at < window_end;
end;
$$;

comment on function public.financial_sales_outcomes_summary(uuid, date, date) is
  'Whole-range counts, unvalued counts and estimated value totals over the same Opportunity set as financial_sales_outcomes_page. Won and Lost are deals that were on the board; Direct jobs are counted apart and are in neither.';

revoke all on function public.financial_sales_outcomes_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_sales_outcomes_summary(uuid, date, date) to authenticated, service_role;
