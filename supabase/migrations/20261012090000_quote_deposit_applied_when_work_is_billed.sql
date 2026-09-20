-- A paid quote deposit reaches the invoice raised for that quote's work.
--
-- A deposit recorded on a quote (`quote_deposit_events`) already lives as unallocated client money: the
-- ledger knows what each receipt still has left (`private.deposit_event_available_minor`), the invoice
-- ledger already carries a deposit-sourced allocation, and the invoice page already renders it. Stage
-- billing (`create_installment_invoice`) already spends that credit on the first stage. Whole-job billing
-- did not, so a client who paid a deposit was billed the full amount again.
--
-- This completes Jobber's unallocated -> applied deposit lifecycle for the ordinary billing path. Nothing
-- about the shape of the data changes; only the billing step learns to spend credit the client has already
-- given. Manual application of leftover client credit stays a separate, later surface.

create or replace function public.create_invoice_from_work(
  target_organization_id uuid,
  target_client_id uuid,
  new_subject text,
  new_lines jsonb,
  new_service_property_ids uuid[],
  new_payment_term_id uuid,
  new_custom_due_date date,
  new_issue_date date,
  new_sources jsonb,
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
  draft jsonb;
  claimed jsonb;
  created_invoice_id uuid;
  reminders_resolved integer := 0;
  invoice_row public.invoices;
  deposit_row record;
  deposit_available bigint;
  deposit_share bigint;
  deposit_remaining bigint;
  deposit_applied_total bigint := 0;
begin
  if caller is null then
    raise exception 'You must be signed in to bill work.' using errcode = 'insufficient_privilege';
  end if;

  if new_sources is null or jsonb_typeof(new_sources) <> 'array'
     or jsonb_array_length(new_sources) = 0 then
    raise exception 'Choose at least one piece of work to bill.' using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'create_invoice_from_work', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- The draft first: it is what the claims attach to. Permission, currency lock, subject, line and terms
  -- validation all happen inside it, so nothing is re-checked here.
  draft := public.create_invoice_draft(
    target_organization_id, target_client_id, new_subject, new_lines, new_service_property_ids,
    new_payment_term_id, new_custom_due_date, new_issue_date, new_idempotency_key, new_request_hash
  );
  created_invoice_id := (draft->>'invoice_id')::uuid;

  -- A fresh draft is at revision 1; passing the figure the draft actually reports keeps this honest rather
  -- than assuming it.
  claimed := public.claim_invoice_sources(
    target_organization_id, created_invoice_id, (draft->>'revision')::integer, new_sources,
    new_idempotency_key, new_request_hash
  );

  -- Deposits, after the claims, because the claims are what say which work -- and so which quote -- this
  -- bill covers. Only receipts on the exact quote version the job was made from count, which is the same
  -- pairing stage billing uses; a job authored without a quote behind it never has one. The invoice is
  -- locked and re-read each time because applying an allocation can settle it and move its revision on,
  -- and the invoice is taken before the deposit, the order every money command in this schema uses.
  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = created_invoice_id
  for update;
  deposit_remaining := invoice_row.total_minor
    - private.invoice_allocated_minor(target_organization_id, created_invoice_id);

  for deposit_row in
    select distinct deposit.id, deposit.created_at
    from public.invoice_sources as claim
    join public.jobs as job
      on job.organization_id = claim.organization_id and job.id = claim.job_id
    join public.quote_deposit_events as deposit
      on deposit.organization_id = job.organization_id
      and deposit.quote_id = job.quote_id
      and deposit.quote_version_id = job.quote_version_id
    where claim.organization_id = target_organization_id
      and claim.root_invoice_id = created_invoice_id
      and job.quote_id is not null
      and deposit.event_type = 'received'
    order by deposit.created_at, deposit.id
  loop
    exit when deposit_remaining <= 0;

    perform 1
    from public.quote_deposit_events
    where organization_id = target_organization_id and id = deposit_row.id
    for update;

    deposit_available := private.deposit_event_available_minor(target_organization_id, deposit_row.id);
    if deposit_available > 0 then
      deposit_share := least(deposit_available, deposit_remaining);

      select * into invoice_row
      from public.invoices
      where organization_id = target_organization_id and id = created_invoice_id;

      perform private.apply_invoice_allocation(
        invoice_row, null, deposit_row.id, deposit_share, caller,
        'Quote deposit applied to the bill for that quote''s work.'
      );

      deposit_applied_total := deposit_applied_total + deposit_share;
      deposit_remaining := deposit_remaining - deposit_share;
    end if;
  end loop;

  -- Whatever work went on the bill, the prompts that asked for *that work* are answered. The claim command
  -- reports the chain root the claims were filed under, which for a fresh draft is the draft itself; taking
  -- it from the response rather than assuming it keeps the two in step.
  reminders_resolved := private.resolve_job_reminders_as_invoiced(
    target_organization_id, (claimed->>'root_invoice_id')::uuid, caller
  );

  return private.complete_invoice_command(
    target_organization_id, 'create_invoice_from_work', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', created_invoice_id,
      'invoice_number', (draft->>'invoice_number')::integer,
      'revision', (draft->>'revision')::integer,
      'claimed_count', (claimed->>'claimed_count')::integer,
      'consumed_visit_count', (claimed->>'consumed_visit_count')::integer,
      'reminders_resolved', reminders_resolved,
      'deposit_applied_minor', deposit_applied_total
    )
  );
end;
$$;

comment on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) is
  'Creates a draft invoice for a client''s job work and claims that work in the same transaction, credits '
  'any deposit already paid on the quote behind that work, then clears the invoice reminders that work '
  'answered. Composes create_invoice_draft and claim_invoice_sources so a bill can never exist without '
  'owning its sources, and never asks a client to pay a deposit twice.';

revoke all on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) from public;
revoke execute on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) from anon;
grant execute on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) to authenticated;

notify pgrst, 'reload schema';
