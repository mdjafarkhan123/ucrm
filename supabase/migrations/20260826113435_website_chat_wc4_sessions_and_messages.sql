-- Communications Website Chat, Part WC4.1: the database foundation for real conversations.
--
-- Adds the five tables WC0.1 fixed (sessions, messages, allowance periods, capacity buckets,
-- capacity reservations), the conversation-limit authority function, and the two write commands
-- every public route will call: accept_website_chat_first_message (the one place an allowance unit
-- is claimed) and post_website_chat_message (every later message, no claim).
--
-- No API route and no UI belong to this slice.
--
-- Grant shape matches the existing website_chat_* / communication_* tables: RLS on, every write
-- privilege revoked from anon and authenticated, public visitor access only ever through the
-- security definer commands below, called by the server's service-role client. Staff-side read
-- policies land with WC4.5, when the Conversations surface that needs them is built.
--
-- Two deliberate refinements of WC0.2's prose, both recorded here so the next session does not read
-- them as drift:
--
-- 1. The capacity bucket carries a running accepted_count instead of being re-derived by summing
--    reservations on every claim. Email has to sum because its reservation is settled asynchronously
--    by a provider callback; a Website Chat unit is accepted synchronously inside this transaction,
--    so a counter on the row we already lock for update is both correct and O(1). It also *is* the
--    usage read model WC0.2 promised, with no separate aggregate or materialized view.
-- 2. The reservation references the session, not the other way round. WC0.2 described the link in the
--    opposite direction; pointing it this way avoids a circular foreign key and lets a plain unique
--    constraint on session_id enforce the real invariant -- exactly one allowance unit per accepted
--    session, forever.

-- 1. Allowance periods -------------------------------------------------------------------------------

-- Website Chat keeps its own period table rather than sharing email's, so the two allowances stay
-- independently reconcilable (WC0.1). Like email's, it is opened by a commercial event; no command
-- opens one yet, which means the channel is fail-closed until one exists -- the same posture the
-- outbound email worker already has.
create table public.website_chat_allowance_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  opened_by_commercial_event_id uuid references public.organization_commercial_events(id),
  created_at timestamptz not null default now(),
  constraint website_chat_allowance_periods_interval_check check (ends_at > starts_at),
  constraint website_chat_allowance_periods_organization_starts_key unique (organization_id, starts_at)
);

comment on table public.website_chat_allowance_periods is
  'Exact UTC interval a Website Chat conversation allowance resets over. Mirrors '
  'communication_email_allowance_periods.';

-- The only lookup: the one period covering now() for one organization.
create index website_chat_allowance_periods_active_idx
  on public.website_chat_allowance_periods (organization_id, starts_at desc);

create index website_chat_allowance_periods_commercial_event_idx
  on public.website_chat_allowance_periods (opened_by_commercial_event_id)
  where opened_by_commercial_event_id is not null;

-- 2. Capacity ----------------------------------------------------------------------------------------

create table public.website_chat_capacity_buckets (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  allowance_period_id uuid not null
    references public.website_chat_allowance_periods(id) on delete cascade,
  -- Running count of accepted conversations in this period. Incremented under the row lock taken by
  -- accept_website_chat_first_message, so concurrent visitors cannot oversubscribe the organization.
  accepted_count integer not null default 0 check (accepted_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, allowance_period_id)
);

comment on table public.website_chat_capacity_buckets is
  'One row per organization per allowance period. The row is the lock target for a conversation '
  'claim and the running usage read model for near-cap warnings.';

create index website_chat_capacity_buckets_allowance_period_idx
  on public.website_chat_capacity_buckets (allowance_period_id);

create table public.website_chat_capacity_reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  allowance_period_id uuid not null
    references public.website_chat_allowance_periods(id) on delete restrict,
  session_id uuid not null,
  -- Accepted the moment it is written: this claim is human-triggered and synchronous, with no
  -- external provider outcome to wait for. 'released' exists for a later reasoned reversal only.
  reservation_state text not null default 'accepted'
    check (reservation_state in ('accepted', 'released')),
  accepted_at timestamptz not null default now(),
  released_at timestamptz,
  created_at timestamptz not null default now(),
  constraint website_chat_capacity_reservations_session_key unique (session_id),
  constraint website_chat_capacity_reservations_released_check check (
    (reservation_state = 'accepted' and released_at is null)
    or (reservation_state = 'released' and released_at is not null)
  ),
  constraint website_chat_capacity_reservations_bucket_fk
    foreign key (organization_id, allowance_period_id)
    references public.website_chat_capacity_buckets(organization_id, allowance_period_id)
    on delete restrict
);

comment on table public.website_chat_capacity_reservations is
  'Exactly one allowance unit per accepted Website Chat session, enforced by the unique session_id.';

