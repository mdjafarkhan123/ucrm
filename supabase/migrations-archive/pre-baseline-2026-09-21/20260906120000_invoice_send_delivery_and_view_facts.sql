-- Invoices Part 6b-1: sending an invoice, copying its customer link, and recording that the client opened it.
--
-- 6a built the frozen customer document, the link table, and the two readers (public resolver + staff
-- preview). It deliberately left issuing links, sending, and view facts to this part. Everything here mirrors
-- the shipped Quote machinery so the two never drift:
--   * public.issue_invoice_access_link  -> the "Copy customer link" press (runs as the member, invoices.send)
--   * public.enqueue_invoice_communication_email -> the "Send invoice" email (service role, Communications)
--   * public.record_invoice_link_view   -> the customer's browser telling us the document was on screen
-- and public.invoice_detail is widened with a `delivery` block so the detail screen can show "Sent" and
-- "Viewed" without a second round trip.
--
-- Sendable, everywhere here, means exactly what the 6a resolver already means: an invoice that is issued, not
-- voided, and not replaced. A draft is issued by the caller first (issue_invoice, method 'sent') and only then
-- delivered -- issuing and delivering are two facts, the same as Mark as Sent already is.

-- 1. The delivery intent can now name an invoice ----------------------------------------------------------

-- Invoices are the second system-owned operational-email source, after Quotes. Same optional-FK shape, same
-- restrict-on-delete, same partial index for "the emails we sent for this invoice, newest first".
alter table public.communication_delivery_intents add column invoice_id uuid;
alter table public.communication_delivery_intents add constraint communication_delivery_intents_invoice_fk
  foreign key (organization_id, invoice_id) references public.invoices(organization_id, id) on delete restrict;
create index communication_delivery_intents_invoice_created_idx
  on public.communication_delivery_intents (organization_id, invoice_id, created_at desc, id desc)
  where invoice_id is not null;

-- 2. Whether the customer ever opened the link ------------------------------------------------------------

-- Stamped only by an explicit call from the customer's browser after the document is drawn -- never by a page
-- request, a HEAD, a mail scanner or a chat link preview, none of which are a person reading a bill.
alter table public.invoice_access_links
  add column first_viewed_at timestamptz,
  add column last_viewed_at timestamptz,
  add column view_count integer not null default 0 check (view_count >= 0);

comment on column public.invoice_access_links.first_viewed_at is
  'Stamped once, by an explicit call from the customer''s browser after the document is on screen. Never by a '
  'page request, a HEAD, a mail scanner or a link preview.';

-- 3. Copy customer link ------------------------------------------------------------------------------------

-- The member's own press. The token is generated in Node and only its SHA-256 arrives here, so the raw link
-- exists once, in the response, on its way to the person who asked for it. Asking twice does not leave two
-- working doors: this rotates the invoice's live links in the same transaction.
create or replace function public.issue_invoice_access_link(
  target_invoice_id uuid,
  supplied_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  client_name text;
  client_email text;
  link_row public.invoice_access_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'A customer link needs a full-length token.' using errcode = 'check_violation';
  end if;

  select * into invoice_row from public.invoices where id = target_invoice_id for update;

  if invoice_row.id is null
     or not private.member_has_permission(invoice_row.organization_id, caller, 'invoices.send') then
    raise exception 'You do not have access to share this invoice.' using errcode = 'insufficient_privilege';
  end if;

  if invoice_row.issued_at is null then
    raise exception 'Send this invoice before creating a customer link.' using errcode = 'check_violation';
  end if;
  if invoice_row.voided_at is not null or invoice_row.replaced_at is not null then
    raise exception 'This invoice can no longer be shared.' using errcode = 'check_violation';
  end if;

  select client.display_name,
         (
           select lower(trim(method.value))
           from public.client_contact_methods as method
           where method.organization_id = invoice_row.organization_id
             and method.client_id = invoice_row.client_id
             and method.kind = 'email'
           order by method.is_primary desc, method.created_at
           limit 1
         )
    into client_name, client_email
  from public.clients as client
  where client.organization_id = invoice_row.organization_id
    and client.id = invoice_row.client_id;

  if client_email is null then
    raise exception 'Add an email address to this client before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  update public.invoice_access_links
  set revoked_at = now(), revoked_reason = 'rotated'
  where organization_id = invoice_row.organization_id
    and invoice_id = invoice_row.id
    and revoked_at is null;

  insert into public.invoice_access_links (
    organization_id, invoice_id, recipient_name, recipient_email, token_hash, issued_by
  ) values (
    invoice_row.organization_id, invoice_row.id,
    coalesce(nullif(trim(client_name), ''), client_email), client_email,
    supplied_token_hash, caller
  )
  returning * into link_row;

  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.link_issued', caller, invoice_row.revision, null,
    jsonb_build_object('invoice_access_link_id', link_row.id, 'recipient_email', client_email)
  );

  return jsonb_build_object(
    'invoice_id', invoice_row.id,
    'invoice_access_link_id', link_row.id,
    'recipient_name', link_row.recipient_name,
    'recipient_email', link_row.recipient_email,
    'issued_at', link_row.issued_at,
    'expires_at', link_row.expires_at
  );
