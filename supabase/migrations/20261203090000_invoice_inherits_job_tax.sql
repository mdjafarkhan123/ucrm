-- An invoice raised from a job starts with the tax that job was priced with.
-- Found in the multi-industry connected proof (B12): the quote's 8% tax reached the job but not the invoice.
-- Proof: supabase/tests/database/invoice_inherits_job_tax.sql

CREATE OR REPLACE FUNCTION public.claim_invoice_sources(target_organization_id uuid, target_invoice_id uuid, expected_revision integer, new_sources jsonb, new_idempotency_key text, new_request_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  invoice_row public.invoices;
  property_count integer;
  requested_job_count integer;
  matched_job_count integer;
  entry record;
  reminder_row public.job_invoice_reminders;
  period_start date;
  period_end date;
  visit_row public.job_visits;
  schedule_item_row public.job_payment_schedule_items;
  claimed_count integer := 0;
  consumed_count integer := 0;
  job_tax record;
  tax_applied integer;
begin
  if caller is null then
    raise exception 'You must be signed in to bill work.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to bill work here.' using errcode = 'insufficient_privilege';
  end if;

  if new_sources is null or jsonb_typeof(new_sources) <> 'array'
     or jsonb_array_length(new_sources) = 0 then
    raise exception 'Choose at least one piece of work to bill.' using errcode = 'check_violation';
  end if;
  -- The bounded batch Part 2 sized. A larger selection is split rather than held under these locks.
  if jsonb_array_length(new_sources) > 100 then
    raise exception 'An invoice can cover at most 100 pieces of work at once.'
      using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'claim_invoice_sources', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision, 'invoices.create'
  );

  if invoice_row.issued_at is not null or invoice_row.recognized_at is not null then
    raise exception 'This bill has already been issued, so the work on it is settled.'
      using errcode = 'check_violation',
      hint = 'Correct the invoice instead; a correction carries the same work forward.';
  end if;
  -- A successor already inherits its chain's claims. Letting it add more would make a correction a way to
  -- bill new work under an old bill's history.
  if invoice_row.id is distinct from invoice_row.root_invoice_id then
    raise exception 'This invoice replaces another one, so it already covers that bill''s work.'
      using errcode = 'check_violation';
  end if;

  property_count := jsonb_array_length(invoice_row.service_properties);

  -- Lock every job this call touches, in id order, before touching any visit. That is the lock order the
  -- job and schedule commands already use, so an invoice and a visit reschedule cannot deadlock each other.
  select count(distinct source.job_id) into requested_job_count
  from jsonb_array_elements(new_sources) as element(value)
  cross join lateral (select nullif(element.value->>'job_id', '')::uuid as job_id) as source;

  -- The lock itself, as its own statement: row locking is not allowed inside a subquery, and the counting
  -- below is a separate question from the ordering that keeps this deadlock-free.
  perform 1
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id in (
      select nullif(element.value->>'job_id', '')::uuid
      from jsonb_array_elements(new_sources) as element(value)
    )
  order by job.id
  for share;

  select count(*) into matched_job_count
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.client_id = invoice_row.client_id
    and job.id in (
      select nullif(element.value->>'job_id', '')::uuid
      from jsonb_array_elements(new_sources) as element(value)
    );

  if requested_job_count = 0 then
    raise exception 'Every piece of billable work belongs to a job.' using errcode = 'check_violation';
  end if;
  if matched_job_count <> requested_job_count then
    raise exception 'One of those jobs does not belong to this invoice''s client.'
      using errcode = 'check_violation';
  end if;

  for entry in
    select
      coalesce(element.value->>'kind', '') as kind,
      nullif(element.value->>'job_id', '')::uuid as job_id,
      nullif(element.value->>'visit_id', '')::uuid as visit_id,
      nullif(element.value->>'reminder_id', '')::uuid as reminder_id,
      nullif(element.value->>'installment_number', '')::integer as installment_number,
      nullif(element.value->>'installment_id', '')::uuid as installment_id,
      nullif(element.value->>'service_property_index', '')::integer as service_property_index
    from jsonb_array_elements(new_sources) as element(value)
    -- A stable processing order so two concurrent batches over overlapping work queue behind each other
    -- rather than each holding half of what the other needs.
    order by 2, 1, 3, 4, 5
  loop
    if entry.kind not in ('job_total', 'visit', 'reminder_period', 'installment') then
      raise exception 'Billable work is a whole job, a visit, a billing period or an installment.'
        using errcode = 'check_violation';
    end if;
    if entry.job_id is null then
      raise exception 'Every piece of billable work names the job it belongs to.'
        using errcode = 'check_violation';
    end if;
    if entry.kind = 'installment' and (entry.installment_number is null or entry.installment_id is null) then
      raise exception 'An installment claim needs its position and identity in the payment schedule.'
        using errcode = 'check_violation';
    end if;
    if entry.service_property_index is not null
       and (entry.service_property_index < 0 or entry.service_property_index >= property_count) then
      raise exception 'That work points at a service address this invoice does not carry.'
        using errcode = 'check_violation';
    end if;

    -- The two exclusive ways to bill one job. Checked before the insert so the contractor gets a sentence
    -- rather than a unique-index violation.
    if entry.kind = 'job_total' then
      if exists (
        select 1 from public.invoice_sources as claim
        where claim.organization_id = target_organization_id and claim.job_id = entry.job_id
      ) then
        raise exception 'Some of this job''s work has already been billed, so it cannot be billed as a whole.'
          using errcode = 'unique_violation',
          hint = 'Bill the remaining visits or periods instead, or void the invoice that already covers it.';
      end if;
    elsif exists (
      select 1 from public.invoice_sources as claim
      where claim.organization_id = target_organization_id
        and claim.job_id = entry.job_id
        and claim.source_kind = 'job_total'
    ) then
      raise exception 'This whole job has already been billed on another invoice.'
        using errcode = 'unique_violation';
    end if;

    if entry.kind = 'visit' then
      select * into visit_row
      from public.job_visits
      where organization_id = target_organization_id
        and id = entry.visit_id
        and job_id = entry.job_id
      for update;
      if not found then
        raise exception 'That visit does not belong to the job being billed.' using errcode = 'P0404';
      end if;

    elsif entry.kind = 'reminder_period' then
      select * into reminder_row
      from public.job_invoice_reminders
      where organization_id = target_organization_id
        and id = entry.reminder_id
        and job_id = entry.job_id
      for update;
      if not found then
        raise exception 'That billing reminder does not belong to the job being billed.'
          using errcode = 'P0404';
      end if;
      if reminder_row.reminder_kind not in ('monthly_last_day', 'custom_date') then
        raise exception 'That reminder covers a single visit, so bill the visit itself.'
          using errcode = 'check_violation';
      end if;

      -- The period's boundaries come from the reminder rows themselves, never from the clock: it runs from
      -- the day after the previous billing reminder up to and including this one's date.
      period_end := reminder_row.due_on;
      select max(previous.due_on) into period_start
      from public.job_invoice_reminders as previous
      where previous.organization_id = target_organization_id
        and previous.job_id = entry.job_id
        and previous.reminder_kind in ('monthly_last_day', 'custom_date')
        and previous.due_on < period_end;
      period_start := coalesce(period_start + 1, '-infinity'::date);

    elsif entry.kind = 'installment' then
      -- The amount is locked by `create_installment_invoice` before this claim is ever attempted, in the
      -- same transaction. Nothing else ever writes `locked_amount_minor`, so seeing it unset here means this
      -- claim was reached some other way — a stage cannot be billed before its amount is final.
      select * into schedule_item_row
      from public.job_payment_schedule_items
      where organization_id = target_organization_id
        and id = entry.installment_id
        and job_id = entry.job_id
      for update;
      if not found then
        raise exception 'That payment stage does not belong to the job being billed.'
          using errcode = 'P0404';
      end if;
      if schedule_item_row.locked_amount_minor is null then
        raise exception 'That payment stage has not been priced and locked yet.'
          using errcode = 'check_violation',
          hint = 'Create the invoice from the job''s Billing card so its amount is locked first.';
      end if;
    end if;

    begin
      insert into public.invoice_sources (
        organization_id, root_invoice_id, client_id, source_kind,
        job_id, visit_id, reminder_id, installment_number, installment_id, service_property_index, claimed_by
      ) values (
        target_organization_id, invoice_row.root_invoice_id, invoice_row.client_id, entry.kind,
        entry.job_id, entry.visit_id, entry.reminder_id, entry.installment_number, entry.installment_id,
        entry.service_property_index, caller
      );
      claimed_count := claimed_count + 1;
    exception when unique_violation then
      raise exception 'That work has already been billed on another invoice.'
        using errcode = 'unique_violation',
        detail = format('%s on job %s', entry.kind, entry.job_id),
        hint = 'Open the invoice that already covers it, or void that invoice and bill this work again.';
    end;

    -- A period bill consumes its own visits. Claiming them here is what stops somebody billing April''s
    -- visits individually next week, and it is done under the same locks as the period claim itself.
    if entry.kind = 'reminder_period' then
      for visit_row in
        select visit.*
        from public.job_visits as visit
        where visit.organization_id = target_organization_id
          and visit.job_id = entry.job_id
          and visit.completed_at is not null
          and visit.visit_date is not null
          and visit.visit_date between period_start and period_end
        order by visit.id
        for update
      loop
        begin
          insert into public.invoice_sources (
            organization_id, root_invoice_id, client_id, source_kind,
            job_id, visit_id, service_property_index, claimed_by
          ) values (
            target_organization_id, invoice_row.root_invoice_id, invoice_row.client_id, 'visit',
            entry.job_id, visit_row.id, entry.service_property_index, caller
          );
          consumed_count := consumed_count + 1;
        exception when unique_violation then
          raise exception 'A visit inside that billing period has already been billed separately.'
            using errcode = 'unique_violation',
            detail = format('visit %s on %s', visit_row.id, visit_row.visit_date),
            hint = 'Bill the remaining periods, or void the invoice that already covers that visit.';
        end;
      end loop;
    end if;
  end loop;

  -- The bill starts with the tax its work was priced with. A quote's tax reaches its job, and without this the
  -- invoice began untaxed and the contractor had to type the same rate again, so a $486 job was billed at $450.
  -- Only one agreed tax is copied: if the jobs on this bill were priced differently, or the invoice already has
  -- a tax decision (including "no tax"), nothing is guessed or overwritten.
  with job_taxes as (
    select distinct job.tax_source, job.tax_name, job.tax_rate_basis_points, job.tax_rate_id
    from public.invoice_sources as claim
    join public.jobs as job
      on job.organization_id = claim.organization_id and job.id = claim.job_id
    where claim.organization_id = target_organization_id
      and claim.root_invoice_id = invoice_row.root_invoice_id
  )
  select * into job_tax from job_taxes where (select count(*) from job_taxes) = 1;

  if job_tax.tax_source is not null and job_tax.tax_source <> 'not_configured' then
    update public.invoices
    set tax_source = job_tax.tax_source, tax_name = job_tax.tax_name,
        tax_rate_basis_points = job_tax.tax_rate_basis_points, tax_rate_id = job_tax.tax_rate_id
    where organization_id = target_organization_id and id = target_invoice_id
      and tax_source = 'not_configured';
    get diagnostics tax_applied = row_count;
    if tax_applied > 0 then
      perform private.store_invoice_money(target_invoice_id);
    end if;
  end if;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.work_claimed', caller, invoice_row.revision, null,
    jsonb_build_object('claimed_count', claimed_count, 'consumed_visit_count', consumed_count),
    false, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'claim_invoice_sources', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'root_invoice_id', invoice_row.root_invoice_id,
      'claimed_count', claimed_count,
      'consumed_visit_count', consumed_count
    )
  );
end;
$function$;
