-- Communications Part 5: outbound email attachments (the composer's paperclip).
--
-- Deliberately NOT symmetric with communication_inbound_attachments. An inbound file arrives from a
-- stranger's mail server and has to travel a status ladder (pending_import -> pending_scan -> available
-- / blocked_* / infected) because we neither chose it nor hold it yet. An outbound file is uploaded by
-- the contractor straight into our own R2 bucket before the message is queued, and the route rejects an
-- oversized or dangerous-typed file at upload time rather than storing a blocked row -- so a row here
-- exists only for a file that is already ours and already sendable. That is why there is no status
-- column: adding one would invent states nothing can produce.
--
-- Malware scanning is out of scope in both directions today (no scanner exists anywhere in this
-- codebase -- inbound files stop at pending_scan and never advance on their own). When a scanner lands
-- it covers both tables at once; approved by Jafar 2026-08-25.

create table public.communication_outbound_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  delivery_intent_id uuid not null,
  file_name text not null check (char_length(trim(file_name)) between 1 and 255),
  mime_type text not null check (char_length(trim(mime_type)) between 1 and 127),
  -- Measured by the API from what actually landed in storage (HeadObject), never the browser's claim.
  byte_size bigint not null check (byte_size > 0),
  -- Private organization-scoped R2 key under <org>/outbound-email-attachments/. The browser only ever
  -- sees a presigned URL derived from it, and only when authorized.
  object_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_outbound_attachments_intent_fk
    foreign key (organization_id, delivery_intent_id)
    references public.communication_delivery_intents (organization_id, id) on delete cascade,
  -- Re-sending the same logical_send_key returns the existing intent (the enqueue commands upsert on
  -- it), so the attachment insert has to be idempotent against exactly the same file. Its index also
  -- happens to be the one that serves the worker's own lookup, which knows only the intent id --
  -- EXPLAIN confirms list_communication_outbound_attachments scans this constraint's index. Dropping
  -- or reordering it would silently cost that path its index.
  constraint communication_outbound_attachments_intent_object_key
    unique (delivery_intent_id, object_key)
);

-- Serves both the FK's cascade lookup (leading-column match on the FK's own column order) and the
-- inbox read path, which is always "this organization's attachments for these intents".
create index communication_outbound_attachments_org_intent_idx
  on public.communication_outbound_attachments (organization_id, delivery_intent_id);

alter table public.communication_outbound_attachments enable row level security;
revoke all on public.communication_outbound_attachments from anon, authenticated;
grant select, insert on public.communication_outbound_attachments to service_role;

create trigger communication_outbound_attachments_set_updated_at
  before update on public.communication_outbound_attachments
  for each row execute function public.set_updated_at();

