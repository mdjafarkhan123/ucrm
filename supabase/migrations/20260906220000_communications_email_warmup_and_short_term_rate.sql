-- Communications Part 7.5a: warm-up ceilings for newly verified sending domains, and the
-- short-term per-organization sending rate. Both are enforced inside the atomic claim and both
-- DEFER a message that is over the limit -- they never cancel it. A deferred message waits and is
-- fully re-checked on its next attempt.
--
-- docs/contractor-email-contract.md § Warm-up and sending capacity:
--   "Newly verified domains use these editable defaults:
--      Days 1 through 3   -> 100 accepted recipients per day
--      Days 4 through 7   -> 250
--      Days 8 through 14  -> 500
--      After day 14       -> Organization limits"
--   "The default short-term organization limit is 100 recipients per 10 minutes. Valid operational
--    email over that limit is deferred with an estimated retry time."
--   "Jafar can edit platform defaults and organization values."
-- § Platform Owner controls: "warm-up stages ... reasoned, effective-dated overrides with
--   immutable history".
--
-- The per-organization provider-period capacity and the 10% platform reserve are slice 7.5b.
-- HTTP transport is still a stub; this is the database layer plus the owner surface it drives.
--
-- Shape follows the 7.4 reputation-threshold pattern exactly: append-only, effective-dated config
-- rows (a change closes the live row and inserts a successor, so the table IS the history), a
-- platform scope plus an organization scope that can only tighten, and a private resolver the
-- claim calls.

-- ---------------------------------------------------------------------------------------------------
-- 1. Warm-up stage ceilings. One live platform row per stage; an organization row overrides the
--    ceiling for that stage. The "after day 14" stage is not stored -- it means "organization
--    limits", which the claim already enforces.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_warmup_stages (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('platform', 'organization')),
  organization_id uuid references public.organizations(id) on delete cascade,
  stage_key text not null check (stage_key in ('days_1_3', 'days_4_7', 'days_8_14')),
  daily_ceiling integer not null check (daily_ceiling >= 0 and daily_ceiling <= 10000000),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  actor_owner_email text not null check (char_length(btrim(actor_owner_email)) between 3 and 320),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint communication_email_warmup_stages_scope_org_check check (
    (scope = 'platform' and organization_id is null)
    or (scope = 'organization' and organization_id is not null)
  ),
  constraint communication_email_warmup_stages_effective_range_check check (
    effective_to is null or effective_to > effective_from
  )
);

-- One live ceiling row per stage.
create unique index communication_email_warmup_stages_live_platform_idx
  on public.communication_email_warmup_stages (stage_key)
  where scope = 'platform' and effective_to is null;

-- One live override per organization and stage; also the resolver's lookup.
create unique index communication_email_warmup_stages_live_org_idx
  on public.communication_email_warmup_stages (organization_id, stage_key)
  where scope = 'organization' and effective_to is null;

-- One tenant's override history, newest first; also the organization cascade-delete path.
create index communication_email_warmup_stages_org_history_idx
  on public.communication_email_warmup_stages (organization_id, effective_from desc, id desc)
  where organization_id is not null;

alter table public.communication_email_warmup_stages enable row level security;
revoke all on public.communication_email_warmup_stages from anon, authenticated;
grant select, insert, update on public.communication_email_warmup_stages to service_role;

insert into public.communication_email_warmup_stages (
  scope, stage_key, daily_ceiling, reason, actor_owner_email
)
values
  ('platform', 'days_1_3', 100, 'Initial platform defaults from the contractor email contract.', 'system'),
  ('platform', 'days_4_7', 250, 'Initial platform defaults from the contractor email contract.', 'system'),
  ('platform', 'days_8_14', 500, 'Initial platform defaults from the contractor email contract.', 'system');

-- ---------------------------------------------------------------------------------------------------
-- 2. Platform-wide sending settings. One live row. 7.5b extends this row with provider-period
--    capacity and the reserve percentage.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_platform_sending_settings (
  id uuid primary key default gen_random_uuid(),
  -- Guarantees a single live row together with the partial unique index below.
  singleton_key boolean not null default true check (singleton_key),
  short_term_window_minutes integer not null check (short_term_window_minutes between 1 and 1440),
  short_term_max_recipients integer not null check (short_term_max_recipients between 1 and 10000000),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  actor_owner_email text not null check (char_length(btrim(actor_owner_email)) between 3 and 320),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint communication_email_platform_sending_settings_effective_range_check check (
    effective_to is null or effective_to > effective_from
  )
);

create unique index communication_email_platform_sending_settings_live_idx
  on public.communication_email_platform_sending_settings (singleton_key)
  where effective_to is null;

alter table public.communication_email_platform_sending_settings enable row level security;
revoke all on public.communication_email_platform_sending_settings from anon, authenticated;
grant select, insert, update on public.communication_email_platform_sending_settings to service_role;

insert into public.communication_email_platform_sending_settings (
  short_term_window_minutes, short_term_max_recipients, reason, actor_owner_email
)
values (10, 100, 'Initial platform defaults from the contractor email contract.', 'system');

