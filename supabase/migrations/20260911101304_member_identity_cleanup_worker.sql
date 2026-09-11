-- Contractor Settings 3E-2b: lease primitives for the identity cleanup that follows a permanent removal.
--
-- remove_team_member already parks the membership at identity_cleanup_state = 'required'. Banning the dead
-- login and renaming its address are Auth HTTP calls that cannot sit inside that transaction, so this layer
-- gives the worker the same claim-with-lease shape the invitation reconciliation worker already uses: a
-- short lease held while Auth is contacted, and step recording a stale worker cannot write behind.

alter table public.organization_members
  add column identity_cleanup_nonce uuid,
  add column identity_cleanup_lease_expires_at timestamptz;

alter table public.organization_members
  add constraint organization_members_identity_cleanup_lease_pair_check
    check (
      (identity_cleanup_nonce is null and identity_cleanup_lease_expires_at is null)
      or (identity_cleanup_nonce is not null and identity_cleanup_lease_expires_at is not null)
    );

comment on column public.organization_members.identity_cleanup_nonce is
  'Short worker lease. It coordinates the Auth ban and email release without holding a database transaction '
  'across the network call.';

-- Bounded worker scan: never-leased rows first, then expired leases, oldest removal first. Settled and
-- never-removed memberships stay out of the index entirely, and the expression order matches the claim
-- command''s ORDER BY exactly.
create index organization_members_identity_cleanup_queue_idx
  on public.organization_members (
    coalesce(identity_cleanup_lease_expires_at, '-infinity'::timestamptz), removed_at, user_id
  )
  where identity_cleanup_state in ('required', 'ban_applied', 'email_released');

-- ---------------------------------------------------------------------------
-- 1. Claim
-- ---------------------------------------------------------------------------

create or replace function public.claim_member_identity_cleanup(
  target_lease_nonce uuid,
  target_batch_size integer default 25,
  target_lease_seconds integer default 300
)
returns setof public.organization_members
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if target_batch_size not between 1 and 100 or target_lease_seconds not between 30 and 1800 then
    raise exception 'The identity cleanup lease is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  return query
    with claimable as (
      select membership.organization_id, membership.user_id
      from public.organization_members as membership
      where membership.identity_cleanup_state in ('required', 'ban_applied', 'email_released')
        and (
          membership.identity_cleanup_lease_expires_at is null
          or membership.identity_cleanup_lease_expires_at < now()
        )
      order by
        coalesce(membership.identity_cleanup_lease_expires_at, '-infinity'::timestamptz),
        membership.removed_at,
        membership.user_id
      limit target_batch_size
      for update skip locked
    )
    update public.organization_members as membership
    set identity_cleanup_nonce = target_lease_nonce,
        identity_cleanup_lease_expires_at = now() + make_interval(secs => target_lease_seconds)
    from claimable
    where membership.organization_id = claimable.organization_id
      and membership.user_id = claimable.user_id
    returning membership.*;
end;
$$;

comment on function public.claim_member_identity_cleanup(uuid, integer, integer) is
  'Leases a bounded batch of removed members whose Auth cleanup is unfinished. Concurrent runs skip each '
  'other''s rows instead of waiting.';

revoke all on function public.claim_member_identity_cleanup(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.claim_member_identity_cleanup(uuid, integer, integer) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Record a step under the lease
-- ---------------------------------------------------------------------------

-- mark_member_identity_revoked stays the single ledger writer -- forward only, and the owner of the one
-- member.identity_revoked history line. This wrapper adds what the worker needs on top: the step is accepted
-- only from the run that still holds the lease, and finishing hands the lease back.
create or replace function public.record_member_identity_cleanup_step(
  target_organization_id uuid,
  target_user_id uuid,
  target_lease_nonce uuid,
  new_cleanup_state text,
  cleanup_error text default null
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
begin
  select membership_row.* into membership
  from public.organization_members as membership_row
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
    and membership_row.identity_cleanup_nonce = target_lease_nonce
    and membership_row.identity_cleanup_lease_expires_at > now()
  for update;

  if not found then
    raise exception 'The identity cleanup lease is no longer valid.'
      using errcode = 'serialization_failure';
  end if;

  membership := public.mark_member_identity_revoked(
    target_organization_id, target_user_id, new_cleanup_state, cleanup_error
  );

  if new_cleanup_state = 'done' then
    update public.organization_members as membership_row
    set identity_cleanup_nonce = null,
        identity_cleanup_lease_expires_at = null
    where membership_row.organization_id = target_organization_id
      and membership_row.user_id = target_user_id
    returning membership_row.* into membership;
  end if;

  return membership;
end;
$$;

comment on function public.record_member_identity_cleanup_step(uuid, uuid, uuid, text, text) is
  'Records one Auth cleanup step for the run holding the lease, and releases the lease once the cleanup is '
  'done.';

revoke all on function public.record_member_identity_cleanup_step(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.record_member_identity_cleanup_step(uuid, uuid, uuid, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Hand the lease back after a failure
-- ---------------------------------------------------------------------------

-- A failed attempt should be retryable now rather than at lease expiry, and visibly stuck rather than
-- silently stuck. The ledger state is left exactly where it got to.
create or replace function public.release_member_identity_cleanup(
  target_organization_id uuid,
  target_user_id uuid,
  target_lease_nonce uuid,
  target_safe_error text
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  released_row public.organization_members;
begin
  update public.organization_members as membership_row
  set identity_cleanup_error = left(nullif(btrim(target_safe_error), ''), 240),
      identity_cleanup_nonce = null,
      identity_cleanup_lease_expires_at = null
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
    and membership_row.identity_cleanup_nonce = target_lease_nonce
    and membership_row.identity_cleanup_lease_expires_at > now()
  returning membership_row.* into released_row;

  if not found then
    raise exception 'The identity cleanup lease is no longer valid.'
      using errcode = 'serialization_failure';
  end if;

  return released_row;
end;
$$;

comment on function public.release_member_identity_cleanup(uuid, uuid, uuid, text) is
  'Hands back an identity cleanup lease after a failed Auth call and records why, so the next run retries '
  'immediately and a stuck cleanup stays visible.';

revoke all on function public.release_member_identity_cleanup(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.release_member_identity_cleanup(uuid, uuid, uuid, text) to service_role;
