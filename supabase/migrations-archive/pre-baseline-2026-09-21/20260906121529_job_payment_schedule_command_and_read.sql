-- Invoices Part 5c-2: the command that owns a job's payment schedule, and the screen's read of it.
--
-- 5c-1 built the records and the arithmetic but left both unreachable from a browser. This adds the two
-- doors: one write command that replaces the editable part of a job's schedule under an expected revision,
-- and one reader that answers "what does this job's billing plan look like right now" with the stage's
-- money behind jobs.view_price and its invoice behind invoices.view, exactly as the rest of the job screen
-- already gates them.

-- 1. Replacing the editable part of a job's schedule ---------------------------------------------------------

-- The whole schedule is sent at once, the same way a job's scope lines and a quote's installments are: staff
-- add, reorder, rename, re-price and remove stages in one dialog and save once. What arrives is the complete
-- intended schedule, not a delta. Each entry is `{id?, description, type, value}` -- `id` naming an existing
-- stage the caller means to keep, absent for a new one -- which is the shape private.price_job_payment_schedule
-- already reads.
--
-- Two things it will not do. It will not touch a stage an invoice already claims -- private.price_job_payment_schedule
-- refuses a list that moves, renames, re-prices or drops one, and the table's own guard trigger refuses it
-- again. And it will not remove a schedule that has already produced an invoice: switching a job back to
-- whole-job billing is only honest before any of it has been billed.
create or replace function public.set_job_payment_schedule(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  item_count integer := 0;
  locked_count integer;
  deposit_id uuid;
  priced jsonb;
  schedule_mode text;
begin
  current_job := private.lock_job_for_edit(target_organization_id, target_job_id, expected_revision);

  if current_job.job_type <> 'one_off' then
    raise exception 'Only a one-off job can carry a payment schedule.' using errcode = 'check_violation';
  end if;

  select count(*) filter (where stage.locked_amount_minor is not null)
  into locked_count
  from public.job_payment_schedule_items as stage
  where stage.organization_id = target_organization_id
    and stage.job_id = target_job_id;

  -- At most one stage carries the quote deposit's identity; the table's partial unique index says so.
  select stage.id
  into deposit_id
  from public.job_payment_schedule_items as stage
  where stage.organization_id = target_organization_id
    and stage.job_id = target_job_id
    and stage.is_deposit;

  if new_items is not null and jsonb_typeof(new_items) <> 'array' then
    raise exception 'Send the payment schedule as a list.' using errcode = 'check_violation';
  end if;
  if new_items is not null then
    item_count := jsonb_array_length(new_items);
  end if;

  if item_count = 0 then
    -- Back to billing the job as a whole. Only available while the plan is still only a plan.
    if locked_count > 0 then
      raise exception
        'One of these payment stages already has an invoice, so this schedule cannot be removed.'
        using errcode = 'check_violation';
    end if;

    delete from public.job_payment_schedule_items
    where organization_id = target_organization_id and job_id = target_job_id;
  else
    -- One answer for what the schedule is worth and whether it is allowed, shared with the reader below and
    -- with the invoice handoff in 5c-3. It refuses a mixed mode, a count outside 2..12, a total that does not
    -- reconcile, and any change to a stage that has already been invoiced.
    priced := private.price_job_payment_schedule(target_job_id, new_items);
    schedule_mode := priced ->> 'mode';

    -- Every stage that is still a plan is rewritten from the list; the invoiced ones are left exactly as they
    -- are. Rewriting rather than patching is what keeps positions unique without a reordering dance, and an
    -- unbilled stage is referenced by nothing, so nothing loses its footing when its row is replaced.
    delete from public.job_payment_schedule_items as stage
    where stage.organization_id = target_organization_id
      and stage.job_id = target_job_id
      and stage.locked_amount_minor is null;

    insert into public.job_payment_schedule_items (
      organization_id, job_id, position, description, value_type, value, is_deposit
    )
    select
      target_organization_id,
      target_job_id,
      (entry ->> 'position')::integer,
      entry ->> 'description',
      entry ->> 'value_type',
      (entry ->> 'value')::bigint,
      -- The quote deposit's identity travels with the stage that carries it, by id. A schedule authored on
      -- the job itself has no deposit stage: money that changed hands is a quote receipt, and this command
      -- never invents one.
      deposit_id is not null and nullif(entry ->> 'installment_id', '')::uuid = deposit_id
    from jsonb_array_elements(priced -> 'items') as entry
    where not exists (
      select 1
      from public.job_payment_schedule_items as kept
      where kept.organization_id = target_organization_id
        and kept.id = nullif(entry ->> 'installment_id', '')::uuid
    );
  end if;

  update public.jobs
  set revision = current_job.revision + 1
  where organization_id = target_organization_id and id = target_job_id;

  -- Counts and the mode only. A job's history rail is readable by anyone who may see the job, and stage
  -- amounts are not.
  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'payment_schedule_updated',
    caller,
    jsonb_build_object(
      'stage_count', item_count,
      'locked_count', locked_count,
      'mode', schedule_mode
    )
  );

  return jsonb_build_object(
    'revision', current_job.revision + 1,
    'stage_count', item_count,
    'mode', schedule_mode
  );
end;
$$;

comment on function public.set_job_payment_schedule(uuid, uuid, integer, jsonb) is
  'Replaces a one-off job''s payment stages in one transaction. Stages that already have an invoice survive '
  'unchanged; an empty list removes the schedule, but only while none of it has been billed.';

revoke all on function public.set_job_payment_schedule(uuid, uuid, integer, jsonb) from public;
revoke execute on function public.set_job_payment_schedule(uuid, uuid, integer, jsonb) from anon;
grant execute on function public.set_job_payment_schedule(uuid, uuid, integer, jsonb) to authenticated;

-- 2. What the job's billing area draws ----------------------------------------------------------------------

-- One job's stages with everything the card shows: the plan, whether each stage has been billed yet, and the
-- bill it produced. Definer for the same reason invoice_list_page is: the status of a bill is derived from
-- money, and a member without invoices.view_price still has to be able to see that a stage is awaiting
-- payment without ever selecting an amount.
--
-- Three separate gates, each already established elsewhere: jobs.view to read the job at all, jobs.view_price
-- for the stage amounts, and invoices.view for the bill's identity and live status. A stage that has been
-- billed says so to everyone -- that is a fact about the job -- but only a reader with invoices.view learns
-- which invoice, and only one with invoices.view_price learns what is still owed on it.
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

  if not private.member_has_permission(org, caller, 'jobs.view') then
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
      -- The lock, said as the card says it: this stage has a bill, so it is history rather than plan.
      'locked', claim.root_invoice_id is not null,
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

comment on function public.job_schedule_stages(uuid) is
  'One job''s payment stages as the billing card draws them: the plan, whether each stage is billed, and the '
  'live invoice behind it. Amounts need jobs.view_price; the invoice needs invoices.view and its balance '
  'needs invoices.view_price.';

revoke all on function public.job_schedule_stages(uuid) from public;
revoke execute on function public.job_schedule_stages(uuid) from anon;
grant execute on function public.job_schedule_stages(uuid) to authenticated;
