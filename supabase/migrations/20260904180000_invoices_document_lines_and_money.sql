-- Invoices Part 3a, file 2 of 3: the bill itself.
--
-- File 1 built what an invoice has to read before it can exist: permissions, payment terms, and the client's
-- billing address. This file builds the bill: its number, its frozen document, its lines, the one piece of
-- arithmetic that owns its money, its history, and the private ledger that makes a retried command safe.
--
-- Two rules shape everything here. First, an invoice is a snapshot, not a view of live work: the customer,
-- the billing address, the service properties, the terms and the lines are copied onto the invoice and a
-- later edit to a client, a property or a job can never rewrite them. Second, the six statuses the contract
-- names are derived from the facts stored here, so there is no status column for a command to get wrong and
-- no nightly job that has to run for an invoice to become past due.
--
-- Deliberately not here: the commands that create, edit, issue or void an invoice (file 3), and every table
-- that moves money -- receipts, allocations and source claims belong to 3b and 3c.

-- 1. Invoice numbers ------------------------------------------------------------------------------------------

-- The same shape as organization_quote_counters and its job twin: one row per organization, written only by
-- the allocator under its own row lock, so two invoices created in the same instant cannot be handed the
-- same number. RLS on with no policy and no grant: a member cannot read how many invoices exist.
create table public.organization_invoice_counters (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  next_invoice_number integer not null default 1 check (next_invoice_number >= 1),
  updated_at timestamptz not null default now()
);

comment on table public.organization_invoice_counters is
  'Per-organization invoice number allocation. Written only by private.allocate_invoice_number under a row '
  'lock; numbers are never reused, never decrease, and a rolled-back transaction leaves no committed gap '
  'because its invoice was never committed either.';

alter table public.organization_invoice_counters enable row level security;
revoke all on public.organization_invoice_counters from anon, authenticated;

create or replace function private.allocate_invoice_number(target_organization_id uuid)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  allocated integer;
begin
  insert into public.organization_invoice_counters (organization_id)
  values (target_organization_id)
  on conflict (organization_id) do nothing;

  update public.organization_invoice_counters
  set next_invoice_number = next_invoice_number + 1, updated_at = now()
  where organization_id = target_organization_id
  returning next_invoice_number - 1 into allocated;

  if allocated is null then
    raise exception 'That organization cannot be given an invoice number.'
      using errcode = 'foreign_key_violation';
  end if;

  return allocated;
end;
$$;

revoke all on function private.allocate_invoice_number(uuid) from public;
revoke execute on function private.allocate_invoice_number(uuid) from anon, authenticated;

