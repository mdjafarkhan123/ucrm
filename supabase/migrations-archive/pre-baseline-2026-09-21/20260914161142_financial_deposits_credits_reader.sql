-- CRM launch readiness, financial reconciliation Part 2: quote-deposit and remaining-credit reader.
--
-- Deposit receipts and reversals are cash events. Refunds stay in the payment-event ledger, while this
-- reader links their current total back to the original deposit and shows how much remains available after
-- both refunds and allocation activity. Deposit activity has no separate business date, so its calendar date
-- is the immutable created_at instant interpreted in the organization's timezone.

create index quote_deposit_events_report_created_idx
  on public.quote_deposit_events (organization_id, created_at, id);

create or replace function public.financial_deposit_credits_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_created_at timestamptz default null,
  cursor_event_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  event_id uuid,
  quote_id uuid,
  quote_number integer,
  quote_version_id uuid,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  event_type text,
  amount_minor bigint,
  cash_effect_minor bigint,
  currency_code text,
  method text,
  reference text,
  note text,
  reversed_event_id uuid,
  refunded_minor bigint,
  allocated_minor bigint,
  available_credit_minor bigint,
  actor_user_id uuid,
  activity_date date,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  zone text;
  window_start timestamptz;
  window_end timestamptz;
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
  if (cursor_created_at is null) <> (cursor_event_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select deposit.id, deposit.quote_id, quote.quote_number, deposit.quote_version_id, quote.client_id,
    client.display_name, client.company_name, deposit.event_type, deposit.amount_minor,
    (case when deposit.event_type = 'received' then deposit.amount_minor else -deposit.amount_minor end)::bigint,
    quote.currency_code, deposit.method, deposit.reference, deposit.note, deposit.reversed_event_id,
    case when deposit.event_type = 'received' then coalesce(refund.amount_minor, 0) else 0 end::bigint,
    case when deposit.event_type = 'received' then coalesce(allocation.amount_minor, 0) else 0 end::bigint,
    case when deposit.event_type = 'received'
      then coalesce(private.deposit_event_available_minor(deposit.organization_id, deposit.id), 0)
      else 0 end::bigint,
    deposit.actor_user_id, (deposit.created_at at time zone zone)::date, deposit.created_at
  from public.quote_deposit_events as deposit
  join public.quotes as quote
    on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
  join public.clients as client
    on client.organization_id = quote.organization_id and client.id = quote.client_id
  left join lateral (
    select sum(event.amount_minor)::bigint as amount_minor
    from public.client_payment_events as event
    where event.organization_id = deposit.organization_id
      and event.original_deposit_event_id = deposit.id
      and event.event_type = 'refunded'
      and not exists (
        select 1 from public.client_payment_events as correction
        where correction.organization_id = event.organization_id
          and correction.original_event_id = event.id
          and correction.event_type = 'reversed'
      )
  ) as refund on true
  left join lateral (
    select sum(case when entry.entry_type = 'applied'
      then entry.amount_minor else -entry.amount_minor end)::bigint as amount_minor
    from public.invoice_payment_allocations as entry
    where entry.organization_id = deposit.organization_id and entry.deposit_event_id = deposit.id
  ) as allocation on true
  where deposit.organization_id = target_organization_id
    and deposit.created_at >= window_start and deposit.created_at < window_end
    and (
      cursor_created_at is null
      or (sort_direction = 'asc'
        and (deposit.created_at, deposit.id) > (cursor_created_at, cursor_event_id))
      or (sort_direction = 'desc'
        and (deposit.created_at, deposit.id) < (cursor_created_at, cursor_event_id))
    )
  order by
    case when sort_direction = 'asc' then deposit.created_at end asc,
    case when sort_direction = 'asc' then deposit.id end asc,
    case when sort_direction = 'desc' then deposit.created_at end desc,
    case when sort_direction = 'desc' then deposit.id end desc
  limit resolved_limit;
end;
$$;

create or replace function public.financial_deposit_credits_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  received_minor bigint,
  reversed_minor bigint,
  cash_effect_minor bigint,
  refunded_minor bigint,
  allocated_minor bigint,
  available_credit_minor bigint,
  event_count bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  zone text;
  window_start timestamptz;
  window_end timestamptz;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;

  return query
  with source_rows as (
    select deposit.id, deposit.event_type, deposit.amount_minor,
      case when deposit.event_type = 'received' then coalesce((
        select sum(event.amount_minor)
        from public.client_payment_events as event
        where event.organization_id = deposit.organization_id
          and event.original_deposit_event_id = deposit.id
          and event.event_type = 'refunded'
          and not exists (
            select 1 from public.client_payment_events as correction
            where correction.organization_id = event.organization_id
              and correction.original_event_id = event.id
              and correction.event_type = 'reversed'
          )
      ), 0) else 0 end::bigint as refunded_minor,
      case when deposit.event_type = 'received' then coalesce((
        select sum(case when entry.entry_type = 'applied'
          then entry.amount_minor else -entry.amount_minor end)
        from public.invoice_payment_allocations as entry
        where entry.organization_id = deposit.organization_id and entry.deposit_event_id = deposit.id
      ), 0) else 0 end::bigint as allocated_minor,
      case when deposit.event_type = 'received'
        then coalesce(private.deposit_event_available_minor(deposit.organization_id, deposit.id), 0)
        else 0 end::bigint as available_credit_minor
    from public.quote_deposit_events as deposit
    where deposit.organization_id = target_organization_id
      and deposit.created_at >= window_start and deposit.created_at < window_end
  )
  select
    coalesce(sum(source.amount_minor) filter (where source.event_type = 'received'), 0)::bigint,
    coalesce(sum(source.amount_minor) filter (where source.event_type = 'reversed'), 0)::bigint,
    coalesce(sum(case when source.event_type = 'received'
      then source.amount_minor else -source.amount_minor end), 0)::bigint,
    coalesce(sum(source.refunded_minor), 0)::bigint,
    coalesce(sum(source.allocated_minor), 0)::bigint,
    coalesce(sum(source.available_credit_minor), 0)::bigint,
    count(*)::bigint
  from source_rows as source;
end;
$$;

comment on function public.financial_deposit_credits_page(uuid, date, date, timestamptz, uuid, integer, text) is
  'Keyset-paged immutable quote-deposit activity plus each receipt''s current refunded, allocated and '
  'available amounts. Requires Invoice financial visibility and explicit organization scope.';
comment on function public.financial_deposit_credits_summary(uuid, date, date) is
  'Whole-window quote-deposit cash activity and current disposition totals independent of the visible page.';

revoke all on function public.financial_deposit_credits_page(
  uuid, date, date, timestamptz, uuid, integer, text) from public, anon;
grant execute on function public.financial_deposit_credits_page(
  uuid, date, date, timestamptz, uuid, integer, text) to authenticated;
revoke all on function public.financial_deposit_credits_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_deposit_credits_summary(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
