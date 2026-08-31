-- Team & access, part 3A, layer 1: a membership gets a life story.
--
-- Until now a membership row was organization + user + role, and existing meant active. Team management
-- needs four states, the business details an administrator may edit, and per-section revisions so Member
-- details and Role & access can save without overwriting each other.
--
-- The owner invariant is enforced in two halves that mean different things:
--   * a partial unique index proves "at most one owner", immediately, on every write;
--   * a deferred constraint trigger proves "exactly one active owner", at commit, so an ownership transfer
--     can demote and promote inside one transaction without ever being observed as illegal.
-- Neither half trusts the caller, and neither can be bypassed by a flag.

alter table public.organization_members
  add column if not exists status text not null default 'active',
  add column if not exists work_phone text,
  add column if not exists job_title text,
  add column if not exists schedule_color text,
  add column if not exists access_revision integer not null default 1,
  add column if not exists profile_revision integer not null default 1,
  add column if not exists status_changed_at timestamptz,
  add column if not exists status_changed_by uuid,
  add column if not exists deactivated_at timestamptz,
  add column if not exists removed_at timestamptz,
  add column if not exists display_name_at_removal text,
  add column if not exists identity_cleanup_state text not null default 'not_required',
  add column if not exists identity_cleanup_error text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_status_check'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_status_check
      check (status in ('pending', 'active', 'deactivated', 'removed'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_identity_cleanup_state_check'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_identity_cleanup_state_check
      check (
        identity_cleanup_state in (
          'not_required', 'required', 'ban_applied', 'email_released', 'done'
        )
      );
  end if;

  -- A removed member keeps a name, so historical attribution never depends on an Auth record.
  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_removed_keeps_a_name_check'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_removed_keeps_a_name_check
      check (status <> 'removed' or display_name_at_removal is not null);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_schedule_color_check'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_schedule_color_check
      check (schedule_color is null or schedule_color ~ '^#[0-9A-Fa-f]{6}$');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_work_phone_check'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_work_phone_check
      check (
        work_phone is null
        or (char_length(btrim(work_phone)) between 1 and 40)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_job_title_check'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_job_title_check
      check (
        job_title is null
        or (char_length(btrim(job_title)) between 1 and 80)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_display_name_at_removal_check'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_display_name_at_removal_check
      check (
        display_name_at_removal is null
        or (char_length(btrim(display_name_at_removal)) between 1 and 160)
      );
  end if;

  -- Who changed the state is worth keeping, but it must never block deleting a login account.
  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_members_status_changed_by_fkey'
      and conrelid = 'public.organization_members'::regclass
  ) then
    alter table public.organization_members
      add constraint organization_members_status_changed_by_fkey
      foreign key (status_changed_by) references auth.users (id) on delete set null;
  end if;
end $$;

-- Every membership that exists today predates the four states and is a working member.
update public.organization_members set status = 'active' where status is null;

-- At most one owner, proven on every write, whatever path the write came from.
create unique index if not exists organization_members_one_owner_idx
  on public.organization_members (organization_id)
  where role = 'owner' and status <> 'removed';

-- The team directory pages by status inside one organization.
create index if not exists organization_members_organization_status_created_idx
  on public.organization_members (organization_id, status, created_at desc);

-- Exactly one active owner, checked once at commit rather than on each row, so an ownership transfer may
-- demote the old owner and promote the new one in either order inside a single transaction. An
-- organization with no team members at all is exempt: nothing to own yet.
create or replace function private.assert_single_active_owner()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  subject_organization_id uuid;
  active_owner_count integer;
  present_member_count integer;
begin
  subject_organization_id := coalesce(new.organization_id, old.organization_id);
  if subject_organization_id is null then
    return null;
  end if;

  select
    count(*) filter (where membership.role = 'owner' and membership.status = 'active'),
    count(*) filter (where membership.status <> 'removed')
  into active_owner_count, present_member_count
  from public.organization_members as membership
  where membership.organization_id = subject_organization_id;

  if present_member_count > 0 and active_owner_count <> 1 then
    raise exception
      'An organization with team members must have exactly one active owner, but % were found.',
      active_owner_count
      using errcode = 'check_violation';
  end if;

  return null;
end;
$$;

revoke all on function private.assert_single_active_owner() from public, anon, authenticated, service_role;

drop trigger if exists organization_members_single_active_owner on public.organization_members;
create constraint trigger organization_members_single_active_owner
  after insert or update or delete on public.organization_members
  deferrable initially deferred
  for each row
  execute function private.assert_single_active_owner();

comment on column public.organization_members.status is
  'pending (invited, no access), active, deactivated (access denied, seat freed), removed (tombstone).';
comment on column public.organization_members.access_revision is
  'Bumped by role and permission saves so a stale editor conflicts instead of overwriting.';
comment on column public.organization_members.profile_revision is
  'Bumped by member detail saves, independently of access_revision.';
comment on column public.organization_members.display_name_at_removal is
  'Name snapshot taken at permanent removal so attribution never depends on an Auth record.';
comment on column public.organization_members.identity_cleanup_state is
  'Ledger for the Auth steps that cannot share this transaction. Advanced only by the 3B/3E worker.';
