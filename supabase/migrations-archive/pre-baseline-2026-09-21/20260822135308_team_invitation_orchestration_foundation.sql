-- Contractor Settings 3B, layer 1: persist invitation-time permission adjustments, close the
-- cross-organization email race, and give the Auth reconciliation worker a pooled-connection-safe lease.

alter table public.organization_member_invitations
  add column requested_permission_overrides jsonb not null default '[]'::jsonb,
  add column reconciliation_nonce uuid,
  add column reconciliation_lease_expires_at timestamptz;

alter table public.organization_member_invitations
  add constraint organization_member_invitations_requested_overrides_array_check
    check (jsonb_typeof(requested_permission_overrides) = 'array'),
  add constraint organization_member_invitations_reconciliation_lease_pair_check
    check (
      (reconciliation_nonce is null and reconciliation_lease_expires_at is null)
      or (reconciliation_nonce is not null and reconciliation_lease_expires_at is not null)
    );

comment on column public.organization_member_invitations.requested_permission_overrides is
  'Validated invitation-time adjustments copied atomically to the pending membership when Auth identity attachment succeeds.';
comment on column public.organization_member_invitations.reconciliation_nonce is
  'Short worker lease. It coordinates Auth cleanup without holding a database transaction across the network call.';

-- One login email may belong to only one contractor organization. The old organization-leading index
-- allowed two organizations to reserve the same normalized email concurrently before Auth rejected one.
drop index public.organization_member_invitations_pending_email_idx;
create unique index organization_member_invitations_pending_email_idx
  on public.organization_member_invitations (lower(invited_email))
  where state in ('reserving', 'invited', 'accepting');

-- Bounded worker scan: immediately claim never-leased rows, then expired leases, oldest first. Settled rows
-- do not bloat this index, and the expression order matches the worker's ORDER BY exactly.
create index organization_member_invitations_cleanup_queue_idx
  on public.organization_member_invitations (
    coalesce(reconciliation_lease_expires_at, '-infinity'::timestamptz), created_at, id
  )
  where identity_cleanup_state = 'required';

create or replace function private.assert_team_invitation_overrides(
  target_role text,
  target_overrides jsonb
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if target_overrides is null or jsonb_typeof(target_overrides) <> 'array' then
    raise exception 'The permission adjustments must be a list.' using errcode = 'check_violation';
  end if;

  if target_role = 'admin' and jsonb_array_length(target_overrides) <> 0 then
    raise exception 'Administrator invitations use standard administrator access.'
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(target_overrides) as entry(item)
    where jsonb_typeof(entry.item) <> 'object'
      or (entry.item ->> 'permission_key') is null
      or (entry.item ->> 'override_state') not in ('grant', 'deny')
      or coalesce(entry.item ->> 'access_scope', 'all') <> 'all'
      or not exists (
        select 1 from public.permissions as permission
        where permission.key = entry.item ->> 'permission_key'
      )
  ) then
    raise exception 'One of those permission adjustments is not available.'
      using errcode = 'check_violation';
  end if;

  if exists (
    select entry.item ->> 'permission_key'
    from jsonb_array_elements(target_overrides) as entry(item)
    group by entry.item ->> 'permission_key'
    having count(*) > 1
  ) then
    raise exception 'The same permission was adjusted twice.' using errcode = 'check_violation';
  end if;
end;
$$;

revoke all on function private.assert_team_invitation_overrides(text, jsonb)
  from public, anon, authenticated, service_role;

-- The five-argument command replaces the 3A entry point. Team commands deliberately do not use overloads:
-- one name means one grant surface, and callers must always make the adjustments explicit.
drop function public.begin_team_invitation(uuid, text, text, uuid);

create or replace function public.begin_team_invitation(
  target_organization_id uuid,
  target_invited_email text,
  target_role text,
  target_invited_by uuid,
  target_permission_overrides jsonb
)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_row public.organization_member_invitations;
begin
  perform private.assert_team_invitation_overrides(target_role, target_permission_overrides);
  perform private.assert_employee_seat_available(target_organization_id);

  insert into public.organization_member_invitations (
    organization_id, invited_email, role, invited_by, state, requested_permission_overrides
  ) values (
    target_organization_id, lower(trim(target_invited_email)), target_role, target_invited_by,
    'reserving', target_permission_overrides
  )
  returning * into new_row;

  return new_row;
end;
$$;

