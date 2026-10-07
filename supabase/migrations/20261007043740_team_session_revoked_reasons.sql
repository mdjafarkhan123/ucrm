-- D1 (ADR 0008): a teammate's sessions end when their password is reset or they are removed. The reason
-- check only knew the owner's 'logout' and 'rotated', so those revocations were refused.
alter table public.platform_owner_sessions
  drop constraint platform_owner_sessions_revoked_reason_check,
  add constraint platform_owner_sessions_revoked_reason_check
    check (revoked_reason = any (array['logout', 'rotated', 'password_reset', 'teammate_removed']));
