-- Two read-only money/work rollups for the "No fake numbers" pass:
--
-- invoice_money_overview: the three KPI tiles above the Invoices list (Outstanding, Overdue, Collected this
-- month), for the whole organization. Mirrors the same is_effective_receivable predicate the Invoices list
-- and public.client_account_balance already use, so a bill's status label and its presence in these totals
-- never disagree. Gated on invoices.view_price like every other money surface -- a reader without it gets
-- null figures, never a wrong number.
--
-- client_work_summary: the three stat tiles at the top of a client's page (Lifetime billed, Open quotes,
-- Active jobs). Lifetime is gated on customers.view_financials, the permission already named for exactly
-- this ("See client lifetime revenue and balance"). Open quotes and Active jobs are gated on quotes.view and
-- jobs.view respectively, and an 'assigned' jobs.view scope counts only jobs the caller is assigned to --
-- the same narrowing every other Job report in this database already applies.

CREATE OR REPLACE FUNCTION "public"."invoice_money_overview"("target_organization_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $function$
declare
  caller uuid := (select auth.uid());
  today date;
  month_start date;
  currency text;
  outstanding_minor bigint;
  overdue_minor bigint;
  collected_minor bigint;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;

  select settings.currency_code into currency
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;

  if not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    return jsonb_build_object(
      'currency_code', coalesce(currency, 'USD'),
      'outstanding_minor', null,
      'overdue_minor', null,
      'collected_this_month_minor', null
    );
  end if;

  today := private.organization_today(target_organization_id);
  month_start := date_trunc('month', today)::date;

  -- The partial index on (organization_id, due_date) WHERE is_effective_receivable keeps this to the
  -- organization's open ledger, never its whole invoice history. marked_received_at is excluded on top of
  -- is_effective_receivable because a status-only closure reads "Paid" everywhere else in the product; it
  -- would be a fake number here too if it still counted as owed.
  select
    coalesce(sum(invoice.total_minor - coalesce(allocation.applied_minor, 0)), 0)::bigint,
    coalesce(sum(case when invoice.due_date < today
      then invoice.total_minor - coalesce(allocation.applied_minor, 0) else 0 end), 0)::bigint
  into outstanding_minor, overdue_minor
  from public.invoices as invoice
  left join lateral (
    select sum(case when entry.entry_type = 'applied'
      then entry.amount_minor else -entry.amount_minor end) as applied_minor
    from public.invoice_payment_allocations as entry
    where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
  ) as allocation on true
  where invoice.organization_id = target_organization_id
    and invoice.is_effective_receivable
    and invoice.marked_received_at is null;

  -- Money actually received this calendar month, net of anything since reversed -- the same "never counts a
  -- receipt twice" rule public.client_account_balance uses, just organization-wide and date-bounded by the
  -- (organization_id, payment_date) index instead of by client.
  select coalesce(sum(receipt.amount_minor), 0)::bigint into collected_minor
  from public.client_payment_events as receipt
  where receipt.organization_id = target_organization_id
    and receipt.event_type = 'received'
    and receipt.payment_date >= month_start
    and receipt.payment_date <= today
    and not exists (
      select 1 from public.client_payment_events as reversal
      where reversal.organization_id = receipt.organization_id
        and reversal.original_event_id = receipt.id
        and reversal.event_type = 'reversed'
    );

  return jsonb_build_object(
    'currency_code', coalesce(currency, 'USD'),
    'outstanding_minor', outstanding_minor,
    'overdue_minor', overdue_minor,
    'collected_this_month_minor', collected_minor
  );
end;
$function$;

ALTER FUNCTION "public"."invoice_money_overview"("target_organization_id" "uuid") OWNER TO "postgres";

COMMENT ON FUNCTION "public"."invoice_money_overview"("target_organization_id" "uuid") IS 'Outstanding, Overdue and Collected-this-month for the Invoices list KPI tiles. Same is_effective_receivable predicate as public.client_account_balance and public.invoice_status_counts; null money for a reader without invoices.view_price.';

REVOKE ALL ON FUNCTION "public"."invoice_money_overview"("target_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."invoice_money_overview"("target_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."invoice_money_overview"("target_organization_id" "uuid") TO "service_role";


CREATE OR REPLACE FUNCTION "public"."client_work_summary"("target_client_ids" "uuid"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $function$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
  can_view_money boolean;
  jobs_scope text;
  quotes_scope text;
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

  if not private.member_has_permission(org, caller, 'customers.view') then
    raise exception 'You do not have access to these clients.' using errcode = 'insufficient_privilege';
  end if;

  can_view_money := private.member_has_permission(org, caller, 'customers.view_financials');
  jobs_scope := private.member_permission_scope(org, caller, 'jobs.view');
  quotes_scope := private.member_permission_scope(org, caller, 'quotes.view');

  select coalesce(jsonb_object_agg(client.id::text, jsonb_build_object(
      'currency_code', settings.currency_code,
      'lifetime_billed_minor', case when can_view_money then billed.amount_minor else null end,
      'open_quotes_count', case when quotes_scope = 'none' then null else quotes.total end,
      'active_jobs_count', case when jobs_scope = 'none' then null else jobs.total end
    )), '{}'::jsonb)
  into answer
  from public.clients as client
  cross join public.organization_settings as settings
  -- Lifetime is everything ever actually billed: issued or recognized, and never a bill that was voided or
  -- superseded by a later one -- a cancelled bill never billed the client at all. Draft totals are excluded
  -- by the same issued/recognized check invoice_live_status uses to call a bill "Draft".
  cross join lateral (
    select coalesce(sum(invoice.total_minor), 0)::bigint as amount_minor
    from public.invoices as invoice
    where invoice.organization_id = client.organization_id
      and invoice.client_id = client.id
      and (invoice.issued_at is not null or invoice.recognized_at is not null)
      and invoice.voided_at is null
      and invoice.replaced_at is null
  ) as billed
  -- Open mirrors QUOTE_OVERVIEW_STATUSES: still live, one of the four the office is expected to act on.
  cross join lateral (
    select count(*)::bigint as total
    from public.quotes as quote
    where quote.organization_id = client.organization_id
      and quote.client_id = client.id
      and quote.status in ('draft', 'awaiting_response', 'changes_requested', 'approved')
  ) as quotes
  -- Active reads the stored status, not the richer Jobs-list derived status -- a closed job that still owes
  -- an invoice is "Requires invoicing" there, but it is no longer active work on this client's own summary.
  cross join lateral (
    select count(*)::bigint as total
    from public.jobs as job
    where job.organization_id = client.organization_id
      and job.client_id = client.id
      and job.status = 'active'
      and (jobs_scope <> 'assigned' or private.is_assigned_to_job(job.organization_id, job.id))
  ) as jobs
  where client.organization_id = org
    and client.id = any(target_client_ids)
    and settings.organization_id = org;

  return answer;
end;
$function$;

ALTER FUNCTION "public"."client_work_summary"("target_client_ids" "uuid"[]) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."client_work_summary"("target_client_ids" "uuid"[]) IS 'The Lifetime billed / Open quotes / Active jobs stats on a client''s page header. Lifetime is null without customers.view_financials; Open quotes and Active jobs are null without quotes.view / jobs.view, and an assigned-scope jobs.view member counts only jobs they are assigned to.';

REVOKE ALL ON FUNCTION "public"."client_work_summary"("target_client_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."client_work_summary"("target_client_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."client_work_summary"("target_client_ids" "uuid"[]) TO "service_role";
