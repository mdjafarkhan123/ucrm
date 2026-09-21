-- Communications A2 / Stage 4A part 2: the one atomic, consent-aware SMS enqueue command.
--
-- Approved behavior (docs/communications-a2-implementation-plan.md §4A; durable rules in docs/PRODUCT.md §11
-- and docs/research/communications-a2-stage2-consent-balance-sending-safety.md). This is the single server
-- command every normal outbound SMS goes through later (manual Conversations sends in Stage 6, Automation sends
-- in Stage 7). In one short transaction it freezes the logical send — recipient number, sender/registration,
-- final body, the estimated segments, and the applicable retail rate — together with the credit reservation, the
-- immutable message snapshot and the outbox row, and it rechecks every live gate at enqueue time:
--
--   * consent          — opted_in for the exact customer number and this one operational subject (4A part 1
--                         read). Unknown or opted_out refuses.
--   * destination      — a real, active customer phone that normalizes to E.164.
--   * readiness/holds  — communication_sms_outbound_state must be 'ready'; that one read already folds in the
--                         effective SMS mode/package, an approved registration with a live sender, and any active
--                         platform/organization/provider outbound hold (which shows as 'outbound_paused').
--   * balance          — enough spendable credit for the estimated cost, drawing Promotional Credit first then
--                         Purchased Credit (PRODUCT.md §11), reserved atomically so concurrent sends can never
--                         overspend one organization's balance.
--   * quiet hours      — a platform-configurable window reschedules the outbox row's available_at instead of
--                         sending now.
--
-- Idempotency: the same (organization, logical_send_key) returns the already-queued intent unchanged; the same
-- key with a different frozen payload is refused as a conflict. Caps and the workflow authoring window are NOT in
-- the 4A gate and are left for later stages. Nothing here sends: Stage 4 stays dark until Stage 5 webhooks and a
-- country launch gate pass.

-- ---------------------------------------------------------------------------------------------------------------
-- Schema refinements this command relies on.
-- ---------------------------------------------------------------------------------------------------------------

-- Stage 1 dropped NOT NULL on the email-only payload columns (recipient_email, subject, html_content) but left it
-- on text_content, so an SMS intent would have been forced to duplicate its body there. The SMS body lives in the
-- message snapshot (with its frozen encoding and segment count); make the payload contract channel-correct so the
-- body is stored once: email carries text_content, SMS never does.
alter table public.communication_delivery_intents
  alter column text_content drop not null;

alter table public.communication_delivery_intents
  drop constraint communication_delivery_intents_channel_payload_check,
  add constraint communication_delivery_intents_channel_payload_check check (
    (
      channel = 'email'
      and recipient_email is not null
      and position('@' in recipient_email) > 1
      and recipient_phone is null
      and subject is not null
      and char_length(trim(subject)) between 1 and 998
      and html_content is not null
      and char_length(trim(html_content)) > 0
      and text_content is not null
      and char_length(trim(text_content)) > 0
      and sms_sender_identity_id is null
    )
    or
    (
      channel = 'sms'
      and recipient_email is null
      and recipient_phone is not null
      and recipient_phone ~ '^\+[1-9][0-9]{7,14}$'
      and subject is null
      and html_content is null
      and text_content is null
      and sender_id is null
      and reply_alias_id is null
    )
  );

-- A reservation records how its estimated cost was funded so settlement/release can return each part to the right
-- pool. Promotional Credit is spent first, then Purchased Credit (PRODUCT.md §11); only the purchased part is held
-- against the credit account's reserved balance (the promotional part is netted out of the live promotional
-- balance by this command's own read). The two parts always sum to amount_minor.
alter table public.communication_sms_credit_reservations
  add column reserved_promotional_minor bigint not null default 0,
  add column reserved_purchased_minor bigint not null default 0,
  add constraint communication_sms_credit_reservations_funding_check check (
    reserved_promotional_minor >= 0
    and reserved_purchased_minor >= 0
    and amount_minor = reserved_promotional_minor + reserved_purchased_minor
  );

comment on column public.communication_sms_credit_reservations.reserved_promotional_minor is
  'The part of this reservation funded from Promotional Credit (spent first). Netted out of the live promotional '
  'balance while the reservation is active so concurrent sends cannot double-spend the same promotional grant.';
comment on column public.communication_sms_credit_reservations.reserved_purchased_minor is
  'The part of this reservation funded from Purchased Credit, held against communication_sms_credit_accounts.'
  'reserved_balance_minor.';

