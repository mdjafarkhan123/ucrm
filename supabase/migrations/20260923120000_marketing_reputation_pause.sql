-- Marketing M4 stage 6: a Marketing-only reputation pause.
--
-- Until now the automatic reputation pause only measured operational email (quotes, invoices, reminders), so
-- a Marketing campaign that drew spam complaints or hard bounces never stopped itself. This adds the
-- Marketing counterpart, following the separate-stream pattern (Postmark broadcast streams, SES configuration
-- sets): Marketing is measured on its own recipients and pauses on its own, and that pause never holds any
-- operational email. The reverse coupling is kept on purpose -- an operational reputation pause (or any
-- organization pause) still holds Marketing too.
--
-- Signals are spam complaints and hard bounces over rolling 24-hour and 7-day windows, judged against the
-- same effective thresholds (platform values plus Jafar's per-organization overrides) the operational
-- evaluator uses. Unsubscribes are deliberately not a pause signal for Marketing: a one-click unsubscribe is
-- the healthy outcome a promotional stream is expected to produce. Only Jafar resumes the pause; each waiting
-- recipient's consent and suppression are rechecked at claim time, so resuming reruns eligibility.

-- ---------------------------------------------------------------------------------------------------
-- The pause row: a new source that applies to Marketing only
-- ---------------------------------------------------------------------------------------------------

alter table "public"."communication_email_sending_pauses"
    drop constraint "communication_email_sending_pauses_applies_to_check",
    drop constraint "communication_email_sending_pauses_source_check",
    drop constraint "communication_email_sending_pauses_source_scope_check";

alter table "public"."communication_email_sending_pauses"
    add constraint "communication_email_sending_pauses_applies_to_check"
        check ("applies_to" = any (array['all'::text, 'optional'::text, 'marketing'::text])),
    add constraint "communication_email_sending_pauses_source_check"
        check ("source" = any (array['manual'::text, 'auto_reputation'::text, 'auto_marketing_reputation'::text])),
    add constraint "communication_email_sending_pauses_source_scope_check"
        check (
            ("source" = 'manual' and "applies_to" = 'all')
            or ("source" = 'auto_reputation' and "scope" = 'organization' and "applies_to" = 'optional')
            or ("source" = 'auto_marketing_reputation' and "scope" = 'organization' and "applies_to" = 'marketing')
        );

comment on column "public"."communication_email_sending_pauses"."applies_to" is
    'all = every email; optional = operational optional email and Marketing (automatic operational reputation pause); marketing = Marketing campaigns only, never operational email (automatic Marketing reputation pause).';

-- ---------------------------------------------------------------------------------------------------
-- Measuring Marketing on its own recipients
-- ---------------------------------------------------------------------------------------------------

-- Backs the numerator: this organization's projected complaint/hard-bounce events inside a window. The
-- denominator already has marketing_campaign_recipients_org_submitted_idx.
create index if not exists "marketing_campaign_recipient_events_org_reputation_idx"
    on "public"."marketing_campaign_recipient_events" using btree ("organization_id", "normalized_kind", "received_at")
    where ("processed_at" is not null and "normalized_kind" in ('hard_bounce', 'complaint'));

-- Same output shape as private.communication_email_reputation_metrics so the Jafar panel can render both the
-- same way. Denominator: recipients SES accepted inside the window. Numerator: distinct sends with a
-- projected event of that kind received inside the window.
create or replace function "private"."marketing_email_reputation_metrics"(
    "p_organization_id" uuid,
    "p_at" timestamptz default now()
) returns table (
    "signal" text, "window_key" text, "window_hours" integer, "window_start" timestamptz,
    "accepted_recipients" bigint, "event_count" bigint, "rate" numeric, "warn_rate" numeric,
    "pause_rate" numeric, "min_sample_recipients" integer, "min_event_count" integer, "status" text
)
    language sql stable security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
    with resolved as (
        select t.*, p_at - make_interval(hours => t.window_hours) as window_start
        from private.communication_email_effective_reputation_thresholds(p_organization_id, p_at) t
        where t.signal in ('complaint', 'hard_bounce')
    ),
    counted as (
        select
            r.*,
            (
                select count(*)::bigint
                from public.marketing_campaign_recipients recipient
                where recipient.organization_id = p_organization_id
                    and recipient.submitted_at is not null
                    and recipient.submitted_at >= r.window_start
                    and recipient.submitted_at <= p_at
            ) as accepted_recipients,
            (
                select count(distinct event.provider_message_id)::bigint
                from public.marketing_campaign_recipient_events event
                where event.organization_id = p_organization_id
                    and event.processed_at is not null
                    and event.normalized_kind = r.signal
                    and event.received_at >= r.window_start
                    and event.received_at <= p_at
            ) as event_count
        from resolved r
    ),
    rated as (
        select c.*,
            case when c.accepted_recipients > 0
                then round((100::numeric * c.event_count) / c.accepted_recipients, 4)
            end as rate
        from counted c
    )
    select
        rated.signal, rated.window_key, rated.window_hours, rated.window_start,
        rated.accepted_recipients, rated.event_count, rated.rate, rated.warn_rate, rated.pause_rate,
        rated.min_sample_recipients, rated.min_event_count,
        case
            when rated.rate is null then 'ok'
            when rated.rate >= rated.pause_rate
                and (
                    rated.accepted_recipients >= rated.min_sample_recipients
                    or (rated.min_event_count is not null and rated.event_count >= rated.min_event_count)
                ) then 'pause'
            when rated.rate >= rated.warn_rate then 'warn'
            else 'ok'
        end as status
    from rated
    order by rated.signal, rated.window_key;
$$;

alter function "private"."marketing_email_reputation_metrics"(uuid, timestamptz) owner to "postgres";
revoke all on function "private"."marketing_email_reputation_metrics"(uuid, timestamptz)
    from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- Engaging the pause
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."evaluate_marketing_email_reputation"(
    "p_organization_id" uuid,
    "p_at" timestamptz default now()
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    measured jsonb;
    breach jsonb;
    new_pause_id uuid;
    pause_reason text;
begin
    select coalesce(jsonb_agg(to_jsonb(m) order by m.signal, m.window_key), '[]'::jsonb)
    into measured
    from private.marketing_email_reputation_metrics(p_organization_id, p_at) m;

    select entry into breach
    from jsonb_array_elements(measured) entry
    where entry ->> 'status' = 'pause'
    order by ((entry ->> 'rate')::numeric / nullif((entry ->> 'pause_rate')::numeric, 0)) desc nulls last
    limit 1;

    if breach is null then
        return jsonb_build_object('organization_id', p_organization_id, 'paused', false, 'metrics', measured);
    end if;

    pause_reason := format(
        'Automatic Marketing pause: %s rate %s%% over the %s window is at or above the %s%% threshold (%s of %s recipients).',
        replace(breach ->> 'signal', '_', ' '), breach ->> 'rate',
        case breach ->> 'window_key' when 'rolling_24h' then 'rolling 24-hour' else 'rolling 7-day' end,
        breach ->> 'pause_rate', breach ->> 'event_count', breach ->> 'accepted_recipients'
    );

    -- The partial unique index on (organization_id, source) for live organization pauses makes a concurrent
    -- second drain a no-op instead of a duplicate pause.
    insert into public.communication_email_sending_pauses (
        scope, organization_id, reason, engaged_by_owner_email, source, applies_to, evidence
    ) values (
        'organization', p_organization_id, pause_reason, 'system', 'auto_marketing_reputation', 'marketing',
        jsonb_build_object('signal', breach ->> 'signal', 'window_key', breach ->> 'window_key',
            'rate', (breach ->> 'rate')::numeric, 'pause_rate', (breach ->> 'pause_rate')::numeric,
            'event_count', (breach ->> 'event_count')::bigint,
            'accepted_recipients', (breach ->> 'accepted_recipients')::bigint,
            'evaluated_at', p_at)
    )
    on conflict (organization_id, source) where (scope = 'organization' and released_at is null)
    do nothing
    returning id into new_pause_id;

    if new_pause_id is null then
        return jsonb_build_object('organization_id', p_organization_id, 'paused', true, 'metrics', measured);
    end if;

    insert into public.platform_owner_audit_events (
        actor_owner_email, event_type, target_type, target_key, after_state
    ) values (
        'system', 'communications.marketing_reputation_pause_engaged', 'organization',
        p_organization_id::text,
        jsonb_build_object('pause_id', new_pause_id, 'reason', pause_reason, 'metrics', measured)
    );

    return jsonb_build_object('organization_id', p_organization_id, 'paused', true,
        'pause_id', new_pause_id, 'metrics', measured);
end;
$$;

alter function "public"."evaluate_marketing_email_reputation"(uuid, timestamptz) owner to "postgres";
revoke all on function "public"."evaluate_marketing_email_reputation"(uuid, timestamptz)
    from public, anon, authenticated;
grant all on function "public"."evaluate_marketing_email_reputation"(uuid, timestamptz) to "service_role";

comment on function "public"."evaluate_marketing_email_reputation"(uuid, timestamptz) is
    'Measures one organization''s Marketing complaint and hard-bounce rates and engages a Marketing-only pause when a pause threshold is crossed. Never touches operational email or communication_email_reputation_state. Called by the Marketing event projector; service role only.';

-- ---------------------------------------------------------------------------------------------------
-- Resuming the pause (Jafar only)
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."resume_marketing_email_reputation_pause"(
    "p_organization_id" uuid,
    "p_reason" text,
    "p_actor_email" text,
    "p_confirm_remediation" boolean default false
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    actor text := lower(btrim(coalesce(p_actor_email, '')));
    clean_reason text := btrim(coalesce(p_reason, ''));
    existing public.communication_email_sending_pauses%rowtype;
    still_breaching boolean;
begin
    if char_length(actor) not between 3 and 320 then
        raise exception 'An owner email is required.' using errcode = 'check_violation';
    end if;
    if char_length(clean_reason) not between 3 and 500 then
        raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
    end if;

    select * into existing
    from public.communication_email_sending_pauses
    where scope = 'organization' and organization_id = p_organization_id
        and source = 'auto_marketing_reputation' and released_at is null
    for update;
    if not found then
        return jsonb_build_object('released', false, 'reason_code', 'no_active_marketing_reputation_pause');
    end if;

    select exists (
        select 1 from private.marketing_email_reputation_metrics(p_organization_id, now()) m
        where m.status = 'pause'
    ) into still_breaching;

    if still_breaching and not coalesce(p_confirm_remediation, false) then
        raise exception 'Marketing for this organization is still at or above a pause threshold. Confirm remediation review to resume.'
            using errcode = 'check_violation';
    end if;

    update public.communication_email_sending_pauses
    set released_at = now(), released_by_owner_email = actor, released_reason = clean_reason
    where id = existing.id;

    insert into public.platform_owner_audit_events (
        actor_owner_email, event_type, target_type, target_key, before_state, after_state
    ) values (
        actor, 'communications.marketing_reputation_pause_released', 'organization', p_organization_id::text,
        jsonb_build_object('pause_id', existing.id, 'engaged_reason', existing.reason,
            'evidence', existing.evidence),
        jsonb_build_object('released_reason', clean_reason, 'still_breaching', still_breaching,
            'confirmed_remediation', coalesce(p_confirm_remediation, false))
    );

    return jsonb_build_object('released', true, 'pause_id', existing.id, 'still_breaching', still_breaching);
end;
$$;

alter function "public"."resume_marketing_email_reputation_pause"(uuid, text, text, boolean) owner to "postgres";
revoke all on function "public"."resume_marketing_email_reputation_pause"(uuid, text, text, boolean)
    from public, anon, authenticated;
grant all on function "public"."resume_marketing_email_reputation_pause"(uuid, text, text, boolean)
    to "service_role";

-- ---------------------------------------------------------------------------------------------------
-- Jafar's per-organization reputation read: adds the Marketing measurements and pause
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."get_communication_email_reputation"("p_organization_id" uuid)
    returns jsonb
    language sql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
  select jsonb_build_object(
    'organization_id', p_organization_id,
    'measured_at', now(),
    'metrics', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.signal, m.window_key)
      from private.communication_email_reputation_metrics(p_organization_id, now()) m
    ), '[]'::jsonb),
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'signal', t.signal, 'window_key', t.window_key,
        'warn_rate', t.warn_rate, 'pause_rate', t.pause_rate,
        'min_sample_recipients', t.min_sample_recipients, 'min_event_count', t.min_event_count,
        'reason', t.reason, 'actor_owner_email', t.actor_owner_email,
        'effective_from', t.effective_from
      ) order by t.signal, t.window_key)
      from public.communication_email_reputation_thresholds t
      where t.scope = 'organization' and t.organization_id = p_organization_id and t.effective_to is null
    ), '[]'::jsonb),
    'reputation_pause', (
      select jsonb_build_object(
        'id', p.id, 'reason', p.reason, 'engaged_at', p.engaged_at, 'evidence', p.evidence
      )
      from public.communication_email_sending_pauses p
      where p.scope = 'organization' and p.organization_id = p_organization_id
        and p.source = 'auto_reputation' and p.released_at is null
      limit 1
    ),
    'state', (
      select jsonb_build_object(
        'worst_status', s.worst_status, 'evaluated_at', s.evaluated_at, 'last_breach_at', s.last_breach_at
      )
      from public.communication_email_reputation_state s
      where s.organization_id = p_organization_id
    ),
    'marketing_metrics', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.signal, m.window_key)
      from private.marketing_email_reputation_metrics(p_organization_id, now()) m
    ), '[]'::jsonb),
    'marketing_reputation_pause', (
      select jsonb_build_object(
        'id', p.id, 'reason', p.reason, 'engaged_at', p.engaged_at, 'evidence', p.evidence
      )
      from public.communication_email_sending_pauses p
      where p.scope = 'organization' and p.organization_id = p_organization_id
        and p.source = 'auto_marketing_reputation' and p.released_at is null
      limit 1
    )
  );
