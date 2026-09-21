-- Replacing a pending invitation email must release only the identity that the manager just cancelled.
-- The general reconciliation worker claims an arbitrary bounded batch, so it is not safe for a synchronous
-- manager request. This command leases one tenant-owned cancelled invitation for the existing prepare/delete/
-- settle cleanup sequence.

create or replace function public.claim_cancelled_team_invitation_cleanup(
  target_organization_id uuid,
  target_invitation_id uuid,
  target_lease_nonce uuid,
  target_lease_seconds integer default 300
)
returns public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  claimed_row public.organization_member_invitations;
begin
  if target_lease_seconds not between 30 and 1800 then
    raise exception 'The reconciliation lease is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  update public.organization_member_invitations
  set reconciliation_nonce = target_lease_nonce,
      reconciliation_lease_expires_at = now() + make_interval(secs => target_lease_seconds)
  where id = target_invitation_id
    and organization_id = target_organization_id
    and state = 'cancelled'
    and identity_cleanup_state = 'required'
    and invited_user_id is not null
    and (
      reconciliation_lease_expires_at is null
      or reconciliation_lease_expires_at < now()
    )
  returning * into claimed_row;

  if not found then
    raise exception 'The cancelled invitation is not available for cleanup.'
      using errcode = 'serialization_failure';
  end if;

  return claimed_row;
end;
$$;

revoke all on function public.claim_cancelled_team_invitation_cleanup(uuid, uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.claim_cancelled_team_invitation_cleanup(uuid, uuid, uuid, integer)
  to service_role;
