-- Invoices Part 6a: the customer's copy of a bill, and the one safe way they get to see it.
--
-- Everything before this part is staff-facing: the list, the detail, the money ledger. This part gives an
-- issued invoice a customer-facing door. Like quotes, it is built on three rules.
--
--   1. One definition of what a customer may see. private.invoice_customer_document is the only place that
--      assembles the customer's document, so the token page (a stranger with a link) and Preview as client
--      (a signed-in member) can never drift into showing different things.
--   2. The raw token never reaches the database. The server hashes it and passes 32 bytes, so a stolen
--      backup carries no working link.
--   3. `anon` gets nothing. The public page runs on our server with the service key and calls exactly one
--      function, which is the only public seam.
--
-- Issuing links, sending, and view/receipt facts are Part 6b. This part builds the document, the link table
-- it will populate, the resolver that reads it, and Preview as client -- which is fully exercisable now
-- against any issued invoice, without a link existing yet.

-- 1. The one builder ---------------------------------------------------------------------------------------

-- Invoker, not definer, and private: it is only ever reached from inside a security definer function that
-- has already decided the caller is allowed to be here. It makes no access decision of its own -- it is
-- handed the frozen invoice row, the business name, the already-derived contract status, and whether money
-- is included. An invoice freezes its own customer, billing and service snapshots at issue, so unlike a
-- quote there is no separate version row to read: the row is the document.
--
-- The deposit-vs-payment split is real data: invoice_payment_allocations rows carry payment_event_id XOR
-- deposit_event_id, and an 'unapplied' entry takes an 'applied' one back. Summed by source (applied add,
-- unapplied subtract) that is exactly "Deposit applied" and "Payment received", and the balance is the
-- total minus their sum -- the same net the detail screen shows.
create or replace function private.invoice_customer_document(
  invoice_row public.invoices,
  business_name text,
  derived_status text,
  include_money boolean
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  deposit_applied_minor bigint := 0;
  payment_received_minor bigint := 0;
begin
  if include_money then
    select
      coalesce(sum(case when entry.deposit_event_id is not null then signed else 0 end), 0),
      coalesce(sum(case when entry.payment_event_id is not null then signed else 0 end), 0)
    into deposit_applied_minor, payment_received_minor
    from (
      select
        allocation.deposit_event_id,
        allocation.payment_event_id,
        case when allocation.entry_type = 'applied'
          then allocation.amount_minor else -allocation.amount_minor end as signed
      from public.invoice_payment_allocations as allocation
      where allocation.organization_id = invoice_row.organization_id
        and allocation.invoice_id = invoice_row.id
    ) as entry;
  end if;

  return jsonb_build_object(
    'business', jsonb_build_object('name', business_name),
    'invoice', jsonb_build_object(
      'invoice_number', invoice_row.invoice_number,
      'subject', invoice_row.subject,
      'currency_code', invoice_row.currency_code,
      'status', derived_status,
      'issue_date', invoice_row.issue_date,
      'due_date', invoice_row.due_date,
      'due_date_source', invoice_row.due_date_source,
      'payment_term_snapshot', invoice_row.payment_term_snapshot
    ),
    -- The frozen snapshots, verbatim. A later rename or address change on the client record never rewrites
    -- the bill a customer was handed.
    'customer', invoice_row.customer_snapshot,
    'billing_address', invoice_row.billing_address_snapshot,
    'service_properties', invoice_row.service_properties,
    -- A hidden price is one that never enters the payload, not one drawn and then covered in the browser.
    -- include_money closes the amounts for a member who may open a bill but not see its prices, in the same
    -- place and for the same reason as the detail read model.
    'lines', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'line_id', line.id,
          'position', line.position,
          'line_kind', line.line_kind,
          'name', line.name,
          'description', line.description,
          'unit_label', line.unit_label,
          'quantity', line.quantity,
          'service_date', line.service_date
        )
        || case when include_money
             then jsonb_build_object(
               'unit_price_minor', line.unit_price_minor,
               'line_total_minor', line.line_total_minor)
             else '{}'::jsonb end
        order by line.position, line.id
      ), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = invoice_row.organization_id
        and line.invoice_id = invoice_row.id
    ),
    'money', case when include_money then jsonb_build_object(
      'subtotal_minor', invoice_row.subtotal_minor,
      'discount', case when invoice_row.discount_minor > 0 then jsonb_build_object(
        'name', invoice_row.discount_name,
        'type', invoice_row.discount_type,
        'value', invoice_row.discount_value,
        'amount_minor', invoice_row.discount_minor
      ) else null end,
      'tax', case when invoice_row.tax_minor > 0 then jsonb_build_object(
        'name', invoice_row.tax_name,
        'rate_basis_points', invoice_row.tax_rate_basis_points,
        'amount_minor', invoice_row.tax_minor
      ) else null end,
      'total_minor', invoice_row.total_minor,
      'deposit_applied_minor', deposit_applied_minor,
      'payment_received_minor', payment_received_minor,
      'balance_due_minor', invoice_row.total_minor - deposit_applied_minor - payment_received_minor
    ) else null end
  );
