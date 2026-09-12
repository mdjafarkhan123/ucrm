-- Contractor Settings, Part 4D: atomic submission outcomes.
--
-- Part 4C safely caught and held a public submission in `private.form_submissions`. This part turns each
-- held row into the real thing exactly once: a Request, a Request + confirmed Assessment, or a Job + first
-- Visit -- matching Jobber's own bookingType behavior (NONE = request only, ASSESSMENT = request + on-site
-- visit, JOB = books straight into the schedule, see jobber-02-requests-leads.md §3.3).
--
-- Three pieces:
--
--   1. `submit_form_response` is revised to hold the exact slot a booking-outcome customer picked
--      synchronously, at submit time -- the reservation primitive 4B-2b built and explicitly reserved for
--      "Part 4D's submission command" to call. A lost race is told to the customer immediately (Calendly/
--      Jobber-style instant booking), not silently double-booked or discovered later by staff. An
--      assessment form with `requires_booking_approval` on skips this entirely: Jobber's own behavior is
--      that an approval-gated booking never touches the schedule until staff accepts it, so nothing is
--      reserved for it either. A job form always instant-books -- that field's own help text names it
--      "assessment booking approval," and a job booking form's whole point (Jobber's words: "books a
--      service directly into your schedule") is that it does not wait for a human glance.
--
--   2. `private.form_submissions` gains the two facts (1) needs to remember: which team member's calendar
--      was reserved, and which reservation row holds it. Both stay null for a request-only form or an
--      approval-gated assessment, where nothing is reserved yet.
--
--   3. `process_next_form_submission` is the one worker entry point: claim the oldest pending row
--      (`for update skip locked`, the same competing-consumer primitive the geocoding queue already uses),
--      resolve or create the customer the same conservative way Website Chat already does (one unambiguous
--      email/phone match connects; anything ambiguous or absent creates a new lead -- a Request's `client_id`
--      is `not null`, so unlike chat's "needs_review" thread there is no "leave it unattached" option here),
--      create the property the structured address resolved, and write the one correct outcome. All of it
--      runs inside the same transaction the row was claimed under: a permanent failure (the form got
--      archived mid-flight, say) is caught and recorded on the row rather than raised, so one bad row can
--      never wedge the queue, and a crash mid-transaction simply leaves the row 'pending' for the next wake
--      to retry -- exactly the geocoding worker's own recovery story.
--
-- `requests.status` gains `needs_approval` -- Jobber's own label for a booking form submission that
-- `requires_booking_approval` held back from the schedule. It behaves exactly like every other stored
-- status already does in `deriveRequestStatus` (src/lib/server/requests/status.ts): a request with no
-- assessment yet keeps its stored status untouched by the calendar-derived branch.

-- ---------------------------------------------------------------------------------------------------------
-- 1. requests.status gains 'needs_approval'
-- ---------------------------------------------------------------------------------------------------------

alter table public.requests drop constraint requests_status_check;
alter table public.requests add constraint requests_status_check
  check (status in (
    'new', 'unscheduled', 'assessment_completed', 'completed', 'converted', 'archived', 'needs_approval'
  ));

comment on column public.requests.status is
  'Stored status. needs_approval (Part 4D) is a public assessment-booking submission held for staff review '
  'because its form requires booking approval -- nothing is reserved on the calendar for it yet. The three '
  'calendar-derived values (today/upcoming/overdue) are never written here.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. What a held submission remembers about its reserved slot
-- ---------------------------------------------------------------------------------------------------------

alter table private.form_submissions
  add column assigned_user_id uuid,
  add column booking_reservation_id uuid,
  add column result jsonb;

alter table private.form_submissions
  add constraint form_submissions_assigned_member_fk foreign key (organization_id, assigned_user_id)
    references public.organization_members(organization_id, user_id) on delete set null,
  add constraint form_submissions_reservation_fk foreign key (booking_reservation_id)
    references private.form_booking_reservations(id) on delete set null;

comment on column private.form_submissions.assigned_user_id is
  'The team member whose calendar submit_form_response reserved for this exact slot. Null for a request-only '
  'form and for an approval-gated assessment, where nothing is reserved until staff acts.';
comment on column private.form_submissions.booking_reservation_id is
  'The private.form_booking_reservations row submit_form_response claimed at submit time, carried forward so '
  'the worker never re-derives or re-claims it.';
comment on column private.form_submissions.result is
  'Filled once processed: which client/property/request/assessment/job/visit this submission became, for '
  'support and debugging traceability back from one submission to its records.';

-- ---------------------------------------------------------------------------------------------------------
-- 3. submit_form_response: hold the exact slot synchronously, for outcomes that instant-book
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.submit_form_response(
  target_organization_slug text,
  target_form_slug text,
  target_idempotency_key text,
  target_contact jsonb,
  target_answers jsonb,
  target_photo_object_keys text[] default '{}',
  target_selected_catalog_item_id uuid default null,
  target_requested_starts_at timestamptz default null,
  target_requested_ends_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  resolved_org public.organizations;
  form_row public.forms;
  rules public.form_booking_rules;
  key_prefix text;
  bad_key text;
  existing_id uuid;
  new_id uuid;
  max_photos constant integer := 20;
  max_json_bytes constant integer := 32768;
  skip_reservation boolean;
  org_timezone text;
  local_start timestamp;
  local_end timestamp;
  resolved_member uuid;
  reservation_id uuid;
begin
  if target_idempotency_key is null or char_length(trim(target_idempotency_key)) = 0
    or char_length(target_idempotency_key) > 200
  then
    raise exception 'That submission could not be read.' using errcode = 'check_violation';
  end if;

  select * into resolved_org from public.organizations
  where slug = target_organization_slug and lifecycle_status = 'active';
  if resolved_org.id is null then
    raise exception 'That form is not available.' using errcode = 'check_violation';
  end if;

  select * into form_row from public.forms
  where organization_id = resolved_org.id
    and public_slug = target_form_slug
    and archived_at is null
    and is_enabled
    and current_published_version_id is not null;
  if form_row.id is null then
    raise exception 'That form is not available.' using errcode = 'check_violation';
  end if;

  if form_row.outcome = 'request' then
    if target_selected_catalog_item_id is not null
      or target_requested_starts_at is not null or target_requested_ends_at is not null
    then
      raise exception 'This form does not book a time.' using errcode = 'check_violation';
    end if;
  else
    if target_requested_starts_at is null or target_requested_ends_at is null then
      raise exception 'Choose a time for this visit.' using errcode = 'check_violation';
    end if;
    if target_selected_catalog_item_id is not null and not exists (
      select 1 from public.form_bookable_services
      where form_id = form_row.id and catalog_item_id = target_selected_catalog_item_id
    ) then
      raise exception 'Choose one of the listed services.' using errcode = 'check_violation';
    end if;

    -- Re-checked here for the same reason every other claim in this function is: the booking rules the app
    -- layer already validated against are re-read and re-applied against the caller's own numbers, never
    -- trusted a second time.
    select * into rules from public.form_booking_rules
    where form_id = form_row.id and organization_id = resolved_org.id;
    if rules.form_id is null then
      raise exception 'This form has no booking rules.' using errcode = 'check_violation';
    end if;
    if target_requested_ends_at - target_requested_starts_at
        <> make_interval(mins => rules.visit_duration_minutes) then
      raise exception 'Choose a valid time for this visit.' using errcode = 'check_violation';
    end if;
    if target_requested_starts_at < now() + make_interval(mins => rules.min_notice_minutes) then
      raise exception 'That time is no longer available. Please choose another.'
        using errcode = 'check_violation';
    end if;
  end if;

  if target_contact is null or jsonb_typeof(target_contact) <> 'object'
    or length(target_contact::text) > max_json_bytes
  then
    raise exception 'That submission could not be read.' using errcode = 'check_violation';
  end if;
  if target_answers is null or jsonb_typeof(target_answers) <> 'object'
    or length(target_answers::text) > max_json_bytes
  then
    raise exception 'That submission could not be read.' using errcode = 'check_violation';
  end if;

  if target_photo_object_keys is not null and array_length(target_photo_object_keys, 1) > max_photos then
    raise exception 'Too many photos on one submission.' using errcode = 'check_violation';
  end if;

  if target_photo_object_keys is not null then
    key_prefix := resolved_org.id || '/public-form-submissions/' || form_row.id || '/';
    select each_key into bad_key
    from unnest(target_photo_object_keys) as each_key
    where left(each_key, char_length(key_prefix)) <> key_prefix
    limit 1;
    if bad_key is not null then
      raise exception 'That photo does not belong to this form.' using errcode = 'check_violation';
    end if;
  end if;

  select id into existing_id from private.form_submissions
  where form_id = form_row.id and idempotency_key = target_idempotency_key;
  if existing_id is not null then
    return jsonb_build_object('submission_id', existing_id, 'already_received', true);
  end if;

  begin
    insert into private.form_submissions (
      organization_id, form_id, form_version_id, idempotency_key, contact, answers,
      photo_object_keys, selected_catalog_item_id, requested_starts_at, requested_ends_at
    ) values (
      resolved_org.id, form_row.id, form_row.current_published_version_id, target_idempotency_key,
      target_contact, target_answers, coalesce(target_photo_object_keys, '{}'::text[]),
      target_selected_catalog_item_id, target_requested_starts_at, target_requested_ends_at
    )
    returning id into new_id;
  exception
    when unique_violation then
      -- A concurrent retry of the same idempotency key lost the race; the row it collided with is the real
      -- answer, not an error the customer should see. Nothing is reserved on this path -- the winning
      -- request already holds (or is about to hold) the only reservation that matters.
      select id into new_id from private.form_submissions
      where form_id = form_row.id and idempotency_key = target_idempotency_key;
      return jsonb_build_object('submission_id', new_id, 'already_received', true);
  end;

  -- Only the genuine first insert of a new idempotency key reaches here, so the slot is claimed exactly
  -- once per real submission -- never wasted on a retry, never skipped for the one request that needed it.
  if form_row.outcome <> 'request' then
    skip_reservation := (form_row.outcome = 'assessment' and rules.requires_booking_approval);

    if not skip_reservation then
      select settings.timezone into org_timezone
      from public.organization_settings as settings
      where settings.organization_id = resolved_org.id;
      org_timezone := coalesce(org_timezone, 'UTC');

      local_start := target_requested_starts_at at time zone org_timezone;
      local_end := target_requested_ends_at at time zone org_timezone;

      resolved_member := private.form_booking_free_member_for_slot(
        resolved_org.id, local_start, local_end, rules.buffer_minutes, org_timezone
      );
      if resolved_member is null then
        raise exception 'That time is no longer available. Please choose another.'
          using errcode = 'check_violation';
      end if;

      reservation_id := public.claim_form_booking_reservation(
        resolved_org.id, form_row.id, resolved_member, target_requested_starts_at, target_requested_ends_at
      );
      if reservation_id is null then
        raise exception 'That time is no longer available. Please choose another.'
          using errcode = 'check_violation';
      end if;

      update private.form_submissions
      set assigned_user_id = resolved_member, booking_reservation_id = reservation_id
      where id = new_id;
    end if;
  end if;

  return jsonb_build_object('submission_id', new_id, 'already_received', false);
end;
$$;

comment on function public.submit_form_response(
  text, text, text, jsonb, jsonb, text[], uuid, timestamptz, timestamptz
) is
  'Safely receives one public form answer into private.form_submissions. Re-checks everything the /api '
  'route already validated because an anonymous caller''s own claims are never trusted twice. Idempotent by '
  '{form, idempotency key}. For an instant-booking outcome (any job form, or an assessment form that does '
  'not require approval) it also claims the exact reservation Part 4D''s worker will honor, synchronously, '
  'so a lost race is told to the customer immediately.';

revoke all on function public.submit_form_response(
  text, text, text, jsonb, jsonb, text[], uuid, timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function public.submit_form_response(
  text, text, text, jsonb, jsonb, text[], uuid, timestamptz, timestamptz
) to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 4. The worker's one entry point: claim one pending row and turn it into the real thing
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.process_next_form_submission()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  submission private.form_submissions;
  form_row public.forms;
  rules public.form_booking_rules;
  org_active boolean;
  version_content jsonb;
  clean_name text;
  given_name text;
  family_name text;
  first_space integer;
  match_phone text;
  match_email text;
  phone_candidate uuid;
  email_candidate uuid;
  phone_match_count integer := 0;
  email_match_count integer := 0;
  resolved_client_id uuid;
  is_new_client boolean := false;
  new_client_id uuid;
  address jsonb;
  has_address boolean;
  resolved_property_id uuid;
  description_text text;
  org_timezone text;
  organization_currency text;
  new_request_id uuid;
  new_assessment_id uuid;
  created_job public.jobs;
  new_visit public.job_visits;
  catalog_row public.catalog_items;
  preferred_time_text text;
  outcome_kind text;
  calculated jsonb;
  outcome_payload jsonb;
begin
  select * into submission
  from private.form_submissions
  where status = 'pending'
  order by created_at
  for update skip locked
  limit 1;

  if not found then
    return jsonb_build_object('status', 'idle');
  end if;

  begin
    select * into form_row from public.forms where id = submission.form_id;
    select exists (
      select 1 from public.organizations
      where id = submission.organization_id and lifecycle_status = 'active'
    ) into org_active;

    if form_row.id is null or not org_active or form_row.archived_at is not null
      or not form_row.is_enabled or form_row.current_published_version_id is null
    then
      raise exception 'That form is no longer available.' using errcode = 'check_violation';
    end if;

    select settings.timezone, settings.currency_code into org_timezone, organization_currency
    from public.organization_settings as settings
    where settings.organization_id = submission.organization_id;
    org_timezone := coalesce(org_timezone, 'UTC');
    organization_currency := coalesce(organization_currency, 'USD');

    -- 4.1 Match or create the customer -- the exact conservative rule already proven for Website Chat
    -- (accept_website_chat_first_message): one unambiguous email/phone match connects; anything ambiguous
    -- or absent creates a new lead. A Request's client_id is not null, so unlike chat's "needs_review"
    -- thread there is no "leave it unattached" outcome here -- ambiguous also means "create a new lead."
    -- The org-wide unique index on (organization_id, kind, normalized_value) means the count>1 branches below
    -- can never fire from real data (one value belongs to at most one client); they stay as cheap defense in
    -- depth against a future relaxed constraint or a direct-SQL import. The genuinely reachable ambiguity is
    -- phone-points-to-one-client while email-points-to-another (phone_candidate <> email_candidate).
    match_phone := nullif(regexp_replace(coalesce(submission.contact->>'phone', ''), '[^0-9]', '', 'g'), '');
    match_email := lower(nullif(trim(coalesce(submission.contact->>'email', '')), ''));

    if match_phone is not null then
      select count(distinct method.client_id), min(method.client_id::text)::uuid
      into phone_match_count, phone_candidate
      from public.client_contact_methods method
      join public.clients client
        on client.organization_id = method.organization_id and client.id = method.client_id
      where method.organization_id = submission.organization_id
        and method.kind = 'phone'
        and method.normalized_value = match_phone
        and client.deleted_at is null;
      if phone_match_count <> 1 then phone_candidate := null; end if;
    end if;

    if match_email is not null then
      select count(distinct method.client_id), min(method.client_id::text)::uuid
      into email_match_count, email_candidate
      from public.client_contact_methods method
      join public.clients client
        on client.organization_id = method.organization_id and client.id = method.client_id
      where method.organization_id = submission.organization_id
        and method.kind = 'email'
        and method.normalized_value = match_email
        and client.deleted_at is null;
      if email_match_count <> 1 then email_candidate := null; end if;
    end if;

    if phone_match_count > 1 or email_match_count > 1
      or (phone_candidate is not null and email_candidate is not null and phone_candidate <> email_candidate)
    then
      resolved_client_id := null;
    else
      resolved_client_id := coalesce(phone_candidate, email_candidate);
    end if;

    if resolved_client_id is null then
      is_new_client := true;
      clean_name := coalesce(
        nullif(btrim(regexp_replace(coalesce(submission.contact->>'name', ''), '\s+', ' ', 'g')), ''),
        'Website visitor'
      );
      first_space := position(' ' in clean_name);
      if first_space > 0 then
        given_name := substr(clean_name, 1, first_space - 1);
        family_name := nullif(btrim(substr(clean_name, first_space + 1)), '');
      else
        given_name := clean_name;
        family_name := null;
      end if;

      insert into public.clients (
        organization_id, display_name, first_name, last_name, lifecycle_status, lead_source, client_type
      ) values (
        submission.organization_id, clean_name, given_name, family_name, 'lead',
        'Website form: ' || form_row.name, 'person'
      ) returning id into new_client_id;
      resolved_client_id := new_client_id;

      -- The only way a new lead is created while a contact value is present is that the value is either
      -- brand-new, or it disagrees between two existing clients (phone points to one, email to another) --
      -- the ambiguous case that resolved to null above. An org-wide unique index already owns that value
      -- for the other client, so copying it here would raise and lose the whole inbound lead. Conservative
      -- identity resolution never auto-merges on a conflicting identifier and never drops the inbound: skip
      -- the identifier that already belongs to someone else (on conflict do nothing) and keep the new lead +
      -- Request for staff to review and merge. A brand-new value has no conflict and inserts normally.
      if match_phone is not null then
        insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
        values (submission.organization_id, new_client_id, 'phone', match_phone, true)
        on conflict do nothing;
      end if;
      if match_email is not null then
        insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
        values (submission.organization_id, new_client_id, 'email', match_email, true)
        on conflict do nothing;
      end if;
    end if;

    -- 4.2 The property this work happens at. A known customer with no new address on this submission keeps
    -- using their existing primary property; everyone else gets one built from what was submitted. Two of
    -- Property's own columns (address_line1, city) are not-null, so a form that hides the address field
    -- still needs a placeholder -- a real gap, not a guess: staff can correct it before scheduling.
    address := submission.contact->'address';
    has_address := address is not null and jsonb_typeof(address) = 'object'
      and coalesce(nullif(btrim(address->>'line1'), ''), '') <> '';

    if not is_new_client and not has_address then
      select id into resolved_property_id from public.properties
      where client_id = resolved_client_id and is_primary and deleted_at is null
      limit 1;
    end if;

    if resolved_property_id is null then
      insert into public.properties (organization_id, client_id, address_line1, city, state_region, postal_code)
      values (
        submission.organization_id, resolved_client_id,
        coalesce(nullif(btrim(address->>'line1'), ''), 'Address not provided'),
        coalesce(nullif(btrim(address->>'city'), ''), 'Unknown'),
        nullif(btrim(address->>'state_region'), ''),
        nullif(btrim(address->>'postal_code'), '')
      ) returning id into resolved_property_id;
    end if;

    -- 4.3 What the customer actually said, rendered from the published version's own question labels --
    -- answers are keyed by question id, never by label, so this is the one place that ever joins them back.
    select fv.content into version_content
    from public.form_versions fv
    where fv.id = submission.form_version_id;

    select string_agg((q.value->>'label') || ': ' || a.answer_text, e'\n' order by s.section_ord, q.question_ord)
    into description_text
    from jsonb_array_elements(coalesce(version_content->'sections', '[]'::jsonb))
      with ordinality as s(value, section_ord)
    cross join lateral jsonb_array_elements(coalesce(s.value->'questions', '[]'::jsonb))
      with ordinality as q(value, question_ord)
    cross join lateral (
      select case jsonb_typeof(submission.answers -> (q.value->>'id'))
        when 'array' then (
          select string_agg(elem #>> '{}', ', ')
          from jsonb_array_elements(submission.answers -> (q.value->>'id')) as elem
        )
        when 'string' then submission.answers ->> (q.value->>'id')
        when 'number' then submission.answers ->> (q.value->>'id')
        when 'boolean' then case (submission.answers ->> (q.value->>'id'))
          when 'true' then 'Yes' when 'false' then 'No' else null end
        else null
      end as answer_text
    ) a
    where submission.answers ? (q.value->>'id') and coalesce(a.answer_text, '') <> '';

    -- 4.4 The one correct outcome for this form.
    if form_row.outcome = 'request' then
      insert into public.requests (organization_id, client_id, property_id, title, description)
      values (
        submission.organization_id, resolved_client_id, resolved_property_id,
        coalesce(nullif(btrim(form_row.name), ''), 'Website request'), description_text
      ) returning id into new_request_id;

      outcome_payload := jsonb_build_object(
        'outcome', 'request', 'client_id', resolved_client_id, 'property_id', resolved_property_id,
        'request_id', new_request_id
      );

    elsif form_row.outcome = 'assessment' then
      select * into rules from public.form_booking_rules
      where form_id = form_row.id and organization_id = submission.organization_id;

      outcome_kind := case
        when rules.requires_booking_approval or submission.assigned_user_id is null then 'needs_approval'
        else 'confirmed'
      end;

      if outcome_kind = 'needs_approval' then
        preferred_time_text := 'Customer requested '
          || to_char(submission.requested_starts_at at time zone org_timezone, 'Dy, Mon DD "at" HH12:MI AM')
          || ' - '
          || to_char(submission.requested_ends_at at time zone org_timezone, 'HH12:MI AM');
      end if;

      insert into public.requests (
        organization_id, client_id, property_id, title, description, status, preferred_time
      ) values (
        submission.organization_id, resolved_client_id, resolved_property_id,
        coalesce(nullif(btrim(form_row.name), ''), 'Website request'), description_text,
        case when outcome_kind = 'needs_approval' then 'needs_approval' else 'new' end,
        preferred_time_text
      ) returning id into new_request_id;

      if outcome_kind = 'confirmed' then
        insert into public.assessments (organization_id, request_id, starts_at, ends_at)
        values (
          submission.organization_id, new_request_id, submission.requested_starts_at, submission.requested_ends_at
        ) returning id into new_assessment_id;

        insert into public.assessment_assignees (organization_id, assessment_id, user_id)
        values (submission.organization_id, new_assessment_id, submission.assigned_user_id);
      end if;

      outcome_payload := jsonb_build_object(
        'outcome', case when outcome_kind = 'needs_approval' then 'assessment_needs_approval' else 'assessment' end,
        'client_id', resolved_client_id, 'property_id', resolved_property_id,
        'request_id', new_request_id, 'assessment_id', new_assessment_id
      );

    elsif form_row.outcome = 'job' then
      -- A job booking form always books straight into the schedule (Jobber's own description of bookingType
      -- JOB) -- submit_form_response already guaranteed a held reservation and an assigned member for it.
      created_job := private.create_job(
        submission.organization_id, resolved_client_id, resolved_property_id,
        coalesce(nullif(btrim(form_row.name), ''), 'Website booking'),
        'one_off', 'job_total', organization_currency, null, false, 'on_closure',
        description_text, null, null, null, null
      );

      if submission.selected_catalog_item_id is not null then
        select * into catalog_row from public.catalog_items where id = submission.selected_catalog_item_id;
        if catalog_row.id is not null then
          insert into public.job_line_items (
            organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
            name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable
          ) values (
            created_job.organization_id, created_job.id, 0, catalog_row.id, 'priced', catalog_row.category,
            catalog_row.is_labor, catalog_row.name, catalog_row.description, catalog_row.unit_label, 1,
            catalog_row.unit_price_minor, catalog_row.unit_cost_minor, catalog_row.is_taxable
          );
        end if;
      end if;

      insert into public.job_visits (organization_id, job_id, position, visit_date, start_time, end_time, source)
      values (
        created_job.organization_id, created_job.id, 0,
        (submission.requested_starts_at at time zone org_timezone)::date,
        (submission.requested_starts_at at time zone org_timezone)::time,
        (submission.requested_ends_at at time zone org_timezone)::time,
        'manual'
      ) returning * into new_visit;

      insert into public.job_visit_assignments (organization_id, visit_id, user_id)
      values (created_job.organization_id, new_visit.id, submission.assigned_user_id);

      calculated := private.store_job_money(created_job.id);

      outcome_payload := jsonb_build_object(
        'outcome', 'job', 'client_id', resolved_client_id, 'property_id', resolved_property_id,
        'job_id', created_job.id, 'job_number', created_job.job_number, 'visit_id', new_visit.id
      );
    end if;

    update private.form_submissions
    set status = 'processed', processed_at = now(), result = outcome_payload
    where id = submission.id;

    return jsonb_build_object('status', 'processed', 'submission_id', submission.id) || outcome_payload;
  exception
    when others then
      -- A permanent failure (the form got archived mid-flight, a data-integrity surprise) is recorded on
      -- the row, never raised -- raising here would abort the transaction that claimed it, leaving it
      -- 'pending' forever and wedging every submission behind it in the queue.
      update private.form_submissions
      set status = 'failed', processed_at = now(), processing_error = sqlerrm
      where id = submission.id;
      return jsonb_build_object('status', 'failed', 'submission_id', submission.id, 'error', sqlerrm);
  end;
end;
$$;

comment on function public.process_next_form_submission() is
  'The worker''s one entry point. Claims the oldest pending form_submissions row (for update skip locked, '
  'same competing-consumer primitive as the geocoding queue), turns it into a Request, a Request + confirmed '
  'Assessment, a needs_approval Request, or a Job + first Visit, and marks it processed -- all in one '
  'transaction, so a crash mid-flight simply leaves it pending for the next wake to retry. Returns '
  '{status: idle} when the queue is empty.';

revoke all on function public.process_next_form_submission() from public, anon, authenticated;
grant execute on function public.process_next_form_submission() to service_role;

notify pgrst, 'reload schema';