-- 2. The invoice ------------------------------------------------------------------------------------------------

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Restrict, not cascade: a client with financial history cannot be deleted out from under it.
  client_id uuid not null,
  invoice_number integer not null check (invoice_number >= 1),
  subject text not null check (char_length(trim(subject)) between 2 and 160),
  -- Snapshot, not a lookup. Copied from organization_settings at creation and never changed afterwards, so
  -- an organization that switches currency cannot silently relabel a bill it already sent.
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),

  -- The frozen document ------------------------------------------------------------------------------------
  -- Who the bill is addressed to and where it goes, copied at creation and refreshed only by an explicit
  -- command while the invoice is still a draft. Nothing that renders history ever reads the live client.
  customer_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(customer_snapshot) = 'object'),
  billing_address_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(billing_address_snapshot) = 'object'),
  -- Every service property on the bill, in one array, so one invoice can cover several jobs at several
  -- addresses without duplicating a source claim. 3c's source rows point at an entry in this array by index.
  service_properties jsonb not null default '[]'::jsonb
    check (jsonb_typeof(service_properties) = 'array'),
  -- Stamped when the document stops being editable-by-default: at issue, or at the moment a draft is fully
  -- paid and recognised. A permitted edit after that keeps the prior snapshot in invoice_events.
  document_frozen_at timestamptz,

  -- Terms and dates ------------------------------------------------------------------------------------------
  -- Both dates are the organization's own calendar dates, resolved through private.organization_today and
  -- private.invoice_due_date. Storing them as dates is what stops a timezone change from moving a due date.
  payment_term_id uuid,
  payment_term_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payment_term_snapshot) = 'object'),
  due_date_source text not null default 'term' check (due_date_source in ('term', 'custom')),
  issue_date date not null,
  due_date date not null,

  -- Issue, recognition and closure facts ------------------------------------------------------------------
  issued_at timestamptz,
  issued_by uuid references auth.users(id) on delete set null,
  issue_method text check (issue_method in ('sent', 'marked_sent')),
  -- D1: a draft that gets fully paid is recognised as a settled bill without pretending it was ever sent.
  recognized_at timestamptz,
  -- Status-only closure. It moves the label to Paid and extinguishes no debt.
  marked_received_at timestamptz,
  marked_received_by uuid references auth.users(id) on delete set null,
  -- Bad debt: valid work that will not be collected. Reversible, which is why these are nullable stamps.
  written_off_at timestamptz,
  written_off_by uuid references auth.users(id) on delete set null,
  write_off_note text check (write_off_note is null or char_length(write_off_note) <= 2000),
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text check (
    void_reason in ('duplicate', 'created_in_error', 'client_request', 'other')
  ),
  void_note text check (void_note is null or char_length(void_note) <= 2000),

  -- Correction and rebill chains ------------------------------------------------------------------------------
  -- The bill this one replaces, and the first bill in the chain. Root is what a source claim attaches to, so
  -- a correction can never let the same work be billed twice through a second independent chain.
  predecessor_invoice_id uuid,
  root_invoice_id uuid not null,
  replacement_kind text check (replacement_kind in ('correction', 'rebill')),
  -- Filled on the successor's activation command, never before: a prepared draft does not switch off an
  -- issued bill until somebody says so.
  replaced_at timestamptz,
  replaced_by_invoice_id uuid,
  -- The label this invoice had when it was replaced, frozen so history never ages into Past Due.
  frozen_status_label text check (
    frozen_status_label in ('draft', 'awaiting_payment', 'past_due', 'paid', 'bad_debt', 'voided')
  ),

  -- Money. Maintained only by private.store_invoice_money; no command writes these by hand.
  discount_name text,
  discount_type text,
  discount_value bigint,
  tax_source text not null default 'not_configured' check (tax_source in (
    'not_configured', 'business_default', 'property_default', 'saved_rate', 'no_tax', 'custom'
  )),
  tax_name text,
  tax_rate_basis_points integer not null default 0,
  tax_rate_id uuid,
  subtotal_minor bigint not null default 0 check (subtotal_minor between 0 and 1000000000000),
  discount_minor bigint not null default 0 check (discount_minor between 0 and 1000000000000),
  tax_minor bigint not null default 0 check (tax_minor between 0 and 1000000000000),
  total_minor bigint not null default 0 check (total_minor between 0 and 1000000000000),

  revision integer not null default 0 check (revision >= 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint invoices_organization_id_unique unique (organization_id, id),
  constraint invoices_number_unique unique (organization_id, invoice_number),
  constraint invoices_client_organization_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict,
  constraint invoices_payment_term_fk foreign key (organization_id, payment_term_id)
    references public.invoice_payment_terms(organization_id, id) on delete restrict,
  constraint invoices_tax_rate_organization_fk foreign key (organization_id, tax_rate_id)
    references public.organization_tax_rates(organization_id, id) on delete set null (tax_rate_id),
  constraint invoices_predecessor_fk foreign key (organization_id, predecessor_invoice_id)
    references public.invoices(organization_id, id) on delete restrict,
  constraint invoices_root_fk foreign key (organization_id, root_invoice_id)
    references public.invoices(organization_id, id) on delete restrict,
  constraint invoices_replaced_by_fk foreign key (organization_id, replaced_by_invoice_id)
    references public.invoices(organization_id, id) on delete restrict,

  -- A term-based due date needs a term. A custom due date is a date the contractor typed, and the term
  -- column stays empty rather than pointing at a term the date does not follow.
  constraint invoices_due_date_source_shape check (
    (due_date_source = 'term' and payment_term_id is not null)
    or (due_date_source = 'custom' and payment_term_id is null)
  ),
  constraint invoices_due_not_before_issue check (due_date >= issue_date),
  -- Issued means issued by some route. A stamp without a route, or a route without a stamp, is half a fact.
  constraint invoices_issue_facts_complete check ((issued_at is null) = (issue_method is null)),
  -- The document freezes exactly when the bill becomes real: issued, or recognised through full payment.
  constraint invoices_frozen_when_real check (
    (document_frozen_at is not null) = (issued_at is not null or recognized_at is not null)
  ),
  constraint invoices_void_facts_complete check ((voided_at is null) = (void_reason is null)),
  constraint invoices_void_note_needs_void check (void_note is null or voided_at is not null),
  -- A voided bill is cancelled, not written off, and not closed by hand. The two closures are different
  -- financial statements and an invoice may not make both.
  constraint invoices_void_excludes_closure check (
    voided_at is null or (written_off_at is null and marked_received_at is null)
  ),
  -- A write-off note without a write-off is a half fact. The actor may be null because a deleted user
  -- clears it, and the note is optional, so only the note is tied to the stamp.
  constraint invoices_write_off_note_needs_write_off check (
    write_off_note is null or written_off_at is not null
  ),
  constraint invoices_replacement_kind_needs_predecessor check (
    (predecessor_invoice_id is null) = (replacement_kind is null)
  ),
  constraint invoices_not_its_own_predecessor check (
    predecessor_invoice_id is null or predecessor_invoice_id <> id
  ),
  -- Replacement is one atomic fact: the moment, the successor, and the label frozen at that moment.
  constraint invoices_replaced_facts_complete check (
    (replaced_at is null) = (replaced_by_invoice_id is null)
    and (replaced_at is null) = (frozen_status_label is null)
  ),
  constraint invoices_discount_name_check check (
    discount_name is null or char_length(trim(discount_name)) between 1 and 80
  ),
  constraint invoices_discount_check check (
    (discount_type is null and discount_value is null and discount_name is null)
    or (
      discount_type in ('fixed', 'percentage')
      and discount_value between 0
        and case when discount_type = 'percentage' then 10000 else 9000000000000000000 end
      and discount_name is not null
    )
  ),
  constraint invoices_tax_name_check check (
    tax_name is null or char_length(trim(tax_name)) between 1 and 80
  ),
  constraint invoices_tax_check check (
    tax_rate_basis_points between 0 and 10000
    and ((tax_rate_basis_points = 0 and tax_name is null) or tax_name is not null)
  ),
  -- A tax rate later deleted or deactivated never invalidates a bill that already froze its name and
  -- percentage, exactly as a quote version and a job already do.
  constraint invoices_tax_source_consistency check (
    case tax_source
      when 'not_configured' then tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null
      when 'no_tax' then tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null
      when 'custom' then tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is null
      when 'saved_rate' then tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is not null
      else
        (tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is not null)
        or (tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null)
    end
  ),
  constraint invoices_discount_within_subtotal check (discount_minor <= subtotal_minor)
);