$$;

-- ---------------------------------------------------------------------------------------------------
-- Operational claim: a Marketing-only pause never holds operational email
-- ---------------------------------------------------------------------------------------------------

-- Unchanged from the baseline except the pause predicate, which used to let any non-'all' pause hold
-- optional operational email.
CREATE OR REPLACE FUNCTION "public"."claim_communication_outbox_event"() RETURNS TABLE("outbox_event_id" "uuid", "delivery_intent_id" "uuid", "claim_token" "uuid", "recipient_email" "text", "subject" "text", "html_content" "text", "text_content" "text", "logical_send_key" "text", "sender_id" "uuid", "sender_email" "text", "sender_name" "text", "reply_to_email" "text", "reply_to_name" "text")
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
      and (pause.applies_to = 'all'
        or (pause.applies_to = 'optional' and candidate.allowance_class = 'optional'))
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
$$;

-- ---------------------------------------------------------------------------------------------------
-- Marketing claim: organization-wide holds move into the candidate query
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."claim_marketing_campaign_recipient"()
returns table(
    "recipient_id" uuid,
    "campaign_id" uuid,
    "organization_id" uuid,
    "claim_token" uuid,
    "client_id" uuid,
    "client_contact_method_id" uuid,
    "recipient_email" text,
    "display_name" text
)
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public', 'private'
    as $$
