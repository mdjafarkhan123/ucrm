-- The add-on preview answers one question and the whole answer is money: what the customer would pay if
-- they took these optional lines. `quotes.view` was the only gate, so a member who may open a quote but
-- not see its prices could read subtotal, discount, tax, total, and the deposit requirement out of it.
-- Jobber draws the same line - a member without the pricing permission never sees what the client pays -
-- and the sibling reader `quote_customer_preview` already withholds money without `quotes.view_price`.
-- Here there is nothing left to return once the money is withheld, so the call is refused instead.
create or replace function public.preview_quote_version_totals(
  target_quote_id uuid,
  selected_addon_ids uuid[] default '{}'::uuid[]
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_id uuid;
  calculated jsonb;
begin
  select * into quote_row from public.quotes where id = target_quote_id;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.view'
     ) then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  if not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.view_price'
  ) then
    raise exception 'You do not have access to the prices on this quote.'
      using errcode = 'insufficient_privilege';
  end if;

  version_id := coalesce(quote_row.draft_version_id, quote_row.current_published_version_id);
  if version_id is null then
    raise exception 'This quote has nothing to price yet.' using errcode = 'check_violation';
  end if;

  calculated := private.calculate_quote_version(version_id, selected_addon_ids);

  if private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.view_cost'
  ) then
    return calculated;
  end if;
  return private.quote_customer_totals(calculated);
end;
$$;

comment on function public.preview_quote_version_totals(uuid, uuid[]) is
  'What the customer would pay with these optional add-ons selected. Requires quotes.view and '
  'quotes.view_price; cost, profit, and margin are included only for quotes.view_cost.';
