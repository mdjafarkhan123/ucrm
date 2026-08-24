-- Communications Part 2B-B: reserve one recipient slot before a worker can make an
-- external provider call. A reservation is settled only after the provider outcome is
-- known, so concurrent workers cannot oversubscribe an organization's period.

alter table public.communication_delivery_intents
  add column allowance_class text not null default 'optional'
    check (allowance_class in ('optional', 'essential'));

alter table public.communication_email_usage_events
  add column allowance_period_id uuid references public.communication_email_allowance_periods(id) on delete restrict,
  add column allowance_class text check (allowance_class in ('optional', 'essential'));

create index communication_email_usage_events_capacity_idx
  on public.communication_email_usage_events (organization_id, allowance_period_id, allowance_class);
create index communication_email_usage_events_allowance_period_idx
  on public.communication_email_usage_events (allowance_period_id);

create table public.communication_email_capacity_buckets (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  allowance_period_id uuid not null references public.communication_email_allowance_periods(id) on delete cascade,
  allowance_class text not null check (allowance_class in ('optional', 'essential')),
  created_at timestamptz not null default now(),
  primary key (organization_id, allowance_period_id, allowance_class)
);

create table public.communication_email_capacity_reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  delivery_intent_id uuid not null references public.communication_delivery_intents(id) on delete cascade,
  allowance_period_id uuid not null references public.communication_email_allowance_periods(id) on delete restrict,
  allowance_class text not null check (allowance_class in ('optional', 'essential')),
  recipient_count integer not null default 1 check (recipient_count > 0),
  reservation_state text not null default 'reserved'
    check (reservation_state in ('reserved', 'released', 'accepted', 'submission_unknown')),
  reserved_at timestamptz not null default now(),
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_email_capacity_reservations_delivery_intent_key unique (delivery_intent_id)
);

create index communication_email_capacity_buckets_allowance_period_idx
  on public.communication_email_capacity_buckets (allowance_period_id);
create index communication_email_capacity_reservations_organization_idx
  on public.communication_email_capacity_reservations (organization_id);
create index communication_email_capacity_reservations_allowance_period_idx
  on public.communication_email_capacity_reservations (allowance_period_id);

create index communication_email_capacity_reservations_active_idx
  on public.communication_email_capacity_reservations (
    organization_id, allowance_period_id, allowance_class
  ) where reservation_state in ('reserved', 'submission_unknown');

create trigger communication_email_capacity_reservations_set_updated_at
before update on public.communication_email_capacity_reservations
for each row execute function public.set_updated_at();

alter table public.communication_email_capacity_buckets enable row level security;
alter table public.communication_email_capacity_reservations enable row level security;
revoke all on public.communication_email_capacity_buckets, public.communication_email_capacity_reservations
  from anon, authenticated;
grant select, insert, update on public.communication_email_capacity_buckets,
  public.communication_email_capacity_reservations to service_role;

