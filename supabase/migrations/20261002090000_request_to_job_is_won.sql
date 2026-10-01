-- Pipeline B1: a Request turned straight into a Job is a Won deal.
--
-- Jobber's "Convert to Job" opens the ordinary new-job form filled in from the request, and the request only
-- becomes Converted when that job is saved. This follows it: the one direct job create learns which request
-- it came from, and in the same transaction marks the request Converted and its Pipeline card Won, with the
-- card's value frozen from the job total. A job made from an already-approved quote goes through
-- convert_quote_to_job, which never touched this path, so it cannot add a second win.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Lineage. A job remembers the request it was converted from, the same way it remembers its quote.
-- ---------------------------------------------------------------------------------------------------------

alter table public.jobs
  add column request_id uuid,
  add constraint jobs_request_organization_fk
    foreign key (organization_id, request_id)
    references public.requests (organization_id, id) on delete restrict,
  add constraint jobs_single_source check (request_id is null or quote_id is null);

comment on column public.jobs.request_id is
  'Set when the job was converted straight from a request, skipping the quote. A job made from a quote keeps quote_id instead, never both. Permanent, like quote lineage.';

grant select (request_id) on table public.jobs to authenticated;

-- One job per request, mirroring one job per quote. Also the index the foreign key is checked through.
create unique index jobs_request_lineage_idx
  on public.jobs (organization_id, request_id)
  where request_id is not null;

-- ---------------------------------------------------------------------------------------------------------
-- 2. The job row writer takes the request it came from, and the identity guard keeps it there.
-- ---------------------------------------------------------------------------------------------------------

drop function private.create_job(uuid, uuid, uuid, text, text, text, text, uuid, boolean, text, text, uuid, uuid, text, text);

CREATE OR REPLACE FUNCTION "private"."create_job"("target_organization_id" "uuid", "target_client_id" "uuid", "target_property_id" "uuid", "new_title" "text", "new_job_type" "text", "new_price_basis" "text", "new_currency_code" "text", "actor" "uuid", "new_is_as_needed" boolean DEFAULT false, "new_billing_timing" "text" DEFAULT 'on_closure'::"text", "new_instructions" "text" DEFAULT NULL::"text", "source_quote_id" "uuid" DEFAULT NULL::"uuid", "source_quote_version_id" "uuid" DEFAULT NULL::"uuid", "idempotency_key" "text" DEFAULT NULL::"text", "request_hash" "text" DEFAULT NULL::"text", "source_request_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  created public.jobs;
  clean_title text := nullif(trim(coalesce(new_title, '')), '');
begin
  if clean_title is null or char_length(clean_title) < 2 or char_length(clean_title) > 160 then
    raise exception 'A job needs a title between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  -- The property has to belong to the client, and both have to belong to the organization. The composite
  -- foreign keys already stop a cross-tenant row; this stops a same-tenant mismatch with a sentence a person
  -- can act on.
  if not exists (
    select 1 from public.properties
    where id = target_property_id
      and organization_id = target_organization_id
      and client_id = target_client_id
  ) then
    raise exception 'That property does not belong to that client.' using errcode = 'check_violation';
  end if;

  insert into public.jobs (
    organization_id, client_id, property_id, quote_id, quote_version_id, request_id, job_number, title,
    job_type, is_as_needed, price_basis, billing_timing, currency_code, instructions,
    conversion_idempotency_key, conversion_request_hash, created_by
  ) values (
    target_organization_id,
    target_client_id,
    target_property_id,
    source_quote_id,
    source_quote_version_id,
    source_request_id,
    private.allocate_job_number(target_organization_id),
    clean_title,
    new_job_type,
    coalesce(new_is_as_needed, false),
    new_price_basis,
    coalesce(new_billing_timing, 'on_closure'),
    new_currency_code,
    nullif(trim(coalesce(new_instructions, '')), ''),
    idempotency_key,
    request_hash,
    actor
  )
  returning * into created;

  insert into public.job_events (
    organization_id, job_id, event_type, actor_id, new_status, related_quote_id, metadata
  ) values (
    target_organization_id,
    created.id,
    'job_created',
    actor,
    'active',
    source_quote_id,
    jsonb_build_object(
      'job_type', new_job_type,
      'from_quote', source_quote_id is not null,
      'from_request', source_request_id is not null
    )
  );

  return created;
end;
$$;

revoke all on function private.create_job(uuid, uuid, uuid, text, text, text, text, uuid, boolean, text, text, uuid, uuid, text, text, uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION "private"."jobs_guard_identity_and_transitions"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'A job cannot be moved to another organization.' using errcode = 'check_violation';
  end if;
  if new.job_number is distinct from old.job_number then
    raise exception 'A job number cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.job_type is distinct from old.job_type or new.is_as_needed is distinct from old.is_as_needed then
    raise exception 'A job type cannot be changed after the job is created. Create a new job instead.'
      using errcode = 'check_violation';
  end if;
  if new.client_id is distinct from old.client_id then
    raise exception 'A job cannot be moved to another client.' using errcode = 'check_violation';
  end if;
  -- Lineage is permanent in both directions: a converted job can never forget its quote, and a direct job can
  -- never claim one it did not come from.
  if new.quote_id is distinct from old.quote_id or new.quote_version_id is distinct from old.quote_version_id then
    raise exception 'Quote lineage cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.request_id is distinct from old.request_id then
    raise exception 'Request lineage cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'A job creation time cannot be changed.' using errcode = 'check_violation';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'active' and new.status = 'closed')
      or (old.status = 'closed' and new.status = 'active')
    ) then
      raise exception 'A job cannot go from % to %.', old.status, new.status
        using errcode = 'check_violation';
    end if;

    if new.status = 'closed' and new.closed_at is null then
      new.closed_at := now();
    end if;
    if new.status = 'active' then
      new.closed_at := null;
      new.closed_by := null;
      new.reopened_at := now();
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 3. The direct job create, now also the request conversion.
-- ---------------------------------------------------------------------------------------------------------

drop function public.create_job_with_visits(uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb);

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

  if source_request_id is not null then
    -- This one update is also what takes the request card off the board: the resync trigger recomputes its
    -- stage from the new status, exactly as it does when a request becomes a quote.
    update public.requests set status = 'converted' where id = request_row.id;

    -- Won once. A card that is already decided keeps the decision it has. The value is frozen from the job
    -- total as it stands at this moment; a job saved with no priced lines has no total yet, so the card is
    -- Unvalued rather than worth a made-up zero. Nothing later rewrites it.
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
          estimated_value = case
            when line_count > 0
              then least((calculated->>'total_minor')::numeric / 100, 9999999999.99)
          end,
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

comment on function public.create_job_with_visits(uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb, uuid) is
  'The one direct job create. One-off with typed visits, recurring generated from a rule, or as-needed with neither. Given a source request it is also the request-to-job conversion: the request becomes Converted and its Pipeline card Won with the job total, in the same transaction. Idempotent per (organization, key) through job_command_receipts.';

revoke all on function public.create_job_with_visits(uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb, uuid) from public, anon;
grant execute on function public.create_job_with_visits(uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb, uuid) to authenticated, service_role;
