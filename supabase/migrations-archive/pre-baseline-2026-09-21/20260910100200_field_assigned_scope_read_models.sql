-- Jobs, Part 15a-2: narrow the Field role to assigned work only.
-- Step 3 of 4. The order and the reasoning are in 20260910100000_field_assigned_scope_foundation.sql.

-- 5. The ten SECURITY DEFINER read models ----------------------------------------------------------------

-- These check the permission themselves and never consult RLS, so narrowing the policies above does not
-- reach them. Each now asks whether this caller may see this job, not merely whether the tenant's role
-- carries jobs.view. The bodies are otherwise byte-for-byte what shipped.

create or replace function private.can_view_job_expense(
  target_organization_id uuid,
  target_expense_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.job_expenses as expense
    where expense.id = target_expense_id
      and expense.organization_id = target_organization_id
      and private.can_view_job(target_organization_id, expense.job_id)
      and (
        private.has_permission(target_organization_id, 'expenses.manage_team')
        or (
          expense.created_by = (select auth.uid())
          and private.has_permission(target_organization_id, 'expenses.record')
        )
      )
  );
$$;

create or replace function public.job_money(target_job_ids uuid[])
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_job_ids is null or cardinality(target_job_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct job.organization_id) into organizations
  from public.jobs as job
  where job.id = any(target_job_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those jobs do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to these jobs.' using errcode = 'insufficient_privilege';
  end if;

  if not private.member_has_permission(org, caller, 'jobs.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(job.id::text,
      jsonb_build_object(
        'subtotal_minor', job.subtotal_minor,
        'discount_minor', job.discount_minor,
        'discount_name', job.discount_name,
        'discount_type', job.discount_type,
        'discount_value', job.discount_value,
        'tax_minor', job.tax_minor,
        'tax_name', job.tax_name,
        'tax_source', job.tax_source,
        'tax_rate_id', job.tax_rate_id,
        'tax_rate_basis_points', job.tax_rate_basis_points,
        'total_minor', job.total_minor
      )
    ), '{}'::jsonb)
  into answer
  from public.jobs as job
  where job.organization_id = org
    and job.id = any(target_job_ids)
    and private.member_job_is_visible(org, caller, job.id);

  return answer;
end;
$$;

