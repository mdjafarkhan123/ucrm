-- Invoices Part 5c-3: atomic installment-to-Invoice handoff.
--
-- Fixes a gap 5c-1 left behind: `invoice_sources_shape` now requires `installment_id` whenever
-- `source_kind = 'installment'`, but `claim_invoice_sources` never learned to read or store one, so an
-- installment claim could not succeed at all. This migration teaches it that, adds the one command that
-- locks a job's payment stage, prices it, and hands it to a fresh Draft invoice in one transaction, and stops
-- the ready-to-bill queue from offering whole-job billing on a job that now bills by stage instead.

-- --- 1. `claim_invoice_sources` learns the installment shape -----------------------------------------------
create or replace function public.claim_invoice_sources(target_organization_id uuid, target_invoice_id uuid, expected_revision integer, new_sources jsonb, new_idempotency_key text, new_request_hash text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
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

-- --- 2. The progress-line allocator -------------------------------------------------------------------------
-- Splits one stage's locked amount across the job's own priced lines, proportionally, by the same
-- largest-remainder rule `price_job_payment_schedule` already uses for percentage stages: floor each share,
-- then hand the leftover cents to the lines with the largest fractional share, ties by position. A job whose
-- priced lines all happen to total zero splits the stage evenly across them instead, by the identical rule.
create or replace function private.progress_invoice_lines(target_organization_id uuid, target_job_id uuid, stage_amount_minor bigint)
 returns jsonb
 language sql
 stable
 set search_path to 'pg_catalog', 'public'
as $function$
  with raw as (
    select
      line.id, line.source_catalog_item_id, line.category, line.name, line.description,
      line.is_taxable, line.line_total_minor,
      row_number() over (order by line.position, line.id) as ord
    from public.job_line_items as line
    where line.organization_id = target_organization_id
      and line.job_id = target_job_id
      and line.line_kind = 'priced'
  ),
  totals as (
    select coalesce(sum(raw.line_total_minor), 0) as base_total, count(*) as line_count from raw
  ),
  weighted as (
    select raw.*,
      case when totals.base_total > 0 then raw.line_total_minor::numeric else 1::numeric end as weight,
      case when totals.base_total > 0 then totals.base_total::numeric else totals.line_count::numeric end
        as weight_total
    from raw cross join totals
  ),
  computed as (
    select weighted.*,
      floor(stage_amount_minor::numeric * weighted.weight / weighted.weight_total) as base_amount,
      stage_amount_minor::numeric * weighted.weight / weighted.weight_total
        - floor(stage_amount_minor::numeric * weighted.weight / weighted.weight_total) as fractional_part
    from weighted
  ),
  spread as (
    select computed.*,
      row_number() over (order by computed.fractional_part desc, computed.ord) as remainder_rank,
      stage_amount_minor - sum(computed.base_amount) over () as residual
    from computed
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'position', spread.ord - 1,
    'source_catalog_item_id', spread.source_catalog_item_id,
    'source_job_id', target_job_id,
    'source_job_line_id', spread.id,
    'line_kind', 'priced',
    'category', spread.category,
    'name', spread.name,
    'description', spread.description,
    'unit_label', null,
    'quantity', 1,
    'unit_price_minor',
      (spread.base_amount + case when spread.remainder_rank <= spread.residual then 1 else 0 end)::bigint,
    'is_taxable', spread.is_taxable,
    'progress_original_amount_minor', spread.line_total_minor
  ) order by spread.ord), '[]'::jsonb)
  from spread;
$function$;

