-- CRM launch readiness, financial reconciliation Part 2: payment-allocation ledger reader.
--
-- Allocations are activity, not cash: applying money increases the amount committed to invoices and
-- unapplying it decreases that amount. Their activity date is the immutable created_at instant interpreted
-- in the organization's timezone. The timestamp remains in the result so exports preserve exact ordering.

create index invoice_payment_allocations_report_created_idx
  on public.invoice_payment_allocations (organization_id, created_at, id);

create or replace function public.financial_payment_allocations_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_created_at timestamptz default null,
  cursor_allocation_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  allocation_id uuid,
  invoice_id uuid,
  invoice_number integer,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  entry_type text,
  amount_minor bigint,
  allocation_effect_minor bigint,
  currency_code text,
  source_type text,
  source_event_id uuid,
  reversed_allocation_id uuid,
  reason text,
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
  if (cursor_created_at is null) <> (cursor_allocation_id is null) then
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
  select allocation.id, allocation.invoice_id, allocation.invoice_number, allocation.client_id,
    client.display_name, client.company_name, allocation.entry_type, allocation.amount_minor,
    (case when allocation.entry_type = 'applied'
      then allocation.amount_minor else -allocation.amount_minor end)::bigint,
    allocation.currency_code,
    case when allocation.payment_event_id is not null then 'payment' else 'quote_deposit' end::text,
    coalesce(allocation.payment_event_id, allocation.deposit_event_id), allocation.reversed_allocation_id,
    allocation.reason, allocation.actor_user_id, (allocation.created_at at time zone zone)::date,
    allocation.created_at
  from public.invoice_payment_allocations as allocation
  join public.clients as client
    on client.organization_id = allocation.organization_id and client.id = allocation.client_id
  where allocation.organization_id = target_organization_id
    and allocation.created_at >= window_start and allocation.created_at < window_end
    and (
      cursor_created_at is null
      or (sort_direction = 'asc'
        and (allocation.created_at, allocation.id) > (cursor_created_at, cursor_allocation_id))
      or (sort_direction = 'desc'
        and (allocation.created_at, allocation.id) < (cursor_created_at, cursor_allocation_id))
    )
  order by
    case when sort_direction = 'asc' then allocation.created_at end asc,
    case when sort_direction = 'asc' then allocation.id end asc,
    case when sort_direction = 'desc' then allocation.created_at end desc,
    case when sort_direction = 'desc' then allocation.id end desc
  limit resolved_limit;
end;
$$;

create or replace function public.financial_payment_allocations_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  applied_minor bigint,
  unapplied_minor bigint,
  net_allocated_minor bigint,
  entry_count bigint
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
  select
    coalesce(sum(allocation.amount_minor) filter (where allocation.entry_type = 'applied'), 0)::bigint,
    coalesce(sum(allocation.amount_minor) filter (where allocation.entry_type = 'unapplied'), 0)::bigint,
    coalesce(sum(case when allocation.entry_type = 'applied'
      then allocation.amount_minor else -allocation.amount_minor end), 0)::bigint,
    count(*)::bigint
  from public.invoice_payment_allocations as allocation
  where allocation.organization_id = target_organization_id
    and allocation.created_at >= window_start and allocation.created_at < window_end;
end;
$$;

comment on function public.financial_payment_allocations_page(uuid, date, date, timestamptz, uuid, integer, text) is
  'Keyset-paged immutable allocation activity in the organization timezone. Requires invoices.view and '
  'invoices.view_price and explicitly scopes every row to one organization.';
comment on function public.financial_payment_allocations_summary(uuid, date, date) is
  'Whole-window applied, unapplied and net allocation activity independent of the visible page.';

revoke all on function public.financial_payment_allocations_page(
  uuid, date, date, timestamptz, uuid, integer, text) from public, anon;
grant execute on function public.financial_payment_allocations_page(
  uuid, date, date, timestamptz, uuid, integer, text) to authenticated;
revoke all on function public.financial_payment_allocations_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_payment_allocations_summary(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
