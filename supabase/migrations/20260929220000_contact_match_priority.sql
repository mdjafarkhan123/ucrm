-- Contact matching priority, following HighLevel's Contact deduplication preferences
-- (help.gohighlevel.com/support/solutions/articles/48001181714, read 2026-09-29): a contractor chooses whether
-- a new website chat or form submission is matched to an existing Client by email first (the default) or by
-- phone first; the other identifier is only the fallback. Approved by Jafar 2026-09-29.
--
-- Before this, a visitor whose phone belonged to one Client and whose email belonged to another was parked as
-- a "Needs review" chat every single time (a person's choice was never remembered), and a website form in the
-- same situation created a third Client with neither contact. A phone or an email belongs to at most one Client
-- per organization (client_contact_methods_org_value_unique_idx), so a clash between two Clients is the only
-- ambiguity left, and this setting settles it. Neither Client is edited; true duplicates are merged by a person
-- (merge_clients). Chats already waiting for review stay resolvable by staff.

-- 1. The setting, with its own revision so saving it never collides with another settings section.
alter table public.organization_settings
  add column contact_match_priority text not null default 'email',
  add column contact_match_revision integer not null default 1,
  add column contact_match_updated_by uuid,
  add column contact_match_updated_at timestamp with time zone,
  add constraint organization_settings_contact_match_priority_check
    check (contact_match_priority in ('email', 'phone'));

grant select (contact_match_priority, contact_match_revision, contact_match_updated_by, contact_match_updated_at)
  on table public.organization_settings to authenticated;

alter table public.organization_settings_audit
  drop constraint organization_settings_audit_section_check,
  add constraint organization_settings_audit_section_check check (section = any (array[
    'profile', 'branding', 'hours', 'pipeline', 'taxes', 'quote_terms', 'quote_representative',
    'quote_target_margin', 'quote_signature_policy', 'invoice_terms', 'payment_settings', 'stripe_connection',
    'contact_matching'
  ]));

-- 2. The one matcher every public intake uses. Two unique-index lookups and one settings row.
create or replace function private.match_client_by_contact(
  target_organization_id uuid, match_phone text, match_email text
) returns uuid
  language plpgsql stable
  set search_path to 'pg_catalog', 'public'
as $$
declare
  phone_client uuid;
  email_client uuid;
  priority text;
begin
  if match_phone is not null then
    select method.client_id into phone_client
    from public.client_contact_methods method
    join public.clients client
      on client.organization_id = method.organization_id and client.id = method.client_id
    where method.organization_id = target_organization_id
      and method.kind = 'phone'
      and method.normalized_value = match_phone
      and client.deleted_at is null;
  end if;

  if match_email is not null then
    select method.client_id into email_client
    from public.client_contact_methods method
    join public.clients client
      on client.organization_id = method.organization_id and client.id = method.client_id
    where method.organization_id = target_organization_id
      and method.kind = 'email'
      and method.normalized_value = match_email
      and client.deleted_at is null;
  end if;

  if phone_client is null or email_client is null or phone_client = email_client then
    return coalesce(email_client, phone_client);
  end if;

  select settings.contact_match_priority into priority
  from public.organization_settings settings
  where settings.organization_id = target_organization_id;

  return case when priority = 'phone' then phone_client else email_client end;
end;
$$;

revoke all on function private.match_client_by_contact(uuid, text, text) from public;

comment on function private.match_client_by_contact(uuid, text, text) is
  'Which existing Client a public chat or form belongs to: the Client owning the normalized phone or email, and when those are two different Clients, the one named by organization_settings.contact_match_priority (email by default). Null when neither matches.';

-- 3. Saving the setting: the same revision-checked, audited shape as save_pipeline_presentation.
create or replace function public.save_contact_match_priority(
  target_organization_id uuid, expected_revision integer, new_priority text
) returns jsonb
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
as $$
declare
  settings_row public.organization_settings;
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_priority is null or new_priority not in ('email', 'phone') then
    raise exception 'Choose whether to match by email or by phone first.'
      using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.contact_match_revision then
    select profile.full_name, settings_row.contact_match_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.contact_match_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  update public.organization_settings
  set
    contact_match_priority = new_priority,
    contact_match_revision = contact_match_revision + 1,
    contact_match_updated_by = (select auth.uid()),
    contact_match_updated_at = now()
  where organization_id = target_organization_id
  returning contact_match_revision into new_revision;

  if new_priority is distinct from settings_row.contact_match_priority then
    insert into public.organization_settings_audit (
      organization_id, section, changed_fields, actor_user_id
    )
    values (
      target_organization_id, 'contact_matching', array['contact_match_priority'], (select auth.uid())
    );
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'contact_match_revision', new_revision,
    'contact_match_priority', new_priority
  );
