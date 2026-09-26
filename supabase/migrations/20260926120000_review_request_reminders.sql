-- Google review campaign Part 4A: the reminder plan every review request follows.
--
-- Product truth: docs/google-review-campaign-owner-brief.md (§ How the automation is set up, § When the
-- sequence stops). Following HighLevel's Reputation settings, one plan in Review settings says when the first
-- message goes and which reminders follow; every request (manual now, automatic in Part 4B) follows it.
--
-- 1. review_request_messages: one row per message a request sends (slot 0 = the first message, 1..10 the
--    reminders), each with its own customer link. The raw token is never stored, so every message mints its
--    own link, as the quote follow-up does. The request's token and delivery intent move here.
-- 2. review_requests gains the chosen style and contact, the due marker for its next reminder, and why its
--    sequence stopped.
-- 3. review_settings gains request_plan (null = UCRM's defaults, supplied by src/lib/reviews/settings.ts).
-- 4. Reminders are queued lazily, one at a time: the automation worker claims due requests
--    (claim_review_reminders, FOR UPDATE SKIP LOCKED, fair per organization, under a lease) and
--    send_review_reminder re-checks everything at send time -- the customer's action, consent, suppression,
--    sender, the job, the client -- then queues the reminder through the same Communications path as the
--    first message. A reminder counts from when the previous message was actually accepted for delivery.
--
-- Stops: Google click, private feedback, cancel, a message that failed or bounced, STOP / unsubscribe or any
-- other refusal to send, the client deleted or switched review requests off, the job reopened or no longer
-- eligible, the plan shortened. A stop also cancels a reminder still waiting in the outbox.

-- 1. Messages -----------------------------------------------------------------------------------------------

create table public.review_request_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  request_id uuid not null,
  slot smallint not null,
  token_hash bytea not null,
  delivery_intent_id uuid references public.communication_delivery_intents (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint review_request_messages_slot_check check (slot between 0 and 10),
  constraint review_request_messages_token_hash_check check (octet_length(token_hash) = 32),
  constraint review_request_messages_token_hash_key unique (token_hash),
  constraint review_request_messages_request_slot_key unique (organization_id, request_id, slot),
  constraint review_request_messages_request_fkey
    foreign key (organization_id, request_id)
    references public.review_requests (organization_id, id) on delete cascade
);

comment on table public.review_request_messages is
  'Each message a review request sent: slot 0 is the first message, 1..10 its reminders. Every message has its own customer link (token hash only). Read and written by the server only.';

create unique index review_request_messages_delivery_intent_key
  on public.review_request_messages (delivery_intent_id) where delivery_intent_id is not null;

alter table public.review_request_messages enable row level security;
revoke all on table public.review_request_messages from public, anon, authenticated;
grant all on table public.review_request_messages to service_role;

insert into public.review_request_messages (organization_id, request_id, slot, token_hash, delivery_intent_id, created_at)
select request.organization_id, request.id, 0, request.token_hash, request.delivery_intent_id, request.created_at
from public.review_requests as request;

-- 2. Request sequence facts ---------------------------------------------------------------------------------

alter table public.review_requests
  add column style text not null default 'friendly',
  add column contact_method_id uuid,
  -- When the next reminder is due. Null when none is: no reminders, the last one went, or the sequence stopped.
  add column next_reminder_at timestamptz,
  add column reminder_claim_token uuid,
  add column reminder_attempts smallint not null default 0,
  add column stopped_at timestamptz,
  add column stop_reason text,
  add column stop_detail text,
  add constraint review_requests_style_check check (style in ('friendly', 'professional', 'short')),
  add constraint review_requests_reminder_attempts_check check (reminder_attempts >= 0),
  add constraint review_requests_stop_reason_check check (stop_reason is null or stop_reason in (
    'cancelled', 'continued_to_google', 'feedback_submitted', 'not_delivered', 'not_sent',
    'client_removed', 'client_opted_out', 'job_not_eligible', 'no_contact', 'plan_changed', 'error'
  )),
  add constraint review_requests_stop_detail_check check (stop_detail is null or char_length(stop_detail) <= 500);

update public.review_requests as request
set contact_method_id = intent.client_contact_method_id
from public.communication_delivery_intents as intent
where intent.id = request.delivery_intent_id;

alter table public.review_requests
  drop column token_hash,
  drop column delivery_intent_id;

-- The worker's claim reads only requests with a reminder due, oldest first.
create index review_requests_next_reminder_idx
  on public.review_requests (next_reminder_at) where next_reminder_at is not null;

-- 3. Settings: the request plan -----------------------------------------------------------------------------

alter table public.review_settings
  add column request_plan jsonb,
  -- Gross backstop only (10 reminders, each with six texts); the API's Zod schema validates the shape.
  add constraint review_settings_request_plan_check check (
    request_plan is null
    or (jsonb_typeof(request_plan) = 'object' and octet_length(request_plan::text) <= 262144)
  );

drop function public.save_review_settings(uuid, uuid, integer, text, boolean, smallint, boolean, jsonb, jsonb);

create or replace function public.save_review_settings(
  p_organization_id uuid,
  p_actor_id uuid,
  p_expected_revision integer,
  p_google_review_url text,
  p_routing_enabled boolean,
  p_routing_google_min_rating smallint,
  p_acknowledge_routing boolean,
  p_feedback_form jsonb,
  p_message_styles jsonb,
  p_request_plan jsonb
) returns public.review_settings
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  current_row public.review_settings;
  clean_url text := nullif(trim(coalesce(p_google_review_url, '')), '');
  saved public.review_settings;
begin
  if p_organization_id is null or p_actor_id is null then
    raise exception 'An organization and an actor are required.' using errcode = 'check_violation';
  end if;
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.manage') then
    raise exception 'You do not have permission to change review settings.' using errcode = 'insufficient_privilege';
  end if;

  select * into current_row from public.review_settings
  where organization_id = p_organization_id
  for update;

  if coalesce(current_row.revision, 0) <> coalesce(p_expected_revision, -1) then
    raise exception 'Review settings changed since you opened them.' using errcode = 'P0409';
  end if;

  if p_routing_enabled and clean_url is null then
    raise exception 'Add your Google review link before turning on review routing.' using errcode = 'check_violation';
  end if;
  if p_routing_enabled and not coalesce(current_row.routing_enabled, false) and not coalesce(p_acknowledge_routing, false) then
    raise exception 'Accept the review routing warning to turn it on.' using errcode = 'check_violation';
  end if;

  insert into public.review_settings as s (
    organization_id, google_review_url, routing_enabled, routing_google_min_rating,
    routing_acknowledged_at, routing_acknowledged_by, feedback_form, message_styles, request_plan,
    revision, updated_at, updated_by
  )
  values (
    p_organization_id, clean_url, coalesce(p_routing_enabled, false), coalesce(p_routing_google_min_rating, 4),
    case when p_routing_enabled then now() end,
    case when p_routing_enabled then p_actor_id end,
    p_feedback_form, p_message_styles, p_request_plan, 1, now(), p_actor_id
  )
  on conflict (organization_id) do update
  set google_review_url = excluded.google_review_url,
      routing_enabled = excluded.routing_enabled,
      routing_google_min_rating = excluded.routing_google_min_rating,
      routing_acknowledged_at = case
        when not excluded.routing_enabled then null
        when s.routing_enabled then s.routing_acknowledged_at
        else now() end,
      routing_acknowledged_by = case
        when not excluded.routing_enabled then null
        when s.routing_enabled then s.routing_acknowledged_by
        else p_actor_id end,
      feedback_form = excluded.feedback_form,
      message_styles = excluded.message_styles,
      request_plan = excluded.request_plan,
      revision = s.revision + 1,
      updated_at = now(),
      updated_by = p_actor_id
  returning * into saved;

  return saved;
end;
$$;

revoke all on function public.save_review_settings(uuid, uuid, integer, text, boolean, smallint, boolean, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.save_review_settings(uuid, uuid, integer, text, boolean, smallint, boolean, jsonb, jsonb, jsonb) to service_role;

-- 4. Helpers ------------------------------------------------------------------------------------------------

-- The request behind any of its messages' links. Same null-for-everything contract as before.
create or replace function private.live_review_request(supplied_token_hash bytea)
returns public.review_requests
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select request.*
  from public.review_request_messages as message
  join public.review_requests as request
    on request.organization_id = message.organization_id and request.id = message.request_id
  join public.clients as client
    on client.organization_id = request.organization_id and client.id = request.client_id
  where supplied_token_hash is not null
    and octet_length(supplied_token_hash) = 32
    and message.token_hash = supplied_token_hash
    and request.cancelled_at is null
    and client.deleted_at is null;
$$;

revoke all on function private.live_review_request(bytea) from public, anon, authenticated;

-- "N days later at the same time of day", in the business's own time zone, so a reminder does not drift an
-- hour across a daylight-saving change.
create or replace function private.review_request_days_later(
  p_organization_id uuid,
  p_from timestamptz,
  p_days integer
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  zone text;
begin
  select settings.timezone into zone from public.organization_settings as settings
  where settings.organization_id = p_organization_id;
  begin
    return ((p_from at time zone coalesce(zone, 'UTC')) + make_interval(days => p_days)) at time zone coalesce(zone, 'UTC');
  exception when invalid_parameter_value then
    -- A zone name Postgres does not know: count in UTC rather than never reminding.
    return p_from + make_interval(days => p_days);
  end;
end;
$$;

revoke all on function private.review_request_days_later(uuid, timestamptz, integer) from public, anon, authenticated;

-- One message's delivery state in the brief's words.
create or replace function private.review_request_message_state(p_intent_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  intent public.communication_delivery_intents;
  outbox public.communication_outbox_events;
begin
  select * into intent from public.communication_delivery_intents where id = p_intent_id;
  if intent.id is null then return 'queued'; end if;
  if intent.status = 'cancelled' then return 'cancelled'; end if;
  if intent.status = 'failed'
    or intent.delivery_outcome in ('hard_bounce', 'complaint', 'blocked', 'unsubscribed', 'sms_undelivered', 'sms_failed') then
    return 'failed';
  end if;
  if intent.delivery_outcome in ('delivered', 'sms_delivered') then return 'delivered'; end if;
  if intent.status = 'submitted' then return 'sent'; end if;

  select * into outbox from public.communication_outbox_events where delivery_intent_id = intent.id;
  if outbox.status = 'pending' and outbox.available_at > now() then return 'scheduled'; end if;
  return 'queued';
end;
$$;

revoke all on function private.review_request_message_state(uuid) from public, anon, authenticated;

-- The one plain-language status: what the customer did beats what the messages did; otherwise the newest
-- message's delivery state.
create or replace function private.review_request_status(p_request public.review_requests)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select case
    when p_request.cancelled_at is not null then 'cancelled'
    when p_request.feedback_submitted_at is not null then 'feedback_submitted'
    when p_request.continued_to_google_at is not null then 'continued_to_google'
    when p_request.first_opened_at is not null then 'opened'
    else coalesce((
      select private.review_request_message_state(message.delivery_intent_id)
      from public.review_request_messages as message
      where message.organization_id = p_request.organization_id and message.request_id = p_request.id
      order by message.slot desc
      limit 1
    ), 'queued')
  end;
$$;

revoke all on function private.review_request_status(public.review_requests) from public, anon, authenticated;

-- A request as the app shows it, with every message it sent and what happens next.
create or replace function private.review_request_summary(p_request public.review_requests)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select jsonb_build_object(
    'id', p_request.id,
    'job_id', p_request.job_id,
    'job_number', (select job.job_number from public.jobs as job
                   where job.organization_id = p_request.organization_id and job.id = p_request.job_id),
    'channel', p_request.channel,
    'style', p_request.style,
    'recipient', coalesce(first_intent.recipient_phone, first_intent.recipient_email),
    'status', private.review_request_status(p_request),
    'created_at', p_request.created_at,
    'send_at', first_outbox.available_at,
    'sent_at', first_intent.accepted_at,
    'failure_message', case when first_intent.status in ('failed', 'cancelled') then first_intent.failure_message end,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
               'slot', message.slot,
               'state', private.review_request_message_state(message.delivery_intent_id),
               'send_at', outbox.available_at,
               'sent_at', intent.accepted_at
             ) order by message.slot)
      from public.review_request_messages as message
      left join public.communication_delivery_intents as intent on intent.id = message.delivery_intent_id
      left join public.communication_outbox_events as outbox on outbox.delivery_intent_id = intent.id
      where message.organization_id = p_request.organization_id and message.request_id = p_request.id
    ), '[]'::jsonb),
    'next_reminder_at', p_request.next_reminder_at,
    'stop_reason', p_request.stop_reason,
    'stop_detail', p_request.stop_detail,
    -- While anything is still to go: a reminder due, or a message waiting in the outbox.
    'cancellable', p_request.cancelled_at is null and (
      p_request.next_reminder_at is not null or exists (
        select 1
        from public.review_request_messages as message
        join public.communication_outbox_events as outbox on outbox.delivery_intent_id = message.delivery_intent_id
        where message.organization_id = p_request.organization_id and message.request_id = p_request.id
          and outbox.status = 'pending' and outbox.available_at > now()
      )
    )
  )
  from (select 1) as anchor
  left join public.review_request_messages as first_message
    on first_message.organization_id = p_request.organization_id
   and first_message.request_id = p_request.id and first_message.slot = 0
  left join public.communication_delivery_intents as first_intent on first_intent.id = first_message.delivery_intent_id
  left join public.communication_outbox_events as first_outbox on first_outbox.delivery_intent_id = first_intent.id;
