-- Package email allowances can no longer silently stop email.
--
-- Found 2026-09-26: several package versions carried 'not_included' for both email allowance keys (seeded
-- that way, never chosen), including the published Starter and the Elite version two live organizations are
-- on. claim_communication_outbox_event then retried their email every 15 minutes forever, sending nothing
-- and telling nobody -- which breaks docs/contractor-email-contract.md: essential email never stops because
-- of an allowance.
--
-- The claim now treats a missing / 'not_included' allowance as zero (see the comment in the function).
-- Package versions themselves are not touched: published and retired versions are immutable by design, so
-- their allowances are corrected by publishing new versions from the Jafar Panel.

CREATE OR REPLACE FUNCTION "public"."claim_communication_outbox_event"()
RETURNS TABLE(
    "outbox_event_id" uuid, "delivery_intent_id" uuid, "organization_id" uuid, "claim_token" uuid,
    "recipient_email" text, "subject" text, "html_content" text, "text_content" text, "logical_send_key" text,
    "sender_id" uuid, "sender_email" text, "sender_name" text, "sender_provider" text,
    "reply_to_email" text, "reply_to_name" text
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'private'
    AS $$
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
  email_rate public.communication_email_retail_rates;
  credit_cost_minor bigint;
  credit_recipient_count integer;
  credit_promo_used bigint;
  credit_purchased_used bigint;
  credit_settled bigint;
  credit_reserved bigint;
  credit_promo_balance bigint;
  credit_promo_reserved bigint;
  credit_promo_available bigint;
  credit_purchased_available bigint;
begin
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
    where event.channel = 'email' and event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
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
    -- A package with no email allowance set ('not_included', or no row at all) is an allowance of zero,
    -- never a stop: essential email still sends (the reserve-exhaustion alert fires once per period) and
    -- optional email is funded from the Communication Balance like any over-allowance email. It used to
    -- retry here every 15 minutes forever with nothing shown to anyone.
    if allowance_limit_state is distinct from 'unlimited'
      and (allowance_limit_state is distinct from 'numeric' or allowance_limit_value is null) then
      allowance_limit_state := 'numeric';
      allowance_limit_value := 0;
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

    credit_cost_minor := null;
    credit_recipient_count := null;
    credit_promo_used := null;
    credit_purchased_used := null;

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
        if candidate.allowance_class = 'essential' then
          -- Essential email never queues for an exhausted reserve -- alert once per period, then fall
          -- through below and let it send (still counted against the essential bucket as usual).
          perform private.record_communication_email_reserve_exhaustion(candidate.organization_id, active_allowance.period_id);
        else
          -- Optional email over its allowance: try to fund it from the organization's Communication
          -- Balance (the same account and ledger SMS spends from) at Jafar's published over-allowance
          -- price. No published price yet means UCRM cannot safely charge, so this behaves like the old
          -- exhausted-defer instead of guessing a price.
          select rr.* into email_rate
          from public.communication_email_effective_retail_rate('USD', now()) rr;
          if email_rate.id is null then
            update public.communication_delivery_intents set failure_code = 'email_allowance_exhausted',
              failure_message = 'Email allowance is currently exhausted. UCRM will check again.'
            where id = candidate.delivery_intent_id;
            update public.communication_outbox_events
            set available_at = least(now() + interval '15 minutes', candidate.expires_at),
              last_error = 'Email allowance is currently exhausted. UCRM will check again.'
            where id = candidate.event_id;
            continue;
          end if;

          credit_recipient_count := 1;
          credit_cost_minor := ceil(credit_recipient_count * email_rate.retail_rate_major / 1000.0 * 100)::bigint;

          insert into public.communication_sms_credit_accounts (organization_id, currency_code)
          values (candidate.organization_id, email_rate.currency_code)
          on conflict on constraint communication_sms_credit_accounts_pkey do nothing;

          select account.settled_balance_minor, account.reserved_balance_minor into credit_settled, credit_reserved
          from public.communication_sms_credit_accounts account
          where account.organization_id = candidate.organization_id
          for update;

          credit_promo_balance := public.communication_sms_promotional_balance(candidate.organization_id);
          select coalesce(sum(credit_res.reserved_promotional_minor), 0) into credit_promo_reserved
          from public.communication_sms_credit_reservations credit_res
          where credit_res.organization_id = candidate.organization_id
            and credit_res.state in ('reserved', 'submission_unknown', 'settled');
          credit_promo_available := greatest(credit_promo_balance - credit_promo_reserved, 0);
          credit_purchased_available := credit_settled - credit_reserved;

          if credit_promo_available + credit_purchased_available < credit_cost_minor then
            update public.communication_delivery_intents set failure_code = 'email_balance_insufficient',
              failure_message = 'This email is beyond your plan''s free allowance and your Communication Balance is too low to send it. Add credit to send it.'
            where id = candidate.delivery_intent_id;
            update public.communication_outbox_events
            set available_at = least(now() + interval '15 minutes', candidate.expires_at),
              last_error = 'Communication Balance is too low for over-allowance email. UCRM will retry after credit is added.'
            where id = candidate.event_id;
            continue;
          end if;

          credit_promo_used := least(credit_cost_minor, credit_promo_available);
          credit_purchased_used := credit_cost_minor - credit_promo_used;

          update public.communication_sms_credit_accounts
          set reserved_balance_minor = reserved_balance_minor + credit_purchased_used,
              updated_at = now()
          where communication_sms_credit_accounts.organization_id = candidate.organization_id;
        end if;
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

    if credit_cost_minor is not null then
      insert into public.communication_sms_credit_reservations (
        organization_id, delivery_intent_id, channel, source_key, amount_minor, recipient_count,
        reserved_promotional_minor, reserved_purchased_minor, state
      ) values (
        candidate.organization_id, candidate.delivery_intent_id, 'email',
        'email-overage:' || candidate.delivery_intent_id::text, credit_cost_minor, credit_recipient_count,
        credit_promo_used, credit_purchased_used, 'reserved'
      )
      on conflict on constraint communication_sms_credit_reservations_one_intent do update set
        source_key = excluded.source_key, amount_minor = excluded.amount_minor,
        recipient_count = excluded.recipient_count, reserved_promotional_minor = excluded.reserved_promotional_minor,
        reserved_purchased_minor = excluded.reserved_purchased_minor,
        state = 'reserved', reserved_at = now(), settled_at = null
      where public.communication_sms_credit_reservations.state = 'released';
      if not found then
        raise exception 'The email over-allowance credit reservation is not available for this delivery intent.'
          using errcode = 'object_not_in_prerequisite_state';
      end if;
    end if;

    alias := null;
    alias_domain := null;
    if candidate.reply_alias_id is not null then
      select rep_alias.* into alias from public.communication_reply_aliases rep_alias
      where rep_alias.id = candidate.reply_alias_id and rep_alias.organization_id = candidate.organization_id
      for share;
      if alias.id is not null then
        select domain.* into alias_domain from public.communication_email_domains domain
        where domain.id = alias.receiving_domain_id and domain.organization_id = candidate.organization_id
        for share;
      end if;
    end if;

    new_claim_token := gen_random_uuid();
    update public.communication_outbox_events set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null where id = candidate.event_id;
    update public.communication_delivery_intents set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null where id = candidate.delivery_intent_id;
    return query select candidate.event_id, candidate.delivery_intent_id, candidate.organization_id, new_claim_token,
      candidate.recipient_email, candidate.subject, candidate.html_content, candidate.text_content,
      candidate.logical_send_key, selected_sender.id, selected_sender.email_address, selected_sender.display_name,
      sender_domain.provider,
      case when alias.id is not null and alias_domain.id is not null
        then alias.alias_local_part || '@' || alias_domain.domain_name else null end,
      case when alias.id is not null then selected_sender.display_name else null end;
    return;
  end loop;
end;
$$;
