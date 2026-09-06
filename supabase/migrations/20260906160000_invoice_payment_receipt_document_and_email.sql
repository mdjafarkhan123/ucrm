-- Invoices Part 6b-2a: the customer's receipt for a recorded payment, and how it reaches them.
--
-- Part 7 records payments (client_payment_events + invoice_payment_allocations). This part gives a recorded
-- payment a customer-facing receipt, built on the same three rules as the invoice document (6a) and sent
-- through the same machinery as the invoice email (6b-1):
--
--   1. private.payment_receipt_document is the only place the receipt is assembled, so the customer's token
--      page and any staff render (6b-2b's Print/Save PDF) can never drift.
--   2. The raw token never reaches the database -- the server hashes it and passes 32 bytes.
--   3. `anon` gets nothing. The public page runs on our server with the service key and calls exactly one
--      function.
--
-- The receipt's field set follows Jobber's own receipt PDF exactly (recorded live 2026-09-05, then deleted):
-- business name, a "Transaction date" badge, RECIPIENT (name + billing address, no contact info), a
-- "Payment receipt" heading, the amount paid, then transaction date / method / reference, then the free-text
-- details note. No receipt number, no invoice number, no line items, no balance. Unlike Jobber we deliver it
-- as a hosted page link, not a PDF attachment -- we run no server PDF engine (Part 6 decision), and it is
-- how we already email invoices.

-- 1. The delivery intent can now name a payment -----------------------------------------------------------

-- Payments are the third system-owned operational-email source, after Quotes and Invoices. Same optional-FK
-- shape, same restrict-on-delete, same partial index for "the receipts we emailed for this payment".
alter table public.communication_delivery_intents add column client_payment_event_id uuid;
alter table public.communication_delivery_intents
  add constraint communication_delivery_intents_payment_fk
  foreign key (organization_id, client_payment_event_id)
  references public.client_payment_events(organization_id, id) on delete restrict;
create index communication_delivery_intents_payment_created_idx
  on public.communication_delivery_intents (organization_id, client_payment_event_id, created_at desc, id desc)
  where client_payment_event_id is not null;

comment on column public.communication_delivery_intents.client_payment_event_id is
  'The recorded payment this email is a receipt for. Restrict-on-delete so a payment with a sent receipt '
  'cannot be deleted out from under it.';

-- 2. The link itself -------------------------------------------------------------------------------------

-- One customer link, scoped to organization and payment. A payment is immutable once recorded, so unlike an
-- invoice there is nothing to re-freeze: the receipt is the same every time it is asked for. Sending again
-- rotates the live links so asking twice never leaves two open doors.
create table public.payment_receipt_access_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_payment_event_id uuid not null,
  recipient_name text check (recipient_name is null or char_length(trim(recipient_name)) between 1 and 200),
  recipient_email text check (
    recipient_email is null or (
      recipient_email = lower(trim(recipient_email))
      and char_length(recipient_email) between 6 and 320
      and recipient_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    )
  ),
  -- SHA-256 of a 256-bit random token, as raw bytes: the only form of the token that survives the request
  -- that created it.
  token_hash bytea not null check (octet_length(token_hash) = 32),
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text check (revoked_reason is null or revoked_reason in ('rotated', 'revoked')),
  constraint payment_receipt_access_links_token_hash_unique unique (token_hash),
  constraint payment_receipt_access_links_organization_id_unique unique (organization_id, id),
  constraint payment_receipt_access_links_payment_fk foreign key (organization_id, client_payment_event_id)
    references public.client_payment_events(organization_id, id) on delete cascade,
  constraint payment_receipt_access_links_revocation_agrees check ((revoked_at is null) = (revoked_reason is null)),
  constraint payment_receipt_access_links_expiry_follows_issue check (expires_at is null or expires_at > issued_at)
);

comment on table public.payment_receipt_access_links is
  'One customer link to a recorded payment''s receipt. Scoped to organization and payment. Stores only the '
  'token hash -- the raw token exists once, in the URL the send composes, and must never appear in a row, a '
  'log line, or an activity payload.';

-- The customer read is one equality lookup on the unique token hash. This index serves the foreign key and
-- the "the receipt links for this payment, newest first" rotation; neither is on the customer path.
create index payment_receipt_access_links_payment_idx
  on public.payment_receipt_access_links(organization_id, client_payment_event_id, issued_at desc);

create index payment_receipt_access_links_issued_by_idx
  on public.payment_receipt_access_links(issued_by) where issued_by is not null;

-- 3. The one builder -----------------------------------------------------------------------------------

