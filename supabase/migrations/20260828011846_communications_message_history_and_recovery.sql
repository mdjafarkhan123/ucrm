-- Communications Part 7.6a: one message history, and Jafar's recovery actions on top of it.
--
-- Everything a message goes through is already decided somewhere -- the outbox row knows it was
-- queued, claimed, deferred, cancelled or sent; the delivery intent knows what the provider said;
-- an inbound message knows a reply came back. What was missing is a single ordered story: the
-- outbox row is updated in place, so every deferral overwrites the one before it and nothing
-- survives to explain why a message sat for six hours.
--
-- docs/contractor-email-contract.md
--   § Queueing, retries, and history
--     "One history links queued, deferred, sent, delivered, bounced, complained, replied, cancelled,
--      and resent events. It records the actor, template version, sender, recipients, related CRM
--      record, provider identifier, automation execution, forwarding, and administrative intervention
--      without exposing provider secrets."
--   § Platform Owner controls
--     "retry and recovery actions that still enforce consent, suppression, authorization, and
--      idempotency"
--
-- Shape, and why:
--
--   * The history is written by AFTER triggers on the tables that already decide the facts, not by
--     edits inside the claim / enqueue / finalize functions. Those functions have been re-created by
--     7.1, 7.3 and 7.4 already; adding history writes to each of their branches is a dozen more
--     places to keep in step, and any missed branch is a silent hole. A trigger cannot be bypassed.
--
--   * Repeated identical deferrals collapse. A message held by an organization pause re-checks every
--     five minutes and can stay held for 72 hours; a row per attempt would be hundreds of rows saying
--     the same sentence. Instead the last deferral row carries `repeat_count` and `last_occurred_at`,
--     the way an ESP event log or Sentry shows "seen 43 times". A new reason always starts a new row,
--     so the sequence of *reasons* -- which is the part a human reads -- stays intact.
--
--   * The log is append-only. Rows are never updated except by the deferral collapse above, and never
--     deleted except with the message itself.

-- ---------------------------------------------------------------------------------------------------
-- 1. The history table.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_message_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  delivery_intent_id uuid not null
    references public.communication_delivery_intents (id) on delete cascade,
  event_kind text not null check (event_kind in (
    -- application lifecycle
    'queued', 'claimed', 'deferred', 'held', 'cancelled', 'sent', 'send_failed', 'submission_unknown',
    -- what the provider told us afterwards
    'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'provider_deferred', 'blocked',
    'unsubscribed',
    -- relationships to other messages and people
    'replied', 'resent', 'administrative_intervention'
  )),
  occurred_at timestamptz not null default now(),
  -- Only a collapsed deferral streak moves these; every other row keeps last = first, repeat = 1.
  last_occurred_at timestamptz not null default now(),
  repeat_count integer not null default 1 check (repeat_count >= 1),
  attempt_number integer check (attempt_number >= 0),
  reason_code text,
  reason_message text,
  retry_at timestamptz,
  actor_kind text not null default 'system'
    check (actor_kind in ('system', 'provider', 'recipient', 'user', 'platform_owner')),
  actor_user_id uuid references auth.users (id) on delete set null,
  actor_email text,
  -- A resend links the original message to its replacement; a reply links to the inbound message.
  related_intent_id uuid references public.communication_delivery_intents (id) on delete set null,
  related_inbound_message_id uuid
    references public.communication_inbound_messages (id) on delete set null,
  constraint communication_message_events_span_check check (last_occurred_at >= occurred_at)
);

comment on table public.communication_message_events is
  'Append-only lifecycle history for one outbound message. Written by triggers on the tables that '
  'decide each fact. Repeated identical deferrals collapse into one row via repeat_count.';

-- The timeline read: every event for one message, oldest first.
create index communication_message_events_timeline_idx
  on public.communication_message_events (delivery_intent_id, occurred_at, id);

-- The deferral collapse looks for the newest event of one message.
create index communication_message_events_latest_idx
  on public.communication_message_events (delivery_intent_id, occurred_at desc, id desc);