revoke all on function public.begin_team_invitation(uuid, text, text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.begin_team_invitation(uuid, text, text, uuid, jsonb) to service_role;

-- Replace the 3A identity attachment so pending membership and its requested adjustments appear in the
-- same transaction. There is never a partially configured pending member.
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

  return updated_row;
end;
$$;

revoke all on function public.attach_team_invitation_identity(uuid, uuid, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.attach_team_invitation_identity(uuid, uuid, uuid, text, timestamptz)
  to service_role;

-- Exact server-only Auth lookup. It returns only the identity id and the two invitation receipts required
-- for reconciliation; email, secrets, and unrestricted metadata never cross this seam.
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
  join auth.users as auth_user on lower(auth_user.email) = lower(invitation.invited_email)
  where invitation.id = target_invitation_id
  limit 1;
$$;

revoke all on function public.find_team_invitation_auth_receipt(uuid)
  from public, anon, authenticated;
grant execute on function public.find_team_invitation_auth_receipt(uuid) to service_role;

create or replace function public.claim_team_invitation_reconciliation(
  target_lease_nonce uuid,
  target_batch_size integer default 25,
  target_lease_seconds integer default 300
)
returns setof public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if target_batch_size not between 1 and 100 or target_lease_seconds not between 30 and 1800 then
    raise exception 'The reconciliation lease is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  return query
    with claimable as (
      select invitation.id
      from public.organization_member_invitations as invitation
      where invitation.identity_cleanup_state = 'required'
        and (
          invitation.reconciliation_lease_expires_at is null
          or invitation.reconciliation_lease_expires_at < now()
        )
      order by
        coalesce(invitation.reconciliation_lease_expires_at, '-infinity'::timestamptz),
        invitation.created_at,
        invitation.id
      limit target_batch_size
      for update skip locked
    )
    update public.organization_member_invitations as invitation
    set reconciliation_nonce = target_lease_nonce,
        reconciliation_lease_expires_at = now() + make_interval(secs => target_lease_seconds)
    from claimable
    where invitation.id = claimable.id
    returning invitation.*;
end;
$$;

revoke all on function public.claim_team_invitation_reconciliation(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.claim_team_invitation_reconciliation(uuid, integer, integer)
  to service_role;

-- Auth deletion cannot run while organization_members still references the pending identity. Remove only
-- that pending membership under the worker lease first, while leaving the invitation open, cleanup-required,
-- globally email-claimed, and seat-counted until the external Auth deletion is known to have succeeded.
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
  select * into prepared_row
  from public.organization_member_invitations
  where id = target_invitation_id
    and identity_cleanup_state = 'required'
    and reconciliation_nonce = target_lease_nonce
    and reconciliation_lease_expires_at > now()
  for update;

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

create or replace function public.settle_team_invitation_identity_cleanup(
  target_invitation_id uuid,
  target_lease_nonce uuid
)
returns public.organization_member_invitations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settled_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set state = case when state in ('reserving', 'invited', 'accepting') then 'abandoned' else state end,
      token_hash = null,
      lease_nonce = null,
      lease_expires_at = null,
      identity_cleanup_state = 'done',
      identity_cleanup_error = null,
      reconciliation_nonce = null,
      reconciliation_lease_expires_at = null
  where id = target_invitation_id
    and identity_cleanup_state = 'required'
    and reconciliation_nonce = target_lease_nonce
    and reconciliation_lease_expires_at > now()
  returning * into settled_row;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.' using errcode = 'serialization_failure';
  end if;

  return settled_row;
end;
$$;

revoke all on function public.settle_team_invitation_identity_cleanup(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.settle_team_invitation_identity_cleanup(uuid, uuid) to service_role;

create or replace function public.release_team_invitation_reconciliation(
  target_invitation_id uuid,
  target_lease_nonce uuid,
  target_safe_error text
)
returns public.organization_member_invitations
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  released_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set identity_cleanup_error = left(nullif(trim(target_safe_error), ''), 240),
      reconciliation_nonce = null,
      reconciliation_lease_expires_at = null
  where id = target_invitation_id
    and identity_cleanup_state = 'required'
    and reconciliation_nonce = target_lease_nonce
    and reconciliation_lease_expires_at > now()
  returning * into released_row;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.' using errcode = 'serialization_failure';
  end if;
  return released_row;
end;
$$;

revoke all on function public.release_team_invitation_reconciliation(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.release_team_invitation_reconciliation(uuid, uuid, text) to service_role;
