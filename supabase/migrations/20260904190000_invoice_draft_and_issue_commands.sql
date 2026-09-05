-- Invoices Part 3a, file 3 of 3: the commands that make a bill, change it, and issue it.
--
-- File 1 built what an invoice reads before it exists; file 2 built the bill, its lines, its arithmetic and
-- its history. This file is the only way any of that changes. Every command here checks permission, takes
-- its locks in the same order, bumps the revision the caller sent, writes history, and returns what the
-- screen needs. Nothing else in the product may write an invoice row.
--
-- Two rules run through all of it. A bill that has been issued -- or settled while still a draft -- keeps a
-- complete copy of its previous document in history whenever a permitted edit changes it, so the version the
-- customer received is never lost. And the organization's currency locks the moment a customer can see a
-- bill, joining the quote rule that already existed.
--
-- Deliberately not here: recording money, allocating it, void and bad debt. Those depend on the money ledger
-- and are built and verified together in 3b. The seams they need are defined here so the rules that belong
-- to a draft -- refusing to delete a draft that holds money, and recognising a draft that has been paid in
-- full -- are wired now rather than bolted on later.

-- 1. The currency lock, in one place ---------------------------------------------------------------------------

-- The lock predicate existed twice: once in the settings reader and once inline in the business-profile save.
-- Invoices add two more facts to it, so it becomes one function that every reader and the guard below share.
--
-- It reads history, not live rows, on purpose. Deleting a draft, voiding a bill or refunding a payment does
-- not unlock the currency: the customer still saw an amount in it, and that is what the lock protects.
create or replace function private.organization_currency_lock_reason(target_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when exists (
      select 1 from public.quotes
      where organization_id = target_organization_id
        and (current_published_version_id is not null or sent_at is not null)
    ) then 'quote_sent'
    when exists (
      select 1 from public.invoice_events
      where organization_id = target_organization_id
        and event_type in ('invoice.issued', 'invoice.recognized')
    ) then 'invoice_issued'
  end;
$$;

comment on function private.organization_currency_lock_reason(uuid) is
  'Why this organization''s currency is locked, or null when it is still free to change. The one predicate '
  'behind the settings reader, the business-profile save and the guard on organization_settings.';

revoke all on function private.organization_currency_lock_reason(uuid) from public;
revoke execute on function private.organization_currency_lock_reason(uuid) from anon, authenticated;

-- Keeps the lock question an index probe rather than a scan of an organization's whole invoice history.
create index invoice_events_currency_lock_idx
  on public.invoice_events(organization_id)
  where event_type in ('invoice.issued', 'invoice.recognized');

create or replace function public.organization_currency_is_locked(target_organization_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.has_permission(target_organization_id, 'settings.business.view') then
    raise exception 'You do not have access to business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  return private.organization_currency_lock_reason(target_organization_id) is not null;
end;
$$;

revoke all on function public.organization_currency_is_locked(uuid) from public;
revoke execute on function public.organization_currency_is_locked(uuid) from anon;
grant execute on function public.organization_currency_is_locked(uuid) to authenticated;

-- The backstop. public.save_organization_business_profile already refuses a currency change after a quote
-- was sent, and it keeps that friendlier message; this trigger is what makes the rule true for every other
-- writer, including a future settings command that forgets it. Both the settings save and the invoice
-- commands below lock the settings row before doing anything else, so a currency change racing a first
-- issue is decided by whichever gets the lock, never by both winning.
create or replace function private.organization_settings_guard_currency()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  reason text;
begin
  if new.currency_code is distinct from old.currency_code then
    reason := private.organization_currency_lock_reason(new.organization_id);
    if reason = 'quote_sent' then
      raise exception 'Currency cannot change once a Quote has been sent to a customer.'
        using errcode = 'check_violation';
    elsif reason is not null then
      raise exception 'Currency cannot change once an invoice has been issued or paid.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.organization_settings_guard_currency() from public;
revoke execute on function private.organization_settings_guard_currency() from anon, authenticated;

create trigger organization_settings_guard_currency
before update on public.organization_settings
for each row execute function private.organization_settings_guard_currency();

-- One correction to file 2 before anything can be deleted. root_invoice_id points at the invoice's own id
-- when it starts a chain, and ON DELETE RESTRICT is checked without noticing that the referencing row is the
-- row being deleted -- so it would refuse to delete any draft at all. NO ACTION asks the same question at the
-- end of the statement, when a self-referencing row has already gone, and still refuses to delete an invoice
-- some other invoice's chain points at.
alter table public.invoices drop constraint invoices_root_fk;
alter table public.invoices add constraint invoices_root_fk
  foreign key (organization_id, root_invoice_id)
  references public.invoices(organization_id, id);

-- And the currency rule relaxes by exactly one case: a draft nobody has been given may be re-stamped by the
-- explicit refresh command below. Once the document is frozen the currency is part of what the customer was
-- told, and nothing may change it.
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
  if new.currency_code is distinct from old.currency_code and old.document_frozen_at is not null then
    raise exception 'An issued invoice''s currency cannot be changed.' using errcode = 'check_violation';
  end if;
  if old.issued_at is not null and new.issued_at is distinct from old.issued_at then
    raise exception 'An invoice that has been issued cannot be un-issued.' using errcode = 'check_violation';
  end if;
  if old.recognized_at is not null and new.recognized_at is distinct from old.recognized_at then
    raise exception 'A settled invoice cannot be un-settled.' using errcode = 'check_violation';
  end if;
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

-- 2. Snapshots ----------------------------------------------------------------------------------------------

-- Who the bill is addressed to. Contact details are not here: recipients belong to delivery in Part 6, and
-- copying an address book onto every bill would be a snapshot of something nobody agreed to.
create or replace function private.build_invoice_customer_snapshot(
  target_organization_id uuid,
  target_client_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  client_row public.clients;
begin
  select * into client_row
  from public.clients
  where organization_id = target_organization_id and id = target_client_id;
  if not found then
    raise exception 'That client could not be found.' using errcode = 'P0404';
  end if;

  return jsonb_build_object(
    'client_id', client_row.id,
    'display_name', client_row.display_name,
    'company_name', client_row.company_name,
    'first_name', client_row.first_name,
    'last_name', client_row.last_name,
    'client_type', client_row.client_type
  );
end;
$$;

revoke all on function private.build_invoice_customer_snapshot(uuid, uuid) from public;
revoke execute on function private.build_invoice_customer_snapshot(uuid, uuid) from anon, authenticated;

-- Every service address the bill covers, copied in full. One invoice may cover several jobs at several
-- properties, so this is an array and a source claim points at an entry in it. Historical rendering never
-- goes back to the live property.
create or replace function private.build_invoice_service_properties(
  target_organization_id uuid,
  target_client_id uuid,
  property_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  built jsonb;
  wanted integer := coalesce(cardinality(property_ids), 0);
  found_count integer;
begin
  if wanted = 0 then
    return '[]'::jsonb;
  end if;

  select jsonb_agg(jsonb_build_object(
      'property_id', property.id,
      'job_id', null,
      'label', property.label,
      'address_line1', property.address_line1,
      'address_line2', property.address_line2,
      'city', property.city,
      'state_region', property.state_region,
      'postal_code', property.postal_code,
      'country', property.country
    ) order by ordering.position),
    count(*)
  into built, found_count
  from unnest(property_ids) with ordinality as ordering(property_id, position)
  join public.properties as property
    on property.id = ordering.property_id
   and property.organization_id = target_organization_id
   and property.client_id = target_client_id
   and property.deleted_at is null;

  if coalesce(found_count, 0) <> wanted then
    raise exception 'One of those service properties does not belong to this client.'
      using errcode = 'check_violation';
  end if;

  return coalesce(built, '[]'::jsonb);
end;
$$;

revoke all on function private.build_invoice_service_properties(uuid, uuid, uuid[]) from public;
revoke execute on function private.build_invoice_service_properties(uuid, uuid, uuid[])
  from anon, authenticated;

-- The whole document as one object: everything the customer would see, plus the amounts. This is what gets
-- kept in history before a permitted edit to an already-issued bill, which is the only way the previous
-- version of a frozen document survives.
create or replace function private.invoice_document_snapshot(target_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  invoice_row public.invoices;
begin
  select * into invoice_row from public.invoices where id = target_invoice_id;
  if not found then
    raise exception 'That invoice was not found.' using errcode = 'P0404';
  end if;

  return jsonb_build_object(
    'invoice_id', invoice_row.id,
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
    'discount', jsonb_build_object(
      'name', invoice_row.discount_name,
      'type', invoice_row.discount_type,
      'value', invoice_row.discount_value
    ),
    'tax', jsonb_build_object(
      'source', invoice_row.tax_source,
      'name', invoice_row.tax_name,
      'rate_basis_points', invoice_row.tax_rate_basis_points
    ),
    'totals', jsonb_build_object(
      'subtotal_minor', invoice_row.subtotal_minor,
      'discount_minor', invoice_row.discount_minor,
      'tax_minor', invoice_row.tax_minor,
      'total_minor', invoice_row.total_minor
    ),
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'line_id', line.id,
        'position', line.position,
        'line_kind', line.line_kind,
        'category', line.category,
        'name', line.name,
        'description', line.description,
        'unit_label', line.unit_label,
        'quantity', line.quantity,
        'unit_price_minor', line.unit_price_minor,
        'is_taxable', line.is_taxable,
        'service_date', line.service_date,
        'line_total_minor', line.line_total_minor
      ) order by line.position, line.id), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = invoice_row.organization_id
        and line.invoice_id = invoice_row.id
    )
  );
end;
$$;

revoke all on function private.invoice_document_snapshot(uuid) from public;
revoke execute on function private.invoice_document_snapshot(uuid) from anon, authenticated;

-- 3. The shared entry check for every edit -----------------------------------------------------------------------

-- Permission, row lock, and a stale revision refused, exactly as private.lock_job_for_edit does for jobs.
-- It also refuses the two states no edit may touch: a voided bill and one that has been replaced.
create or replace function private.lock_invoice_for_edit(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  required_permission text default 'invoices.edit'
)
returns public.invoices
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to change an invoice.'
      using errcode = 'insufficient_privilege';
  end if;
  -- Issuing and deleting are their own permissions, so each command says which one this lock is for rather
  -- than making everybody who may delete a draft also able to edit one.
  if not private.member_has_permission(target_organization_id, caller, required_permission) then
    raise exception 'You do not have access to change this invoice.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id
  for update;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;

  if invoice_row.voided_at is not null then
    raise exception 'A voided invoice cannot be changed.' using errcode = 'check_violation';
  end if;
  if invoice_row.replaced_at is not null then
    raise exception 'This invoice was replaced. Change the invoice that replaced it.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.revision is distinct from expected_revision then
    raise exception 'Someone else changed this invoice. Reload to see the latest.'
      using errcode = 'P0409';
  end if;

  return invoice_row;
end;
$$;

comment on function private.lock_invoice_for_edit(uuid, uuid, integer, text) is
  'Shared entry check for every invoice edit: the named permission, a row lock, voided/replaced refused, '
  'and a stale revision refused as P0409.';

revoke all on function private.lock_invoice_for_edit(uuid, uuid, integer, text) from public;
revoke execute on function private.lock_invoice_for_edit(uuid, uuid, integer, text)
  from anon, authenticated;

-- Anything that touches money also needs price visibility. Header wording does not; amounts do.
create or replace function private.require_invoice_price_access(target_organization_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.member_has_permission(target_organization_id, (select auth.uid()), 'invoices.view_price')
  then
    raise exception 'You do not have access to invoice amounts.' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

revoke all on function private.require_invoice_price_access(uuid) from public;
revoke execute on function private.require_invoice_price_access(uuid) from anon, authenticated;

-- Called by every edit before it changes anything. On a draft it does nothing; on a bill the customer has
-- already been given, it puts the complete previous document into history first.
create or replace function private.retain_prior_invoice_document(
  invoice_row public.invoices,
  actor uuid,
  change_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if invoice_row.document_frozen_at is null then
    return;
  end if;

  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.document_edited', actor, invoice_row.revision, change_reason, '{}'::jsonb, true,
    private.invoice_document_snapshot(invoice_row.id)
  );
end;
$$;

revoke all on function private.retain_prior_invoice_document(public.invoices, uuid, text) from public;
revoke execute on function private.retain_prior_invoice_document(public.invoices, uuid, text)
  from anon, authenticated;

-- 4. The money seams 3b fills in ------------------------------------------------------------------------------

-- Two rules belong to a draft but depend on money that does not exist yet. They are wired here, behind
-- functions 3b replaces with the real ledger reads, so the draft commands below already refuse and recognise
-- correctly the moment the ledger arrives. Until then there are no allocations, so both answer honestly.
create or replace function private.invoice_allocated_minor(
  target_organization_id uuid,
  target_invoice_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select 0::bigint;
$$;

comment on function private.invoice_allocated_minor(uuid, uuid) is
  'Money currently applied to this invoice, in minor units. A seam: 3a has no ledger, so it answers zero. '
  '3b replaces the body with the sum of live allocations. Callers must not read allocation tables directly.';

revoke all on function private.invoice_allocated_minor(uuid, uuid) from public;
revoke execute on function private.invoice_allocated_minor(uuid, uuid) from anon, authenticated;

-- Contract decision D1: a draft that gets paid in full becomes a settled bill without pretending it was
-- ever sent. 3b calls this after every allocation; it is a no-op until then.
create or replace function private.recognize_invoice_if_settled(
  target_organization_id uuid,
  target_invoice_id uuid,
  actor uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invoice_row public.invoices;
  applied bigint;
begin
  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id
  for update;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;

  if invoice_row.issued_at is not null or invoice_row.recognized_at is not null
     or invoice_row.voided_at is not null or invoice_row.total_minor <= 0 then
    return false;
  end if;

  applied := private.invoice_allocated_minor(target_organization_id, target_invoice_id);
  if applied < invoice_row.total_minor then
    return false;
  end if;

  update public.invoices
  set recognized_at = now(),
      document_frozen_at = coalesce(document_frozen_at, now()),
      revision = revision + 1
  where organization_id = target_organization_id and id = target_invoice_id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.recognized', actor, invoice_row.revision + 1, null,
    jsonb_build_object('reason', 'paid_in_full'), false, null
  );

  return true;
end;
$$;

revoke all on function private.recognize_invoice_if_settled(uuid, uuid, uuid) from public;
revoke execute on function private.recognize_invoice_if_settled(uuid, uuid, uuid) from anon, authenticated;

-- 5. Creating a draft -------------------------------------------------------------------------------------------

create or replace function public.create_invoice_draft(
  target_organization_id uuid,
  target_client_id uuid,
  new_subject text,
  new_lines jsonb,
  new_service_property_ids uuid[],
  new_payment_term_id uuid,
  new_custom_due_date date,
  new_issue_date date,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  settings_row public.organization_settings;
  term_row public.invoice_payment_terms;
  clean_subject text := nullif(trim(coalesce(new_subject, '')), '');
  issue_on date;
  due_on date;
  term_source text;
  created public.invoices;
  line_count integer;
  money jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to create an invoice.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to create an invoice here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  if clean_subject is null or char_length(clean_subject) < 2 or char_length(clean_subject) > 160 then
    raise exception 'An invoice needs a subject between 2 and 160 characters.'
      using errcode = 'check_violation';
  end if;
  if new_lines is null or jsonb_typeof(new_lines) <> 'array' or jsonb_array_length(new_lines) = 0 then
    raise exception 'An invoice needs at least one line.' using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'create_invoice_draft', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- The settings row first, always. It carries the currency this bill is about to snapshot, and holding it
  -- is what stops a currency change from committing between reading it and writing the invoice.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for share;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  if not exists (
    select 1 from public.clients
    where organization_id = target_organization_id and id = target_client_id and deleted_at is null
  ) then
    raise exception 'That client could not be found.' using errcode = 'P0404';
  end if;

  issue_on := coalesce(new_issue_date, private.organization_today(target_organization_id));

  if new_custom_due_date is not null then
    if new_payment_term_id is not null then
      raise exception 'Choose either a payment term or a custom due date, not both.'
        using errcode = 'check_violation';
    end if;
    if new_custom_due_date < issue_on then
      raise exception 'A due date cannot be before the invoice date.' using errcode = 'check_violation';
    end if;
    term_source := 'custom';
    due_on := new_custom_due_date;
  else
    term_row := private.resolve_client_payment_term(
      target_organization_id, target_client_id, new_payment_term_id
    );
    term_source := 'term';
    due_on := private.invoice_due_date(issue_on, term_row);
    -- End-of-month terms land before the issue date when a bill is dated late in a month it belongs to.
    -- The customer is due immediately in that case rather than owing money in the past.
    due_on := greatest(due_on, issue_on);
  end if;

  insert into public.invoices (
    organization_id, client_id, invoice_number, subject, currency_code,
    customer_snapshot, billing_address_snapshot, service_properties,
    payment_term_id, payment_term_snapshot, due_date_source, issue_date, due_date, created_by
  ) values (
    target_organization_id,
    target_client_id,
    private.allocate_invoice_number(target_organization_id),
    clean_subject,
    settings_row.currency_code,
    private.build_invoice_customer_snapshot(target_organization_id, target_client_id),
    private.resolve_client_billing_address(target_organization_id, target_client_id),
    private.build_invoice_service_properties(
      target_organization_id, target_client_id, new_service_property_ids
    ),
    case when term_source = 'term' then term_row.id end,
    case when term_source = 'term' then jsonb_build_object(
      'term_id', term_row.id, 'name', term_row.name, 'rule', term_row.rule, 'net_days', term_row.net_days
    ) else jsonb_build_object('rule', 'custom_date') end,
    term_source,
    issue_on,
    due_on,
    caller
  )
  returning * into created;

  insert into public.invoice_lines (
    organization_id, invoice_id, position, source_catalog_item_id, source_job_id, source_job_line_id,
    service_date, line_kind, category, name, description, unit_label, quantity, unit_price_minor,
    is_taxable, progress_original_amount_minor
  )
  select
    target_organization_id,
    created.id,
    (row_number() over (order by (line.value->>'position')::integer, line.ordinality) - 1)::integer,
    nullif(line.value->>'source_catalog_item_id', '')::uuid,
    nullif(line.value->>'source_job_id', '')::uuid,
    nullif(line.value->>'source_job_line_id', '')::uuid,
    nullif(line.value->>'service_date', '')::date,
    coalesce(line.value->>'line_kind', 'priced'),
    nullif(line.value->>'category', ''),
    line.value->>'name',
    nullif(line.value->>'description', ''),
    nullif(line.value->>'unit_label', ''),
    (line.value->>'quantity')::numeric,
    (line.value->>'unit_price_minor')::bigint,
    coalesce((line.value->>'is_taxable')::boolean, true),
    nullif(line.value->>'progress_original_amount_minor', '')::bigint
  from jsonb_array_elements(new_lines) with ordinality as line(value, ordinality);

  get diagnostics line_count = row_count;

  money := private.store_invoice_money(created.id);

  perform private.record_invoice_event(
    target_organization_id, created.id, created.invoice_number, target_client_id,
    'invoice.created', caller, created.revision, null,
    jsonb_build_object('line_count', line_count, 'due_date_source', term_source), false, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'create_invoice_draft', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', created.id,
      'invoice_number', created.invoice_number,
      'revision', created.revision,
      'issue_date', created.issue_date,
      'due_date', created.due_date,
      'currency_code', created.currency_code,
      'line_count', line_count,
      'totals', money - 'lines'
    )
  );
end;
$$;

comment on function public.create_invoice_draft(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, text, text
) is
  'Creates a draft invoice with its customer, billing-address, service-property and payment-term snapshots, '
  'its lines and its calculated money, in one transaction. A retry carrying the same key returns the first '
  'invoice instead of creating a second one.';

revoke all on function public.create_invoice_draft(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, text, text
) from public;
revoke execute on function public.create_invoice_draft(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, text, text
) from anon;
grant execute on function public.create_invoice_draft(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, text, text
) to authenticated;

-- 6. Changing the document -----------------------------------------------------------------------------------

-- The header: what the bill is called and when it is dated and due. Allowed on an issued bill because the
-- contract keeps sent invoices editable, and safe there because the previous document goes into history
-- first and re-sending is a separate explicit choice.
create or replace function public.update_invoice_details(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_subject text,
  new_issue_date date,
  new_payment_term_id uuid,
  new_custom_due_date date
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  term_row public.invoice_payment_terms;
  clean_subject text := nullif(trim(coalesce(new_subject, '')), '');
  issue_on date;
  due_on date;
  term_source text;
begin
  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision
  );

  if clean_subject is null or char_length(clean_subject) < 2 or char_length(clean_subject) > 160 then
    raise exception 'An invoice needs a subject between 2 and 160 characters.'
      using errcode = 'check_violation';
  end if;

  issue_on := coalesce(new_issue_date, invoice_row.issue_date);

  if new_custom_due_date is not null then
    if new_payment_term_id is not null then
      raise exception 'Choose either a payment term or a custom due date, not both.'
        using errcode = 'check_violation';
    end if;
    if new_custom_due_date < issue_on then
      raise exception 'A due date cannot be before the invoice date.' using errcode = 'check_violation';
    end if;
    term_source := 'custom';
    due_on := new_custom_due_date;
  else
    term_row := private.resolve_client_payment_term(
      target_organization_id, invoice_row.client_id, new_payment_term_id
    );
    term_source := 'term';
    due_on := greatest(private.invoice_due_date(issue_on, term_row), issue_on);
  end if;

  perform private.retain_prior_invoice_document(invoice_row, caller, 'details updated');

  update public.invoices
  set subject = clean_subject,
      issue_date = issue_on,
      due_date = due_on,
      due_date_source = term_source,
      payment_term_id = case when term_source = 'term' then term_row.id end,
      payment_term_snapshot = case when term_source = 'term' then jsonb_build_object(
        'term_id', term_row.id, 'name', term_row.name, 'rule', term_row.rule, 'net_days', term_row.net_days
      ) else jsonb_build_object('rule', 'custom_date') end,
      revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.details_updated', caller, invoice_row.revision + 1, null,
    jsonb_build_object('due_date_source', term_source), false, null
  );

  return jsonb_build_object(
    'revision', invoice_row.revision + 1, 'issue_date', issue_on, 'due_date', due_on
  );
end;
$$;

revoke all on function public.update_invoice_details(uuid, uuid, integer, text, date, uuid, date)
  from public;
revoke execute on function public.update_invoice_details(uuid, uuid, integer, text, date, uuid, date)
  from anon;
grant execute on function public.update_invoice_details(uuid, uuid, integer, text, date, uuid, date)
  to authenticated;

-- The whole set of lines in one call, the same all-or-nothing replacement the quote and job commands use.
-- The hundred-line cap and the shape of each line are the table's own rules; this inserts and lets the
-- table refuse what it must.
create or replace function public.replace_invoice_lines(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  line_count integer;
  money jsonb;
begin
  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision
  );
  perform private.require_invoice_price_access(target_organization_id);

  if new_lines is null or jsonb_typeof(new_lines) <> 'array' or jsonb_array_length(new_lines) = 0 then
    raise exception 'An invoice needs at least one line.' using errcode = 'check_violation';
  end if;

  perform private.retain_prior_invoice_document(invoice_row, caller, 'lines replaced');

  delete from public.invoice_lines
  where organization_id = target_organization_id and invoice_id = target_invoice_id;

  insert into public.invoice_lines (
    organization_id, invoice_id, position, source_catalog_item_id, source_job_id, source_job_line_id,
    service_date, line_kind, category, name, description, unit_label, quantity, unit_price_minor,
    is_taxable, progress_original_amount_minor
  )
  select
    target_organization_id,
    target_invoice_id,
    (row_number() over (order by (line.value->>'position')::integer, line.ordinality) - 1)::integer,
    nullif(line.value->>'source_catalog_item_id', '')::uuid,
    nullif(line.value->>'source_job_id', '')::uuid,
    nullif(line.value->>'source_job_line_id', '')::uuid,
    nullif(line.value->>'service_date', '')::date,
    coalesce(line.value->>'line_kind', 'priced'),
    nullif(line.value->>'category', ''),
    line.value->>'name',
    nullif(line.value->>'description', ''),
    nullif(line.value->>'unit_label', ''),
    (line.value->>'quantity')::numeric,
    (line.value->>'unit_price_minor')::bigint,
    coalesce((line.value->>'is_taxable')::boolean, true),
    nullif(line.value->>'progress_original_amount_minor', '')::bigint
  from jsonb_array_elements(new_lines) with ordinality as line(value, ordinality);

  get diagnostics line_count = row_count;

  money := private.store_invoice_money(target_invoice_id);

  update public.invoices
  set revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id;

  -- Redacted metadata: how many lines the bill now carries, never what they say or what they cost.
  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.lines_updated', caller, invoice_row.revision + 1, null,
    jsonb_build_object('line_count', line_count), false, null
  );

  return jsonb_build_object(
    'revision', invoice_row.revision + 1, 'line_count', line_count, 'totals', money - 'lines'
  );
end;
$$;

revoke all on function public.replace_invoice_lines(uuid, uuid, integer, jsonb) from public;
revoke execute on function public.replace_invoice_lines(uuid, uuid, integer, jsonb) from anon;
grant execute on function public.replace_invoice_lines(uuid, uuid, integer, jsonb) to authenticated;

create or replace function public.set_invoice_discount(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_name text,
  new_type text,
  new_value bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  clean_type text := nullif(trim(coalesce(new_type, '')), '');
  clean_name text := nullif(trim(coalesce(new_name, '')), '');
  money jsonb;
begin
  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision
  );
  perform private.require_invoice_price_access(target_organization_id);

  if clean_type is not null and clean_type not in ('fixed', 'percentage') then
    raise exception 'A discount is either a fixed amount or a percentage.' using errcode = 'check_violation';
  end if;
  if clean_type is not null and (new_value is null or new_value < 0) then
    raise exception 'A discount needs an amount.' using errcode = 'check_violation';
  end if;
  if clean_type = 'percentage' and new_value > 10000 then
    raise exception 'A percentage discount is between 0 and 100 percent.' using errcode = 'check_violation';
  end if;
  if clean_type is not null and clean_name is null then
    raise exception 'Give this discount a name the customer will recognize.'
      using errcode = 'check_violation';
  end if;

  perform private.retain_prior_invoice_document(invoice_row, caller, 'discount changed');

  update public.invoices
  set discount_name = case when clean_type is null then null else clean_name end,
      discount_type = clean_type,
      discount_value = case when clean_type is null then null else new_value end
  where organization_id = target_organization_id and id = target_invoice_id;

  money := private.store_invoice_money(target_invoice_id);

  update public.invoices
  set revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.discount_updated', caller, invoice_row.revision + 1, null,
    jsonb_build_object('type', clean_type), false, null
  );

  return jsonb_build_object('revision', invoice_row.revision + 1, 'totals', money - 'lines');
end;
$$;

revoke all on function public.set_invoice_discount(uuid, uuid, integer, text, text, bigint) from public;
revoke execute on function public.set_invoice_discount(uuid, uuid, integer, text, text, bigint) from anon;
grant execute on function public.set_invoice_discount(uuid, uuid, integer, text, text, bigint)
  to authenticated;

-- The same tax choices a job has, resolved through the same private.resolve_property_tax. An invoice may
-- cover several properties, so the property default is read from the first service property on the bill,
-- and an invoice with none falls back to the business default.
create or replace function public.set_invoice_tax(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_source text,
  new_rate_id uuid default null,
  new_custom_name text default null,
  new_custom_rate_basis_points integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  rate_row public.organization_tax_rates;
  resolved_tax record;
  first_property uuid;
  clean_name text;
  clean_rate integer;
  money jsonb;
begin
  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision
  );
  perform private.require_invoice_price_access(target_organization_id);

  if new_source not in ('business_default', 'property_default', 'saved_rate', 'no_tax', 'custom') then
    raise exception 'Choose a tax option.' using errcode = 'check_violation';
  end if;

  perform private.retain_prior_invoice_document(invoice_row, caller, 'tax changed');

  if new_source in ('business_default', 'property_default') then
    first_property := nullif(invoice_row.service_properties->0->>'property_id', '')::uuid;

    select * into resolved_tax
    from private.resolve_property_tax(target_organization_id, first_property);

    update public.invoices
    set tax_source = resolved_tax.source, tax_name = resolved_tax.name,
        tax_rate_basis_points = resolved_tax.rate_basis_points, tax_rate_id = resolved_tax.rate_id
    where organization_id = target_organization_id and id = target_invoice_id;

  elsif new_source = 'saved_rate' then
    select * into rate_row
    from public.organization_tax_rates
    where id = new_rate_id and organization_id = target_organization_id and is_active;
    if rate_row.id is null then
      raise exception 'Choose an active saved tax rate.' using errcode = 'check_violation';
    end if;

    update public.invoices
    set tax_source = 'saved_rate', tax_name = rate_row.name,
        tax_rate_basis_points = rate_row.rate_basis_points, tax_rate_id = rate_row.id
    where organization_id = target_organization_id and id = target_invoice_id;

  elsif new_source = 'no_tax' then
    update public.invoices
    set tax_source = 'no_tax', tax_name = null, tax_rate_basis_points = 0, tax_rate_id = null
    where organization_id = target_organization_id and id = target_invoice_id;

  else
    clean_rate := coalesce(new_custom_rate_basis_points, 0);
    if clean_rate <= 0 or clean_rate > 10000 then
      raise exception 'A tax rate is between 0 and 100 percent.' using errcode = 'check_violation';
    end if;
    clean_name := nullif(trim(coalesce(new_custom_name, '')), '');
    if clean_name is null or char_length(clean_name) > 80 then
      raise exception 'Give this tax a name the customer will recognize, under 80 characters.'
        using errcode = 'check_violation';
    end if;

    update public.invoices
    set tax_source = 'custom', tax_name = clean_name, tax_rate_basis_points = clean_rate,
        tax_rate_id = null
    where organization_id = target_organization_id and id = target_invoice_id;
  end if;

  money := private.store_invoice_money(target_invoice_id);

  update public.invoices
  set revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.tax_updated', caller, invoice_row.revision + 1, null,
    jsonb_build_object('source', new_source), false, null
  );

  return jsonb_build_object('revision', invoice_row.revision + 1, 'totals', money - 'lines');
