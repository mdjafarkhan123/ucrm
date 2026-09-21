-- Team & access, Part 3 follow-up: the invitation lifecycle was invisible in the contractor-facing team
-- history. member_access_event_shapes has carried invitation.sent/resent/cancelled/expired/accepted since 3A,
-- but nothing ever inserted them -- the Activity log reader had sentence templates for five event types that
-- never once appeared in real data. This closes that gap by inserting from inside the same commands that
-- already move an invitation through its states, so the trail can never drift from what actually happened.
--
-- invitation.sent is recorded when attach_team_invitation_identity moves reserving -> invited -- the point an
-- invite becomes a real, sendable thing -- not later, so a delivery failure (still tracked separately by
-- last_delivery_error) does not hide that the invite was issued.
--
-- invitation.resent needed a new argument: resend_team_invitation never took an actor. Threaded through from
-- the API route's already-authenticated manager, the same way cancel_team_invitation already does.
--
-- invitation.cancelled is recorded for both an in-flight reservation and an already-issued invite. The
-- accepting-with-lapsed-lease branch is left alone: its outcome is not actually a cancellation, since
-- settle_expired_acceptance may finalize it as accepted, which logs itself.
--
-- invitation.expired is recorded only for the direct invited -> expired transition in
-- expire_team_invitations_bounded. A lapsed accepting lease resolves through that same shared settle path and
-- either finalizes (logging invitation.accepted) or waits for reconciliation, so it is not "expired" yet.
--
-- invitation.accepted is recorded once, in private.finalize_accepted_invitation, so both the normal accept
-- path (finalize_team_invitation) and the worker's late-reconciliation path
-- (finalize_reconciled_team_invitation) log it identically without duplicating the insert.

-- ---------------------------------------------------------------------------
-- invitation.sent
-- ---------------------------------------------------------------------------

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
    raise exception 'Invitation % cannot attach that Auth identity.', target_invitation_id
      using errcode = 'check_violation';
  end if;

  insert into public.organization_members (organization_id, user_id, role, status)
  values (updated_row.organization_id, target_invited_user_id, updated_row.role, 'pending');

  insert into public.organization_member_permission_overrides (
    organization_id, user_id, permission_key, override_state, access_scope
  )
  select
    updated_row.organization_id,
    target_invited_user_id,
    entry.item ->> 'permission_key',
    entry.item ->> 'override_state',
    'all'
  from jsonb_array_elements(updated_row.requested_permission_overrides) as entry(item);

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id, summary
  )
  values (
    updated_row.organization_id, 'invitation.sent', 'member', updated_row.invited_by, updated_row.id,
    jsonb_build_object('role', updated_row.role)
  );

  return updated_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- invitation.resent -- resend_team_invitation gains an actor argument
-- ---------------------------------------------------------------------------

drop function public.resend_team_invitation(uuid, text, timestamptz);

create or replace function public.resend_team_invitation(
  target_invitation_id uuid,
  target_token_hash text,
  target_expires_at timestamptz,
  target_resent_by uuid
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

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id, summary
  )
  values (
    updated_row.organization_id, 'invitation.resent', 'member', target_resent_by, updated_row.id, '{}'::jsonb
  );

  return updated_row;
end;
$$;

revoke all on function public.resend_team_invitation(uuid, text, timestamptz, uuid)
  from public, anon, authenticated;
