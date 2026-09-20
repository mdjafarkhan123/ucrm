-- Online payments Part 9b: the list of a client's unspent money, so it can be put on an invoice by hand.
--
-- `apply_client_payment` already puts a recorded payment or a quote deposit onto a bill, but it needs to be
-- told exactly which one. Nothing listed them: the invoice page only knows the client's total spare credit.
-- This reader lists each payment or deposit that still has money left, using the same "what is left"
-- helpers the ledger and the apply command use, so the screen can never offer more than the command accepts.
--
-- Read-only. Same gate as applying a payment: the caller may record payments and see invoice amounts.

create or replace function public.client_spendable_credit(
  target_organization_id uuid,
  target_client_id uuid
)
returns table (
  source text,
  source_id uuid,
  quote_id uuid,
  quote_number integer,
  method text,
  reference text,
  currency_code text,
  amount_minor bigint,
  available_minor bigint,
  received_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
begin
  if caller is null then
    raise exception 'You must be signed in to see a client''s credit.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.record_payment') then
    raise exception 'You do not have access to apply payments here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  return query
  select spendable.source, spendable.source_id, spendable.quote_id, spendable.quote_number,
    spendable.method, spendable.reference, spendable.currency_code, spendable.amount_minor,
    spendable.available_minor, spendable.received_at
  from (
    select 'payment'::text as source, receipt.id as source_id, null::uuid as quote_id,
      null::integer as quote_number, receipt.method, receipt.reference, receipt.currency_code,
      receipt.amount_minor::bigint as amount_minor,
      private.payment_event_available_minor(receipt.organization_id, receipt.id) as available_minor,
      receipt.created_at as received_at
    from public.client_payment_events as receipt
    where receipt.organization_id = target_organization_id
      and receipt.client_id = target_client_id
      and receipt.event_type = 'received'

    union all

    select 'deposit'::text, deposit.id, quote.id, quote.quote_number, deposit.method, deposit.reference,
      quote.currency_code, deposit.amount_minor::bigint,
      private.deposit_event_available_minor(deposit.organization_id, deposit.id),
      deposit.created_at
    from public.quote_deposit_events as deposit
    join public.quotes as quote
      on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
    where deposit.organization_id = target_organization_id
      and quote.client_id = target_client_id
      and deposit.event_type = 'received'
  ) as spendable
  where spendable.available_minor > 0
  order by spendable.received_at, spendable.source_id;
end;
$$;

comment on function public.client_spendable_credit(uuid, uuid) is
  'Lists the payments and quote deposits a client has given that still have money left to put on a bill, '
  'with how much is left on each.';

revoke all on function public.client_spendable_credit(uuid, uuid) from public;
revoke execute on function public.client_spendable_credit(uuid, uuid) from anon;
grant execute on function public.client_spendable_credit(uuid, uuid) to authenticated;
