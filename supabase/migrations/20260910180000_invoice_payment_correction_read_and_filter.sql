-- Paid-launch-trust Part 11: two small read-model changes needed before the payment correction routes
-- (unapply / move / refund) can be built.
--
--   1. invoice_list_page gains an optional client_id_filter, appended as a trailing defaulted parameter so
--      every existing caller (the Invoices list) is unaffected. The "Move to another invoice" picker needs
--      one client's open bills, not a page of the whole organization's; invoices_client_idx
--      (organization_id, client_id, created_at desc, id) already carries exactly this shape, so the filter
--      is index-backed with no new index.
--   2. payment_detail's applied_to rows gain is_reversed, so the payment screen can tell an active
--      application apart from one already taken back off (unapply_client_payment / move_client_payment both
--      refuse a second reversal of the same allocation) without re-deriving that from allocation history.
--      invoice_payment_allocations_reversed_once_idx (organization_id, reversed_allocation_id) already
--      carries the lookup.

-- 1. invoice_list_page: optional client filter ----------------------------------------------------------------

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
  page_limit integer default 25,
  client_id_filter uuid default null
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
      and ($12::uuid is null or invoice.client_id = $12)
      %1$s
    order by %2$s %3$s, invoice.id %3$s
    limit $8
  $q$, seek_clause, sort_column, case when ascending then 'asc' else 'desc' end);

  return query execute statement
    using target_organization_id, today, search_like, search_number, created_from, created_to,
          status_filter, page_limit, cursor_created, cursor_number, cursor_id, client_id_filter;
end;
$$;

comment on function public.invoice_list_page(
  uuid, text, bigint, text[], text, text, timestamptz, timestamptz, timestamptz, bigint, uuid, integer, uuid
) is
  'One keyset-paged page of the Invoices list, with the derived contract status computed set-based. Definer '
  'so a reader without invoices.view_price still sees a bill''s status without ever selecting its amount; '
  'checks invoices.view and scopes every row to the one organization. client_id_filter narrows to one '
  'client''s bills (invoices_client_idx) -- used by the payment-move picker, optional everywhere else. No '
  'money -- that comes from public.invoice_money.';

revoke all on function public.invoice_list_page(
  uuid, text, bigint, text[], text, text, timestamptz, timestamptz, timestamptz, bigint, uuid, integer, uuid
) from public, anon;
grant execute on function public.invoice_list_page(
  uuid, text, bigint, text[], text, text, timestamptz, timestamptz, timestamptz, bigint, uuid, integer, uuid
) to authenticated;

-- 2. payment_detail: which applications are still active --------------------------------------------------

create or replace function public.payment_detail(
  target_organization_id uuid,
  target_payment_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  payment_row public.client_payment_events;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this payment.' using errcode = 'insufficient_privilege';
  end if;

  select * into payment_row
  from public.client_payment_events
  where organization_id = target_organization_id and id = target_payment_event_id;

  -- A refund or a reversal is a correction, not a receipt, and this screen is the receipt's home. Same answer
  -- as a payment that does not exist, so the screen cannot be used to find out which is which.
  if payment_row.id is null or payment_row.event_type <> 'received' then
    raise exception 'That payment could not be found.' using errcode = 'P0404';
  end if;

  return jsonb_build_object(
    'payment', jsonb_build_object(
      'id', payment_row.id,
      'amount_minor', payment_row.amount_minor,
      'currency_code', payment_row.currency_code,
      'method', payment_row.method,
      'payment_date', payment_row.payment_date,
      'reference', payment_row.reference,
      'note', payment_row.note,
      'created_at', payment_row.created_at
    ),
    -- The same client card the invoice screen shows, read the same way: the primary email lives in
    -- client_contact_methods, not on the client row, and the send dialog needs it to say who the receipt
    -- goes to.
    'client', (
      select jsonb_build_object(
        'id', client.id,
        'display_name', client.display_name,
        'company_name', client.company_name,
        'email', (
          select lower(trim(method.value))
          from public.client_contact_methods as method
          where method.organization_id = target_organization_id
            and method.client_id = client.id
            and method.kind = 'email'
          order by method.is_primary desc, method.created_at
          limit 1
        )
      )
      from public.clients as client
      where client.organization_id = target_organization_id and client.id = payment_row.client_id
    ),
    -- What this money was put against. Applications and the entries that take them back both appear, oldest
    -- first, so a payment that was moved off a bill reads as what happened rather than as a gap. The invoice
    -- number is the allocation's own copy, so it still reads as "Invoice #14" after that draft is gone --
    -- and invoice_id is left null for a bill that no longer exists, which is what makes the link safe.
    -- is_reversed is true on an 'applied' row once some later row has taken it back off (unapply or the first
    -- half of a move) -- unapply_client_payment and move_client_payment both refuse a second reversal of the
    -- same allocation, so the screen uses this to stop offering an action that can only fail.
    'applied_to', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'allocation_id', allocation.id,
        'invoice_id', invoice.id,
        'invoice_number', allocation.invoice_number,
        'subject', invoice.subject,
        'entry_type', allocation.entry_type,
        'amount_minor', allocation.amount_minor,
        'created_at', allocation.created_at,
        'is_reversed', exists (
          select 1 from public.invoice_payment_allocations as reversal
          where reversal.organization_id = allocation.organization_id
            and reversal.reversed_allocation_id = allocation.id
        )
      ) order by allocation.created_at, allocation.id), '[]'::jsonb)
      from public.invoice_payment_allocations as allocation
      left join public.invoices as invoice
        on invoice.organization_id = allocation.organization_id and invoice.id = allocation.invoice_id
      where allocation.organization_id = target_organization_id
        and allocation.payment_event_id = target_payment_event_id
    )
  );
end;
$$;

comment on function public.payment_detail(uuid, uuid) is
  'One recorded payment for its detail screen: the receipt fields, the client, and the invoices it was '
  'applied to, each application flagged is_reversed once it has been taken back off. Definer; requires '
  'invoices.view and invoices.view_price, because a payment with its amount withheld is nothing. Refunds and '
  'reversals are not found here -- this screen is the receipt''s home.';

revoke all on function public.payment_detail(uuid, uuid) from public, anon;
grant execute on function public.payment_detail(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