end;
$$;

comment on function private.invoice_customer_document(public.invoices, text, text, boolean) is
  'The only definition of what a customer may see on a bill. Called by public.resolve_invoice_access_link '
  'for the customer and by public.invoice_customer_preview for staff. No cost, no margin, no internal note '
  'and no other client may ever be added here. Money -- line prices, totals, tax, discount and the '
  'deposit/payment split -- is left out whole when include_money is false.';

revoke all on function private.invoice_customer_document(public.invoices, text, text, boolean)
  from public, anon, authenticated, service_role;

-- 2. The link itself ---------------------------------------------------------------------------------------

-- One customer link, scoped to organization and invoice. Unlike a quote there is no version to pin: an
-- issued invoice's document is frozen on the row, and a permitted edit replaces the bill with a new one that
-- carries its own link. The recipient the link was addressed to is copied onto the row (Part 6b sets it when
-- it issues); the invoice's own customer_snapshot is who the document is billed to.
create table public.invoice_access_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  recipient_name text check (recipient_name is null or char_length(trim(recipient_name)) between 1 and 200),
  recipient_email text check (
    recipient_email is null or (
      recipient_email = lower(trim(recipient_email))
      and char_length(recipient_email) between 6 and 320
      and recipient_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    )
  ),
  -- SHA-256 of a 256-bit random token, as raw bytes: fixed width, and the only thing about the token that
  -- survives the request that created it.
  token_hash bytea not null check (octet_length(token_hash) = 32),
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text check (revoked_reason is null or revoked_reason in ('rotated', 'revoked')),
  constraint invoice_access_links_token_hash_unique unique (token_hash),
  constraint invoice_access_links_organization_id_unique unique (organization_id, id),
  constraint invoice_access_links_invoice_fk foreign key (organization_id, invoice_id)
    references public.invoices(organization_id, id) on delete cascade,
  constraint invoice_access_links_revocation_agrees check ((revoked_at is null) = (revoked_reason is null)),
  constraint invoice_access_links_expiry_follows_issue check (expires_at is null or expires_at > issued_at)
);

comment on table public.invoice_access_links is
  'One customer link to an issued invoice. Scoped to organization and invoice. Stores only the token hash -- '
  'the raw token exists once, in the URL handed to the staff member who created it, and must never appear in '
  'a row, a log line, or an activity payload.';

comment on column public.invoice_access_links.token_hash is
  'SHA-256 of the raw token, computed by the server. The database never sees the token itself.';

-- The customer read is one equality lookup on the unique token hash. These serve the foreign key and the
-- staff view of an invoice's links; neither is on the customer path.
create index invoice_access_links_invoice_idx
  on public.invoice_access_links(organization_id, invoice_id, issued_at desc);

create index invoice_access_links_issued_by_idx
  on public.invoice_access_links(issued_by) where issued_by is not null;

-- 3. The one public seam -----------------------------------------------------------------------------------

