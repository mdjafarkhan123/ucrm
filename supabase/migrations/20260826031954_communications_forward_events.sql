-- Communications Part 5C-ii: manual forwarding schema.
--
-- A forward is not customer email: its recipient is external (a colleague, a vendor), never a row in
-- client_contact_methods, and it must never draw on the customer-email allowance/capacity-claim system
-- that every communication_delivery_intents row goes through (docs/contractor-email-contract.md §
-- Recipients, forwarding, and portal access -- "It neither shares the whole conversation nor grants
-- portal access"). That table's client_contact_method_id is NOT NULL and FK'd to the client's own
-- contact methods, so a forward cannot be represented as a delivery intent without either relaxing that
-- constraint or teaching the shared capacity-claim RPC to special-case a kind of send that was never in
-- its financial model. Jafar decided 2026-08-26 (Part 5 packet, 5C-ii): keep it simple and isolated --
-- its own small table, reusing only the provider-send call, not the allowance/reply-alias machinery.
--
-- The queue/claim columns (available_at, claimed_at, claim_token, attempt_count, last_error) live
-- directly on this table rather than a second outbox-join table like communication_outbox_events, since
-- a forward has no allowance reservation step to keep separate from -- one row is the whole lifecycle.
-- status reuses the exact vocabulary of communication_delivery_intents.status (queued/claimed/submitted/
-- failed/cancelled/submission_unknown) so the existing outboundEmailStatus() UI helper (src/lib/
-- communications/inbox.ts) renders a forward event with no new status mapping.

create table public.communication_forward_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- The conversation this forward was sent from -- for timeline placement only, never a send target.
  client_id uuid not null,
  source_inbound_message_id uuid not null,
  sender_id uuid not null,
  recipient_emails text[] not null,
  logical_send_key text not null check (char_length(trim(logical_send_key)) between 1 and 200),
  subject text not null check (char_length(trim(subject)) between 1 and 998),
  html_content text not null check (char_length(trim(html_content)) > 0),
  text_content text not null check (char_length(trim(text_content)) > 0),
  status text not null default 'queued'
    check (status in ('queued', 'claimed', 'submitted', 'failed', 'cancelled', 'submission_unknown')),
  provider_message_id text,
  accepted_at timestamptz,
  failure_code text,
  failure_message text,
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  claim_token uuid,
  -- Set only by finalize, distinct from claim_token: lets a lost RPC response be retried safely and
  -- return the already-committed outcome instead of erroring, mirroring communication_outbox_events'
  -- own finalized_claim_token (20260824002116_communications_email_worker_completion.sql).
  finalized_claim_token uuid,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_forward_events_client_fk
    foreign key (organization_id, client_id) references public.clients (organization_id, id) on delete cascade,
  constraint communication_forward_events_message_fk
    foreign key (organization_id, source_inbound_message_id)
    references public.communication_inbound_messages (organization_id, id) on delete cascade,
  constraint communication_forward_events_sender_fk
    foreign key (organization_id, sender_id)
    references public.communication_email_senders (organization_id, id) on delete restrict,
  constraint communication_forward_events_recipients_bounds
    check (array_length(recipient_emails, 1) between 1 and 10),
  constraint communication_forward_events_unique_logical_send
    unique (organization_id, logical_send_key),
  constraint communication_forward_events_claim_check check (
    (status = 'claimed') = (claimed_at is not null and claim_token is not null)
  ),
  constraint communication_forward_events_accepted_check check (
    (status = 'submitted') = (accepted_at is not null and provider_message_id is not null)
  )
);

create unique index communication_forward_events_organization_id_id_key
  on public.communication_forward_events (organization_id, id);
-- Timeline read: "this organization's forward events for this client, newest first" -- same shape as
-- communication_delivery_intents_client_created_idx, which the merged inbox query already relies on.
create index communication_forward_events_client_created_idx
  on public.communication_forward_events (organization_id, client_id, created_at desc, id desc);
-- Worker claim: mirrors communication_outbox_events_claim_idx's partial-index shape.
create index communication_forward_events_claim_idx
  on public.communication_forward_events (available_at, created_at)
  where status in ('queued', 'failed');

alter table public.communication_forward_events enable row level security;
revoke all on public.communication_forward_events from anon, authenticated;
grant select, insert, update on public.communication_forward_events to service_role;

-- Attachments are never re-uploaded: a forward can only reference files already imported into private
-- tenant storage on the source inbound message (communication_inbound_attachments.status = 'available'),
-- enforced in enqueue_inbound_message_forward below, not by this join table's shape alone.
alter table public.communication_inbound_attachments
  add constraint communication_inbound_attachments_organization_id_id_key unique (organization_id, id);

create table public.communication_forward_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  forward_event_id uuid not null,
  inbound_attachment_id uuid not null,
  created_at timestamptz not null default now(),
  constraint communication_forward_attachments_event_fk
    foreign key (organization_id, forward_event_id)
    references public.communication_forward_events (organization_id, id) on delete cascade,
  constraint communication_forward_attachments_source_fk
    foreign key (organization_id, inbound_attachment_id)
    references public.communication_inbound_attachments (organization_id, id) on delete restrict,
  constraint communication_forward_attachments_unique unique (forward_event_id, inbound_attachment_id)
);

create index communication_forward_attachments_org_event_idx
  on public.communication_forward_attachments (organization_id, forward_event_id);

alter table public.communication_forward_attachments enable row level security;
revoke all on public.communication_forward_attachments from anon, authenticated;
grant select, insert on public.communication_forward_attachments to service_role;
