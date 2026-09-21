-- Communications Part 7.2: the human side of the suppression list.
--
-- 7.1 built the auditable suppression spine and made the outbox claim refuse a suppressed recipient.
-- What was missing: a contractor cannot see which addresses are blocked, and there is no path back.
--
-- docs/contractor-email-contract.md
--   § Preferences, consent, and suppressions
--     "Organization administrators may request removal of a corrected hard-bounce suppression. Only
--      Jafar may approve complaint-suppression removal. Removal requires a reason, evidence, and any
--      required renewed consent."
--   § Platform Owner controls
--     "sender restrictions, suppressions, unusual volume, and provider incidents"
--
-- The split, following standard ESP practice (a bounce suppression is self-serviceable, a spam
-- complaint is not):
--   * hard_bounce -- an organization administrator clears it themselves. The request and its release
--     are still recorded with who, why, and the evidence they attested to.
--   * complaint   -- the administrator files a request that stays pending until Jafar approves or
--     denies it. Nothing is released until he does.
--
-- The outbox claim is NOT touched here: it already keys off `released_at is null`, so releasing a
-- suppression is all it takes for sending to resume. A later provider bounce/complaint event opens a
-- fresh suppression row exactly as before -- releasing one does not immunise an address.

-- ---------------------------------------------------------------------------------------------------
-- 1. Record who released a suppression from the contractor side. 7.1 only had an owner-email column.
-- ---------------------------------------------------------------------------------------------------

alter table public.communication_email_suppressions
  add column released_by_kind text
    check (released_by_kind in ('organization_admin', 'platform_owner')),
  add column released_by_user_id uuid references auth.users(id) on delete set null;

-- A released row now always names who did it: the owner email (platform_owner) or the user id
-- (organization_admin). Rows released before this migration existed have neither and are grandfathered.
alter table public.communication_email_suppressions
  add constraint communication_email_suppressions_released_by_check check (
    released_at is null
    or released_by_kind is not null
    or released_by_owner_email is not null
  );

create index communication_email_suppressions_released_by_user_idx
  on public.communication_email_suppressions (released_by_user_id)
  where released_by_user_id is not null;

-- ---------------------------------------------------------------------------------------------------
-- 2. The removal request. One open request per blocked address; the row is its own history.
-- ---------------------------------------------------------------------------------------------------

create table public.communication_email_suppression_removal_requests (
  id uuid primary key default gen_random_uuid(),
  suppression_id uuid not null
    references public.communication_email_suppressions(id) on delete cascade,
  -- Denormalised for the organization-scoped read and the cascade path, the same way 7.1 put
  -- organization_id on the callback events.
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Snapshot of what was being removed, so the owner queue renders without joining back and history
  -- survives the wording of the source row.
  suppression_reason text not null check (suppression_reason in ('complaint', 'hard_bounce')),
  recipient_email text not null check (position('@' in recipient_email) > 1),

  requested_by_user_id uuid references auth.users(id) on delete set null,
  requested_by_email text not null check (char_length(btrim(requested_by_email)) between 3 and 320),
  request_reason text not null check (char_length(btrim(request_reason)) between 3 and 1000),
  request_evidence text not null check (char_length(btrim(request_evidence)) between 1 and 2000),
  -- "any required renewed consent" -- a plain attestation that the customer still wants this mail.
  consent_confirmed boolean not null,

  status text not null default 'pending'
    check (status in ('pending', 'approved', 'denied', 'withdrawn')),
  decided_by_kind text check (decided_by_kind in ('organization_admin', 'platform_owner')),
  decided_by_user_id uuid references auth.users(id) on delete set null,
  decided_by_email text,
  decided_at timestamptz,
  decision_note text check (decision_note is null or char_length(btrim(decision_note)) between 1 and 1000),

  created_at timestamptz not null default now(),

  -- A pending request has no decision; a closed one always records who closed it and when.
  constraint communication_email_suppression_removal_requests_decision_check check (
    (status = 'pending') = (decided_at is null)
    and (status = 'pending') = (decided_by_kind is null)
  )
);

-- At most one open request per blocked address. This is the arbiter the request RPC checks.
create unique index communication_email_suppression_removal_requests_open_idx
  on public.communication_email_suppression_removal_requests (suppression_id)
  where status = 'pending';

-- Jafar's queue: the oldest still-pending request first. Partial, so it stays tiny.
create index communication_email_suppression_removal_requests_pending_idx
  on public.communication_email_suppression_removal_requests (created_at, id)
  where status = 'pending';

-- The organization's own list of requests it has filed, newest first, and the cascade path.
create index communication_email_suppression_removal_requests_org_created_idx
  on public.communication_email_suppression_removal_requests (organization_id, created_at desc, id desc);

-- Foreign-key indexes for the two set-null user references and the suppression cascade.
create index communication_email_suppression_removal_requests_suppression_idx
  on public.communication_email_suppression_removal_requests (suppression_id);