comment on table public.invoices is
  'The customer''s bill: a frozen snapshot of what is charged, not a view of live work. Members read this '
  'table and never write it; every row is created and changed by a checked command function. The six '
  'contract statuses are derived from the issue, recognition, closure, void and replacement facts stored '
  'here plus the money applied to it, so no status column can drift out of date.';

comment on column public.invoices.root_invoice_id is
  'The first invoice in this correction/rebill chain, set to the invoice''s own id when it starts one. '
  'Source claims attach here, which is what stops a replacement from becoming a second way to bill the '
  'same work.';

comment on column public.invoices.recognized_at is
  'When a draft became a settled bill through full payment (contract decision D1). It is not an issue date '
  'and creates no delivery or communication fact.';

-- The list page's default view and its keyset paging, newest first.
create index invoices_organization_created_idx
  on public.invoices(organization_id, created_at desc, id);

-- Everything a client owes, for the client record and the account balance sum.
create index invoices_client_idx
  on public.invoices(organization_id, client_id, created_at desc, id);

-- The receivables index: issued bills that are still the active one in their chain, in due-date order. This
-- is what answers "what is past due" and what payment reminders select from, and it stays the size of the
-- open ledger rather than the size of history.
create index invoices_receivable_due_idx
  on public.invoices(organization_id, due_date, id)
  where issued_at is not null and voided_at is null and replaced_at is null;

-- Drafts awaiting review, for the list filter and for batch review.
create index invoices_draft_idx
  on public.invoices(organization_id, created_at desc, id)
  where issued_at is null and recognized_at is null and voided_at is null;

-- One invoice may be replaced by exactly one successor. The loser of a race to correct the same bill fails
-- on this index rather than branching the chain into two active receivables.
create unique index invoices_predecessor_unique_idx
  on public.invoices(organization_id, predecessor_invoice_id)
  where predecessor_invoice_id is not null;

create index invoices_root_idx
  on public.invoices(organization_id, root_invoice_id, created_at, id);

create index invoices_payment_term_idx
  on public.invoices(organization_id, payment_term_id)
  where payment_term_id is not null;

create index invoices_tax_rate_idx
  on public.invoices(organization_id, tax_rate_id)
  where tax_rate_id is not null;

-- The two actor columns worth an index of their own: every invoice has a creator and most have an issuer,
-- so those are the two set-null lookups a user deletion would otherwise scan the whole table for. The
-- remaining actor columns are set on a small minority of rows and are left to that rare scan.
create index invoices_created_by_idx on public.invoices(created_by) where created_by is not null;
create index invoices_issued_by_idx on public.invoices(issued_by) where issued_by is not null;

create trigger invoices_set_updated_at
before update on public.invoices
for each row execute function public.set_updated_at();

-- 3. What can never change --------------------------------------------------------------------------------------

-- A new chain points at itself. Doing it in a trigger rather than in the create command means a future
-- command, a fixup script or a mistake in a migration cannot leave a row without a root.
create or replace function private.invoices_set_root()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.root_invoice_id is null then
    new.root_invoice_id := new.id;
  end if;
  return new;
