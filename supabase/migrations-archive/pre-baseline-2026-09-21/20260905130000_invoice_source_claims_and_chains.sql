-- Invoices Part 3c: source claims and the correction/rebill replacement chains.
--
-- Parts 3a and 3b built the bill, its money and its closures. What they could not answer on their own is the
-- question that keeps a contractor out of trouble: has this piece of work already been billed? A void, a
-- correction and a rebill all create a second invoice covering the same job, and nothing so far stops a third
-- one appearing beside them.
--
-- This file answers it with a claim. Every unit of source work -- a whole one-off job, one visit, one fixed
-- billing period, one installment -- gets exactly one claim row, and that row is attached to the *root* of a
-- correction chain rather than to a single invoice. A replacement therefore inherits the claim instead of
-- competing for it, which is precisely what makes "correct this bill" different from "bill this work again".
--
-- Contract decisions this implements: D3 (issued progress corrections keep the original and move the
-- receivable to a replacement) and D4 (a void never returns work to the billing queue; only an explicit
-- rebill does, and it stays inside the same chain).

-- 1. The claim ------------------------------------------------------------------------------------------------

create table public.invoice_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- The chain root, not the invoice that happens to be active. This is the whole mechanism: a correction or
  -- a rebill shares its predecessor's root, so it inherits this claim and can never become a second,
  -- independent way to bill the same work.
  --
  -- Cascade is correct here and only here: the single invoice row that can ever be deleted is a draft, and a
  -- deleted draft must give its work back to the billing queue rather than sterilise it forever. Every other
  -- invoice is retained through void.
  root_invoice_id uuid not null,
  client_id uuid not null,
  source_kind text not null check (
    source_kind in ('job_total', 'visit', 'reminder_period', 'installment')
  ),
  -- Always set. Every unit of billable work belongs to a job, and carrying the job here is what lets the
  -- uniqueness rules and the "does this client own this work" check stay one indexed lookup.
  job_id uuid not null,
  visit_id uuid,
  reminder_id uuid,
  -- The installment's position in the job's payment schedule. Jobs 11c owns that schedule and will add the
  -- foreign key to its row; until then the number is the identity, which is enough to keep one installment
  -- from being billed twice. Deliberately not a made-up foreign key to a table that does not exist yet.
  installment_number integer check (installment_number is null or installment_number >= 1),
  -- Which entry of the invoice's frozen service_properties array renders this claim's address. Null when the
  -- bill carries no service property for it. An index into a frozen array, never a live property lookup.
  service_property_index integer check (service_property_index is null or service_property_index >= 0),
  claimed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  constraint invoice_sources_organization_id_unique unique (organization_id, id),
  constraint invoice_sources_root_fk foreign key (organization_id, root_invoice_id)
    references public.invoices(organization_id, id) on delete cascade,
  -- Restrict, not cascade: work that has been billed cannot be deleted out from under its bill. The
  -- contractor gets a refusal naming the invoice instead of a bill whose history quietly lost its source.
  constraint invoice_sources_client_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict,
  constraint invoice_sources_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete restrict,
  constraint invoice_sources_visit_fk foreign key (organization_id, visit_id)
    references public.job_visits(organization_id, id) on delete restrict,
  constraint invoice_sources_reminder_fk foreign key (organization_id, reminder_id)
    references public.job_invoice_reminders(organization_id, id) on delete restrict,

  -- Each kind carries exactly the references it means and no others. A claim that is half a visit and half a
  -- reminder is not a claim anybody can reason about.
  constraint invoice_sources_shape check (
    case source_kind
      when 'job_total' then
        visit_id is null and reminder_id is null and installment_number is null
      when 'visit' then
        visit_id is not null and reminder_id is null and installment_number is null
      when 'reminder_period' then
        visit_id is null and reminder_id is not null and installment_number is null
      when 'installment' then
        visit_id is null and reminder_id is null and installment_number is not null
    end
  )
);

comment on table public.invoice_sources is
  'One canonical claim per unit of billable work, attached to the root of an invoice''s correction chain so a '
  'replacement inherits it rather than competing for it. Members read this table; only the commands in this '
  'file write it. A void keeps the claim (decision D4), which is what stops a cancelled bill from quietly '
  'putting the same work back in the queue.';