grant execute on function public.resend_team_invitation(uuid, text, timestamptz, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- invitation.cancelled
-- ---------------------------------------------------------------------------

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
  where id = target_invitation_id
  for update;

  if not found then
    raise exception 'Invitation % does not exist.', target_invitation_id using errcode = 'check_violation';
  end if;

  if current_row.state = 'reserving' and current_row.invited_user_id is null then
    update public.organization_member_invitations
    set state = 'cancelled',
        token_hash = null,
        lease_nonce = null,
        lease_expires_at = null,
        cancelled_at = now(),
        cancelled_by = target_cancelled_by
    where id = target_invitation_id
    returning * into updated_row;

    insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id, summary
    )
    values (
      updated_row.organization_id, 'invitation.cancelled', 'member', target_cancelled_by, updated_row.id,
      '{}'::jsonb
    );

    return updated_row;
  end if;

  if current_row.state in ('reserving', 'invited') then
    update public.organization_member_invitations
    set state = 'cancelled',
        token_hash = null,
        lease_nonce = null,
        lease_expires_at = null,
        cancelled_at = now(),
        cancelled_by = target_cancelled_by,
        identity_cleanup_state = 'required',
        identity_cleanup_error = null
    where id = target_invitation_id
    returning * into updated_row;

    insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id, summary
    )
    values (
      updated_row.organization_id, 'invitation.cancelled', 'member', target_cancelled_by, updated_row.id,
      '{}'::jsonb
    );

    return updated_row;
  end if;

  if current_row.state = 'accepting' then
    if current_row.lease_expires_at > now() then
      raise exception
        'Invitation % has an open acceptance lease; it cannot be cancelled until the lease expires.',
        target_invitation_id
        using errcode = 'check_violation';
    end if;

    -- Not a cancellation: the lapsed lease may still finalize as accepted (settle_expired_acceptance calls
    -- private.finalize_accepted_invitation itself, which logs invitation.accepted), or it may flag the
    -- identity for reconciliation with no terminal outcome yet. Either way, "cancelled" would be a lie.
    return private.settle_expired_acceptance(target_invitation_id);
  end if;

  raise exception 'Invitation % is % and cannot be cancelled.', target_invitation_id, current_row.state
    using errcode = 'check_violation';
end;
$$;

-- ---------------------------------------------------------------------------
-- invitation.expired
-- ---------------------------------------------------------------------------

create or replace function public.expire_team_invitations_bounded(
  target_batch_size integer default 25
)
returns setof public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_row record;
  updated_row public.organization_member_invitations;
begin
  if target_batch_size not between 1 and 100 then
    raise exception 'The invitation expiry batch is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  for target_row in
    select invitation.id
    from public.organization_member_invitations as invitation
    where
      (invitation.state = 'invited' and invitation.expires_at < now())
      or (
        invitation.state = 'accepting'
        and invitation.expires_at < now()
        and invitation.lease_expires_at < now()
      )
    order by invitation.expires_at, invitation.id
    limit target_batch_size
    for update skip locked
  loop
    select * into updated_row
    from public.organization_member_invitations
    where id = target_row.id;

    if updated_row.state = 'invited' then
      update public.organization_member_invitations
      set state = 'expired',
          token_hash = null,
          lease_nonce = null,
          lease_expires_at = null,
          identity_cleanup_state = 'required',
          identity_cleanup_error = null
      where id = target_row.id
      returning * into updated_row;

      insert into public.organization_member_access_events (
        organization_id, event_type, actor_kind, subject_invitation_id, summary
      )
      values (
        updated_row.organization_id, 'invitation.expired', 'system', updated_row.id, '{}'::jsonb
      );
    else
      -- Shares the settle path expire_team_invitations previously used alone: a completed password receipt
      -- finalizes as accepted (logging itself); an unknown outcome is flagged for reconciliation, not expired.
      updated_row := private.settle_expired_acceptance(target_row.id);
    end if;

    return next updated_row;
  end loop;

  return;
end;
$$;

-- ---------------------------------------------------------------------------
-- invitation.accepted
-- ---------------------------------------------------------------------------

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

    insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id, summary
    )
    values (
      updated_row.organization_id, 'invitation.accepted', 'member', updated_row.invited_user_id,
      updated_row.id, jsonb_build_object('role', updated_row.role)
    );

    return updated_row;
  end if;

  select * into updated_row
  from public.organization_member_invitations
  where id = target_invitation_id;

  return updated_row;
end;
$$;