end;
$$;

revoke all on function private.invoices_set_root() from public;
revoke execute on function private.invoices_set_root() from anon, authenticated;

create trigger invoices_set_root
before insert on public.invoices
for each row execute function private.invoices_set_root();

-- The identity guards. These sit under every command rather than inside one, because the whole value of a
-- snapshot is that no code path anywhere can rewrite it.
create or replace function private.invoices_guard_identity()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'An invoice cannot be moved to another organization.' using errcode = 'check_violation';
  end if;
  if new.client_id is distinct from old.client_id then
    raise exception 'An invoice cannot be moved to another client.' using errcode = 'check_violation';
  end if;
  if new.invoice_number is distinct from old.invoice_number then
    raise exception 'An invoice number cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.root_invoice_id is distinct from old.root_invoice_id
     or new.predecessor_invoice_id is distinct from old.predecessor_invoice_id then
    raise exception 'An invoice cannot be moved to another correction chain.'
      using errcode = 'check_violation';
  end if;
  -- The currency the customer was billed in. Changing it would relabel amounts that were already agreed.
  if new.currency_code is distinct from old.currency_code then
    raise exception 'An invoice''s currency cannot be changed.' using errcode = 'check_violation';
  end if;
  -- Issue and recognition happen once. Un-issuing would leave a customer holding a bill the product denies
  -- having sent.
  if old.issued_at is not null and new.issued_at is distinct from old.issued_at then
    raise exception 'An invoice that has been issued cannot be un-issued.' using errcode = 'check_violation';
  end if;
  if old.recognized_at is not null and new.recognized_at is distinct from old.recognized_at then
    raise exception 'A settled invoice cannot be un-settled.' using errcode = 'check_violation';
  end if;
  -- Void is irreversible, and a voided bill is immutable in every other respect too. The only change it
  -- still accepts is being marked as replaced by an explicit rebill.
  if old.voided_at is not null then
    if new.voided_at is distinct from old.voided_at then
      raise exception 'A voided invoice cannot be reopened.' using errcode = 'check_violation';
    end if;
    if to_jsonb(new) - 'replaced_at' - 'replaced_by_invoice_id' - 'frozen_status_label' - 'updated_at'
       is distinct from
       to_jsonb(old) - 'replaced_at' - 'replaced_by_invoice_id' - 'frozen_status_label' - 'updated_at' then
      raise exception 'A voided invoice cannot be changed.' using errcode = 'check_violation';
    end if;
  end if;
  -- A replaced bill is history. Its frozen label never moves again.
  if old.replaced_at is not null then
    if new.replaced_at is distinct from old.replaced_at
       or new.replaced_by_invoice_id is distinct from old.replaced_by_invoice_id
       or new.frozen_status_label is distinct from old.frozen_status_label then
      raise exception 'A replaced invoice''s history cannot be rewritten.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.invoices_guard_identity() from public;
revoke execute on function private.invoices_guard_identity() from anon, authenticated;

create trigger invoices_guard_identity
before update on public.invoices
for each row execute function private.invoices_guard_identity();

alter table public.invoices enable row level security;

create policy "permitted members can view invoices"
on public.invoices for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'invoices.view')
);

revoke all on public.invoices from anon, authenticated;

-- Money is not in this grant, exactly as it is not in the grant on jobs. Someone who may see that a bill
-- exists is not automatically someone who may see what the customer was charged; the amounts come back
-- through public.invoice_money, which checks invoices.view_price.
grant select (
  id, organization_id, client_id, invoice_number, subject, currency_code,
  customer_snapshot, billing_address_snapshot, service_properties, document_frozen_at,
  payment_term_id, payment_term_snapshot, due_date_source, issue_date, due_date,
  issued_at, issued_by, issue_method, recognized_at, marked_received_at, marked_received_by,
  written_off_at, written_off_by, write_off_note, voided_at, voided_by, void_reason, void_note,
  predecessor_invoice_id, root_invoice_id, replacement_kind, replaced_at, replaced_by_invoice_id,
  frozen_status_label, tax_source, tax_name, revision, created_by, created_at, updated_at
) on public.invoices to authenticated;

-- 4. Invoice lines --------------------------------------------------------------------------------------------