-- --- 3. The atomic handoff itself ----------------------------------------------------------------------------
-- Locks the job, then the one stage this call bills — the same order the schedule commands already lock in,
-- so this and a schedule edit cannot deadlock each other. Prices the stage, locks its amount in (before the
-- claim exists, which is what the guard trigger on job_payment_schedule_items requires), builds its progress
-- lines, and hands both to a fresh Draft in one transaction. `create_invoice_draft` and `claim_invoice_sources`
-- enforce their own permissions and money-visibility rules, so nothing here repeats them.
create or replace function public.create_installment_invoice(target_organization_id uuid, target_job_id uuid, target_installment_id uuid, new_subject text, new_service_property_ids uuid[], new_payment_term_id uuid, new_custom_due_date date, new_issue_date date, new_idempotency_key text, new_request_hash text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  job_row public.jobs;
  stage_row public.job_payment_schedule_items;
  priced jsonb;
  stage_entry jsonb;
  stage_amount_minor bigint;
  progress_lines jsonb;
  draft jsonb;
  created_invoice_id uuid;
  invoice_row public.invoices;
  deposit_row record;
  deposit_available bigint;
  deposit_remaining bigint;
  deposit_share bigint;
  deposit_applied_total bigint := 0;
begin
  if caller is null then
    raise exception 'You must be signed in to create an invoice.' using errcode = 'insufficient_privilege';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'create_installment_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Lock order: the job, then the one stage this call bills. A second call for the same stage blocks here
  -- until the first commits, and then sees the stage already locked below rather than racing it.
  select * into job_row
  from public.jobs
  where organization_id = target_organization_id and id = target_job_id
  for share;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if job_row.job_type <> 'one_off' then
    raise exception 'Only a one-off job carries a payment schedule.' using errcode = 'check_violation';
  end if;

  select * into stage_row
  from public.job_payment_schedule_items
  where organization_id = target_organization_id and id = target_installment_id and job_id = target_job_id
  for update;
  if not found then
    raise exception 'That payment stage could not be found.' using errcode = 'P0404';
  end if;
  if stage_row.locked_amount_minor is not null then
    raise exception 'That payment stage has already been billed.'
      using errcode = 'unique_violation',
      hint = 'Open its invoice from the job''s Billing card instead of creating a new one.';
  end if;

  -- Priced as the schedule stands right now. A stage that no longer reconciles with the job total cannot be
  -- billed until the schedule is corrected — the same rule the Billing card already explains.
  priced := private.price_job_payment_schedule(target_job_id, null);
  select entry into stage_entry
  from jsonb_array_elements(priced -> 'items') as entry
  where nullif(entry ->> 'installment_id', '')::uuid = target_installment_id;
  if stage_entry is null then
    raise exception 'That payment stage could not be priced.' using errcode = 'check_violation';
  end if;
  stage_amount_minor := (stage_entry ->> 'amount_minor')::bigint;

  update public.job_payment_schedule_items
  set locked_amount_minor = stage_amount_minor
  where organization_id = target_organization_id and id = target_installment_id;

  progress_lines := private.progress_invoice_lines(target_organization_id, target_job_id, stage_amount_minor);

  draft := public.create_invoice_draft(
    target_organization_id, job_row.client_id, new_subject, progress_lines, new_service_property_ids,
    new_payment_term_id, new_custom_due_date, new_issue_date, new_idempotency_key, new_request_hash
  );
  created_invoice_id := (draft ->> 'invoice_id')::uuid;

  perform public.claim_invoice_sources(
    target_organization_id, created_invoice_id, (draft ->> 'revision')::integer,
    jsonb_build_array(jsonb_build_object(
      'kind', 'installment',
      'job_id', target_job_id,
      'installment_id', target_installment_id,
      'installment_number', stage_row.position + 1
    )),
    new_idempotency_key, new_request_hash
  );

  -- A live Quote deposit is spent on the first stage only, once, up to what the stage still owes. A job
  -- authored without a Quote behind it (`quote_id is null`) never has one to apply.
  if stage_row.position = 0 and job_row.quote_id is not null then
    deposit_remaining := stage_amount_minor;
    for deposit_row in
      select deposit.id
      from public.quote_deposit_events as deposit
      where deposit.organization_id = target_organization_id
        and deposit.quote_id = job_row.quote_id
        and deposit.quote_version_id = job_row.quote_version_id
        and deposit.event_type = 'received'
      order by deposit.created_at
    loop
      exit when deposit_remaining <= 0;
      deposit_available := private.deposit_event_available_minor(target_organization_id, deposit_row.id);
      if deposit_available > 0 then
        deposit_share := least(deposit_available, deposit_remaining);
        select * into invoice_row from public.invoices where id = created_invoice_id;
        perform private.apply_invoice_allocation(
          invoice_row, null, deposit_row.id, deposit_share, caller,
          'Quote deposit applied to the first payment stage.'
        );
        deposit_applied_total := deposit_applied_total + deposit_share;
        deposit_remaining := deposit_remaining - deposit_share;
      end if;
    end loop;
  end if;

  return private.complete_invoice_command(
    target_organization_id, 'create_installment_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', created_invoice_id,
      'invoice_number', (draft ->> 'invoice_number')::integer,
      'revision', (draft ->> 'revision')::integer,
      'installment_id', target_installment_id,
      'amount_minor', stage_amount_minor,
      'deposit_applied_minor', deposit_applied_total
    )
  );
end;
$function$;

revoke all on function public.create_installment_invoice(uuid, uuid, uuid, text, uuid[], uuid, date, date, text, text) from public;
revoke execute on function public.create_installment_invoice(uuid, uuid, uuid, text, uuid[], uuid, date, date, text, text) from anon;
grant execute on function public.create_installment_invoice(uuid, uuid, uuid, text, uuid[], uuid, date, date, text, text) to authenticated;

-- --- 4. A scheduled one-off job stops offering whole-job billing ---------------------------------------------
-- A one-off job with any payment-schedule stages bills only per stage, from the Billing card; the ready-to-
-- bill queue and the billable-work reader must stop offering it as a single whole-job unit too, the same way
-- they already stop once any invoice_sources claim exists.
create or replace function private.job_uninvoiced_work(target_organization_id uuid, target_job_id uuid, job_price_basis text, job_subtotal_minor bigint, job_total_minor bigint, as_of date)
 returns TABLE(unit_kind text, unit_count integer, uninvoiced_minor bigint)
 language sql
 stable
 set search_path to 'pg_catalog', 'public'
as $function$
  select
    case job_price_basis
      when 'per_visit' then 'visits'
      when 'fixed_per_period' then 'periods'
      else 'job'
    end as unit_kind,
    units.count::integer as unit_count,
    (case when job_price_basis = 'job_total' then job_total_minor else job_subtotal_minor end
      * units.count)::bigint as uninvoiced_minor
  from (
    select case job_price_basis
      when 'per_visit' then (
        select count(*)
        from public.job_visits as visit
        where visit.organization_id = target_organization_id
          and visit.job_id = target_job_id
          and visit.completed_at is not null
          and not exists (
            select 1
            from public.invoice_sources as claim
            where claim.organization_id = visit.organization_id
              and claim.visit_id = visit.id
              and claim.source_kind = 'visit'
          )
      )
      when 'fixed_per_period' then (
        select count(*)
        from public.job_invoice_reminders as reminder
        where reminder.organization_id = target_organization_id
          and reminder.job_id = target_job_id
          and reminder.status = 'pending'
          and reminder.due_on <= as_of
          and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      )
      else (
        select case when exists (
          select 1
          from public.invoice_sources as claim
          where claim.organization_id = target_organization_id
            and claim.job_id = target_job_id
        ) or exists (
          select 1
          from public.job_payment_schedule_items as stage
          where stage.organization_id = target_organization_id
            and stage.job_id = target_job_id
        ) then 0 else 1 end
      )
    end as count
  ) as units;
$function$;