-- Covers the composite bucket foreign key and per-period reconciliation ("recount usage").
create index website_chat_capacity_reservations_bucket_idx
  on public.website_chat_capacity_reservations (organization_id, allowance_period_id);

-- 3. Sessions ----------------------------------------------------------------------------------------

create table public.website_chat_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  widget_id uuid not null,
  -- Null only while match_status is needs_review: UCRM never guesses which Client a conflicting
  -- pair of identifiers belongs to.
  client_id uuid,
  match_status text not null default 'resolved'
    check (match_status in ('resolved', 'needs_review')),
  candidate_client_id_by_phone uuid,
  candidate_client_id_by_email uuid,
  -- Captured from the visitor at first message. Stored on the session, never written back over an
  -- existing Client's own fields.
  visitor_first_name text not null check (char_length(btrim(visitor_first_name)) between 1 and 80),
  submitted_phone_e164 text
    check (submitted_phone_e164 is null or submitted_phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  submitted_email text check (submitted_email is null or char_length(btrim(submitted_email)) between 3 and 254),
  -- Same normalization the matcher uses, so a later re-match never re-derives it differently:
  -- digits only for phone, lowercased/trimmed for email (client_contact_methods' own convention).
  normalized_phone text,
  normalized_email text,
  -- Opaque visitor bearer token, hashed at rest like every other bearer token in the app.
  session_token_hash text not null,
  -- A retried first-message POST must be a no-op, never a second session and a second claimed unit.
  idempotency_key text not null check (char_length(btrim(idempotency_key)) between 8 and 200),
  attribution jsonb not null default '{}'::jsonb check (jsonb_typeof(attribution) = 'object'),
  consent_transactional_sms boolean not null default false,
  -- One-way hash for abuse correlation. No raw IP is ever stored (WC0.3).
  ip_hash text,
  started_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_reason text check (
    closed_reason in ('visitor_ended', 'staff_ended', 'inactivity_timeout', 'widget_disabled')
  ),
  created_at timestamptz not null default now(),
  constraint website_chat_sessions_organization_id_id_key unique (organization_id, id),
  constraint website_chat_sessions_session_token_hash_key unique (session_token_hash),
  constraint website_chat_sessions_widget_idempotency_key unique (widget_id, idempotency_key),
  -- The contract's "at least one of phone or email", enforced in the data, not only in the form.
  constraint website_chat_sessions_identifier_present_check check (
    submitted_phone_e164 is not null or submitted_email is not null
  ),
  constraint website_chat_sessions_client_presence_check check (
    (match_status = 'resolved' and client_id is not null)
    or (match_status = 'needs_review' and client_id is null)
  ),
  constraint website_chat_sessions_closed_reason_present_check check (
    (closed_at is null and closed_reason is null)
    or (closed_at is not null and closed_reason is not null)
  ),
  constraint website_chat_sessions_widget_fk
    foreign key (organization_id, widget_id)
    references public.website_chat_widgets(organization_id, id) on delete restrict,
  constraint website_chat_sessions_client_fk
    foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict
);

comment on table public.website_chat_sessions is
  'One visitor conversation on one widget. Sessions from distinct widgets stay separate; a later '
  'inquiry creates a new session linked to the same Client.';

-- Session restore by the visitor's own token. closed_at is filtered in the query, not the index --
-- a closed session still reads its own history.
-- (covered by website_chat_sessions_session_token_hash_key)

-- Foreign-key cover plus per-widget diagnostics and usage.
create index website_chat_sessions_widget_idx
  on public.website_chat_sessions (organization_id, widget_id, started_at desc);

-- Foreign-key cover plus "this Client's Website Chat sessions" on the contact timeline.
create index website_chat_sessions_client_idx
  on public.website_chat_sessions (organization_id, client_id, started_at desc)
  where client_id is not null;

-- The 30-day inactivity closure sweep.
create index website_chat_sessions_inactivity_idx
  on public.website_chat_sessions (last_activity_at)
  where closed_at is null;

-- Retention and cleanup.
create index website_chat_sessions_organization_closed_idx
  on public.website_chat_sessions (organization_id, closed_at);

-- Staff review queue: unresolved conflicts, and the 30-day stale surfacing WC0.3 requires.
create index website_chat_sessions_needs_review_idx
  on public.website_chat_sessions (organization_id, started_at desc)
  where match_status = 'needs_review';

-- 4. Messages ----------------------------------------------------------------------------------------

create table public.website_chat_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  session_id uuid not null,
  -- Denormalized from the session (WC0.2) so the cross-channel "latest message per contact" query
  -- keeps the same shape it already has on communication_delivery_intents and
  -- communication_inbound_messages. Null while the session is needs_review; backfilled when it resolves.
  client_id uuid,
  direction text not null check (direction in ('inbound', 'outbound')),
  sender_type text not null check (sender_type in ('visitor', 'staff', 'system', 'automation')),
  sender_user_id uuid references auth.users(id) on delete set null,
  body text not null check (char_length(btrim(body)) between 1 and 5000),
  -- Only ever a state we can actually prove. A message written here is already durably stored.
  delivery_state text not null default 'sent' check (delivery_state in ('sent', 'failed')),
  -- Lets a retried send be a no-op rather than a duplicate bubble.
  idempotency_key text check (idempotency_key is null or char_length(btrim(idempotency_key)) between 8 and 200),
  created_at timestamptz not null default now(),
  constraint website_chat_messages_organization_id_id_key unique (organization_id, id),
  constraint website_chat_messages_visitor_direction_check check (
    (sender_type = 'visitor' and direction = 'inbound')
    or (sender_type <> 'visitor' and direction = 'outbound')
  ),
  constraint website_chat_messages_sender_user_check check (
    sender_user_id is null or sender_type = 'staff'
  ),
  constraint website_chat_messages_session_fk
    foreign key (organization_id, session_id)
    references public.website_chat_sessions(organization_id, id) on delete restrict,
  constraint website_chat_messages_client_fk
    foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict
);