comment on column public.invoice_sources.root_invoice_id is
  'The first invoice of the chain that claimed this work. Every correction and rebill in that chain shares '
  'it, so the uniqueness indexes below let a chain be re-billed without ever letting the work be billed twice.';

comment on column public.invoice_sources.installment_number is
  'Position in the job''s payment schedule. Jobs 11c adds the foreign key to the schedule row; the number '
  'carries the identity until then.';

-- The uniqueness rules. Each is a partial unique index rather than a table constraint, because each kind
-- identifies its work with a different column and a single constraint over all four would either be nullable
-- and useless or force every claim to carry columns it has no meaning for.
--
-- These are also the only defence that survives two people pressing "Create invoice" at the same instant: the
-- loser gets a unique violation, which the commands below turn into a sentence naming the existing bill.

create unique index invoice_sources_job_total_unique_idx
  on public.invoice_sources(organization_id, job_id)
  where source_kind = 'job_total';

create unique index invoice_sources_visit_unique_idx
  on public.invoice_sources(organization_id, visit_id)
  where source_kind = 'visit';

create unique index invoice_sources_reminder_unique_idx
  on public.invoice_sources(organization_id, reminder_id)
  where source_kind = 'reminder_period';

create unique index invoice_sources_installment_unique_idx
  on public.invoice_sources(organization_id, job_id, installment_number)
  where source_kind = 'installment';

-- "What work is on this bill", asked once per invoice detail page and once per chain.
create index invoice_sources_root_idx
  on public.invoice_sources(organization_id, root_invoice_id, source_kind, id);

-- "Has this job been billed, and where", for the job screen and for the billing queue's exclusion.
create index invoice_sources_job_idx
  on public.invoice_sources(organization_id, job_id, source_kind, id);

create index invoice_sources_client_idx
  on public.invoice_sources(organization_id, client_id, id);

-- Child foreign keys the uniqueness indexes do not already cover, so a visit or reminder deletion checks an
-- index instead of scanning the table.
create index invoice_sources_visit_fk_idx
  on public.invoice_sources(organization_id, visit_id) where visit_id is not null;
create index invoice_sources_reminder_fk_idx
  on public.invoice_sources(organization_id, reminder_id) where reminder_id is not null;
create index invoice_sources_claimed_by_idx
  on public.invoice_sources(claimed_by) where claimed_by is not null;

-- A claim is a fact about what was billed, so it does not change; it is created with its bill and removed
-- only when a draft that never became a bill is deleted. The trigger catches what a grant cannot: a
-- SECURITY DEFINER command running as the table owner.
create or replace function private.invoice_sources_are_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'A billing claim cannot be edited. Delete the draft or correct the invoice instead.'
    using errcode = 'check_violation';
end;
$$;

revoke all on function private.invoice_sources_are_immutable() from public;
revoke execute on function private.invoice_sources_are_immutable() from anon, authenticated;

create trigger invoice_sources_no_update
before update on public.invoice_sources
for each row execute function private.invoice_sources_are_immutable();

create trigger invoice_sources_no_truncate
before truncate on public.invoice_sources
for each statement execute function private.invoice_sources_are_immutable();

alter table public.invoice_sources enable row level security;

-- A claim carries no money, only a pointer from a bill to the work it covers. Anyone who may see the invoice
-- may see what it is for.
create policy "permitted members can view invoice sources"
on public.invoice_sources for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'invoices.view')
);

revoke all on public.invoice_sources from anon, authenticated;
grant select on public.invoice_sources to authenticated;

revoke all on public.invoice_sources from service_role;
grant select, insert, delete on public.invoice_sources to service_role;

-- 2. The frozen status label ------------------------------------------------------------------------------------

