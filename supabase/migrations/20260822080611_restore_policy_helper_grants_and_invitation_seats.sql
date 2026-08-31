-- Team & access, part 3A, layer 5: seat usage and the invitations table it depends on.
--
-- Reordered on Jafar's instruction: a seat-used formula that counts invitation reservations cannot be
-- built, applied, or tested correctly before the invitations table exists, and a membership-only
-- intermediate would silently undercount seats -- concurrent invitation reservations could exceed the limit
-- if that partial version were ever relied on. Seats used = memberships in (pending, active) + invitations
-- in reserving. Built together, in one migration, per the 3A packet's explicit instruction not to split
-- seat-used from the invitations table again.
--
-- Drift fix first: 20260825090100_membership_status_authorization_seam.sql's closing `revoke all ... from
-- ... authenticated` line took EXECUTE off the four RLS policy helpers, contradicting that same session's
-- own "a policy helper must keep EXECUTE for authenticated" rule (policy expressions run as the querying
-- user). The live database already carries a corrective grant -- verified via has_function_privilege before
-- writing this file -- so today's reads work, but no migration says so. This closes that gap so the
-- checked-in history matches what is actually running: replaying migrations from zero must not revoke
-- EXECUTE out from under every existing RLS policy in the app.
grant execute on function private.is_organization_member(uuid) to authenticated;
grant execute on function private.is_organization_admin(uuid) to authenticated;
grant execute on function private.has_permission(uuid, text) to authenticated;
grant execute on function private.permitted_organizations(text) to authenticated;

-- The invitations table. Columns map directly onto the 3A packet's per-state invariants table and its
-- Orphan Rule section. `state` collapses the packet's "identity_created ... accepting" range into one
-- `invited` state plus `last_sent_at` / `last_delivery_error`, following the existing
-- platform_onboarding_application_setup_links convention (issueSetupLink) rather than inventing a new
-- delivery-status enum: the blueprint's visible "Delivery failed" state is `invited` with a non-null
-- `last_delivery_error`, not a separate persisted value. `accepting` stays its own state because it is the
-- leased, race-guarded phase with columns nothing else needs (`lease_nonce`, `lease_expires_at`).
create table public.organization_member_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invited_email text not null check (
    char_length(trim(invited_email)) between 3 and 254
    and invited_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  role text not null check (role in ('admin', 'office', 'sales', 'field', 'finance')),
  state text not null default 'reserving' check (
    state in ('reserving', 'invited', 'accepting', 'accepted', 'cancelled', 'expired', 'abandoned')
  ),
  invited_user_id uuid references auth.users(id) on delete set null,
  invited_by uuid references auth.users(id) on delete set null,
  token_hash text,
  lease_nonce uuid,
  lease_expires_at timestamptz,
  auth_attempt_started_at timestamptz,
  identity_cleanup_state text not null default 'not_required' check (
    identity_cleanup_state in ('not_required', 'required', 'ban_applied', 'email_released', 'done')
  ),
  identity_cleanup_error text,
  last_sent_at timestamptz,
  last_delivery_error text,
  expires_at timestamptz,
  accepted_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  -- The invariants table, enforced: no auth identity while reserving; an identity for every later
  -- non-terminal state and for the accepted terminal state. cancelled/expired/abandoned make no claim
  -- either way, matching "Auth user: deleted by 3B" -- 3A does not own that deletion.
  constraint organization_member_invitations_identity_matches_state_check check (
    (state = 'reserving' and invited_user_id is null)
    or (state in ('invited', 'accepting', 'accepted') and invited_user_id is not null)
    or (state in ('cancelled', 'expired', 'abandoned'))
  ),
  constraint organization_member_invitations_accepted_at_check check (
    (state = 'accepted') = (accepted_at is not null)
  ),
  constraint organization_member_invitations_cancelled_at_check check (
    (state = 'cancelled') = (cancelled_at is not null)
  )
);

comment on column public.organization_member_invitations.state is
  'reserving (no identity yet) -> invited (identity + delivery attempted) -> accepting (leased claim) -> '
  'accepted, or cancelled/expired/abandoned. See parts/03a-access-and-data-foundation.md invariants table.';
comment on column public.organization_member_invitations.last_delivery_error is
  'Non-null while state = invited means the blueprint''s visible Delivery failed state. No separate enum '
  'value, matching issueSetupLink''s last_error convention.';
comment on column public.organization_member_invitations.auth_attempt_started_at is
  'Orphan Rule: stamped immediately before calling Auth. The sweep may only release the seat and mark '
  'abandoned while this is null; otherwise identity_cleanup_state moves to required and the seat stays held.';
comment on column public.organization_member_invitations.token_hash is
  'sha256 hex of the acceptance token, following issueSetupLink (src/lib/server/jafar/setup-link.ts). The '
  'raw token is never stored.';

-- The Orphan Rule's partial unique index: one non-terminal invitation per email per organization. Accepted
-- is excluded on purpose so a removed-then-reinvited person gets a fresh row.
create unique index organization_member_invitations_pending_email_idx
  on public.organization_member_invitations (organization_id, lower(invited_email))
  where state in ('reserving', 'invited', 'accepting');

-- Claim looks up by token alone, so this is global rather than per-organization.
create unique index organization_member_invitations_token_hash_idx
  on public.organization_member_invitations (token_hash)
  where token_hash is not null;

-- The future team/invitations list pages by state inside one organization.
create index organization_member_invitations_organization_state_idx
  on public.organization_member_invitations (organization_id, state, created_at desc);

create index organization_member_invitations_invited_user_id_idx
  on public.organization_member_invitations (invited_user_id)
  where invited_user_id is not null;

alter table public.organization_member_invitations enable row level security;

-- Read-only for authenticated: every mutation is a service_role primitive (item 3, a future session),
-- exactly like the membership lifecycle writes today. Reuses the existing once-per-query permission helper
-- instead of adding a new one.
create policy "team managers can view invitations"
  on public.organization_member_invitations
  for select
  to authenticated
  using (organization_id in (select private.permitted_organizations('team.manage')));

grant select on public.organization_member_invitations to authenticated;

-- Seats used = memberships in (pending, active) + invitations in reserving. Once an invitation reaches
-- `invited`, a pending membership row already exists and is counted there instead -- counting both would
-- double count the same seat.
create or replace function private.employee_seats_used(target_organization_id uuid)
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    (
      select count(*)::integer
      from public.organization_members as membership
      where membership.organization_id = target_organization_id
        and membership.status in ('pending', 'active')
    )
    +
    (
      select count(*)::integer
      from public.organization_member_invitations as invitation
      where invitation.organization_id = target_organization_id
        and invitation.state = 'reserving'
    );
$$;

-- Takes the advisory lock before comparing, so two concurrent reservations for the same organization
-- serialize instead of both reading "one seat free" and both proceeding. Namespaced by a string key
-- (references/lock-advisory.md's single-hashtext-argument pattern) -- a hash collision between two
-- different organizations only costs an extra wait, never a wrong count, because the count is read after
-- the lock is held.
create or replace function private.assert_employee_seat_available(target_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  seat_limit record;
  seats_used integer;
begin
  perform pg_advisory_xact_lock(hashtext('employee_seats:' || target_organization_id::text));

  select *
  into seat_limit
  from public.effective_employee_seat_limit(target_organization_id);

  seats_used := private.employee_seats_used(target_organization_id);

  if not seat_limit.is_unlimited and seats_used >= coalesce(seat_limit.value, 0) then
    raise exception 'No employee seats are available for this organization.'
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function private.employee_seats_used(uuid) is
  'Single authority for employee seats consumed. Counts memberships in (pending, active) plus invitations '
  'in reserving -- never both for the same seat.';
comment on function private.assert_employee_seat_available(uuid) is
  'Advisory-lock-guarded seat check for the future invitation/restoration command primitives (item 3). Not '
  'an RPC target -- called only from other SECURITY DEFINER commands, like private.member_has_permission.';

-- Command-support helpers for the future service_role primitives, not something a client calls directly --
-- fully locked down, matching private.member_has_permission.
revoke all on function private.employee_seats_used(uuid) from public, anon, authenticated, service_role;
revoke all on function private.assert_employee_seat_available(uuid)
  from public, anon, authenticated, service_role;