$$;

revoke all on function private.review_request_summary(public.review_requests) from public, anon, authenticated;

-- Ends a request's reminder sequence and takes back any of its messages still waiting to go (with the SMS
-- credit they held). The caller holds the request row lock. A message the outbox is already sending is left
-- alone: it is past the point of recall.
create or replace function private.review_request_stop(
  p_request_id uuid,
  p_reason text,
  p_detail text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  waiting record;
begin
  for waiting in
    select intent.id as intent_id, intent.channel, outbox.id as outbox_id
    from public.review_request_messages as message
    join public.communication_delivery_intents as intent on intent.id = message.delivery_intent_id
    join public.communication_outbox_events as outbox on outbox.delivery_intent_id = intent.id
    where message.request_id = p_request_id
      and outbox.status = 'pending' and outbox.available_at > now()
    for update of intent, outbox
  loop
    update public.communication_outbox_events set status = 'cancelled' where id = waiting.outbox_id;
    update public.communication_delivery_intents
    set status = 'cancelled', failure_code = 'review_request_stopped',
        failure_message = 'The review request stopped before this message was sent.'
    where id = waiting.intent_id;
    if waiting.channel = 'sms' then
      perform private.communication_sms_release_reservation(waiting.intent_id);
    end if;
  end loop;

  update public.review_requests
  set next_reminder_at = null,
      reminder_claim_token = null,
      reminder_attempts = 0,
      stopped_at = coalesce(stopped_at, now()),
      stop_reason = coalesce(stop_reason, p_reason),
      stop_detail = case when stop_reason is null then left(p_detail, 500) else stop_detail end
  where id = p_request_id;
end;
$$;

revoke all on function private.review_request_stop(uuid, text, text) from public, anon, authenticated;

-- Queues one message of a request through the Communications pipeline and records it: the shared path for
-- the first message and every reminder. Refusals (consent, balance, sender, suppression) raise, worded for
-- the contractor. Manual messages go from a sender that allows manual sending; reminders and automatic
-- requests from one that allows automated sending.
create or replace function private.review_request_enqueue_message(
  p_request public.review_requests,
  p_slot smallint,
  p_send_kind text,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_link_url text,
  p_token_hash bytea,
  p_send_at timestamptz,
  p_actor_id uuid,
  p_send_key text
)
returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  send_key text := p_send_key;
  recipient public.client_contact_methods;
  sender public.communication_email_senders;
  alias public.communication_reply_aliases;
  intent public.communication_delivery_intents;
begin
  if p_link_url is null or p_link_url !~ '^https?://[^[:space:]]+$'
    or p_token_hash is null or octet_length(p_token_hash) <> 32 then
    raise exception 'The review link is not available.' using errcode = 'check_violation';
  end if;
  if p_body_text is null or position(p_link_url in p_body_text) = 0
    or (p_request.channel = 'email' and (p_body_html is null or position(p_link_url in p_body_html) = 0)) then
    raise exception 'The message must include the review link.' using errcode = 'check_violation';
  end if;
  if p_request.channel = 'email' and coalesce(btrim(p_subject), '') = '' then
    raise exception 'An email needs a subject.' using errcode = 'check_violation';
  end if;

  select * into recipient from public.client_contact_methods
  where organization_id = p_request.organization_id and client_id = p_request.client_id
    and id = p_request.contact_method_id
    and kind = case when p_request.channel = 'sms' then 'phone' else 'email' end
  for share;
  if recipient.id is null then
    raise exception 'Choose one of this client''s saved % for the review request.',
      case when p_request.channel = 'sms' then 'mobile numbers' else 'email addresses' end
      using errcode = 'foreign_key_violation';
  end if;

  if p_request.channel = 'sms' then
    -- Consent, the sending number, SMS credit and quiet hours are the shared core's job.
    intent := private.communication_sms_enqueue_operational_core(
      p_request.organization_id, p_request.client_id, recipient.id, null, 'service', p_body_text, p_send_kind,
      send_key, p_actor_id, '[]'::jsonb);
    if p_send_at is not null then
      update public.communication_outbox_events
      set available_at = greatest(available_at, p_send_at)
      where delivery_intent_id = intent.id and status = 'pending';
    end if;
  else
    if exists (
      select 1 from public.communication_email_suppressions as suppression
      where suppression.organization_id = p_request.organization_id
        and suppression.recipient_email = recipient.normalized_value
        and suppression.released_at is null
    ) then
      raise exception 'This email address unsubscribed or could not receive email, so it cannot be asked.'
        using errcode = 'check_violation';
    end if;

    sender := private.review_request_email_sender(
      p_request.organization_id, case when p_send_kind = 'automated' then 'automation' else 'manual' end);
    if sender.id is null then
      if p_send_kind = 'automated' then
        raise exception 'Your business email is not set up to send automatic messages.'
          using errcode = 'object_not_in_prerequisite_state';
      end if;
      raise exception 'Your business email is not set up to send yet.' using errcode = 'object_not_in_prerequisite_state';
    end if;

    alias := public.ensure_communication_reply_alias(p_request.organization_id, sender.id, p_request.client_id, recipient.id);

    -- 'optional': a review request is not an essential service message, so an unsubscribe suppresses it.
    insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
      subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by
    ) values (
      p_request.organization_id, p_request.client_id, recipient.id, send_key, recipient.normalized_value,
      btrim(p_subject), p_body_html, p_body_text, p_send_kind, 'optional', sender.id, alias.id, p_actor_id
    )
    returning * into intent;

    insert into public.communication_outbox_events (organization_id, delivery_intent_id, available_at)
    values (p_request.organization_id, intent.id, coalesce(p_send_at, now()));
  end if;

  insert into public.review_request_messages (organization_id, request_id, slot, token_hash, delivery_intent_id)
  values (p_request.organization_id, p_request.id, p_slot, p_token_hash, intent.id);

  return intent;