-- The six contract statuses, derived from stored facts. 3a and 3b deliberately stored no status column, so
-- this is the first place the derivation is written down -- and it exists because replacement has to freeze
-- the label a bill had at the moment it was replaced. Without freezing, yesterday's replaced invoice would
-- silently age into Past Due forever, because its due date keeps receding into the past.
--
-- Order matters. Void beats everything: a cancelled bill is not overdue. Write-off beats payment state,
-- because bad debt is a statement about the remainder. Only then do the money and the calendar speak.
create or replace function private.invoice_status_label(invoice_row public.invoices)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  allocated_minor bigint;
begin
  if invoice_row.voided_at is not null then
    return 'voided';
  end if;
  if invoice_row.written_off_at is not null then
    return 'bad_debt';
  end if;
  if invoice_row.issued_at is null and invoice_row.recognized_at is null then
    return 'draft';
  end if;
  -- Status-only closure. It extinguishes no debt, but the label the contractor sees is Paid.
  if invoice_row.marked_received_at is not null then
    return 'paid';
  end if;

  allocated_minor := private.invoice_allocated_minor(
    invoice_row.organization_id, invoice_row.id
  );
  if allocated_minor >= invoice_row.total_minor then
    return 'paid';
  end if;

  if invoice_row.due_date < private.organization_today(invoice_row.organization_id) then
    return 'past_due';
  end if;
  return 'awaiting_payment';
end;
$$;

comment on function private.invoice_status_label(public.invoices) is
  'The six contract statuses derived from stored facts, used to freeze the label a bill carried at the moment '
  'it was replaced so history never ages into Past Due.';

revoke all on function private.invoice_status_label(public.invoices) from public;
revoke execute on function private.invoice_status_label(public.invoices) from anon, authenticated;

-- 3. Building a successor ---------------------------------------------------------------------------------------

-- A replacement is a new draft that says the same thing about the same work. It copies the predecessor's
-- document and lines exactly, because a correction that silently re-resolved the customer's address or
-- re-read the live job would be a different bill wearing the old one's number.
--
-- What it deliberately does not copy is money. Payments stay allocated where they were until somebody moves
-- them, which is the approved behaviour in D3: a 100 bill with 30 on it, replaced by an 80 bill, leaves the
-- 30 pointing at the original.
create or replace function private.create_chain_successor_draft(
  predecessor public.invoices,
  link_kind text,
  actor uuid
)
returns public.invoices
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  successor public.invoices;
begin
  insert into public.invoices (
    organization_id, client_id, invoice_number, subject, currency_code,
    customer_snapshot, billing_address_snapshot, service_properties,
    payment_term_id, payment_term_snapshot, due_date_source, issue_date, due_date,
    predecessor_invoice_id, root_invoice_id, replacement_kind, created_by
  ) values (
    predecessor.organization_id,
    predecessor.client_id,
    private.allocate_invoice_number(predecessor.organization_id),
    predecessor.subject,
    -- The chain's currency, not today's setting. A correction to a bill written in the old currency stays in
    -- that currency or it is not a correction.
    predecessor.currency_code,
    predecessor.customer_snapshot,
    predecessor.billing_address_snapshot,
    predecessor.service_properties,
    predecessor.payment_term_id,
    predecessor.payment_term_snapshot,
    predecessor.due_date_source,
    -- Today's date for the replacement, with the predecessor's own interval to its due date preserved, so a
    -- Net 30 correction is still Net 30 rather than instantly overdue.
    private.organization_today(predecessor.organization_id),
    private.organization_today(predecessor.organization_id)
      + (predecessor.due_date - predecessor.issue_date),
    predecessor.id,
    predecessor.root_invoice_id,
    link_kind,
    actor
  )
  returning * into successor;

  insert into public.invoice_lines (
    organization_id, invoice_id, position, source_catalog_item_id, source_job_id, source_job_line_id,
    service_date, line_kind, category, name, description, unit_label, quantity, unit_price_minor,
    is_taxable, progress_original_amount_minor
  )
  select
    line.organization_id, successor.id, line.position, line.source_catalog_item_id, line.source_job_id,
    line.source_job_line_id, line.service_date, line.line_kind, line.category, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.is_taxable,
    -- D3: already issued installment amounts are locked on the job, so the original amount travels with the
    -- line rather than being recalculated from a schedule the correction is not allowed to rewrite.
    line.progress_original_amount_minor
  from public.invoice_lines as line
  where line.organization_id = predecessor.organization_id
    and line.invoice_id = predecessor.id
  order by line.position, line.id;

  -- The discount and tax inputs come across too; store_invoice_money recalculates the totals from them so no
  -- amount is ever copied by hand.
  update public.invoices
  set discount_name = predecessor.discount_name,
      discount_type = predecessor.discount_type,
      discount_value = predecessor.discount_value,
      tax_source = predecessor.tax_source,
      tax_name = predecessor.tax_name,
      tax_rate_basis_points = predecessor.tax_rate_basis_points,
      tax_rate_id = predecessor.tax_rate_id
  where organization_id = successor.organization_id and id = successor.id;

  perform private.store_invoice_money(successor.id);

  select * into successor
  from public.invoices
  where organization_id = successor.organization_id and id = successor.id;

  return successor;
