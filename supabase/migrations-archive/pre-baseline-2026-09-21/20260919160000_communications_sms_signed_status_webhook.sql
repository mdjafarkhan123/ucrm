-- Communications A2 Stage 5A: signed Twilio SMS status callbacks -- the SMS-side projection.
--
-- The callback spine already carries a `channel` discriminator added by the SMS channel-safe foundation
-- (provider_channel_check ties email<->brevo and sms<->twilio), and the email drain
-- (process_communication_provider_callbacks) is already scoped to channel='email' with its own quote-event,
-- suppression, reputation and quarantine behavior. This migration therefore LEAVES THE EMAIL DRAIN
-- UNTOUCHED. It only:
--   1. admits the SMS vocabularies into the shared normalized_kind and delivery_outcome checks; and
--   2. adds a channel='sms'-scoped projection that maps Twilio MessageStatus onto delivery_outcome, with two
--      rules from the plan -- a confirmed terminal outcome is never regressed by a later non-terminal or
--      same-class event, and conflicting terminal evidence (delivered vs failed/undelivered for one message)
--      is not guessed but becomes 'sms_needs_checking' for an operator to resolve.
--
-- Every SMS value is 'sms_'-namespaced, so email reputation windows that filter on delivery_outcome or
-- normalized_kind keep counting exactly what they counted before. Delivery outcome lives on the
-- delivery_outcome axis; the submission `status` (submitted/failed/...) stays owned by the Stage 4 worker.

-- ---------------------------------------------------------------------------------------------------
-- 1. Admit SMS into the shared callback vocabularies.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_provider_callback_events
  drop constraint if exists communication_provider_callback_events_normalized_kind_check,
  add constraint communication_provider_callback_events_normalized_kind_check
    check (normalized_kind in (
      'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked',
      'unsubscribed', 'opened', 'clicked', 'other',
      'sms_delivered', 'sms_sent', 'sms_undelivered', 'sms_failed'
    ));

alter table public.communication_delivery_intents
  drop constraint if exists communication_delivery_intents_delivery_outcome_check,
  add constraint communication_delivery_intents_delivery_outcome_check
    check (delivery_outcome in (
      'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked', 'unsubscribed',
      'sms_delivered', 'sms_undelivered', 'sms_failed', 'sms_needs_checking'
    ));

-- A delivery_outcome change fires private.communication_delivery_outcome_history, which records a message
-- timeline event whose event_kind is the outcome verbatim. Admit the SMS outcomes so an SMS delivered/failed
-- projection can write its timeline entry (email outcomes are already listed). Existing values are preserved.
alter table public.communication_message_events
  drop constraint if exists communication_message_events_event_kind_check,
  add constraint communication_message_events_event_kind_check
    check (event_kind in (
      'queued', 'claimed', 'deferred', 'held', 'cancelled', 'sent', 'send_failed', 'submission_unknown',
      'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'provider_deferred', 'blocked', 'unsubscribed',
      'replied', 'resent', 'administrative_intervention',
      'sms_delivered', 'sms_undelivered', 'sms_failed', 'sms_needs_checking'
    ));

-- ---------------------------------------------------------------------------------------------------
-- 2. The SMS status projection. Twilio MessageStatus -> delivery_outcome, with terminal protection and
--    conflicting-terminal -> needs-checking. Bounded, idempotent (processed_at gate), SKIP LOCKED, and
--    channel='sms'-scoped so it rides the sms partial index and never claims an email (brevo) row. Per-row
--    error isolation mirrors the email drain so one poison callback cannot wedge the batch.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.process_communication_sms_provider_callbacks(batch_size integer default 500)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate record;
  norm text;
  current_outcome text;
  new_is_success boolean;
  new_is_failure boolean;
  cur_is_success boolean;
  cur_is_failure boolean;
  next_outcome text;
  processed_count integer := 0;
  max_processing_attempts constant integer := 5;