-- Foreign-key cover, so a cascade or a set-null never seq-scans this table.
create index communication_message_events_organization_idx
  on public.communication_message_events (organization_id, occurred_at desc, id desc);
create index communication_message_events_actor_user_idx
  on public.communication_message_events (actor_user_id) where actor_user_id is not null;
create index communication_message_events_related_intent_idx
  on public.communication_message_events (related_intent_id) where related_intent_id is not null;
create index communication_message_events_related_inbound_idx
  on public.communication_message_events (related_inbound_message_id)
  where related_inbound_message_id is not null;

alter table public.communication_message_events enable row level security;
-- No policy and no `authenticated` grant: like the suppression and pause tables from 7.1-7.4, every
-- read goes through the owner (service-role) client with an explicit organization filter.
revoke all on table public.communication_message_events from public, anon, authenticated;

-- Append-only. The one legal update is the deferral collapse, which runs as the definer function
-- below and sets this flag first. Deletes are not guarded here: the only way a row goes is with its
-- message, through the cascade a purge relies on.
create or replace function private.guard_communication_message_events_append_only()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('ucrm.message_event_collapse', true), '') <> 'on' then
    raise exception 'Message history cannot be edited.' using errcode = 'check_violation';
  end if;
  if new.id <> old.id
    or new.delivery_intent_id <> old.delivery_intent_id
    or new.event_kind <> old.event_kind
    or new.occurred_at <> old.occurred_at then
    raise exception 'Message history cannot be rewritten.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger communication_message_events_append_only
before update on public.communication_message_events
for each row execute function private.guard_communication_message_events_append_only();

