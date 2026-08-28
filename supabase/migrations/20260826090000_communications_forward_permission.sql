-- Communications Part 5C-ii: permission key for external manual forwarding.
--
-- docs/contractor-email-contract.md § Recipients, forwarding, and portal access: owner/admin may forward
-- by default; other staff need an explicit grant. Mirrors conversations.send's own seeding history
-- (20260825160000_conversations_send_default_owner_admin.sql) -- seed the grant in the same migration
-- that creates the key this time, since that omission is already a known footgun here.

insert into public.permissions (key, description)
values ('conversations.forward', 'Forward an inbound message to an external recipient')
on conflict (key) do nothing;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'conversations.forward'),
  ('admin', 'conversations.forward')
on conflict (role, permission_key) do nothing;
