-- Fix a correctness bug found while building Stage 8-3's scale evidence: the SMS claim function
-- (public.claim_communication_sms_outbox_event, 20260919120000) declares `delivery_intent_id` as one of its
-- RETURNS TABLE output columns, which PL/pgSQL also exposes as an implicit variable of the same name in the
-- function body. Two of the function's internal lookups wrote a bare, unqualified `delivery_intent_id` on the
-- left side of a WHERE clause, which is ambiguous between that implicit variable and the joined table's own
-- `delivery_intent_id` column. Postgres refuses to guess and raises `column reference "delivery_intent_id" is
-- ambiguous`, so the claim function has thrown on this error on step 7 (the reservation-still-held check) for
-- every candidate that passed the earlier recipient/consent/sender/registration/account/quiet-hours checks --
-- i.e. on the normal, healthy path for essentially every real send. Every existing test exercised this
-- function's contract through a mocked TypeScript client or by calling finalize directly against an
-- already-processing row, so nothing had actually run the real SQL claim function past step 6 until this
-- session's direct-SQL load test did.
--
-- Fix: qualify both lookups against their table alias. No other behavior changes. Full function body restated
-- (only this migration ever defines it) so the fix is visible in one readable diff rather than a string patch.

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
    -- Fixed 2026-09-23: qualified against the table alias -- was a bare `delivery_intent_id`, ambiguous with
    -- this function's own RETURNS TABLE column of the same name (see migration header).
    select r.state into reservation_state
    from public.communication_sms_credit_reservations r
    where r.delivery_intent_id = candidate.delivery_intent_id;
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

    -- Fixed 2026-09-23: same ambiguity as step 7, against communication_sms_message_snapshots.
    select snap.* into snapshot
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = candidate.delivery_intent_id;

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
