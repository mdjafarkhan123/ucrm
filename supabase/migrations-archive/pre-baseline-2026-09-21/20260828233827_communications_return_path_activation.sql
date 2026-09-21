-- Communications A1 (R1): activate the return path.
--
-- Outbound is proven live. This migration closes the loop on what comes back from Brevo -- unsubscribes,
-- complaints, and poison callbacks -- so the system stops sending where it must and an operator can see
-- the processor's health.
--
-- docs/contractor-email-contract.md
--   § Preferences, consent, and suppressions
--     "A complaint immediately suppresses non-security mail from that organization. ... UCRM owns an
--      auditable suppression record and reconciles it with Brevo."
--
-- Four changes, all in the database layer:
--   1. `unsubscribe` becomes a suppression reason of its own.
--   2. A Brevo `unsubscribed` callback now opens a suppression (reason `unsubscribe`), and every callback
--      is processed in its own subtransaction so one poison row can never wedge the batch.
--   3. The outbox claim's suppression scope is corrected: hard bounce AND complaint block every class;
--      unsubscribe blocks optional mail only.
--   4. A Platform-Owner read exposes callback-processing health (oldest unprocessed, last cron success by
--      job name, parked poison rows) and provider blocking.

-- ---------------------------------------------------------------------------------------------------
-- 1. `unsubscribe` is a first-class suppression reason.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_email_suppressions
  drop constraint communication_email_suppressions_reason_check;
alter table public.communication_email_suppressions
  add constraint communication_email_suppressions_reason_check
  check (reason in ('complaint', 'hard_bounce', 'unsubscribe'));

-- ---------------------------------------------------------------------------------------------------
-- 2. Minimum poison-message state on the raw callback sink. Not a dead-letter queue -- an auditable
--    attempt count and last error on the row itself. A row that keeps failing is parked (marked
--    processed with its error preserved) after a small number of attempts.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_provider_callback_events
  add column processing_attempts integer not null default 0,
  add column processing_error text;

-- ---------------------------------------------------------------------------------------------------
-- 3. Provider-blocking and adverse-outcome reads. Two small partial indexes so the owner health read
--    below never seq-scans: one over the (few) live suppressions by reason, one over the (few) adverse
--    delivery outcomes by time.
-- ---------------------------------------------------------------------------------------------------

create index communication_email_suppressions_active_reason_idx
  on public.communication_email_suppressions (reason)
  where released_at is null;

create index communication_delivery_intents_adverse_outcome_idx
  on public.communication_delivery_intents (delivery_outcome_at desc)
  where delivery_outcome in ('blocked', 'hard_bounce', 'complaint', 'unsubscribed');