-- ---------------------------------------------------------------------------------------------------------------
-- Platform quiet-hours policy: one configurable window applied to normal outbound SMS. Recipient-local resolution
-- (contact timezone / area-code inference) and legal per-country confirmation are deferred to the launch gate;
-- this launch window is evaluated in a single configured reference timezone. Server-owned like the other platform
-- controls: the /api layer verifies the Platform Owner and writes only through the setter command below.
-- ---------------------------------------------------------------------------------------------------------------

create table public.communication_sms_quiet_hours_policy (
  id boolean primary key default true,
  enabled boolean not null default true,
  quiet_start time not null default '21:00',
  quiet_end time not null default '08:00',
  time_zone text not null default 'America/New_York',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  -- Singleton: id can only ever be true, so at most one policy row exists.
  constraint communication_sms_quiet_hours_policy_singleton check (id)
);

comment on table public.communication_sms_quiet_hours_policy is
  'The single platform quiet-hours window for normal outbound SMS. A send inside the window is rescheduled to the '
  'window end rather than sent immediately. Recipient-local time and per-country legal rules are a later launch-'
  'gate refinement; today the window is evaluated in time_zone.';

insert into public.communication_sms_quiet_hours_policy (id) values (true);

-- Set the platform quiet-hours window. Platform-owner authorization is enforced by the /api layer (as with the
-- retail-rate and hold commands); this command records who last changed it.
create or replace function public.communication_sms_set_quiet_hours_policy(
  p_enabled boolean,
  p_quiet_start time,
  p_quiet_end time,
  p_time_zone text,
  p_actor uuid
) returns public.communication_sms_quiet_hours_policy
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  policy public.communication_sms_quiet_hours_policy;
begin
  if p_actor is null then
    raise exception 'a quiet-hours change must record who made it' using errcode = 'P0001';
  end if;
  if p_enabled is null then
    raise exception 'the quiet-hours toggle is required' using errcode = 'P0001';
  end if;
  if p_quiet_start is null or p_quiet_end is null then
    raise exception 'the quiet-hours window needs a start and end time' using errcode = 'P0001';
  end if;
  if p_quiet_start = p_quiet_end then
    raise exception 'the quiet-hours window cannot start and end at the same time' using errcode = 'P0001';
  end if;
  if p_time_zone is null or char_length(btrim(p_time_zone)) = 0 then
    raise exception 'the quiet-hours window needs a time zone' using errcode = 'P0001';
  end if;
  -- Reject an unknown IANA zone up front with a clear message instead of failing later at send time.
  begin
    perform now() at time zone p_time_zone;
  exception when others then
    raise exception 'that is not a known time zone' using errcode = 'P0001';
  end;

  update public.communication_sms_quiet_hours_policy
  set enabled = p_enabled,
      quiet_start = p_quiet_start,
      quiet_end = p_quiet_end,
      time_zone = btrim(p_time_zone),
      updated_by = p_actor,
      updated_at = now()
  where id
  returning * into policy;

  return policy;
end;
$$;

-- The moment a send may leave the outbox: now unless now falls inside the quiet-hours window, in which case the
-- next window end. Handles a window that wraps past midnight (e.g. 21:00–08:00). Disabled policy sends now.
create or replace function public.communication_sms_quiet_hours_available_at(
  p_at timestamptz default now()
) returns timestamptz
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  policy public.communication_sms_quiet_hours_policy;
  local_ts timestamp;
  local_time time;
  in_window boolean;
  window_end_local timestamp;
begin
  select * into policy from public.communication_sms_quiet_hours_policy where id;
  if not found or not policy.enabled then
    return p_at;
  end if;

  local_ts := p_at at time zone policy.time_zone;
  local_time := local_ts::time;

  if policy.quiet_start <= policy.quiet_end then
    in_window := local_time >= policy.quiet_start and local_time < policy.quiet_end;
  else
    -- Window wraps midnight: quiet from quiet_start to end-of-day and from start-of-day to quiet_end.
    in_window := local_time >= policy.quiet_start or local_time < policy.quiet_end;
  end if;

  if not in_window then
    return p_at;
  end if;

  if local_time < policy.quiet_end then
    -- In the early-morning tail of the window: the end is later today (local).
    window_end_local := local_ts::date + policy.quiet_end;
  else
    -- At or after quiet_start: the end is tomorrow morning (local).
    window_end_local := (local_ts::date + 1) + policy.quiet_end;
  end if;

  return window_end_local at time zone policy.time_zone;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Segment estimate: encoding and segment count for one SMS body, using the GSM 03.38 rules Twilio bills on.
