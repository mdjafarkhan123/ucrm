-- Communications Part 7.3: the sending-pause spine.
--
-- A "stop sending" lever with two scopes:
--   * platform  -- an account-wide emergency pause (Brevo incident, reputation crisis, billing hold);
--   * organization -- one tenant frozen while a problem is investigated.
--
-- docs/contractor-email-contract.md
--   § Brevo and tenant isolation
--     "an account-wide emergency pause and organization-specific pauses"
--   § Queueing, retries, and history
--     "That command rechecks the current organization state and email pause ...
--      A temporary failure remains unclaimed and deferred"
--   § Platform Owner controls
--     "provider health, capacity, reconciliation, and emergency pause"
--     "Contractors ... cannot ... bypass an organization or platform pause."
--
-- A manual pause is a hard stop: it holds every send class (optional and protected-essential alike).
-- The softer optional-only auto-pause driven by reputation rates lands in slice 7.4 on top of this
-- table. Transport (the HTTP worker that calls Brevo) is still a stub; this is the claim-time gate it
-- will meet, verifiable now on the owner surfaces.

-- ---------------------------------------------------------------------------------------------------
-- 1. The pause ledger. One row per engage; releasing it stamps released_*. History is the rows.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_sending_pauses (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('platform', 'organization')),
  -- null for a platform pause; the frozen tenant for an organization pause.
  organization_id uuid references public.organizations(id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  engaged_by_owner_email text not null check (char_length(btrim(engaged_by_owner_email)) between 3 and 320),
  engaged_at timestamptz not null default now(),
  released_at timestamptz,
  released_by_owner_email text,
  released_reason text,
  constraint communication_email_sending_pauses_scope_org_check check (
    (scope = 'platform' and organization_id is null)
    or (scope = 'organization' and organization_id is not null)
  ),
  -- released_at, released_by, and released_reason are all set together or all null.
  constraint communication_email_sending_pauses_release_check check (
    num_nonnulls(released_at, released_by_owner_email, released_reason) in (0, 3)
  )
);

-- At most one live platform pause. Expression index on a constant: the partial predicate does the work.
create unique index communication_email_sending_pauses_active_platform_idx
  on public.communication_email_sending_pauses ((true))
  where scope = 'platform' and released_at is null;

-- At most one live pause per organization.
create unique index communication_email_sending_pauses_active_org_idx
  on public.communication_email_sending_pauses (organization_id)
  where scope = 'organization' and released_at is null;

-- The claim recheck: is THIS organization live-paused right now.
create index communication_email_sending_pauses_org_lookup_idx
  on public.communication_email_sending_pauses (organization_id)
  where scope = 'organization' and released_at is null;

-- Owner history list, newest engagement first.
create index communication_email_sending_pauses_history_idx
  on public.communication_email_sending_pauses (engaged_at desc, id desc);

-- Full foreign-key index. The partial indexes above lead with organization_id but exclude released
-- rows, so neither serves an organization cascade delete or a full-history lookup for one tenant.
create index communication_email_sending_pauses_organization_id_idx
  on public.communication_email_sending_pauses (organization_id)
  where organization_id is not null;

alter table public.communication_email_sending_pauses enable row level security;
revoke all on public.communication_email_sending_pauses from anon, authenticated;
grant select, insert, update on public.communication_email_sending_pauses to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 2. Engage / release a pause. Jafar-only: the owner API routes hold the service_role key, and no
--    contractor path reaches these. Every change writes an immutable owner audit event.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.set_communication_email_platform_pause(
  p_engage boolean,
  p_reason text,
  p_actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  existing public.communication_email_sending_pauses%rowtype;
  new_id uuid;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;

  -- Serialize concurrent toggles on the platform row.
  select * into existing
  from public.communication_email_sending_pauses
  where scope = 'platform' and released_at is null
  order by engaged_at desc
  for update;

  if p_engage then
    if found then
      return existing.id; -- already paused; the reason of record is the first one.
    end if;
    insert into public.communication_email_sending_pauses (scope, reason, engaged_by_owner_email)
    values ('platform', clean_reason, actor)
    returning id into new_id;
    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, after_state
    ) values (
      actor, 'communications.email_platform_pause_engaged', 'communication_email_sending_pause',
      new_id::text, jsonb_build_object('reason', clean_reason)
    );
    return new_id;
  end if;

  -- Release.
  if not found then
    return null; -- nothing paused.
  end if;
  update public.communication_email_sending_pauses
  set released_at = now(), released_by_owner_email = actor, released_reason = clean_reason
  where id = existing.id;
  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_platform_pause_released', 'communication_email_sending_pause',
    existing.id::text,
    jsonb_build_object('engaged_reason', existing.reason, 'engaged_by', existing.engaged_by_owner_email),
    jsonb_build_object('released_reason', clean_reason)
  );
  return existing.id;
