-- Take private.member_permission_scope away from signed-in users.
--
-- It was granted to `authenticated` when the Field role's assigned-only scope shipped (20260907), but nothing
-- needs that: every caller (member_job_is_visible, member_receives_inquiry_alerts and the three financial
-- report functions) is SECURITY DEFINER and runs as the function owner, no security policy names it directly,
-- and `authenticated` has no USAGE on the private schema anyway. Least privilege: only the owner keeps it.

revoke all on function private.member_permission_scope(uuid, uuid, text) from authenticated;