-- ---------------------------------------------------------------------------------------------------
-- 2. One writer. Every trigger and every recovery command goes through this.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.record_communication_message_event(
  p_organization_id uuid,
  p_delivery_intent_id uuid,
  p_event_kind text,
  p_occurred_at timestamptz default now(),
  p_attempt_number integer default null,
  p_reason_code text default null,
  p_reason_message text default null,
  p_retry_at timestamptz default null,
  p_actor_kind text default 'system',
  p_actor_user_id uuid default null,
  p_actor_email text default null,
  p_related_intent_id uuid default null,
  p_related_inbound_message_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  latest public.communication_message_events;
  new_id uuid;
begin
  -- A stalled message re-checks on a timer. Collapsing an unchanged reason keeps the history at the
  -- length of the story instead of the length of the wait.
  if p_event_kind = 'deferred' then
    select * into latest
    from public.communication_message_events
    where delivery_intent_id = p_delivery_intent_id
    order by occurred_at desc, id desc
    limit 1;

    if latest.id is not null
      and latest.event_kind = 'deferred'
      and latest.reason_code is not distinct from p_reason_code then
      perform set_config('ucrm.message_event_collapse', 'on', true);
      update public.communication_message_events
      set repeat_count = repeat_count + 1,
        last_occurred_at = greatest(p_occurred_at, latest.last_occurred_at),
        retry_at = p_retry_at,
        reason_message = coalesce(p_reason_message, reason_message),
        attempt_number = coalesce(p_attempt_number, attempt_number)
      where id = latest.id;
      perform set_config('ucrm.message_event_collapse', 'off', true);
      return latest.id;
    end if;
  end if;

  insert into public.communication_message_events (
    organization_id, delivery_intent_id, event_kind, occurred_at, last_occurred_at,
    attempt_number, reason_code, reason_message, retry_at,
    actor_kind, actor_user_id, actor_email, related_intent_id, related_inbound_message_id
  ) values (
    p_organization_id, p_delivery_intent_id, p_event_kind, p_occurred_at, p_occurred_at,
    p_attempt_number, p_reason_code, nullif(btrim(coalesce(p_reason_message, '')), ''), p_retry_at,
    coalesce(p_actor_kind, 'system'), p_actor_user_id,
    nullif(btrim(coalesce(p_actor_email, '')), ''), p_related_intent_id, p_related_inbound_message_id
  )
  returning id into new_id;
  return new_id;
end;
$$;

revoke all on function private.record_communication_message_event(
  uuid, uuid, text, timestamptz, integer, text, text, timestamptz, text, uuid, text, uuid, uuid
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 3. Queued, and the resend link back to the original.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.communication_outbox_event_queued_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  intent public.communication_delivery_intents;
begin
  select * into intent from public.communication_delivery_intents where id = new.delivery_intent_id;
  if intent.id is null then
    return new;
  end if;

  perform private.record_communication_message_event(
    p_organization_id => new.organization_id,
    p_delivery_intent_id => new.delivery_intent_id,
    p_event_kind => 'queued',
    p_occurred_at => new.created_at,
    p_attempt_number => new.attempt_count,
    p_actor_kind => case when intent.created_by is not null then 'user' else 'system' end,
    p_actor_user_id => intent.created_by
  );

  -- A resend is a new message, but the story belongs to the original too: "we sent this again".
  if intent.resent_from_intent_id is not null then
    perform private.record_communication_message_event(
      p_organization_id => new.organization_id,
      p_delivery_intent_id => intent.resent_from_intent_id,
      p_event_kind => 'resent',
      p_occurred_at => new.created_at,
      p_actor_kind => case when intent.created_by is not null then 'user' else 'system' end,
      p_actor_user_id => intent.created_by,
      p_related_intent_id => new.delivery_intent_id
    );
  end if;

  return new;
end;
$$;

create trigger communication_outbox_events_history_queued
after insert on public.communication_outbox_events
for each row execute function private.communication_outbox_event_queued_history();

-- ---------------------------------------------------------------------------------------------------
-- 4. Everything the claim and the worker decide afterwards.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.communication_outbox_event_progress_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  intent public.communication_delivery_intents;
  kind text;
begin
  select * into intent from public.communication_delivery_intents where id = new.delivery_intent_id;

  if new.status is distinct from old.status then
    kind := case new.status
      when 'processing' then 'claimed'
      when 'submitted' then 'sent'
      when 'cancelled' then 'cancelled'
      when 'submission_unknown' then 'submission_unknown'
      -- Back to pending after a transient send failure: the worker handed it back for another try.
      when 'pending' then 'deferred'
      when 'failed' then
        case when intent.failure_code = 'manual_sender_review_required' then 'held' else 'send_failed' end
    end;
    if kind is null then
      return new;
    end if;

    perform private.record_communication_message_event(
      p_organization_id => new.organization_id,
      p_delivery_intent_id => new.delivery_intent_id,
      p_event_kind => kind,
      p_attempt_number => new.attempt_count,
      p_reason_code => case when kind in ('claimed', 'sent') then null else intent.failure_code end,
      p_reason_message => case when kind in ('claimed', 'sent') then null else new.last_error end,
      p_retry_at => case when kind = 'deferred' then new.available_at end
    );
    return new;
  end if;

  -- Status unchanged but the message was pushed into the future: a claim check said "not yet".
  if new.available_at > old.available_at then
    perform private.record_communication_message_event(
      p_organization_id => new.organization_id,
      p_delivery_intent_id => new.delivery_intent_id,
      p_event_kind => 'deferred',
      p_attempt_number => new.attempt_count,
      p_reason_code => intent.failure_code,
      p_reason_message => new.last_error,
      p_retry_at => new.available_at
    );
  end if;

  return new;
end;
$$;

create trigger communication_outbox_events_history_progress
after update on public.communication_outbox_events
for each row execute function private.communication_outbox_event_progress_history();

-- ---------------------------------------------------------------------------------------------------
-- 5. What the provider said. 7.1's callback processor lands these on the intent.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.communication_delivery_outcome_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.delivery_outcome is null
    or new.delivery_outcome is not distinct from old.delivery_outcome then
    return new;
  end if;

  perform private.record_communication_message_event(
    p_organization_id => new.organization_id,
    p_delivery_intent_id => new.id,
    -- The provider's own word for a temporary hold collides with ours, so it is named apart.
    p_event_kind => case when new.delivery_outcome = 'deferred'
      then 'provider_deferred' else new.delivery_outcome end,
    p_occurred_at => coalesce(new.delivery_outcome_at, now()),
    p_reason_message => new.delivery_outcome_detail,
    p_actor_kind => 'provider'
  );
  return new;
end;
$$;

create trigger communication_delivery_intents_history_outcome
after update of delivery_outcome on public.communication_delivery_intents
for each row execute function private.communication_delivery_outcome_history();

-- ---------------------------------------------------------------------------------------------------
-- 6. The reply that came back.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.communication_inbound_reply_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  intent_organization_id uuid;
begin
  if new.in_reply_to_intent_id is null then
    return new;
  end if;

  select organization_id into intent_organization_id
  from public.communication_delivery_intents where id = new.in_reply_to_intent_id;
  if intent_organization_id is distinct from new.organization_id then
    return new;
  end if;

  perform private.record_communication_message_event(
    p_organization_id => new.organization_id,
    p_delivery_intent_id => new.in_reply_to_intent_id,
    p_event_kind => 'replied',
    p_occurred_at => new.created_at,
    p_actor_kind => 'recipient',
    p_actor_email => new.sender_email,
    p_related_inbound_message_id => new.id
  );
  return new;
end;
$$;

create trigger communication_inbound_messages_history_reply
after insert on public.communication_inbound_messages
for each row execute function private.communication_inbound_reply_history();

-- ---------------------------------------------------------------------------------------------------
-- 7. Reading one message's story.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_message_history(
  p_organization_id uuid,
  p_delivery_intent_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select case when intent.id is null then null else jsonb_build_object(
    'message', jsonb_build_object(
      'id', intent.id,
      'organization_id', intent.organization_id,
      'organization_name', org.name,
      'client_id', intent.client_id,
      'subject', intent.subject,
      'recipient_email', intent.recipient_email,
      'send_kind', intent.send_kind,
      'allowance_class', intent.allowance_class,
      'logical_send_key', intent.logical_send_key,
      'status', intent.status,
      'delivery_outcome', intent.delivery_outcome,
      'failure_code', intent.failure_code,
      'failure_message', intent.failure_message,
      -- The provider identifier belongs in the history; provider credentials never do.
      'provider_message_id', intent.provider_message_id,
      'quote_id', intent.quote_id,
      'resent_from_intent_id', intent.resent_from_intent_id,
      'sender_email', sender.email_address,
      'sender_display_name', sender.display_name,
      'created_at', intent.created_at,
      'accepted_at', intent.accepted_at,
      'outbox_status', outbox.status,
      'attempt_count', outbox.attempt_count,
      'available_at', outbox.available_at,
      'last_error', outbox.last_error
    ),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', history.id,
        'event_kind', history.event_kind,
        'occurred_at', history.occurred_at,
        'last_occurred_at', history.last_occurred_at,
        'repeat_count', history.repeat_count,
        'attempt_number', history.attempt_number,
        'reason_code', history.reason_code,
        'reason_message', history.reason_message,
        'retry_at', history.retry_at,
        'actor_kind', history.actor_kind,
        'actor_email', coalesce(history.actor_email, actor_account.email),
        'actor_name', actor.full_name,
        'related_intent_id', history.related_intent_id,
        'related_inbound_message_id', history.related_inbound_message_id
      ) order by history.occurred_at, history.id)
      from public.communication_message_events history
      left join public.profiles actor on actor.id = history.actor_user_id
      left join auth.users actor_account on actor_account.id = history.actor_user_id
      where history.delivery_intent_id = intent.id
    ), '[]'::jsonb)
  ) end
  from public.communication_delivery_intents intent
  join public.organizations org on org.id = intent.organization_id
  left join public.communication_email_senders sender on sender.id = intent.sender_id
  left join public.communication_outbox_events outbox on outbox.delivery_intent_id = intent.id
  where intent.id = p_delivery_intent_id
    and intent.organization_id = p_organization_id;