-- ---------------------------------------------------------------------------------------------------
-- 3. Resolver: the warm-up ceiling for one sending domain right now, or null when the domain is
--    past day 14 (or has never been verified) and only organization limits apply.
--
--    The warm-up clock is warmup_started_at when a domain-lifecycle step-back has set it, otherwise
--    verified_at -- the moment the domain first became "newly verified". Day counting is by UTC
--    calendar day, matching how the provider meters a day.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.resolve_communication_email_warmup_ceiling(
  p_organization_id uuid,
  p_domain_id uuid,
  p_at timestamptz default now()
)
returns integer
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  warmup_clock timestamptz;
  elapsed_days integer;
  chosen_stage text;
  ceiling integer;
begin
  select coalesce(domain.warmup_started_at, domain.verified_at)
  into warmup_clock
  from public.communication_email_domains domain
  where domain.organization_id = p_organization_id
    and domain.id = p_domain_id;

  if warmup_clock is null or warmup_clock > p_at then
    return null;
  end if;

  elapsed_days := floor(extract(epoch from (p_at - warmup_clock)) / 86400.0)::integer;

  if elapsed_days < 3 then
    chosen_stage := 'days_1_3';
  elsif elapsed_days < 7 then
    chosen_stage := 'days_4_7';
  elsif elapsed_days < 14 then
    chosen_stage := 'days_8_14';
  else
    return null;
  end if;

  select coalesce(
    (
      select org_stage.daily_ceiling
      from public.communication_email_warmup_stages org_stage
      where org_stage.scope = 'organization'
        and org_stage.organization_id = p_organization_id
        and org_stage.stage_key = chosen_stage
        and org_stage.effective_from <= p_at
        and org_stage.effective_to is null
    ),
    (
      select platform_stage.daily_ceiling
      from public.communication_email_warmup_stages platform_stage
      where platform_stage.scope = 'platform'
        and platform_stage.stage_key = chosen_stage
        and platform_stage.effective_from <= p_at
        and platform_stage.effective_to is null
    )
  )
  into ceiling;

  return ceiling;
end;
$$;

revoke all on function private.resolve_communication_email_warmup_ceiling(uuid, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function private.resolve_communication_email_warmup_ceiling(uuid, uuid, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Resolver: the short-term rate for one organization. 7.5a returns the platform default; the
--    organization parameter is here so 7.5b/an organization page can layer a stricter override
--    without changing the claim.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.resolve_communication_email_short_term_rate(
  p_organization_id uuid,
  p_at timestamptz default now()
)
returns table (max_recipients integer, window_minutes integer)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select
    settings.short_term_max_recipients,
    settings.short_term_window_minutes
  from public.communication_email_platform_sending_settings settings
  where settings.effective_to is null
    and settings.effective_from <= p_at;
$$;

revoke all on function private.resolve_communication_email_short_term_rate(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function private.resolve_communication_email_short_term_rate(uuid, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. The claim gains the two checks. Everything else is migration 20260906200000's body unchanged.
--    Placement: after sender and domain eligibility (so a warm-up check has its domain) and before
--    the allowance resolution, because both new checks defer rather than cancel and are cheaper to
--    evaluate than the allowance path.
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
-- 6. Owner read: the platform sending-capacity surface.
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
-- 7. Owner write: change a platform warm-up ceiling. Closes the live row and inserts a successor, so
--    the table is the immutable history. Requires explicit confirmation -- it is a platform safety
--    setting -- and records the change in the owner audit log.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.set_communication_email_warmup_stage(
  p_stage_key text,
  p_daily_ceiling integer,
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
  live public.communication_email_warmup_stages%rowtype;
  new_id uuid;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if p_stage_key not in ('days_1_3', 'days_4_7', 'days_8_14') then
    raise exception 'The warm-up stage is invalid.' using errcode = 'check_violation';
  end if;
  if p_daily_ceiling is null or p_daily_ceiling < 0 or p_daily_ceiling > 10000000 then
    raise exception 'A daily ceiling of 0 to 10,000,000 is required.' using errcode = 'check_violation';
  end if;
  if not coalesce(p_confirm_platform_change, false) then
    raise exception 'Changing a platform warm-up ceiling requires explicit confirmation.'
      using errcode = 'check_violation';
  end if;

  select * into live
  from public.communication_email_warmup_stages
  where scope = 'platform' and stage_key = p_stage_key and effective_to is null
  for update;
  if not found then
    raise exception 'No platform warm-up ceiling exists for that stage.'
      using errcode = 'foreign_key_violation';
  end if;

  update public.communication_email_warmup_stages
  set effective_to = now() where id = live.id;

  insert into public.communication_email_warmup_stages (
    scope, stage_key, daily_ceiling, reason, actor_owner_email
  ) values (
    'platform', p_stage_key, p_daily_ceiling, clean_reason, actor
  )
  returning id into new_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_warmup_stage_changed',
    'communication_email_warmup_stage', new_id::text,
    to_jsonb(live) - 'id',
    jsonb_build_object('stage_key', p_stage_key, 'daily_ceiling', p_daily_ceiling, 'reason', clean_reason)
  );

  return jsonb_build_object('id', new_id, 'stage_key', p_stage_key, 'daily_ceiling', p_daily_ceiling);
end;
$$;

revoke all on function public.set_communication_email_warmup_stage(text, integer, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.set_communication_email_warmup_stage(text, integer, text, text, boolean)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 8. Owner write: change the short-term sending rate. Same append-only, confirm-required shape.
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
    short_term_window_minutes, short_term_max_recipients, reason, actor_owner_email
  ) values (
    p_window_minutes, p_max_recipients, clean_reason, actor
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
