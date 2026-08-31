-- Communications Part 7.1: turn raw Brevo callback events into delivery outcomes and an auditable
-- suppression list, and make the outbox claim refuse a suppressed recipient.
--
-- docs/contractor-email-contract.md
--   § Preferences, consent, and suppressions
--     "A complaint immediately suppresses non-security mail from that organization. A hard bounce
--      prevents further sending until the address is corrected and verified. UCRM owns an auditable
--      suppression record and reconciles it with Brevo."
--   § Queueing, retries, and history
--     "Recheck recipients, permissions, status, ..., suppression, allowance, and sender eligibility
--      immediately before sending."
--
-- Transport (the HTTP worker that calls Brevo) is still a stub, exactly as it was when the allowance
-- layer landed. This is the database layer it will meet. The processor is pure SQL, so pg_cron runs it
-- directly -- no worker route, no new Vault secret.

-- ---------------------------------------------------------------------------------------------------
-- 1. Suppression list. One active row per (organization, address, reason); a released row is history.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_suppressions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Stored in the same normalized form enqueue_communication_email writes: lower(trim(address)).
  recipient_email text not null check (position('@' in recipient_email) > 1),
  reason text not null check (reason in ('complaint', 'hard_bounce')),
  source text not null default 'provider_callback' check (source in ('provider_callback', 'manual')),
  source_callback_event_id uuid references public.communication_provider_callback_events(id) on delete set null,
  first_delivery_intent_id uuid references public.communication_delivery_intents(id) on delete set null,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence) = 'object'),
  created_by_owner_email text,
  created_at timestamptz not null default now(),
  released_at timestamptz,
  released_by_owner_email text,
  released_reason text,
  constraint communication_email_suppressions_release_check check (
    (released_at is null) = (released_reason is null)
  )
);

-- Enforces "one live suppression per address per reason" and is the arbiter the processor's
-- ON CONFLICT below infers. A complaint and a hard bounce can both be live for the same address.
create unique index communication_email_suppressions_active_idx
  on public.communication_email_suppressions (organization_id, recipient_email, reason)
  where released_at is null;

-- The claim recheck: is THIS address live-suppressed for this org, and for which reasons.
create index communication_email_suppressions_lookup_idx
  on public.communication_email_suppressions (organization_id, recipient_email)
  where released_at is null;

-- Contractor "blocked addresses" list read (7.2) and owner review, newest first.
create index communication_email_suppressions_org_created_idx
  on public.communication_email_suppressions (organization_id, created_at desc, id desc);

-- Foreign-key indexes: both references are nullable and set-null on delete, so an index keeps that
-- cleanup and any lookup off a sequential scan.
create index communication_email_suppressions_callback_event_idx
  on public.communication_email_suppressions (source_callback_event_id)
  where source_callback_event_id is not null;
create index communication_email_suppressions_intent_idx
  on public.communication_email_suppressions (first_delivery_intent_id)
  where first_delivery_intent_id is not null;

alter table public.communication_email_suppressions enable row level security;
revoke all on public.communication_email_suppressions from anon, authenticated;
grant select, insert, update on public.communication_email_suppressions to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 2. The raw callback sink gains a processed marker, a normalized kind, and a resolved organization
--    so downstream reads (reputation rollups in 7.4) never have to re-join through the intent.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_provider_callback_events
  add column organization_id uuid references public.organizations(id) on delete cascade,
  add column processed_at timestamptz,
  add column normalized_kind text check (normalized_kind in (
    'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked',
    'unsubscribed', 'opened', 'clicked', 'other'
  ));

-- The processor's claim: oldest unprocessed first.
create index communication_provider_callback_events_unprocessed_idx
  on public.communication_provider_callback_events (received_at, id)
  where processed_at is null;

-- 7.4 reputation windows: complaint / bounce / unsubscribe counts per org over a rolling period.
create index communication_provider_callback_events_org_kind_time_idx
  on public.communication_provider_callback_events (organization_id, normalized_kind, occurred_at desc)
  where organization_id is not null and processed_at is not null;

-- ---------------------------------------------------------------------------------------------------
-- 3. Post-acceptance outcome on the delivery intent. This is a different axis from `status`
--    (queued -> claimed -> submitted): it is what the provider told us happened after submission.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_delivery_intents
  add column delivery_outcome text check (delivery_outcome in (
    'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked', 'unsubscribed'
  )),
  add column delivery_outcome_at timestamptz,
  add column delivery_outcome_detail text;

-- ---------------------------------------------------------------------------------------------------
-- 4. The processor. Bounded, idempotent (processed_at gate), SKIP LOCKED so a second run never waits.
--    Pure SQL side effects only -- no external calls -- so pg_cron can run it directly.
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

    -- No resolved intent (a callback with no ucrm tag, or one that arrived before its intent): mark it
    -- processed so it stops being claimed, but leave its organization unresolved. Nothing downstream
    -- counts an event with a null organization.
    if candidate.delivery_intent_id is null or candidate.organization_id is null then
      update public.communication_provider_callback_events
      set processed_at = now(), normalized_kind = norm
      where id = candidate.id;
      processed_count := processed_count + 1;
      continue;
    end if;

    -- Latest provider word wins, except a terminal outcome (hard bounce / complaint) is only ever
    -- replaced by another terminal outcome -- a stray later 'delivered' never un-bounces a message.
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

    -- Complaint and hard bounce open an auditable suppression. A row already live for this
    -- (organization, address, reason) is left untouched -- its evidence is the first one we saw.
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
    end if;

    update public.communication_provider_callback_events
    set processed_at = now(), normalized_kind = norm, organization_id = candidate.organization_id
    where id = candidate.id;
    processed_count := processed_count + 1;
  end loop;

  return processed_count;
end;
$$;

revoke all on function public.process_communication_provider_callbacks(integer) from public, anon, authenticated;
grant execute on function public.process_communication_provider_callbacks(integer) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. The outbox claim rechecks suppression, fail-closed, before it reserves allowance capacity.
--    A hard bounce blocks every send to the address; a complaint blocks optional (non-essential) mail
--    only -- requested quotes, invoices, receipts, security notices and direct replies still go
--    (docs/contractor-email-contract.md § Preferences, consent, and suppressions).
--    The rest of the body is the current definition unchanged.
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
begin
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
-- 6. Run the processor every two minutes. It is pure SQL, so pg_cron invokes it directly. Suppression
--    latency of at most one interval before the next send attempt is well inside the contract's
--    "immediately suppresses" intent for a queue that retries on 15-minute steps.
-- ---------------------------------------------------------------------------------------------------

create extension if not exists pg_cron;

select cron.schedule(
  'communications-provider-callback-processor',
  '*/2 * * * *',
  $cron$ select public.process_communication_provider_callbacks(500); $cron$
);
