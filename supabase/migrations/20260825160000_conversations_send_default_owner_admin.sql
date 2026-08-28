-- Owner and admin may send customer messages by default.
--
-- conversations.send was seeded as a permission key in
-- 20260823080419_communications_email_delivery_foundation.sql but never granted to any role, unlike its
-- siblings conversations.view_team and conversations.manage_assignment
-- (20260824141034_..., 20260825130000_...). The result was that nobody -- not even the organization owner --
-- could send a quote email, a client email, or a Conversations reply without a per-member override, which
-- surfaced in every send-path browser verification as a 403.
--
-- Jafar decided 2026-08-25 that this is permanent policy, not a per-organization opt-in: being an owner or
-- admin means you may message customers, matching the other administrative conversations permissions.
-- Everyone else still needs an explicit grant on their role or an override on their member row.
--
-- Idempotent seed: role_permissions is keyed (role, permission_key), so re-running changes nothing.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'conversations.send'),
  ('admin', 'conversations.send')
on conflict (role, permission_key) do nothing;
