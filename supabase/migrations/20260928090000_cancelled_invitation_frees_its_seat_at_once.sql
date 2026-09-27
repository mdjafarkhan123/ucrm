-- Cancelling a sent invitation now frees its seat and drops the person from the Team list at once.
-- Before, the pending membership lingered until the invitation worker's identity cleanup ran, so the Team
-- page kept showing the cancelled person and counting their seat for up to five minutes (indefinitely when
-- the worker was unreachable). The worker still deletes the unused sign-in identity afterwards; its own
-- delete of this pending membership then finds nothing, which it already tolerates.

CREATE OR REPLACE FUNCTION "public"."cancel_team_invitation"("target_invitation_id" "uuid", "target_cancelled_by" "uuid") RETURNS "public"."organization_member_invitations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
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

    delete from public.organization_members
    where organization_id = updated_row.organization_id
      and user_id = current_row.invited_user_id
      and status = 'pending';

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


ALTER FUNCTION "public"."cancel_team_invitation"("target_invitation_id" "uuid", "target_cancelled_by" "uuid") OWNER TO "postgres";
