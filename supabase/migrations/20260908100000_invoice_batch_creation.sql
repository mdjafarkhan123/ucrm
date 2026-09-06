-- Invoices Part 8a: making many bills at once.
--
-- The ready-to-bill queue (5b-5) already gathers every job that owes an invoice today. What it could not do
-- was act on more than one row at a time: each "Bill" button walked one job through the single-job composer.
-- Jobber's batch invoicing is the missing half, and its shape is what this file implements:
--
--   * One invoice per CLIENT, not per job. A client's several finished jobs merge onto one bill.
--   * A differing property tax rate splits that bill, because an invoice carries exactly one tax rate
--     (invoices.tax_rate_id is a column, not a per-line choice).
--   * Each line keeps its own job's service date, so a merged bill still reads as a dated list of work.
--   * Unfinished visits are never billed unless the contractor explicitly ticked them; ticking one completes
--     it in the same transaction that bills it, so "invoiced but never marked done" cannot happen.
--
-- One command and one helper live here:
--
--   1. private.job_batch_billing_payload -- the lines and source claims for ONE job, by its price basis.
--   2. public.create_invoices_in_batch   -- complete the ticked visits, then write one draft per group.
--
-- Deliberately NOT here: sending the batch (Part 8b owns delivery), tax (the batch leaves each draft
-- untaxed exactly as the single-job composer does -- tax is applied afterwards through set_invoice_tax),
-- deposits, and any background queue. A batch is 25 jobs under one transaction, which is small enough to
-- answer inside the request that asked for it.

-- 1. What one job contributes to a batch -----------------------------------------------------------------
--
-- The single-job composer builds these lines in the browser (src/routes/(app)/invoices/new/+page.svelte).
-- A batch cannot: it would mean one round trip per job before anything could be written, and the whole
-- point of the batch is that the drafts and the claims land together or not at all. So the same three
-- seeding rules are stated once here, in SQL, and they are the same rules deliberately:
--
--   priced lines only        -- headings and notes describe work, they do not bill it.
--   job_total                -- one copy of the job's priced lines, no service date.
--   per_visit                -- one copy per completed, unbilled visit, stamped with that visit's date.
--   fixed_per_period         -- one copy per due, still-pending period, stamped with that period's end date.
--
-- Cost is bounded by one job: its own priced lines, its own visits, its own pending reminders. Nothing here
-- grows with the organization, and the caller runs it at most 25 times.
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
            element.value || jsonb_build_object('service_date', numbered.visit_date)
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

