-- Communications Part 7.5b: the platform-wide provider-period sending capacity and the essential
-- reserve, enforced inside the atomic claim. Like every other claim check it DEFERS a message that is
-- over the line -- it never cancels it -- and re-checks it in full on the next attempt.
--
-- docs/contractor-email-contract.md
--   § Warm-up and sending capacity:
--     "Jafar configures total provider-period capacity. Ten percent is reserved by default for
--      platform/system mail and protected essential contractor mail. Jafar can edit both values.
--      Ordinary organization mail cannot consume the protected platform reserve."
--   § Package allowances and counting:
--     "Optional email pauses at the normal allowance. The protected reserve permits requested quotes,
--      invoices, receipts, security notices, and direct human replies. If the reserve is exhausted,
--      queue essential mail temporarily, warn the organization, and alert Jafar."
--   § Platform Owner controls: "reasoned, effective-dated overrides with immutable history".
--
-- Standard ESP pattern: the provider meters a plan quota per calendar month, so the platform tracks a
-- single running total of accepted recipients per UTC month and fences off a percentage of the quota
-- for essential mail. Ordinary ('optional') mail stops at capacity minus the reserve; essential mail
-- may spend the reserve but still stops at the full capacity.
--
-- The per-claim check must NOT sum communication_email_usage_events for the whole month across every
-- tenant -- that table grows with total platform volume. Instead an AFTER INSERT trigger keeps a
-- maintained monthly counter (one row per month), and the claim reads that row by primary key plus a
-- bounded sum of only the currently in-flight reservations. The counter is a hot single row; at the
-- expected volume (well under tens of finalizations per second) its row-lock contention is negligible.
-- Threshold to revisit with a sharded counter: sustained thousands of finalizations per second.
--
-- HTTP transport is still a stub; this is the database layer plus the owner surface it drives.

-- ---------------------------------------------------------------------------------------------------
-- 1. The maintained monthly counter. One row per UTC calendar month, created on the month's first
--    accepted send and then incremented in place. Accepted recipients only ever grow within a month
--    (a provider-accepted message counts even if it later bounces), so there is no decrement path.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_platform_period_usage (
  period_start timestamptz primary key,
  period_end timestamptz not null,
  accepted_recipients bigint not null default 0 check (accepted_recipients >= 0),
  updated_at timestamptz not null default now(),
  constraint communication_email_platform_period_usage_range_check check (period_end > period_start)
);

alter table public.communication_email_platform_period_usage enable row level security;
revoke all on public.communication_email_platform_period_usage from anon, authenticated;
grant select, insert, update on public.communication_email_platform_period_usage to service_role;

-- Seed the current and historical months from the usage already recorded, so the check is accurate
-- from the first claim after this migration.
insert into public.communication_email_platform_period_usage (period_start, period_end, accepted_recipients)
select
  date_trunc('month', usage.occurred_at at time zone 'UTC') at time zone 'UTC',
  (date_trunc('month', usage.occurred_at at time zone 'UTC') + interval '1 month') at time zone 'UTC',
  sum(usage.recipient_count)
from public.communication_email_usage_events usage
group by 1, 2
on conflict (period_start) do update
  set accepted_recipients = excluded.accepted_recipients, updated_at = now();

create or replace function private.accrue_platform_email_period_usage()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  bucket_start timestamptz := date_trunc('month', new.occurred_at at time zone 'UTC') at time zone 'UTC';
begin
  insert into public.communication_email_platform_period_usage (
    period_start, period_end, accepted_recipients
  ) values (
    bucket_start,
    (date_trunc('month', new.occurred_at at time zone 'UTC') + interval '1 month') at time zone 'UTC',
    new.recipient_count
  )
  on conflict (period_start) do update
    set accepted_recipients =
          public.communication_email_platform_period_usage.accepted_recipients + excluded.accepted_recipients,
        updated_at = now();
  return null;
end;
$$;

revoke all on function private.accrue_platform_email_period_usage() from public, anon, authenticated;

-- communication_email_usage_events is inserted once per delivery intent (unique key + ON CONFLICT DO
-- NOTHING), so this AFTER INSERT trigger fires exactly once per accepted message.
create trigger communication_email_usage_events_accrue_platform_period
after insert on public.communication_email_usage_events
for each row execute function private.accrue_platform_email_period_usage();

-- ---------------------------------------------------------------------------------------------------
-- 2. Extend the single-live-row platform sending settings with the provider-period capacity and the
--    reserve percentage. Capacity is nullable: until Jafar enters a real provider plan number the
--    whole check is skipped, so nothing changes for existing sends.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_email_platform_sending_settings
  add column provider_period_capacity integer
    check (provider_period_capacity is null or provider_period_capacity between 1 and 1000000000),
  add column reserve_percent integer not null default 10
    check (reserve_percent between 0 and 100);

