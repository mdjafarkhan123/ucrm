-- Communications Part 7.6a follow-up: give the message history a monotonic tiebreaker.
--
-- `occurred_at` is a wall clock, and inside one transaction now() does not move. Two events on the
-- same message that share a timestamp were then ordered by a random uuid -- which decides both what
-- the timeline shows last and, more importantly, which row the deferral collapse looks at. An
-- identity column removes the guess: insertion order is the tiebreaker, always.

alter table public.communication_message_events
  add column seq bigint generated always as identity;

alter table public.communication_message_events
  add constraint communication_message_events_seq_key unique (seq);

drop index if exists public.communication_message_events_timeline_idx;
drop index if exists public.communication_message_events_latest_idx;

create index communication_message_events_timeline_idx
  on public.communication_message_events (delivery_intent_id, occurred_at, seq);
create index communication_message_events_latest_idx
  on public.communication_message_events (delivery_intent_id, seq desc);

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
    order by seq desc
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

-- The append-only guard must also refuse a rewritten sequence number.
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
    or new.seq <> old.seq
    or new.delivery_intent_id <> old.delivery_intent_id
    or new.event_kind <> old.event_kind
    or new.occurred_at <> old.occurred_at then
    raise exception 'Message history cannot be rewritten.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- The timeline read orders by the same pair the index does.
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
        'seq', history.seq,
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
      ) order by history.occurred_at, history.seq)
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
