-- The office role answers customers.
--
-- Jafar approved (2026-09-27) giving office staff the full team inbox by default: read every conversation,
-- reply, assign and follow, and forward -- the same day-to-day message work owner/admin already hold, and the
-- role that answers customers in Jobber and HighLevel. Office previously held no conversations.* permission
-- at all, so its client Communication tab and Inbox were refused outright. Connection management and
-- permanent delete stay with owner/admin. Sales, finance and field are unchanged.

insert into public.role_permissions (access_scope, permission_key, role)
values
  ('all', 'conversations.view_team', 'office'),
  ('all', 'conversations.send', 'office'),
  ('all', 'conversations.manage_assignment', 'office'),
  ('all', 'conversations.forward', 'office')
on conflict (role, permission_key) do nothing;