-- The same vocabulary as job_line_items, minus two things and plus two things. Gone: cost and markup, which
-- are internal to a job and have no place on a customer's bill, and the quote's optional/recommended selling
-- machinery. Added: the service date the line covers, and, for a progress invoice, the amount the payment
-- schedule fixed for that installment.
create table public.invoice_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  position integer not null check (position >= 0),
  -- Notes about where the line came from, never foreign keys: a catalog item or a job line disappearing must
  -- not reach into a bill that has already been sent.
  source_catalog_item_id uuid,
  source_job_id uuid,
  source_job_line_id uuid,
  service_date date,
  line_kind text not null default 'priced' check (line_kind in ('priced', 'text', 'heading')),
  category text,
  name text not null check (char_length(trim(name)) between 2 and 160),
  description text check (description is null or char_length(description) <= 2000),
  unit_label text check (unit_label is null or char_length(trim(unit_label)) between 1 and 24),
  quantity numeric(12, 3),
  unit_price_minor bigint,
  is_taxable boolean not null default true,
  -- What the job's payment schedule fixed for this installment, kept beside the line so a progress bill can
  -- show that its amount is not something an editor chose.
  progress_original_amount_minor bigint
    check (progress_original_amount_minor is null
      or progress_original_amount_minor between 0 and 1000000000000),
  line_total_minor bigint
    generated always as (public.pricing_line_total_minor(quantity, unit_price_minor)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoice_lines_organization_id_unique unique (organization_id, id),
  constraint invoice_lines_invoice_organization_fk foreign key (organization_id, invoice_id)
    references public.invoices(organization_id, id) on delete cascade,
  constraint invoice_lines_shape_check check (
    (
      line_kind = 'priced'
      and category in ('product', 'service')
      and quantity > 0 and quantity <= 1000000
      and unit_price_minor between 0 and 1000000000000
    )
    or (
      line_kind in ('text', 'heading')
      and category is null
      and quantity is null
      and unit_price_minor is null
      and not is_taxable
      and progress_original_amount_minor is null
    )
  )
);

comment on table public.invoice_lines is
  'What the customer is being charged for, copied onto the invoice at creation. Deleted with its invoice '
  'only while that invoice is still a deletable draft; an issued bill is retained through void, so its '
  'lines are retained with it.';

create index invoice_lines_invoice_idx
  on public.invoice_lines(organization_id, invoice_id, position, id);

-- The one lookup 3c needs to prove a job line was billed once, and the index behind it.
create index invoice_lines_source_job_idx
  on public.invoice_lines(organization_id, source_job_id, invoice_id)
  where source_job_id is not null;

create trigger invoice_lines_set_updated_at
before update on public.invoice_lines
for each row execute function public.set_updated_at();

-- A hundred lines per invoice, matching the quote and job limits the scope is copied from, and matching the
-- per-invoice bound the approved design measures against. One statement-level check, so a bulk copy costs
-- one count rather than one per row.
create or replace function private.invoice_lines_enforce_limit()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  offending uuid;
begin
  select line.invoice_id into offending
  from public.invoice_lines as line
  where line.invoice_id in (select distinct inserted.invoice_id from inserted)
  group by line.invoice_id
  having count(*) > 100
  limit 1;

  if offending is not null then
    raise exception 'An invoice can hold up to 100 lines.' using errcode = '54000';
  end if;

  return null;
end;
$$;

revoke all on function private.invoice_lines_enforce_limit() from public;
revoke execute on function private.invoice_lines_enforce_limit() from anon, authenticated;

create trigger invoice_lines_enforce_limit
after insert on public.invoice_lines
referencing new table as inserted
for each statement execute function private.invoice_lines_enforce_limit();

alter table public.invoice_lines enable row level security;

create policy "permitted members can view invoice lines"
on public.invoice_lines for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'invoices.view')
);

revoke all on public.invoice_lines from anon, authenticated;

grant select (
  id, organization_id, invoice_id, position, source_catalog_item_id, source_job_id, source_job_line_id,
  service_date, line_kind, category, name, description, unit_label, quantity, is_taxable,
  created_at, updated_at
) on public.invoice_lines to authenticated;

-- 5. One function owns invoice arithmetic ------------------------------------------------------------------------