-- ---------------------------------------------------------------------------------------------------
-- 4. The processor. Same projection and suppression logic as before, now with an unsubscribe
--    suppression and per-row fault isolation. The body outside the subtransaction and the unsubscribe
--    branch is migration 20260906200000's definition unchanged.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.process_communication_provider_callbacks(batch_size integer default 500)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate record;
  norm text;
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
      cb.processing_attempts,
      cb.delivery_intent_id,
      intent.organization_id,
      intent.recipient_email,
      intent.delivery_outcome as current_outcome
    from public.communication_provider_callback_events cb
    left join public.communication_delivery_intents intent on intent.id = cb.delivery_intent_id
    where cb.processed_at is null
    order by cb.received_at, cb.id
    limit batch_size
    for update of cb skip locked
  loop
    norm := case lower(trim(candidate.event_kind))
      when 'delivered' then 'delivered'
      when 'soft_bounce' then 'soft_bounce'
      when 'hard_bounce' then 'hard_bounce'
      when 'invalid_email' then 'hard_bounce'
      when 'blocked' then 'blocked'
      when 'spam' then 'complaint'
      when 'complaint' then 'complaint'
      when 'deferred' then 'deferred'
      when 'unsubscribed' then 'unsubscribed'
      when 'list_addition' then 'other'
      when 'opened' then 'opened'
      when 'unique_opened' then 'opened'
      when 'click' then 'clicked'
      when 'proxy_open' then 'opened'
      else 'other'
    end;

    -- Each callback is handled in its own subtransaction. A single malformed or conflicting event can
    -- never abort the batch: on failure the row records the error, counts the attempt, is retried on
    -- later runs, and is parked once it has failed max_processing_attempts times. This is the minimum
    -- poison guard -- an auditable column, not a separate dead-letter queue.
    begin
      -- No resolved intent (a callback with no ucrm tag, or one that arrived before its intent): mark it
      -- processed so it stops being claimed, but leave its organization unresolved.
      if candidate.delivery_intent_id is null or candidate.organization_id is null then
        update public.communication_provider_callback_events
        set processed_at = now(), normalized_kind = norm
        where id = candidate.id;
        processed_count := processed_count + 1;
        continue;
      end if;

      -- Latest provider word wins, except a terminal outcome (hard bounce / complaint) is only ever
      -- replaced by another terminal outcome.
      if norm in ('delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked', 'unsubscribed') then
        update public.communication_delivery_intents
        set delivery_outcome = norm,
          delivery_outcome_at = coalesce(candidate.occurred_at, candidate.received_at),
          delivery_outcome_detail = nullif(trim(candidate.event_kind), '')
        where id = candidate.delivery_intent_id
          and (
            delivery_outcome is null
            or delivery_outcome not in ('hard_bounce', 'complaint')
            or norm in ('hard_bounce', 'complaint')
          );
      end if;

      -- Complaint and hard bounce open an auditable suppression that blocks every class. A Brevo
      -- unsubscribe opens one too, under its own reason, so the outbox claim can scope it to optional
      -- mail only. A row already live for this (organization, address, reason) keeps its first evidence.
      if norm in ('complaint', 'hard_bounce') then
        insert into public.communication_email_suppressions (
          organization_id, recipient_email, reason, source, source_callback_event_id,
          first_delivery_intent_id, evidence
        ) values (
          candidate.organization_id, candidate.recipient_email, norm, 'provider_callback', candidate.id,
          candidate.delivery_intent_id,
          jsonb_build_object(
            'event_kind', candidate.event_kind,
            'occurred_at', candidate.occurred_at,
            'received_at', candidate.received_at
          )
        )
        on conflict (organization_id, recipient_email, reason) where released_at is null
        do nothing;
      elsif norm = 'unsubscribed' then
        insert into public.communication_email_suppressions (
          organization_id, recipient_email, reason, source, source_callback_event_id,
          first_delivery_intent_id, evidence
        ) values (
          candidate.organization_id, candidate.recipient_email, 'unsubscribe', 'provider_callback',
          candidate.id, candidate.delivery_intent_id,
          jsonb_build_object(
            'event_kind', candidate.event_kind,
            'occurred_at', candidate.occurred_at,
            'received_at', candidate.received_at
          )
        )
        on conflict (organization_id, recipient_email, reason) where released_at is null
        do nothing;
      end if;

      -- An adverse event is the only thing that can worsen a reputation rate, so it -- and nothing
      -- else -- asks for a re-evaluation.
      if norm in ('complaint', 'hard_bounce', 'unsubscribed') then
        insert into public.communication_email_reputation_state (organization_id, evaluation_requested_at)
        values (candidate.organization_id, now())
        on conflict (organization_id) do update
        set evaluation_requested_at = excluded.evaluation_requested_at;
      end if;

      update public.communication_provider_callback_events
      set processed_at = now(), normalized_kind = norm, organization_id = candidate.organization_id
      where id = candidate.id;
      processed_count := processed_count + 1;
    exception
      when others then
        -- The subtransaction rolled back every change above for this row. Record why, count the attempt,
        -- and park the row (mark it processed, error preserved) once it has exhausted its retries so it
        -- can never wedge the queue. A parked row is visible in the owner health read.
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