-- Invoker, not definer, and private: only ever reached from inside a security definer function that has
-- already decided the caller may be here. It makes no access decision. Handed the payment row and the
-- business name, it assembles exactly Jobber's receipt field set and nothing else.
--
-- RECIPIENT identity comes from the invoice the payment settled -- its frozen customer_snapshot and
-- billing_address_snapshot, so a later rename or address change never rewrites a receipt already handed out.
-- Today a receipt always settles exactly one invoice (single-invoice collection); if more than one is ever
-- applied, the lowest-numbered invoice's snapshot names the recipient and the rest are simply not itemised,
-- because the receipt never itemises invoices. A payment applied to no invoice (pure account credit) falls
-- back to the client's current display name with no address.
create or replace function private.payment_receipt_document(
  receipt public.client_payment_events,
  business_name text
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  snapshot_invoice public.invoices;
  recipient_name text;
  recipient_company text;
  recipient_address jsonb;
begin
  select invoice.* into snapshot_invoice
  from public.invoice_payment_allocations as allocation
  join public.invoices as invoice
    on invoice.organization_id = allocation.organization_id and invoice.id = allocation.invoice_id
  where allocation.organization_id = receipt.organization_id
    and allocation.payment_event_id = receipt.id
    and allocation.entry_type = 'applied'
  order by allocation.invoice_number
  limit 1;

  if snapshot_invoice.id is not null then
    recipient_name := coalesce(
      nullif(trim(snapshot_invoice.customer_snapshot->>'display_name'), ''),
      (select client.display_name from public.clients as client
        where client.organization_id = receipt.organization_id and client.id = receipt.client_id)
    );
    recipient_company := nullif(trim(snapshot_invoice.customer_snapshot->>'company_name'), '');
    recipient_address := snapshot_invoice.billing_address_snapshot;
  else
    select client.display_name, nullif(trim(client.company_name), '')
      into recipient_name, recipient_company
    from public.clients as client
    where client.organization_id = receipt.organization_id and client.id = receipt.client_id;
    recipient_address := null;
  end if;

  return jsonb_build_object(
    'business', jsonb_build_object('name', business_name),
    'receipt', jsonb_build_object(
      'amount_minor', receipt.amount_minor,
      'currency_code', receipt.currency_code,
      'transaction_date', receipt.payment_date,
      'method', receipt.method,
      'reference', receipt.reference,
      'details', receipt.note
    ),
    'recipient', jsonb_build_object(
      'display_name', recipient_name,
      'company_name', recipient_company,
      'address', case
        when recipient_address is null
          or recipient_address->>'source' = 'none'
          or coalesce(recipient_address->>'address_line1', '') = '' then null
        else jsonb_build_object(
          'address_line1', recipient_address->>'address_line1',
          'address_line2', recipient_address->>'address_line2',
          'city', recipient_address->>'city',
          'state_region', recipient_address->>'state_region',
          'postal_code', recipient_address->>'postal_code',
          'country', recipient_address->>'country'
        )
      end
    )
  );
end;
$$;

comment on function private.payment_receipt_document(public.client_payment_events, text) is
  'The only definition of a customer payment receipt. Jobber''s field set exactly: business, amount paid, '
  'transaction date, method, reference, details note, and the recipient name + billing address from the '
  'settled invoice''s frozen snapshot. No receipt number, invoice number, line items or balance.';

revoke all on function private.payment_receipt_document(public.client_payment_events, text)
  from public, anon, authenticated, service_role;

-- 4. The one public seam -----------------------------------------------------------------------------------

-- Our server hashes the token from the URL and calls this as the service role. Every way of failing returns
-- the same null -- unknown token, revoked, expired, a payment that is not a plain recorded receipt (a
-- reversal or a refund row) -- so the page cannot be used to learn whether a payment, a client or an
-- organization exists. A receipt with the number removed is not a receipt, so amounts are unconditional here.
create or replace function public.resolve_payment_receipt_access_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.payment_receipt_access_links;
  receipt public.client_payment_events;
  business_name text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.payment_receipt_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into receipt from public.client_payment_events where id = link_row.client_payment_event_id;
  if receipt.id is null or receipt.event_type <> 'received' then
    return null;
  end if;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = receipt.organization_id;

  return private.payment_receipt_document(receipt, business_name);
end;
$$;

comment on function public.resolve_payment_receipt_access_link(bytea) is
  'The customer''s reader for a payment receipt. Hashed token in, one receipt document out, or null for every '
  'failure alike. Service role only: not part of the Data API for anybody else.';

revoke all on function public.resolve_payment_receipt_access_link(bytea) from public;
revoke execute on function public.resolve_payment_receipt_access_link(bytea) from anon, authenticated;
grant execute on function public.resolve_payment_receipt_access_link(bytea) to service_role;

-- 5. Send the receipt by email ---------------------------------------------------------------------------

-- Service role only, called by our own server after it has generated the token. Mirrors
-- enqueue_invoice_communication_email: checks the payment is a plain recorded receipt, resolves the
-- recipient and an eligible verified sender, rotates the live receipt links, opens a fresh door, and queues
-- one email -- all in one transaction, idempotent on the logical send key so a double click returns the
-- first intent rather than sending twice. A deliberate resend passes a new key and sends again.
create or replace function public.enqueue_payment_receipt_email(
  target_organization_id uuid, target_actor_user_id uuid, target_payment_event_id uuid,
  target_logical_send_key text, target_receipt_url text, target_receipt_token_hash bytea
) returns public.communication_delivery_intents
language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare
  receipt public.client_payment_events; client_row public.clients;
  recipient public.client_contact_methods;
  business_name text; money_text text;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'invoices.record_payment')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to send this receipt by email.' using errcode = 'insufficient_privilege';
  end if;
  if target_receipt_url !~ '^https?://[^[:space:]]+$' or target_receipt_token_hash is null
    or octet_length(target_receipt_token_hash) <> 32 then
    raise exception 'The receipt link is not available.' using errcode = 'check_violation';
  end if;

  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = target_logical_send_key for share;
  if intent.id is not null then
    if intent.client_payment_event_id is distinct from target_payment_event_id then
      raise exception 'This receipt retry does not match the original payment.' using errcode = 'unique_violation';
    end if;
    return intent;
  end if;

  select * into receipt from public.client_payment_events
    where organization_id = target_organization_id and id = target_payment_event_id for share;
  if receipt.id is null or receipt.event_type <> 'received' then
    raise exception 'This payment does not have a receipt to send.' using errcode = 'foreign_key_violation';
  end if;

  select * into client_row from public.clients
    where organization_id = receipt.organization_id and id = receipt.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = receipt.organization_id and client_id = receipt.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if client_row.id is null or recipient.id is null then
    raise exception 'This payment needs an active customer email address before a receipt can be sent.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select organization.name into business_name from public.organizations as organization
    where organization.id = receipt.organization_id;

  -- The organization's default automated sender, exactly as the invoice and quote emails choose it.
  select * into sender from public.communication_email_senders
    where organization_id = receipt.organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    raise exception 'No automated email sender is ready for this business.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  update public.payment_receipt_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = receipt.organization_id and client_payment_event_id = receipt.id and revoked_at is null;
  insert into public.payment_receipt_access_links (organization_id, client_payment_event_id, recipient_name, recipient_email, token_hash, issued_by)
    values (receipt.organization_id, receipt.id,
      coalesce(nullif(trim(client_row.display_name), ''), recipient.normalized_value), recipient.normalized_value,
      target_receipt_token_hash, target_actor_user_id);

  money_text := trim(to_char(receipt.amount_minor / 100.0, 'FM999G999G990D00')) || ' ' || receipt.currency_code;
  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, client_payment_event_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by)
    values (receipt.organization_id, receipt.client_id, recipient.id, receipt.id, target_logical_send_key, recipient.normalized_value,
      'Receipt for your payment to ' || coalesce(nullif(trim(business_name), ''), 'your contractor'),
      '<p>Thank you for your payment of ' || money_text || '.</p><p><a href="' || replace(target_receipt_url, '&', '&amp;') || '">View your receipt</a></p>',
      'Thank you for your payment of ' || money_text || '. View your receipt here: ' || target_receipt_url,
      'automated', 'essential', sender.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);

  return intent;
end;
$$;

comment on function public.enqueue_payment_receipt_email(uuid, uuid, uuid, text, text, bytea) is
  'Queues one payment-receipt email as a hosted link (no PDF attachment -- we run no PDF engine). Idempotent '
  'on the logical send key; a deliberate resend passes a new key. Service role only.';

revoke all on function public.enqueue_payment_receipt_email(uuid, uuid, uuid, text, text, bytea) from public, anon, authenticated;
grant execute on function public.enqueue_payment_receipt_email(uuid, uuid, uuid, text, text, bytea) to service_role;

-- 6. Least privilege -------------------------------------------------------------------------------------

alter table public.payment_receipt_access_links enable row level security;

-- No policy and no grant: every row holds a token hash. 6b-2b's staff render of a receipt goes through a
-- definer function that cannot return that column, exactly as invoices and quotes do.
revoke all on public.payment_receipt_access_links from anon, authenticated;

notify pgrst, 'reload schema';
