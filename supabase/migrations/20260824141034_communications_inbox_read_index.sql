-- The inbox starts every request inside one organization and reads newest operational email first.
-- This supports keyset pagination without walking another tenant's history or sorting a growing outbox.
create index if not exists communication_delivery_intents_inbox_read_idx
  on public.communication_delivery_intents (organization_id, created_at desc, id desc);

-- The first safe inbox slice is the shared team view. Member-specific assignment/following stays closed
-- until Conversations owns those records; granting it now would promise a view we cannot filter safely.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'conversations.view_team'),
  ('admin', 'conversations.view_team')
on conflict (role, permission_key) do nothing;