-- Deliberately identical in shape to private.calculate_job and private.calculate_quote_version: per line
-- exclusive tax after a proportionally allocated discount, one rounding pass, largest-remainder spreading so
-- the allocated parts add back to the whole. Cost, profit and margin are absent because a bill has none.
create or replace function private.calculate_invoice(target_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invoice_row public.invoices;
  line_subtotal numeric := 0;
  non_taxable_subtotal numeric := 0;
  taxable_subtotal numeric := 0;
  discount_amount numeric := 0;
  non_taxable_discount numeric := 0;
  taxable_discount numeric := 0;
  tax_amount numeric := 0;
  total_amount numeric := 0;
  line_count integer := 0;
  line_result jsonb := '[]'::jsonb;
begin
  select * into invoice_row from public.invoices where id = target_invoice_id;
  if invoice_row.id is null then
    raise exception 'That invoice was not found.' using errcode = 'no_data_found';
  end if;

  select coalesce(sum(line_total_minor), 0),
         coalesce(sum(line_total_minor) filter (where not is_taxable), 0),
         coalesce(sum(line_total_minor) filter (where is_taxable), 0),
         count(*)
  into line_subtotal, non_taxable_subtotal, taxable_subtotal, line_count
  from public.invoice_lines
  where organization_id = invoice_row.organization_id
    and invoice_id = invoice_row.id
    and line_kind = 'priced';

  if line_subtotal > 1000000000000 then
    raise exception 'That invoice value is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  if invoice_row.discount_type = 'fixed' then
    discount_amount := least(invoice_row.discount_value, line_subtotal);
  elsif invoice_row.discount_type = 'percentage' then
    discount_amount := round(line_subtotal * invoice_row.discount_value / 10000);
  end if;
  non_taxable_discount := least(discount_amount, non_taxable_subtotal);
  taxable_discount := discount_amount - non_taxable_discount;

  with priced as (
    select id, position, is_taxable, line_total_minor
    from public.invoice_lines
    where organization_id = invoice_row.organization_id
      and invoice_id = invoice_row.id
      and line_kind = 'priced'
  ),
  shared as (
    select priced.*,
      case when priced.is_taxable then taxable_subtotal else non_taxable_subtotal end as group_total,
      case when priced.is_taxable then taxable_discount else non_taxable_discount end as group_discount,
      row_number() over (partition by priced.is_taxable order by priced.position, priced.id) as group_rank
    from priced
  ),
  rounded as (
    select shared.*,
      case when shared.group_total = 0 or shared.group_discount = 0 then 0
        else floor(shared.group_discount * shared.line_total_minor / shared.group_total)
      end as raw_allocation
    from shared
  ),
  spread as (
    select rounded.*,
      rounded.group_discount - sum(rounded.raw_allocation) over (partition by rounded.is_taxable)
        as group_remainder
    from rounded
  ),
  allocated as (
    select spread.id, spread.position, spread.is_taxable, spread.line_total_minor,
      spread.raw_allocation + case when spread.group_rank <= spread.group_remainder then 1 else 0 end
        as line_discount
    from spread
  ),
  taxed as (
    select allocated.*,
      allocated.line_total_minor - allocated.line_discount as net_amount,
      case when allocated.is_taxable
        then round((allocated.line_total_minor - allocated.line_discount)
          * invoice_row.tax_rate_basis_points / 10000)
        else 0
      end as line_tax
    from allocated
  )
  select coalesce(sum(line_tax), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'line_id', id,
      'gross_minor', line_total_minor,
      'discount_minor', line_discount::bigint,
      'net_minor', net_amount::bigint,
      'tax_minor', line_tax::bigint,
      'total_minor', (net_amount + line_tax)::bigint
    ) order by position, id), '[]'::jsonb)
  into tax_amount, line_result
  from taxed;

  total_amount := line_subtotal - discount_amount + tax_amount;
  if total_amount > 1000000000000 then
    raise exception 'That invoice total is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  return jsonb_build_object(
    'invoice_id', invoice_row.id,
    'line_count', line_count,
    'subtotal_minor', line_subtotal::bigint,
    'discount_minor', discount_amount::bigint,
    'tax_minor', tax_amount::bigint,
    'total_minor', total_amount::bigint,
    'lines', line_result
  );
end;
$$;

comment on function private.calculate_invoice(uuid) is
  'The only invoice arithmetic in the product, and the same rules as private.calculate_job: proportional '
  'discount allocation with largest-remainder spreading, then per-line exclusive tax. No route, screen or '
  'document recomputes this.';

revoke all on function private.calculate_invoice(uuid) from public;
revoke execute on function private.calculate_invoice(uuid) from anon, authenticated;