-- A body that is entirely GSM-7 encodable uses 160 chars in a single segment or 153 per concatenated segment
-- (extension characters ^ { } \ [ ] ~ | € and form feed each cost two). Anything else is UCS-2: 70 UTF-16 units
-- single, 67 per concatenated segment. This is an honest pre-send estimate; the final billed count comes from the
-- provider at settlement.
create or replace function public.communication_sms_estimate_segments(
  p_body text
) returns table (
  encoding text,
  segment_count integer
)
language plpgsql
immutable
security definer
set search_path = pg_catalog, public
as $$
declare
  gsm_basic constant text :=
    '@£$¥èéùìòÇØøÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&''()*+,-./0123456789:;<=>?'
    || '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà'
    || chr(10) || chr(13);
  gsm_ext constant text := '^{}\[~]|€' || chr(12);
  ch text;
  is_gsm boolean := true;
  units integer := 0;
begin
  if p_body is null or char_length(p_body) = 0 then
    raise exception 'an SMS needs a message body' using errcode = 'P0001';
  end if;

  foreach ch in array regexp_split_to_array(p_body, '') loop
    if position(ch in gsm_ext) > 0 then
      units := units + 2;
    elsif position(ch in gsm_basic) > 0 then
      units := units + 1;
    else
      is_gsm := false;
      exit;
    end if;
  end loop;

  if is_gsm then
    encoding := 'gsm7';
    segment_count := case when units <= 160 then 1 else ceil(units::numeric / 153) end;
  else
    encoding := 'ucs2';
    -- UTF-16 code units: characters beyond the Basic Multilingual Plane (e.g. most emoji) take two.
    units := 0;
    foreach ch in array regexp_split_to_array(p_body, '') loop
      units := units + case when ascii(ch) > 65535 then 2 else 1 end;
    end loop;
    segment_count := case when units <= 70 then 1 else ceil(units::numeric / 67) end;
  end if;

  return next;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- The consent-aware enqueue command. All the SMS delivery-spine writes for one send happen only here.
-- ---------------------------------------------------------------------------------------------------------------

