-- Server-revocable owner sessions and sanitized login auditing (Part 8: operations and current-owner
-- security hardening). Today `jafar_session` only signs an email and expiry into the cookie -- there
-- is no server record, so nothing can invalidate an already-issued cookie before it expires.
--
-- The browser cookie now carries only a signed session id. Every protected page and /api/jafar/*
-- request looks that id up here: it must exist, be unrevoked, and be unexpired. Login attempts are
-- recorded as a sanitized outcome only -- no raw IP address or attempted email is stored anywhere,
-- per the approved privacy boundary. Rate limiting reuses the existing generic
-- public.check_rate_limit, keyed by an HMAC of the caller's IP computed in application code, so the
-- rate-limit bucket itself never holds a raw IP either.

create table public.platform_owner_sessions (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null default gen_random_uuid(),
  owner_email text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_reason text check (revoked_reason in ('logout', 'rotated')),
  constraint platform_owner_sessions_revoked_check check (
    (revoked_at is null) = (revoked_reason is null)
  ),
  constraint platform_owner_sessions_expiry_check check (expires_at > created_at)
);

alter table public.platform_owner_sessions enable row level security;

revoke all on public.platform_owner_sessions from anon, authenticated;
grant select, insert, update on public.platform_owner_sessions to service_role;

-- A session row is either created once or revoked once -- nothing else about it may ever change,
-- so a bug elsewhere can't silently extend or reassign an existing session.
create or replace function private.restrict_platform_owner_session_update()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.id <> old.id
    or new.correlation_id is distinct from old.correlation_id
    or new.owner_email <> old.owner_email
    or new.created_at <> old.created_at
    or new.expires_at <> old.expires_at
  then
    raise exception 'Only the revocation state of a session can change.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function private.restrict_platform_owner_session_update() from public;

create trigger platform_owner_sessions_restrict_update
before update on public.platform_owner_sessions
for each row execute function private.restrict_platform_owner_session_update();

create trigger platform_owner_sessions_prevent_delete
before delete on public.platform_owner_sessions
for each row execute function private.prevent_platform_history_mutation();

-- Sanitized login attempt record: outcome and a correlation id only. No password, cookie value,
-- attempted email, or IP address is ever stored here -- that is the approved privacy boundary for
-- this table. Rate-limit grouping happens separately through the keyed-hash bucket key passed into
-- public.check_rate_limit, not through anything stored in this table.
create table public.platform_owner_login_attempts (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null default gen_random_uuid(),
  outcome text not null check (outcome in ('succeeded', 'failed', 'rate_limited')),
  created_at timestamptz not null default now()
);

alter table public.platform_owner_login_attempts enable row level security;

revoke all on public.platform_owner_login_attempts from anon, authenticated;
grant select, insert on public.platform_owner_login_attempts to service_role;

create trigger platform_owner_login_attempts_immutable
before update or delete on public.platform_owner_login_attempts
for each row execute function private.prevent_platform_history_mutation();