revoke all on function public.process_communication_provider_callbacks(integer) from public, anon, authenticated;
grant execute on function public.process_communication_provider_callbacks(integer) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. The outbox claim. Suppression scope corrected: hard bounce and complaint block every class;
--    unsubscribe blocks optional mail only. This is the live definition (migrations 7.3/7.4/7.5/8.1/8.2)
--    verbatim except for the suppression predicate in the recheck block.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.claim_communication_outbox_event()
returns table (
  outbox_event_id uuid, delivery_intent_id uuid, claim_token uuid, recipient_email text, subject text,
  html_content text, text_content text, logical_send_key text, sender_id uuid, sender_email text,
  sender_name text, reply_to_email text, reply_to_name text
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  candidate record;
  current_recipient public.client_contact_methods;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  active_allowance record;
  allowance_limit_state text;
  allowance_limit_value integer;
  accepted_recipient_count integer;
  reserved_recipient_count integer;
  new_claim_token uuid;
  alias public.communication_reply_aliases;
  alias_domain public.communication_email_domains;
  holding_pause public.communication_email_sending_pauses%rowtype;
  hold_code text;
  hold_message text;
  today_start timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  warmup_ceiling integer;
  warmup_used_today integer;
  short_term_max integer;
  short_term_window integer;
  short_term_used integer;
  short_term_oldest_at timestamptz;
  short_term_retry_at timestamptz;
  provider_capacity integer;
  provider_reserve_percent integer;
  provider_reserve integer;
  provider_effective_cap integer;
  current_period_start timestamptz := date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
  platform_accepted bigint;
  platform_reserved bigint;
begin
  -- Part 7.3: an account-wide emergency pause stops the queue outright. The worker claims nothing and
  -- tries again later; queued rows keep their state and are re-checked in full when the pause lifts.
  if exists (
    select 1 from public.communication_email_sending_pauses
    where scope = 'platform' and released_at is null
  ) then
    return;
  end if;

  for candidate in
    select
      event.id as event_id,
      event.delivery_intent_id,
      intent.organization_id,
      intent.client_id,
      intent.client_contact_method_id,
      intent.recipient_email,
      intent.subject,
      intent.html_content,
      intent.text_content,
      intent.logical_send_key,
      intent.send_kind,
      intent.allowance_class,
      intent.retry_class,
      intent.expires_at,
      intent.sender_id,
      intent.reply_alias_id,
      intent.created_by
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    -- Part 8.2: the message's own clock, checked before anything else. Past its deadline nothing
    -- downstream matters -- not the tenant's state, not the recipient's, not capacity -- so this is both
    -- the cheapest check and the only one that must not be skipped by an earlier hold.
    if candidate.expires_at <= now() then
      hold_message := case candidate.retry_class
        when 'payment_receipt' then
          'This receipt could not be sent within 72 hours, so UCRM cancelled it. Send it again once sending is working.'
        when 'appointment_reminder' then
          'This reminder was not sent before its appointment window passed, so UCRM cancelled it.'
        when 'optional_followup' then
          'This follow-up passed its send window before it could go out, so UCRM cancelled it.'
        else
          'This message could not be sent within 24 hours, so UCRM cancelled it. Send it again once sending is working.'
      end;
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'retry_deadline_passed', failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null, last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    -- Part 8.1: a suspended organization, and one inside its recoverable closure window, send no
    -- contractor mail at all. The message is held, never cancelled -- reactivation and closure restore
    -- both re-run every check in this loop from scratch, and 8.2's per-class deadlines above, not this
    -- branch, decide what has grown too stale to release.
    --
    -- Backoff is an hour rather than the pause path's five minutes because suspension and closure are
    -- resolved on a human clock. A short retry would keep a stopped tenant's whole backlog cycling
    -- through the fifty-row candidate window ahead of tenants that can actually send.
    hold_code := null;
    hold_message := null;

    if exists (
      select 1 from public.organizations org
      where org.id = candidate.organization_id
        and org.lifecycle_status = 'suspended'
    ) then
      hold_code := 'organization_suspended';
      hold_message := 'Sending is suspended for this organization. UCRM will retry once it is reactivated.';
    elsif exists (
      -- Matches organization_closure_records_one_open_idx, the partial unique index on the open window.
      select 1 from public.organization_closure_records closure
      where closure.organization_id = candidate.organization_id
        and closure.status in ('pending_closure', 'purge_in_progress')
    ) then
      hold_code := 'organization_closing';
      hold_message := 'This organization is closing. UCRM will retry if the closure is reversed.';
    end if;

    if hold_code is not null then
      update public.communication_delivery_intents
      set failure_code = hold_code, failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      -- Never sleep past the deadline: the message must come back around while there is still time to
      -- send it, and if reactivation never comes it must come back to be cancelled on its own clock.
      set available_at = least(now() + interval '1 hour', candidate.expires_at), last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    current_recipient := null;
    select method.* into current_recipient
    from public.client_contact_methods method
    where method.organization_id = candidate.organization_id
      and method.id = candidate.client_contact_method_id
    for share;

    if current_recipient.id is null
      or current_recipient.client_id <> candidate.client_id
      or current_recipient.kind <> 'email'
      or current_recipient.normalized_value <> candidate.recipient_email then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_no_longer_eligible',
        failure_message = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.event_id;
      continue;
    end if;

    -- Part 7.1 / A1(R1): suppression recheck. Fail-closed and never retried -- a suppressed address is
    -- cleared by a person (7.2) or renewed consent, not by waiting. A hard bounce and a complaint block
    -- every class; an unsubscribe blocks optional mail only, so a requested quote, invoice, receipt,
    -- security notice, or direct reply still goes out.
    if exists (
      select 1
      from public.communication_email_suppressions suppression
      where suppression.organization_id = candidate.organization_id
        and suppression.recipient_email = candidate.recipient_email
        and suppression.released_at is null
        and (
          suppression.reason in ('hard_bounce', 'complaint')
          or (suppression.reason = 'unsubscribe' and candidate.allowance_class = 'optional')
        )
    ) then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_suppressed',
        failure_message = 'This recipient address is on the organization suppression list.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This recipient address is on the organization suppression list.'
      where id = candidate.event_id;
      continue;
    end if;

    -- Parts 7.3 and 7.4: an organization pause holds this tenant's mail -- deferred, not cancelled --
    -- and re-checked from scratch on every retry. A manual freeze holds every class; the automatic
    -- reputation pause holds optional mail only, so essential email keeps flowing.
    holding_pause := null;
    select pause.* into holding_pause
    from public.communication_email_sending_pauses pause
    where pause.scope = 'organization'
      and pause.organization_id = candidate.organization_id
      and pause.released_at is null
      and (pause.applies_to = 'all' or candidate.allowance_class = 'optional')
    order by case when pause.applies_to = 'all' then 0 else 1 end
    limit 1;

    if holding_pause.id is not null then
      if holding_pause.source = 'auto_reputation' then
        hold_code := 'sending_paused_reputation';
        hold_message := 'Optional email is paused while this organization''s delivery reputation is reviewed.';
      else
        hold_code := 'sending_paused_organization';
        hold_message := 'Sending for this organization is paused. UCRM will retry when it resumes.';
      end if;
      update public.communication_delivery_intents
      set failure_code = hold_code, failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '5 minutes', candidate.expires_at), last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    selected_sender := null;
    if candidate.sender_id is not null then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id and sender.id = candidate.sender_id
      for share;
    elsif candidate.send_kind = 'automated' then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id
        and sender.is_organization_default and sender.lifecycle_state <> 'removed'
      order by sender.created_at, sender.id limit 1 for share;
    end if;

    if selected_sender.id is null then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    assigned_member_status := null;
    if selected_sender.assigned_user_id is not null then
      select member.status into assigned_member_status from public.organization_members member
      where member.organization_id = selected_sender.organization_id and member.user_id = selected_sender.assigned_user_id
      for share;
    end if;
    sender_domain := null;
    select domain.* into sender_domain from public.communication_email_domains domain
    where domain.organization_id = selected_sender.organization_id and domain.id = selected_sender.domain_id
    for share;

    if selected_sender.lifecycle_state = 'pending_verification'
      or (sender_domain.id is not null and sender_domain.lifecycle_state not in ('removal_pending', 'removed')
        and (sender_domain.lifecycle_state <> 'verified' or not sender_domain.provider_verified
          or not sender_domain.provider_authenticated or sender_domain.ownership_status <> 'passing'
          or sender_domain.dkim_status <> 'passing')) then
      update public.communication_delivery_intents set failure_code = 'sender_domain_temporarily_unavailable',
        failure_message = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '15 minutes', candidate.expires_at),
        last_error = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if selected_sender.lifecycle_state <> 'enabled'
      or (candidate.send_kind = 'manual' and not selected_sender.allows_manual)
      or (candidate.send_kind = 'automated' and not selected_sender.allows_automated)
      or (selected_sender.assigned_user_id is not null and assigned_member_status is distinct from 'active')
      or sender_domain.id is null or sender_domain.purpose <> 'sending'
      or sender_domain.lifecycle_state in ('removal_pending', 'removed') then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    -- Part 7.5a: warm-up ceiling. A newly verified sending domain may have only a staged number of
    -- recipients accepted per UTC day; over that, the message waits for the next day. Applies to
    -- every class -- the ceiling is a total for the domain. Skipped entirely once the domain is past
    -- day 14 (resolver returns null), so a settled domain pays nothing here.
    warmup_ceiling := private.resolve_communication_email_warmup_ceiling(
      candidate.organization_id, sender_domain.id, now());
    if warmup_ceiling is not null then
      select
        coalesce((
          select sum(usage.recipient_count)
          from public.communication_email_usage_events usage
          join public.communication_delivery_intents used_intent on used_intent.id = usage.delivery_intent_id
          join public.communication_email_senders used_sender on used_sender.id = used_intent.sender_id
          where usage.organization_id = candidate.organization_id
            and usage.occurred_at >= today_start
            and used_sender.domain_id = sender_domain.id
        ), 0)
      + coalesce((
          select sum(reservation.recipient_count)
          from public.communication_email_capacity_reservations reservation
          join public.communication_delivery_intents reserved_intent on reserved_intent.id = reservation.delivery_intent_id
          join public.communication_email_senders reserved_sender on reserved_sender.id = reserved_intent.sender_id
          where reservation.organization_id = candidate.organization_id
            and reservation.reservation_state in ('reserved', 'submission_unknown')
            and reservation.reserved_at >= today_start
            and reserved_sender.domain_id = sender_domain.id
        ), 0)
      into warmup_used_today;

      if warmup_used_today + 1 > warmup_ceiling then
        update public.communication_delivery_intents
        set failure_code = 'email_warmup_ceiling_reached',
          failure_message = 'This sending domain is still warming up and has reached today''s limit. UCRM will retry tomorrow.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events
        set available_at = least(today_start + interval '1 day', candidate.expires_at),
          last_error = 'This sending domain is still warming up and has reached today''s limit. UCRM will retry tomorrow.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    -- Part 7.5a: the short-term organization sending rate. A rolling-window ceiling on recipients so
    -- a burst is spread out instead of hammering the provider. Over the limit defers with an
    -- estimated retry time; never cancels.
    select rate.max_recipients, rate.window_minutes
    into short_term_max, short_term_window
    from private.resolve_communication_email_short_term_rate(candidate.organization_id, now()) rate;

    if short_term_max is not null then
      select
        coalesce((
          select sum(usage.recipient_count)
          from public.communication_email_usage_events usage
          where usage.organization_id = candidate.organization_id
            and usage.occurred_at > now() - make_interval(mins => short_term_window)
        ), 0)
      + coalesce((
          select sum(reservation.recipient_count)
          from public.communication_email_capacity_reservations reservation
          where reservation.organization_id = candidate.organization_id
            and reservation.reservation_state in ('reserved', 'submission_unknown')
            and reservation.reserved_at > now() - make_interval(mins => short_term_window)
        ), 0)
      into short_term_used;

      select min(usage.occurred_at) into short_term_oldest_at
      from public.communication_email_usage_events usage
      where usage.organization_id = candidate.organization_id
        and usage.occurred_at > now() - make_interval(mins => short_term_window);

      if short_term_used + 1 > short_term_max then
        short_term_retry_at := coalesce(short_term_oldest_at, now())
          + make_interval(mins => short_term_window);
        if short_term_retry_at <= now() then
          short_term_retry_at := now() + interval '1 minute';
        end if;
        update public.communication_delivery_intents
        set failure_code = 'email_short_term_rate_limited',
          failure_message = format(
            'This organization has reached its short-term sending limit (%s recipients per %s minutes). UCRM will retry shortly.',
            short_term_max, short_term_window)
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events
        set available_at = least(short_term_retry_at, candidate.expires_at),
          last_error = 'Short-term sending limit reached. UCRM will retry shortly.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    -- Part 7.5b: the platform provider-period capacity and the essential reserve. Jafar sets the total
    -- recipients the provider will accept in a UTC calendar month; a percentage is fenced off so that
    -- requested quotes, invoices, receipts, security notices, and human replies still get out once
    -- ordinary mail has filled the month. Ordinary ('optional') mail stops at capacity minus the
    -- reserve; essential mail may spend the reserve but still stops at the full capacity. Over the
    -- line the message waits and is re-checked -- never cancelled. Skipped entirely while Jafar has
    -- set no capacity, which is the common case until a provider plan number is entered.
    select cap.capacity, cap.reserve_percent
    into provider_capacity, provider_reserve_percent
    from private.resolve_communication_email_provider_capacity(now()) cap;

    if provider_capacity is not null then
      provider_reserve := ceil(provider_capacity::numeric * provider_reserve_percent / 100.0)::integer;
      if candidate.allowance_class = 'optional' then
        provider_effective_cap := provider_capacity - provider_reserve;
      else
        provider_effective_cap := provider_capacity;
      end if;

      select coalesce(usage.accepted_recipients, 0) into platform_accepted
      from public.communication_email_platform_period_usage usage
      where usage.period_start = current_period_start;
      platform_accepted := coalesce(platform_accepted, 0);

      select coalesce(sum(reservation.recipient_count), 0) into platform_reserved
      from public.communication_email_capacity_reservations reservation
      where reservation.reservation_state in ('reserved', 'submission_unknown')
        and reservation.reserved_at >= current_period_start;

      if platform_accepted + platform_reserved + 1 > provider_effective_cap then
        if candidate.allowance_class = 'optional' then
          hold_message := 'The platform has reached its reserved monthly sending capacity. Essential email still sends; other email will retry.';
          update public.communication_delivery_intents
          set failure_code = 'email_platform_capacity_reserved', failure_message = hold_message
          where id = candidate.delivery_intent_id;
        else
          hold_message := 'The platform has reached its monthly provider sending capacity. UCRM will retry shortly.';
          update public.communication_delivery_intents
          set failure_code = 'email_platform_capacity_reached', failure_message = hold_message
          where id = candidate.delivery_intent_id;
        end if;
        update public.communication_outbox_events
        set available_at = least(now() + interval '15 minutes', candidate.expires_at), last_error = hold_message
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    select * into active_allowance
    from private.resolve_communication_email_allowance(candidate.organization_id, now());
    if not found then
      update public.communication_delivery_intents set failure_code = 'email_allowance_period_unavailable',
        failure_message = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '15 minutes', candidate.expires_at),
        last_error = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if candidate.allowance_class = 'optional' then
      allowance_limit_state := active_allowance.operational_limit_state;
      allowance_limit_value := active_allowance.operational_limit_value;
    else
      allowance_limit_state := active_allowance.essential_limit_state;
      allowance_limit_value := active_allowance.essential_limit_value;
    end if;
    if allowance_limit_state not in ('numeric', 'unlimited')
      or (allowance_limit_state = 'numeric' and allowance_limit_value is null) then
      update public.communication_delivery_intents set failure_code = 'email_allowance_unavailable',
        failure_message = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '15 minutes', candidate.expires_at),
        last_error = 'Email allowance is unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    insert into public.communication_email_capacity_buckets (
      organization_id, allowance_period_id, allowance_class
    ) values (candidate.organization_id, active_allowance.period_id, candidate.allowance_class)
    on conflict do nothing;
    perform 1 from public.communication_email_capacity_buckets bucket
    where bucket.organization_id = candidate.organization_id
      and bucket.allowance_period_id = active_allowance.period_id
      and bucket.allowance_class = candidate.allowance_class
    for update;

    if allowance_limit_state = 'numeric' then
      select coalesce(sum(usage.recipient_count), 0)::integer into accepted_recipient_count
      from public.communication_email_usage_events usage
      where usage.organization_id = candidate.organization_id
        and usage.allowance_period_id = active_allowance.period_id
        and usage.allowance_class = candidate.allowance_class;
      select coalesce(sum(reservation.recipient_count), 0)::integer into reserved_recipient_count
      from public.communication_email_capacity_reservations reservation
      where reservation.organization_id = candidate.organization_id
        and reservation.allowance_period_id = active_allowance.period_id
        and reservation.allowance_class = candidate.allowance_class
        and reservation.reservation_state in ('reserved', 'submission_unknown');
      if accepted_recipient_count + reserved_recipient_count >= allowance_limit_value then
        update public.communication_delivery_intents set failure_code = 'email_allowance_exhausted',
          failure_message = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events
        set available_at = least(now() + interval '15 minutes', candidate.expires_at),
          last_error = 'Email allowance is currently exhausted. UCRM will check again.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    insert into public.communication_email_capacity_reservations (
      organization_id, delivery_intent_id, allowance_period_id, allowance_class, reservation_state, reserved_at, settled_at
    ) values (
      candidate.organization_id, candidate.delivery_intent_id, active_allowance.period_id,
      candidate.allowance_class, 'reserved', now(), null
    ) on conflict on constraint communication_email_capacity_reservations_delivery_intent_key do update set
      organization_id = excluded.organization_id,
      allowance_period_id = excluded.allowance_period_id,
      allowance_class = excluded.allowance_class,
      reservation_state = 'reserved', reserved_at = now(), settled_at = null
    where public.communication_email_capacity_reservations.reservation_state = 'released';
    if not found then
      raise exception 'The email capacity reservation is not available for this delivery intent.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;

    alias := null;
    alias_domain := null;
    if candidate.reply_alias_id is not null then
      select rep_alias.* into alias from public.communication_reply_aliases rep_alias
      where rep_alias.id = candidate.reply_alias_id and rep_alias.organization_id = candidate.organization_id
      for share;
      if alias.id is not null then
        select * into alias_domain from public.communication_email_domains
        where id = alias.receiving_domain_id and organization_id = candidate.organization_id
        for share;
      end if;
    end if;

    new_claim_token := gen_random_uuid();
    update public.communication_outbox_events set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null where id = candidate.event_id;
    update public.communication_delivery_intents set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null where id = candidate.delivery_intent_id;
    return query select candidate.event_id, candidate.delivery_intent_id, new_claim_token,
      candidate.recipient_email, candidate.subject, candidate.html_content, candidate.text_content,
      candidate.logical_send_key, selected_sender.id, selected_sender.email_address, selected_sender.display_name,
      case when alias.id is not null and alias_domain.id is not null
        then alias.alias_local_part || '@' || alias_domain.domain_name else null end,
      case when alias.id is not null then selected_sender.display_name else null end;
    return;
  end loop;