-- ---------------------------------------------------------------------------------------------------
-- 3. Resolver: the live provider-period capacity and reserve percentage. Mirrors the 7.5a resolvers;
--    returns a null capacity when Jafar has set none.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.resolve_communication_email_provider_capacity(
  p_at timestamptz default now()
)
returns table (capacity integer, reserve_percent integer)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select settings.provider_period_capacity, settings.reserve_percent
  from public.communication_email_platform_sending_settings settings
  where settings.effective_to is null
    and settings.effective_from <= p_at;
$$;

revoke all on function private.resolve_communication_email_provider_capacity(timestamptz)
  from public, anon, authenticated;
grant execute on function private.resolve_communication_email_provider_capacity(timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. The claim gains the provider-period capacity check. Everything else is migration 20260906220000's
--    body unchanged. Placement: right after the 7.5a short-term rate check and before the per-org
--    allowance path, because it is a primary-key read plus a small bounded sum, it defers rather than
--    cancels, and a platform-level ceiling should short-circuit before the per-org bucket lock.
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

    -- Part 7.1: suppression recheck. Fail-closed and never retried -- a suppressed address is cleared
    -- by a person (7.2), not by waiting.
    if exists (
      select 1
      from public.communication_email_suppressions suppression
      where suppression.organization_id = candidate.organization_id
        and suppression.recipient_email = candidate.recipient_email
        and suppression.released_at is null
        and (
          suppression.reason = 'hard_bounce'
          or (suppression.reason = 'complaint' and candidate.allowance_class = 'optional')
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
      set available_at = now() + interval '5 minutes', last_error = hold_message
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
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
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
        set available_at = today_start + interval '1 day',
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
        set available_at = short_term_retry_at,
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
        set available_at = now() + interval '15 minutes', last_error = hold_message
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
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
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
      update public.communication_outbox_events set available_at = now() + interval '15 minutes',
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
        update public.communication_outbox_events set available_at = now() + interval '15 minutes',
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
-- 5. Owner read: fold the provider-period capacity into the sending-capacity overview.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_email_sending_capacity_overview()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'warmup_stages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', stage.id, 'stage_key', stage.stage_key, 'daily_ceiling', stage.daily_ceiling,
        'reason', stage.reason, 'actor_owner_email', stage.actor_owner_email,
        'effective_from', stage.effective_from
      ) order by array_position(
        array['days_1_3', 'days_4_7', 'days_8_14']::text[], stage.stage_key))
      from public.communication_email_warmup_stages stage
      where stage.scope = 'platform' and stage.effective_to is null
    ), '[]'::jsonb),
    'short_term', (
      select jsonb_build_object(
        'id', settings.id,
        'window_minutes', settings.short_term_window_minutes,
        'max_recipients', settings.short_term_max_recipients,
        'reason', settings.reason, 'actor_owner_email', settings.actor_owner_email,
        'effective_from', settings.effective_from
      )
      from public.communication_email_platform_sending_settings settings
      where settings.effective_to is null
    ),
    'provider_capacity', (
      select jsonb_build_object(
        'capacity', settings.provider_period_capacity,
        'reserve_percent', settings.reserve_percent,
        'reserve_recipients', case
          when settings.provider_period_capacity is null then null
          else ceil(settings.provider_period_capacity::numeric * settings.reserve_percent / 100.0)::integer
        end,
        'reason', settings.reason,
        'actor_owner_email', settings.actor_owner_email,
        'effective_from', settings.effective_from,
        'period_start', date_trunc('month', now() at time zone 'UTC') at time zone 'UTC',
        'period_end', (date_trunc('month', now() at time zone 'UTC') + interval '1 month') at time zone 'UTC',
        'period_accepted', coalesce((
          select usage.accepted_recipients
          from public.communication_email_platform_period_usage usage
          where usage.period_start = date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'
        ), 0),
        'period_reserved', coalesce((
          select sum(reservation.recipient_count)
          from public.communication_email_capacity_reservations reservation
          where reservation.reservation_state in ('reserved', 'submission_unknown')
            and reservation.reserved_at >= date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'
        ), 0)
      )
      from public.communication_email_platform_sending_settings settings
      where settings.effective_to is null
    ),
    'domains_warming_up', (
      select count(*)
      from public.communication_email_domains domain
      where domain.purpose = 'sending'
        and domain.lifecycle_state = 'verified'
        and coalesce(domain.warmup_started_at, domain.verified_at) is not null
        and coalesce(domain.warmup_started_at, domain.verified_at) > now() - interval '14 days'
    )
  );
$$;

revoke all on function public.get_communication_email_sending_capacity_overview()
  from public, anon, authenticated;