create or replace function public.communication_sms_enqueue_operational(
  p_organization_id uuid,
  p_actor uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_sender_id uuid,
  p_subject text,
  p_body text,
  p_send_kind text,
  p_logical_send_key text
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  recipient public.client_contact_methods;
  recipient_e164 text;
  sender public.communication_sms_sender_identities;
  registration public.communication_sms_registrations;
  outbound record;
  consent text;
  v_encoding text;
  v_segment_count integer;
  rate public.communication_sms_retail_rates;
  cost_minor bigint;
  currency text := 'USD';
  settled bigint;
  reserved bigint;
  promo_balance bigint;
  promo_reserved bigint;
  promo_available bigint;
  purchased_available bigint;
  promo_used bigint;
  purchased_used bigint;
  available timestamptz;
  intent public.communication_delivery_intents;
  existing public.communication_delivery_intents;
  existing_body text;
  source_key text;
begin
  -- 1. Shape.
  if p_actor is null then
    raise exception 'a send must record who sent it' using errcode = 'P0001';
  end if;
  if p_subject is null or p_subject not in ('service', 'work_updates', 'billing_updates') then
    raise exception 'a send must name a valid operational subject' using errcode = 'P0001';
  end if;
  if p_body is null or char_length(trim(p_body)) = 0 then
    raise exception 'a send needs a message body' using errcode = 'P0001';
  end if;
  if p_send_kind is null or p_send_kind not in ('manual', 'automated') then
    raise exception 'a send must be manual or automated' using errcode = 'P0001';
  end if;
  if p_logical_send_key is null or char_length(trim(p_logical_send_key)) = 0 then
    raise exception 'a send must carry a logical send key' using errcode = 'P0001';
  end if;

  -- 2. Permission. Mirrors the email command: the authorized member may send customer messages.
  if not private.member_has_permission(p_organization_id, p_actor, 'conversations.send')
    or not private.member_has_permission(p_organization_id, p_actor, 'customers.view') then
    raise exception 'You do not have permission to send a customer message.'
      using errcode = 'insufficient_privilege';
  end if;

  -- 3. Resolve the recipient: an active phone on this customer in this organization, normalized to E.164.
  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = p_organization_id
    and method.id = p_client_contact_method_id
    and method.client_id = p_client_id
    and method.kind = 'phone'
    and client.deleted_at is null
  for share of method, client;

  if recipient.id is null then
    raise exception 'Choose an active phone number for this customer.' using errcode = 'foreign_key_violation';
  end if;
  recipient_e164 := '+' || recipient.normalized_value;
  if recipient_e164 !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'That customer phone number is not a valid mobile number.' using errcode = 'P0001';
  end if;

  -- 4. Resolve the sending number: the chosen one, or the organization default. Must be a live, SMS-capable
  --    number tied to a registration.
  if p_sender_id is not null then
    select s.* into sender
    from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id
      and s.id = p_sender_id
      and s.lifecycle_state = 'ready'
      and s.capable_sms
    for share of s;
  else
    select s.* into sender
    from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id
      and s.is_default_sender
      and s.lifecycle_state = 'ready'
      and s.capable_sms
    for share of s;
  end if;

  if sender.id is null then
    raise exception 'No ready SMS number is available to send from.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if sender.registration_id is null or sender.country_code is null or sender.sender_type is null then
    raise exception 'This SMS number is not fully set up to send yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select r.* into registration
  from public.communication_sms_registrations r
  where r.organization_id = p_organization_id and r.id = sender.registration_id;
  if registration.id is null then
    raise exception 'This SMS number is not fully set up to send yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 5. Idempotency: a repeat of the same logical send returns the already-queued intent unchanged; the same key
  --    with a different frozen payload is a conflict. Return the replay before re-running any live gate.
  select i.* into existing
  from public.communication_delivery_intents i
  where i.organization_id = p_organization_id and i.logical_send_key = trim(p_logical_send_key);

  if existing.id is not null then
    select snap.body into existing_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;

    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_body = p_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end if;

  -- 6. Readiness and holds in one read: 'ready' means the effective mode/package allows SMS, the registration is
  --    approved with a live sender, and no active outbound hold governs the organization.
  select * into outbound
  from public.communication_sms_outbound_state(
    p_organization_id, sender.country_code, sender.sender_type, registration.use_case
  );
  if outbound.state = 'outbound_paused' then
    raise exception 'Outbound SMS is paused for this organization right now.'
      using errcode = 'object_not_in_prerequisite_state';
  elsif outbound.state <> 'ready' then
    raise exception 'This organization is not ready to send SMS yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 7. Consent for this exact number and this one subject. Unknown or opted-out refuses.
  consent := public.communication_sms_consent_status(
    p_organization_id, p_client_contact_method_id, p_subject
  );
  if consent = 'opted_out' then
    raise exception 'This customer has opted out of text messages.' using errcode = 'P0001';
  elsif consent <> 'opted_in' then
    raise exception 'There is no SMS consent on file for this customer and message type.'
      using errcode = 'P0001';
  end if;

  -- 8. Freeze the segment estimate.
  select est.encoding, est.segment_count into v_encoding, v_segment_count
  from public.communication_sms_estimate_segments(p_body) est;
  if v_segment_count > 10 then
    raise exception 'This message is too long to send as one text.' using errcode = 'P0001';
  end if;

  -- 9. Freeze the applicable retail rate and the estimated cost (rounded up so the reservation never under-holds).
  select rr.* into rate
  from public.communication_sms_effective_retail_rate(
    sender.country_code, sender.sender_type, 'segment', currency, now()
  ) rr;
  if rate.id is null then
    raise exception 'No SMS price is published for this destination yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  cost_minor := ceil(v_segment_count * rate.retail_rate_major * 100)::bigint;

  -- 10. Serialize on the organization's credit account and check spendable balance. Promotional Credit is spent
  --     first, then Purchased Credit; the account row is the single lock so concurrent sends cannot overspend.
  insert into public.communication_sms_credit_accounts (organization_id, currency_code)
  values (p_organization_id, currency)
  on conflict (organization_id) do nothing;

  select settled_balance_minor, reserved_balance_minor into settled, reserved
  from public.communication_sms_credit_accounts
  where organization_id = p_organization_id
  for update;

  promo_balance := public.communication_sms_promotional_balance(p_organization_id);
  select coalesce(sum(reserved_promotional_minor), 0) into promo_reserved
  from public.communication_sms_credit_reservations
  where organization_id = p_organization_id and state in ('reserved', 'submission_unknown');
  promo_available := greatest(promo_balance - promo_reserved, 0);
  purchased_available := settled - reserved;

  if promo_available + purchased_available < cost_minor then
    raise exception 'There is not enough SMS balance to send this message.' using errcode = 'P0001';
  end if;

  promo_used := least(cost_minor, promo_available);
  purchased_used := cost_minor - promo_used;

  -- 11. Schedule for quiet hours (now unless inside the window).
  available := public.communication_sms_quiet_hours_available_at(now());

  -- 12. Create the durable send intent. A concurrent identical retry loses the unique (org, logical_send_key)
  --     race here; re-read and return it (or conflict) without reserving twice.
  begin
    insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, channel, logical_send_key,
      recipient_phone, sms_sender_identity_id, send_kind, allowance_class, created_by
    ) values (
      p_organization_id, p_client_id, p_client_contact_method_id, 'sms', trim(p_logical_send_key),
      recipient_e164, sender.id, p_send_kind, 'optional', p_actor
    )
    returning * into intent;
  exception when unique_violation then
    select i.* into existing
    from public.communication_delivery_intents i
    where i.organization_id = p_organization_id and i.logical_send_key = trim(p_logical_send_key);
    select snap.body into existing_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;
    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_body = p_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end;

  -- 13. Freeze the message body, encoding and segment count.
  insert into public.communication_sms_message_snapshots (
    delivery_intent_id, organization_id, body, encoding, segment_count
  ) values (
    intent.id, p_organization_id, p_body, v_encoding, v_segment_count
  );

  -- 14. Reserve the estimated cost: hold the purchased part against the account, record the promo/purchased split.
  source_key := 'send:' || trim(p_logical_send_key);
  update public.communication_sms_credit_accounts
  set reserved_balance_minor = reserved_balance_minor + purchased_used,
      updated_at = now()
  where organization_id = p_organization_id;

  insert into public.communication_sms_credit_reservations (
    organization_id, delivery_intent_id, source_key, amount_minor, segment_count,
    reserved_promotional_minor, reserved_purchased_minor
  ) values (
    p_organization_id, intent.id, source_key, cost_minor, v_segment_count,
    promo_used, purchased_used
  );

  -- 15. Hand the send to the outbox, scheduled for quiet hours.
  insert into public.communication_outbox_events (
    organization_id, delivery_intent_id, channel, available_at
  ) values (
    p_organization_id, intent.id, 'sms', available
  );

  return intent;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Access: everything is server-owned. The new table stays RLS-on and deny-all to client roles; the /api layer