end;
$function$;

revoke all on function public.claim_communication_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_outbox_event() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 6. The contractor removal flow only clears bounces and complaints. An unsubscribe is restored by
--    renewed consent and Brevo reconciliation, not this auto/pending flow, so it is refused here with a
--    clear message instead of failing the removal-request table's own reason check.
--    This is migration 20260906210000's definition with that one guard added.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.request_communication_email_suppression_removal(
  p_organization_id uuid,
  p_suppression_id uuid,
  p_actor_user_id uuid,
  p_actor_email text,
  p_reason text,
  p_evidence text,
  p_consent_confirmed boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_email text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  clean_evidence text := btrim(coalesce(p_evidence, ''));
  target public.communication_email_suppressions%rowtype;
  new_request public.communication_email_suppression_removal_requests%rowtype;
  auto_approve boolean;
begin
  if char_length(actor_email) not between 3 and 320 then
    raise exception 'An administrator email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 1000 then
    raise exception 'A reason of 3 to 1000 characters is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_evidence) not between 1 and 2000 then
    raise exception 'Describe how the address was verified.' using errcode = 'check_violation';
  end if;
  if coalesce(p_consent_confirmed, false) is not true then
    raise exception 'Confirm the customer still wants to receive this email.'
      using errcode = 'check_violation';
  end if;

  -- Lock the suppression so a concurrent request or a race with the release cannot double up.
  select * into target
  from public.communication_email_suppressions
  where id = p_suppression_id and organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'That blocked address was not found.' using errcode = 'no_data_found';
  end if;
  if target.released_at is not null then
    raise exception 'That address is no longer blocked.' using errcode = 'check_violation';
  end if;
  if target.reason not in ('hard_bounce', 'complaint') then
    raise exception 'Unsubscribed addresses are restored through renewed consent, not a removal request.'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.communication_email_suppression_removal_requests
    where suppression_id = p_suppression_id and status = 'pending'
  ) then
    raise exception 'A removal request for that address is already open.'
      using errcode = 'unique_violation';
  end if;

  auto_approve := target.reason = 'hard_bounce';

  insert into public.communication_email_suppression_removal_requests (
    suppression_id, organization_id, suppression_reason, recipient_email,
    requested_by_user_id, requested_by_email, request_reason, request_evidence, consent_confirmed,
    status, decided_by_kind, decided_by_user_id, decided_by_email, decided_at, decision_note
  ) values (
    p_suppression_id, p_organization_id, target.reason, target.recipient_email,
    p_actor_user_id, actor_email, clean_reason, clean_evidence, true,
    case when auto_approve then 'approved' else 'pending' end,
    case when auto_approve then 'organization_admin' end,
    case when auto_approve then p_actor_user_id end,
    case when auto_approve then actor_email end,
    case when auto_approve then now() end,
    case when auto_approve then 'Corrected hard-bounce address cleared by the organization.' end
  )
  returning * into new_request;

  if auto_approve then
    update public.communication_email_suppressions
    set released_at = now(),
      released_by_owner_email = null,
      released_by_kind = 'organization_admin',
      released_by_user_id = p_actor_user_id,
      released_reason = 'Hard-bounce address corrected and re-verified by the organization.'
    where id = p_suppression_id;
  end if;

  return public.communication_email_suppression_removal_request_json(new_request.id);