declare
    candidate record;
    new_claim_token uuid;
    marketing_domain public.communication_email_domains;
    warmup_ceiling integer;
    warmup_used_today integer;
    blocked_reason text;
    today_start timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
begin
    if exists (
        select 1 from public.communication_email_sending_pauses
        where scope = 'platform' and released_at is null
    ) then
        return;
    end if;

    -- A campaign scheduled for a moment that has now arrived starts sending exactly the way an immediate
    -- launch already does; nothing else needs to change for it to become claimable.
    update public.marketing_campaigns
    set status = 'sending'
    where status = 'scheduled' and scheduled_for <= now();

    for candidate in
        select
            recipient.id as recipient_id,
            recipient.campaign_id,
            recipient.organization_id,
            recipient.client_id,
            recipient.client_contact_method_id,
            recipient.recipient_email,
            recipient.display_name
        from public.marketing_campaign_recipients recipient
        join public.marketing_campaigns campaign
            on campaign.id = recipient.campaign_id and campaign.organization_id = recipient.organization_id
        where campaign.status = 'sending' and recipient.status = 'waiting'
            -- Organization-wide holds are filtered here rather than skipped inside the loop: a held
            -- organization's queue ahead of everyone else's would otherwise fill all 50 candidate slots and
            -- starve every other organization's campaigns until the hold lifted.
            and not exists (
                select 1 from public.organizations org
                where org.id = recipient.organization_id and org.lifecycle_status = 'suspended'
            )
            and not exists (
                select 1 from public.organization_closure_records closure
                where closure.organization_id = recipient.organization_id
                    and closure.status in ('pending_closure', 'purge_in_progress')
            )
            -- Every live organization pause holds Marketing: manual, the operational reputation pause, and
            -- the Marketing-only reputation pause.
            and not exists (
                select 1 from public.communication_email_sending_pauses pause
                where pause.scope = 'organization'
                    and pause.organization_id = recipient.organization_id
                    and pause.released_at is null
            )
            and exists (
                select 1 from public.communication_email_domains domain
                where domain.organization_id = recipient.organization_id
                    and domain.purpose = 'marketing_sending'
                    and domain.lifecycle_state = 'verified'
            )
        order by campaign.launched_at, recipient.created_at, recipient.id
        limit 50
        for update of recipient skip locked
    loop
        blocked_reason := private.marketing_recipient_blocked_reason(
            candidate.organization_id, candidate.client_id, candidate.client_contact_method_id,
            candidate.recipient_email
        );
        if blocked_reason is not null then
            update public.marketing_campaign_recipients
            set status = 'excluded', excluded_reason = blocked_reason, updated_at = now()
            where id = candidate.recipient_id;
            continue;
        end if;

        marketing_domain := null;
        select domain.* into marketing_domain
        from public.communication_email_domains domain
        where domain.organization_id = candidate.organization_id
            and domain.purpose = 'marketing_sending'
            and domain.lifecycle_state = 'verified';

        if marketing_domain.id is null then
            -- The organization's Marketing identity is no longer ready; try again on the next wake.
            continue;
        end if;

        warmup_ceiling := private.resolve_communication_email_warmup_ceiling(
            candidate.organization_id, marketing_domain.id, now());
        if warmup_ceiling is not null then
            select count(*) into warmup_used_today
            from public.marketing_campaign_recipients mr
            where mr.organization_id = candidate.organization_id
                and (
                    (mr.status = 'checking' and mr.claimed_at >= today_start)
                    or (mr.submitted_at is not null and mr.submitted_at >= today_start)
                );

            if warmup_used_today + 1 > warmup_ceiling then
                continue;
            end if;
        end if;

        new_claim_token := gen_random_uuid();
        update public.marketing_campaign_recipients
        set status = 'checking', claim_token = new_claim_token, claimed_at = now(),
            attempt_count = attempt_count + 1, updated_at = now()
        where id = candidate.recipient_id;

        recipient_id := candidate.recipient_id;
        campaign_id := candidate.campaign_id;
        organization_id := candidate.organization_id;
        claim_token := new_claim_token;
        client_id := candidate.client_id;
        client_contact_method_id := candidate.client_contact_method_id;
        recipient_email := candidate.recipient_email;
        display_name := candidate.display_name;
        return next;
        return;
    end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Marketing event projector: re-measures an organization after it takes a complaint or hard bounce
