-- WC4 carry-over: the visitor's whole name was stored as their first name.
--
-- The identity form shows one "Name" field, following HighLevel's form, but the command only ever
-- took a first name -- so "Marta Olsen" became a Client whose first name was "Marta Olsen" and whose
-- surname was empty, and every downstream screen showed the surname glued on. Jobber asks for a first
-- and a last name separately and stores them separately; HighLevel asks for one name and splits it at
-- the first space. Our form is HighLevel's, so our split is HighLevel's too (approved by Jafar,
-- 2026-08-27): everything before the first space is the given name, the remainder is the family name.
--
-- Renaming the command's argument means dropping and recreating it rather than replacing it: PostgREST
-- resolves RPCs by argument name, and a `create or replace` with a renamed argument is an error. The
-- same reason `20260904110000` had to drop and recreate both widget commands.
--
-- The session column is renamed with it. It holds what the visitor submitted, which is now a whole
-- name, and a column called `visitor_first_name` holding "Marta Olsen" is a lie in the schema.
--
-- Its length check widens from 1..80 to 2..120: 80 was chosen for a first name, and the minimum rises
-- to 2 because `clients.display_name` already refuses a single character -- a one-letter name passed
-- every check here and then failed on the Client insert.

alter table public.website_chat_sessions
  rename column visitor_first_name to visitor_name;

alter table public.website_chat_sessions
  drop constraint website_chat_sessions_visitor_first_name_check;

alter table public.website_chat_sessions
  add constraint website_chat_sessions_visitor_name_check
    check (char_length(btrim(visitor_name)) between 2 and 120);

comment on column public.website_chat_sessions.visitor_name is
  'The whole name the visitor typed into the identity form. Split at the first space into the Lead '
  'Client''s first and last name when the session created one.';

drop function if exists public.accept_website_chat_first_message(
  uuid, text, text, text, text, text, text, text, boolean, text, jsonb
);

create function public.accept_website_chat_first_message(
  widget_public_token uuid,
  requesting_origin text,
  new_session_token_hash text,
  new_idempotency_key text,
  visitor_name text,
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
set statement_timeout = '5000'
as $$
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
    attribution, consent_transactional_sms, ip_hash
  ) values (
    widget.organization_id, widget.id, resolved_client_id, resolved_match_status,
    case when resolved_match_status = 'needs_review' then phone_candidate end,
    case when resolved_match_status = 'needs_review' then email_candidate end,
    clean_name, clean_phone, clean_email,
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

comment on function public.accept_website_chat_first_message(
  uuid, text, text, text, text, text, text, text, boolean, text, jsonb
) is 'The one place a Website Chat allowance unit is claimed. Validates origin and token, applies '
  'flood limits, claims one unit under a bucket lock, resolves or creates the Client, and writes the '
  'session and its first message in a single transaction.';

revoke all on function public.accept_website_chat_first_message(
  uuid, text, text, text, text, text, text, text, boolean, text, jsonb
) from public, anon, authenticated;
grant execute on function public.accept_website_chat_first_message(
  uuid, text, text, text, text, text, text, text, boolean, text, jsonb
) to service_role;