create index communication_email_suppression_removal_requests_requested_by_idx
  on public.communication_email_suppression_removal_requests (requested_by_user_id)
  where requested_by_user_id is not null;
create index communication_email_suppression_removal_requests_decided_by_idx
  on public.communication_email_suppression_removal_requests (decided_by_user_id)
  where decided_by_user_id is not null;

alter table public.communication_email_suppression_removal_requests enable row level security;
revoke all on public.communication_email_suppression_removal_requests from anon, authenticated;
grant select, insert, update on public.communication_email_suppression_removal_requests to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 2b. One request row shaped for an API response: the request plus the current suppression state.
--     Defined here because every write RPC below returns through it.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.communication_email_suppression_removal_request_json(p_request_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'id', r.id,
    'suppression_id', r.suppression_id,
    'organization_id', r.organization_id,
    'recipient_email', r.recipient_email,
    'suppression_reason', r.suppression_reason,
    'requested_by_email', r.requested_by_email,
    'request_reason', r.request_reason,
    'request_evidence', r.request_evidence,
    'status', r.status,
    'decided_by_kind', r.decided_by_kind,
    'decided_by_email', r.decided_by_email,
    'decided_at', r.decided_at,
    'decision_note', r.decision_note,
    'created_at', r.created_at,
    'suppression_released_at', s.released_at,
    'suppression_released_by_kind', s.released_by_kind
  )
  from public.communication_email_suppression_removal_requests r
  left join public.communication_email_suppressions s on s.id = r.suppression_id
  where r.id = p_request_id;
$$;

revoke all on function public.communication_email_suppression_removal_request_json(uuid)
  from public, anon, authenticated;
