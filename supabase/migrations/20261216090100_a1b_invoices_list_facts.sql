-- A1b slice 3: the Invoices list shows what its Pencil frame shows (classic.pen `aBctI`, Jafar 2026-10-16).
--
-- invoice_list_facts: the strip under the Getting paid tiles -- average days to get paid over the past 30
-- days (Jobber's "average time to get paid": issue date to the day the invoice was paid in full) and whether
-- overdue reminders are on. invoice_list_views: "Viewed N times" / "Not opened yet" for one page of rows.
--
-- SECURITY DEFINER for the same reason as the quote functions: invoice_access_links has RLS with no policy and
-- recipes need automations.view. Both check invoices.view themselves. Neither returns money.
--
-- Paid-in-full moments come from two places: the allocation that brought the applied total up to the invoice
-- total (allocations ride their (organization_id, created_at) report index), and a status-only "marked
-- received" closure, which gets a small partial index here so it never scans the invoice history.

create index if not exists invoices_marked_received_idx
  on public.invoices (organization_id, marked_received_at)
  where marked_received_at is not null;

create or replace function public.invoice_list_facts(target_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  today date;
  zone text;
  window_start timestamptz;
  paid_count bigint;
  average_days numeric;
  reminder_days integer;
  reminders_on boolean;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  today := private.organization_today(target_organization_id);
  window_start := ((today - 29)::timestamp at time zone zone);

  with touched as (
    -- Invoices that took money in the window, and invoices closed by hand in it.
    select distinct allocation.invoice_id
    from public.invoice_payment_allocations as allocation
    where allocation.organization_id = target_organization_id
      and allocation.created_at >= window_start
    union
    select invoice.id
    from public.invoices as invoice
    where invoice.organization_id = target_organization_id
      and invoice.marked_received_at >= window_start
  ),
  paid as (
    select
      invoice.issue_date,
      coalesce(invoice.marked_received_at, settled.settled_at) as paid_at
    from touched
    join public.invoices as invoice
      on invoice.organization_id = target_organization_id and invoice.id = touched.invoice_id
    left join lateral (
      -- The last moment the running applied total crossed up to the invoice total: a payment later taken back
      -- and paid again counts from the second payment.
      select crossing.created_at as settled_at
      from (
        select
          running.created_at,
          running.applied_minor,
          lag(running.applied_minor, 1, 0::numeric) over (order by running.created_at, running.id) as before_minor
        from (
          select
            entry.id,
            entry.created_at,
            sum(case when entry.entry_type = 'applied' then entry.amount_minor else -entry.amount_minor end)
              over (order by entry.created_at, entry.id) as applied_minor
          from public.invoice_payment_allocations as entry
          where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
        ) as running
      ) as crossing
      where crossing.applied_minor >= invoice.total_minor
        and crossing.before_minor < invoice.total_minor
      order by crossing.created_at desc
      limit 1
    ) as settled on true
    where invoice.voided_at is null
      and invoice.written_off_at is null
      and invoice.replaced_at is null
      and (invoice.issued_at is not null or invoice.recognized_at is not null)
      and invoice.total_minor > 0
      and (
        invoice.marked_received_at is not null
        or (select coalesce(sum(case when entry.entry_type = 'applied' then entry.amount_minor
                                     else -entry.amount_minor end), 0)
            from public.invoice_payment_allocations as entry
            where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id)
           >= invoice.total_minor
      )
  )
  select
    count(*),
    -- A deposit taken before the invoice was issued counts as paid on the day it was issued, never earlier.
    avg(greatest((paid.paid_at at time zone zone)::date - paid.issue_date, 0))
  into paid_count, average_days
  from paid
  where paid.paid_at >= window_start;

  select
    true,
    coalesce((version.definition -> 'trigger' -> 'config' ->> 'days_after_due')::integer, 1)
  into reminders_on, reminder_days
  from public.automation_recipes as recipe
  join public.automation_recipe_versions as version on version.id = recipe.current_version_id
  where recipe.organization_id = target_organization_id
    and recipe.status = 'active'
    and recipe.active_trigger_key = 'invoice.past_due'
  order by version.activated_at, recipe.id
  limit 1;

  return jsonb_build_object(
    'paid_count', paid_count,
    'average_days_to_paid', case when paid_count > 0 then round(average_days)::integer end,
    'overdue_reminders_on', coalesce(reminders_on, false),
    'overdue_reminder_days_after_due', reminder_days
  );
end;
$$;

comment on function public.invoice_list_facts(uuid) is
  'The Invoices list facts strip: average days from issue date to paid in full for invoices paid in the past 30 days, and the active overdue reminder timing. Needs invoices.view; returns no money.';

create or replace function public.invoice_list_views(target_organization_id uuid, target_invoice_ids uuid[])
returns table (invoice_id uuid, view_count integer, emailed boolean)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  if target_invoice_ids is null or cardinality(target_invoice_ids) = 0 then
    return;
  end if;
  if cardinality(target_invoice_ids) > 100 then
    raise exception 'Ask for at most 100 invoices at a time.' using errcode = 'check_violation';
  end if;

  -- Every link the client was ever sent for the invoice counts: a re-sent link replaces the old one, but the
  -- client opening the first email still opened the bill.
  return query
  select link.invoice_id, sum(link.view_count)::integer, true
  from public.invoice_access_links as link
  where link.organization_id = target_organization_id
    and link.invoice_id = any(target_invoice_ids)
  group by link.invoice_id;
end;
$$;

comment on function public.invoice_list_views(uuid, uuid[]) is
  'How often the client opened each invoice on one page of the Invoices list (at most 100). Invoices never emailed have no row. Needs invoices.view.';

revoke all on function public.invoice_list_facts(uuid) from public, anon;
revoke all on function public.invoice_list_views(uuid, uuid[]) from public, anon;
grant execute on function public.invoice_list_facts(uuid) to authenticated, service_role;
grant execute on function public.invoice_list_views(uuid, uuid[]) to authenticated, service_role;
