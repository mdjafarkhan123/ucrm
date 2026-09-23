-- Marketing M5b: attribution.
--
-- M5a made delivery, open, click, unsubscribe, and reply-tagging real. This stage stores the two credits the
-- blueprint (§13) names as facts, not read-time guesses:
--
--   1. Tracked: a public form submitted through a recipient-bound call-to-action link (M5a) carries that
--      token through to the worker that turns the submission into a Request or Job, which stores the credit
--      the moment the work is created. The Request/Job belongs to whoever actually submitted -- a forwarded
--      email still credits the campaign, because the token names the campaign, not a person.
--   2. Declared: authorized staff connect a Request/Job to a campaign after reviewing the Customer and
--      timing. Stored the same way, distinguished only by `source` and `declared_by`.
--
-- The third method -- a 30-day last-touch window over undeclared work -- is never stored (it must stay live
-- as new deliveries happen); `marketing_campaign_window_attribution` computes it at read time for M5c to call.
-- No stage here touches `requests.source` or `clients.lead_source`: a Marketing touch never overwrites the
-- Customer's original lead source (blueprint §13).

-- ---------------------------------------------------------------------------------------------------
-- 1. The submission carries its token from the public POST to the async worker
-- ---------------------------------------------------------------------------------------------------

alter table "private"."form_submissions"
    add column if not exists "marketing_cta_token_hash" bytea;

alter table "private"."form_submissions"
    drop constraint if exists "form_submissions_marketing_cta_token_hash_check";

alter table "private"."form_submissions"
    add constraint "form_submissions_marketing_cta_token_hash_check"
    check ("marketing_cta_token_hash" is null or octet_length("marketing_cta_token_hash") = 32);

comment on column "private"."form_submissions"."marketing_cta_token_hash" is
    'Hash of the ?mc= token on the public form URL, when the visitor arrived through a Marketing call-to-action link. Resolved against marketing_campaign_cta_links by the worker, never trusted from the request twice.';

