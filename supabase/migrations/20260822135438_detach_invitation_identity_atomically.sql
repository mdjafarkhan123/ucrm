-- The invitation state constraint requires reserving and invited_user_id = null in the same row version.
-- Capture the pending identity under the live worker lease, detach it atomically, then remove its membership.

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
    and invitation.state in ('reserving', 'invited', 'accepting')
    and invitation.identity_cleanup_state = 'required'
    and invitation.reconciliation_nonce = target_lease_nonce
    and invitation.reconciliation_lease_expires_at > now()
  for update;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.' using errcode = 'serialization_failure';
  end if;

  update public.organization_member_invitations
  set state = 'reserving',
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
