-- Communications A2 / Stage 4B: the SMS side of the bounded delivery spine — a Twilio submission claim,
-- finalize and stale-claim quarantine that mirror the proven email worker functions.
--
-- Approved behavior (docs/communications-a2-implementation-plan.md §4B). The 4A enqueue command froze every
-- send (recipient, sender, body, segment estimate, retail rate) with its credit reservation and outbox row and
-- checked every gate AT ENQUEUE. This migration adds the AT-CLAIM half: a bounded competing-consumer claim that
-- rechecks the live gates that can change between enqueue and send (a customer STOP, a lost/changed number, an
-- organization or provider pause, quiet hours), hands the frozen row to the out-of-transaction Twilio worker,
-- and a finalize that records the single provider outcome under the claim token. One attempt is recorded before
-- the provider call; uncertain submissions are quarantined for Stage 8 reconciliation, never resent.
--
-- Postgres remains the sole owner of eligibility, retry timing and money. The TypeScript worker only performs the
-- one HTTP call this claim authorizes. Nothing sends live: Stage 4 stays dark until Stage 5 webhooks and a
-- country launch gate pass.
--
-- Mirrors: public.claim_communication_outbox_event() (email claim, 20260828022617),
--          public.finalize_communication_outbox_event() (20260824002355),
--          public.quarantine_stale_communication_claims() (20260824002727).
-- Reuses:  the worker lease + wake ledger (20260829030837), which are already keyed by worker name.

-- ---------------------------------------------------------------------------------------------------------------
-- Shared money helper: release a still-reserved SMS credit reservation back to the organization's balance.
-- Called when a queued send is cancelled at claim (STOP / dead number) or at finalize (definite provider
-- rejection). Releasing frees the purchased hold on the account and, by leaving 'reserved'/'submission_unknown',
-- also frees the promotional part that the enqueue command nets out of the live promotional balance.
-- A reservation that is already settled/released/unknown is left untouched (nothing to return here).
-- ---------------------------------------------------------------------------------------------------------------