create or replace function "public"."submit_form_response"(
    "target_organization_slug" "text",
    "target_form_slug" "text",
    "target_idempotency_key" "text",
    "target_contact" "jsonb",
    "target_answers" "jsonb",
    "target_photo_object_keys" "text"[] DEFAULT '{}'::"text"[],
    "target_selected_catalog_item_id" "uuid" DEFAULT NULL::"uuid",
    "target_requested_starts_at" timestamp with time zone DEFAULT NULL::timestamp with time zone,
    "target_requested_ends_at" timestamp with time zone DEFAULT NULL::timestamp with time zone,
    "target_marketing_cta_token_hash" bytea DEFAULT NULL::bytea
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
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

  if target_marketing_cta_token_hash is not null and octet_length(target_marketing_cta_token_hash) <> 32 then
    target_marketing_cta_token_hash := null;
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
      photo_object_keys, selected_catalog_item_id, requested_starts_at, requested_ends_at,
      marketing_cta_token_hash
    ) values (
      resolved_org.id, form_row.id, form_row.current_published_version_id, target_idempotency_key,
      target_contact, target_answers, coalesce(target_photo_object_keys, '{}'::text[]),
      target_selected_catalog_item_id, target_requested_starts_at, target_requested_ends_at,
      target_marketing_cta_token_hash
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

-- ---------------------------------------------------------------------------------------------------
-- 2. Credits: one row per Request/Job that a campaign gets to claim
-- ---------------------------------------------------------------------------------------------------

create table if not exists "public"."marketing_campaign_result_credits" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "campaign_id" uuid not null,
    "marketing_campaign_recipient_id" uuid,
    "source" text not null,
    "request_id" uuid,
    "job_id" uuid,
    "client_id" uuid not null,
    "credited_at" timestamptz not null default now(),
    "declared_by" uuid,
    constraint "marketing_campaign_result_credits_pkey" primary key ("id"),
    constraint "marketing_campaign_result_credits_source_check"
        check ("source" = any (array['tracked'::text, 'declared'::text])),
    -- Exactly one of Request or Job -- the two shapes M5b credits ("a Request, or a Job created without a
    -- Request").
    constraint "marketing_campaign_result_credits_work_check"
        check ((("request_id" is not null) <> ("job_id" is not null))),
    constraint "marketing_campaign_result_credits_declared_by_check"
        check ((("source" = 'declared') = ("declared_by" is not null))),
    constraint "marketing_campaign_result_credits_organization_id_fkey"
        foreign key ("organization_id") references "public"."organizations"("id") on delete cascade,
    constraint "marketing_campaign_result_credits_campaign_fkey"
        foreign key ("organization_id", "campaign_id")
        references "public"."marketing_campaigns"("organization_id", "id") on delete cascade,
    constraint "marketing_campaign_result_credits_recipient_fkey"
        foreign key ("marketing_campaign_recipient_id")
        references "public"."marketing_campaign_recipients"("id") on delete set null,
    constraint "marketing_campaign_result_credits_request_fkey"
        foreign key ("request_id") references "public"."requests"("id") on delete cascade,
    constraint "marketing_campaign_result_credits_job_fkey"
        foreign key ("job_id") references "public"."jobs"("id") on delete cascade,
    constraint "marketing_campaign_result_credits_client_fkey"
        foreign key ("organization_id", "client_id")
        references "public"."clients"("organization_id", "id") on delete cascade,
    constraint "marketing_campaign_result_credits_declared_by_fkey"
        foreign key ("declared_by") references "auth"."users"("id") on delete set null
);

-- One campaign may claim a given Request or Job at most once -- "no work is counted twice" (blueprint §13)
-- starts here, at the strongest (stored) layer.
create unique index if not exists "marketing_campaign_result_credits_request_key"
    on "public"."marketing_campaign_result_credits" using btree ("request_id") where ("request_id" is not null);
create unique index if not exists "marketing_campaign_result_credits_job_key"
    on "public"."marketing_campaign_result_credits" using btree ("job_id") where ("job_id" is not null);
create index if not exists "marketing_campaign_result_credits_campaign_idx"
    on "public"."marketing_campaign_result_credits" using btree ("organization_id", "campaign_id");

comment on table "public"."marketing_campaign_result_credits" is
    'A stored (not read-time) attribution: a Request or Job credited to a Marketing campaign, either because the visitor used that campaign''s recipient-bound call-to-action link (source=tracked, written by process_next_form_submission) or because authorized staff connected the two after review (source=declared, written by declare_marketing_campaign_result_credit). The read-time 30-day window (marketing_campaign_window_attribution) never writes here.';

alter table "public"."marketing_campaign_result_credits" enable row level security;
revoke all on table "public"."marketing_campaign_result_credits" from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 3. Tracked credit: written by the same worker that turns a submission into a Request or Job
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."process_next_form_submission"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
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
  credit_campaign_id uuid;
  credit_recipient_id uuid;
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

    -- Resolved once, up front: a token that no longer matches a link (the link's recipient row was somehow
    -- removed) simply credits nothing, the same as no token at all. It never blocks the submission itself.
    if submission.marketing_cta_token_hash is not null then
      select link.campaign_id, link.marketing_campaign_recipient_id
        into credit_campaign_id, credit_recipient_id
      from public.marketing_campaign_cta_links link
      where link.token_hash = submission.marketing_cta_token_hash
        and link.organization_id = submission.organization_id;
    end if;

    select settings.timezone, settings.currency_code into org_timezone, organization_currency
    from public.organization_settings as settings
    where settings.organization_id = submission.organization_id;
    org_timezone := coalesce(org_timezone, 'UTC');
    organization_currency := coalesce(organization_currency, 'USD');

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

    if credit_campaign_id is not null then
      if new_request_id is not null then
        insert into public.marketing_campaign_result_credits (
          organization_id, campaign_id, marketing_campaign_recipient_id, source, request_id, client_id
        ) values (
          submission.organization_id, credit_campaign_id, credit_recipient_id, 'tracked', new_request_id,
          resolved_client_id
        )
        on conflict (request_id) where request_id is not null do nothing;
      elsif created_job.id is not null then
        insert into public.marketing_campaign_result_credits (
          organization_id, campaign_id, marketing_campaign_recipient_id, source, job_id, client_id
        ) values (
          submission.organization_id, credit_campaign_id, credit_recipient_id, 'tracked', created_job.id,
          resolved_client_id
        )
        on conflict (job_id) where job_id is not null do nothing;
      end if;
    end if;

    update private.form_submissions
    set status = 'processed', processed_at = now(), result = outcome_payload
    where id = submission.id;

    return jsonb_build_object('status', 'processed', 'submission_id', submission.id) || outcome_payload;
  exception
    when others then
      update private.form_submissions
      set status = 'failed', processed_at = now(), processing_error = sqlerrm
      where id = submission.id;
      return jsonb_build_object('status', 'failed', 'submission_id', submission.id, 'error', sqlerrm);
  end;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 4. Declared credit: authorized staff connect a Request/Job to a campaign after review
-- ---------------------------------------------------------------------------------------------------

-- The marketing.draft permission (the same tier that edits customer groups, templates, and drafts) is
-- enforced by the calling route, exactly as marketing_cancel_campaign's comment describes for every other
-- Marketing command -- this function trusts the organization and actor it is given.
create or replace function "public"."declare_marketing_campaign_result_credit"(
    "target_organization_id" uuid,
    "target_campaign_id" uuid,
    "target_request_id" uuid default null,
    "target_job_id" uuid default null,
    "actor_user_id" uuid default null
) returns "public"."marketing_campaign_result_credits"
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    resolved_client_id uuid;
    credit_row public.marketing_campaign_result_credits;
begin
    if (target_request_id is null) = (target_job_id is null) then
        raise exception 'Choose exactly one Request or Job to credit.' using errcode = 'check_violation';
    end if;

    if not exists (
        select 1 from public.marketing_campaigns
        where id = target_campaign_id and organization_id = target_organization_id
    ) then
        raise exception 'That campaign no longer exists.' using errcode = 'check_violation';
    end if;

    if target_request_id is not null then
        select client_id into resolved_client_id from public.requests
        where id = target_request_id and organization_id = target_organization_id;
    else
        select client_id into resolved_client_id from public.jobs
        where id = target_job_id and organization_id = target_organization_id;
    end if;

    if resolved_client_id is null then
        raise exception 'That work no longer exists.' using errcode = 'check_violation';
    end if;

    insert into public.marketing_campaign_result_credits (
        organization_id, campaign_id, source, request_id, job_id, client_id, declared_by
    ) values (
        target_organization_id, target_campaign_id, 'declared', target_request_id, target_job_id,
        resolved_client_id, actor_user_id
    )
    returning * into credit_row;

    return credit_row;
exception
    when unique_violation then
        raise exception 'That work is already credited to a campaign.' using errcode = 'unique_violation';
end;
$$;

revoke all on function "public"."declare_marketing_campaign_result_credit"(uuid, uuid, uuid, uuid, uuid)
    from public, anon, authenticated;
grant all on function "public"."declare_marketing_campaign_result_credit"(uuid, uuid, uuid, uuid, uuid)
    to "service_role";

-- ---------------------------------------------------------------------------------------------------
-- 5. The 30-day window, computed live -- never stored, so a later delivery cannot retroactively rewrite
--    history and an uncredited work item always reflects the best fact known right now.
-- ---------------------------------------------------------------------------------------------------

-- Bounds the window lookup to this one Customer's delivered recipient rows, regardless of how many
-- campaigns the organization has sent overall -- without it this becomes a growing per-organization scan.
create index if not exists "marketing_campaign_recipients_client_delivered_idx"
    on "public"."marketing_campaign_recipients" using btree ("organization_id", "client_id", "delivered_at" desc)
    where ("delivered_at" is not null);

create or replace function "public"."marketing_campaign_window_attribution"(
    "target_organization_id" uuid,
    "target_client_id" uuid,
    "target_work_created_at" timestamptz,
    "window_days" integer default 30
) returns table("campaign_id" uuid, "marketing_campaign_recipient_id" uuid, "delivered_at" timestamptz)
    language sql stable
    set search_path to 'pg_catalog', 'public'
    as $$
    select recipient.campaign_id, recipient.id, recipient.delivered_at
    from public.marketing_campaign_recipients recipient
    where recipient.organization_id = target_organization_id
      and recipient.client_id = target_client_id
      and recipient.delivered_at is not null
      and recipient.delivered_at <= target_work_created_at
      and recipient.delivered_at > target_work_created_at - make_interval(days => window_days)
    order by recipient.delivered_at desc
    limit 1;
$$;

comment on function "public"."marketing_campaign_window_attribution"(uuid, uuid, timestamptz, integer) is
    'Last-touch, read-time only (blueprint §13 method 3): the most recent campaign delivered to this Customer within the window before the given work was created. Callers apply this only when the work has no stored credit (tracked or declared) -- those are always stronger. Never writes marketing_campaign_result_credits.';

revoke all on function "public"."marketing_campaign_window_attribution"(uuid, uuid, timestamptz, integer)
    from public, anon, authenticated;
grant execute on function "public"."marketing_campaign_window_attribution"(uuid, uuid, timestamptz, integer)
    to "service_role";
