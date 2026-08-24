-- A cancelled invitation may still own an Auth identity. Keep its normalized email reserved and its pending
-- seat intact until the worker confirms Auth deletion; otherwise a retry can strand the identity or let a
-- second invitation race the same login email.

drop index public.organization_member_invitations_pending_email_idx;
create unique index organization_member_invitations_pending_email_idx
  on public.organization_member_invitations (lower(invited_email))
  where state in ('reserving', 'invited', 'accepting') or identity_cleanup_state = 'required';

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

-- Cleanup preparation keeps a manager-requested cancellation terminal while atomically detaching the Auth
-- identity. Other reconciliation paths still withdraw to reserving until their uncertain outcome is settled.
create or replace function public.prepare_team_invitation_identity_cleanup(
  target_invitation_id uuid,
  target_lease_nonce uuid
)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_invited_user_id uuid;
  prepared_row public.organization_member_invitations;
begin
  select invitation.invited_user_id
  into target_invited_user_id
  from public.organization_member_invitations as invitation
  where invitation.id = target_invitation_id
    and (
      invitation.state in ('reserving', 'invited', 'accepting')
      or invitation.state = 'cancelled'
    )
    and invitation.identity_cleanup_state = 'required'
    and invitation.reconciliation_nonce = target_lease_nonce
    and invitation.reconciliation_lease_expires_at > now()
  for update;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.' using errcode = 'serialization_failure';
  end if;

  update public.organization_member_invitations
  set state = case when state = 'cancelled' then 'cancelled' else 'reserving' end,
      invited_user_id = null,
      token_hash = null,
      lease_nonce = null,
      lease_expires_at = null
  where id = target_invitation_id
  returning * into prepared_row;

  delete from public.organization_members
  where organization_id = prepared_row.organization_id
    and user_id = target_invited_user_id
    and status = 'pending';

  return prepared_row;
end;
$$;

revoke all on function public.prepare_team_invitation_identity_cleanup(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.prepare_team_invitation_identity_cleanup(uuid, uuid) to service_role;