grant execute on function public.communication_email_suppression_removal_request_json(uuid)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. File a removal request. Called by an organization administrator through a service-role API route.
--    hard_bounce: the request is auto-approved and the suppression released in the same transaction.
--    complaint:   the request is left pending for Jafar.
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
-- 4. An organization administrator withdraws their own still-pending complaint request.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.withdraw_communication_email_suppression_removal(
  p_organization_id uuid,
  p_suppression_id uuid,
  p_actor_user_id uuid,
  p_actor_email text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_email text := lower(btrim(coalesce(p_actor_email, '')));
  open_request public.communication_email_suppression_removal_requests%rowtype;
begin
  if char_length(actor_email) not between 3 and 320 then
    raise exception 'An administrator email is required.' using errcode = 'check_violation';
  end if;

  select * into open_request
  from public.communication_email_suppression_removal_requests
  where suppression_id = p_suppression_id
    and organization_id = p_organization_id
    and status = 'pending'
  for update;

  if not found then
    raise exception 'There is no open removal request for that address.'
      using errcode = 'no_data_found';
  end if;

  update public.communication_email_suppression_removal_requests
  set status = 'withdrawn',
    decided_by_kind = 'organization_admin',
    decided_by_user_id = p_actor_user_id,
    decided_by_email = actor_email,
    decided_at = now()
  where id = open_request.id;

  return public.communication_email_suppression_removal_request_json(open_request.id);
end;
$$;

revoke all on function public.withdraw_communication_email_suppression_removal(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.withdraw_communication_email_suppression_removal(uuid, uuid, uuid, text)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. Jafar approves or denies a pending complaint-removal request. Approving releases the suppression;
--    denying leaves it in place. Either way an immutable owner audit event is written.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.decide_communication_email_suppression_removal(
  p_request_id uuid,
  p_actor_email text,
  p_decision text,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_email text := lower(btrim(coalesce(p_actor_email, '')));
  clean_note text := nullif(btrim(coalesce(p_note, '')), '');
  target_request public.communication_email_suppression_removal_requests%rowtype;
  target_suppression public.communication_email_suppressions%rowtype;
  approving boolean;
begin
  if char_length(actor_email) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if p_decision not in ('approve', 'deny') then
    raise exception 'The decision must be approve or deny.' using errcode = 'check_violation';
  end if;
  approving := p_decision = 'approve';
  if not approving and (clean_note is null or char_length(clean_note) not between 1 and 1000) then
    raise exception 'A note of 1 to 1000 characters is required to deny a request.'
      using errcode = 'check_violation';
  end if;

  select * into target_request
  from public.communication_email_suppression_removal_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'That removal request was not found.' using errcode = 'no_data_found';
  end if;
  if target_request.status <> 'pending' then
    raise exception 'That removal request has already been decided.' using errcode = 'check_violation';
  end if;

  select * into target_suppression
  from public.communication_email_suppressions
  where id = target_request.suppression_id
  for update;

  update public.communication_email_suppression_removal_requests
  set status = case when approving then 'approved' else 'denied' end,
    decided_by_kind = 'platform_owner',
    decided_by_email = actor_email,
    decided_at = now(),
    decision_note = clean_note
  where id = p_request_id;

  if approving and target_suppression.id is not null and target_suppression.released_at is null then
    update public.communication_email_suppressions
    set released_at = now(),
      released_by_owner_email = actor_email,
      released_by_kind = 'platform_owner',
      released_by_user_id = null,
      released_reason = 'Complaint-suppression removal approved by the platform owner.'
    where id = target_suppression.id;
  end if;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor_email,
    case when approving
      then 'communications.email_suppression_removal_approved'
      else 'communications.email_suppression_removal_denied' end,
    'communication_email_suppression',
    target_request.suppression_id::text,
    jsonb_build_object(
      'request_id', target_request.id,
      'organization_id', target_request.organization_id,
      'recipient_email', target_request.recipient_email,
      'suppression_reason', target_request.suppression_reason,
      'requested_by', target_request.requested_by_email,
      'request_reason', target_request.request_reason
    ),
    jsonb_build_object('decision', p_decision, 'note', clean_note)
  );

  return public.communication_email_suppression_removal_request_json(p_request_id);
end;
$$;

revoke all on function public.decide_communication_email_suppression_removal(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.decide_communication_email_suppression_removal(uuid, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 6. The contractor "Blocked addresses" screen read: everything currently blocked for one
--    organization, plus a short tail of recently cleared addresses. Bounded.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_email_blocked_addresses(p_organization_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  with blocked as (
    select s.*
    from public.communication_email_suppressions s
    where s.organization_id = p_organization_id and s.released_at is null
    order by s.created_at desc, s.id desc
    limit 200
  )
  select jsonb_build_object(
    'blocked', coalesce((
      select jsonb_agg(jsonb_build_object(
        'suppression_id', b.id,
        'recipient_email', b.recipient_email,
        'reason', b.reason,
        'source', b.source,
        'created_at', b.created_at,
        'client_id', intent.client_id,
        'client_display_name', cl.display_name,
        'open_request', (
          select jsonb_build_object(
            'id', r.id,
            'request_reason', r.request_reason,
            'requested_by_email', r.requested_by_email,
            'created_at', r.created_at
          )
          from public.communication_email_suppression_removal_requests r
          where r.suppression_id = b.id and r.status = 'pending'
          limit 1
        )
      ) order by b.created_at desc, b.id desc)
      from blocked b
      left join public.communication_delivery_intents intent on intent.id = b.first_delivery_intent_id
      left join public.clients cl on cl.id = intent.client_id
    ), '[]'::jsonb),
    'blocked_total', (
      select count(*)
      from public.communication_email_suppressions s
      where s.organization_id = p_organization_id and s.released_at is null
    ),
    'recently_cleared', coalesce((
      select jsonb_agg(jsonb_build_object(
        'suppression_id', s.id,
        'recipient_email', s.recipient_email,
        'reason', s.reason,
        'released_at', s.released_at,
        'released_by_kind', s.released_by_kind,
        'released_reason', s.released_reason
      ) order by s.released_at desc, s.id desc)
      from (
        select *
        from public.communication_email_suppressions s2
        where s2.organization_id = p_organization_id and s2.released_at is not null
        order by s2.released_at desc, s2.id desc
        limit 25
      ) s
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_communication_email_blocked_addresses(uuid)
  from public, anon, authenticated;
grant execute on function public.get_communication_email_blocked_addresses(uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 7. Jafar's review queue: pending complaint-removal requests, oldest first, plus a short tail of the
--    ones he has recently decided. Bounded.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_email_suppression_removal_queue()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'pending', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'suppression_id', r.suppression_id,
        'organization_id', r.organization_id,
        'organization_name', o.name,
        'recipient_email', r.recipient_email,
        'suppression_reason', r.suppression_reason,
        'requested_by_email', r.requested_by_email,
        'request_reason', r.request_reason,
        'request_evidence', r.request_evidence,
        'created_at', r.created_at,
        'suppression_created_at', s.created_at
      ) order by r.created_at, r.id)
      from (
        select *
        from public.communication_email_suppression_removal_requests
        where status = 'pending'
        order by created_at, id
        limit 100
      ) r
      join public.organizations o on o.id = r.organization_id
      left join public.communication_email_suppressions s on s.id = r.suppression_id
    ), '[]'::jsonb),
    'pending_total', (
      select count(*)
      from public.communication_email_suppression_removal_requests
      where status = 'pending'
    ),
    'recently_decided', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'organization_name', o.name,
        'recipient_email', r.recipient_email,
        'status', r.status,
        'decided_by_email', r.decided_by_email,
        'decided_at', r.decided_at,
        'decision_note', r.decision_note
      ) order by r.decided_at desc, r.id desc)
      from (
        select *
        from public.communication_email_suppression_removal_requests
        where status in ('approved', 'denied')
          and decided_by_kind = 'platform_owner'
        order by decided_at desc, id desc
        limit 20
      ) r
      join public.organizations o on o.id = r.organization_id
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_communication_email_suppression_removal_queue()
  from public, anon, authenticated;
grant execute on function public.get_communication_email_suppression_removal_queue() to service_role;