end;
$$;

revoke all on function private.review_request_enqueue_message(public.review_requests, smallint, text, text, text, text, text, bytea, timestamptz, uuid, text) from public, anon, authenticated;

-- 5. Create and cancel --------------------------------------------------------------------------------------

drop function public.create_review_request(uuid, uuid, uuid, uuid, text, uuid, text, text, text, text, bytea, timestamptz, text);

-- The app renders the first message (it holds the new link) and resolves the plan: p_first_reminder_days is
-- the first reminder's wait, or null when the plan has none. A retry with the same p_idempotency_key returns
-- the first request instead of sending twice.
create or replace function public.create_review_request(
  p_organization_id uuid,
  p_actor_id uuid,
  p_client_id uuid,
  p_job_id uuid,
  p_channel text,
  p_style text,
  p_contact_method_id uuid,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_link_url text,
  p_token_hash bytea,
  p_send_at timestamptz,
  p_first_reminder_days integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing_request public.review_requests;
  client_row public.clients;
  request_row public.review_requests;
  intent public.communication_delivery_intents;
  first_send_at timestamptz;
begin
  if p_organization_id is null or p_actor_id is null or p_client_id is null then
    raise exception 'An organization, an actor and a client are required.' using errcode = 'check_violation';
  end if;
  if p_channel is null or p_channel not in ('sms', 'email') then
    raise exception 'Choose text message or email.' using errcode = 'check_violation';
  end if;
  if p_style is null or p_style not in ('friendly', 'professional', 'short') then
    raise exception 'Choose a message style.' using errcode = 'check_violation';
  end if;
  if coalesce(btrim(p_idempotency_key), '') = '' then
    raise exception 'A send key is required.' using errcode = 'check_violation';
  end if;
  if p_send_at is not null and (p_send_at <= now() or p_send_at > now() + interval '90 days') then
    raise exception 'Choose a send time within the next 90 days.' using errcode = 'check_violation';
  end if;
  if p_first_reminder_days is not null and p_first_reminder_days not between 1 and 60 then
    raise exception 'A reminder waits 1 to 60 days.' using errcode = 'check_violation';
  end if;

  -- A retry of the same send returns what the first attempt made.
  select * into existing_request from public.review_requests
  where organization_id = p_organization_id and id = (
    select message.request_id
    from public.review_request_messages as message
    join public.communication_delivery_intents as sent_intent on sent_intent.id = message.delivery_intent_id
    where sent_intent.organization_id = p_organization_id
      and sent_intent.logical_send_key = 'review_request:' || btrim(p_idempotency_key)
  );
  if existing_request.id is not null then
    return private.review_request_summary(existing_request);
  end if;

  if not private.review_request_actor_may_ask(p_organization_id, p_actor_id, p_job_id) then
    raise exception 'You do not have permission to ask this customer for a review.' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.organizations where id = p_organization_id and lifecycle_status = 'active'
  ) then
    raise exception 'This business cannot send messages right now.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  select * into client_row from public.clients
  where organization_id = p_organization_id and id = p_client_id and deleted_at is null
  for share;
  if client_row.id is null then
    raise exception 'That client was not found.' using errcode = 'no_data_found';
  end if;

  if p_job_id is not null then
    if not exists (
      select 1 from public.jobs where organization_id = p_organization_id and id = p_job_id and client_id = p_client_id
    ) then
      raise exception 'That job was not found for this client.' using errcode = 'no_data_found';
    end if;
    if not private.review_request_job_is_eligible(p_organization_id, p_job_id) then
      raise exception 'Ask for a review once work on this job has been completed.' using errcode = 'check_violation';
    end if;
  end if;

  insert into public.review_requests (
    organization_id, client_id, job_id, created_by, channel, origin, style, contact_method_id
  )
  values (p_organization_id, p_client_id, p_job_id, p_actor_id, p_channel, 'manual', p_style, p_contact_method_id)
  returning * into request_row;

  -- The first message's send key is the panel's own, so a retry finds it (above).
  intent := private.review_request_enqueue_message(
    request_row, 0::smallint, 'manual', p_subject, p_body_text, p_body_html, p_link_url, p_token_hash,
    p_send_at, p_actor_id, 'review_request:' || btrim(p_idempotency_key));

  -- A first estimate; the reminder re-counts from when the first message was actually accepted.
  if p_first_reminder_days is not null then
    select outbox.available_at into first_send_at
    from public.communication_outbox_events as outbox where outbox.delivery_intent_id = intent.id;
    update public.review_requests
    set next_reminder_at = private.review_request_days_later(
      p_organization_id, coalesce(first_send_at, p_send_at, now()), p_first_reminder_days)
    where id = request_row.id
    returning * into request_row;
  end if;

  return private.review_request_summary(request_row);
