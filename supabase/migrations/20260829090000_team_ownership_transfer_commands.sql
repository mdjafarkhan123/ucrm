-- Team & access, part 3A, item 5: ownership transfer, and the three commands that move it.
--
-- The blueprint's rule is that ownership changes only through a request the recipient accepts: "The current
-- Owner may transfer ownership only to an active Administrator... sends a request that the recipient must
-- accept. Until acceptance, nothing changes and the Owner may cancel. On acceptance, the recipient becomes
-- Owner and the former Owner becomes Administrator." So a transfer is a row with a life of its own, not a
-- role update with a confirmation dialog in front of it.
--
-- The packet's "Ownership transfer has no bypass" section is the binding constraint, and it names three
-- layers that do not trust each other:
--   * authenticated holds no write grant on this table, so only the SECURITY DEFINER commands below write;
--   * each command re-checks owner and administrator standing itself, at the moment it acts, rather than
--     believing what the request row said when it was created;
--   * the partial unique index (at most one owner) and the deferred constraint trigger (exactly one active
--     owner at commit) from 20260825090000 prove the invariant independently of both.
-- Accept demotes the old owner *before* promoting the new one, inside one transaction, so the immediate
-- at-most-one index is never asked to hold two owners and the deferred trigger sees one owner at commit.
--
-- Three commands cover the four seeded ownership.transfer_* event shapes because who ends a pending
-- transfer is the database's decision, not a flag the caller passes: the requester closing it is a
-- cancellation, the recipient closing it is a decline. A caller cannot mislabel what it did.
--
-- Not here, on purpose: the Owner's password/MFA confirmation and the notification emails are orchestration
-- and belong to 3B/3E, and a transfer request has no expiry -- the blueprint asks for none, and the owner
-- can always cancel.

create table public.organization_ownership_transfers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- on delete no action, matching organization_member_access_events and the 24 authorship columns: a
  -- transfer that forgot who asked or who accepted is worse than a delete that fails loudly.
  from_user_id uuid not null references auth.users(id) on delete no action,
  to_user_id uuid not null references auth.users(id) on delete no action,
  state text not null default 'pending' check (
    state in ('pending', 'accepted', 'declined', 'cancelled')
  ),
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete no action,

  constraint organization_ownership_transfers_distinct_parties_check check (from_user_id <> to_user_id),
  -- Pending means unresolved, and resolved means we know when and by whom. Both halves, so a command
  -- cannot settle a transfer while leaving it looking open.
  constraint organization_ownership_transfers_resolution_check check (
    (state = 'pending') = (resolved_at is null)
    and (state = 'pending') = (resolved_by is null)
  )
);

comment on table public.organization_ownership_transfers is
  'One ownership handover: the owner asked, and the administrator has not yet answered. Until state leaves '
  'pending nothing about anyone''s role has changed. Read-only for authenticated; every write is one of the '
  'three SECURITY DEFINER commands in this migration.';
comment on column public.organization_ownership_transfers.from_user_id is
  'The owner who asked. Re-checked as the active owner at acceptance -- a transfer requested last month by '
  'someone who is no longer the owner cannot be accepted.';
comment on column public.organization_ownership_transfers.to_user_id is
  'The administrator who must accept. Also the subject of all four ownership.transfer_* history events, so '
  'one person''s team history reads as the whole story of the handover.';
comment on column public.organization_ownership_transfers.resolved_by is
  'Who ended it: the recipient on accept or decline, the requester on cancel. Never null once settled.';

-- At most one pending transfer per organization. Two owners cannot exist, so two competing handovers are
-- always a mistake; this refuses the second one at the write rather than sorting it out later.
create unique index organization_ownership_transfers_one_pending_idx
  on public.organization_ownership_transfers (organization_id)
  where state = 'pending';

-- The organization's transfer history, newest first. Its leading column also serves the cascade when an
-- organization is deleted, which the partial index above cannot.
create index organization_ownership_transfers_organization_requested_idx
  on public.organization_ownership_transfers (organization_id, requested_at desc);

-- Item 4's lesson, applied before it costs anything: deleting an Auth account makes Postgres check every
-- column referencing auth.users, and an unindexed one plans as a Seq Scan that only grows. from_ and to_
-- are NOT NULL so they take plain indexes; resolved_by's index is partial because a null can never be the
-- row the check is looking for. to_user_id doubles as "transfers waiting for me".
create index organization_ownership_transfers_to_user_idx
  on public.organization_ownership_transfers (to_user_id);
