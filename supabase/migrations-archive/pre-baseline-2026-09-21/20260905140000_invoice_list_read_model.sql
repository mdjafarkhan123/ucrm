-- Invoices Part 4a: the list's read model.
--
-- The Invoices list and its overview show a status that is never stored: Draft, Awaiting payment, Past due,
-- Paid, Bad debt, Voided. Working the label out needs the invoice's total and how much money has been applied
-- to it, and those money columns are deliberately kept off the grant to `authenticated` (a member who may
-- see that a bill exists is not automatically one who may see what the customer was charged). So the derived
-- status cannot be produced by an ordinary security-invoker view the way jobs_list_rows produces a job's
-- status -- a job's status is pure arithmetic on dates, an invoice's is not.
--
-- The proven shape for a paged list with a permission-gated, derived column is a SECURITY DEFINER read: the
-- amounts stay behind the function boundary, the function checks invoices.view itself (exactly as
-- public.invoice_money and public.client_account_balance already do), and the label is computed set-based --
-- one scan with an inline allocation probe per row -- rather than a function call per row. A per-row plpgsql
-- reader was measured against 40k invoices and timed out; the set-based form runs in ~150ms and, for an
-- unfiltered page, is bounded to the rows the page actually returns.

-- 1. The one live-status rule --------------------------------------------------------------------------------

-- Pure: a function of the facts alone, reading nothing. It is the single definition of the six labels, so the
-- per-row label used when a replacement freezes its predecessor (private.invoice_status_label) and the two
-- set-based readers below all derive the same status from the same rule and can never drift. Being a plain SQL
-- expression, Postgres inlines it into the reader's scan, so calling it costs no more than writing the CASE by
-- hand.
create or replace function private.invoice_live_status(
  voided_at timestamptz,
  written_off_at timestamptz,
  issued_at timestamptz,
  recognized_at timestamptz,
  marked_received_at timestamptz,
  total_minor bigint,
  allocated_minor bigint,
  due_date date,
  today date
)
returns text
language sql
immutable
as $$
  select case
    when voided_at is not null then 'voided'
    when written_off_at is not null then 'bad_debt'
    when issued_at is null and recognized_at is null then 'draft'
    -- Status-only closure. It extinguishes no debt, but the label the contractor sees is Paid.
    when marked_received_at is not null then 'paid'
    when allocated_minor >= total_minor then 'paid'
    when due_date < today then 'past_due'
    else 'awaiting_payment'
  end;
$$;

comment on function private.invoice_live_status(
  timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, bigint, bigint, date, date
) is
  'The one rule for an invoice''s live contract status, as a pure function of its facts. Shared by '
  'private.invoice_status_label and the list/overview readers so a bill''s label is derived one way '
  'everywhere. A replaced bill''s frozen label is handled by its readers, not here.';

revoke all on function private.invoice_live_status(
  timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, bigint, bigint, date, date
) from public;
revoke execute on function private.invoice_live_status(
  timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, bigint, bigint, date, date
) from anon, authenticated;

-- 2. The per-row status label now delegates to the shared rule ----------------------------------------------

-- Behaviour is unchanged from when it shipped in 20260905130000: it still gathers the same inputs and returns
-- the same six labels. It now derives them through private.invoice_live_status so the freezing path and the
-- list can never disagree about what "Paid" means. Re-verified by the source-claims pgTAP suite.
create or replace function private.invoice_status_label(invoice_row public.invoices)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  return private.invoice_live_status(
    invoice_row.voided_at,
    invoice_row.written_off_at,
    invoice_row.issued_at,
    invoice_row.recognized_at,
    invoice_row.marked_received_at,
    invoice_row.total_minor,
    private.invoice_allocated_minor(invoice_row.organization_id, invoice_row.id),
    invoice_row.due_date,
    private.organization_today(invoice_row.organization_id)
  );
end;
$$;

comment on function private.invoice_status_label(public.invoices) is
  'The six contract statuses derived from stored facts, used to freeze the label a bill carried at the moment '
  'it was replaced so history never ages into Past Due. Delegates to private.invoice_live_status.';

revoke all on function private.invoice_status_label(public.invoices) from public;
revoke execute on function private.invoice_status_label(public.invoices) from anon, authenticated;

-- 3. The list's page ---------------------------------------------------------------------------------------

