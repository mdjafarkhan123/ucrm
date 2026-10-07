-- Jafar business D1: Uplift teammates who sign in to /jafar (ADR 0008).
-- A teammate is a separate login from any contractor account: their own row and bcrypt password hash here,
-- and the same session registry the platform owner uses, linked through platform_owner_sessions.team_member_id.

create table public.platform_team_members (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  full_name text,
  role text not null,
  status text not null default 'invited',
  password_hash text,
  invitation_token_hash text,
  invitation_expires_at timestamptz,
  invited_by_email text not null,
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  password_reset_token_hash text,
  password_reset_expires_at timestamptz,
  password_changed_at timestamptz,
  removed_at timestamptz,
  removed_by_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_team_members_email_normalized check (email = lower(btrim(email)) and email like '%_@_%'),
  constraint platform_team_members_role_check
    check (role in ('sales', 'delivery', 'support', 'platform_operations')),
  constraint platform_team_members_status_check check (status in ('invited', 'active', 'removed')),
  constraint platform_team_members_full_name_length check (full_name is null or char_length(full_name) between 1 and 120),
  -- Each status carries exactly what it needs: an invitation its link, an active teammate a password,
  -- a removed teammate neither.
  constraint platform_team_members_invited_shape check (
    status <> 'invited'
    or (invitation_token_hash is not null and invitation_expires_at is not null and password_hash is null)
  ),
  constraint platform_team_members_active_shape check (
    status <> 'active'
    or (password_hash is not null and accepted_at is not null and full_name is not null and invitation_token_hash is null)
  ),
  constraint platform_team_members_removed_shape check (
    status <> 'removed'
    or (
      removed_at is not null
      and password_hash is null
      and invitation_token_hash is null
      and password_reset_token_hash is null
    )
  )
);

comment on table public.platform_team_members is
  'Uplift teammates invited to the /jafar panel. Not Supabase Auth users (ADR 0008). Service role only.';

-- One live (invited or active) record per email; a removed teammate can be invited again as a new record.
create unique index platform_team_members_live_email_key
  on public.platform_team_members (email)
  where status <> 'removed';

create unique index platform_team_members_invitation_token_key
  on public.platform_team_members (invitation_token_hash)
  where invitation_token_hash is not null;

create unique index platform_team_members_password_reset_token_key
  on public.platform_team_members (password_reset_token_hash)
  where password_reset_token_hash is not null;

create trigger platform_team_members_set_updated_at
  before update on public.platform_team_members
  for each row execute function public.set_updated_at();

alter table public.platform_team_members enable row level security;
revoke all on table public.platform_team_members from public, anon, authenticated;
grant all on table public.platform_team_members to service_role;

-- A teammate's session is an ordinary /jafar session row that names its teammate; the owner's keeps null.
alter table public.platform_owner_sessions
  add column team_member_id uuid references public.platform_team_members (id) on delete cascade;

create index platform_owner_sessions_team_member_id_idx
  on public.platform_owner_sessions (team_member_id)
  where team_member_id is not null;

comment on column public.platform_owner_sessions.team_member_id is
  'The teammate this /jafar session belongs to; null for the platform owner. owner_email then holds the teammate''s email.';
