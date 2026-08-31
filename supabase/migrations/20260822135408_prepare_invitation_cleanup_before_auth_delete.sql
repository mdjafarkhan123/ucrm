-- Auth deletion sets organization_member_invitations.invited_user_id to null. The invitation state check
-- permits that only for reserving/terminal rows, so cleanup preparation must also withdraw the usable link
-- while keeping the reservation open, seat-counted, email-claimed, and cleanup-required.

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
  prepared_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set state = 'reserving',
      token_hash = null,
      lease_nonce = null,
      lease_expires_at = null
  where id = target_invitation_id
    and state in ('reserving', 'invited', 'accepting')
    and identity_cleanup_state = 'required'
    and reconciliation_nonce = target_lease_nonce
    and reconciliation_lease_expires_at > now()
  returning * into prepared_row;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.' using errcode = 'serialization_failure';
  end if;

  delete from public.organization_members
  where organization_id = prepared_row.organization_id
    and user_id = prepared_row.invited_user_id
    and status = 'pending';

  return prepared_row;
end;
$$;

revoke all on function public.prepare_team_invitation_identity_cleanup(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.prepare_team_invitation_identity_cleanup(uuid, uuid) to service_role;