-- One page of the Invoices list. Definer, because the derived status needs money the reader may not select;
-- it exposes only the label and identity, never an amount. It checks invoices.view for itself and scopes
-- every row to the one organization, so it stands in for the RLS a security-invoker view would have applied.
-- The client name is joined live for display, the same way the Jobs list does; the frozen customer snapshot
-- is the detail screen's concern.
--
-- Keyset paged: the seek and ordering run on invoices_organization_created_idx (created sort) or
-- invoices_number_unique (number sort), so an unfiltered page computes the status only for the rows it
-- returns. A status filter is applied on the computed label through a lateral, so it narrows correctly; the
-- per-row work is an inline allocation probe, not a function call, so even a rare status stays a single cheap
-- scan rather than the timeout a per-row plpgsql reader produced.
create or replace function public.invoice_list_page(
  target_organization_id uuid,
  search_like text default null,
  search_number bigint default null,
  status_filter text[] default null,
  sort_key text default 'created',
  sort_dir text default 'desc',
  created_from timestamptz default null,
  created_to timestamptz default null,
  cursor_created timestamptz default null,
  cursor_number bigint default null,
  cursor_id uuid default null,
  page_limit integer default 25
)
returns table(
  id uuid,
  invoice_number integer,
  subject text,
  currency_code text,
  issue_date date,
  due_date date,
  issued_at timestamptz,
  created_at timestamptz,
  is_replaced boolean,
  derived_status text,
  client_id uuid,
  client_display_name text,
  client_company_name text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  today date;
  ascending boolean := lower(sort_dir) = 'asc';
  sort_column text;
  comparison text;
  seek_clause text := '';
  statement text;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  if page_limit is null or page_limit < 1 or page_limit > 50 then
    page_limit := 25;
  end if;
  today := private.organization_today(target_organization_id);

  -- Whitelisted, never interpolated from caller text: only these two columns and two directions are ever
  -- placed into the statement, and every value travels as a bound parameter.
  sort_column := case when sort_key = 'number' then 'invoice.invoice_number' else 'invoice.created_at' end;
  comparison := case when ascending then '>' else '<' end;

  if sort_key = 'number' and cursor_number is not null and cursor_id is not null then
    seek_clause := format(
      ' and (invoice.invoice_number %1$s $10 or (invoice.invoice_number = $10 and invoice.id %1$s $11))',
      comparison
    );
  elsif sort_key <> 'number' and cursor_created is not null and cursor_id is not null then
    seek_clause := format(
      ' and (invoice.created_at %1$s $9 or (invoice.created_at = $9 and invoice.id %1$s $11))',
      comparison
    );
  end if;

  statement := format($q$
    select
      invoice.id,
      invoice.invoice_number,
      invoice.subject,
      invoice.currency_code,
      invoice.issue_date,
      invoice.due_date,
      invoice.issued_at,
      invoice.created_at,
      invoice.replaced_at is not null as is_replaced,
      label.derived_status,
      invoice.client_id,
      client.display_name as client_display_name,
      client.company_name as client_company_name
    from public.invoices as invoice
    left join public.clients as client
      on client.organization_id = invoice.organization_id and client.id = invoice.client_id
    left join lateral (
      select coalesce(sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end), 0)::bigint as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
    ) as allocation on true
    cross join lateral (
      select case
        when invoice.replaced_at is not null then invoice.frozen_status_label
        else private.invoice_live_status(
          invoice.voided_at, invoice.written_off_at, invoice.issued_at, invoice.recognized_at,
          invoice.marked_received_at, invoice.total_minor, allocation.applied_minor, invoice.due_date, $2)
      end as derived_status
    ) as label
    where invoice.organization_id = $1
      and ($3::text is null or invoice.subject ilike $3
           or ($4::bigint is not null and invoice.invoice_number = $4))
      and ($5::timestamptz is null or invoice.created_at >= $5)
      and ($6::timestamptz is null or invoice.created_at <= $6)
      and ($7::text[] is null or label.derived_status = any($7))
      %1$s
    order by %2$s %3$s, invoice.id %3$s
    limit $8
  $q$, seek_clause, sort_column, case when ascending then 'asc' else 'desc' end);

  return query execute statement
    using target_organization_id, today, search_like, search_number, created_from, created_to,
          status_filter, page_limit, cursor_created, cursor_number, cursor_id;
end;
$$;

comment on function public.invoice_list_page(
  uuid, text, bigint, text[], text, text, timestamptz, timestamptz, timestamptz, bigint, uuid, integer
) is
  'One keyset-paged page of the Invoices list, with the derived contract status computed set-based. Definer '
  'so a reader without invoices.view_price still sees a bill''s status without ever selecting its amount; '
  'checks invoices.view and scopes every row to the one organization. No money -- that comes from '
  'public.invoice_money.';

revoke all on function public.invoice_list_page(
  uuid, text, bigint, text[], text, text, timestamptz, timestamptz, timestamptz, bigint, uuid, integer
) from public, anon;
grant execute on function public.invoice_list_page(
  uuid, text, bigint, text[], text, text, timestamptz, timestamptz, timestamptz, bigint, uuid, integer
) to authenticated;

-- 4. The overview counts ---------------------------------------------------------------------------------

-- The tiles at the top of the list, counted live like the Jobs and Quotes overviews so they can never be
-- stale, and derived from the same rule the list uses so a tile and the rows behind it can never disagree.
-- Definer for the same reason as the page: the label needs money the reader may not select, and only the
-- label and its count ever leave. One scan of the organization's invoices with an inline allocation probe per
-- row -- measured at ~150ms for 40k invoices.
create or replace function public.invoice_status_counts(target_organization_id uuid)
returns table(derived_status text, total bigint)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  today date;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  today := private.organization_today(target_organization_id);

  return query
    select label.derived_status, count(*)::bigint as total
    from public.invoices as invoice
    left join lateral (
      select coalesce(sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end), 0)::bigint as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
    ) as allocation on true
    cross join lateral (
      select case
        when invoice.replaced_at is not null then invoice.frozen_status_label
        else private.invoice_live_status(
          invoice.voided_at, invoice.written_off_at, invoice.issued_at, invoice.recognized_at,
          invoice.marked_received_at, invoice.total_minor, allocation.applied_minor, invoice.due_date, today)
      end as derived_status
    ) as label
    where invoice.organization_id = target_organization_id
    group by label.derived_status;
end;
$$;

comment on function public.invoice_status_counts(uuid) is
  'Live count of this organization''s invoices by derived contract status, for the Invoices overview card. '
  'Derived from the same rule as public.invoice_list_page.';

revoke all on function public.invoice_status_counts(uuid) from public, anon;
grant execute on function public.invoice_status_counts(uuid) to authenticated;

notify pgrst, 'reload schema';
