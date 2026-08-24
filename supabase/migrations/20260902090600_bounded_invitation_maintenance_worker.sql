-- Contractor Settings 3B: make every invitation maintenance pass bounded and recover the
-- two Auth crash boundaries without holding database locks across Auth network calls.

create index organization_member_invitations_reserving_age_idx
  on public.organization_member_invitations (created_at, id)
  where state = 'reserving';

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
    else
      updated_row := private.settle_expired_acceptance(target_row.id);
    end if;

    return next updated_row;
  end loop;

  return;
end;
$$;

revoke all on function public.expire_team_invitations_bounded(integer)
  from public, anon, authenticated;
grant execute on function public.expire_team_invitations_bounded(integer) to service_role;

create or replace function public.expire_team_invitations()
returns setof public.organization_member_invitations
language sql
security definer
set search_path = pg_catalog, public
as $$
  select * from public.expire_team_invitations_bounded(100);
$$;

revoke all on function public.expire_team_invitations() from public, anon, authenticated;
grant execute on function public.expire_team_invitations() to service_role;

create or replace function public.sweep_team_invitation_reservations_bounded(
  target_batch_size integer default 25,
  target_stale_after interval default interval '1 hour'
)
returns setof public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  target_row record;
  updated_row public.organization_member_invitations;
begin
  if target_batch_size not between 1 and 100
     or target_stale_after < interval '5 minutes'
     or target_stale_after > interval '24 hours' then
    raise exception 'The invitation reservation sweep is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  for target_row in
    select invitation.id
    from public.organization_member_invitations as invitation
    where invitation.state = 'reserving'
      and invitation.created_at < now() - target_stale_after
    order by invitation.created_at, invitation.id
    limit target_batch_size
    for update skip locked
  loop
    update public.organization_member_invitations
    set state = case when auth_attempt_started_at is null then 'abandoned' else state end,
        identity_cleanup_state = case
          when auth_attempt_started_at is null then identity_cleanup_state
          else 'required'
        end,
        identity_cleanup_error = case
          when auth_attempt_started_at is null then identity_cleanup_error
          else null
        end
    where id = target_row.id
    returning * into updated_row;

    return next updated_row;
  end loop;

  return;
end;
$$;

revoke all on function public.sweep_team_invitation_reservations_bounded(integer, interval)
  from public, anon, authenticated;
grant execute on function public.sweep_team_invitation_reservations_bounded(integer, interval)
  to service_role;

create or replace function public.sweep_team_invitation_reservations(
  stale_after interval default interval '1 hour'
)
returns setof public.organization_member_invitations
language sql
security invoker
set search_path = pg_catalog, public
as $$
  select * from public.sweep_team_invitation_reservations_bounded(100, stale_after);
$$;

revoke all on function public.sweep_team_invitation_reservations(interval)
  from public, anon, authenticated;
grant execute on function public.sweep_team_invitation_reservations(interval) to service_role;

-- Attached invitations are resolved by their immutable Auth id. A reservation whose Auth create
-- outcome was lost has no id yet, so only that case falls back to the normalized email.
create or replace function public.find_team_invitation_auth_receipt(target_invitation_id uuid)
returns table (
  user_id uuid,
  identity_invitation_id text,
  password_set_invitation_id text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    auth_user.id,
    auth_user.raw_app_meta_data ->> 'team_invitation_identity_for',
    auth_user.raw_app_meta_data ->> 'invitation_password_set_for'
  from public.organization_member_invitations as invitation
  join auth.users as auth_user
    on (
      invitation.invited_user_id is not null
      and auth_user.id = invitation.invited_user_id
    ) or (
      invitation.invited_user_id is null
      and lower(auth_user.email) = lower(invitation.invited_email)
    )
  where invitation.id = target_invitation_id
  order by (auth_user.id = invitation.invited_user_id) desc, auth_user.id
  limit 1;
$$;

revoke all on function public.find_team_invitation_auth_receipt(uuid)
  from public, anon, authenticated;
grant execute on function public.find_team_invitation_auth_receipt(uuid) to service_role;

-- The worker may recover a password write only when Auth itself carries both invitation receipts.
-- Rechecking those receipts inside this command keeps the database, not caller input, authoritative.
create or replace function public.finalize_reconciled_team_invitation(
  target_invitation_id uuid,
  target_lease_nonce uuid
)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_row public.organization_member_invitations;
begin
  select invitation.* into current_row
  from public.organization_member_invitations as invitation
  join auth.users as auth_user on auth_user.id = invitation.invited_user_id
  where invitation.id = target_invitation_id
    and invitation.state = 'accepting'
    and invitation.identity_cleanup_state = 'required'
    and invitation.reconciliation_nonce = target_lease_nonce
    and invitation.reconciliation_lease_expires_at > now()
    and auth_user.raw_app_meta_data ->> 'team_invitation_identity_for' = invitation.id::text
    and auth_user.raw_app_meta_data ->> 'invitation_password_set_for' = invitation.id::text
  for update of invitation;

  if not found then
    raise exception 'The invitation reconciliation receipt is not valid.'
      using errcode = 'serialization_failure';
  end if;

  update public.organization_member_invitations
  set password_set_at = coalesce(password_set_at, now()),
      identity_cleanup_state = 'not_required',
      identity_cleanup_error = null,
      reconciliation_nonce = null,
      reconciliation_lease_expires_at = null
  where id = target_invitation_id;

  return private.finalize_accepted_invitation(target_invitation_id);
end;
$$;

revoke all on function public.finalize_reconciled_team_invitation(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.finalize_reconciled_team_invitation(uuid, uuid) to service_role;

-- Cleanup preparation must also detach identities after expiry or abandonment. The terminal state remains
-- visible while the Auth account and pending membership are removed under the live worker lease.
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
    and invitation.state in ('reserving', 'invited', 'accepting', 'cancelled', 'expired', 'abandoned')
    and invitation.identity_cleanup_state = 'required'
    and invitation.reconciliation_nonce = target_lease_nonce
    and invitation.reconciliation_lease_expires_at > now()
  for update;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.'
      using errcode = 'serialization_failure';
  end if;

  update public.organization_member_invitations
  set state = case
        when state in ('cancelled', 'expired', 'abandoned') then state
        else 'reserving'
      end,
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
