-- A member whose role is "finance" could not open Invoices at all: the baseline matrix gave the role no
-- invoices.* permission. Finance now does the invoice work it is named for, and office can read invoices
-- without touching money.

insert into public.role_permissions (access_scope, permission_key, role)
values
  ('all', 'invoices.create', 'finance'),
  ('all', 'invoices.edit', 'finance'),
  ('all', 'invoices.record_payment', 'finance'),
  ('all', 'invoices.send', 'finance'),
  ('all', 'invoices.view', 'finance'),
  ('all', 'invoices.view_price', 'finance'),
  ('all', 'invoices.view', 'office'),
  ('all', 'invoices.view_price', 'office')
on conflict (role, permission_key) do nothing;