$$;

revoke all on function public.get_communication_message_history(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.get_communication_message_history(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 8. Jafar's recovery queue: the messages that are not moving on their own.
-- ---------------------------------------------------------------------------------------------------

-- Newest-trouble-first across every tenant. Without this the list seq-scans the whole outbox as mail
-- volume grows; the predicate keeps the index to the small unhappy tail.
create index communication_outbox_events_recovery_idx
  on public.communication_outbox_events (updated_at desc, id desc)
  where status = 'failed' or (status = 'pending' and last_error is not null);

create or replace function public.get_communication_message_recovery_queue()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  with troubled as (
    select outbox.*
    from public.communication_outbox_events outbox
    where outbox.status = 'failed'
      or (outbox.status = 'pending' and outbox.last_error is not null)
    order by outbox.updated_at desc, outbox.id desc
    limit 50
  )
  select jsonb_build_object(
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'delivery_intent_id', intent.id,
        'organization_id', intent.organization_id,
        'organization_name', org.name,
        'subject', intent.subject,
        'recipient_email', intent.recipient_email,
        'send_kind', intent.send_kind,
        'allowance_class', intent.allowance_class,
        'intent_status', intent.status,
        'outbox_status', troubled.status,
        'attempt_count', troubled.attempt_count,
        'available_at', troubled.available_at,
        'failure_code', intent.failure_code,
        'last_error', troubled.last_error,
        'updated_at', troubled.updated_at,
        'created_at', intent.created_at
      ) order by troubled.updated_at desc, troubled.id desc)
      from troubled
      join public.communication_delivery_intents intent on intent.id = troubled.delivery_intent_id
      join public.organizations org on org.id = intent.organization_id
    ), '[]'::jsonb),
    'held_total', (
      select count(*) from public.communication_outbox_events where status = 'failed'
    ),
    'waiting_total', (
      select count(*) from public.communication_outbox_events
      where status = 'pending' and last_error is not null
    )
  );
