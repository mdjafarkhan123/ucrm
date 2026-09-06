-- A stage's `locked` flag now answers the same question the write command asks.
--
-- `set_job_payment_schedule` decides what it may rewrite from `locked_amount_minor is not null`, but this
-- reader was deriving `locked` (and `status`) from the invoice claim instead. The two agree everywhere except
-- after a still-Draft progress invoice is deleted: the claim cascades away, the locked amount stays -- as
-- designed, because deleting a draft must never make a stage independently billable again -- and the reader
-- then reported an editable, still-to-bill stage that the command would silently refuse to touch and the
-- billing card would offer a "Create invoice" button for that could only fail. The reader now tells the truth:
-- a stage that has been priced into a bill is locked, whatever became of that bill.
--
-- `status` is deliberately left alone. It answers where the *bill* stands, and with no bill in existence
-- 'remaining' is still the honest answer; `locked` is what says the stage is spent. The billing card reads
-- both.


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

comment on function public.job_schedule_stages(uuid) is
  'One job''s payment stages as the billing card draws them: the plan, whether each stage is billed, and the '
  'live invoice behind it. Amounts need jobs.view_price; the invoice needs invoices.view and its balance '
  'needs invoices.view_price.';

revoke all on function public.job_schedule_stages(uuid) from public;
revoke execute on function public.job_schedule_stages(uuid) from anon;
grant execute on function public.job_schedule_stages(uuid) to authenticated;