end;
$$;

revoke all on function private.create_chain_successor_draft(public.invoices, text, uuid) from public;
revoke execute on function private.create_chain_successor_draft(public.invoices, text, uuid)
  from anon, authenticated;

-- 4. Claiming the work ------------------------------------------------------------------------------------------

-- Attaches source work to a draft's chain. Part 5 calls this when it builds an invoice from a job, and Part 8
-- calls it once per draft in a batch; a directly typed invoice claims nothing and is unaffected.
--
-- Three rules do the real work here, and all three are about the same fear -- billing a customer twice:
--
--   * A whole-job claim and a per-visit claim for the same job are mutually exclusive. You bill a job one way.
--   * A fixed-period reminder consumes the visits that fall inside its period, so it is not a competing
--     second claim for work its own visits already cover.
--   * A per-visit reminder has no period of its own. It is claimed as the visit it was raised for, which is
--     why this command refuses it by name rather than inventing a period around a single day.
create or replace function public.claim_invoice_sources(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
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
  invoice_row public.invoices;
  property_count integer;
  requested_job_count integer;
  matched_job_count integer;
  entry record;
  reminder_row public.job_invoice_reminders;
  period_start date;
  period_end date;
  visit_row public.job_visits;
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
    if entry.kind = 'installment' and entry.installment_number is null then
      raise exception 'An installment claim needs its position in the payment schedule.'
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
    end if;

    begin
      insert into public.invoice_sources (
        organization_id, root_invoice_id, client_id, source_kind,
        job_id, visit_id, reminder_id, installment_number, service_property_index, claimed_by
      ) values (
        target_organization_id, invoice_row.root_invoice_id, invoice_row.client_id, entry.kind,
        entry.job_id, entry.visit_id, entry.reminder_id, entry.installment_number,
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
$$;

comment on function public.claim_invoice_sources(uuid, uuid, integer, jsonb, text, text) is
  'Attaches source work to a draft invoice''s chain so the same job, visit, billing period or installment '
  'cannot be billed twice. A fixed-period claim also consumes the completed visits inside its period.';

revoke all on function public.claim_invoice_sources(uuid, uuid, integer, jsonb, text, text) from public;
revoke execute on function public.claim_invoice_sources(uuid, uuid, integer, jsonb, text, text) from anon;
grant execute on function public.claim_invoice_sources(uuid, uuid, integer, jsonb, text, text) to authenticated;

-- 5. Rebilling a voided invoice (decision D4) ---------------------------------------------------------------------

-- Voiding never puts work back in the queue by itself. This command is the explicit "yes, bill this again",
-- and it keeps the new bill inside the voided one's chain so the pair reads as one story rather than as two
-- unrelated invoices that happen to cover the same job.
create or replace function public.rebill_voided_invoice(
  target_organization_id uuid,
  target_invoice_id uuid,
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
  predecessor public.invoices;
  successor public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to rebill an invoice.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to create an invoice here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'rebill_voided_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Locked directly rather than through lock_invoice_for_edit, which refuses voided invoices outright. That
  -- refusal is right for every other command; this one exists precisely to act on a voided bill.
  select * into predecessor
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id
  for update;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;

  if predecessor.voided_at is null then
    raise exception 'Only a voided invoice is rebilled. Correct this one instead.'
      using errcode = 'check_violation';
  end if;
  -- The unique index would catch this anyway; catching it here names the invoice instead of the index.
  if exists (
    select 1 from public.invoices as existing
    where existing.organization_id = target_organization_id
      and existing.predecessor_invoice_id = predecessor.id
  ) then
    raise exception 'This invoice has already been rebilled.' using errcode = 'unique_violation',
      hint = 'Open the invoice that replaced it.';
  end if;

  successor := private.create_chain_successor_draft(predecessor, 'rebill', caller);

  perform private.record_invoice_event(
    target_organization_id, successor.id, successor.invoice_number, successor.client_id,
    'invoice.created_as_rebill', caller, successor.revision, null,
    jsonb_build_object(
      'predecessor_invoice_id', predecessor.id,
      'predecessor_invoice_number', predecessor.invoice_number
    ),
    false, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'rebill_voided_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', successor.id,
      'invoice_number', successor.invoice_number,
      'revision', successor.revision,
      'predecessor_invoice_id', predecessor.id,
      'root_invoice_id', successor.root_invoice_id,
      'replacement_kind', 'rebill'
    )
  );
end;
$$;

comment on function public.rebill_voided_invoice(uuid, uuid, text, text) is
  'Creates the explicit replacement draft for a voided invoice, inside the same chain so the work is billed '
  'again without ever being claimed twice. The voided bill stays exactly as it is until the replacement is '
  'activated.';

revoke all on function public.rebill_voided_invoice(uuid, uuid, text, text) from public;
revoke execute on function public.rebill_voided_invoice(uuid, uuid, text, text) from anon;
grant execute on function public.rebill_voided_invoice(uuid, uuid, text, text) to authenticated;

-- 6. Correcting an issued invoice (decision D3) --------------------------------------------------------------------

-- The progress-invoice answer, and the general one. An issued bill that was wrong is not deleted and not
-- voided: a replacement draft is prepared beside it, edited until it is right, and then activated. Until that
-- activation the original is still the live receivable, which is what lets somebody prepare a correction
-- without the customer's balance flickering in the meantime.
create or replace function public.prepare_invoice_correction(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
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
  predecessor public.invoices;
  successor public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to correct an invoice.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to create an invoice here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'prepare_invoice_correction', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Refuses a voided or already-replaced predecessor and a stale revision on the caller's behalf.
  predecessor := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision, 'invoices.create'
  );

  if predecessor.issued_at is null and predecessor.recognized_at is null then
    raise exception 'A draft is edited directly rather than corrected.' using errcode = 'check_violation';
  end if;
  if predecessor.written_off_at is not null then
    raise exception 'Undo the write-off before correcting this bill.' using errcode = 'check_violation';
  end if;
  if predecessor.marked_received_at is not null then
    raise exception 'Reopen this bill before correcting it.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.invoices as existing
    where existing.organization_id = target_organization_id
      and existing.predecessor_invoice_id = predecessor.id
  ) then
    raise exception 'A correction for this invoice already exists.' using errcode = 'unique_violation',
      hint = 'Open that correction and finish it, or delete it if it was a mistake.';
  end if;

  successor := private.create_chain_successor_draft(predecessor, 'correction', caller);

  perform private.record_invoice_event(
    target_organization_id, successor.id, successor.invoice_number, successor.client_id,
    'invoice.created_as_correction', caller, successor.revision, null,
    jsonb_build_object(
      'predecessor_invoice_id', predecessor.id,
      'predecessor_invoice_number', predecessor.invoice_number
    ),
    false, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'prepare_invoice_correction', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', successor.id,
      'invoice_number', successor.invoice_number,
      'revision', successor.revision,
      'predecessor_invoice_id', predecessor.id,
      'root_invoice_id', successor.root_invoice_id,
      'replacement_kind', 'correction'
    )
  );