grant execute on function public.get_communication_email_sending_capacity_overview() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 6. Owner write: set the provider-period capacity and reserve. Same append-only, confirm-required
--    shape as the 7.5a commands -- closes the live settings row and inserts a successor carrying the
--    short-term values forward, so the table stays the immutable history.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.set_communication_email_provider_capacity(
  p_capacity integer,
  p_reserve_percent integer,
  p_reason text,
  p_actor_email text,
  p_confirm_platform_change boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  live public.communication_email_platform_sending_settings%rowtype;
  new_id uuid;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if p_capacity is not null and (p_capacity < 1 or p_capacity > 1000000000) then
    raise exception 'A provider-period capacity of 1 to 1,000,000,000 recipients is required, or none to turn the limit off.'
      using errcode = 'check_violation';
  end if;
  if p_reserve_percent is null or p_reserve_percent < 0 or p_reserve_percent > 100 then
    raise exception 'A reserve of 0 to 100 percent is required.' using errcode = 'check_violation';
  end if;
  if not coalesce(p_confirm_platform_change, false) then
    raise exception 'Changing the provider-period sending capacity requires explicit confirmation.'
      using errcode = 'check_violation';
  end if;

  select * into live
  from public.communication_email_platform_sending_settings
  where effective_to is null
  for update;
  if not found then
    raise exception 'No live platform sending settings row exists.'
      using errcode = 'foreign_key_violation';
  end if;

  update public.communication_email_platform_sending_settings
  set effective_to = now() where id = live.id;

  insert into public.communication_email_platform_sending_settings (
    short_term_window_minutes, short_term_max_recipients,
    provider_period_capacity, reserve_percent, reason, actor_owner_email
  ) values (
    live.short_term_window_minutes, live.short_term_max_recipients,
    p_capacity, p_reserve_percent, clean_reason, actor
  )
  returning id into new_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_provider_capacity_changed',
    'communication_email_platform_sending_settings', new_id::text,
    to_jsonb(live) - 'id',
    jsonb_build_object('provider_period_capacity', p_capacity, 'reserve_percent', p_reserve_percent,
      'reason', clean_reason)
  );

  return jsonb_build_object('id', new_id, 'provider_period_capacity', p_capacity,
    'reserve_percent', p_reserve_percent);
end;
$$;

revoke all on function public.set_communication_email_provider_capacity(integer, integer, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.set_communication_email_provider_capacity(integer, integer, text, text, boolean)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 7. The 7.5a short-term rate command must now carry the provider-period columns forward when it
--    writes its successor row, or changing the rate would silently clear a configured capacity.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.set_communication_email_short_term_rate(
  p_window_minutes integer,
  p_max_recipients integer,
  p_reason text,
  p_actor_email text,
  p_confirm_platform_change boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  live public.communication_email_platform_sending_settings%rowtype;
  new_id uuid;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if p_window_minutes is null or p_window_minutes < 1 or p_window_minutes > 1440 then
    raise exception 'A window of 1 to 1440 minutes is required.' using errcode = 'check_violation';
  end if;
  if p_max_recipients is null or p_max_recipients < 1 or p_max_recipients > 10000000 then
    raise exception 'A recipient ceiling of 1 to 10,000,000 is required.' using errcode = 'check_violation';
  end if;
  if not coalesce(p_confirm_platform_change, false) then
    raise exception 'Changing the short-term sending rate requires explicit confirmation.'
      using errcode = 'check_violation';
  end if;

  select * into live
  from public.communication_email_platform_sending_settings
  where effective_to is null
  for update;
  if not found then
    raise exception 'No live platform sending settings row exists.'
      using errcode = 'foreign_key_violation';
  end if;

  update public.communication_email_platform_sending_settings
  set effective_to = now() where id = live.id;

  insert into public.communication_email_platform_sending_settings (
    short_term_window_minutes, short_term_max_recipients,
    provider_period_capacity, reserve_percent, reason, actor_owner_email
  ) values (
    p_window_minutes, p_max_recipients,
    live.provider_period_capacity, live.reserve_percent, clean_reason, actor
  )
  returning id into new_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_short_term_rate_changed',
    'communication_email_platform_sending_settings', new_id::text,
    to_jsonb(live) - 'id',
    jsonb_build_object('window_minutes', p_window_minutes, 'max_recipients', p_max_recipients,
      'reason', clean_reason)
  );

  return jsonb_build_object('id', new_id, 'window_minutes', p_window_minutes,
    'max_recipients', p_max_recipients);
end;
$$;

revoke all on function public.set_communication_email_short_term_rate(integer, integer, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.set_communication_email_short_term_rate(integer, integer, text, text, boolean)
  to service_role;