end;
$$;

comment on function public.create_review_request(uuid, uuid, uuid, uuid, text, text, uuid, text, text, text, text, bytea, timestamptz, integer, text) is
  'Creates a manual review request, queues its first SMS or email (optionally scheduled) through the Communications outbox and schedules its first reminder, in one transaction. Idempotent on p_idempotency_key. Service role only.';

-- Cancels while anything is still to go (a reminder due or a message waiting). The link stops working, as
-- for every cancelled request (owner decision 2026-09-25).
create or replace function public.cancel_review_request(
  p_organization_id uuid,
  p_actor_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  request_row public.review_requests;
begin
  select * into request_row from public.review_requests
  where organization_id = p_organization_id and id = p_request_id
  for update;
  if request_row.id is null
    or not private.review_request_actor_may_ask(p_organization_id, p_actor_id, request_row.job_id) then
    raise exception 'That review request was not found.' using errcode = 'no_data_found';
  end if;
  if request_row.cancelled_at is not null then
    return private.review_request_summary(request_row);
  end if;
  if not (private.review_request_summary(request_row) ->> 'cancellable')::boolean then
    raise exception 'Every message of this review request has already been sent, so there is nothing left to cancel.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  perform private.review_request_stop(request_row.id, 'cancelled', null);

  update public.review_requests
  set cancelled_at = now(), cancelled_by = p_actor_id
  where id = request_row.id
  returning * into request_row;

  return private.review_request_summary(request_row);
end;
$$;

comment on function public.cancel_review_request(uuid, uuid, uuid) is
  'Cancels a review request while a message or reminder is still to go: takes back waiting messages and their SMS credit, stops the reminders and switches its links off. Service role only.';

-- 6. The customer's actions stop the reminders --------------------------------------------------------------

create or replace function public.record_review_request_google(
  supplied_token_hash bytea,
  supplied_rating smallint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  request_row public.review_requests;
begin
  if supplied_rating is not null and supplied_rating not between 1 and 5 then
    raise exception 'A rating is 1 to 5 stars.' using errcode = 'check_violation';
  end if;

  select request.* into request_row
  from public.review_requests as request
  where request.id = (private.live_review_request(supplied_token_hash)).id
  for update;
  if request_row.id is null then
    return;
  end if;

  update public.review_requests
  set continued_to_google_at = coalesce(continued_to_google_at, now()),
      rating = coalesce(supplied_rating, rating)
  where id = request_row.id;

  perform private.review_request_stop(request_row.id, 'continued_to_google', null);
end;
$$;

create or replace function public.submit_review_feedback(
  supplied_token_hash bytea,
  supplied_rating smallint,
  supplied_questions jsonb,
  supplied_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  request_row public.review_requests;
  feedback_id uuid;
begin
  if supplied_rating is not null and supplied_rating not between 1 and 5 then
    raise exception 'A rating is 1 to 5 stars.' using errcode = 'check_violation';
  end if;

  -- Locked so two taps of Send at once cannot both pass the "not yet submitted" test.
  select request.* into request_row
  from public.review_requests as request
  where request.id = (private.live_review_request(supplied_token_hash)).id
  for update;
  if request_row.id is null then
    return null;
  end if;

  if request_row.feedback_submitted_at is not null then
    return jsonb_build_object('state', 'already_submitted');
  end if;

  insert into public.review_feedback (organization_id, request_id, rating, questions, answers)
  values (request_row.organization_id, request_row.id, supplied_rating, supplied_questions, supplied_answers)
  returning id into feedback_id;

  update public.review_requests
  set feedback_submitted_at = now(),
      rating = coalesce(supplied_rating, rating)
  where id = request_row.id;

  perform private.review_request_stop(request_row.id, 'feedback_submitted', null);

  return jsonb_build_object('state', 'submitted', 'feedback_id', feedback_id);
end;
$$;

-- 7. The reminder worker ------------------------------------------------------------------------------------

-- Claims a bounded, organization-fair batch of requests whose next reminder is due, under a per-row lease:
-- the due marker moves to the lease's end, so a worker that dies leaves the row to be claimed again then.
-- Returns what the app needs to write the reminder: the slot, channel, style, names and the saved plan
-- (null = UCRM's defaults). Rows that failed p_max_attempts times stop instead.
create or replace function public.claim_review_reminders(
  p_batch_size integer default 25,
  p_per_organization_cap integer default 5,
  p_lease_seconds integer default 120,
  p_max_attempts integer default 5
)
returns table (
  request_id uuid,
  claim_token uuid,
  organization_id uuid,
  slot smallint,
  channel text,
  style text,
  business_name text,
  customer_first_name text,
  customer_name text,
  request_plan jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
#variable_conflict use_column
declare
  v_token uuid := gen_random_uuid();
  doomed record;
begin
  if p_batch_size < 1 or p_batch_size > 200 then
    raise exception 'The claim batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_per_organization_cap < 1 or p_per_organization_cap > p_batch_size then
    raise exception 'The per-organization cap is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The claim lease is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception 'The attempt cap is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for doomed in
    select request.id
    from public.review_requests as request
    where request.next_reminder_at <= now()
      and request.reminder_attempts >= p_max_attempts
    order by request.next_reminder_at, request.id
    limit p_batch_size
    for update skip locked
  loop
    perform private.review_request_stop(doomed.id, 'error', 'The reminder could not be sent after several tries.');
  end loop;

  return query
  with candidates as (
    select request.id, request.next_reminder_at, request.organization_id
    from public.review_requests as request
    where request.next_reminder_at <= now()
      and request.reminder_attempts < p_max_attempts
    order by request.next_reminder_at, request.id
    limit least(p_batch_size * 4, 400)
  ),
  due as (
    select candidates.id, candidates.next_reminder_at,
      row_number() over (
        partition by candidates.organization_id order by candidates.next_reminder_at, candidates.id
      ) as per_organization_rank
    from candidates
  ),
  ranked as (
    select due.id,
      row_number() over (
        order by (due.per_organization_rank > p_per_organization_cap), due.next_reminder_at, due.id
      ) as pick_order
    from due
  ),
  locked as (
    select request.id
    from public.review_requests as request
    where request.id in (select ranked.id from ranked where ranked.pick_order <= p_batch_size)
      and request.next_reminder_at <= now()
    for update skip locked
  ),
  claimed as (
    update public.review_requests as request
    set reminder_claim_token = v_token,
        reminder_attempts = request.reminder_attempts + 1,
        next_reminder_at = now() + make_interval(secs => p_lease_seconds)
    from locked
    where request.id = locked.id
    returning request.*
  )
  select
    claimed.id,
    claimed.reminder_claim_token,
    claimed.organization_id,
    (coalesce((
      select max(message.slot) from public.review_request_messages as message
      where message.organization_id = claimed.organization_id and message.request_id = claimed.id
    ), -1) + 1)::smallint,
    claimed.channel,
    claimed.style,
    organization.name,
    coalesce(split_part(nullif(btrim(concat_ws(' ', contact.first_name, contact.last_name)), ''), ' ', 1),
             nullif(btrim(client.first_name), ''), split_part(client.display_name, ' ', 1)),
    coalesce(nullif(btrim(concat_ws(' ', contact.first_name, contact.last_name)), ''), client.display_name),
    settings.request_plan
  from claimed
  join public.organizations as organization on organization.id = claimed.organization_id
  join public.clients as client on client.organization_id = claimed.organization_id and client.id = claimed.client_id
  left join public.client_contact_methods as method
    on method.organization_id = claimed.organization_id and method.id = claimed.contact_method_id
  left join public.client_contacts as contact
    on contact.organization_id = method.organization_id and contact.id = method.client_contact_id
  left join public.review_settings as settings on settings.organization_id = claimed.organization_id;
end;
$$;

comment on function public.claim_review_reminders(integer, integer, integer, integer) is
  'Atomically claims a bounded, organization-fair batch of review requests whose next reminder is due, under a per-row lease, with what the app needs to write each reminder. Safe from any number of workers at once. Service role only.';

-- Sends one claimed reminder, or decides it must not go. The app has written the reminder from the plan it
-- read at claim time: p_wait_days is this reminder's wait after the previous message, p_next_wait_days the
-- following one's (null when this is the last), and a null p_body_text says the plan no longer has this
-- reminder. Everything is re-checked here, under the request lock. Returns 'sent', 'waiting' (the previous
-- message is not out yet, or the wait is not over), 'stopped', or 'claim_lost'. A refusal to send stops the
-- sequence; any other error rolls back and the lease brings the row round again.
create or replace function public.send_review_reminder(
  p_request_id uuid,
  p_claim_token uuid,
  p_slot smallint,
  p_wait_days integer,
  p_next_wait_days integer,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_link_url text,
  p_token_hash bytea
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  request_row public.review_requests;
  previous_intent public.communication_delivery_intents;
  previous_outbox public.communication_outbox_events;
  due_at timestamptz;
  intent public.communication_delivery_intents;
  send_at timestamptz;
begin
  select * into request_row from public.review_requests
  where id = p_request_id and reminder_claim_token = p_claim_token
  for update;
  if request_row.id is null then
    return 'claim_lost';
  end if;

  if request_row.cancelled_at is not null or request_row.stopped_at is not null then
    perform private.review_request_stop(request_row.id, 'cancelled', null);
    return 'stopped';
  end if;
  if request_row.continued_to_google_at is not null then
    perform private.review_request_stop(request_row.id, 'continued_to_google', null);
    return 'stopped';
  end if;
  if request_row.feedback_submitted_at is not null then
    perform private.review_request_stop(request_row.id, 'feedback_submitted', null);
    return 'stopped';
  end if;

  -- The slot the claim computed must still be the next one.
  if p_slot is distinct from (
    select coalesce(max(message.slot), -1) + 1 from public.review_request_messages as message
    where message.organization_id = request_row.organization_id and message.request_id = request_row.id
  ) or p_slot < 1 then
    update public.review_requests set reminder_claim_token = null, next_reminder_at = now()
    where id = request_row.id;
    return 'claim_lost';
  end if;

  if p_body_text is null then
    perform private.review_request_stop(request_row.id, 'plan_changed',
      'The reminder plan in Review settings no longer includes this reminder.');
    return 'stopped';
  end if;
  if p_wait_days is null or p_wait_days not between 1 and 60
    or (p_next_wait_days is not null and p_next_wait_days not between 1 and 60) then
    raise exception 'A reminder waits 1 to 60 days.' using errcode = 'check_violation';
  end if;

  -- The previous message must have gone out, and the wait counts from when it did.
  select intent_row.* into previous_intent
  from public.review_request_messages as message
  join public.communication_delivery_intents as intent_row on intent_row.id = message.delivery_intent_id
  where message.organization_id = request_row.organization_id and message.request_id = request_row.id
    and message.slot = p_slot - 1;
  if previous_intent.id is null
    or previous_intent.status in ('failed', 'cancelled')
    or previous_intent.delivery_outcome in ('hard_bounce', 'complaint', 'blocked', 'unsubscribed', 'sms_undelivered', 'sms_failed') then
    perform private.review_request_stop(request_row.id, 'not_delivered', previous_intent.failure_message);
    return 'stopped';
  end if;
  if previous_intent.accepted_at is null then
    select * into previous_outbox from public.communication_outbox_events where delivery_intent_id = previous_intent.id;
    update public.review_requests
    set reminder_claim_token = null, reminder_attempts = 0,
        next_reminder_at = greatest(coalesce(previous_outbox.available_at, now()), now()) + interval '30 minutes'
    where id = request_row.id;
    return 'waiting';
  end if;
  due_at := private.review_request_days_later(request_row.organization_id, previous_intent.accepted_at, p_wait_days);
  if due_at > now() then
    update public.review_requests
    set reminder_claim_token = null, reminder_attempts = 0, next_reminder_at = due_at
    where id = request_row.id;
    return 'waiting';
  end if;

  -- Still someone the business may remind about this work.
  if not exists (
    select 1 from public.clients
    where organization_id = request_row.organization_id and id = request_row.client_id and deleted_at is null
  ) then
    perform private.review_request_stop(request_row.id, 'client_removed', null);
    return 'stopped';
  end if;
  if exists (
    select 1 from public.client_communication_preferences as preference
    where preference.organization_id = request_row.organization_id and preference.client_id = request_row.client_id
      and not preference.review_requests
  ) then
    perform private.review_request_stop(request_row.id, 'client_opted_out', null);
    return 'stopped';
  end if;
  if request_row.job_id is not null
    and not private.review_request_job_is_eligible(request_row.organization_id, request_row.job_id) then
    perform private.review_request_stop(request_row.id, 'job_not_eligible', null);
    return 'stopped';
  end if;
  if not exists (
    select 1 from public.organizations where id = request_row.organization_id and lifecycle_status = 'active'
  ) then
    perform private.review_request_stop(request_row.id, 'not_sent', 'This business cannot send messages right now.');
    return 'stopped';
  end if;
  if request_row.contact_method_id is null or not exists (
    select 1 from public.client_contact_methods
    where organization_id = request_row.organization_id and client_id = request_row.client_id
      and id = request_row.contact_method_id
  ) then
    perform private.review_request_stop(request_row.id, 'no_contact', null);
    return 'stopped';
  end if;

  begin
    intent := private.review_request_enqueue_message(
      request_row, p_slot, 'automated', p_subject, p_body_text, p_body_html, p_link_url, p_token_hash, null, null,
      'review_request:' || request_row.id || ':reminder:' || p_slot);
  exception
    -- The refusals the send path words for the contractor: consent or STOP, suppression, balance, a sender
    -- or number not set up, length. They end the sequence; anything else is a fault and is retried.
    when sqlstate 'P0001' or sqlstate '23514' or sqlstate '23503' or sqlstate '55000' or sqlstate 'P0402' then
      perform private.review_request_stop(request_row.id, 'not_sent', sqlerrm);
      return 'stopped';
  end;

  select outbox.available_at into send_at
  from public.communication_outbox_events as outbox where outbox.delivery_intent_id = intent.id;

  update public.review_requests
  set reminder_claim_token = null,
      reminder_attempts = 0,
      next_reminder_at = case when p_next_wait_days is null then null
        else private.review_request_days_later(request_row.organization_id, coalesce(send_at, now()), p_next_wait_days) end
  where id = request_row.id;

  return 'sent';
end;
$$;

comment on function public.send_review_reminder(uuid, uuid, smallint, integer, integer, text, text, text, text, bytea) is
  'Sends one claimed review reminder through the Communications outbox after re-checking the customer''s actions, the previous message, the wait, the client, the job, consent and the sender; or reschedules or stops the sequence. Service role only.';

revoke all on function public.create_review_request(uuid, uuid, uuid, uuid, text, text, uuid, text, text, text, text, bytea, timestamptz, integer, text) from public, anon, authenticated;
revoke all on function public.cancel_review_request(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.record_review_request_google(bytea, smallint) from public, anon, authenticated;
revoke all on function public.submit_review_feedback(bytea, smallint, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.claim_review_reminders(integer, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.send_review_reminder(uuid, uuid, smallint, integer, integer, text, text, text, text, bytea) from public, anon, authenticated;
grant execute on function public.create_review_request(uuid, uuid, uuid, uuid, text, text, uuid, text, text, text, text, bytea, timestamptz, integer, text) to service_role;
grant execute on function public.cancel_review_request(uuid, uuid, uuid) to service_role;
grant execute on function public.record_review_request_google(bytea, smallint) to service_role;
grant execute on function public.submit_review_feedback(bytea, smallint, jsonb, jsonb) to service_role;
grant execute on function public.claim_review_reminders(integer, integer, integer, integer) to service_role;
grant execute on function public.send_review_reminder(uuid, uuid, smallint, integer, integer, text, text, text, text, bytea) to service_role;
