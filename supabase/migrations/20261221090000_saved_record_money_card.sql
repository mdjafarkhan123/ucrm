-- Batch 35 on saved records: the money summary card (concept.pen `vIjf0`, Jafar 2026-10-21) on the job and
-- invoice pages needs a few figures no reader sent yet.
--
-- job_costing gains `labor_minutes`: the crew hours behind the labour cost ("Labour · 14.5 h"), over the same
-- entries the labour cost already sums.
--
-- job_billing_summary: what has been invoiced of a job and what is still owed on it ("Invoiced $3,200 of
-- $8,000", "Still owed"). A bill counts once it is issued or recognised and has not been voided or replaced;
-- amounts are before tax, like the job revenue they sit beside. Owed is what is left on bills still collectable.
--
-- invoice_money_context: an invoice's place in its job and what it took from deposits ("Billed before",
-- "This invoice", "Deposit applied"), plus its profit from the job lines it was billed from.
--
-- Both are definer because they read across invoices, jobs and payment allocations, and both check the
-- permissions themselves: a reader without them gets null, never an error, so the record page still loads.
-- Their reads ride invoice_sources_job_idx / invoice_sources_root_idx, invoices_root_idx and
-- invoice_payment_allocations_invoice_idx.

CREATE OR REPLACE FUNCTION public.job_costing(target_organization_id uuid, target_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  zone text;
  window_start date;
  window_end date;
  labor_from timestamptz;
  labor_until timestamptz;
  unit_count integer := 0;
  period_price bigint;
  period_cost bigint;
  labor_cost bigint;
  unrated_count integer;
  has_time boolean;
  labor_minutes bigint;
  expense_cost bigint;
  has_labor_line boolean;
  item_cost bigint;
  revenue bigint;
  total_cost bigint;
  profit bigint;
  margin_bp integer;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  if not private.member_has_permission(target_organization_id, caller, 'jobs.view_cost') then
    raise exception 'You do not have access to this job''s costs.' using errcode = 'insufficient_privilege';
  end if;

  if current_job.price_basis = 'job_total' then
    select coalesce(sum(entry.cost_total_minor), 0),
           count(*) filter (where entry.cost_per_hour_minor is null),
           count(*) > 0,
           coalesce(sum(entry.minutes), 0)
    into labor_cost, unrated_count, has_time, labor_minutes
    from public.job_time_entries as entry
    where entry.organization_id = target_organization_id
      and entry.job_id = target_job_id;

    select coalesce(sum(expense.total_minor), 0)
    into expense_cost
    from public.job_expenses as expense
    where expense.organization_id = target_organization_id
      and expense.job_id = target_job_id;

    select exists (
      select 1
      from public.job_line_items as line
      where line.organization_id = target_organization_id
        and line.job_id = target_job_id
        and line.is_labor
    ) into has_labor_line;

    revenue := current_job.total_minor - current_job.tax_minor;
    total_cost := current_job.cost_minor + labor_cost + expense_cost;
    profit := revenue - total_cost;
    margin_bp := case when revenue > 0
      then round(profit::numeric * 10000 / revenue)::integer
      else null
    end;

    return jsonb_build_object(
      'costing_basis', 'one_off',
      'job_closed', current_job.status <> 'active',
      'revenue_minor', revenue,
      'item_cost_minor', current_job.cost_minor,
      'labor_cost_minor', labor_cost,
      'labor_minutes', labor_minutes,
      'expense_cost_minor', expense_cost,
      'total_cost_minor', total_cost,
      'profit_minor', profit,
      'margin_basis_points', margin_bp,
      'unrated_labor_count', unrated_count,
      'labor_line_and_time', has_labor_line and has_time
    );
  end if;

  window_end := private.organization_today(target_organization_id);
  window_start := window_end - 29;

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');

  labor_from := (window_start::timestamp) at time zone zone;
  labor_until := ((window_end + 1)::timestamp) at time zone zone;

  if current_job.price_basis = 'per_visit' then
    with in_window as (
      select visit.id
      from public.job_visits as visit
      where visit.organization_id = target_organization_id
        and visit.job_id = target_job_id
        and visit.completed_at is not null
        and visit.visit_date between window_start and window_end
    ),
    priced_lines as (
      select line.line_total_minor, line.quantity, line.unit_cost_minor, line.is_labor
      from in_window
      cross join lateral private.job_visit_effective_lines(
        target_organization_id, target_job_id, in_window.id
      ) as line
      where line.line_kind = 'priced'
    )
    select
      (select count(*) from in_window)::integer,
      coalesce(sum(priced_lines.line_total_minor), 0),
      coalesce(sum(public.pricing_line_total_minor(
        priced_lines.quantity, priced_lines.unit_cost_minor
      )), 0),
      coalesce(bool_or(priced_lines.is_labor), false)
    into unit_count, revenue, item_cost, has_labor_line
    from priced_lines;

  else
    select count(*)::integer
    into unit_count
    from public.job_invoice_reminders as reminder
    where reminder.organization_id = target_organization_id
      and reminder.job_id = target_job_id
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and reminder.due_on between window_start and window_end;

    select coalesce(sum(line.line_total_minor), 0),
           coalesce(sum(line.line_cost_total_minor), 0),
           coalesce(bool_or(line.is_labor), false)
    into period_price, period_cost, has_labor_line
    from public.job_line_items as line
    where line.organization_id = target_organization_id
      and line.job_id = target_job_id
      and line.line_kind = 'priced';

    if unit_count > 0 then
      revenue := period_price * unit_count;
      item_cost := period_cost * unit_count;
    else
      revenue := null;
      item_cost := 0;
    end if;
  end if;

  select coalesce(sum(entry.cost_total_minor), 0),
         count(*) filter (where entry.cost_per_hour_minor is null),
         count(*) > 0,
         coalesce(sum(entry.minutes), 0)
  into labor_cost, unrated_count, has_time, labor_minutes
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and entry.started_at >= labor_from
    and entry.started_at < labor_until;

  select coalesce(sum(expense.total_minor), 0)
  into expense_cost
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and expense.expense_date between window_start and window_end;

  total_cost := item_cost + labor_cost + expense_cost;
  profit := case when revenue is null then null else revenue - total_cost end;
  margin_bp := case when revenue is not null and revenue > 0
    then round((revenue - total_cost)::numeric * 10000 / revenue)::integer
    else null
  end;

  return jsonb_build_object(
    'costing_basis', current_job.price_basis,
    'job_closed', current_job.status <> 'active',
    'window_start', window_start,
    'window_end', window_end,
    'unit_kind', case when current_job.price_basis = 'per_visit' then 'visits' else 'periods' end,
    'unit_count', unit_count,
    'revenue_minor', revenue,
    'item_cost_minor', item_cost,
    'labor_cost_minor', labor_cost,
    'labor_minutes', labor_minutes,
    'expense_cost_minor', expense_cost,
    'total_cost_minor', total_cost,
    'profit_minor', profit,
    'margin_basis_points', margin_bp,
    'unrated_labor_count', unrated_count,
    'labor_line_and_time', has_labor_line and has_time
  );
end;
$function$;

create or replace function public.job_billing_summary(target_organization_id uuid, target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  answer jsonb;
begin
  if caller is null
    or not private.member_job_is_visible(target_organization_id, caller, target_job_id)
    or not private.member_has_permission(target_organization_id, caller, 'invoices.view')
    or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    return null;
  end if;

  with chains as (
    select distinct source.root_invoice_id
    from public.invoice_sources as source
    where source.organization_id = target_organization_id
      and source.job_id = target_job_id
  ),
  billed as (
    select invoice.id, invoice.subtotal_minor - invoice.discount_minor as before_tax_minor,
           invoice.total_minor, invoice.is_effective_receivable
    from chains
    join public.invoices as invoice
      on invoice.organization_id = target_organization_id
     and invoice.root_invoice_id = chains.root_invoice_id
    where (invoice.issued_at is not null or invoice.recognized_at is not null)
      and invoice.voided_at is null
      and invoice.replaced_at is null
  )
  select jsonb_build_object(
    'invoice_count', count(*),
    'invoiced_minor', coalesce(sum(billed.before_tax_minor), 0),
    'owed_minor', coalesce(sum(
      case when billed.is_effective_receivable then greatest(billed.total_minor - applied.applied_minor, 0) else 0 end
    ), 0)
  )
  into answer
  from billed
  cross join lateral (
    select coalesce(sum(case when entry.entry_type = 'applied' then entry.amount_minor else -entry.amount_minor end), 0)::bigint
      as applied_minor
    from public.invoice_payment_allocations as entry
    where entry.organization_id = target_organization_id and entry.invoice_id = billed.id
  ) as applied;

  return answer;
end;
$$;

create or replace function public.invoice_money_context(target_organization_id uuid, target_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  job_ids uuid[];
  the_job public.jobs;
  deposit_minor bigint;
  billed_before bigint;
  cost bigint;
  can_see_job boolean := false;
begin
  if caller is null
    or not private.member_has_permission(target_organization_id, caller, 'invoices.view')
    or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    return null;
  end if;

  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;
  if not found then
    return null;
  end if;

  select coalesce(sum(case when entry.entry_type = 'applied' then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into deposit_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = target_organization_id
    and entry.invoice_id = target_invoice_id
    and entry.deposit_event_id is not null;

  select array_agg(distinct source.job_id) into job_ids
  from public.invoice_sources as source
  where source.organization_id = target_organization_id
    and source.root_invoice_id = invoice_row.root_invoice_id
    and source.job_id is not null;

  -- A share of the job only reads honestly when the bill comes from exactly one job the reader may price.
  if cardinality(job_ids) = 1
    and private.member_job_is_visible(target_organization_id, caller, job_ids[1])
    and private.member_has_permission(target_organization_id, caller, 'jobs.view_price') then
    select * into the_job
    from public.jobs
    where organization_id = target_organization_id and id = job_ids[1];
    can_see_job := found;
  end if;

  if can_see_job then
    select coalesce(sum(other.subtotal_minor - other.discount_minor), 0)
    into billed_before
    from (
      select distinct source.root_invoice_id
      from public.invoice_sources as source
      where source.organization_id = target_organization_id
        and source.job_id = the_job.id
        and source.root_invoice_id <> invoice_row.root_invoice_id
    ) as chains
    join public.invoices as other
      on other.organization_id = target_organization_id
     and other.root_invoice_id = chains.root_invoice_id
    where (other.issued_at is not null or other.recognized_at is not null)
      and other.voided_at is null
      and other.replaced_at is null;
  end if;

  -- Invoice lines keep no cost of their own; a line billed from a job line carries that line's unit cost.
  if private.member_has_permission(target_organization_id, caller, 'jobs.view_cost') then
    select coalesce(sum(public.pricing_line_total_minor(line.quantity, source_line.unit_cost_minor)), 0)
    into cost
    from public.invoice_lines as line
    join public.job_line_items as source_line
      on source_line.organization_id = target_organization_id and source_line.id = line.source_job_line_id
    where line.organization_id = target_organization_id
      and line.invoice_id = target_invoice_id
      and line.line_kind = 'priced';
  end if;

  return jsonb_build_object(
    'deposit_applied_minor', deposit_minor,
    'job_id', case when can_see_job then the_job.id end,
    'job_number', case when can_see_job then the_job.job_number end,
    'job_revenue_minor', case when can_see_job then the_job.total_minor - the_job.tax_minor end,
    'billed_before_minor', case when can_see_job then billed_before end,
    'cost_minor', cost
  );
end;
$$;

revoke all on function public.job_billing_summary(uuid, uuid) from public, anon;
revoke all on function public.invoice_money_context(uuid, uuid) from public, anon;
grant execute on function public.job_billing_summary(uuid, uuid) to authenticated;
grant execute on function public.invoice_money_context(uuid, uuid) to authenticated;