-- ---------------------------------------------------------------------------------------------------

create or replace function "public"."project_marketing_campaign_recipient_events"(
    "batch_size" integer default 200
) returns integer
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    candidate record;
    norm text;
    bounce_kind text;
    processed_count integer := 0;
    max_processing_attempts constant integer := 5;
    recipient public.marketing_campaign_recipients;
    new_status text;
    reputation_organizations uuid[] := '{}';
    reputation_organization uuid;
begin
    if batch_size < 1 or batch_size > 2000 then
        raise exception 'The marketing event batch size is outside its safe bounds.'
            using errcode = 'check_violation';
    end if;

    for candidate in
        select event.id, event.event_kind, event.payload, event.occurred_at, event.received_at,
            event.processing_attempts, event.provider_message_id
        from public.marketing_campaign_recipient_events event
        where event.processed_at is null
        order by event.received_at, event.id
        limit batch_size
        for update of event skip locked
    loop
        norm := case candidate.event_kind
            when 'Send' then 'sent'
            when 'Delivery' then 'delivered'
            when 'Complaint' then 'complaint'
            when 'Reject' then 'rejected'
            when 'DeliveryDelay' then 'delayed'
            when 'Bounce' then (
                case candidate.payload -> 'bounce' ->> 'bounceType'
                    when 'Permanent' then 'hard_bounce'
                    else 'soft_bounce'
                end
            )
            else 'other'
        end;

        begin
            select * into recipient
            from public.marketing_campaign_recipients
            where provider_message_id = candidate.provider_message_id
            for update;

            if not found then
                -- The event arrived before the recipient's own finalize commit became visible, or names a
                -- message id this database never sent (a stray test send). Left unprocessed to retry on the
                -- next drain, capped like the operational processor so a permanently unknown id cannot spin
                -- forever.
                if candidate.processing_attempts + 1 >= max_processing_attempts then
                    update public.marketing_campaign_recipient_events
                    set processed_at = now(), normalized_kind = norm,
                        processing_attempts = candidate.processing_attempts + 1,
                        processing_error = 'No marketing_campaign_recipients row matches this provider_message_id.'
                    where id = candidate.id;
                else
                    update public.marketing_campaign_recipient_events
                    set processing_attempts = candidate.processing_attempts + 1
                    where id = candidate.id;
                end if;
                continue;
            end if;

            if norm = 'delivered' then
                update public.marketing_campaign_recipients
                set status = 'delivered', updated_at = now()
                where id = recipient.id and status not in ('bounced', 'complained', 'unsubscribed');
            elsif norm in ('hard_bounce', 'complaint') then
                new_status := case norm when 'hard_bounce' then 'bounced' else 'complained' end;
                update public.marketing_campaign_recipients
                set status = new_status, failure_code = 'ses_' || norm, updated_at = now()
                where id = recipient.id and status <> 'unsubscribed';

                bounce_kind := case norm when 'hard_bounce' then 'hard_bounce' else 'complaint' end;
                insert into public.communication_email_suppressions (
                    organization_id, recipient_email, reason, source, evidence
                ) values (
                    recipient.organization_id, recipient.recipient_email, bounce_kind, 'provider_callback',
                    jsonb_build_object(
                        'event_kind', candidate.event_kind,
                        'occurred_at', candidate.occurred_at,
                        'received_at', candidate.received_at,
                        'campaign_id', recipient.campaign_id,
                        'marketing_campaign_recipient_id', recipient.id
                    )
                )
                on conflict (organization_id, recipient_email, reason) where released_at is null
                do nothing;

                if not recipient.organization_id = any(reputation_organizations) then
                    reputation_organizations := reputation_organizations || recipient.organization_id;
                end if;
            elsif norm = 'rejected' then
                update public.marketing_campaign_recipients
                set status = 'failed', failure_code = 'ses_reject', updated_at = now()
                where id = recipient.id and status not in ('bounced', 'complained', 'unsubscribed');
            end if;
            -- soft_bounce, delayed, sent, other: logged only, SES retries a soft bounce on its own.

            update public.marketing_campaign_recipient_events
            set processed_at = now(), normalized_kind = norm, organization_id = recipient.organization_id
            where id = candidate.id;
            processed_count := processed_count + 1;
        exception
            when others then
                update public.marketing_campaign_recipient_events
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

    -- Each organization that took a complaint or hard bounce in this batch is re-measured once, after its
    -- events are projected. A failure here is logged rather than raised so it can never stall the event
    -- pipeline that also writes suppressions; the next complaint or bounce re-runs the evaluation.
    foreach reputation_organization in array reputation_organizations loop
        begin
            perform public.evaluate_marketing_email_reputation(reputation_organization, now());
        exception
            when others then
                raise warning 'Marketing reputation evaluation failed for organization %: %',
                    reputation_organization, sqlerrm;
        end;
    end loop;

    return processed_count;
end;
$$;