$$;

revoke all on function public.get_communication_message_recovery_queue()
  from public, anon, authenticated;
grant execute on function public.get_communication_message_recovery_queue() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 9. Retry. It re-opens a message for the claim; it does not send anything and it does not skip a
--    single check -- the claim re-runs recipient eligibility, suppression, pauses, warm-up, capacity
--    and allowance exactly as it would for a first attempt.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.retry_communication_message(
  p_delivery_intent_id uuid,
  p_reason text,
  p_actor_email text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  outbox public.communication_outbox_events;
  intent public.communication_delivery_intents;
  clean_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  clean_actor text := nullif(btrim(coalesce(p_actor_email, '')), '');
begin
  if clean_actor is null then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if clean_reason is null or char_length(clean_reason) < 3 or char_length(clean_reason) > 1000 then
    raise exception 'A reason of 3 to 1000 characters is required.' using errcode = 'check_violation';
  end if;

  select * into outbox from public.communication_outbox_events
  where delivery_intent_id = p_delivery_intent_id for update;
  if outbox.id is null then
    raise exception 'That message was not found.' using errcode = 'no_data_found';
  end if;
  select * into intent from public.communication_delivery_intents
  where id = p_delivery_intent_id for update;

  if outbox.status = 'submitted' then
    raise exception 'That message was already accepted by the provider.'
      using errcode = 'check_violation';
  end if;
  if outbox.status = 'processing' then
    raise exception 'That message is being sent right now.' using errcode = 'check_violation';
  end if;
  if outbox.status = 'cancelled' then
    raise exception 'That message was cancelled. Send it again instead of retrying it.'
      using errcode = 'check_violation';
  end if;

  -- Idempotent: a message already waiting its turn needs nothing, and repeating the command must not
  -- keep pushing audit noise.
  if outbox.status = 'pending' and outbox.available_at <= now() then
    return jsonb_build_object('changed', false, 'delivery_intent_id', p_delivery_intent_id,
      'outbox_status', outbox.status, 'available_at', outbox.available_at);
  end if;

  update public.communication_outbox_events
  set status = 'pending', available_at = now(), claimed_at = null, claim_token = null,
    last_error = null
  where id = outbox.id;

  update public.communication_delivery_intents
  set status = 'queued', failure_code = null, failure_message = null
  where id = intent.id;

  perform private.record_communication_message_event(
    p_organization_id => intent.organization_id,
    p_delivery_intent_id => intent.id,
    p_event_kind => 'administrative_intervention',
    p_attempt_number => outbox.attempt_count,
    p_reason_code => 'platform_owner_retry',
    p_reason_message => clean_reason,
    p_actor_kind => 'platform_owner',
    p_actor_email => clean_actor
  );

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_actor, 'communications.message_retried', 'communication_delivery_intent', intent.id::text,
    jsonb_build_object('organization_id', intent.organization_id, 'intent_status', intent.status,
      'outbox_status', outbox.status, 'failure_code', intent.failure_code,
      'attempt_count', outbox.attempt_count),
    jsonb_build_object('intent_status', 'queued', 'outbox_status', 'pending', 'reason', clean_reason)
  );

  return jsonb_build_object('changed', true, 'delivery_intent_id', intent.id,
    'outbox_status', 'pending', 'available_at', now());
