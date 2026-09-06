-- Invoices 8b-1: the read behind the Batch Deliver picker.
--
-- One keyset-paged page of the invoices a person may send in a batch -- exactly the three sendable derived
-- statuses (draft, awaiting payment, past due). Paid, voided, bad debt and replaced bills are never eligible,
-- so they never appear. Definer, like invoice_list_page, so a reader without invoices.view_price still sees a
-- bill's status without ever selecting its amount; it reuses private.invoice_live_status so the status label
-- can never drift from the main list.
--
-- On top of the list's columns it carries the three facts the picker needs and cannot cheaply recompute in
-- the browser:
--   * revision     -- the optimistic-lock value the batch send passes back to issue_invoice for a draft.
--   * has_email    -- whether the client has an email at all, so the picker can flag "no email" before submit.
--                     Mirrors what enqueue_invoice_communication_email resolves (kind='email'), so the flag
--                     and the send agree.
--   * last_sent_at -- the newest delivery intent for this invoice, so a previously-sent bill shows as such and
--                     is only ever re-sent on purpose.
--
-- No new indexes: created-order paging rides the invoices list index, has_email rides
-- client_contact_methods_value_unique_idx (client_id, kind, ...), and last_sent_at rides
-- communication_delivery_intents_invoice_created_idx (organization_id, invoice_id, created_at desc, id desc).

create or replace function public.invoice_batch_deliverable_page(
  target_organization_id uuid,
  cursor_created timestamptz default null,
  cursor_id uuid default null,
  page_limit integer default 20
)
returns table(
  id uuid,
  invoice_number integer,
  subject text,
  currency_code text,
  due_date date,
  issued_at timestamptz,
  created_at timestamptz,
  derived_status text,
  revision integer,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  has_email boolean,
  last_sent_at timestamptz
)
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
  if page_limit is null or page_limit < 1 or page_limit > 50 then
    page_limit := 20;
  end if;
  today := private.organization_today(target_organization_id);

  return query
    select
      invoice.id,
      invoice.invoice_number,
      invoice.subject,
      invoice.currency_code,
      invoice.due_date,
      invoice.issued_at,
      invoice.created_at,
      label.derived_status,
      invoice.revision,
      invoice.client_id,
      client.display_name as client_display_name,
      client.company_name as client_company_name,
      exists (
        select 1 from public.client_contact_methods as method
        where method.client_id = invoice.client_id and method.kind = 'email'
      ) as has_email,
      (
        select max(intent.created_at) from public.communication_delivery_intents as intent
        where intent.organization_id = invoice.organization_id and intent.invoice_id = invoice.id
      ) as last_sent_at
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
      select private.invoice_live_status(
        invoice.voided_at, invoice.written_off_at, invoice.issued_at, invoice.recognized_at,
        invoice.marked_received_at, invoice.total_minor, allocation.applied_minor, invoice.due_date, today
      ) as derived_status
    ) as label
    where invoice.organization_id = target_organization_id
      and invoice.replaced_at is null
      and label.derived_status in ('draft', 'awaiting_payment', 'past_due')
      and (
        cursor_created is null or cursor_id is null
        or invoice.created_at < cursor_created
        or (invoice.created_at = cursor_created and invoice.id < cursor_id)
      )
    order by invoice.created_at desc, invoice.id desc
    limit page_limit;
end;
$$;

comment on function public.invoice_batch_deliverable_page(uuid, timestamptz, uuid, integer) is
  'One keyset-paged page of invoices eligible for batch delivery (draft, awaiting payment, past due), newest '
  'first. Definer so status shows without invoices.view_price; reuses private.invoice_live_status. Adds '
  'revision, has_email and last_sent_at for the picker. Checks invoices.view and scopes to one organization.';

revoke all on function public.invoice_batch_deliverable_page(uuid, timestamptz, uuid, integer) from public, anon;
grant execute on function public.invoice_batch_deliverable_page(uuid, timestamptz, uuid, integer) to authenticated;