-- 2. The batch itself --------------------------------------------------------------------------------------
--
-- One transaction, one command receipt, all-or-nothing. Everything the contractor ticked is billed or nothing
-- is, which is the only honest answer when the same save also marks visits complete: a batch that half-worked
-- would leave visits done with no bill behind them, and there is no screen that would show that.
--
-- Three details are worth stating because none of them is obvious from the signature:
--
-- THE IDEMPOTENCY SUB-KEY. create_invoice_from_work, create_invoice_draft and claim_invoice_sources each take
-- a receipt under their own action name and the caller's key. Calling them in a loop with one key would make
-- the SECOND group replay the FIRST group's draft and return it -- one bill for two clients. So each group
-- gets a derived sub-key, `<key>:<group index>`, and the batch keeps its own receipt under its own action.
-- Group order is therefore part of correctness, not presentation: it is (client, tax rate), both stable, so a
-- retry with the same key and the same selection reproduces exactly the same sub-keys.
--
-- THE GROUPING KEY is client plus effective tax rate, where effective means the property's pinned rate if it
-- has one and the business default otherwise -- the same fallback Settings > Taxes defines. The batch does
-- not APPLY tax (neither does the single-job composer; tax is added on the draft afterwards). It splits by
-- rate anyway, because a bill that mixed two rates could never take either one.
--
-- LOCK ORDER. Groups are processed in client order and claim_invoice_sources locks each group's jobs in id
-- order, so two batches over overlapping work queue behind each other in the same order rather than each
-- holding half of what the other needs.
create or replace function public.create_invoices_in_batch(
  target_organization_id uuid,
  new_job_ids uuid[],
  new_complete_visit_ids uuid[],
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  today date;
  default_tax_rate_id uuid;
  job_ids uuid[];
  visit_ids uuid[];
  found_jobs integer;
  visit_row public.job_visits;
  found_visits integer := 0;
  visits_completed integer := 0;
  group_row record;
  group_index integer := 0;
  client_label text;
  job_id uuid;
  payload jsonb;
  group_lines jsonb;
  group_sources jsonb;
  positioned jsonb;
  created jsonb;
  results jsonb := '[]'::jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to bill work.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to bill work here.' using errcode = 'insufficient_privilege';
  end if;
  -- A batch is a screenful of amounts being committed at once; somebody who cannot see job prices cannot
  -- check what they are about to send. The same honest refusal the queue and the picker give.
  perform private.require_invoice_price_access(target_organization_id);

  select coalesce(array_agg(distinct id), '{}'::uuid[]) into job_ids
  from unnest(coalesce(new_job_ids, '{}'::uuid[])) as id;
  select coalesce(array_agg(distinct id), '{}'::uuid[]) into visit_ids
  from unnest(coalesce(new_complete_visit_ids, '{}'::uuid[])) as id;

  if cardinality(job_ids) = 0 then
    raise exception 'Choose at least one job to bill.' using errcode = 'check_violation';
  end if;
  -- The cap Jafar set: one page of the queue. Larger selections are billed as several batches rather than
  -- held under these locks for longer than a request should last.
  if cardinality(job_ids) > 25 then
    raise exception 'A batch can cover at most 25 jobs at once.' using errcode = 'check_violation',
      hint = 'Bill this page, then select the next one.';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'create_invoices_in_batch', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  today := private.organization_today(target_organization_id);

  select settings.tax_default_rate_id into default_tax_rate_id
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id
  for share;

  select count(*) into found_jobs
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = any(job_ids);
  if found_jobs <> cardinality(job_ids) then
    raise exception 'One of those jobs could not be found.' using errcode = 'P0404';
  end if;

  -- Ticked visits first, so the work they represent is complete before anything asks what is billable.
  -- complete_job_visit checks jobs.complete for itself: billing does not confer the right to declare field
  -- work finished, and a member who may bill but not complete is refused here rather than silently skipped.
  if cardinality(visit_ids) > 0 then
    for visit_row in
      select visit.*
      from public.job_visits as visit
      where visit.organization_id = target_organization_id and visit.id = any(visit_ids)
      order by visit.job_id, visit.id
    loop
      found_visits := found_visits + 1;
      -- The DB half of "never auto-selected": a visit can only be completed by this command if the
      -- contractor named it, and it must belong to a job actually in the batch.
      if not (visit_row.job_id = any(job_ids)) then
        raise exception 'One of those visits belongs to a job that is not in this batch.'
          using errcode = 'check_violation';
      end if;
      if visit_row.completed_at is null then
        perform public.complete_job_visit(target_organization_id, visit_row.job_id, visit_row.id);
        visits_completed := visits_completed + 1;
      end if;
    end loop;

    if found_visits <> cardinality(visit_ids) then
      raise exception 'One of those visits could not be found.' using errcode = 'P0404';
    end if;
  end if;

  for group_row in
    with selected as (
      select
        job.id,
        job.job_number,
        job.title,
        job.client_id,
        job.property_id,
        coalesce(property.tax_rate_id, default_tax_rate_id) as tax_group
      from public.jobs as job
      left join public.properties as property
        on property.organization_id = job.organization_id and property.id = job.property_id
      where job.organization_id = target_organization_id and job.id = any(job_ids)
    )
    select
      selected.client_id,
      selected.tax_group,
      count(*)::integer as job_count,
      array_agg(selected.id order by selected.job_number, selected.id) as group_job_ids,
      (array_agg(selected.title order by selected.job_number, selected.id))[1] as first_title,
      array_remove(array_agg(distinct selected.property_id), null) as property_ids
    from selected
    group by selected.client_id, selected.tax_group
    -- Deterministic, and therefore part of the idempotency contract: the same selection retried with the
    -- same key derives the same per-group sub-keys in the same order.
    order by selected.client_id, selected.tax_group nulls first
  loop
    group_index := group_index + 1;
    group_lines := '[]'::jsonb;
    group_sources := '[]'::jsonb;

    foreach job_id in array group_row.group_job_ids loop
      payload := private.job_batch_billing_payload(target_organization_id, job_id, today);
      group_lines := group_lines || (payload->'lines');
      group_sources := group_sources || (payload->'sources');
    end loop;

    -- Named the way the contractor knows the client, so the refusal below points at a row on the screen.
    select coalesce(nullif(trim(coalesce(client.company_name, '')), ''), client.display_name, 'That client')
    into client_label
    from public.clients as client
    where client.organization_id = target_organization_id and client.id = group_row.client_id;

    -- The two ceilings a single invoice actually has. Both are refused by name, because the contractor's only
    -- move is to unpick that client's rows and bill them separately.
    if jsonb_array_length(group_sources) > 100 then
      raise exception
        'Client % has % pieces of work waiting, which is more than the 100 one invoice can cover.',
        client_label,
        jsonb_array_length(group_sources)
        using errcode = 'check_violation',
        hint = 'Bill some of that client''s jobs on their own first.';
    end if;
    if jsonb_array_length(group_lines) > 100 then
      raise exception 'Client %''s work comes to % lines, which is more than one invoice can hold.',
        client_label,
        jsonb_array_length(group_lines)
        using errcode = 'check_violation',
        hint = 'Bill some of that client''s jobs on their own first.';
    end if;

    -- create_invoice_draft orders lines by their stated position, so the group's own assembly order is
    -- stamped on now that every job has contributed.
    select coalesce(
      jsonb_agg(
        element.value || jsonb_build_object('position', element.ordinality - 1)
        order by element.ordinality
      ),
      '[]'::jsonb
    ) into positioned
    from jsonb_array_elements(group_lines) with ordinality as element(value, ordinality);

    created := public.create_invoice_from_work(
      target_organization_id,
      group_row.client_id,
      -- One job bills under its own name, the way Jobber does it; several share the neutral default. Same
      -- rule the single-job composer applies when several jobs are picked for one client.
      case when group_row.job_count = 1 then group_row.first_title else 'For services rendered' end,
      positioned,
      group_row.property_ids,
      null,
      null,
      null,
      group_sources,
      new_idempotency_key || ':' || group_index::text,
      new_request_hash
    );

    results := results || jsonb_build_array(jsonb_build_object(
      'invoice_id', created->'invoice_id',
      'invoice_number', created->'invoice_number',
      'client_id', group_row.client_id,
      'job_count', group_row.job_count,
      'claimed_count', created->'claimed_count'
    ));
  end loop;

  return private.complete_invoice_command(
    target_organization_id, 'create_invoices_in_batch', new_idempotency_key,
    jsonb_build_object(
      'invoice_count', jsonb_array_length(results),
      'job_count', cardinality(job_ids),
      'visits_completed', visits_completed,
      'invoices', results
    )
  );
end;
$$;

comment on function public.create_invoices_in_batch(uuid, uuid[], uuid[], text, text) is
  'Bills up to 25 selected jobs at once: one draft per client per effective tax rate, each claiming its own '
  'work and clearing the reminders that asked for it, with any explicitly ticked unfinished visits completed '
  'in the same transaction. All-or-nothing. Each group takes a derived sub-key so a retry cannot replay one '
  'group''s draft as another''s.';

revoke all on function public.create_invoices_in_batch(uuid, uuid[], uuid[], text, text) from public;
revoke execute on function public.create_invoices_in_batch(uuid, uuid[], uuid[], text, text) from anon;
grant execute on function public.create_invoices_in_batch(uuid, uuid[], uuid[], text, text) to authenticated;