end;
$$;

revoke all on function public.retry_communication_message(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.retry_communication_message(uuid, text, text) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 10. Cancel. Stops a message that should not go out and gives its reserved allowance back.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.cancel_communication_message(
  p_delivery_intent_id uuid,
  p_reason text,
  p_actor_email text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  outbox public.communication_outbox_events;
  intent public.communication_delivery_intents;
  clean_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  clean_actor text := nullif(btrim(coalesce(p_actor_email, '')), '');
begin
  if clean_actor is null then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if clean_reason is null or char_length(clean_reason) < 3 or char_length(clean_reason) > 1000 then
    raise exception 'A reason of 3 to 1000 characters is required.' using errcode = 'check_violation';
  end if;

  select * into outbox from public.communication_outbox_events
  where delivery_intent_id = p_delivery_intent_id for update;
  if outbox.id is null then
    raise exception 'That message was not found.' using errcode = 'no_data_found';
  end if;
  select * into intent from public.communication_delivery_intents
  where id = p_delivery_intent_id for update;

  if outbox.status = 'cancelled' then
    return jsonb_build_object('changed', false, 'delivery_intent_id', p_delivery_intent_id,
      'outbox_status', outbox.status);
  end if;
  if outbox.status = 'submitted' then
    raise exception 'That message was already accepted by the provider.'
      using errcode = 'check_violation';
  end if;
  if outbox.status = 'processing' then
    raise exception 'That message is being sent right now.' using errcode = 'check_violation';
  end if;

  update public.communication_outbox_events
  set status = 'cancelled', claimed_at = null, claim_token = null,
    last_error = 'Cancelled by the platform owner.'
  where id = outbox.id;

  update public.communication_delivery_intents
  set status = 'cancelled', provider_message_id = null, accepted_at = null,
    failure_code = 'cancelled_by_platform_owner',
    failure_message = 'Cancelled by the platform owner.'
  where id = intent.id;

  -- Give the held allowance back, the same way a released reservation does elsewhere.
  update public.communication_email_capacity_reservations
  set reservation_state = 'released', settled_at = now()
  where delivery_intent_id = intent.id
    and reservation_state in ('reserved', 'submission_unknown');

  perform private.record_communication_message_event(
    p_organization_id => intent.organization_id,
    p_delivery_intent_id => intent.id,
    p_event_kind => 'administrative_intervention',
    p_attempt_number => outbox.attempt_count,
    p_reason_code => 'platform_owner_cancel',
    p_reason_message => clean_reason,
    p_actor_kind => 'platform_owner',
    p_actor_email => clean_actor
  );

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_actor, 'communications.message_cancelled', 'communication_delivery_intent', intent.id::text,
    jsonb_build_object('organization_id', intent.organization_id, 'intent_status', intent.status,
      'outbox_status', outbox.status, 'failure_code', intent.failure_code,
      'attempt_count', outbox.attempt_count),
    jsonb_build_object('intent_status', 'cancelled', 'outbox_status', 'cancelled',
      'reason', clean_reason)
  );

  return jsonb_build_object('changed', true, 'delivery_intent_id', intent.id,
    'outbox_status', 'cancelled');
end;
$$;

revoke all on function public.cancel_communication_message(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.cancel_communication_message(uuid, text, text) to service_role;