create or replace function private.communication_sms_release_reservation(p_delivery_intent_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  reservation public.communication_sms_credit_reservations;
begin
  select * into reservation
  from public.communication_sms_credit_reservations
  where delivery_intent_id = p_delivery_intent_id
  for update;

  -- Only an active 'reserved' hold returns money. 'submission_unknown' keeps its hold pending reconciliation;
  -- 'settled'/'released' are already terminal.
  if not found or reservation.state <> 'reserved' then
    return;
  end if;

  update public.communication_sms_credit_accounts
  set reserved_balance_minor = reserved_balance_minor - reservation.reserved_purchased_minor,
      updated_at = now()
  where organization_id = reservation.organization_id;

  update public.communication_sms_credit_reservations
  set state = 'released', settled_at = now()
  where id = reservation.id;
end;
$$;

revoke all on function private.communication_sms_release_reservation(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Claim one SMS outbox row. Bounded SKIP LOCKED scan of the SMS-only partial index, live-gate rechecks, then the
-- atomic claim: mark the outbox 'processing' with a fresh token, the intent 'claimed', and record the 'started'
-- submission attempt so an attempt exists before the worker's provider call. Returns the frozen row plus the
-- Twilio routing identifiers the worker needs (the encrypted Restricted key is fetched and decrypted in the
-- worker, never here). Returns no row when nothing is claimable.
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.claim_communication_sms_outbox_event()
returns table (
  outbox_event_id uuid,
  delivery_intent_id uuid,
  organization_id uuid,
  twilio_account_id uuid,
  subaccount_sid text,
  messaging_service_sid text,
  claim_token uuid,
  attempt_number integer,
  recipient_phone text,
  sender_phone text,
  body text,
  encoding text,
  segment_count integer
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate record;
  recipient public.client_contact_methods;
  sender public.communication_sms_sender_identities;
  registration public.communication_sms_registrations;
  account public.communication_twilio_accounts;
  outbound record;
  latest_consent text;
  snapshot public.communication_sms_message_snapshots;
  reservation_state text;
  available timestamptz;
  new_claim_token uuid;
  new_attempt integer;
  hold_message text;
begin
  for candidate in
    select event.id as event_id, event.delivery_intent_id, event.attempt_count,
      intent.organization_id, intent.client_id, intent.client_contact_method_id,
      intent.recipient_phone, intent.sms_sender_identity_id
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.channel = 'sms' and event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    -- 1. Recipient still an active phone on this customer, unchanged from the frozen E.164 number.
    recipient := null;
    select method.* into recipient
    from public.client_contact_methods method
    join public.clients client
      on client.organization_id = method.organization_id and client.id = method.client_id
    where method.organization_id = candidate.organization_id
      and method.id = candidate.client_contact_method_id
      and method.client_id = candidate.client_id
      and method.kind = 'phone'
      and client.deleted_at is null
    for share of method, client;

    if recipient.id is null or ('+' || recipient.normalized_value) <> candidate.recipient_phone then
      perform private.communication_sms_release_reservation(candidate.delivery_intent_id);
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'recipient_no_longer_eligible',
        failure_message = 'The queued phone number is no longer active for this customer.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The queued phone number is no longer active for this customer.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 2. A customer STOP after enqueue is a global opt-out: cancel rather than send. Consent is derived from the
    --    append-only events; the governing event for the number is the most recent opt-in/opt-out (HELP never
    --    changes eligibility). A global opt-out therefore beats any earlier subject opt-in, which is exactly the
    --    STOP-racing-a-claim case. Subject scope was fully enforced at enqueue and cannot tighten afterwards.
    latest_consent := (
      select case when governing.event_kind = 'opt_out' then 'opted_out' else 'opted_in' end
      from public.communication_sms_consent_events governing
      where governing.organization_id = candidate.organization_id
        and governing.client_contact_method_id = candidate.client_contact_method_id
        and governing.event_kind in ('opt_in', 'opt_out')
      order by governing.occurred_at desc, governing.received_at desc, governing.id desc
      limit 1
    );
    if latest_consent is distinct from 'opted_in' then
      perform private.communication_sms_release_reservation(candidate.delivery_intent_id);
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'recipient_opted_out',
        failure_message = 'This customer opted out of text messages before this one was sent.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This customer opted out of text messages before this one was sent.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 3. Sending number: must still exist and be live. A released number is gone for good (cancel); any other
    --    not-ready state is transient (defer and re-check).
    sender := null;
    select s.* into sender
    from public.communication_sms_sender_identities s
    where s.organization_id = candidate.organization_id and s.id = candidate.sms_sender_identity_id
    for share of s;

    if sender.id is null or sender.lifecycle_state = 'released' then
      perform private.communication_sms_release_reservation(candidate.delivery_intent_id);
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'sms_sender_unavailable',
        failure_message = 'The number this text would have sent from is no longer available.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The number this text would have sent from is no longer available.'
      where id = candidate.event_id;
      continue;
    end if;

    if sender.lifecycle_state <> 'ready' or not sender.capable_sms
      or sender.registration_id is null or sender.country_code is null or sender.sender_type is null then
      update public.communication_delivery_intents
      set failure_code = 'sms_sender_not_ready',
        failure_message = 'This SMS number is not ready to send right now. UCRM will try again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '15 minutes',
        last_error = 'This SMS number is not ready to send right now. UCRM will try again.'
      where id = candidate.event_id;
      continue;
    end if;

    select r.* into registration
    from public.communication_sms_registrations r
    where r.organization_id = candidate.organization_id and r.id = sender.registration_id;
    if registration.id is null then
      update public.communication_delivery_intents
      set failure_code = 'sms_registration_unavailable',
        failure_message = 'This SMS number is not ready to send right now. UCRM will try again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '15 minutes',
        last_error = 'This SMS number is not ready to send right now. UCRM will try again.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 4. Readiness and holds in one read (effective mode/package, approved registration, and any active
    --    platform/organization/provider outbound hold). A pause defers, never cancels — inbound and STOP/START
    --    stay available through it, and a lifted pause re-runs every check here.
    select * into outbound
    from public.communication_sms_outbound_state(
      candidate.organization_id, sender.country_code, sender.sender_type, registration.use_case
    );
    if outbound.state <> 'ready' then
      hold_message := case when outbound.state = 'outbound_paused'
        then 'Outbound texting is paused for this organization. UCRM will try again when it resumes.'
        else 'This organization is not ready to send SMS right now. UCRM will try again.' end;
      update public.communication_delivery_intents
      set failure_code = 'sms_outbound_not_ready', failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '5 minutes', last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    -- 5. The Twilio subaccount and Messaging Service the worker sends through must be present and live.
    account := null;
    select a.* into account
    from public.communication_twilio_accounts a
    where a.organization_id = candidate.organization_id
    for share of a;
    if account.id is null or account.messaging_service_sid is null
      or account.lifecycle_state not in ('ready', 'restricted') then
      update public.communication_delivery_intents
      set failure_code = 'sms_provider_account_not_ready',
        failure_message = 'This organization''s texting service is not ready. UCRM will try again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '15 minutes',
        last_error = 'This organization''s texting service is not ready. UCRM will try again.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 6. Quiet hours: if now falls inside the platform window, reschedule to the window end instead of sending.
    available := public.communication_sms_quiet_hours_available_at(now());
    if available > now() then
      update public.communication_delivery_intents
      set failure_code = 'sms_quiet_hours',
        failure_message = 'This text is waiting for quiet hours to end before it goes out.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = available,
        last_error = 'This text is waiting for quiet hours to end before it goes out.'
      where id = candidate.event_id;
      continue;
    end if;

    -- 7. The credit reservation frozen at enqueue must still be holding funds; a released/settled reservation
    --    means this send has already been resolved and must not be sent again.
    select state into reservation_state
    from public.communication_sms_credit_reservations
    where delivery_intent_id = candidate.delivery_intent_id;
    if reservation_state is distinct from 'reserved' then
      update public.communication_delivery_intents
      set status = 'cancelled', failure_code = 'sms_reservation_not_held',
        failure_message = 'This text no longer has a held balance and was not sent.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This text no longer has a held balance and was not sent.'
      where id = candidate.event_id;
      continue;
    end if;

    select * into snapshot
    from public.communication_sms_message_snapshots
    where delivery_intent_id = candidate.delivery_intent_id;

    -- 8. Claim: mark the outbox processing under a fresh token, mark the intent claimed, and record the 'started'
    --    attempt so one attempt exists before the worker's provider call. The attempt number equals the new
    --    outbox attempt_count, so retries append distinct attempt rows.
    new_claim_token := gen_random_uuid();
    new_attempt := candidate.attempt_count + 1;

    update public.communication_outbox_events
    set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = new_attempt, last_error = null
    where id = candidate.event_id;
    update public.communication_delivery_intents
    set status = 'claimed', failure_code = null, failure_message = null
    where id = candidate.delivery_intent_id;
    insert into public.communication_sms_submission_attempts (
      organization_id, delivery_intent_id, attempt_number, claim_token, provider, outcome
    ) values (
      candidate.organization_id, candidate.delivery_intent_id, new_attempt, new_claim_token, 'twilio', 'started'
    );

    return query select candidate.event_id, candidate.delivery_intent_id, candidate.organization_id,
      account.id, account.subaccount_sid, account.messaging_service_sid, new_claim_token, new_attempt,
      candidate.recipient_phone, sender.phone_number, snapshot.body, snapshot.encoding, snapshot.segment_count;
    return;
  end loop;
end;
$$;

revoke all on function public.claim_communication_sms_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_sms_outbox_event() to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Finalize one claimed SMS submission. Records the single provider outcome under the claim token: accepted
-- (submitted), a proven pre-submission transient failure (retry with backoff), a definite rejection (cancelled,
-- reservation released), or an ambiguous outcome (submission_unknown, funds held and a reconciliation item
-- opened). A lost RPC response is idempotent: only the exact lease that finalized the row may re-read its result.
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.finalize_communication_sms_outbox_event(
  target_outbox_event_id uuid,
  target_claim_token uuid,
  target_outcome text,
  target_provider_message_id text default null,
  target_failure_code text default null,
  target_failure_message text default null
)
returns table (outbox_status text, intent_status text, attempt_count integer, available_at timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed_event public.communication_outbox_events;
  next_available_at timestamptz;
begin
  if target_outcome not in ('submitted', 'retry', 'submission_unknown', 'cancelled') then
    raise exception 'The SMS outcome is invalid.' using errcode = 'check_violation';
  end if;

  select * into claimed_event
  from public.communication_outbox_events
  where id = target_outbox_event_id
  for update;

  if not found then
    raise exception 'The SMS outbox event does not exist.' using errcode = 'no_data_found';
  end if;
  if claimed_event.channel <> 'sms' then
    raise exception 'This is not an SMS outbox event.' using errcode = 'check_violation';
  end if;

  -- Idempotent replay of a lost response: return the committed result only for the exact finalizing lease.
  if claimed_event.status <> 'processing' then
    if claimed_event.finalized_claim_token is distinct from target_claim_token then
      raise exception 'The SMS claim is no longer current.' using errcode = 'object_not_in_prerequisite_state';
    end if;
    return query
    select claimed_event.status, intent.status, claimed_event.attempt_count, claimed_event.available_at
    from public.communication_delivery_intents intent
    where intent.id = claimed_event.delivery_intent_id;
    return;
  end if;

  if claimed_event.claim_token is distinct from target_claim_token then
    raise exception 'The SMS claim token is invalid.' using errcode = 'insufficient_privilege';
  end if;

  if target_outcome = 'submitted' then
    if nullif(trim(target_provider_message_id), '') is null then
      raise exception 'A submitted SMS requires a provider message identifier.' using errcode = 'not_null_violation';
    end if;

    update public.communication_delivery_intents
    set status = 'submitted', provider_message_id = trim(target_provider_message_id), accepted_at = now(),
      failure_code = null, failure_message = null
    where id = claimed_event.delivery_intent_id;

    update public.communication_sms_submission_attempts
    set outcome = 'accepted', provider_message_id = trim(target_provider_message_id), finished_at = now()
    where delivery_intent_id = claimed_event.delivery_intent_id and claim_token = target_claim_token;

    -- The reservation stays 'reserved'. Settlement against the provider's billed price is Stage 8 work.
    update public.communication_outbox_events
    set status = 'submitted', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = null
    where id = claimed_event.id;

  elsif target_outcome = 'retry' then
    next_available_at := case claimed_event.attempt_count
      when 1 then now() + interval '5 minutes'
      when 2 then now() + interval '30 minutes'
      when 3 then now() + interval '2 hours'
      when 4 then now() + interval '8 hours'
      when 5 then now() + interval '24 hours'
      else 'infinity'::timestamptz
    end;

    update public.communication_delivery_intents
    set status = 'failed', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;

    update public.communication_sms_submission_attempts
    set outcome = 'rejected', error_code = nullif(trim(target_failure_code), ''), finished_at = now()
    where delivery_intent_id = claimed_event.delivery_intent_id and claim_token = target_claim_token;

    -- Funds stay reserved for the retry.
    update public.communication_outbox_events
    set status = 'failed', available_at = next_available_at, claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;

  elsif target_outcome = 'cancelled' then
    perform private.communication_sms_release_reservation(claimed_event.delivery_intent_id);

    update public.communication_delivery_intents
    set status = 'cancelled', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;

    update public.communication_sms_submission_attempts
    set outcome = 'rejected', error_code = nullif(trim(target_failure_code), ''), finished_at = now()
    where delivery_intent_id = claimed_event.delivery_intent_id and claim_token = target_claim_token;

    update public.communication_outbox_events
    set status = 'cancelled', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;

  else
    -- submission_unknown: the provider may or may not have accepted it. Hold the funds, quarantine for
    -- reconciliation (Stage 8), and never resend from here.
    update public.communication_delivery_intents
    set status = 'submission_unknown', provider_message_id = nullif(trim(target_provider_message_id), ''),
      accepted_at = null, failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;

    update public.communication_sms_submission_attempts
    set outcome = 'submission_unknown', error_code = nullif(trim(target_failure_code), ''),
      provider_message_id = nullif(trim(target_provider_message_id), ''), finished_at = now()
    where delivery_intent_id = claimed_event.delivery_intent_id and claim_token = target_claim_token;

    update public.communication_sms_credit_reservations
    set state = 'submission_unknown', settled_at = now()
    where delivery_intent_id = claimed_event.delivery_intent_id and state = 'reserved';

    insert into public.communication_sms_reconciliation_items (
      organization_id, delivery_intent_id, provider_message_id, reason, last_error
    ) values (
      claimed_event.organization_id, claimed_event.delivery_intent_id,
      nullif(trim(target_provider_message_id), ''), 'submission_unknown',
      nullif(trim(target_failure_message), '')
    )
    on conflict (delivery_intent_id, reason) where status in ('open', 'processing', 'failed')
      and delivery_intent_id is not null do nothing;

    update public.communication_outbox_events
    set status = 'submission_unknown', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;
  end if;

  return query
  select event.status, intent.status, event.attempt_count, event.available_at
  from public.communication_outbox_events event
  join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
  where event.id = claimed_event.id;
end;
$$;

revoke all on function public.finalize_communication_sms_outbox_event(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_communication_sms_outbox_event(uuid, uuid, text, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Stale-claim quarantine for SMS. A worker can vanish after the Twilio request left UCRM, so an expired lease is
-- never retried: quarantine it as submission_unknown, hold its funds, mark its 'started' attempt unknown, and
-- open a reconciliation item. Bounded batches with SKIP LOCKED, mirroring the email quarantine.
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.quarantine_stale_communication_sms_claims(
  batch_size integer default 50,
  stale_after interval default interval '15 minutes'
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quarantined_count integer;
begin
  if batch_size < 1 or batch_size > 100 then
    raise exception 'The stale SMS batch is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if stale_after < interval '1 minute' or stale_after > interval '1 day' then
    raise exception 'The stale SMS threshold is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  with stale as (
    select id, delivery_intent_id, organization_id, claim_token
    from public.communication_outbox_events
    where channel = 'sms' and status = 'processing' and claimed_at <= now() - stale_after
    order by claimed_at, id
    limit batch_size
    for update skip locked
  ), quarantined as (
    update public.communication_outbox_events event
    set status = 'submission_unknown', finalized_claim_token = event.claim_token,
      claimed_at = null, claim_token = null,
      last_error = 'The worker lease expired before its provider outcome was recorded.'
    from stale
    where event.id = stale.id
    returning event.delivery_intent_id, stale.organization_id, stale.claim_token
  ), updated_intents as (
    update public.communication_delivery_intents intent
    set status = 'submission_unknown', failure_code = 'worker_lease_expired',
      failure_message = 'The worker lease expired before its provider outcome was recorded.'
    from quarantined
    where intent.id = quarantined.delivery_intent_id
    returning intent.id
  ), updated_attempts as (
    update public.communication_sms_submission_attempts attempt
    set outcome = 'submission_unknown', error_code = 'worker_lease_expired', finished_at = now()
    from quarantined
    where attempt.delivery_intent_id = quarantined.delivery_intent_id
      and attempt.claim_token = quarantined.claim_token
      and attempt.outcome = 'started'
    returning attempt.id
  ), held_reservations as (
    update public.communication_sms_credit_reservations reservation
    set state = 'submission_unknown', settled_at = now()
    from quarantined
    where reservation.delivery_intent_id = quarantined.delivery_intent_id
      and reservation.state = 'reserved'
    returning reservation.id
  ), opened_items as (
    insert into public.communication_sms_reconciliation_items (
      organization_id, delivery_intent_id, reason, last_error
    )
    select quarantined.organization_id, quarantined.delivery_intent_id, 'submission_unknown',
      'The worker lease expired before its provider outcome was recorded.'
    from quarantined
    on conflict (delivery_intent_id, reason) where status in ('open', 'processing', 'failed')
      and delivery_intent_id is not null do nothing
    returning id
  )
  select count(*)::integer into quarantined_count from updated_intents;

  return quarantined_count;
end;
$$;

revoke all on function public.quarantine_stale_communication_sms_claims(integer, interval)
  from public, anon, authenticated;
grant execute on function public.quarantine_stale_communication_sms_claims(integer, interval)
  to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Scope the shared stale-claim quarantine to email only. Now that SMS 'processing' rows exist in the same outbox,
-- the email worker's quarantine must not touch them (it would mark them submission_unknown without releasing or
-- holding their SMS reservation or opening a reconciliation item). The SMS worker's own quarantine above owns SMS
-- rows. Rewritten from the live definition so any prior fix stays intact; only the channel scope changes.
-- ---------------------------------------------------------------------------------------------------------------

do $migration$
declare
  function_sql text;
  updated_sql text;
begin
  function_sql := pg_get_functiondef('public.quarantine_stale_communication_claims(integer, interval)'::regprocedure);
  updated_sql := replace(
    function_sql,
    $$where status = 'processing' and claimed_at <= now() - stale_after$$,
    $$where channel = 'email' and status = 'processing' and claimed_at <= now() - stale_after$$
  );
  if updated_sql = function_sql then
    raise exception 'Could not add email channel isolation to quarantine_stale_communication_claims().';
  end if;
  execute updated_sql;
end;
$migration$;
