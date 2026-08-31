-- Correction to 20260904090000: Postgres has no min(uuid) aggregate, so the candidate-Client
-- lookup inside accept_website_chat_first_message raised 42883 the first time a visitor supplied
-- an identifier that matched an existing Client. Aggregating on the text form and casting back is
-- the ordinary fix; nothing else about the function changes.

create or replace function public.accept_website_chat_first_message(
  widget_public_token uuid,
  requesting_origin text,
  new_session_token_hash text,
  new_idempotency_key text,
  visitor_first_name text,
  visitor_phone_e164 text,
  visitor_email text,
  message_body text,
  consent_transactional_sms boolean default false,
  visitor_ip_hash text default null,
  new_attribution jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  widget record;
  normalized_origin text := lower(btrim(coalesce(requesting_origin, '')));
  origin_allowed boolean;
  clean_first_name text;
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
begin
  clean_idempotency_key := nullif(btrim(coalesce(new_idempotency_key, '')), '');
  clean_first_name := nullif(btrim(coalesce(visitor_first_name, '')), '');
  clean_phone := nullif(btrim(coalesce(visitor_phone_e164, '')), '');
  clean_email := lower(nullif(btrim(coalesce(visitor_email, '')), ''));
  clean_body := nullif(btrim(coalesce(message_body, '')), '');

  if normalized_origin = '' or clean_idempotency_key is null or clean_first_name is null
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

  if match_phone is not null then
    select count(distinct method.client_id), min(method.client_id::text)::uuid
    into phone_match_count, phone_candidate
    from public.client_contact_methods method
    join public.clients client
      on client.organization_id = method.organization_id and client.id = method.client_id
    where method.organization_id = widget.organization_id
      and method.kind = 'phone'
      and method.normalized_value = match_phone
      and client.deleted_at is null;
    if phone_match_count <> 1 then
      phone_candidate := null;
    end if;
  end if;

  if match_email is not null then
    select count(distinct method.client_id), min(method.client_id::text)::uuid
    into email_match_count, email_candidate
    from public.client_contact_methods method
    join public.clients client
      on client.organization_id = method.organization_id and client.id = method.client_id
    where method.organization_id = widget.organization_id
      and method.kind = 'email'
      and method.normalized_value = match_email
      and client.deleted_at is null;
    if email_match_count <> 1 then
      email_candidate := null;
    end if;
  end if;

  if phone_match_count > 1 or email_match_count > 1
    or (phone_candidate is not null and email_candidate is not null
        and phone_candidate <> email_candidate) then
    -- Two identifiers pointing at different Clients, or one identifier pointing at several. UCRM
    -- never guesses and never merges: messaging stays usable behind a guarded identity.
    resolved_match_status := 'needs_review';
    resolved_client_id := null;
  elsif coalesce(phone_candidate, email_candidate) is not null then
    resolved_match_status := 'resolved';
    resolved_client_id := coalesce(phone_candidate, email_candidate);
  else
    -- Nobody matched: a new Lead. Public input creates a Client but never edits an existing one.
    resolved_match_status := 'resolved';
    insert into public.clients (
      organization_id, display_name, first_name, lifecycle_status, lead_source, client_type
    ) values (
      widget.organization_id, clean_first_name, clean_first_name, 'lead',
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
    visitor_first_name, submitted_phone_e164, submitted_email,
    normalized_phone, normalized_email, session_token_hash, idempotency_key,
    attribution, consent_transactional_sms, ip_hash
  ) values (
    widget.organization_id, widget.id, resolved_client_id, resolved_match_status,
    case when resolved_match_status = 'needs_review' then phone_candidate end,
    case when resolved_match_status = 'needs_review' then email_candidate end,
    clean_first_name, clean_phone, clean_email,
    match_phone, match_email, btrim(new_session_token_hash), clean_idempotency_key,
    case when jsonb_typeof(coalesce(new_attribution, '{}'::jsonb)) = 'object'
      then coalesce(new_attribution, '{}'::jsonb) else '{}'::jsonb end,
    coalesce(consent_transactional_sms, false), nullif(btrim(coalesce(visitor_ip_hash, '')), '')
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

