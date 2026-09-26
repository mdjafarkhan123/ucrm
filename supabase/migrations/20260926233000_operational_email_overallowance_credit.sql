-- Over-allowance email credit (Part 7 of the operational-email-on-SES campaign; approved 2026-08-15,
-- amended 2026-09-24 -- see docs/contractor-email-contract.md "Package allowances and counting").
--
-- Jafar's decision (2026-09-26): optional email beyond the period allowance spends from the exact same
-- Communication Balance account and ledger SMS already uses -- one balance, one top-up flow, one history.
-- communication_sms_credit_reservations already carried a channel column constrained to 'sms' only, which
-- reads as a deliberate widening seam: this migration opens it up to 'email' rows instead of building a
-- second, parallel balance system. communication_sms_credit_accounts and communication_sms_credit_ledger_
-- entries need no change at all -- they were already organization-level with no SMS-specific column.
--
-- Essential email (requested quotes, invoices, receipts, security notices, direct replies) never stops or
-- queues for an exhausted allowance or balance; it is only counted, with a one-time alert to Jafar when the
-- protected reserve runs out. That alert used to ride on a trigger keyed to the very failure_code update
-- this migration removes for essential, so the alert becomes a plain function claim_communication_outbox_
-- event calls directly instead.

-- 1. Widen the SMS credit reservation table to also hold an email over-allowance credit hold.
ALTER TABLE "public"."communication_sms_credit_reservations"
  DROP CONSTRAINT "communication_sms_credit_reservations_channel_check";

ALTER TABLE "public"."communication_sms_credit_reservations"
  ALTER COLUMN "segment_count" DROP NOT NULL;

ALTER TABLE "public"."communication_sms_credit_reservations"
  ADD COLUMN "recipient_count" integer;

ALTER TABLE "public"."communication_sms_credit_reservations"
  ADD CONSTRAINT "communication_sms_credit_reservations_channel_check"
    CHECK (("channel" = ANY (ARRAY['sms'::"text", 'email'::"text"])));

ALTER TABLE "public"."communication_sms_credit_reservations"
  ADD CONSTRAINT "communication_sms_credit_reservations_recipient_count_check"
    CHECK ((("recipient_count" IS NULL) OR ("recipient_count" > 0)));

ALTER TABLE "public"."communication_sms_credit_reservations"
  ADD CONSTRAINT "communication_sms_credit_reservations_unit_check"
    CHECK (
      ((("channel" = 'sms') AND ("segment_count" IS NOT NULL) AND ("recipient_count" IS NULL)))
      OR ((("channel" = 'email') AND ("recipient_count" IS NOT NULL) AND ("segment_count" IS NULL)))
    );

COMMENT ON TABLE "public"."communication_sms_credit_reservations" IS 'Per-send money hold against the organization''s one Communication Balance account (communication_sms_credit_accounts), shared by SMS (priced by segment_count) and over-allowance optional email (priced by recipient_count). Settles to a charge ledger entry on provider acceptance, releases on cancel/retry.';

COMMENT ON COLUMN "public"."communication_sms_credit_reservations"."recipient_count" IS 'Set only for an email row (channel = ''email''): the recipient this over-allowance send charged for. Null for an SMS row, which prices by segment_count instead.';

COMMENT ON COLUMN "public"."communication_sms_credit_reservations"."channel" IS 'sms or email. Both channels share one organization-level balance and ledger; this column only tells apart how a given reservation is priced and matched back to its delivery intent.';