create index organization_ownership_transfers_from_user_idx
  on public.organization_ownership_transfers (from_user_id);
create index organization_ownership_transfers_resolved_by_idx
  on public.organization_ownership_transfers (resolved_by)
  where resolved_by is not null;

alter table public.organization_ownership_transfers enable row level security;

create policy "team managers can view ownership transfers"
  on public.organization_ownership_transfers
  for select
  to authenticated
  using (organization_id in (select private.permitted_organizations('team.manage')));

-- Layer one of "no bypass": no browser session holds a write grant, so no policy mistake can ever be the
-- difference between a valid transfer and an invalid one. Same shape as the invitations table.
-- service_role is revoked too, and handed back only select/insert/update. Item 4 learned this the hard way:
-- Supabase's default privileges quietly leave service_role holding DELETE and TRUNCATE, and a settled
-- transfer is history -- it is answered, never erased.
revoke all on public.organization_ownership_transfers from anon, authenticated, service_role;
grant select on public.organization_ownership_transfers to authenticated;
grant select, insert, update on public.organization_ownership_transfers to service_role;

-- ---------------------------------------------------------------------------
-- 1. Request
-- ---------------------------------------------------------------------------

-- Changes nobody's role. It only records that the owner asked, which is what makes "until acceptance,
-- nothing changes" true by construction rather than by the API remembering to be careful.
create or replace function public.request_ownership_transfer(
  target_organization_id uuid,
  requesting_user_id uuid,
  target_user_id uuid
)
returns public.organization_ownership_transfers
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_row public.organization_ownership_transfers;
begin
  -- Same key space convention as private.assert_employee_seat_available: two concurrent requests for one
  -- organization serialize instead of both reading "no pending transfer" and both inserting.
  perform pg_advisory_xact_lock(hashtext('ownership_transfer:' || target_organization_id::text));

  if not exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = requesting_user_id
      and membership.role = 'owner'
      and membership.status = 'active'
  ) then
    raise exception 'Only the current owner can hand over ownership.' using errcode = 'check_violation';
  end if;

  -- An active administrator, and nothing else. A pending invitee, a deactivated administrator, or someone
  -- on another role is refused here and again at acceptance.
  if not exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = target_user_id
      and membership.role = 'admin'
      and membership.status = 'active'
  ) then
    raise exception 'Ownership can only be handed to an active administrator.'
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.organization_ownership_transfers as transfer
    where transfer.organization_id = target_organization_id
      and transfer.state = 'pending'
  ) then
    raise exception 'There is already an ownership handover waiting for an answer.'
      using errcode = 'unique_violation';
  end if;

  insert into public.organization_ownership_transfers (organization_id, from_user_id, to_user_id)
  values (target_organization_id, requesting_user_id, target_user_id)
  returning * into new_row;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'ownership.transfer_requested', 'member', requesting_user_id, target_user_id,
    jsonb_build_object('transfer_id', new_row.id)
  );

  return new_row;
end;
$$;

comment on function public.request_ownership_transfer(uuid, uuid, uuid) is
  'Records that the active owner asked an active administrator to take over. Changes no roles. Refuses a '
  'second pending handover for the same organization.';

