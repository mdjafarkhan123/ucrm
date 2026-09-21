-- client_account_balance stopped honouring a reversed refund.
--
-- 20260905120000 made a refund that was later reversed ("recorded in error, taken back") stop counting as money
-- sent back, so the client's credit came back. 20261003100000 rewrote this function from an older copy and dropped
-- that condition, so a reversed refund kept reducing the client's available credit and account balance. The
-- receipt-level and report functions still handle it; this restores the same rule here and changes nothing else.

CREATE OR REPLACE FUNCTION public.client_account_balance(target_client_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_client_ids is null or cardinality(target_client_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct client.organization_id) into organizations
  from public.clients as client
  where client.id = any(target_client_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those clients do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'invoices.view') then
    raise exception 'You do not have access to these clients'' billing.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(org, caller, 'invoices.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(client.id::text, jsonb_build_object(
      'currency_code', settings.currency_code,
      'outstanding_minor', outstanding.amount_minor + coalesce(opening.receivable_minor, 0),
      'available_credit_minor', credit.amount_minor + coalesce(opening.credit_minor, 0),
      'account_balance_minor',
        (outstanding.amount_minor + coalesce(opening.receivable_minor, 0))
        - (credit.amount_minor + coalesce(opening.credit_minor, 0))
    )), '{}'::jsonb)
  into answer
  from public.clients as client
  cross join public.organization_settings as settings
  -- What the effective bills still ask for. The partial index on is_effective_receivable is what keeps this
  -- to the client's open ledger instead of their whole billing history.
  cross join lateral (
    select coalesce(sum(invoice.total_minor - coalesce(entry.applied_minor, 0)), 0)::bigint as amount_minor
    from public.invoices as invoice
    left join lateral (
      select sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end) as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id
        and entry.invoice_id = invoice.id
    ) as entry on true
    where invoice.organization_id = client.organization_id
      and invoice.client_id = client.id
      and invoice.is_effective_receivable
  ) as outstanding
  cross join lateral (
    select (
      -- Manual receipts that were not reversed away.
      coalesce((
        select sum(receipt.amount_minor)
        from public.client_payment_events as receipt
        where receipt.organization_id = client.organization_id
          and receipt.client_id = client.id
          and receipt.event_type = 'received'
          and not exists (
            select 1 from public.client_payment_events as correction
            where correction.organization_id = receipt.organization_id
              and correction.original_event_id = receipt.id
              and correction.event_type = 'reversed'
          )
      ), 0)
      -- Quote deposits, reused where they already live, minus the ones the quote workspace reversed.
      + coalesce((
        select sum(deposit.amount_minor)
        from public.quote_deposit_events as deposit
        join public.quotes as quote
          on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
        where deposit.organization_id = client.organization_id
          and quote.client_id = client.id
          and deposit.event_type = 'received'
          and not exists (
            select 1 from public.quote_deposit_events as reversal
            where reversal.organization_id = deposit.organization_id
              and reversal.reversed_event_id = deposit.id
          )
      ), 0)
      -- Money actually sent back is no longer the client's to spend, unless the refund itself was reversed.
      - coalesce((
        select sum(refund.amount_minor)
        from public.client_payment_events as refund
        where refund.organization_id = client.organization_id
          and refund.client_id = client.id
          and refund.event_type = 'refunded'
          and not exists (
            select 1 from public.client_payment_events as undo
            where undo.organization_id = refund.organization_id
              and undo.original_event_id = refund.id
              and undo.event_type = 'reversed'
          )
      ), 0)
      -- Money committed to a bill is not available, whichever kind of receipt it came from.
      - coalesce((
        select sum(case when entry.entry_type = 'applied'
          then entry.amount_minor else -entry.amount_minor end)
        from public.invoice_payment_allocations as entry
        where entry.organization_id = client.organization_id
          and entry.client_id = client.id
      ), 0)
    )::bigint as amount_minor
  ) as credit
  left join lateral (
    select receivable_minor, credit_minor
    from private.client_opening_balance_totals(org, array[client.id])
  ) as opening on true
  where client.organization_id = org
    and client.id = any(target_client_ids)
    and settings.organization_id = org;

  return answer;
end;
$function$;