create or replace function public.job_line_money(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  select job.organization_id into org
  from public.jobs as job
  where job.id = target_job_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_job_is_visible(org, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(org, caller, 'jobs.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(item.id::text,
      (case when can_price then jsonb_build_object(
         'unit_price_minor', item.unit_price_minor,
         'line_total_minor', item.line_total_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'unit_cost_minor', item.unit_cost_minor,
         'line_cost_total_minor', item.line_cost_total_minor
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.job_line_items as item
  where item.organization_id = org
    and item.job_id = target_job_id;

  return answer;
end;
$$;

create or replace function public.job_schedule_money(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  priced jsonb;
  answer jsonb;
begin
  select job.organization_id into org from public.jobs as job where job.id = target_job_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_job_is_visible(org, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  if not private.member_has_permission(org, caller, 'jobs.view_price') then
    return '{}'::jsonb;
  end if;

  -- A job edited after a stage was invoiced can leave the schedule unable to reconcile. That is a real
  -- state the billing screen has to show rather than an error it should die on, so the reader answers with
  -- the stored stages and says the schedule does not reconcile.
  begin
    priced := private.price_job_payment_schedule(target_job_id);
  exception when others then
    priced := null;
  end;

  select jsonb_build_object(
    'reconciles', priced is not null,
    'job_total_minor', (select job.total_minor from public.jobs as job where job.id = target_job_id),
    'stages', coalesce(jsonb_agg(jsonb_build_object(
      'installment_id', stage.id,
      'position', stage.position,
      'value_type', stage.value_type,
      'value', stage.value,
      'locked_amount_minor', stage.locked_amount_minor,
      'amount_minor', coalesce(stage.locked_amount_minor, (
        select (entry ->> 'amount_minor')::bigint
        from jsonb_array_elements(coalesce(priced -> 'items', '[]'::jsonb)) as entry
        where nullif(entry ->> 'installment_id', '')::uuid = stage.id
      ))
    ) order by stage.position, stage.id), '[]'::jsonb)
  )
  into answer
  from public.job_payment_schedule_items as stage
  where stage.organization_id = org and stage.job_id = target_job_id;

  return answer;
end;
$$;

create or replace function public.job_schedule_stages(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  job_total bigint;
  is_one_off boolean;
  can_price boolean;
  can_view_invoices boolean;
  can_price_invoices boolean;
  priced jsonb;
  today date;
  answer jsonb;
begin
  select job.organization_id, job.total_minor, job.job_type = 'one_off'
  into org, job_total, is_one_off
  from public.jobs as job
  where job.id = target_job_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_job_is_visible(org, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'jobs.view_price');
  can_view_invoices := private.member_has_permission(org, caller, 'invoices.view');
  can_price_invoices := can_view_invoices
    and private.member_has_permission(org, caller, 'invoices.view_price');

  -- A job edited after one of its stages was invoiced can leave the schedule unable to reconcile. That is a
  -- real state the billing card has to show and explain, not an error it should die on, so the reader answers
  -- with the stored stages and says the schedule does not reconcile.
  if can_price then
    begin
      priced := private.price_job_payment_schedule(target_job_id);
    exception when others then
      priced := null;
    end;
  end if;

  today := private.organization_today(org);

  select jsonb_build_object(
    'job_id', target_job_id,
    'one_off', is_one_off,
    'reconciles', case when can_price then priced is not null else null end,
    'job_total_minor', case when can_price then job_total else null end,
    'stages', coalesce(jsonb_agg(jsonb_build_object(
      'installment_id', stage.id,
      'position', stage.position,
      'description', stage.description,
      'is_deposit', stage.is_deposit,
      -- The lock the write command enforces: this stage has been priced into a bill, so it is history
      -- rather than plan, and stays that way even if that bill was a draft somebody deleted.
      'locked', stage.locked_amount_minor is not null,
      'value_type', stage.value_type,
      'value', case when can_price then stage.value else null end,
      'amount_minor', case
        when not can_price then null
        else coalesce(stage.locked_amount_minor, (
          select (entry ->> 'amount_minor')::bigint
          from jsonb_array_elements(coalesce(priced -> 'items', '[]'::jsonb)) as entry
          where nullif(entry ->> 'installment_id', '')::uuid = stage.id
        ))
      end,
      'status', case
        when claim.root_invoice_id is null then 'remaining'
        when not can_view_invoices then 'invoiced'
        else private.invoice_live_status(
          active.voided_at, active.written_off_at, active.issued_at, active.recognized_at,
          active.marked_received_at, active.total_minor,
          private.invoice_allocated_minor(org, active.id), active.due_date, today
        )
      end,
      'invoice', case
        when claim.root_invoice_id is null or not can_view_invoices or active.id is null then null
        else jsonb_build_object(
          'id', active.id,
          'invoice_number', active.invoice_number,
          'total_minor', case when can_price_invoices then active.total_minor else null end,
          'balance_minor', case
            when can_price_invoices
              then active.total_minor - private.invoice_allocated_minor(org, active.id)
            else null
          end
        )
      end
    ) order by stage.position, stage.id), '[]'::jsonb)
  )
  into answer
  from public.job_payment_schedule_items as stage
  -- The claim names the chain's root, never the bill that happens to be active, so a correction inherits it.
  -- Served by invoice_sources_installment_id_unique_idx.
  left join lateral (
    select source.root_invoice_id
    from public.invoice_sources as source
    where source.organization_id = stage.organization_id
      and source.installment_id = stage.id
    limit 1
  ) as claim on true
  -- The bill that currently stands for that chain: everything before it has been replaced. Served by
  -- invoices_root_idx.
  left join lateral (
    select invoice.id, invoice.invoice_number, invoice.total_minor, invoice.due_date,
           invoice.voided_at, invoice.written_off_at, invoice.issued_at, invoice.recognized_at,
           invoice.marked_received_at
    from public.invoices as invoice
    where invoice.organization_id = org
      and invoice.root_invoice_id = claim.root_invoice_id
      and invoice.replaced_at is null
    order by invoice.created_at desc, invoice.id desc
    limit 1
  ) as active on claim.root_invoice_id is not null
  where stage.organization_id = org
    and stage.job_id = target_job_id;

  return answer;
end;
$$;

create or replace function public.visit_line_money(target_visit_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  visit_job uuid;
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  select visit.organization_id, visit.job_id into org, visit_job
  from public.job_visits as visit
  where visit.id = target_visit_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_job_is_visible(org, caller, visit_job) then
    raise exception 'You do not have access to this visit.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(org, caller, 'jobs.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(item.id::text,
      (case when can_price then jsonb_build_object(
         'unit_price_minor', item.unit_price_minor,
         'line_total_minor', item.line_total_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'unit_cost_minor', item.unit_cost_minor,
         'line_cost_total_minor', item.line_cost_total_minor
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.job_visit_line_items as item
  where item.organization_id = org
    and item.visit_id = target_visit_id;

  return answer;
end;
$$;

create or replace function public.job_visit_lines(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_price boolean;
  can_cost boolean;
  wanted uuid[] := coalesce(target_visit_ids, '{}'::uuid[]);
  answer jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  -- The same 100 the claim command caps one invoice at: a longer selection could not be billed in one go,
  -- so answering it would be a promise the next screen cannot keep.
  if cardinality(wanted) > 100 then
    raise exception 'Too many visits were asked for at once.' using errcode = '54000';
  end if;

  can_price := private.member_has_permission(target_organization_id, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'visit_id', visit.id,
        'visit_date', visit.visit_date,
        'completed', visit.completed_at is not null,
        'revision', visit.revision,
        -- Whether this visit carries its own set. False means it is showing the job's lines and has not been
        -- customised, which is what the editor's "back to the job's lines" state is.
        'has_override', exists (
          select 1
          from public.job_visit_line_items as override
          where override.organization_id = target_organization_id
            and override.visit_id = visit.id
        ),
        -- Locked pricing, and why. A completed visit is a record of work done; an invoiced one is history a
        -- customer has seen. Both refuse an edit in the write command; the editor reads this to say so first.
        'locked', visit.completed_at is not null or claimed.invoiced,
        'lock_reason', case
          when claimed.invoiced then 'invoiced'
          when visit.completed_at is not null then 'completed'
          else null
        end,
        'subtotal_minor', case when can_price then coalesce(effective.subtotal_minor, 0) else null end,
        'lines', coalesce(effective.lines, '[]'::jsonb)
      )
      order by visit.visit_date nulls last, visit.position, visit.id
    ),
    '[]'::jsonb
  ) into answer
  from public.job_visits as visit
  cross join lateral (
    select exists (
      select 1
      from public.invoice_sources as claim
      where claim.organization_id = target_organization_id
        and claim.visit_id = visit.id
        and claim.source_kind = 'visit'
    ) as invoiced
  ) as claimed
  cross join lateral (
    select
      sum(line.line_total_minor) filter (where line.line_kind = 'priced') as subtotal_minor,
      jsonb_agg(
        jsonb_build_object(
          'id', line.id,
          'is_override', line.is_override,
          'source_job_line_item_id', line.source_job_line_item_id,
          'catalog_item_id', line.source_catalog_item_id,
          'line_kind', line.line_kind,
          'category', line.category,
          'is_labor', line.is_labor,
          'name', line.name,
          'description', line.description,
          'unit_label', line.unit_label,
          'quantity', line.quantity,
          'is_taxable', line.is_taxable,
          'image_attachment_id', line.image_attachment_id
        )
        || (case when can_price then jsonb_build_object(
              'unit_price_minor', line.unit_price_minor,
              'line_total_minor', line.line_total_minor
            ) else '{}'::jsonb end)
        || (case when can_cost then jsonb_build_object(
              'unit_cost_minor', line.unit_cost_minor
            ) else '{}'::jsonb end)
        order by line.position, line.id
      ) as lines
    from private.job_visit_effective_lines(target_organization_id, target_job_id, visit.id) as line
  ) as effective
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = any(wanted);

  return jsonb_build_object('visits', answer);
end;
$$;

create or replace function public.job_labor(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  page_size constant integer := 200;
  can_cost boolean;
  can_team boolean;
  can_own boolean;
  job_closed boolean;
  entries jsonb;
  totals jsonb;
  entry_count integer;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  can_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');
  can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');
  can_own := private.member_has_permission(target_organization_id, caller, 'time.track_own');

  -- The same own/team split the table's policy applies, restated here because this function is definer and
  -- the policy no longer stands between the reader and the rows.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', visible.id,
          'user_id', visible.user_id,
          'user_name', visible.user_name,
          'visit_id', visible.visit_id,
          'visit_date', visible.visit_date,
          'started_at', visible.started_at,
          'minutes', visible.minutes,
          'notes', visible.notes,
          'can_edit', can_team or (visible.user_id = caller and can_own and not job_closed),
          'is_unrated', visible.cost_per_hour_minor is null
        )
        || (case when can_cost then jsonb_build_object(
              'cost_per_hour_minor', visible.cost_per_hour_minor,
              'cost_total_minor', visible.cost_total_minor
            ) else '{}'::jsonb end)
        order by visible.started_at desc, visible.id desc
      ),
      '[]'::jsonb
    ),
    count(*)
  into entries, entry_count
  from (
    select entry.id, entry.user_id, entry.visit_id, entry.started_at, entry.minutes, entry.notes,
           entry.cost_per_hour_minor, entry.cost_total_minor,
           profile.full_name as user_name,
           visit.visit_date
    from public.job_time_entries as entry
    left join public.profiles as profile on profile.id = entry.user_id
    left join public.job_visits as visit
      on visit.organization_id = entry.organization_id and visit.id = entry.visit_id
    where entry.organization_id = target_organization_id
      and entry.job_id = target_job_id
      and (can_team or (entry.user_id = caller and can_own))
    order by entry.started_at desc, entry.id desc
    limit page_size
  ) as visible;

  select jsonb_build_object(
    'entry_count', count(*),
    'minutes', coalesce(sum(entry.minutes), 0),
    'unrated_count', count(*) filter (where entry.cost_per_hour_minor is null),
    'cost_total_minor', case when can_cost then coalesce(sum(entry.cost_total_minor), 0) else null end
  ) into totals
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and (can_team or (entry.user_id = caller and can_own));

  return jsonb_build_object(
    'entries', entries,
    'totals', totals,
    -- More hours exist than the list shows. The totals still count all of them.
    'has_more', (totals->>'entry_count')::integer > entry_count,
    'job_closed', job_closed,
    'can_add', can_team or (can_own and not job_closed),
    'can_track_team', can_team,
    'can_see_cost', can_cost
  );
end;
$$;

create or replace function public.job_expenses_list(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  page_size constant integer := 200;
  can_cost boolean;
  can_team boolean;
  can_own boolean;
  job_closed boolean;
  expenses jsonb;
  totals jsonb;
  expense_count integer;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  can_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');
  can_team := private.member_has_permission(target_organization_id, caller, 'expenses.manage_team');
  can_own := private.member_has_permission(target_organization_id, caller, 'expenses.record');

  -- The same own/team split the table's policy applies, restated here because this function is definer and
  -- the policy no longer stands between the reader and the rows.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', visible.id,
          'name', visible.name,
          'accounting_code', visible.accounting_code,
          'description', visible.description,
          'expense_date', visible.expense_date,
          'reimburse_to_user_id', visible.reimburse_to_user_id,
          'reimburse_to_name', visible.reimburse_to_name,
          'created_by', visible.created_by,
          'receipt_count', visible.receipt_count,
          'can_edit', can_team or (visible.created_by = caller and can_own and not job_closed)
        )
        || (case when can_cost then jsonb_build_object('total_minor', visible.total_minor)
              else '{}'::jsonb end)
        order by visible.expense_date desc, visible.id desc
      ),
      '[]'::jsonb
    ),
    count(*)
  into expenses, expense_count
  from (
    select expense.id, expense.name, expense.accounting_code, expense.description, expense.expense_date,
           expense.total_minor, expense.reimburse_to_user_id, expense.created_by,
           profile.full_name as reimburse_to_name,
           (
             select count(*)
             from public.attachments as receipt
             where receipt.organization_id = expense.organization_id
               and receipt.entity_type = 'job_expense'
               and receipt.entity_id = expense.id
           ) as receipt_count
    from public.job_expenses as expense
    left join public.profiles as profile on profile.id = expense.reimburse_to_user_id
    where expense.organization_id = target_organization_id
      and expense.job_id = target_job_id
      and (can_team or (expense.created_by = caller and can_own))
    order by expense.expense_date desc, expense.id desc
    limit page_size
  ) as visible;

  select jsonb_build_object(
    'expense_count', count(*),
    'total_minor', case when can_cost then coalesce(sum(expense.total_minor), 0) else null end
  ) into totals
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and (can_team or (expense.created_by = caller and can_own));

  return jsonb_build_object(
    'expenses', expenses,
    'totals', totals,
    -- More expenses exist than the list shows. The total still counts all of them.
    'has_more', (totals->>'expense_count')::integer > expense_count,
    'job_closed', job_closed,
    'can_add', can_team or (can_own and not job_closed),
    'can_manage_team', can_team,
    'can_see_cost', can_cost
  );
end;
$$;

create or replace function public.job_costing(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
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

  -- No jobs.view_cost, nothing to show. The card only renders when the reader confirmed this right, and the
  -- API route only calls here then, so reaching this branch is a real error rather than an ordinary state.
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view_cost') then
    raise exception 'You do not have access to this job''s costs.' using errcode = 'insufficient_privilege';
  end if;

  -- A one-off job is measured over its whole life, exactly as 14d shipped it: it has an end, so it can have a
  -- final answer. Nothing below this block applies to it.
  if current_job.price_basis = 'job_total' then
    select coalesce(sum(entry.cost_total_minor), 0),
           count(*) filter (where entry.cost_per_hour_minor is null),
           count(*) > 0
    into labor_cost, unrated_count, has_time
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
      'expense_cost_minor', expense_cost,
      'total_cost_minor', total_cost,
      'profit_minor', profit,
      'margin_basis_points', margin_bp,
      'unrated_labor_count', unrated_count,
      'labor_line_and_time', has_labor_line and has_time
    );
  end if;

  -- The window. Thirty days ending today, both ends inclusive, on the organization's own calendar -- a
  -- contractor in Los Angeles and one in London do not agree about when today started, and a costing figure
  -- that moved at UTC midnight would be wrong for both of them at some hour.
  window_end := private.organization_today(target_organization_id);
  window_start := window_end - 29;

  -- The same timezone again, this time to turn those two dates into the instants labor is compared against.
  -- Comparing started_at to a pair of timestamptz keeps job_time_entries_job_started_idx in play; casting the
  -- column to a local date instead would throw the index away for no gain.
  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');

  labor_from := (window_start::timestamp) at time zone zone;
  labor_until := ((window_end + 1)::timestamp) at time zone zone;

  if current_job.price_basis = 'per_visit' then
    -- What the completed visits in this window are worth, priced the way the biller prices them. bool_or over
    -- the same rows answers the labor-line question for exactly the work being counted.
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
    -- fixed_per_period. Every billing period whose date landed in the window, invoiced or not.
    select count(*)::integer
    into unit_count
    from public.job_invoice_reminders as reminder
    where reminder.organization_id = target_organization_id
      and reminder.job_id = target_job_id
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and reminder.due_on between window_start and window_end;

    -- What one period sells for and costs in materials: the job's own priced lines, which is precisely the set
    -- private.job_batch_billing_payload stamps onto a period invoice.
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
      -- Manual billing, or simply no period fell in these 30 days. Either way there is no revenue to state and
      -- no item cost to draw down, so the card shows the recorded costs and leaves the rest blank.
      revenue := null;
      item_cost := 0;
    end if;
  end if;

  -- Labor and expenses are recorded against the job whatever its basis, so both bases count them the same way:
  -- everything that happened inside the window.
  select coalesce(sum(entry.cost_total_minor), 0),
         count(*) filter (where entry.cost_per_hour_minor is null),
         count(*) > 0
  into labor_cost, unrated_count, has_time
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
  -- No revenue means no profit and no margin. A window that cost $400 and sold nothing it can name is not a
  -- $400 loss; it is a window we cannot price, and saying so is the only honest answer.
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
    'expense_cost_minor', expense_cost,
    'total_cost_minor', total_cost,
    'profit_minor', profit,
    'margin_basis_points', margin_bp,
    'unrated_labor_count', unrated_count,
    'labor_line_and_time', has_labor_line and has_time
  );
end;
$$;


