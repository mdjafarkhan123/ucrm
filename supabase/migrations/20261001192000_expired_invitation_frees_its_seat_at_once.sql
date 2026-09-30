-- Package builder P14: an expired invitation frees its seat at once, as a cancelled one already does
-- (20260928090000). Before, the pending membership kept counting until the invitation worker's identity
-- cleanup ran, and indefinitely when that worker was unreachable. The worker still deletes the unused
-- sign-in identity afterwards; its own delete of this pending membership then finds nothing.

CREATE OR REPLACE FUNCTION "public"."expire_team_invitations_bounded"("target_batch_size" integer DEFAULT 25) RETURNS SETOF "public"."organization_member_invitations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
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

      delete from public.organization_members
      where organization_id = updated_row.organization_id
        and user_id = updated_row.invited_user_id
        and status = 'pending';

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
