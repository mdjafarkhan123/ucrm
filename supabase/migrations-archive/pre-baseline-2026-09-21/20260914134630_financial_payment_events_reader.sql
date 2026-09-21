-- CRM launch readiness, financial reconciliation Part 2: immutable payment-event reader.
--
-- This reader exposes the manual payment ledger exactly as recorded. Receipts, refunds and corrections keep
-- their own business dates and stable IDs; allocation entries deliberately stay in their separate ledger.
-- A reversal has the opposite cash effect of the row it corrects, so reversing a mistaken refund restores
-- cash while reversing a mistaken receipt removes it. Quote-deposit receipts remain in their own source and
-- will be reported by the deposit reader; refunds of those deposits are disclosed here with their source ID.

create index client_payment_events_report_date_idx
  on public.client_payment_events (organization_id, payment_date, id);

create or replace function public.financial_payment_events_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_event_date date default null,
  cursor_event_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  event_id uuid,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  event_type text,
  original_event_type text,
  event_date date,
  amount_minor bigint,
  cash_effect_minor bigint,
  currency_code text,
  method text,
  reference text,
  note text,
  original_event_id uuid,
  original_deposit_event_id uuid,
  actor_user_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  resolved_limit integer;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_event_date is null) <> (cursor_event_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select event.id, event.client_id, client.display_name, client.company_name, event.event_type,
    original.event_type, event.payment_date, event.amount_minor,
    case
      when event.event_type = 'received' then event.amount_minor
      when event.event_type = 'refunded' then -event.amount_minor
      when original.event_type = 'refunded' then event.amount_minor
      else -event.amount_minor
    end::bigint,
    event.currency_code, event.method, event.reference, event.note, event.original_event_id,
    event.original_deposit_event_id, event.actor_user_id, event.created_at
  from public.client_payment_events as event
  join public.clients as client
    on client.organization_id = event.organization_id and client.id = event.client_id
  left join public.client_payment_events as original
    on original.organization_id = event.organization_id and original.id = event.original_event_id
  where event.organization_id = target_organization_id
    and event.payment_date >= report_from and event.payment_date < report_to
    and (
      cursor_event_date is null
      or (sort_direction = 'asc' and (event.payment_date, event.id) > (cursor_event_date, cursor_event_id))
      or (sort_direction = 'desc' and (event.payment_date, event.id) < (cursor_event_date, cursor_event_id))
    )
  order by
    case when sort_direction = 'asc' then event.payment_date end asc,
    case when sort_direction = 'asc' then event.id end asc,
    case when sort_direction = 'desc' then event.payment_date end desc,
    case when sort_direction = 'desc' then event.id end desc
  limit resolved_limit;
end;
$$;

create or replace function public.financial_payment_events_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  received_minor bigint,
  refunded_minor bigint,
  reversed_receipt_minor bigint,
  reversed_refund_minor bigint,
  cash_effect_minor bigint,
  event_count bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  return query
  select
    coalesce(sum(event.amount_minor) filter (where event.event_type = 'received'), 0)::bigint,
    coalesce(sum(event.amount_minor) filter (where event.event_type = 'refunded'), 0)::bigint,
    coalesce(sum(event.amount_minor) filter (
      where event.event_type = 'reversed' and original.event_type = 'received'
    ), 0)::bigint,
    coalesce(sum(event.amount_minor) filter (
      where event.event_type = 'reversed' and original.event_type = 'refunded'
    ), 0)::bigint,
    coalesce(sum(case
      when event.event_type = 'received' then event.amount_minor
      when event.event_type = 'refunded' then -event.amount_minor
      when original.event_type = 'refunded' then event.amount_minor
      else -event.amount_minor
    end), 0)::bigint,
    count(*)::bigint
  from public.client_payment_events as event
  left join public.client_payment_events as original
    on original.organization_id = event.organization_id and original.id = event.original_event_id
  where event.organization_id = target_organization_id
    and event.payment_date >= report_from and event.payment_date < report_to;
end;
$$;

comment on function public.financial_payment_events_page(uuid, date, date, date, uuid, integer, text) is
  'Keyset-paged immutable manual payment events on their own business dates. Requires invoices.view and '
  'invoices.view_price, scopes every row to one organization, and keeps allocations outside cash events.';
comment on function public.financial_payment_events_summary(uuid, date, date) is
  'Whole-window manual payment-event totals independent of the visible page. Reversals carry the opposite '
  'cash effect of the receipt or refund they correct.';

revoke all on function public.financial_payment_events_page(uuid, date, date, date, uuid, integer, text)
  from public, anon;
grant execute on function public.financial_payment_events_page(uuid, date, date, date, uuid, integer, text)
  to authenticated;
revoke all on function public.financial_payment_events_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_payment_events_summary(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
