-- Contractor Settings Part 6B, slice 2: Automation permission keys and owner/admin defaults.
--
-- Four keys following docs/automation-behavior-contract.md § Entitlement, permissions, and commands.
-- Owner and admin receive all four by default; employees receive none in 6B. The contract grants
-- employees `automations.view` only when their package includes Automation, and no package includes it
-- yet, so seeding an employee default now would be dishonest. A later slice seeds employee view together
-- with publishing the feature to a package.
--
-- Each key stays scope_model = 'none' (all-or-nothing): Automation is a settings-area capability, not a
-- per-record assigned scope, so the assigned/all machinery from 20260825090300 does not apply.
-- The effective-access resolver maps the `automations.` prefix to the `automations` feature so these
-- permissions fold the plan entitlement in automatically (src/lib/server/access/effective.ts).

insert into public.permissions (key, description)
values
  ('automations.view', 'View automation recipes and history'),
  ('automations.manage', 'Create and edit automation recipe drafts'),
  ('automations.activate', 'Activate, pause, resume, and archive automation recipes'),
  ('automations.control_enrollment', 'Enroll, pause, resume, skip, and stop records in automations')
on conflict (key) do nothing;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'automations.view'),
  ('owner', 'automations.manage'),
  ('owner', 'automations.activate'),
  ('owner', 'automations.control_enrollment'),
  ('admin', 'automations.view'),
  ('admin', 'automations.manage'),
  ('admin', 'automations.activate'),
  ('admin', 'automations.control_enrollment')
on conflict (role, permission_key) do nothing;