-- Our server hashes the token from the URL and calls this as the service role. Everything a customer may see
-- is assembled here from the frozen invoice, and everything else is simply never selected.
--
-- Every way of failing returns the same null -- unknown token, revoked, expired, a draft, a voided bill, or
-- one that has been replaced (the replacement has its own link) -- so the page cannot be used to find out
-- whether an invoice exists. The customer always sees their own amounts: a bill with the numbers left off is
-- not a bill, so include_money is unconditionally true here.
create or replace function public.resolve_invoice_access_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.invoice_access_links;
  invoice_row public.invoices;
  applied_minor bigint;
  derived_status text;
  business_name text;
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

  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into applied_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = invoice_row.organization_id and entry.invoice_id = invoice_row.id;

  derived_status := private.invoice_live_status(
    invoice_row.voided_at, invoice_row.written_off_at, invoice_row.issued_at, invoice_row.recognized_at,
    invoice_row.marked_received_at, invoice_row.total_minor, applied_minor, invoice_row.due_date,
    private.organization_today(invoice_row.organization_id));

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = invoice_row.organization_id;

  return private.invoice_customer_document(invoice_row, business_name, derived_status, true);
end;
$$;

comment on function public.resolve_invoice_access_link(bytea) is
  'The customer''s reader. Hashed token in, one customer document out, or null for every failure alike. '
  'Service role only: not part of the Data API for anybody else.';

-- 4. Preview as client -------------------------------------------------------------------------------------

-- The same document a customer would see, for a signed-in member who holds no token. It mints nothing: no
-- link, no recipient. Money follows the same permission as the rest of the app -- a member with invoices.view
-- but not invoices.view_price gets the document and the status with the amounts left out of the payload, not
-- hidden in the browser. Unlike quotes there is no draft preview here: an invoice document is only frozen at
-- issue, so a draft has no customer document to show yet.
create or replace function public.invoice_customer_preview(target_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  can_see_price boolean;
  applied_minor bigint;
  derived_status text;
  business_name text;
begin
  select * into invoice_row from public.invoices where id = target_invoice_id;
  if invoice_row.id is null
     or not private.member_has_permission(invoice_row.organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to this invoice.' using errcode = 'insufficient_privilege';
  end if;

  can_see_price := private.member_has_permission(
    invoice_row.organization_id, caller, 'invoices.view_price');

  -- A replaced bill keeps the label it was frozen with; every other is derived live from the one shared rule.
  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into applied_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = invoice_row.organization_id and entry.invoice_id = invoice_row.id;

  derived_status := case
    when invoice_row.replaced_at is not null then invoice_row.frozen_status_label
    else private.invoice_live_status(
      invoice_row.voided_at, invoice_row.written_off_at, invoice_row.issued_at, invoice_row.recognized_at,
      invoice_row.marked_received_at, invoice_row.total_minor, applied_minor, invoice_row.due_date,
      private.organization_today(invoice_row.organization_id))
  end;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = invoice_row.organization_id;

  return jsonb_build_object(
    'document', private.invoice_customer_document(
      invoice_row, business_name, derived_status, can_see_price),
    'preview', jsonb_build_object(
      'is_issued', invoice_row.issued_at is not null,
      'is_replaced', invoice_row.replaced_at is not null,
      'prices_withheld', not can_see_price
    )
  );
end;
$$;

comment on function public.invoice_customer_preview(uuid) is
  'Preview as client. Returns the same customer document the token page renders, for a signed-in member with '
  'invoices.view, without creating a link. Amounts are withheld from the payload unless the member holds '
  'invoices.view_price.';

-- 5. Least privilege ---------------------------------------------------------------------------------------

alter table public.invoice_access_links enable row level security;

-- No policy and no grant at all: every row holds a token hash. Part 6b's staff view of an invoice's links
-- will read them through a definer function that cannot return that column, exactly as quotes do.
revoke all on public.invoice_access_links from anon, authenticated;

revoke all on function public.invoice_customer_preview(uuid) from public;
revoke execute on function public.invoice_customer_preview(uuid) from anon;
grant execute on function public.invoice_customer_preview(uuid) to authenticated;

-- The resolver is not part of the Data API for anybody. Only our own server, holding the service key, may
-- call it.
revoke all on function public.resolve_invoice_access_link(bytea) from public;
revoke execute on function public.resolve_invoice_access_link(bytea) from anon, authenticated;
grant execute on function public.resolve_invoice_access_link(bytea) to service_role;

notify pgrst, 'reload schema';