-- 2. The over-allowance email price Jafar sets, in currency major units per 1,000 recipients, versioned
--    and effective-dated exactly like communication_sms_retail_rates.
CREATE TABLE IF NOT EXISTS "public"."communication_email_retail_rates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "currency_code" "text" DEFAULT 'USD'::"text" NOT NULL,
    "retail_rate_major" numeric(14,6) NOT NULL,
    "provider_cost_major" numeric(14,6),
    "effective_from" timestamp with time zone DEFAULT "now"() NOT NULL,
    "set_by" "uuid" NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "communication_email_retail_rates_currency_check" CHECK (("currency_code" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "communication_email_retail_rates_cost_check" CHECK ((("provider_cost_major" IS NULL) OR ("provider_cost_major" >= (0)::numeric))),
    CONSTRAINT "communication_email_retail_rates_note_check" CHECK ((("note" IS NULL) OR ("char_length"("note") <= 2000))),
    CONSTRAINT "communication_email_retail_rates_retail_check" CHECK (("retail_rate_major" > (0)::numeric))
);

ALTER TABLE "public"."communication_email_retail_rates" OWNER TO "postgres";

COMMENT ON TABLE "public"."communication_email_retail_rates" IS 'Immutable over-allowance email retail price versions, in currency major units per 1,000 recipients, set by the Platform Owner. The applicable rate for a moment is the latest version whose effective_from has arrived; a send freezes it so historical charges keep their rate. Server-owned; written only via communication_email_set_retail_rate. provider_cost_major (Amazon SES''s real per-1,000 cost) is Jafar-only.';

ALTER TABLE "public"."communication_email_retail_rates" ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION "public"."communication_email_effective_retail_rate"("p_currency_code" "text" DEFAULT 'USD'::"text", "p_at" timestamp with time zone DEFAULT "now"()) RETURNS "public"."communication_email_retail_rates"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
  select r.*
  from public.communication_email_retail_rates r
  where r.currency_code = coalesce(p_currency_code, 'USD')
    and r.effective_from <= p_at
  order by r.effective_from desc
  limit 1;
$$;

ALTER FUNCTION "public"."communication_email_effective_retail_rate"("p_currency_code" "text", "p_at" timestamp with time zone) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."communication_email_set_retail_rate"("p_retail_rate_major" numeric, "p_set_by" "uuid", "p_currency_code" "text" DEFAULT 'USD'::"text", "p_provider_cost_major" numeric DEFAULT NULL::numeric, "p_effective_from" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_note" "text" DEFAULT NULL::"text") RETURNS "public"."communication_email_retail_rates"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  rate public.communication_email_retail_rates;
  effective timestamptz := coalesce(p_effective_from, now());
begin
  if effective < now() then
    raise exception 'a retail rate takes effect now or in the future, never retroactively'
      using errcode = 'P0001';
  end if;

  insert into public.communication_email_retail_rates (
    currency_code, retail_rate_major, provider_cost_major, effective_from, set_by, note
  ) values (
    coalesce(p_currency_code, 'USD'), p_retail_rate_major, p_provider_cost_major, effective, p_set_by, p_note
  )
  returning * into rate;

  return rate;
end;
$$;

ALTER FUNCTION "public"."communication_email_set_retail_rate"("p_retail_rate_major" numeric, "p_set_by" "uuid", "p_currency_code" "text", "p_provider_cost_major" numeric, "p_effective_from" timestamp with time zone, "p_note" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."communication_email_effective_retail_rate"("p_currency_code" "text", "p_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."communication_email_effective_retail_rate"("p_currency_code" "text", "p_at" timestamp with time zone) TO "service_role";

REVOKE ALL ON FUNCTION "public"."communication_email_set_retail_rate"("p_retail_rate_major" numeric, "p_set_by" "uuid", "p_currency_code" "text", "p_provider_cost_major" numeric, "p_effective_from" timestamp with time zone, "p_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."communication_email_set_retail_rate"("p_retail_rate_major" numeric, "p_set_by" "uuid", "p_currency_code" "text", "p_provider_cost_major" numeric, "p_effective_from" timestamp with time zone, "p_note" "text") TO "service_role";

GRANT SELECT, INSERT ON TABLE "public"."communication_email_retail_rates" TO "service_role";

-- 3. Essential-reserve-exhaustion alerting no longer rides on the delivery-intent failure_code trigger,
--    because essential email no longer sets that failure_code (it never queues). Convert the trigger
--    function into a plain function claim_communication_outbox_event calls directly.
DROP TRIGGER IF EXISTS "communication_delivery_intents_essential_reserve_exhausted" ON "public"."communication_delivery_intents";

DROP FUNCTION IF EXISTS "private"."record_communication_email_reserve_exhaustion"();

CREATE FUNCTION "private"."record_communication_email_reserve_exhaustion"("p_organization_id" "uuid", "p_allowance_period_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'private'
    AS $$
declare
  organization_name text;
begin
  insert into public.communication_email_allowance_alerts (
    organization_id, allowance_period_id, alert_kind
  ) values (p_organization_id, p_allowance_period_id, 'essential_reserve_exhausted')
  on conflict on constraint communication_email_allowance_alerts_once do nothing;
  if not found then
    return;
  end if;

  select organization.name into organization_name
  from public.organizations as organization
  where organization.id = p_organization_id;

  insert into public.platform_owner_notifications (kind, severity, title, body, target_kind, target_id)
  values (
    'communication_email_essential_reserve_exhausted',
    'urgent',
    'Protected essential email reserve exhausted',
    coalesce(organization_name, 'An organization')
      || ' has used its whole protected essential email reserve for the current billing period. '
      || 'Requested quotes, invoices, receipts, security notices, and direct replies are still being sent '
      || '(essential email is never held back), but you may want to raise its allowance.',
    'organization',
    p_organization_id
  );
end;
$$;

ALTER FUNCTION "private"."record_communication_email_reserve_exhaustion"("p_organization_id" "uuid", "p_allowance_period_id" "uuid") OWNER TO "postgres";

-- 4. claim_communication_outbox_event: essential never queues for an exhausted reserve (alert, then send);
--    optional over its allowance tries to fund the send from the shared Communication Balance at Jafar's
--    published over-allowance price, and only pauses (with a distinct, credit-specific failure code) when
--    that balance is too low. Rebuilt from the 20260925191000 version (which added organization_id and
--    sender_provider to the return columns and qualified the alias-domain lookup), not the stale baseline
--    copy -- that earlier version is gone from the live schema.
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

ALTER FUNCTION "public"."claim_communication_outbox_event"() OWNER TO "postgres";

-- 5. finalize_communication_outbox_event: settle the email over-allowance credit reservation synchronously
--    on submission (SES pricing is known upfront, unlike Twilio's async-reported price), and release it on
--    retry/cancel exactly like the allowance reservation is released.
CREATE OR REPLACE FUNCTION "public"."finalize_communication_outbox_event"("target_outbox_event_id" "uuid", "target_claim_token" "uuid", "target_outcome" "text", "target_provider_message_id" "text" DEFAULT NULL::"text", "target_failure_code" "text" DEFAULT NULL::"text", "target_failure_message" "text" DEFAULT NULL::"text") RETURNS TABLE("outbox_status" "text", "intent_status" "text", "attempt_count" integer, "available_at" timestamp with time zone, "usage_recorded" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  claimed_event public.communication_outbox_events;
  reservation public.communication_email_capacity_reservations;
  credit_reservation public.communication_sms_credit_reservations;
  next_available_at timestamptz;
  new_settled_balance bigint;
begin
  if target_outcome not in ('submitted', 'retry', 'submission_unknown', 'cancelled') then
    raise exception 'The communication outcome is invalid.' using errcode = 'check_violation';
  end if;
  select * into claimed_event from public.communication_outbox_events where id = target_outbox_event_id for update;
  if not found then raise exception 'The communication outbox event does not exist.' using errcode = 'no_data_found'; end if;
  if claimed_event.status <> 'processing' then
    if claimed_event.finalized_claim_token is distinct from target_claim_token then
      raise exception 'The communication claim is no longer current.' using errcode = 'object_not_in_prerequisite_state';
    end if;
    return query select claimed_event.status, intent.status, claimed_event.attempt_count, claimed_event.available_at,
      exists (select 1 from public.communication_email_usage_events usage where usage.delivery_intent_id = claimed_event.delivery_intent_id)
    from public.communication_delivery_intents intent where intent.id = claimed_event.delivery_intent_id;
    return;
  end if;
  if claimed_event.claim_token is distinct from target_claim_token then
    raise exception 'The communication claim token is invalid.' using errcode = 'insufficient_privilege';
  end if;
  select * into reservation from public.communication_email_capacity_reservations
  where delivery_intent_id = claimed_event.delivery_intent_id for update;
  select * into credit_reservation from public.communication_sms_credit_reservations
  where delivery_intent_id = claimed_event.delivery_intent_id and channel = 'email' for update;

  if target_outcome = 'submitted' then
    if nullif(trim(target_provider_message_id), '') is null then
      raise exception 'A submitted email requires a provider message identifier.' using errcode = 'not_null_violation';
    end if;
    update public.communication_delivery_intents set status = 'submitted', provider_message_id = trim(target_provider_message_id),
      accepted_at = now(), failure_code = null, failure_message = null where id = claimed_event.delivery_intent_id;
    if reservation.id is null then
      insert into public.communication_email_usage_events (organization_id, delivery_intent_id, recipient_count)
      values (claimed_event.organization_id, claimed_event.delivery_intent_id, 1) on conflict (delivery_intent_id) do nothing;
    else
      update public.communication_email_capacity_reservations set reservation_state = 'accepted', settled_at = now()
      where id = reservation.id;
      insert into public.communication_email_usage_events (
        organization_id, delivery_intent_id, recipient_count, allowance_period_id, allowance_class
      ) values (
        claimed_event.organization_id, claimed_event.delivery_intent_id, reservation.recipient_count,
        reservation.allowance_period_id, reservation.allowance_class
      ) on conflict (delivery_intent_id) do nothing;
    end if;
    if credit_reservation.id is not null and credit_reservation.state = 'reserved' then
      update public.communication_sms_credit_accounts
      set settled_balance_minor = settled_balance_minor - credit_reservation.reserved_purchased_minor,
          reserved_balance_minor = reserved_balance_minor - credit_reservation.reserved_purchased_minor,
          updated_at = now()
      where organization_id = credit_reservation.organization_id
      returning settled_balance_minor into new_settled_balance;

      insert into public.communication_sms_credit_ledger_entries (
        organization_id, reservation_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at
      ) values (
        credit_reservation.organization_id, credit_reservation.id, 'charge:' || credit_reservation.source_key, 'charge',
        -credit_reservation.reserved_purchased_minor, new_settled_balance, now()
      );

      update public.communication_sms_credit_reservations
      set state = 'settled', settled_at = now()
      where id = credit_reservation.id;
    end if;
    update public.communication_outbox_events set status = 'submitted', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = null where id = claimed_event.id;
  elsif target_outcome = 'retry' then
    next_available_at := case claimed_event.attempt_count when 1 then now() + interval '5 minutes'
      when 2 then now() + interval '30 minutes' when 3 then now() + interval '2 hours'
      when 4 then now() + interval '8 hours' when 5 then now() + interval '24 hours' else 'infinity'::timestamptz end;
    update public.communication_delivery_intents set status = 'failed', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''), failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;
    if reservation.id is not null then update public.communication_email_capacity_reservations
      set reservation_state = 'released', settled_at = now() where id = reservation.id; end if;
    perform private.communication_sms_release_reservation(claimed_event.delivery_intent_id);
    update public.communication_outbox_events set status = 'failed', available_at = next_available_at, claimed_at = null,
      claim_token = null, finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;
  elsif target_outcome = 'submission_unknown' then
    update public.communication_delivery_intents set status = 'submission_unknown', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''), failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;
    if reservation.id is not null then update public.communication_email_capacity_reservations
      set reservation_state = 'submission_unknown', settled_at = now() where id = reservation.id; end if;
    if credit_reservation.id is not null and credit_reservation.state = 'reserved' then
      update public.communication_sms_credit_reservations
      set state = 'submission_unknown', settled_at = now()
      where id = credit_reservation.id;
    end if;
    update public.communication_outbox_events set status = 'submission_unknown', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '') where id = claimed_event.id;
  else
    update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''), failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;
    if reservation.id is not null then update public.communication_email_capacity_reservations
      set reservation_state = 'released', settled_at = now() where id = reservation.id; end if;
    perform private.communication_sms_release_reservation(claimed_event.delivery_intent_id);
    update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '') where id = claimed_event.id;
  end if;
  return query select event.status, intent.status, event.attempt_count, event.available_at,
    exists (select 1 from public.communication_email_usage_events usage where usage.delivery_intent_id = event.delivery_intent_id)
  from public.communication_outbox_events event join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
  where event.id = claimed_event.id;
end;
$$;

ALTER FUNCTION "public"."finalize_communication_outbox_event"("target_outbox_event_id" "uuid", "target_claim_token" "uuid", "target_outcome" "text", "target_provider_message_id" "text", "target_failure_code" "text", "target_failure_message" "text") OWNER TO "postgres";
