-- Paid-launch trust, Part 2: the requests.view permission seam.
--
-- Part 1 proved a Field member sees every Request in the organization: requests.view has never existed as
-- its own permission, so public.requests and its RLS have only ever checked plain organization membership.
-- This adds the switch and seeds it correctly, mirroring the seam jobs.view turned on in
-- field_assigned_scope_foundation: a permission declares scope_model = 'assigned_or_all', and a role holds
-- it at a narrower access_scope. Request policies, private.can_view_request, and request_pricing_lines are
-- untouched here -- wiring the switch to real visibility is Part 3.

insert into public.permissions (key, description, scope_model)
values ('requests.view', 'See requests', 'assigned_or_all')
on conflict (key) do update set description = excluded.description, scope_model = excluded.scope_model;

insert into public.role_permissions (role, permission_key, access_scope)
values
  ('owner', 'requests.view', 'all'),
  ('admin', 'requests.view', 'all'),
  ('office', 'requests.view', 'all'),
  ('sales', 'requests.view', 'all'),
  ('finance', 'requests.view', 'all'),
  ('field', 'requests.view', 'assigned')
on conflict (role, permission_key) do nothing;