end;
$$;

revoke all on function public.set_communication_email_platform_pause(boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.set_communication_email_platform_pause(boolean, text, text)
  to service_role;

create or replace function public.set_communication_email_organization_pause(
  p_organization_id uuid,
  p_engage boolean,
  p_reason text,
  p_actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  org_exists boolean;
  existing public.communication_email_sending_pauses%rowtype;
  new_id uuid;
begin
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;

  select true into org_exists from public.organizations where id = p_organization_id;
  if not found then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  select * into existing
  from public.communication_email_sending_pauses
  where scope = 'organization' and organization_id = p_organization_id and released_at is null
  order by engaged_at desc
  for update;

  if p_engage then
    if found then
      return existing.id;
    end if;
    insert into public.communication_email_sending_pauses (
      scope, organization_id, reason, engaged_by_owner_email
    )
    values ('organization', p_organization_id, clean_reason, actor)
    returning id into new_id;
    insert into public.platform_owner_audit_events (
      actor_owner_email, event_type, target_type, target_key, after_state
    ) values (
      actor, 'communications.email_organization_pause_engaged', 'organization',
      p_organization_id::text, jsonb_build_object('pause_id', new_id, 'reason', clean_reason)
    );
    return new_id;
  end if;

  if not found then
    return null;
  end if;
  update public.communication_email_sending_pauses
  set released_at = now(), released_by_owner_email = actor, released_reason = clean_reason
  where id = existing.id;
  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.email_organization_pause_released', 'organization',
    p_organization_id::text,
    jsonb_build_object('pause_id', existing.id, 'engaged_reason', existing.reason,
      'engaged_by', existing.engaged_by_owner_email),
    jsonb_build_object('released_reason', clean_reason)
  );
  return existing.id;
end;
$$;

revoke all on function public.set_communication_email_organization_pause(uuid, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.set_communication_email_organization_pause(uuid, boolean, text, text)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. One read for the Jafar email-health page: the live platform pause, every live org pause, and how
--    much queued mail is currently held.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_email_sending_health()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'platform_pause', (
      select jsonb_build_object(
        'id', p.id, 'reason', p.reason,
        'engaged_by', p.engaged_by_owner_email, 'engaged_at', p.engaged_at
      )
      from public.communication_email_sending_pauses p
      where p.scope = 'platform' and p.released_at is null
      order by p.engaged_at desc
      limit 1
    ),
    'organization_pauses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'organization_id', p.organization_id, 'organization_name', o.name,
        'reason', p.reason, 'engaged_by', p.engaged_by_owner_email, 'engaged_at', p.engaged_at
      ) order by p.engaged_at desc)
      from public.communication_email_sending_pauses p
      join public.organizations o on o.id = p.organization_id
      where p.scope = 'organization' and p.released_at is null
    ), '[]'::jsonb),
    'held_email_count', (
      select count(*)
      from public.communication_outbox_events e
      join public.communication_delivery_intents i on i.id = e.delivery_intent_id
      where e.status in ('pending', 'failed')
        and i.failure_code in ('sending_paused_platform', 'sending_paused_organization')
    ),
    'queued_email_count', (
      select count(*)
      from public.communication_outbox_events e
      where e.status in ('pending', 'failed')
    )
  );
$$;

revoke all on function public.get_communication_email_sending_health() from public, anon, authenticated;
grant execute on function public.get_communication_email_sending_health() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. The outbox claim honours both pauses. A platform pause makes claim a no-op -- the worker gets
--    nothing and retries later. An organization pause holds that tenant's rows: deferred, not
--    cancelled, annotated so the queue and the health page can explain the delay.
--    The rest of the body is migration 20260906180000's definition unchanged.
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

    -- Part 7.3: organization pause. The tenant's mail is held -- deferred, not cancelled -- and
    -- re-checked from scratch on every retry once the pause is released.
    if exists (
      select 1 from public.communication_email_sending_pauses pause
      where pause.scope = 'organization'
        and pause.organization_id = candidate.organization_id
        and pause.released_at is null
    ) then
      update public.communication_delivery_intents
      set failure_code = 'sending_paused_organization',
        failure_message = 'Sending for this organization is paused. UCRM will retry when it resumes.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = now() + interval '5 minutes',
        last_error = 'Sending for this organization is paused. UCRM will retry when it resumes.'
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
