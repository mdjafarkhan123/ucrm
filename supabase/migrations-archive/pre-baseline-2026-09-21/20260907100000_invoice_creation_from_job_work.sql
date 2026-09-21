-- Invoices Part 5a: turning a job into a bill.
--
-- Everything the money side needs already exists. Part 3a writes drafts, Part 3c claims the work so one unit
-- of work is billed once, and Jobs Part 11b raises the reminder that says "time to bill this". What was
-- missing is the bridge: a way to see what work a client has waiting, and a single write that creates the
-- draft, claims that work, and clears the reminder together.
--
-- Two things live here and nothing else:
--
--   1. public.client_billable_work  -- what can I bill for this client?
--   2. public.create_invoice_from_work -- create the draft, claim the work, clear the reminders, at once.
--
-- Scope note, deliberate: this file bills a WHOLE job (source kind 'job_total'). Picking individual completed
-- visits, billing periods and payment-schedule installments are the other three claim kinds Part 3c already
-- reserved slots for; they arrive with their own screens in 5b and 5c. Nothing here forecloses them -- the
-- command takes the same source array claim_invoice_sources already understands.

-- 1. What work is waiting to be billed ----------------------------------------------------------------------

-- The picker behind "Create invoice" on a job: every job of one client that no invoice has claimed yet.
--
-- This read is scoped to ONE CLIENT, which is what keeps it cheap forever. It never grows with the size of
-- the organization, only with how many jobs a single client has accumulated -- tens, not thousands -- and
-- jobs_client_idx (organization_id, client_id, created_at desc, id) serves exactly that predicate and order.
-- The "already billed?" test is one probe per candidate row into invoice_sources_job_idx.
--
-- The cap is the same 100 that claim_invoice_sources enforces on a single invoice: showing work that could
-- not be claimed in one go would be a promise the next screen cannot keep.
create or replace function public.client_billable_work(
  target_organization_id uuid,
  target_client_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  today date;
  billable jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to bill work.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to bill work here.' using errcode = 'insufficient_privilege';
  end if;
  -- The picker's whole purpose is to compare amounts before choosing. A reader who cannot see job prices
  -- would get a list of blanks, which is worse than an honest refusal.
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to job prices, so there is nothing to compare here.'
      using errcode = 'insufficient_privilege';
  end if;

  select calendar.today into today
  from private.organization_calendars() as calendar
  where calendar.organization_id = target_organization_id;

  select coalesce(jsonb_agg(entry order by entry->>'created_at' desc), '[]'::jsonb) into billable
  from (
    select jsonb_build_object(
      'job_id', job.id,
      'job_number', job.job_number,
      'title', job.title,
      'job_type', job.job_type,
      'created_at', job.created_at,
      'currency_code', job.currency_code,
      'derived_status', private.job_derived_status(
        job.status,
        job.job_type,
        job.contract_end_date,
        today,
        exists (
          select 1
          from public.job_invoice_reminders as reminder
          where reminder.organization_id = job.organization_id
            and reminder.job_id = job.id
            and reminder.status = 'pending'
            and reminder.due_on <= today
        )
      ),
      'property_id', job.property_id,
      'property_label', property.label,
      'property_address_line1', property.address_line1,
      'property_city', property.city,
      'property_state_region', property.state_region,
      'property_postal_code', property.postal_code,
      'subtotal_minor', job.subtotal_minor,
      -- Nothing on this job has been billed -- that is the only way it reaches this list -- so everything it
      -- is worth is still uninvoiced. 5b's per-visit billing is what makes these two figures diverge.
      'uninvoiced_minor', job.total_minor,
      'total_minor', job.total_minor,
      'line_count', (
        select count(*) from public.job_line_items as line
        where line.organization_id = job.organization_id
          and line.job_id = job.id
          and line.line_kind = 'priced'
      ),
      'last_visit_date', visits.last_visit_date,
      'visit_count', coalesce(visits.visit_count, 0),
      'completed_visit_count', coalesce(visits.completed_visit_count, 0),
      -- The reminder that put this job in "Requires invoicing", so the screen can say why it is here and the
      -- command below knows which prompt this bill answers.
      'due_reminder_id', (
        select reminder.id
        from public.job_invoice_reminders as reminder
        where reminder.organization_id = job.organization_id
          and reminder.job_id = job.id
          and reminder.status = 'pending'
          and reminder.due_on <= today
        order by reminder.due_on, reminder.id
        limit 1
      )
    ) as entry
    from public.jobs as job
    left join public.properties as property
      on property.organization_id = job.organization_id and property.id = job.property_id
    left join lateral (
      select
        max(visit.visit_date) as last_visit_date,
        count(*) as visit_count,
        count(*) filter (where visit.completed_at is not null) as completed_visit_count
      from public.job_visits as visit
      where visit.organization_id = job.organization_id and visit.job_id = job.id
    ) as visits on true
    where job.organization_id = target_organization_id
      and job.client_id = target_client_id
      -- Any claim at all disqualifies the job from being billed as a whole, which is the same rule
      -- claim_invoice_sources enforces. Checking it here means the picker never offers work the next screen
      -- would refuse.
      and not exists (
        select 1
        from public.invoice_sources as claim
        where claim.organization_id = job.organization_id
          and claim.job_id = job.id
      )
    order by job.created_at desc, job.id
    limit 100
  ) as candidates;

  return billable;
end;
$$;

comment on function public.client_billable_work(uuid, uuid) is
  'Every job of one client that no invoice has claimed yet, with the figures the "select work to invoice" '
  'picker compares. Scoped to one client and capped at the 100 sources one invoice can claim. Needs '
  'invoices.create and jobs.view_price.';

revoke all on function public.client_billable_work(uuid, uuid) from public;
revoke execute on function public.client_billable_work(uuid, uuid) from anon;
grant execute on function public.client_billable_work(uuid, uuid) to authenticated;

-- 2. Clearing the prompt that asked for this bill -------------------------------------------------------------

-- The Jobs contract's other half of resolution: a reminder cleared by actually invoicing, not by hand.
--
-- Deliberately private and deliberately without the jobs.edit check that dismiss_job_invoice_reminder makes.
-- Dismissing is an editorial act on the job -- "stop asking me". This is not: the caller has already proved
-- invoices.create and has just billed the work the reminder was asking about, so the prompt is answered by
-- the fact, not by a second permission.
create or replace function private.resolve_job_reminders_as_invoiced(
  target_organization_id uuid,
  target_job_id uuid,
  target_invoice_id uuid,
  actor uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reminder_row public.job_invoice_reminders;
  resolved_count integer := 0;
  rolled_month_end boolean := false;
begin
  -- Every pending reminder on the job, due or not: billing the whole job answers all of them. Ordered by id
  -- so two invoices racing on one job queue behind each other rather than deadlocking.
  for reminder_row in
    update public.job_invoice_reminders
    set status = 'resolved', resolution = 'invoiced', resolved_at = now(), resolved_by = actor
    where organization_id = target_organization_id
      and job_id = target_job_id
      and status = 'pending'
    returning *
  loop
    resolved_count := resolved_count + 1;

    -- related_invoice_id is what makes the job's own history say which bill answered this prompt, rather
    -- than only that something did.
    insert into public.job_events
      (organization_id, job_id, event_type, actor_id, related_invoice_id, metadata)
    values (
      target_organization_id,
      reminder_row.job_id,
      'invoice_reminder_invoiced',
      actor,
      target_invoice_id,
      jsonb_build_object('reminder_kind', reminder_row.reminder_kind, 'due_on', reminder_row.due_on)
    );

    -- A month-end reminder is a standing arrangement, not a one-off prompt: clearing this month's rolls next
    -- month's forward. Once per call even if several were open, so a backlog does not seed a pile of them.
    if reminder_row.reminder_kind = 'monthly_last_day' and not rolled_month_end then
      perform private.seed_next_month_end_reminder(target_organization_id, reminder_row.job_id, actor);
      rolled_month_end := true;
    end if;
  end loop;

  return resolved_count;
end;
$$;

comment on function private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid, uuid) is
  'Clears a job''s pending invoice reminders with resolution = invoiced when its work is billed, rolling a '
  'month-end reminder forward once. Called only by create_invoice_from_work, whose caller already proved '
  'invoices.create by billing the work the reminder asked about.';

revoke all on function private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid, uuid) from public;
revoke execute on function private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid, uuid)
  from anon, authenticated;