end;
$$;

comment on function public.prepare_invoice_correction(uuid, uuid, integer, text, text) is
  'Prepares a replacement draft beside an issued invoice, copying its document, lines and amounts. The '
  'original stays the live receivable until the replacement is activated.';

revoke all on function public.prepare_invoice_correction(uuid, uuid, integer, text, text) from public;
revoke execute on function public.prepare_invoice_correction(uuid, uuid, integer, text, text) from anon;
grant execute on function public.prepare_invoice_correction(uuid, uuid, integer, text, text) to authenticated;

-- 7. Activating the replacement -----------------------------------------------------------------------------------

-- The single moment the receivable moves. The successor becomes issued and the predecessor becomes history in
-- the same transaction, so there is no instant in which the customer owes both bills or neither.
--
-- Two safeguards sit on it. The caller sends back the difference it showed the user, and a difference that no
-- longer matches is refused rather than applied to numbers nobody approved. And the predecessor's label is
-- frozen at this instant, so a replaced bill dated last month never drifts into Past Due afterwards.
--
-- Money does not move. Payments stay allocated to the invoice that received them until somebody moves them
-- explicitly, which is D3's rule and the reason a replacement shows its predecessor's payments as context
-- rather than as its own.
create or replace function public.activate_invoice_replacement(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  previewed_difference_minor bigint,
  new_issue_method text,
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
  settings_row public.organization_settings;
  successor public.invoices;
  predecessor public.invoices;
  frozen_label text;
  actual_difference_minor bigint;
  issued public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to activate a replacement.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.send') then
    raise exception 'You do not have access to issue an invoice.' using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  if new_issue_method not in ('sent', 'marked_sent') then
    raise exception 'An invoice is issued by sending it or by marking it sent.'
      using errcode = 'check_violation';
  end if;
  if previewed_difference_minor is null then
    raise exception 'Confirm the difference this replacement makes before applying it.'
      using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'activate_invoice_replacement', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Settings before invoices, matching every other currency-sensitive command.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for share;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  select * into successor
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;
  if successor.predecessor_invoice_id is null then
    raise exception 'This invoice does not replace anything.' using errcode = 'check_violation';
  end if;

  -- Both rows locked in id order in one statement. Two people activating replacements in the same chain
  -- queue behind each other instead of deadlocking.
  perform 1
  from public.invoices
  where organization_id = target_organization_id
    and id in (successor.id, successor.predecessor_invoice_id)
  order by id
  for update;

  select * into successor
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;
  select * into predecessor
  from public.invoices
  where organization_id = target_organization_id and id = successor.predecessor_invoice_id;

  if successor.revision is distinct from expected_revision then
    raise exception 'Someone else changed this invoice. Reload to see the latest.' using errcode = 'P0409';
  end if;
  if successor.issued_at is not null or successor.recognized_at is not null then
    raise exception 'This replacement has already been activated.' using errcode = 'check_violation';
  end if;
  if successor.currency_code is distinct from settings_row.currency_code then
    raise exception 'This draft was written in a different currency. Refresh it before issuing it.'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from public.invoice_lines
    where organization_id = target_organization_id and invoice_id = successor.id
  ) then
    raise exception 'An invoice needs at least one line before it can be issued.'
      using errcode = 'check_violation';
  end if;
  if predecessor.replaced_at is not null then
    raise exception 'That invoice has already been replaced.' using errcode = 'check_violation';
  end if;

  -- The stale-preview refusal. The user approved a specific change in what the customer owes; if the numbers
  -- moved underneath them, they approved something else.
  actual_difference_minor := successor.total_minor - predecessor.total_minor;
  if actual_difference_minor is distinct from previewed_difference_minor then
    raise exception 'These amounts changed since you reviewed them. Check the difference and try again.'
      using errcode = 'P0409',
      detail = format('reviewed %s, now %s', previewed_difference_minor, actual_difference_minor);
  end if;

  -- Read the label before anything is written, because the label is a statement about the bill as it stood
  -- one instant ago.
  frozen_label := private.invoice_status_label(predecessor);

  update public.invoices
  set issued_at = now(),
      issued_by = caller,
      issue_method = new_issue_method,
      document_frozen_at = now(),
      revision = successor.revision + 1
  where organization_id = target_organization_id and id = successor.id
  returning * into issued;

  update public.invoices
  set replaced_at = now(),
      replaced_by_invoice_id = successor.id,
      frozen_status_label = frozen_label,
      -- A voided predecessor is frozen against every other change by the identity guard, including its
      -- revision. Being marked as replaced is the one fact it may still accept.
      revision = case when predecessor.voided_at is null then predecessor.revision + 1
                      else predecessor.revision end,
      updated_at = now()
  where organization_id = target_organization_id and id = predecessor.id;

  perform private.record_invoice_event(
    target_organization_id, predecessor.id, predecessor.invoice_number, predecessor.client_id,
    'invoice.replaced', caller, null, null,
    jsonb_build_object(
      'replaced_by_invoice_id', successor.id,
      'replaced_by_invoice_number', successor.invoice_number,
      'replacement_kind', successor.replacement_kind,
      'frozen_status_label', frozen_label
    ),
    false, null
  );
  perform private.record_invoice_event(
    target_organization_id, issued.id, issued.invoice_number, issued.client_id,
    'invoice.replacement_activated', caller, issued.revision, null,
    jsonb_build_object(
      'predecessor_invoice_id', predecessor.id,
      'predecessor_invoice_number', predecessor.invoice_number,
      'replacement_kind', issued.replacement_kind,
      'difference_minor', actual_difference_minor,
      'method', new_issue_method
    ),
    true, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'activate_invoice_replacement', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', issued.id,
      'invoice_number', issued.invoice_number,
      'revision', issued.revision,
      'issued_at', issued.issued_at,
      'issue_method', issued.issue_method,
      'replacement_kind', issued.replacement_kind,
      'predecessor_invoice_id', predecessor.id,
      'predecessor_invoice_number', predecessor.invoice_number,
      'predecessor_frozen_status_label', frozen_label,
      'difference_minor', actual_difference_minor
    )
  );