end;
$$;

revoke all on function public.set_invoice_tax(uuid, uuid, integer, text, uuid, text, integer) from public;
revoke execute on function public.set_invoice_tax(uuid, uuid, integer, text, uuid, text, integer) from anon;
grant execute on function public.set_invoice_tax(uuid, uuid, integer, text, uuid, text, integer)
  to authenticated;

-- Re-copying the customer, the billing address and the service properties onto a draft nobody has been
-- given yet. Explicit on purpose: a client who moves does not silently rewrite a bill, and a draft written
-- before a currency change is re-stamped only when somebody asks for it, having seen what changes.
create or replace function public.refresh_invoice_snapshots(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_service_property_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  settings_row public.organization_settings;
  refreshed public.invoices;
begin
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for share;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision
  );
  perform private.require_invoice_price_access(target_organization_id);

  if invoice_row.document_frozen_at is not null then
    raise exception 'This invoice has already been issued, so its snapshot cannot be refreshed.'
      using errcode = 'check_violation';
  end if;
  if private.invoice_allocated_minor(target_organization_id, target_invoice_id) <> 0 then
    raise exception 'Return the money on this draft to client credit before refreshing it.'
      using errcode = 'check_violation';
  end if;

  update public.invoices
  set customer_snapshot = private.build_invoice_customer_snapshot(
        target_organization_id, invoice_row.client_id
      ),
      billing_address_snapshot = private.resolve_client_billing_address(
        target_organization_id, invoice_row.client_id
      ),
      service_properties = case
        when new_service_property_ids is null then service_properties
        else private.build_invoice_service_properties(
          target_organization_id, invoice_row.client_id, new_service_property_ids
        )
      end,
      -- Amounts are not converted, only relabelled, which is why this command exists and why the caller
      -- has to show the difference before calling it.
      currency_code = settings_row.currency_code,
      revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id
  returning * into refreshed;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.snapshot_refreshed', caller, refreshed.revision, null,
    jsonb_build_object(
      'currency_changed', refreshed.currency_code is distinct from invoice_row.currency_code
    ), false, null
  );

  return jsonb_build_object(
    'revision', refreshed.revision,
    'currency_code', refreshed.currency_code,
    'billing_address', refreshed.billing_address_snapshot
  );