comment on table public.website_chat_messages is
  'Website Chat''s channel-native thread. Surfaces into the shared client timeline by client_id + '
  'created_at, the same way every other channel already does.';

-- Session timeline: the visitor polling fallback and the staff view, both keyset-paginated on the
-- app's existing (created_at desc, id desc) convention.
create index website_chat_messages_session_timeline_idx
  on public.website_chat_messages (session_id, created_at desc, id desc);

-- Cross-channel Conversations list, mirroring communication_delivery_intents' index shape exactly.
create index website_chat_messages_organization_client_idx
  on public.website_chat_messages (organization_id, client_id, created_at desc)
  where client_id is not null;

create index website_chat_messages_sender_user_idx
  on public.website_chat_messages (sender_user_id)
  where sender_user_id is not null;

-- A retried send never duplicates a bubble.
create unique index website_chat_messages_session_idempotency_idx
  on public.website_chat_messages (session_id, idempotency_key)
  where idempotency_key is not null;

create trigger website_chat_capacity_buckets_set_updated_at
before update on public.website_chat_capacity_buckets
for each row execute function public.set_updated_at();

-- 5. Access ------------------------------------------------------------------------------------------

alter table public.website_chat_allowance_periods enable row level security;
alter table public.website_chat_capacity_buckets enable row level security;
alter table public.website_chat_capacity_reservations enable row level security;
alter table public.website_chat_sessions enable row level security;
alter table public.website_chat_messages enable row level security;

revoke all on
  public.website_chat_allowance_periods,
  public.website_chat_capacity_buckets,
  public.website_chat_capacity_reservations,
  public.website_chat_sessions,
  public.website_chat_messages
  from anon, authenticated;

grant select, insert, update on
  public.website_chat_allowance_periods,
  public.website_chat_capacity_buckets,
  public.website_chat_capacity_reservations,
  public.website_chat_sessions,
  public.website_chat_messages
  to service_role;

-- 6. Limit authority ----------------------------------------------------------------------------------