-- Calculating and storing are one step for every command that changes what a bill charges, so they are one
-- function. Nothing writes the money columns by hand.
create or replace function private.store_invoice_money(target_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  calculated jsonb := private.calculate_invoice(target_invoice_id);
begin
  update public.invoices
  set subtotal_minor = (calculated->>'subtotal_minor')::bigint,
      discount_minor = (calculated->>'discount_minor')::bigint,
      tax_minor = (calculated->>'tax_minor')::bigint,
      total_minor = (calculated->>'total_minor')::bigint
  where id = target_invoice_id;

  return calculated;
end;
$$;

revoke all on function private.store_invoice_money(uuid) from public;
revoke execute on function private.store_invoice_money(uuid) from anon, authenticated;

-- The gated reader that gives the money back. One permission check for the whole call rather than one per
-- row, the same shape as public.job_money and public.quote_version_money.
create or replace function public.invoice_money(target_invoice_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_invoice_ids is null or cardinality(target_invoice_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct invoice.organization_id) into organizations
  from public.invoices as invoice
  where invoice.id = any(target_invoice_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those invoices do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(org, caller, 'invoices.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(invoice.id::text, jsonb_build_object(
      'currency_code', invoice.currency_code,
      'subtotal_minor', invoice.subtotal_minor,
      'discount_minor', invoice.discount_minor,
      'discount_name', invoice.discount_name,
      'discount_type', invoice.discount_type,
      'discount_value', invoice.discount_value,
      'tax_minor', invoice.tax_minor,
      'tax_rate_basis_points', invoice.tax_rate_basis_points,
      'total_minor', invoice.total_minor
    )), '{}'::jsonb)
  into answer
  from public.invoices as invoice
  where invoice.organization_id = org
    and invoice.id = any(target_invoice_ids);

  return answer;
end;
$$;

revoke all on function public.invoice_money(uuid[]) from public;
revoke execute on function public.invoice_money(uuid[]) from anon;
grant execute on function public.invoice_money(uuid[]) to authenticated;

-- 6. Invoice history --------------------------------------------------------------------------------------------

-- Append-only, and deliberately not a child of the invoice. A draft may be deleted; what happened to it may
-- not disappear with it. So the invoice reference is a plain column carrying the number and client alongside
-- it, and no cascade can erase a financial fact.
create table public.invoice_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  -- Copied, not joined: a deleted draft's history still reads as "Invoice #14" a year later.
  invoice_number integer not null check (invoice_number >= 1),
  client_id uuid,
  event_type text not null check (char_length(trim(event_type)) between 2 and 64),
  actor_id uuid references auth.users(id) on delete set null,
  -- The revision the invoice was at when this happened, so history and the document line up.
  invoice_revision integer check (invoice_revision is null or invoice_revision >= 0),
  reason text check (reason is null or char_length(reason) <= 2000),
  -- The complete document as it stood before a permitted edit to an already-issued bill. Null on every
  -- other event; this is the one place the prior version of a frozen document is kept.
  prior_document_snapshot jsonb
    check (prior_document_snapshot is null or jsonb_typeof(prior_document_snapshot) = 'object'),
  -- Redacted metadata only: counts, reasons and ids. Never customer content.
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  -- True when this row carries amounts. The policy below then also demands invoices.view_price, so money
  -- cannot leak into the activity feed of somebody who may not see prices.
  price_sensitive boolean not null default false,
  created_at timestamptz not null default now(),
  constraint invoice_events_organization_id_unique unique (organization_id, id),
  -- A prior document snapshot is money-bearing by definition.
  constraint invoice_events_snapshot_is_price_sensitive check (
    prior_document_snapshot is null or price_sensitive
  )
);

comment on table public.invoice_events is
  'Invoice history. Append-only in privilege as well as in practice: UPDATE, DELETE and TRUNCATE are '
  'revoked from every application role and refused by triggers, including for SECURITY DEFINER commands. '
  'Not a child row -- deleting a draft invoice never deletes what happened to it.';

create index invoice_events_invoice_idx
  on public.invoice_events(organization_id, invoice_id, created_at desc, id);
create index invoice_events_client_idx
  on public.invoice_events(organization_id, client_id, created_at desc, id)
  where client_id is not null;
create index invoice_events_actor_idx on public.invoice_events(actor_id) where actor_id is not null;

-- Append-only, enforced by the database rather than by the discipline of the commands. The trigger catches
-- what a grant cannot: a SECURITY DEFINER command running as the table owner.
create or replace function private.invoice_events_are_append_only()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Invoice history is append-only.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.invoice_events_are_append_only() from public;
revoke execute on function private.invoice_events_are_append_only() from anon, authenticated;

create trigger invoice_events_no_update_or_delete
before update or delete on public.invoice_events
for each row execute function private.invoice_events_are_append_only();

create trigger invoice_events_no_truncate
before truncate on public.invoice_events
for each statement execute function private.invoice_events_are_append_only();

alter table public.invoice_events enable row level security;

create policy "permitted members can view invoice history"
on public.invoice_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'invoices.view')
  and (not price_sensitive or private.has_permission(organization_id, 'invoices.view_price'))
);

revoke all on public.invoice_events from anon, authenticated;
grant select on public.invoice_events to authenticated;

-- Supabase's default privileges hand service_role everything on a new public table. It keeps exactly what a
-- server-side command needs and nothing that could rewrite history.
revoke all on public.invoice_events from service_role;
grant select, insert on public.invoice_events to service_role;