end;
$$;

revoke all on function public.save_contact_match_priority(uuid, integer, text) from public;
grant execute on function public.save_contact_match_priority(uuid, integer, text) to authenticated;
grant execute on function public.save_contact_match_priority(uuid, integer, text) to service_role;

-- 4. Website Chat's first message uses the matcher (body otherwise unchanged from the baseline).
CREATE OR REPLACE FUNCTION "public"."accept_website_chat_first_message"("widget_public_token" "uuid", "requesting_origin" "text", "new_session_token_hash" "text", "new_idempotency_key" "text", "visitor_name" "text", "visitor_phone_e164" "text", "visitor_email" "text", "message_body" "text", "consent_transactional_sms" boolean DEFAULT false, "visitor_ip_hash" "text" DEFAULT NULL::"text", "new_attribution" "jsonb" DEFAULT '{}'::"jsonb", "sms_consent_disclosure" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    SET "statement_timeout" TO '5000'
    AS $$
declare
  widget record;
  normalized_origin text := lower(btrim(coalesce(requesting_origin, '')));
  origin_allowed boolean;
  clean_name text;
  given_name text;
  family_name text;
  first_space integer;
  clean_phone text;
  clean_email text;
  clean_body text;
  clean_idempotency_key text;
  match_phone text;
  match_email text;
  phone_candidate uuid;
  email_candidate uuid;
  phone_match_count integer := 0;
  email_match_count integer := 0;
  resolved_client_id uuid;
  resolved_match_status text;
  existing_session public.website_chat_sessions;
  existing_message_id uuid;
  limit_row record;
  active_period record;
  bucket record;
  new_session public.website_chat_sessions;
  new_message_id uuid;
  rate_check record;
  new_client_id uuid;
  clean_consent_disclosure text;
begin
  clean_idempotency_key := nullif(btrim(coalesce(new_idempotency_key, '')), '');
  -- One "Name" field, HighLevel's own shape, split the way HighLevel splits it: everything up to
  -- the first space is the given name, the whole remainder is the family name. Nothing the visitor
  -- typed is ever dropped, and a single-word name simply has no family name.
  clean_name := nullif(btrim(regexp_replace(coalesce(visitor_name, ''), '\s+', ' ', 'g')), '');
  first_space := position(' ' in coalesce(clean_name, ''));
  if first_space > 0 then
    given_name := substr(clean_name, 1, first_space - 1);
    family_name := nullif(btrim(substr(clean_name, first_space + 1)), '');
  else
    given_name := clean_name;
    family_name := null;
  end if;
  clean_phone := nullif(btrim(coalesce(visitor_phone_e164, '')), '');
  clean_email := lower(nullif(btrim(coalesce(visitor_email, '')), ''));
  clean_body := nullif(btrim(coalesce(message_body, '')), '');
  -- Service-SMS consent counts only with a phone number and the disclosure the route built from the business name
  -- the widget showed. A bare "true" (older widget builds pre-ticked the box) is not consent evidence.
  clean_consent_disclosure := case
    when coalesce(consent_transactional_sms, false) and clean_phone is not null
      then left(nullif(btrim(coalesce(sms_consent_disclosure, '')), ''), 1000)
  end;

  -- The name is bounded here, not only by the session's check constraint, because the Client is
  -- inserted first: a one character name would otherwise raise on `clients.display_name` instead of
  -- being refused. The route's own schema already refuses it; this is the command standing on its own.
  if normalized_origin = '' or clean_idempotency_key is null or clean_name is null
    or char_length(clean_name) < 2 or char_length(clean_name) > 120
    or clean_body is null or nullif(btrim(coalesce(new_session_token_hash, '')), '') is null then
    return jsonb_build_object('status', 'refused');
  end if;
  if clean_phone is null and clean_email is null then
    return jsonb_build_object('status', 'refused');
  end if;

  select w.id, w.organization_id, w.published, w.disabled_at, w.suspended_at, w.source_label
  into widget
  from public.website_chat_widgets w
  where w.public_token = widget_public_token;
  if not found then
    return jsonb_build_object('status', 'refused');
  end if;

  select exists (
    select 1 from public.website_chat_widget_origins o
    where o.widget_id = widget.id and o.origin = normalized_origin
  ) into origin_allowed;
  if not origin_allowed
    or widget.suspended_at is not null
    or widget.disabled_at is not null
    or not widget.published then
    return jsonb_build_object('status', 'refused');
  end if;

  -- A retry is answered from the existing session before any limit is consumed or any unit claimed.
  select * into existing_session
  from public.website_chat_sessions s
  where s.widget_id = widget.id and s.idempotency_key = clean_idempotency_key;
  if found then
    select m.id into existing_message_id
    from public.website_chat_messages m
    where m.session_id = existing_session.id
    order by m.created_at, m.id
    limit 1;
    return jsonb_build_object(
      'status', 'accepted',
      'replayed', true,
      'session_id', existing_session.id,
      'organization_id', existing_session.organization_id,
      'client_id', existing_session.client_id,
      'match_status', existing_session.match_status,
      'message_id', existing_message_id
    );
  end if;

  -- Layered flood control (WC0.3): one visitor, one widget, one organization.
  if visitor_ip_hash is not null then
    select * into rate_check
    from public.check_rate_limit('website_chat:first:ip:' || visitor_ip_hash, 3600, 5);
    if not rate_check.allowed then
      return jsonb_build_object('status', 'rate_limited');
    end if;
  end if;
  select * into rate_check
  from public.check_rate_limit('website_chat:first:widget:' || widget.id::text, 3600, 120);
  if not rate_check.allowed then
    return jsonb_build_object('status', 'rate_limited');
  end if;
  select * into rate_check
  from public.check_rate_limit('website_chat:first:org:' || widget.organization_id::text, 3600, 400);
  if not rate_check.allowed then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  select * into limit_row
  from private.effective_website_chat_conversation_limit(widget.organization_id, now());
  if limit_row.state not in ('numeric', 'unlimited')
    or (limit_row.state = 'numeric' and limit_row.value is null) then
    return jsonb_build_object('status', 'unavailable', 'reason', 'not_entitled');
  end if;

  select p.id, p.starts_at, p.ends_at into active_period
  from public.website_chat_allowance_periods p
  where p.organization_id = widget.organization_id
    and p.starts_at <= now()
    and p.ends_at > now()
  order by p.starts_at desc
  limit 1;
  if not found then
    return jsonb_build_object('status', 'unavailable', 'reason', 'allowance_period_unavailable');
  end if;

  -- One row, locked for update: the serialization point for every concurrent visitor of this
  -- organization. Nothing below it can oversubscribe the period.
  -- The DO UPDATE branch is what makes this race-free: it locks the existing row for us, where a
  -- DO NOTHING followed by a SELECT ... FOR UPDATE would find nothing while a concurrent inserter
  -- was still uncommitted.
  insert into public.website_chat_capacity_buckets (organization_id, allowance_period_id)
  values (widget.organization_id, active_period.id)
  on conflict (organization_id, allowance_period_id) do update
    set accepted_count = public.website_chat_capacity_buckets.accepted_count
  returning * into bucket;

  if limit_row.state = 'numeric' and bucket.accepted_count >= limit_row.value then
    return jsonb_build_object('status', 'cap_reached');
  end if;

  -- Identity, organization-scoped and normalized exactly like client_contact_methods stores it.
  match_phone := nullif(regexp_replace(coalesce(clean_phone, ''), '[^0-9]', '', 'g'), '');
  match_email := clean_email;

  -- One rule for every public intake: the organization's contact matching priority decides when the phone
  -- and the email belong to two different Clients. Public input still never edits an existing Client.
  resolved_client_id := private.match_client_by_contact(widget.organization_id, match_phone, match_email);
  if resolved_client_id is not null then
    resolved_match_status := 'resolved';
  else
    -- Nobody matched: a new Lead. Public input creates a Client but never edits an existing one.
    resolved_match_status := 'resolved';
    insert into public.clients (
      organization_id, display_name, first_name, last_name, lifecycle_status, lead_source,
      client_type
    ) values (
      widget.organization_id, clean_name, given_name, family_name, 'lead',
      coalesce(widget.source_label, 'Website Chat'), 'person'
    ) returning id into new_client_id;
    resolved_client_id := new_client_id;

    if clean_phone is not null then
      insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
      values (widget.organization_id, new_client_id, 'phone', clean_phone, true);
    end if;
    if clean_email is not null then
      insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
      values (widget.organization_id, new_client_id, 'email', clean_email, true);
    end if;
  end if;

  insert into public.website_chat_sessions (
    organization_id, widget_id, client_id, match_status,
    candidate_client_id_by_phone, candidate_client_id_by_email,
    visitor_name, submitted_phone_e164, submitted_email,
    normalized_phone, normalized_email, session_token_hash, idempotency_key,
    attribution, consent_transactional_sms, sms_consent_disclosure, ip_hash
  ) values (
    widget.organization_id, widget.id, resolved_client_id, resolved_match_status,
    case when resolved_match_status = 'needs_review' then phone_candidate end,
    case when resolved_match_status = 'needs_review' then email_candidate end,
    clean_name, clean_phone, clean_email,
    match_phone, match_email, btrim(new_session_token_hash), clean_idempotency_key,
    case when jsonb_typeof(coalesce(new_attribution, '{}'::jsonb)) = 'object'
      then coalesce(new_attribution, '{}'::jsonb) else '{}'::jsonb end,
    clean_consent_disclosure is not null, clean_consent_disclosure,
    nullif(btrim(coalesce(visitor_ip_hash, '')), '')
  ) returning * into new_session;

  insert into public.website_chat_capacity_reservations (
    organization_id, allowance_period_id, session_id
  ) values (widget.organization_id, active_period.id, new_session.id);

  update public.website_chat_capacity_buckets
  set accepted_count = accepted_count + 1
  where organization_id = widget.organization_id
    and allowance_period_id = active_period.id;

  insert into public.website_chat_messages (
    organization_id, session_id, client_id, direction, sender_type, body, idempotency_key
  ) values (
    widget.organization_id, new_session.id, resolved_client_id, 'inbound', 'visitor',
    clean_body, clean_idempotency_key
  ) returning id into new_message_id;

  return jsonb_build_object(
    'status', 'accepted',
    'replayed', false,
    'session_id', new_session.id,
    'organization_id', new_session.organization_id,
    'client_id', new_session.client_id,
    'match_status', new_session.match_status,
    'message_id', new_message_id
  );
end;
$$;

-- 5. Website form processing uses the matcher (body otherwise unchanged from
-- 20260923180000_marketing_campaign_attribution.sql).
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

    -- The organization's contact matching priority settles a phone and an email that belong to two different
    -- Clients, instead of creating a third, contactless one.
    resolved_client_id := private.match_client_by_contact(submission.organization_id, match_phone, match_email);

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