-- The single authority for website_chat_accepted_conversations, following
-- effective_website_chat_widgets_limit. It stays in `private` and stays security definer because,
-- unlike the widgets limit, nothing in the browser calls it -- only the security definer commands
-- below, running as service_role, ever need an answer.
create or replace function private.effective_website_chat_conversation_limit(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  state text,
  value integer,
  is_unlimited boolean,
  source text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  assignment_package_version_id uuid;
  override_limit_state text;
  override_limit_value integer;
  override_is_unlimited boolean;
  override_found boolean;
  package_limit_state text;
  package_limit_value integer;
  package_found boolean;
begin
  select assignment.package_version_id
  into assignment_package_version_id
  from public.organization_package_assignments as assignment
  where assignment.organization_id = target_organization_id
    and assignment.effective_at <= at
  order by assignment.effective_at desc, assignment.id desc
  limit 1;

  select override.limit_state, override.limit_value, override.is_unlimited
  into override_limit_state, override_limit_value, override_is_unlimited
  from public.organization_limit_overrides as override
  where override.organization_id = target_organization_id
    and override.limit_key = 'website_chat_accepted_conversations'
    and override.starts_at <= at
    and (override.expires_at is null or override.expires_at > at);
  override_found := found;

  if assignment_package_version_id is not null then
    select version_limit.limit_state, version_limit.limit_value
    into package_limit_state, package_limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = assignment_package_version_id
      and version_limit.limit_key = 'website_chat_accepted_conversations';
    package_found := found;
  else
    package_found := false;
  end if;

  if override_found then
    state := override_limit_state;
    value := override_limit_value;
    is_unlimited := override_is_unlimited;
  elsif package_found then
    state := package_limit_state;
    value := case when package_limit_state = 'numeric' then package_limit_value else null end;
    is_unlimited := package_limit_state = 'unlimited';
  else
    state := 'not_included';
    value := null;
    is_unlimited := false;
  end if;

  source := case when override_found then 'override' else 'package' end;

  return next;
  return;
end;
$function$;

comment on function private.effective_website_chat_conversation_limit(uuid, timestamptz) is
  'Single authority for the website_chat_accepted_conversations limit.';

revoke all on function private.effective_website_chat_conversation_limit(uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- 7. The first message ---------------------------------------------------------------------------------

-- Everything a first message does happens here, in one transaction: origin/token validation, spam and
-- flood limits, the allowance claim, Client resolution, the session, and the message itself. If any
-- step fails, the claimed unit rolls back with it.
--
-- Every refusal that is not a real cap is reported as a single generic 'refused' so a caller cannot
-- tell a bad token from a stranger's domain from a disabled widget (WC0.3).
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

-- 8. Every later message ---------------------------------------------------------------------------------

-- No allowance claim and no identity matching: the contract is explicit that later messages in an
-- accepted session never consume another unit, and an existing session stays usable at the hard cap.
create or replace function public.post_website_chat_message(
  session_token_hash text,
  requesting_origin text,
  message_body text,
  new_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_session public.website_chat_sessions;
  widget record;
  normalized_origin text := lower(btrim(coalesce(requesting_origin, '')));
  origin_allowed boolean;
  clean_body text;
  clean_idempotency_key text;
  existing_message_id uuid;
  new_message_id uuid;
  rate_check record;
begin
  clean_body := nullif(btrim(coalesce(message_body, '')), '');
  clean_idempotency_key := nullif(btrim(coalesce(new_idempotency_key, '')), '');

  if normalized_origin = '' or clean_body is null
    or nullif(btrim(coalesce(session_token_hash, '')), '') is null then
    return jsonb_build_object('status', 'refused');
  end if;

  select * into target_session
  from public.website_chat_sessions s
  where s.session_token_hash = btrim(post_website_chat_message.session_token_hash)
  for update;
  if not found then
    return jsonb_build_object('status', 'refused');
  end if;

  select w.id, w.disabled_at, w.suspended_at, w.published into widget
  from public.website_chat_widgets w
  where w.id = target_session.widget_id;

  select exists (
    select 1 from public.website_chat_widget_origins o
    where o.widget_id = target_session.widget_id and o.origin = normalized_origin
  ) into origin_allowed;

  if not origin_allowed
    or widget.suspended_at is not null
    or widget.disabled_at is not null
    or not widget.published then
    return jsonb_build_object('status', 'refused');
  end if;

  -- A closed session still reads its own history; it never accepts another message.
  if target_session.closed_at is not null then
    return jsonb_build_object('status', 'session_closed');
  end if;

  if clean_idempotency_key is not null then
    select m.id into existing_message_id
    from public.website_chat_messages m
    where m.session_id = target_session.id and m.idempotency_key = clean_idempotency_key;
    if found then
      return jsonb_build_object(
        'status', 'accepted', 'replayed', true,
        'session_id', target_session.id, 'message_id', existing_message_id
      );
    end if;
  end if;

  -- Flood control inside an already-accepted session, separate from the first-message limits.
  select * into rate_check
  from public.check_rate_limit('website_chat:message:' || target_session.id::text, 60, 20);
  if not rate_check.allowed then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  insert into public.website_chat_messages (
    organization_id, session_id, client_id, direction, sender_type, body, idempotency_key
  ) values (
    target_session.organization_id, target_session.id, target_session.client_id, 'inbound', 'visitor',
    clean_body, clean_idempotency_key
  ) returning id into new_message_id;

  update public.website_chat_sessions
  set last_activity_at = now()
  where id = target_session.id;

  return jsonb_build_object(
    'status', 'accepted', 'replayed', false,
    'session_id', target_session.id, 'message_id', new_message_id
  );
end;
$$;

comment on function public.post_website_chat_message(text, text, text, text) is
  'Every Website Chat message after the first: origin and session checks, per-session flood limit, '
  'insert, and a last_activity_at bump. Never claims an allowance unit.';

revoke all on function public.post_website_chat_message(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.post_website_chat_message(text, text, text, text) to service_role;