-- reads with service_role and scopes to the caller. The commands are security definer and callable only by
-- service_role, exactly like the rest of the SMS spine.
-- ---------------------------------------------------------------------------------------------------------------

alter table public.communication_sms_quiet_hours_policy enable row level security;

revoke all on table public.communication_sms_quiet_hours_policy from public, anon, authenticated;
revoke all on table public.communication_sms_quiet_hours_policy from service_role;
grant select on table public.communication_sms_quiet_hours_policy to service_role;

revoke all on function public.communication_sms_set_quiet_hours_policy(boolean, time, time, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_set_quiet_hours_policy(boolean, time, time, text, uuid)
  to service_role;

revoke all on function public.communication_sms_quiet_hours_available_at(timestamptz)
  from public, anon, authenticated;
grant execute on function public.communication_sms_quiet_hours_available_at(timestamptz) to service_role;

revoke all on function public.communication_sms_estimate_segments(text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_estimate_segments(text) to service_role;

revoke all on function public.communication_sms_enqueue_operational(uuid, uuid, uuid, uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_enqueue_operational(uuid, uuid, uuid, uuid, uuid, text, text, text, text)
  to service_role;

comment on function public.communication_sms_enqueue_operational(uuid, uuid, uuid, uuid, uuid, text, text, text, text) is
  'The one atomic consent-aware SMS enqueue command. Freezes recipient, sender/registration, body, segment '
  'estimate and applicable retail rate with the credit reservation, snapshot and outbox row; rechecks consent '
  '(exact number + subject), destination, readiness/holds, balance (promotional first) and quiet-hour scheduling. '
  'Idempotent by (organization, logical_send_key); a changed payload for the same key is refused. Nothing sends '
  'until the Stage 4B worker and Stage 5 webhooks ship.';