end;
$$;

revoke all on function public.refresh_invoice_snapshots(uuid, uuid, integer, uuid[]) from public;
revoke execute on function public.refresh_invoice_snapshots(uuid, uuid, integer, uuid[]) from anon;
grant execute on function public.refresh_invoice_snapshots(uuid, uuid, integer, uuid[]) to authenticated;

-- 7. Issuing ---------------------------------------------------------------------------------------------------

-- The moment a draft becomes a receivable. Sending the email is Part 6's work and happens after this
-- commits; marking as sent issues the same bill without transport. Both are the same state change here, so
-- the document freezes in one place.
create or replace function public.issue_invoice(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_issue_method text,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  settings_row public.organization_settings;
  invoice_row public.invoices;
  issued public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to issue an invoice.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.send') then
    raise exception 'You do not have access to issue an invoice.' using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  if new_issue_method not in ('sent', 'marked_sent') then
    raise exception 'An invoice is issued by sending it or by marking it sent.'
      using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'issue_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Settings first, then the invoice: the same order every currency-sensitive command uses, so a first
  -- issue and a currency change can never both succeed.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for share;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision, 'invoices.send'
  );

  if invoice_row.issued_at is not null then
    raise exception 'This invoice has already been issued.' using errcode = 'check_violation';
  end if;
  if invoice_row.recognized_at is not null then
    raise exception 'This invoice was already settled and cannot be issued.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.currency_code is distinct from settings_row.currency_code then
    raise exception 'This draft was written in a different currency. Refresh it before issuing it.'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from public.invoice_lines
    where organization_id = target_organization_id and invoice_id = target_invoice_id
  ) then
    raise exception 'An invoice needs at least one line before it can be issued.'
      using errcode = 'check_violation';
  end if;

  update public.invoices
  set issued_at = now(),
      issued_by = caller,
      issue_method = new_issue_method,
      document_frozen_at = now(),
      revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id
  returning * into issued;

  perform private.record_invoice_event(
    target_organization_id, issued.id, issued.invoice_number, issued.client_id,
    'invoice.issued', caller, issued.revision, null,
    jsonb_build_object('method', new_issue_method), false, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'issue_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', issued.id,
      'invoice_number', issued.invoice_number,
      'revision', issued.revision,
      'issued_at', issued.issued_at,
      'issue_method', issued.issue_method,
      'due_date', issued.due_date
    )
  );