end;
$$;

comment on function public.activate_invoice_replacement(uuid, uuid, integer, bigint, text, text, text) is
  'Issues a replacement and retires the invoice it replaces in one transaction, freezing that invoice''s '
  'status label so history never ages. Refuses when the difference the user reviewed no longer matches, and '
  'moves no money.';

revoke all on function public.activate_invoice_replacement(uuid, uuid, integer, bigint, text, text, text)
  from public;
revoke execute on function public.activate_invoice_replacement(uuid, uuid, integer, bigint, text, text, text)
  from anon;
grant execute on function public.activate_invoice_replacement(uuid, uuid, integer, bigint, text, text, text)
  to authenticated;

-- 8. Closing the void gap -------------------------------------------------------------------------------------

-- Recreated only to add one refusal. 3b-2 already refuses a void on a draft, a replaced bill, a written-off
-- or by-hand-closed bill, and a fully paid one; the progress-invoice exclusion had to wait for the claims
-- above to exist. Everything else in this function is unchanged from 20260905120000.

create or replace function public.void_invoice(
  target_organization_id uuid,
  target_invoice_id uuid,
  new_reason text,
  new_note text,
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
  invoice_row public.invoices;
  ordinary_minor bigint;
  remaining_minor bigint;
  deposit_entry public.invoice_payment_allocations;
  released_minor bigint := 0;
  released_count integer := 0;
begin
  if caller is null then
    raise exception 'You must be signed in to void an invoice.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.void') then
    raise exception 'You do not have access to void invoices here.'
      using errcode = 'insufficient_privilege';
  end if;
  -- Whether this bill may be voided depends on what is sitting on it, so price visibility is part of the
  -- decision rather than only part of the display.
  perform private.require_invoice_price_access(target_organization_id);

  if new_reason is null
     or new_reason not in ('duplicate', 'created_in_error', 'client_request', 'other') then
    raise exception 'A void needs one of the four reasons.' using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'void_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Already-voided is refused inside the lock helper, in the words the customer-facing product uses.
  invoice_row := private.lock_invoice_for_payment(target_organization_id, target_invoice_id);

  if invoice_row.issued_at is null and invoice_row.recognized_at is null then
    raise exception 'A draft is deleted rather than voided.' using errcode = 'check_violation';
  end if;
  if invoice_row.replaced_at is not null then
    raise exception 'That bill has already been replaced, so it is history rather than an open bill.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.written_off_at is not null then
    raise exception 'Undo the write-off before voiding this bill.' using errcode = 'check_violation';
  end if;
  if invoice_row.marked_received_at is not null then
    raise exception 'Reopen this bill before voiding it.' using errcode = 'check_violation';
  end if;

  -- The contract's progress-invoice exclusion, real at last. 3b-2 could only leave this implied, because no
  -- installment claim existed for it to test. An installment's amount is fixed by the job's payment
  -- schedule, so cancelling one bill of that schedule outright would leave the schedule describing money
  -- nobody is being asked for; the correction chain replaces it instead, preserving the amount.
  if exists (
    select 1 from public.invoice_sources as claim
    where claim.organization_id = target_organization_id
      and claim.root_invoice_id = invoice_row.root_invoice_id
      and claim.source_kind = 'installment'
  ) then
    raise exception 'A progress invoice is corrected rather than voided.' using errcode = 'check_violation',
      hint = 'Prepare a correction: it keeps the payment schedule intact and replaces this bill.';
  end if;

  -- D2: ordinary money only. Deposits are counted separately because they are the one thing void resolves
  -- on the user's behalf.
  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into ordinary_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = target_organization_id
    and entry.invoice_id = invoice_row.id
    and entry.payment_event_id is not null;

  if ordinary_minor > 0 then
    raise exception 'This bill still has payments on it, so it cannot be voided yet.'
      using errcode = 'check_violation',
      detail = format('%s still applied to invoice #%s', ordinary_minor, invoice_row.invoice_number),
      hint = 'Take the payment back to client credit, move it to another invoice, or refund it first.';
  end if;

  remaining_minor := invoice_row.total_minor
    - private.invoice_allocated_minor(target_organization_id, invoice_row.id);
  if remaining_minor <= 0 then
    raise exception 'This bill is fully paid, so it cannot be voided.' using errcode = 'check_violation',
      hint = 'Take the money off it first if this bill should not have existed.';
  end if;

  -- The approved deposit release, in the same transaction as the void itself. Each live application gets
  -- the same retained unapplication an explicit unapply would have written.
  for deposit_entry in
    select entry.*
    from public.invoice_payment_allocations as entry
    where entry.organization_id = target_organization_id
      and entry.invoice_id = invoice_row.id
      and entry.entry_type = 'applied'
      and entry.deposit_event_id is not null
      and not exists (
        select 1 from public.invoice_payment_allocations as undone
        where undone.organization_id = entry.organization_id
          and undone.reversed_allocation_id = entry.id
      )
    order by entry.id
  loop
    perform private.reverse_invoice_allocation(
      invoice_row, deposit_entry, caller, 'Released because the invoice was voided'
    );
    released_minor := released_minor + deposit_entry.amount_minor;
    released_count := released_count + 1;
  end loop;

  update public.invoices
  set voided_at = now(),
      voided_by = caller,
      void_reason = new_reason,
      void_note = nullif(trim(coalesce(new_note, '')), ''),
      revision = invoice_row.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id and id = invoice_row.id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.voided', caller, invoice_row.revision + 1, new_note,
    jsonb_build_object(
      'reason', new_reason,
      'released_deposit_count', released_count,
      'released_deposit_minor', released_minor
    ),
    true, null
  );

  -- The cancellation notice to the client is a Communications send, queued after the state is secured. That
  -- seam belongs to Part 6 with the rest of invoice delivery; nothing is sent from inside these locks.
  return private.complete_invoice_command(
    target_organization_id, 'void_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'client_id', invoice_row.client_id,
      'reason', new_reason,
      'released_deposit_count', released_count,
      'released_deposit_minor', released_minor
    )
  );
end;
$$;

comment on function public.void_invoice(uuid, uuid, text, text, text, text) is
  'Cancels an issued bill for good, keeping it and its reason forever. Refuses while ordinary payments are '
  'still applied to it and for progress invoices, which are corrected instead, and releases any quote '
  'deposits back to client credit in the same transaction.';

revoke all on function public.void_invoice(uuid, uuid, text, text, text, text) from public;
revoke execute on function public.void_invoice(uuid, uuid, text, text, text, text) from anon;
grant execute on function public.void_invoice(uuid, uuid, text, text, text, text) to authenticated;