revoke all on function public.request_ownership_transfer(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.request_ownership_transfer(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Accept
-- ---------------------------------------------------------------------------

-- The only path by which an organization's owner ever changes.
create or replace function public.accept_ownership_transfer(
  target_transfer_id uuid,
  accepting_user_id uuid
)
returns public.organization_ownership_transfers
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  transfer public.organization_ownership_transfers;
begin
  select * into transfer
  from public.organization_ownership_transfers
  where id = target_transfer_id
  for update;

  if not found then
    raise exception 'That ownership handover no longer exists.' using errcode = 'no_data_found';
  end if;

  -- Taken after the row lock, and in that order every time, so accept and close never deadlock each other.
  perform pg_advisory_xact_lock(hashtext('ownership_transfer:' || transfer.organization_id::text));

  if transfer.state <> 'pending' then
    raise exception 'That ownership handover has already been answered.' using errcode = 'check_violation';
  end if;

  if transfer.to_user_id <> accepting_user_id then
    raise exception 'Only the person the handover was sent to can accept it.'
      using errcode = 'check_violation';
  end if;

  -- Standing is re-checked now, not trusted from request time: the requester may have been deactivated, or
  -- the recipient may have been demoted, since the request was made.
  if not exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = transfer.organization_id
      and membership.user_id = transfer.from_user_id
      and membership.role = 'owner'
      and membership.status = 'active'
  ) then
    raise exception 'The person who offered ownership is no longer the owner.'
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = transfer.organization_id
      and membership.user_id = transfer.to_user_id
      and membership.role = 'admin'
      and membership.status = 'active'
  ) then
    raise exception 'Ownership can only be handed to an active administrator.'
      using errcode = 'check_violation';
  end if;

  -- Demote first, promote second. The at-most-one-owner partial index is checked on every write, so the
  -- other order would fail immediately; the deferred trigger then confirms exactly one owner at commit.
  update public.organization_members
  set role = 'admin',
      access_revision = access_revision + 1
  where organization_id = transfer.organization_id
    and user_id = transfer.from_user_id;

  update public.organization_members
  set role = 'owner',
      access_revision = access_revision + 1
  where organization_id = transfer.organization_id
    and user_id = transfer.to_user_id;

  update public.organization_ownership_transfers
  set state = 'accepted',
      resolved_at = now(),
      resolved_by = accepting_user_id
  where id = transfer.id
  returning * into transfer;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    transfer.organization_id, 'ownership.transfer_accepted', 'member', accepting_user_id,
    transfer.to_user_id, jsonb_build_object('transfer_id', transfer.id)
  );

  return transfer;
end;
$$;

comment on function public.accept_ownership_transfer(uuid, uuid) is
  'The recipient takes over. Demotes the old owner to administrator before promoting the new one, in one '
  'transaction. Re-checks both sides'' standing first -- a stale request cannot be cashed in.';

revoke all on function public.accept_ownership_transfer(uuid, uuid) from public, anon, authenticated;
grant execute on function public.accept_ownership_transfer(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Close
-- ---------------------------------------------------------------------------

-- One command, because cancelled and declined are the same act by different people, and letting the caller
-- name which one it is would let an API mislabel a decline as a cancellation in the team history.
create or replace function public.close_ownership_transfer(
  target_transfer_id uuid,
  actor_user_id uuid
)
returns public.organization_ownership_transfers
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  transfer public.organization_ownership_transfers;
  closed_state text;
  closed_event text;
begin
  select * into transfer
  from public.organization_ownership_transfers
  where id = target_transfer_id
  for update;

  if not found then
    raise exception 'That ownership handover no longer exists.' using errcode = 'no_data_found';
  end if;

  perform pg_advisory_xact_lock(hashtext('ownership_transfer:' || transfer.organization_id::text));

  if transfer.state <> 'pending' then
    raise exception 'That ownership handover has already been answered.' using errcode = 'check_violation';
  end if;

  if actor_user_id = transfer.from_user_id then
    closed_state := 'cancelled';
    closed_event := 'ownership.transfer_cancelled';
  elsif actor_user_id = transfer.to_user_id then
    closed_state := 'declined';
    closed_event := 'ownership.transfer_declined';
  else
    raise exception 'Only the owner who asked or the person asked can end a handover.'
      using errcode = 'check_violation';
  end if;

  update public.organization_ownership_transfers
  set state = closed_state,
      resolved_at = now(),
      resolved_by = actor_user_id
  where id = transfer.id
  returning * into transfer;

  -- The recipient stays the subject even when the owner cancels, so all four events read as one story on
  -- that person's team history.
  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    transfer.organization_id, closed_event, 'member', actor_user_id, transfer.to_user_id,
    jsonb_build_object('transfer_id', transfer.id)
  );

  return transfer;
end;
$$;

comment on function public.close_ownership_transfer(uuid, uuid) is
  'Ends a pending handover. The requester closing it is a cancellation, the recipient closing it is a '
  'decline -- the database decides which, so the history can never be mislabelled.';

revoke all on function public.close_ownership_transfer(uuid, uuid) from public, anon, authenticated;
grant execute on function public.close_ownership_transfer(uuid, uuid) to service_role;
