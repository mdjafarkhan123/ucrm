-- Part 4: inbound message and attachment metadata.
--
-- One row per correlated inbound email (docs/contractor-email-contract.md § Conversations and replies;
-- § Attachments and tracking). Provider callback ingestion is authenticated/idempotent at the existing
-- communication_provider_callback_events dedup boundary (unique (provider, provider_event_key)); this
-- table additionally guards against a duplicate provider Message-ID producing two rows.
--
-- client_id/client_contact_method_id/sender_id stay null for a message that could not be trusted onto
-- an existing conversation (unknown sender, ambiguous sender, or an expired alias) -- review_status then
-- carries that state without silently attaching the reply to the wrong (or a former) customer.

alter table public.communication_delivery_intents
  add constraint communication_delivery_intents_organization_id_id_key unique (organization_id, id);

create table public.communication_inbound_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  reply_alias_id uuid references public.communication_reply_aliases (id) on delete set null,
  client_id uuid,
  client_contact_method_id uuid,
  sender_id uuid,
  owner_user_id uuid references auth.users (id) on delete set null,
  provider text not null default 'brevo',
  provider_message_id text,
  in_reply_to_provider_message_id text,
  in_reply_to_intent_id uuid references public.communication_delivery_intents (id) on delete set null,
  direction text not null default 'inbound' check (direction = 'inbound'),
  sender_email text not null,
  sender_name text,
  to_recipients jsonb not null default '[]'::jsonb,
  cc_recipients jsonb not null default '[]'::jsonb,
  subject text not null,
  html_content text,
  text_content text not null,
  message_kind text not null default 'reply'
    check (message_kind in ('reply', 'auto_response', 'delivery_notice', 'loop_detected')),
  review_status text not null default 'accepted' check (review_status in ('accepted', 'pending_review')),
  review_reason text check (review_reason in ('unknown_sender', 'ambiguous_sender', 'expired_alias')),
  -- Every pending_review row must carry a reason; every accepted row must not.
  constraint communication_inbound_messages_review_reason_matches_status check (
    (review_status = 'accepted' and review_reason is null)
    or (review_status = 'pending_review' and review_reason is not null)
  ),
  automation_suppressed boolean not null default false,
  loop_detected_at timestamptz,
  attachment_count integer not null default 0 check (attachment_count >= 0),
  provider_callback_event_id uuid references public.communication_provider_callback_events (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_inbound_messages_client_fk
    foreign key (organization_id, client_id) references public.clients (organization_id, id) on delete restrict,
  constraint communication_inbound_messages_contact_method_fk
    foreign key (organization_id, client_contact_method_id)
    references public.client_contact_methods (organization_id, id) on delete restrict,
  constraint communication_inbound_messages_sender_fk
    foreign key (organization_id, sender_id)
    references public.communication_email_senders (organization_id, id) on delete restrict,
  -- A resolved conversation always carries all three identifiers together, never a partial match.
  constraint communication_inbound_messages_resolution_complete check (
    (client_id is null and client_contact_method_id is null and sender_id is null)
    or (client_id is not null and client_contact_method_id is not null and sender_id is not null)
  )
);

create unique index communication_inbound_messages_organization_id_id_key
  on public.communication_inbound_messages (organization_id, id);
-- Callback retries/out-of-order delivery collapse onto one row per provider message id.
create unique index communication_inbound_messages_provider_message_idx
  on public.communication_inbound_messages (provider, provider_message_id)
  where provider_message_id is not null;
create index communication_inbound_messages_org_created_idx
  on public.communication_inbound_messages (organization_id, created_at desc, id desc);
create index communication_inbound_messages_org_client_created_idx
  on public.communication_inbound_messages (organization_id, client_id, created_at desc, id desc)
  where client_id is not null;
create index communication_inbound_messages_pending_review_idx
  on public.communication_inbound_messages (organization_id, created_at desc)
  where review_status = 'pending_review';
create index communication_inbound_messages_reply_alias_idx
  on public.communication_inbound_messages (reply_alias_id) where reply_alias_id is not null;
create index communication_inbound_messages_in_reply_to_idx
  on public.communication_inbound_messages (in_reply_to_intent_id) where in_reply_to_intent_id is not null;

alter table public.communication_inbound_messages enable row level security;
revoke all on public.communication_inbound_messages from anon, authenticated;
grant select, insert, update on public.communication_inbound_messages to service_role;

create table public.communication_inbound_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  inbound_message_id uuid not null,
  file_name text not null check (char_length(trim(file_name)) between 1 and 255),
  mime_type text not null check (char_length(trim(mime_type)) between 1 and 127),
  byte_size bigint not null check (byte_size >= 0),
  -- Private organization-scoped storage key (never a provider URL -- that is never the durable access
  -- boundary). Null until import succeeds.
  object_key text,
  status text not null default 'pending_import' check (
    status in ('pending_import', 'pending_scan', 'available', 'blocked_type', 'blocked_size', 'infected', 'scan_failed', 'import_failed')
  ),
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_inbound_attachments_message_fk
    foreign key (organization_id, inbound_message_id)
    references public.communication_inbound_messages (organization_id, id) on delete cascade
);

create index communication_inbound_attachments_message_idx
  on public.communication_inbound_attachments (inbound_message_id);

alter table public.communication_inbound_attachments enable row level security;
revoke all on public.communication_inbound_attachments from anon, authenticated;
grant select, insert, update on public.communication_inbound_attachments to service_role;

create or replace function private.bump_communication_inbound_message_attachment_count()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  update public.communication_inbound_messages
  set attachment_count = attachment_count + 1, updated_at = now()
  where id = new.inbound_message_id;
  return new;
end;
$$;

create trigger communication_inbound_attachments_bump_count
  after insert on public.communication_inbound_attachments
  for each row execute function private.bump_communication_inbound_message_attachment_count();