end;
$$;

revoke all on function public.request_communication_email_suppression_removal(
  uuid, uuid, uuid, text, text, text, boolean
) from public, anon, authenticated;
grant execute on function public.request_communication_email_suppression_removal(
  uuid, uuid, uuid, text, text, text, boolean
) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 7. Platform-Owner callback-processing health. Read-only, bounded, keyed on the processor's job name
--    (never its numeric id, which is not stable). Surfaces whether the cron processor is succeeding,
--    whether anything is stuck or parked as poison, and what the provider is currently rejecting.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_provider_callback_health()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'processor_job_name', 'communications-provider-callback-processor',
    'unprocessed_count', (
      select count(*) from public.communication_provider_callback_events where processed_at is null
    ),
    'oldest_unprocessed_at', (
      select min(received_at) from public.communication_provider_callback_events where processed_at is null
    ),
    'oldest_unprocessed_age_seconds', (
      select extract(epoch from (now() - min(received_at)))::bigint
      from public.communication_provider_callback_events where processed_at is null
    ),
    'retrying_count', (
      select count(*) from public.communication_provider_callback_events
      where processed_at is null and processing_attempts > 0
    ),
    'parked_count', (
      select count(*) from public.communication_provider_callback_events
      where processed_at is not null and processing_error is not null
    ),
    'last_run', (
      select jsonb_build_object('status', d.status, 'ran_at', d.start_time, 'finished_at', d.end_time)
      from cron.job j
      join cron.job_run_details d on d.jobid = j.jobid
      where j.jobname = 'communications-provider-callback-processor'
      order by d.start_time desc
      limit 1
    ),
    'last_success_at', (
      select max(d.end_time)
      from cron.job j
      join cron.job_run_details d on d.jobid = j.jobid
      where j.jobname = 'communications-provider-callback-processor' and d.status = 'succeeded'
    ),
    'provider_blocking_24h', coalesce((
      select jsonb_object_agg(g.delivery_outcome, g.outcome_count)
      from (
        select delivery_outcome, count(*) as outcome_count
        from public.communication_delivery_intents
        where delivery_outcome in ('blocked', 'hard_bounce', 'complaint', 'unsubscribed')
          and delivery_outcome_at >= now() - interval '24 hours'
        group by delivery_outcome
      ) g
    ), '{}'::jsonb),
    'active_suppressions', coalesce((
      select jsonb_object_agg(s.reason, s.reason_count)
      from (
        select reason, count(*) as reason_count
        from public.communication_email_suppressions
        where released_at is null
        group by reason
      ) s
    ), '{}'::jsonb)
  );
$$;

revoke all on function public.get_communication_provider_callback_health() from public, anon, authenticated;
grant execute on function public.get_communication_provider_callback_health() to service_role;
