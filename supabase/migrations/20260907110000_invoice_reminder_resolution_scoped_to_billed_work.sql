-- Invoices 5b fix: a bill clears only the reminders it actually answered.
--
-- Part 5a wrote private.resolve_job_reminders_as_invoiced when the only way to bill a job was to bill all of
-- it, so its own comment -- "billing the whole job answers all of them" -- was true. 5b-2 (bill chosen visits)
-- and 5b-3 (bill one billing period) made it false. Billing August alone marked the pending September and
-- October reminders resolved/invoiced and rolled a fresh month-end, so months nobody had billed left the
-- "ready to bill" queue with no invoice, no line and no claim behind them: work that could never be billed
-- again, and revenue lost silently.
--
-- Part 2's approved design already names the rule -- resolve the reminders *consumed by this batch*, not every
-- pending one -- so this is an implementation repair, not a change of product behaviour. It matches Jobber's
-- model, where a job carries one reminder per period and creating an invoice completes the reminder it came
-- from, leaving the other periods asking.
--
-- What "consumed" means, per claim kind that Part 3c defines:
--
--   job_total       -> every pending reminder on that job. Unchanged: the whole job is now on a bill, so every
--                      prompt asking for it, including an on_completion one, is answered.
--   reminder_period -> that period's reminder, and only it.
--   visit           -> the per_visit reminder raised for that visit, if one is open. This also covers the
--                      visits a period claim sweeps in, because claim_invoice_sources writes those as ordinary
--                      'visit' claims on the same invoice.
--
-- The claims are read back rather than re-derived from the caller's arguments: they are the persisted record
-- of what was billed, they were written moments ago in this same transaction against an invoice row that was
-- also created in it, and they already include the visits a period swept in, which the arguments do not name.
--
-- Public surface is untouched: create_invoice_from_work keeps its signature, its permissions and its return
-- shape, so no API route, type or screen changes with this migration.

-- 1. Resolution, scoped to the work on the bill -----------------------------------------------------------

-- The arity changes (the job argument is gone, the invoice now carries the whole question), so the 5a version
-- is dropped rather than replaced. It is private and create_invoice_from_work below is its only caller.
drop function if exists private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid, uuid);

create or replace function private.resolve_job_reminders_as_invoiced(
  target_organization_id uuid,
  target_invoice_id uuid,
  actor uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  consumed_ids uuid[];
  reminder_row public.job_invoice_reminders;
  resolved_count integer := 0;
  month_end_jobs uuid[] := '{}'::uuid[];
  month_end_job_id uuid;
begin
  -- Which pending reminders did this bill's claims answer? Bounded work: the claims of one invoice, which
  -- claim_invoice_sources caps, joined to the reminders of those jobs. invoice_sources_root_idx serves the
  -- claim side and job_invoice_reminders_pending_due_idx serves the reminder side.
  select coalesce(array_agg(distinct reminder.id order by reminder.id), '{}'::uuid[])
    into consumed_ids
  from public.invoice_sources as claim
  join public.job_invoice_reminders as reminder
    on reminder.organization_id = claim.organization_id
   and reminder.job_id = claim.job_id
   and reminder.status = 'pending'
   and (
        claim.source_kind = 'job_total'
     or (claim.source_kind = 'reminder_period' and reminder.id = claim.reminder_id)
     or (claim.source_kind = 'visit'
         and reminder.reminder_kind = 'per_visit'
         and reminder.visit_id = claim.visit_id)
   )
  where claim.organization_id = target_organization_id
    and claim.root_invoice_id = target_invoice_id;

  if array_length(consumed_ids, 1) is null then
    return 0;
  end if;

  -- Locked in id order before the write, so two invoices racing over one job's reminders queue behind each
  -- other rather than deadlocking. Same lock ordering claim_invoice_sources uses for jobs and visits.
  perform 1
  from public.job_invoice_reminders
  where organization_id = target_organization_id
    and id = any(consumed_ids)
  order by id
  for update;

  for reminder_row in
    update public.job_invoice_reminders
    set status = 'resolved', resolution = 'invoiced', resolved_at = now(), resolved_by = actor
    where organization_id = target_organization_id
      and id = any(consumed_ids)
      -- Re-checked under the lock: a concurrent dismiss may have answered one of these first.
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

    -- A month-end reminder is a standing arrangement, not a one-off prompt: clearing one rolls the next one
    -- forward. Collected per job and rolled once below, so a job with a backlog does not seed a pile.
    if reminder_row.reminder_kind = 'monthly_last_day'
       and not (reminder_row.job_id = any(month_end_jobs)) then
      month_end_jobs := month_end_jobs || reminder_row.job_id;
    end if;
  end loop;

  -- After the loop, not inside it: seed_next_month_end_reminder is a no-op while any month-end reminder is
  -- still pending, so a job whose later months are still open correctly rolls nothing.
  foreach month_end_job_id in array month_end_jobs loop
    perform private.seed_next_month_end_reminder(target_organization_id, month_end_job_id, actor);
  end loop;

  return resolved_count;
end;
$$;

comment on function private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid) is
  'Clears the invoice reminders a bill actually answered, read from the claims on that bill: every pending '
  'reminder on a job billed whole, the named reminder of a billed period, and the per-visit reminder of each '
  'billed visit. Rolls a job''s month-end reminder forward only when a month-end reminder was one of them. '
  'Called only by create_invoice_from_work, whose caller already proved invoices.create by billing the work.';

revoke all on function private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid) from public;
revoke execute on function private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid)
  from anon, authenticated;

-- 2. The bridge, calling it once ----------------------------------------------------------------------------

-- Unchanged from 5a except for the resolution step: the per-job loop is gone, because the question is no
-- longer "which jobs were touched" but "what did this bill claim", and the claims already say so.
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
      'reminders_resolved', reminders_resolved
    )
  );
end;
$$;

comment on function public.create_invoice_from_work(
  uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text
) is
  'Creates a draft invoice for a client''s job work and claims that work in the same transaction, then '
  'clears the invoice reminders that work answered. Composes create_invoice_draft and claim_invoice_sources '
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
