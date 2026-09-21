-- Part 4 item 5: per-user "last seen" position for a client conversation.
--
-- Absence of a row means the user has never marked this conversation read, so every inbound message is
-- unread by default -- matches docs/unified-inbox-behavior-contract.md's approved model: "opening alone
-- does not clear [unread]; replying, explicitly marking read, or an approved workflow may clear unread."
-- The write path (marking read) is not built yet -- it lands with the UI in the next item, once there is
-- an actual user action to call it from.

create table public.communication_conversation_read_marks (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  client_id uuid not null,
  last_read_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id, client_id),
  constraint communication_conversation_read_marks_client_fk
    foreign key (organization_id, client_id) references public.clients (organization_id, id) on delete cascade
);

create trigger communication_conversation_read_marks_set_updated_at
before update on public.communication_conversation_read_marks
for each row execute function public.set_updated_at();

alter table public.communication_conversation_read_marks enable row level security;
revoke all on public.communication_conversation_read_marks from anon, authenticated;
grant select, insert, update on public.communication_conversation_read_marks to service_role;
