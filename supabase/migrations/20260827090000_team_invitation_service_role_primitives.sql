-- Team & access, part 3A, layer 6: the invitations table's service_role primitives.
--
-- Ten primitives were named in the 3A packet: begin_, attach_identity, record_delivery, claim_,
-- record_password_set, finalize_, resend_, cancel_, expire_, sweep_reservations. A gap surfaced while
-- designing them against the Orphan Rule: nothing in that list stamps auth_attempt_started_at *before* the
-- Auth call, and folding the stamp into begin_team_invitation would make every begin_-then-crash look like a
-- possibly-created identity, holding the seat forever. So an eleventh, separate primitive --
-- mark_team_invitation_auth_attempt_started -- exists purely to draw that line: begin_ only reserves, mark_
-- is the caller's promise that an Auth call is about to happen.
--
-- A second gap: the packet's "claim is lease-guarded" language does not by itself say what happens to an
-- expired lease whose Auth outcome nobody recorded. Postgres cannot know whether that Auth call actually set
-- a password -- record_invitation_password_set requires the lease still be open, so a late arrival is
-- indistinguishable from "never happened." Making the token freely reclaimable in that state would let a
-- second person's claim race a first person who actually finished. So an expired-with-unknown-outcome lease
-- (password_set_at is null) is never reclaimed and never silently expired -- it is flagged
-- identity_cleanup_state = 'required' and left exactly where it is for 3B's worker to reconcile against Auth
-- directly. An expired lease with a *known* outcome (password_set_at is not null) finalizes instead of
-- expiring, because the person did finish -- cancelling or expiring them now would revoke a completed signup.

alter table public.organization_member_invitations
  add column if not exists auth_attempt_nonce uuid,
  add column if not exists password_set_at timestamptz;

comment on column public.organization_member_invitations.auth_attempt_nonce is
  'Set by mark_team_invitation_auth_attempt_started immediately before an Auth call. Each call supersedes '
  'the last, so attach_team_invitation_identity can reject a stale attempt that finishes late.';
comment on column public.organization_member_invitations.password_set_at is
  'Stamped by record_invitation_password_set once Auth confirms the password write. Required by '
  'finalize_team_invitation -- an accepting row with a lapsed lease and no stamp is ambiguous, not expired.';

alter table public.organization_member_invitations
  add constraint organization_member_invitations_password_set_requires_identity_check check (
    password_set_at is null or invited_user_id is not null
  );

-- 1. Reservation only. No Auth call has happened yet -- see mark_ below for why.
create or replace function public.begin_team_invitation(
  target_organization_id uuid,
  target_invited_email text,
  target_role text,
  target_invited_by uuid
)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_row public.organization_member_invitations;
begin
  perform private.assert_employee_seat_available(target_organization_id);

  insert into public.organization_member_invitations (
    organization_id, invited_email, role, invited_by, state
  )
  values (
    target_organization_id, target_invited_email, target_role, target_invited_by, 'reserving'
  )
  returning * into new_row;

  return new_row;
end;
$$;

comment on function public.begin_team_invitation(uuid, text, text, uuid) is
  'Reserves a seat and creates the reserving row. Does not touch Auth or auth_attempt_started_at -- call '
  'mark_team_invitation_auth_attempt_started immediately before the Auth call.';

