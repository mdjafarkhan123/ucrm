-- The progress strip on every record page (Request > Quote > Job > Invoice > Paid): one call that starts from
-- any record in the chain and answers where the other steps are.
--
-- The links already exist and are one to one going down the line: a request has at most one quote
-- (quotes_request_lineage_idx), a quote at most one job (jobs_quote_lineage_idx), a request at most one job
-- (jobs_request_lineage_idx). Only the last step fans out: a job can have several invoices, joined through
-- invoice_sources (a standalone invoice has no source row, so it has no job). Every lookup below is an
-- index lookup by id, so the answer costs a handful of single-row reads however large the organization.
--
-- SECURITY DEFINER because an invoice's live status is worked out by a private function and invoice reads
-- are grant-gated. Nothing is returned that the caller may not open: every step is checked with the same
-- can_view helper the record's own page uses. A step that exists but is hidden from this caller comes back
-- as {"restricted": true} (the strip says it happened, without a link or detail). No money leaves here.

create or replace function public.record_chain(
  target_organization_id uuid,
  source_kind text,
  source_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  today date;
  v_request uuid;
  v_quote uuid;
  v_job uuid;
  v_invoice_root uuid;
  step_request jsonb;
  step_quote jsonb;
  step_job jsonb;
  step_invoices jsonb;
  row_data record;
begin
  if caller is null or not private.is_organization_member(target_organization_id) then
    raise exception 'You do not have access to this organization.' using errcode = 'insufficient_privilege';
  end if;
  if source_kind not in ('request', 'quote', 'job', 'invoice') then
    raise exception 'Unknown record kind.' using errcode = 'check_violation';
  end if;

  -- The record the caller stands on has to be one they may open; otherwise there is nothing to say.
  if source_kind = 'request' then
    if not private.can_view_request(target_organization_id, source_id) then return null; end if;
    v_request := source_id;
  elsif source_kind = 'quote' then
    if not private.can_view_quote(target_organization_id, source_id) then return null; end if;
    v_quote := source_id;
  elsif source_kind = 'job' then
    if not private.can_view_job(target_organization_id, source_id) then return null; end if;
    v_job := source_id;
  else
    if not private.can_view_invoice(target_organization_id, source_id) then return null; end if;
    select invoice.root_invoice_id into v_invoice_root
    from public.invoices as invoice
    where invoice.organization_id = target_organization_id and invoice.id = source_id;
    select source.job_id into v_job
    from public.invoice_sources as source
    where source.organization_id = target_organization_id and source.root_invoice_id = v_invoice_root
    order by source.created_at
    limit 1;
  end if;

  -- Up the line first, then down it, filling only what is still unknown.
  if v_job is not null then
    select job.quote_id, job.request_id into v_quote, v_request
    from public.jobs as job
    where job.organization_id = target_organization_id and job.id = v_job;
    -- job.quote_id / job.request_id are the job's own links; keep what the page already stood on.
    if source_kind = 'request' then v_request := source_id; end if;
    if source_kind = 'quote' then v_quote := source_id; end if;
  end if;
  if v_quote is not null and v_request is null then
    select quote.request_id into v_request
    from public.quotes as quote
    where quote.organization_id = target_organization_id and quote.id = v_quote;
  end if;
  if v_request is not null and v_quote is null then
    select quote.id into v_quote
    from public.quotes as quote
    where quote.organization_id = target_organization_id and quote.request_id = v_request;
  end if;
  if v_job is null and v_quote is not null then
    select job.id into v_job
    from public.jobs as job
    where job.organization_id = target_organization_id and job.quote_id = v_quote;
  end if;
  if v_job is null and v_request is not null then
    select job.id into v_job
    from public.jobs as job
    where job.organization_id = target_organization_id and job.request_id = v_request;
  end if;

  if v_request is not null then
    if private.can_view_request(target_organization_id, v_request) then
      select jsonb_build_object('id', r.id, 'status', r.status, 'created_at', r.created_at)
      into step_request
      from public.requests as r
      where r.organization_id = target_organization_id and r.id = v_request;
    else
      step_request := jsonb_build_object('restricted', true);
    end if;
  end if;

  if v_quote is not null then
    if private.can_view_quote(target_organization_id, v_quote) then
      select jsonb_build_object(
        'id', q.id, 'quote_number', q.quote_number, 'status', q.status,
        'sent_at', q.sent_at, 'decided_at', q.decided_at)
      into step_quote
      from public.quotes as q
      where q.organization_id = target_organization_id and q.id = v_quote;
    else
      step_quote := jsonb_build_object('restricted', true);
    end if;
  end if;

  if v_job is not null then
    if private.can_view_job(target_organization_id, v_job) then
      select jsonb_build_object(
        'id', j.id, 'job_number', j.job_number, 'status', j.status, 'closed_at', j.closed_at)
      into step_job
      from public.jobs as j
      where j.organization_id = target_organization_id and j.id = v_job;
    else
      step_job := jsonb_build_object('restricted', true);
    end if;
  end if;

  -- The job's invoices, newest bill in each replacement chain only. Skipped altogether for a caller who
  -- may not open invoices: they get the flag, not the numbers.
  if v_job is not null or source_kind = 'invoice' then
    if private.has_permission(target_organization_id, 'invoices.view') then
      today := private.organization_today(target_organization_id);
      select jsonb_build_object(
        'count', count(*),
        'paid_count', count(*) filter (where status = 'paid'),
        'primary', (
          array_agg(jsonb_build_object(
            'id', id, 'invoice_number', invoice_number, 'status', status,
            'issued_at', issued_at, 'due_date', due_date)
            order by (id = case when source_kind = 'invoice' then source_id end) desc nulls last,
                     created_at desc)
        )[1]
      )
      into step_invoices
      from (
        select
          invoice.id, invoice.invoice_number, invoice.issued_at, invoice.due_date, invoice.created_at,
          private.invoice_live_status(
            invoice.voided_at, invoice.written_off_at, invoice.issued_at, invoice.recognized_at,
            invoice.marked_received_at, invoice.total_minor, allocation.applied_minor,
            invoice.due_date, today) as status
        from public.invoices as invoice
        cross join lateral (
          select coalesce(sum(case when entry.entry_type = 'applied'
            then entry.amount_minor else -entry.amount_minor end), 0)::bigint as applied_minor
          from public.invoice_payment_allocations as entry
          where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
        ) as allocation
        where invoice.organization_id = target_organization_id
          and invoice.replaced_at is null
          and (
            invoice.id = case when source_kind = 'invoice' then source_id end
            or invoice.root_invoice_id in (
              select source.root_invoice_id
              from public.invoice_sources as source
              where source.organization_id = target_organization_id and source.job_id = v_job
            )
          )
      ) as invoices;
      if (step_invoices ->> 'count')::int = 0 then step_invoices := null; end if;
    else
      step_invoices := jsonb_build_object('restricted', true);
    end if;
  end if;

  return jsonb_build_object(
    'request', step_request,
    'quote', step_quote,
    'job', step_job,
    'invoices', step_invoices
  );
end;
$$;

comment on function public.record_chain(uuid, text, uuid) is
  'Where a request, quote, job or invoice stands on the line Request > Quote > Job > Invoice > Paid: the linked records, each only if the caller may open it. Feeds the progress strip on the record pages.';

revoke all on function public.record_chain(uuid, text, uuid) from public, anon;
grant execute on function public.record_chain(uuid, text, uuid) to authenticated, service_role;