-- 3. Create the draft and claim its work, together --------------------------------------------------------------

-- The bridge itself.
--
-- Why one command rather than two calls from the API route: a plpgsql function is one transaction, so the
-- draft and its claims either both exist or neither does. Two RPC calls are two transactions, and a crash
-- between them leaves a draft that does not own its work -- which is precisely the state invoice_sources
-- exists to make impossible. Jobber's own invoiceCreate takes the source work in the same mutation.
--
-- It composes the two shipped, pgTAP-tested commands rather than reimplementing either. Each keeps its own
-- command receipt under its own action name, so a retry replays all three layers consistently.
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
  job_id uuid;
  reminders_resolved integer := 0;
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

  -- Whatever work went on the bill, the prompts that asked for it are answered. Distinct because two sources
  -- may belong to the same job.
  for job_id in
    select distinct nullif(element.value->>'job_id', '')::uuid
    from jsonb_array_elements(new_sources) as element(value)
    order by 1
  loop
    reminders_resolved := reminders_resolved
      + private.resolve_job_reminders_as_invoiced(
          target_organization_id, job_id, created_invoice_id, caller
        );
  end loop;

  return private.complete_invoice_command(
    target_organization_id, 'create_invoice_from_work', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', created_invoice_id,
      'invoice_number', (draft->>'invoice_number')::integer,
      'revision', (draft->>'revision')::integer,
      'claimed_count', (claimed->>'claimed_count')::integer,
      'consumed_visit_count', (claimed->>'consumed_visit_count')::integer,
      'reminders_resolved', reminders_resolved
    )
  );
end;
$$;

comment on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) is
  'Creates a draft invoice for a client''s job work and claims that work in the same transaction, then '
  'clears the invoice reminders the work answered. Composes create_invoice_draft and claim_invoice_sources '
  'so a bill can never exist without owning its sources.';

revoke all on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) from public;
revoke execute on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) from anon;
grant execute on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) to authenticated;