-- The one writer, so no command has to remember which columns history needs.
create or replace function private.record_invoice_event(
  target_organization_id uuid,
  target_invoice_id uuid,
  target_invoice_number integer,
  target_client_id uuid,
  new_event_type text,
  actor uuid,
  new_invoice_revision integer default null,
  new_reason text default null,
  new_metadata jsonb default '{}'::jsonb,
  new_price_sensitive boolean default false,
  new_prior_document_snapshot jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  event_id uuid;
begin
  insert into public.invoice_events (
    organization_id, invoice_id, invoice_number, client_id, event_type, actor_id,
    invoice_revision, reason, metadata, price_sensitive, prior_document_snapshot
  ) values (
    target_organization_id, target_invoice_id, target_invoice_number, target_client_id,
    new_event_type, actor, new_invoice_revision, nullif(trim(coalesce(new_reason, '')), ''),
    coalesce(new_metadata, '{}'::jsonb),
    coalesce(new_price_sensitive, false) or new_prior_document_snapshot is not null,
    new_prior_document_snapshot
  )
  returning id into event_id;

  return event_id;
end;
$$;

revoke all on function private.record_invoice_event(
  uuid, uuid, integer, uuid, text, uuid, integer, text, jsonb, boolean, jsonb
) from public;
revoke execute on function private.record_invoice_event(
  uuid, uuid, integer, uuid, text, uuid, integer, text, jsonb, boolean, jsonb
) from anon, authenticated;

-- 7. Retry protection -----------------------------------------------------------------------------------------

-- In the private schema on purpose. This ledger holds request fingerprints and command results, which are
-- neither history nor anything a screen should be able to read; the private schema is not exposed through
-- PostgREST and has no grants to anon or authenticated, so the only way in is through the two functions
-- below, which only a command function may call.
create table private.invoice_command_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  action text not null check (char_length(trim(action)) between 2 and 64),
  idempotency_key text not null check (char_length(trim(idempotency_key)) >= 8),
  request_hash text not null check (char_length(trim(request_hash)) >= 1),
  -- Who was authorised the first time. Kept for inspection; every replay is authorised again on its own.
  actor_id uuid references auth.users(id) on delete set null,
  -- Filled in the same transaction that does the work, so a receipt only ever carries a committed result.
  -- A rollback leaves neither the receipt nor the changes.
  result jsonb,
  created_at timestamptz not null default now(),
  constraint invoice_command_receipts_unique unique (organization_id, action, idempotency_key)
);

comment on table private.invoice_command_receipts is
  'Idempotency ledger for invoice and payment commands, including client-level and multi-invoice ones that '
  'have no invoice parent. Private: fingerprints and results never reach a history projection, an activity '
  'feed or Client Hub. A replay returns the stored result and never recreates work that was later deleted.';

create index invoice_command_receipts_organization_idx
  on private.invoice_command_receipts(organization_id, created_at desc, id);
create index invoice_command_receipts_actor_idx
  on private.invoice_command_receipts(actor_id) where actor_id is not null;

-- Claim the key before doing any work. "on conflict do nothing" waits for a racing transaction to commit and
-- then returns no row, so the loser reads the winner's committed result instead of doing the work twice.
-- Returns null when this call owns the command and should proceed.
create or replace function private.begin_invoice_command(
  target_organization_id uuid,
  new_action text,
  new_idempotency_key text,
  new_request_hash text,
  actor uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed uuid;
  existing private.invoice_command_receipts;
begin
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  insert into private.invoice_command_receipts
    (organization_id, action, idempotency_key, request_hash, actor_id)
  values (target_organization_id, new_action, new_idempotency_key, new_request_hash, actor)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into claimed;

  if claimed is not null then
    return null;
  end if;

  select * into existing
  from private.invoice_command_receipts
  where organization_id = target_organization_id
    and action = new_action
    and idempotency_key = new_idempotency_key;

  -- Same key, different request. Returning the first result would be a lie about what this call did.
  if existing.request_hash is distinct from new_request_hash then
    raise exception 'That action was already started with different details.' using errcode = 'P0409';
  end if;

  return coalesce(existing.result, '{}'::jsonb) || jsonb_build_object('applied', false);
end;
$$;

revoke all on function private.begin_invoice_command(uuid, text, text, text, uuid) from public;
revoke execute on function private.begin_invoice_command(uuid, text, text, text, uuid)
  from anon, authenticated;

create or replace function private.complete_invoice_command(
  target_organization_id uuid,
  new_action text,
  new_idempotency_key text,
  new_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update private.invoice_command_receipts
  set result = coalesce(new_result, '{}'::jsonb)
  where organization_id = target_organization_id
    and action = new_action
    and idempotency_key = new_idempotency_key;

  if not found then
    raise exception 'That command receipt is missing.' using errcode = 'no_data_found';
  end if;

  return coalesce(new_result, '{}'::jsonb) || jsonb_build_object('applied', true);
end;
$$;

revoke all on function private.complete_invoice_command(uuid, text, text, jsonb) from public;
revoke execute on function private.complete_invoice_command(uuid, text, text, jsonb)
  from anon, authenticated;
