-- Invoices Part 5c-5: the batch planner bills each visit for what that visit actually did.

-- Unchanged except for the per-visit branch, which used to stamp one copy of the JOB's lines onto every
-- visit. That was right while every visit was identical and wrong the moment a visit could carry its own
-- quantities: the bill would have said three lawns on a week we mowed five. It now asks
-- private.job_visit_effective_lines the same question the visit editor and the composer ask, so all three
-- agree about what a visit is worth.
create or replace function private.job_batch_billing_payload(
  target_organization_id uuid,
  target_job_id uuid,
  as_of date
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  job_row public.jobs;
  priced jsonb;
  lines jsonb := '[]'::jsonb;
  sources jsonb := '[]'::jsonb;
begin
  select * into job_row
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'One of those jobs could not be found.' using errcode = 'P0404';
  end if;

  -- The job's own copy of the work, in its own order. `position` is restamped by the caller once the whole
  -- group is assembled, so it is left out here.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'category', line.category,
        'source_catalog_item_id', line.source_catalog_item_id,
        'name', line.name,
        'description', line.description,
        'unit_label', line.unit_label,
        'quantity', line.quantity,
        'unit_price_minor', line.unit_price_minor,
        'is_taxable', line.is_taxable
      )
      order by line.position, line.id
    ),
    '[]'::jsonb
  ) into priced
  from public.job_line_items as line
  where line.organization_id = target_organization_id
    and line.job_id = target_job_id
    and line.line_kind = 'priced';

  -- The composer refuses this one job with a toast; a batch is all-or-nothing, so it refuses the batch and
  -- names the job, which is the only way the contractor can tell which row to unpick.
  if jsonb_array_length(priced) = 0 then
    raise exception 'Job #% has no priced lines yet, so there is nothing to bill on it.', job_row.job_number
      using errcode = 'check_violation',
      hint = 'Add priced work to that job, or clear it from the selection.';
  end if;

  if job_row.price_basis = 'per_visit' then
    -- Completed and not already claimed: the same test the job page's "Visits ready to bill" card and
    -- private.job_uninvoiced_work make. Visits the contractor ticked have already been completed by the
    -- caller above, so they qualify here; ones nobody ticked are simply not on this bill.
    with billable as (
      select visit.id, visit.visit_date
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
      order by visit.visit_date nulls last, visit.id
    ),
    numbered as (
      select billable.*, row_number() over (order by billable.visit_date nulls last, billable.id) as rank
      from billable
    )
    select
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'category', line.category,
              'source_catalog_item_id', line.source_catalog_item_id,
              'name', line.name,
              'description', line.description,
              'unit_label', line.unit_label,
              'quantity', line.quantity,
              'unit_price_minor', line.unit_price_minor,
              'is_taxable', line.is_taxable,
              'service_date', numbered.visit_date
            )
            order by numbered.rank, line.position, line.id
          )
          from numbered
          cross join lateral private.job_visit_effective_lines(
            target_organization_id, target_job_id, numbered.id
          ) as line
          where line.line_kind = 'priced'
        ),
        '[]'::jsonb
      ),
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object('kind', 'visit', 'job_id', target_job_id, 'visit_id', numbered.id)
            order by numbered.rank
          )
          from numbered
        ),
        '[]'::jsonb
      )
    into lines, sources;

  elsif job_row.price_basis = 'fixed_per_period' then
    -- One copy per due, still-open period, stamped with the period's own end date. Per-visit reminders are
    -- excluded by kind: claim_invoice_sources refuses them by name, because a single day is billed as the
    -- visit it belongs to rather than as a period invented around it.
    with billable as (
      select reminder.id, reminder.due_on
      from public.job_invoice_reminders as reminder
      where reminder.organization_id = target_organization_id
        and reminder.job_id = target_job_id
        and reminder.status = 'pending'
        and reminder.due_on <= as_of
        and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
    ),
    numbered as (
      select billable.*, row_number() over (order by billable.due_on, billable.id) as rank
      from billable
    )
    select
      coalesce(
        (
          select jsonb_agg(
            element.value || jsonb_build_object('service_date', numbered.due_on)
            order by numbered.rank, element.ordinality
          )
          from numbered
          cross join jsonb_array_elements(priced) with ordinality as element(value, ordinality)
        ),
        '[]'::jsonb
      ),
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object('kind', 'reminder_period', 'job_id', target_job_id, 'reminder_id', numbered.id)
            order by numbered.rank
          )
          from numbered
        ),
        '[]'::jsonb
      )
    into lines, sources;

  else
    -- The whole job, once. Any claim at all and there is nothing left to bill this way; claim_invoice_sources
    -- enforces the same rule, and checking it here turns a unique-index violation into a sentence naming the
    -- job the contractor has to unpick.
    if exists (
      select 1
      from public.invoice_sources as claim
      where claim.organization_id = target_organization_id and claim.job_id = target_job_id
    ) then
      raise exception 'Job #% has already been billed, so it cannot go on this batch.', job_row.job_number
        using errcode = 'unique_violation',
        hint = 'Clear it from the selection, or void the invoice that already covers it.';
    end if;

    lines := priced;
    sources := jsonb_build_array(jsonb_build_object('kind', 'job_total', 'job_id', target_job_id));
  end if;

  if jsonb_array_length(sources) = 0 then
    raise exception 'Job #% has nothing waiting to be billed.', job_row.job_number
      using errcode = 'check_violation',
      hint = 'Its finished work may already be on another invoice.';
  end if;

  -- Reachable only through per-visit pricing: a visit whose own set is all notes and headings has work to
  -- claim but nothing to charge for, and a bill with no priced line is not a bill. Named, so the contractor
  -- can tell which row to unpick rather than reading an arithmetic error out of the draft command.
  if jsonb_array_length(lines) = 0 then
    raise exception 'Job #% has no priced work on the visits waiting to be billed.', job_row.job_number
      using errcode = 'check_violation',
      hint = 'Add priced lines to those visits, or clear the job from the selection.';
  end if;

  return jsonb_build_object(
    'job_id', job_row.id,
    'job_number', job_row.job_number,
    'title', job_row.title,
    'client_id', job_row.client_id,
    'property_id', job_row.property_id,
    'lines', lines,
    'sources', sources
  );
end;
$$;

comment on function private.job_batch_billing_payload(uuid, uuid, date) is
  'The invoice lines and source claims one job contributes to a batch, stating in SQL the same three seeding '
  'rules the single-job composer applies in the browser: the whole job once, one copy per completed unbilled '
  'visit, or one copy per due pending period. Bounded to a single job. Callers own the permission check.';

revoke all on function private.job_batch_billing_payload(uuid, uuid, date) from public;
revoke execute on function private.job_batch_billing_payload(uuid, uuid, date) from anon, authenticated;