revoke all on function public.begin_team_invitation(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.begin_team_invitation(uuid, text, text, uuid) to service_role;

-- 2. The Orphan Rule's own primitive: stamped before, and only before, the Auth call. Re-callable while
-- still reserving so a clean retry (Auth returned a definite error) can mark a fresh attempt; the new nonce
-- supersedes the old one so a slow, late-arriving completion of the earlier attempt is rejected by attach_.
create or replace function public.mark_team_invitation_auth_attempt_started(
  target_invitation_id uuid,
  target_attempt_nonce uuid
)
returns public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  updated_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set auth_attempt_started_at = now(), auth_attempt_nonce = target_attempt_nonce
  where id = target_invitation_id and state = 'reserving'
  returning * into updated_row;

  if not found then
    raise exception 'Invitation % is not reserving; an Auth attempt cannot be marked.', target_invitation_id
      using errcode = 'check_violation';
  end if;

  return updated_row;
end;
$$;

revoke all on function public.mark_team_invitation_auth_attempt_started(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.mark_team_invitation_auth_attempt_started(uuid, uuid) to service_role;

-- 3. reserving -> invited, atomically alongside the pending membership row that is the seat's new home: once
-- this commits the invitation drops out of employee_seats_used's reserving count exactly as the membership
-- row picks it up, so the handoff never double-counts or gaps. Requires the attempt nonce mark_ stamped, so
-- a stale attempt superseded by a later mark_ cannot attach.
create or replace function public.attach_team_invitation_identity(
  target_invitation_id uuid,
  target_invited_user_id uuid,
  target_attempt_nonce uuid,
  target_token_hash text,
  target_expires_at timestamptz
)
returns public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  updated_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set state = 'invited',
      invited_user_id = target_invited_user_id,
      token_hash = target_token_hash,
      expires_at = target_expires_at
  where id = target_invitation_id
    and state = 'reserving'
    and auth_attempt_nonce = target_attempt_nonce
  returning * into updated_row;

  if not found then
    raise exception
      'Invitation % is not reserving under attempt %; the identity cannot be attached.',
      target_invitation_id, target_attempt_nonce
      using errcode = 'check_violation';
  end if;

  insert into public.organization_members (organization_id, user_id, role, status)
  values (updated_row.organization_id, target_invited_user_id, updated_row.role, 'pending');

  return updated_row;
end;
$$;

revoke all on function public.attach_team_invitation_identity(uuid, uuid, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.attach_team_invitation_identity(uuid, uuid, uuid, text, timestamptz)
  to service_role;

-- 4. Delivery bookkeeping only, following issueSetupLink's last_sent_at / last_error convention.
create or replace function public.record_team_invitation_delivery(
  target_invitation_id uuid,
  target_success boolean,
  target_error text default null
)
returns public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  updated_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set last_sent_at = now(),
      last_delivery_error = case when target_success then null else target_error end
  where id = target_invitation_id and state = 'invited'
  returning * into updated_row;

  if not found then
    raise exception 'Invitation % is not invited; delivery cannot be recorded.', target_invitation_id
      using errcode = 'check_violation';
  end if;

  return updated_row;
end;
$$;

revoke all on function public.record_team_invitation_delivery(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.record_team_invitation_delivery(uuid, boolean, text) to service_role;

-- 5. One atomic UPDATE, safe under concurrent claim attempts. A dead lease (lease_expires_at < now()) is
-- only reclaimable when nothing happened on it: password_set_at is null and identity_cleanup_state is still
-- not_required. Once either is set the token stops being claimable at all -- that row's outcome is decided
-- by finalize or by 3B's reconciliation worker, never by a fresh claim.
create or replace function public.claim_team_invitation(
  target_token_hash text,
  target_email text,
  target_lease_nonce uuid,
  target_lease_seconds integer default 900
)
returns table (
  claimed boolean,
  invitation_id uuid,
  organization_id uuid,
  invited_user_id uuid,
  role text
)
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  updated_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set state = 'accepting',
      lease_nonce = target_lease_nonce,
      lease_expires_at = now() + make_interval(secs => target_lease_seconds)
  where token_hash = target_token_hash
    and lower(invited_email) = lower(target_email)
    and expires_at > now()
    and (
      state = 'invited'
      or (
        state = 'accepting'
        and lease_expires_at < now()
        and password_set_at is null
        and identity_cleanup_state = 'not_required'
      )
    )
  returning * into updated_row;

  if found then
    return query
      select true, updated_row.id, updated_row.organization_id, updated_row.invited_user_id, updated_row.role;
  else
    return query select false, null::uuid, null::uuid, null::uuid, null::text;
  end if;
end;
$$;

revoke all on function public.claim_team_invitation(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_team_invitation(text, text, uuid, integer) to service_role;

-- 6. Only while the lease that was granted is still open. A late arrival (lease already expired) is
-- rejected, not retried here -- that is exactly the ambiguity requirement 3 keeps honest: Postgres cannot
-- tell "Auth succeeded but we heard late" from "Auth never ran", so it does not guess.
create or replace function public.record_invitation_password_set(
  target_invitation_id uuid,
  target_lease_nonce uuid
)
returns public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  updated_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set password_set_at = now()
  where id = target_invitation_id
    and state = 'accepting'
    and lease_nonce = target_lease_nonce
    and lease_expires_at > now()
  returning * into updated_row;

  if not found then
    raise exception
      'Invitation % has no open lease matching %; the password-set receipt cannot be recorded.',
      target_invitation_id, target_lease_nonce
      using errcode = 'check_violation';
  end if;

  return updated_row;
end;
$$;

revoke all on function public.record_invitation_password_set(uuid, uuid) from public, anon, authenticated;
grant execute on function public.record_invitation_password_set(uuid, uuid) to service_role;

-- Shared by finalize_team_invitation and the expiry/cancel paths below so "accepting with a completed
-- password receipt becomes accepted" is written once. Idempotent: an already-accepted row is simply re-read,
-- which is what makes finalize safe to retry after a crash using only the invitation id.
create or replace function private.finalize_accepted_invitation(target_invitation_id uuid)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  updated_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set state = 'accepted', accepted_at = now()
  where id = target_invitation_id and state = 'accepting' and password_set_at is not null
  returning * into updated_row;

  if found then
    update public.organization_members
    set status = 'active', status_changed_at = now()
    where organization_id = updated_row.organization_id
      and user_id = updated_row.invited_user_id
      and status = 'pending';
    return updated_row;
  end if;

  select * into updated_row
  from public.organization_member_invitations
  where id = target_invitation_id;

  return updated_row;
end;
$$;

revoke all on function private.finalize_accepted_invitation(uuid) from public, anon, authenticated, service_role;

-- Shared by expire_team_invitations and cancel_team_invitation for an 'accepting' row whose lease has
-- already lapsed: a completed password receipt finalizes instead of expiring (the person did finish);
-- otherwise the outcome is unknown, so the row is flagged for 3B's reconciliation worker and left exactly
-- where it is -- not expired, not cancelled, and (per claim_team_invitation's own guard) not reclaimable.
create or replace function private.settle_expired_acceptance(target_invitation_id uuid)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_row public.organization_member_invitations;
  updated_row public.organization_member_invitations;
begin
  select * into current_row
  from public.organization_member_invitations
  where id = target_invitation_id;

  if current_row.password_set_at is not null then
    return private.finalize_accepted_invitation(target_invitation_id);
  end if;

  update public.organization_member_invitations
  set identity_cleanup_state = 'required'
  where id = target_invitation_id and identity_cleanup_state = 'not_required'
  returning * into updated_row;

  if found then
    return updated_row;
  end if;

  return current_row;
end;
$$;

revoke all on function private.settle_expired_acceptance(uuid) from public, anon, authenticated, service_role;

-- 7. accepting + a completed password receipt -> accepted, activating the membership in the same
-- transaction. Idempotent by design (see private.finalize_accepted_invitation) so a crash-retry calls this
-- alone -- never the token, never the password, per the packet.
create or replace function public.finalize_team_invitation(target_invitation_id uuid)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return private.finalize_accepted_invitation(target_invitation_id);
end;
$$;

revoke all on function public.finalize_team_invitation(uuid) from public, anon, authenticated;
grant execute on function public.finalize_team_invitation(uuid) to service_role;

-- 8. Only from invited -- not accepting, so a fresh token never races a claim already in flight.
create or replace function public.resend_team_invitation(
  target_invitation_id uuid,
  target_token_hash text,
  target_expires_at timestamptz
)
returns public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  updated_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set token_hash = target_token_hash,
      expires_at = target_expires_at,
      last_sent_at = null,
      last_delivery_error = null
  where id = target_invitation_id and state = 'invited'
  returning * into updated_row;

  if not found then
    raise exception 'Invitation % is not invited; it cannot be resent.', target_invitation_id
      using errcode = 'check_violation';
  end if;

  return updated_row;
end;
$$;

revoke all on function public.resend_team_invitation(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.resend_team_invitation(uuid, text, timestamptz) to service_role;

-- 9. reserving/invited cancel outright. An open accepting lease is refused outright -- the claim in progress
-- gets its window. A lapsed accepting lease resolves through the same settle path expiry uses, because
-- cancelling cannot undo a completed acceptance any more than expiring can.
create or replace function public.cancel_team_invitation(
  target_invitation_id uuid,
  target_cancelled_by uuid
)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_row public.organization_member_invitations;
  updated_row public.organization_member_invitations;
begin
  select * into current_row
  from public.organization_member_invitations
  where id = target_invitation_id;

  if not found then
    raise exception 'Invitation % does not exist.', target_invitation_id using errcode = 'check_violation';
  end if;

  if current_row.state in ('reserving', 'invited') then
    update public.organization_member_invitations
    set state = 'cancelled', cancelled_at = now(), cancelled_by = target_cancelled_by
    where id = target_invitation_id
    returning * into updated_row;

    delete from public.organization_members
    where organization_id = updated_row.organization_id
      and user_id = updated_row.invited_user_id
      and status = 'pending';

    return updated_row;
  end if;

  if current_row.state = 'accepting' then
    if current_row.lease_expires_at > now() then
      raise exception
        'Invitation % has an open acceptance lease; it cannot be cancelled until the lease expires.',
        target_invitation_id
        using errcode = 'check_violation';
    end if;

    return private.settle_expired_acceptance(target_invitation_id);
  end if;

  raise exception 'Invitation % is % and cannot be cancelled.', target_invitation_id, current_row.state
    using errcode = 'check_violation';
end;
$$;

revoke all on function public.cancel_team_invitation(uuid, uuid) from public, anon, authenticated;
grant execute on function public.cancel_team_invitation(uuid, uuid) to service_role;

-- 10. Batch expiry. An accepting row with its lease still open is skipped entirely regardless of the
-- invitation-level expires_at -- a claim made before expiry keeps its window to finish. An accepting row
-- whose lease has also lapsed resolves through the same settle path cancel_ uses.
create or replace function public.expire_team_invitations()
returns setof public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  accepting_row record;
begin
  return query
    with expired as (
      update public.organization_member_invitations
      set state = 'expired'
      where state = 'invited' and expires_at < now()
      returning *
    ), cleanup as (
      delete from public.organization_members as membership
      using expired
      where membership.organization_id = expired.organization_id
        and membership.user_id = expired.invited_user_id
        and membership.status = 'pending'
      returning 1
    )
    select * from expired;

  for accepting_row in
    select id
    from public.organization_member_invitations
    where state = 'accepting' and expires_at < now() and lease_expires_at < now()
  loop
    return next private.settle_expired_acceptance(accepting_row.id);
  end loop;

  return;
end;
$$;

revoke all on function public.expire_team_invitations() from public, anon, authenticated;
grant execute on function public.expire_team_invitations() to service_role;

-- 11. The Orphan Rule, verbatim: no Auth attempt in flight releases the seat immediately; a marked attempt
-- only asks 3B's worker to look, and keeps the seat and the email claimed until it does.
create or replace function public.sweep_team_invitation_reservations(
  stale_after interval default interval '1 hour'
)
returns setof public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  return query
    update public.organization_member_invitations
    set state = 'abandoned'
    where state = 'reserving'
      and auth_attempt_started_at is null
      and created_at < now() - stale_after
    returning *;

  return query
    update public.organization_member_invitations
    set identity_cleanup_state = 'required'
    where state = 'reserving'
      and auth_attempt_started_at is not null
      and identity_cleanup_state = 'not_required'
      and created_at < now() - stale_after
    returning *;
end;
$$;

revoke all on function public.sweep_team_invitation_reservations(interval) from public, anon, authenticated;
grant execute on function public.sweep_team_invitation_reservations(interval) to service_role;