create or replace function public.claim_communication_outbox_event()
returns table (
  outbox_event_id uuid,
  delivery_intent_id uuid,
  claim_token uuid,
  recipient_email text,
  subject text,
  html_content text,
  text_content text,
  logical_send_key text,
  sender_id uuid,
  sender_email text,
  sender_name text
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  current_recipient public.client_contact_methods;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  contact_owner_id uuid;
  active_allowance record;
  allowance_limit_state text;
  allowance_limit_value integer;
  accepted_recipient_count integer;
  reserved_recipient_count integer;
  new_claim_token uuid;
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

    selected_sender := null;
    if candidate.sender_id is not null then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id and sender.id = candidate.sender_id
      for share;
    elsif candidate.send_kind = 'automated' then
      select client.owner_user_id into contact_owner_id
      from public.clients client
      where client.organization_id = candidate.organization_id and client.id = candidate.client_id
      for share;
      if contact_owner_id is not null then
        select sender.* into selected_sender
        from public.communication_email_senders sender
        where sender.organization_id = candidate.organization_id
          and sender.assigned_user_id = contact_owner_id and sender.lifecycle_state <> 'removed'
        order by sender.created_at, sender.id limit 1 for share;
      else
        select sender.* into selected_sender
        from public.communication_email_senders sender
        where sender.organization_id = candidate.organization_id
          and sender.is_organization_default and sender.lifecycle_state <> 'removed'
        order by sender.created_at, sender.id limit 1 for share;
      end if;
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

    new_claim_token := gen_random_uuid();
    update public.communication_outbox_events set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null where id = candidate.event_id;
    update public.communication_delivery_intents set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null where id = candidate.delivery_intent_id;
    return query select candidate.event_id, candidate.delivery_intent_id, new_claim_token,
      candidate.recipient_email, candidate.subject, candidate.html_content, candidate.text_content,
      candidate.logical_send_key, selected_sender.id, selected_sender.email_address, selected_sender.display_name;
    return;
  end loop;
end;
$$;

create or replace function public.finalize_communication_outbox_event(
  target_outbox_event_id uuid,
  target_claim_token uuid,
  target_outcome text,
  target_provider_message_id text default null,
  target_failure_code text default null,
  target_failure_message text default null
)
returns table (
  outbox_status text,
  intent_status text,
  attempt_count integer,
  available_at timestamptz,
  usage_recorded boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed_event public.communication_outbox_events;
  reservation public.communication_email_capacity_reservations;
  next_available_at timestamptz;
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
    update public.communication_outbox_events set status = 'failed', available_at = next_available_at, claimed_at = null,
      claim_token = null, finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;
  elsif target_outcome = 'submission_unknown' then
    update public.communication_delivery_intents set status = 'submission_unknown', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''), failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;
    if reservation.id is not null then update public.communication_email_capacity_reservations
      set reservation_state = 'submission_unknown', settled_at = now() where id = reservation.id; end if;
    update public.communication_outbox_events set status = 'submission_unknown', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '') where id = claimed_event.id;
  else
    update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''), failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;
    if reservation.id is not null then update public.communication_email_capacity_reservations
      set reservation_state = 'released', settled_at = now() where id = reservation.id; end if;
    update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = nullif(trim(target_failure_message), '') where id = claimed_event.id;
  end if;
  return query select event.status, intent.status, event.attempt_count, event.available_at,
    exists (select 1 from public.communication_email_usage_events usage where usage.delivery_intent_id = event.delivery_intent_id)
  from public.communication_outbox_events event join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
  where event.id = claimed_event.id;
end;
$$;

create or replace function public.quarantine_stale_communication_claims(
  batch_size integer default 50,
  stale_after interval default interval '15 minutes'
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare quarantined_count integer;
begin
  if batch_size < 1 or batch_size > 100 then
    raise exception 'The stale communication batch is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if stale_after < interval '1 minute' or stale_after > interval '1 day' then
    raise exception 'The stale communication threshold is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  with stale as (
    select id from public.communication_outbox_events where status = 'processing' and claimed_at <= now() - stale_after
    order by claimed_at, id limit batch_size for update skip locked
  ), quarantined as (
    update public.communication_outbox_events event set status = 'submission_unknown', finalized_claim_token = event.claim_token,
      claimed_at = null, claim_token = null, last_error = 'The worker lease expired before its provider outcome was recorded.'
    from stale where event.id = stale.id returning event.delivery_intent_id
  ), updated_reservations as (
    update public.communication_email_capacity_reservations reservation set reservation_state = 'submission_unknown', settled_at = now()
    from quarantined where reservation.delivery_intent_id = quarantined.delivery_intent_id
      and reservation.reservation_state = 'reserved' returning reservation.delivery_intent_id
  ), updated_intents as (
    update public.communication_delivery_intents intent set status = 'submission_unknown', failure_code = 'worker_lease_expired',
      failure_message = 'The worker lease expired before its provider outcome was recorded.'
    from quarantined where intent.id = quarantined.delivery_intent_id returning intent.id
  ) select count(*)::integer into quarantined_count from updated_intents;
  return quarantined_count;
end;
$$;

revoke all on function public.claim_communication_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_outbox_event() to service_role;
revoke all on function public.finalize_communication_outbox_event(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_communication_outbox_event(uuid, uuid, text, text, text, text) to service_role;
revoke all on function public.quarantine_stale_communication_claims(integer, interval) from public, anon, authenticated;
grant execute on function public.quarantine_stale_communication_claims(integer, interval) to service_role;