end;
$$;

comment on function public.issue_invoice_access_link(uuid, bytea) is
  'Creates the customer''s door to an issued invoice and returns everything but the token, which only ever '
  'exists in the caller''s response. Rotates the invoice''s live links so asking twice never leaves two open.';

revoke all on function public.issue_invoice_access_link(uuid, bytea) from public;
revoke execute on function public.issue_invoice_access_link(uuid, bytea) from anon;
grant execute on function public.issue_invoice_access_link(uuid, bytea) to authenticated;

-- 4. Send by email -----------------------------------------------------------------------------------------

-- Service role only, called by our own server after it has generated the token. It checks the invoice is
-- sendable, resolves the recipient and an eligible verified sender, rotates the live links, opens a fresh
-- door, and queues one email -- all in one transaction, idempotent on the logical send key so a double click
-- returns the first intent rather than sending twice.
create or replace function public.enqueue_invoice_communication_email(
  target_organization_id uuid, target_actor_user_id uuid, target_invoice_id uuid,
  target_logical_send_key text, target_invoice_url text, target_invoice_token_hash bytea
) returns public.communication_delivery_intents
language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare
  invoice_row public.invoices; client_row public.clients;
  recipient public.client_contact_methods;
  business_name text;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'invoices.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to send this invoice by email.' using errcode = 'insufficient_privilege';
  end if;
  if target_invoice_url !~ '^https?://[^[:space:]]+$' or target_invoice_token_hash is null
    or octet_length(target_invoice_token_hash) <> 32 then
    raise exception 'The invoice delivery link is not available.' using errcode = 'check_violation';
  end if;
  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = target_logical_send_key for share;
  if intent.id is not null then
    if intent.invoice_id is distinct from target_invoice_id then
      raise exception 'This email retry does not match the original invoice.' using errcode = 'unique_violation';
    end if;
    return intent;
  end if;
  select * into invoice_row from public.invoices
    where organization_id = target_organization_id and id = target_invoice_id for share;
  if invoice_row.id is null or invoice_row.issued_at is null
    or invoice_row.voided_at is not null or invoice_row.replaced_at is not null then
    raise exception 'This invoice is not available to send.' using errcode = 'foreign_key_violation';
  end if;
  select * into client_row from public.clients
    where organization_id = invoice_row.organization_id and id = invoice_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = invoice_row.organization_id and client_id = invoice_row.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if client_row.id is null or recipient.id is null then
    raise exception 'This invoice needs an active customer email address before it can be sent.' using errcode = 'object_not_in_prerequisite_state';
  end if;
  select organization.name into business_name from public.organizations as organization
    where organization.id = invoice_row.organization_id;
  -- The organization's default automated sender, exactly as enqueue_quote_communication_email chooses it.
  -- (An earlier draft preferred a sender assigned to the client's owner, but clients carry no owner column,
  -- so that reference raised undefined_column on every real send.)
  select * into sender from public.communication_email_senders
    where organization_id = invoice_row.organization_id and lifecycle_state = 'enabled' and allows_automated
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
  update public.invoice_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = invoice_row.organization_id and invoice_id = invoice_row.id and revoked_at is null;
  insert into public.invoice_access_links (organization_id, invoice_id, recipient_name, recipient_email, token_hash, issued_by)
    values (invoice_row.organization_id, invoice_row.id,
      coalesce(nullif(trim(client_row.display_name), ''), recipient.normalized_value), recipient.normalized_value,
      target_invoice_token_hash, target_actor_user_id);
  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, invoice_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by)
    values (invoice_row.organization_id, invoice_row.client_id, recipient.id, invoice_row.id, target_logical_send_key, recipient.normalized_value,
      'Your invoice from ' || coalesce(nullif(trim(business_name), ''), 'your contractor'),
      '<p>Your invoice is ready to view.</p><p><a href="' || replace(target_invoice_url, '&', '&amp;') || '">View your invoice</a></p>',
      'Your invoice is ready to view. View it here: ' || target_invoice_url, 'automated', 'essential', sender.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);
  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.sent', target_actor_user_id, invoice_row.revision, null,
    jsonb_build_object('delivery_intent_id', intent.id, 'recipient_email', recipient.normalized_value)
  );
  return intent;