begin
  if batch_size < 1 or batch_size > 2000 then
    raise exception 'The callback batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select
      cb.id,
      cb.event_kind,
      cb.occurred_at,
      cb.received_at,
      cb.delivery_intent_id,
      intent.organization_id,
      intent.delivery_outcome as current_outcome
    from public.communication_provider_callback_events cb
    left join public.communication_delivery_intents intent on intent.id = cb.delivery_intent_id
    where cb.channel = 'sms' and cb.processed_at is null
    order by cb.received_at, cb.id
    limit batch_size
    for update of cb skip locked
  loop
    norm := case lower(trim(candidate.event_kind))
      when 'delivered' then 'sms_delivered'
      when 'sent' then 'sms_sent'
      when 'undelivered' then 'sms_undelivered'
      when 'failed' then 'sms_failed'
      else 'other'
    end;

    begin
      -- Unresolved (a status for a message we never sent, or one that arrived before its intent): record it
      -- processed with a null organization so nothing downstream counts it, and move on.
      if candidate.delivery_intent_id is null or candidate.organization_id is null then
        update public.communication_provider_callback_events
        set processed_at = now(), normalized_kind = norm
        where id = candidate.id;
        processed_count := processed_count + 1;
        continue;
      end if;

      -- Only terminal delivery evidence moves the outcome axis. 'sms_sent' is pre-delivery progress and is
      -- recorded (normalized_kind) but never written as a delivery outcome.
      if norm in ('sms_delivered', 'sms_undelivered', 'sms_failed') then
        current_outcome := candidate.current_outcome;
        new_is_success := norm = 'sms_delivered';
        new_is_failure := norm in ('sms_undelivered', 'sms_failed');
        cur_is_success := current_outcome = 'sms_delivered';
        cur_is_failure := current_outcome in ('sms_undelivered', 'sms_failed');
        next_outcome := null;

        if current_outcome is null
          or current_outcome not in ('sms_delivered', 'sms_undelivered', 'sms_failed', 'sms_needs_checking') then
          -- First SMS terminal word for this intent (or the column held a non-SMS value): take it.
          next_outcome := norm;
        elsif current_outcome = 'sms_needs_checking' then
          -- Already flagged for an operator; never regress out of it.
          next_outcome := null;
        elsif (cur_is_success and new_is_failure) or (cur_is_failure and new_is_success) then
          -- Success vs failure for the same message: do not guess which is true.
          next_outcome := 'sms_needs_checking';
        else
          -- Same-class terminal (e.g. undelivered then failed, or a duplicate delivered): first word stands.
          next_outcome := null;
        end if;

        if next_outcome is not null then
          update public.communication_delivery_intents
          set delivery_outcome = next_outcome,
            delivery_outcome_at = coalesce(candidate.occurred_at, candidate.received_at),
            delivery_outcome_detail = nullif(trim(candidate.event_kind), '')
          where id = candidate.delivery_intent_id;
        end if;
      end if;

      update public.communication_provider_callback_events
      set processed_at = now(), normalized_kind = norm, organization_id = candidate.organization_id
      where id = candidate.id;
      processed_count := processed_count + 1;
    exception
      when others then
        -- Quarantine a poison row after a few attempts so it can never wedge the batch; mirrors the email drain.
        update public.communication_provider_callback_events
        set processing_attempts = coalesce(processing_attempts, 0) + 1,
          processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
          normalized_kind = coalesce(normalized_kind, norm),
          processed_at = case
            when coalesce(processing_attempts, 0) + 1 >= max_processing_attempts then now()
            else processed_at
          end
        where id = candidate.id;
    end;
  end loop;

  return processed_count;
end;
$$;

revoke all on function public.process_communication_sms_provider_callbacks(integer) from public, anon, authenticated;
grant execute on function public.process_communication_sms_provider_callbacks(integer) to service_role;

comment on function public.process_communication_sms_provider_callbacks(integer) is
  'Projects durable Twilio SMS status callbacks (channel=sms) onto delivery_outcome: terminal outcomes are never regressed, and a delivered vs failed/undelivered conflict becomes sms_needs_checking.';