end;
$$;

comment on function public.issue_invoice(uuid, uuid, integer, text, text, text) is
  'Turns a draft into a receivable and freezes its document. Transport is a separate step: this records the '
  'issue fact for both sending and marking as sent, and a retry returns the first result.';

revoke all on function public.issue_invoice(uuid, uuid, integer, text, text, text) from public;
revoke execute on function public.issue_invoice(uuid, uuid, integer, text, text, text) from anon;
grant execute on function public.issue_invoice(uuid, uuid, integer, text, text, text) to authenticated;

-- 8. Deleting a draft --------------------------------------------------------------------------------------

-- The only invoice that may be deleted at all. An issued bill is retained through void instead, and a draft
-- holding money has to have that money explicitly returned to client credit first -- deletion never quietly
-- unapplies, refunds or moves it. History survives the deletion, because invoice_events is not a child row.
create or replace function public.delete_invoice_draft(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  invoice_row public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to delete an invoice.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.delete') then
    raise exception 'You do not have access to delete an invoice.'
      using errcode = 'insufficient_privilege';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'delete_invoice_draft', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision, 'invoices.delete'
  );

  if invoice_row.issued_at is not null or invoice_row.recognized_at is not null then
    raise exception 'An invoice that has been issued or settled cannot be deleted. Void it instead.'
      using errcode = 'check_violation';
  end if;
  if private.invoice_allocated_minor(target_organization_id, target_invoice_id) <> 0 then
    raise exception 'Return the money on this draft to client credit before deleting it.'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.invoices
    where organization_id = target_organization_id and predecessor_invoice_id = target_invoice_id
  ) then
    raise exception 'Another invoice replaces this one, so it cannot be deleted.'
      using errcode = 'check_violation';
  end if;

  -- History is written before the row goes, and outlives it: the event carries the invoice number and the
  -- client, so a deleted draft still reads correctly a year later.
  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.draft_deleted', caller, invoice_row.revision, null, '{}'::jsonb, false, null
  );

  delete from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;

  return private.complete_invoice_command(
    target_organization_id, 'delete_invoice_draft', new_idempotency_key,
    jsonb_build_object('invoice_id', invoice_row.id, 'invoice_number', invoice_row.invoice_number)
  );
end;
$$;

revoke all on function public.delete_invoice_draft(uuid, uuid, integer, text, text) from public;
revoke execute on function public.delete_invoice_draft(uuid, uuid, integer, text, text) from anon;
grant execute on function public.delete_invoice_draft(uuid, uuid, integer, text, text) to authenticated;

notify pgrst, 'reload schema';