end;
$$;
revoke all on function public.enqueue_invoice_communication_email(uuid, uuid, uuid, text, text, bytea) from public, anon, authenticated;
grant execute on function public.enqueue_invoice_communication_email(uuid, uuid, uuid, text, text, bytea) to service_role;

-- 5. The customer opened it --------------------------------------------------------------------------------

-- Called by the customer's own browser once the document is drawn -- the only moment that means what staff
-- think "viewed" means. Answers the same whether it recorded anything or not, so a forged call with a dead
-- token cannot be used to learn the token is dead.
create or replace function public.record_invoice_link_view(supplied_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.invoice_access_links;
  invoice_row public.invoices;
  was_first boolean;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.invoice_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into invoice_row from public.invoices where id = link_row.invoice_id;
  if invoice_row.id is null
     or invoice_row.issued_at is null
     or invoice_row.voided_at is not null
     or invoice_row.replaced_at is not null then
    return null;
  end if;

  was_first := link_row.first_viewed_at is null;

  update public.invoice_access_links
  set first_viewed_at = coalesce(first_viewed_at, now()),
      last_viewed_at = now(),
      view_count = view_count + 1
  where id = link_row.id;

  if was_first then
    perform private.record_invoice_event(
      invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
      'invoice.viewed_by_client', null, invoice_row.revision, null,
      jsonb_build_object('invoice_access_link_id', link_row.id)
    );
  end if;

  return jsonb_build_object('recorded', true, 'first_view', was_first);
end;
$$;
revoke all on function public.record_invoice_link_view(bytea) from public;
revoke execute on function public.record_invoice_link_view(bytea) from anon, authenticated;
grant execute on function public.record_invoice_link_view(bytea) to service_role;

-- 6. Surface Sent / Viewed on the detail screen -----------------------------------------------------------

-- Widen the existing detail read model with one `delivery` block. Both reads are bounded and indexed: the
-- latest delivery intent for this invoice (the invoice partial index above), and the invoice's links (the
-- 6a (organization, invoice, issued_at desc) index). Aggregating the view stamps across links means a
-- rotated link never loses the fact that the customer had already opened an earlier one.
create or replace function public.invoice_detail(
  target_organization_id uuid,
  target_invoice_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_see_price boolean;
  today date;
  invoice_row public.invoices;
  applied_minor bigint;
  derived_status text;
  money jsonb;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  can_see_price := private.member_has_permission(target_organization_id, caller, 'invoices.view_price');
  today := private.organization_today(target_organization_id);

  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;

  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into applied_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = target_organization_id and entry.invoice_id = target_invoice_id;

  derived_status := case
    when invoice_row.replaced_at is not null then invoice_row.frozen_status_label
    else private.invoice_live_status(
      invoice_row.voided_at, invoice_row.written_off_at, invoice_row.issued_at, invoice_row.recognized_at,
      invoice_row.marked_received_at, invoice_row.total_minor, applied_minor, invoice_row.due_date, today)
  end;

  if can_see_price then
    money := jsonb_build_object(
      'subtotal_minor', invoice_row.subtotal_minor,
      'discount_minor', invoice_row.discount_minor,
      'discount_name', invoice_row.discount_name,
      'discount_type', invoice_row.discount_type,
      'discount_value', invoice_row.discount_value,
      'tax_minor', invoice_row.tax_minor,
      'tax_source', invoice_row.tax_source,
      'tax_name', invoice_row.tax_name,
      'tax_rate_id', invoice_row.tax_rate_id,
      'tax_rate_basis_points', invoice_row.tax_rate_basis_points,
      'total_minor', invoice_row.total_minor,
      'allocated_minor', applied_minor,
      'remaining_minor', invoice_row.total_minor - applied_minor
    );
  else
    money := null;
  end if;

  return jsonb_build_object(
    'invoice', jsonb_build_object(
      'id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'revision', invoice_row.revision,
      'subject', invoice_row.subject,
      'currency_code', invoice_row.currency_code,
      'issue_date', invoice_row.issue_date,
      'due_date', invoice_row.due_date,
      'due_date_source', invoice_row.due_date_source,
      'payment_term_snapshot', invoice_row.payment_term_snapshot,
      'customer_snapshot', invoice_row.customer_snapshot,
      'billing_address_snapshot', invoice_row.billing_address_snapshot,
      'service_properties', invoice_row.service_properties,
      'issued_at', invoice_row.issued_at,
      'issue_method', invoice_row.issue_method,
      'voided_at', invoice_row.voided_at,
      'void_reason', invoice_row.void_reason,
      'void_note', invoice_row.void_note,
      'written_off_at', invoice_row.written_off_at,
      'marked_received_at', invoice_row.marked_received_at,
      'recognized_at', invoice_row.recognized_at,
      'replaced_at', invoice_row.replaced_at,
      'replaced_by_invoice_id', invoice_row.replaced_by_invoice_id,
      'predecessor_invoice_id', invoice_row.predecessor_invoice_id,
      'replacement_kind', invoice_row.replacement_kind,
      'is_replaced', invoice_row.replaced_at is not null,
      'derived_status', derived_status,
      'client_id', invoice_row.client_id,
      'created_at', invoice_row.created_at
    ),
    'client', (
      select case when client.id is null then null else jsonb_build_object(
        'id', client.id,
        'display_name', client.display_name,
        'company_name', client.company_name,
        -- The client's primary email, so the send dialog can show who the invoice goes to and refuse to send
        -- when there is nobody to send it to. Not money, so it rides outside the price gate.
        'email', (
          select lower(trim(method.value))
          from public.client_contact_methods as method
          where method.organization_id = target_organization_id
            and method.client_id = client.id
            and method.kind = 'email'
          order by method.is_primary desc, method.created_at
          limit 1
        )
      ) end
      from public.clients as client
      where client.organization_id = target_organization_id and client.id = invoice_row.client_id
    ),
    'money', money,
    'delivery', jsonb_build_object(
      'last_sent', (
        select case when intent.id is null then null else jsonb_build_object(
          'sent_at', intent.created_at,
          'status', intent.status,
          'recipient_email', intent.recipient_email
        ) end
        from public.communication_delivery_intents as intent
        where intent.organization_id = target_organization_id and intent.invoice_id = target_invoice_id
        order by intent.created_at desc, intent.id desc
        limit 1
      ),
      'views', (
        select jsonb_build_object(
          'first_viewed_at', min(link.first_viewed_at),
          'last_viewed_at', max(link.last_viewed_at),
          'view_count', coalesce(sum(link.view_count), 0)
        )
        from public.invoice_access_links as link
        where link.organization_id = target_organization_id and link.invoice_id = target_invoice_id
      )
    ),
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', line.id,
        'position', line.position,
        'line_kind', line.line_kind,
        'category', line.category,
        'name', line.name,
        'description', line.description,
        'unit_label', line.unit_label,
        'quantity', line.quantity,
        'is_taxable', line.is_taxable,
        'service_date', line.service_date,
        'unit_price_minor', case when can_see_price then line.unit_price_minor else null end,
        'line_total_minor', case when can_see_price then line.line_total_minor else null end
      ) order by line.position, line.id), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = target_organization_id and line.invoice_id = target_invoice_id
    )
  );
end;
$$;

comment on function public.invoice_detail(uuid, uuid) is
  'One whole invoice for the detail screen: its frozen document, derived contract status, revision, money '
  '(gated on invoices.view_price), and a delivery block with the last email sent and whether the customer '
  'has opened it. Definer; checks invoices.view and scopes to the one organization.';

revoke all on function public.invoice_detail(uuid, uuid) from public, anon;
grant execute on function public.invoice_detail(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