-- The total cap matches inbound's configurable 20 MB per message (docs/contractor-email-contract.md
-- section "Attachments and tracking") -- a file we would refuse to receive is one we refuse to send.
create or replace function private.attach_communication_outbound_files(
  target_organization_id uuid,
  target_delivery_intent_id uuid,
  target_attachments jsonb
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  total_bytes bigint;
  file_count integer;
begin
  if target_attachments is null or jsonb_array_length(target_attachments) = 0 then
    return;
  end if;

  select count(*), coalesce(sum((item ->> 'byte_size')::bigint), 0)
  into file_count, total_bytes
  from jsonb_array_elements(target_attachments) as item;

  if file_count > 10 then
    raise exception 'Attach at most 10 files to one email.' using errcode = 'check_violation';
  end if;
  if total_bytes > 20 * 1024 * 1024 then
    raise exception 'Attachments must total 20 MB or less.' using errcode = 'check_violation';
  end if;

  -- Defense in depth behind the API's own prefix check: a key issued for one organization can never be
  -- committed against another, matching how set_organization_logo guards its own prefix.
  if exists (
    select 1 from jsonb_array_elements(target_attachments) as item
    where item ->> 'object_key' not like target_organization_id::text || '/outbound-email-attachments/%'
  ) then
    raise exception 'That file does not belong to this business.' using errcode = 'check_violation';
  end if;

  insert into public.communication_outbound_attachments (
    organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key
  )
  select
    target_organization_id,
    target_delivery_intent_id,
    item ->> 'file_name',
    item ->> 'mime_type',
    (item ->> 'byte_size')::bigint,
    item ->> 'object_key'
  from jsonb_array_elements(target_attachments) as item
  on conflict (delivery_intent_id, object_key) do nothing;
end;
$function$;

revoke all on function private.attach_communication_outbound_files(uuid, uuid, jsonb)
  from public, anon, authenticated;

-- The attachments must land in the same transaction as the intent, and before the outbox event: the
-- worker claims from that event, so inserting them afterwards from the API would leave a window where
-- the message could be submitted without its files.
drop function public.enqueue_conversation_reply_email(uuid, uuid, uuid, text, text, text, text);

create function public.enqueue_conversation_reply_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_logical_send_key text,
  target_subject text,
  target_html_content text,
  target_text_content text,
  target_attachments jsonb default '[]'::jsonb
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  recipient public.client_contact_methods;
  latest_contact_method_id uuid;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
  alias public.communication_reply_aliases;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'customers.view') then
    raise exception 'You do not have permission to send a customer message.' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.organizations organization
    where organization.id = target_organization_id and organization.lifecycle_status = 'active'
  ) then
    raise exception 'This organization cannot send customer email right now.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- The reply always goes to whichever address this conversation most recently used, not necessarily
  -- the customer's primary address -- falls back to primary only when the conversation itself has no
  -- resolvable prior activity (should not happen for an already-open conversation, kept defensive).
  select client_contact_method_id into latest_contact_method_id
  from (
    select client_contact_method_id, created_at
    from public.communication_delivery_intents
    where organization_id = target_organization_id and client_id = target_client_id
    union all
    select client_contact_method_id, created_at
    from public.communication_inbound_messages
    where organization_id = target_organization_id and client_id = target_client_id
  ) activity
  order by created_at desc
  limit 1;

  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.client_id = target_client_id
    and method.kind = 'email'
    and client.deleted_at is null
    and (latest_contact_method_id is null or method.id = latest_contact_method_id)
  order by method.is_primary desc, method.created_at, method.id
  limit 1
  for share of method, client;

  if recipient.id is null then
    raise exception 'This customer has no active email address to reply to.' using errcode = 'foreign_key_violation';
  end if;

  -- The actor's enabled manual sender is resolved and locked before its one referenced domain, exactly
  -- like enqueue_manual_communication_email. The worker repeats these authority checks before submission.
  select email_sender.* into sender
  from public.communication_email_senders email_sender
  where email_sender.organization_id = target_organization_id
    and email_sender.assigned_user_id = target_actor_user_id
    and email_sender.lifecycle_state = 'enabled'
    and email_sender.allows_manual
  order by email_sender.is_organization_default desc, email_sender.created_at, email_sender.id
  limit 1
  for share of email_sender;

  if sender.id is not null then
    select domain.* into sender_domain
    from public.communication_email_domains domain
    where domain.organization_id = target_organization_id
      and domain.id = sender.domain_id
      and domain.purpose = 'sending'
      and domain.lifecycle_state = 'verified'
      and domain.provider_verified
      and domain.provider_authenticated
      and domain.ownership_status = 'passing'
      and domain.dkim_status = 'passing'
    for share of domain;
  end if;

  if sender.id is null or sender_domain.id is null then
    raise exception 'Your assigned email sender is not ready. Ask an administrator to review it.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  alias := public.ensure_communication_reply_alias(target_organization_id, sender.id, target_client_id, recipient.id);

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
    subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by
  ) values (
    target_organization_id, target_client_id, recipient.id, target_logical_send_key,
    recipient.normalized_value, target_subject, target_html_content, target_text_content,
    'manual', 'essential', sender.id, alias.id, target_actor_user_id
  ) on conflict (organization_id, logical_send_key) do update
    set logical_send_key = excluded.logical_send_key
  returning * into intent;

  perform private.attach_communication_outbound_files(
    intent.organization_id, intent.id, target_attachments
  );

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
  values (intent.organization_id, intent.id)
  on conflict (delivery_intent_id) do nothing;

  return intent;
end;
$function$;

revoke all on function public.enqueue_conversation_reply_email(uuid, uuid, uuid, text, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.enqueue_conversation_reply_email(uuid, uuid, uuid, text, text, text, text, jsonb)
  to service_role;

-- The worker holds only an rpc() seam (CommunicationWorkerClient), so it reads a claimed message's
-- files through a command rather than a table select. Metadata only -- the bytes are fetched from R2 by
-- the worker itself, and the object key never reaches a browser through this path.
create or replace function public.list_communication_outbound_attachments(
  target_delivery_intent_id uuid
) returns table (file_name text, mime_type text, byte_size bigint, object_key text)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select
    attachment.file_name,
    attachment.mime_type,
    attachment.byte_size,
    attachment.object_key
  from public.communication_outbound_attachments attachment
  where attachment.delivery_intent_id = target_delivery_intent_id
  order by attachment.created_at, attachment.id;
$function$;

revoke all on function public.list_communication_outbound_attachments(uuid)
  from public, anon, authenticated;
grant execute on function public.list_communication_outbound_attachments(uuid) to service_role;
