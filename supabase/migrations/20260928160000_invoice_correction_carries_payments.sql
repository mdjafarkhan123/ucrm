-- Deferred launch sweep Part 4d (decision D6): correcting an issued invoice carries what was already paid.
--
-- 1. activate_invoice_replacement moves every live application on the original (payments and quote deposits)
--    onto the replacement, oldest first, up to its total; any excess stays with the client as credit. The
--    result and the replaced event report carried_minor.
-- 2. issue_invoice refuses a correction or rebill draft: a plain Send would issue it without retiring the bill
--    it replaces, leaving the client billed twice.
-- 3. apply_invoice_allocation refuses money on an un-activated correction or rebill draft, which would
--    otherwise settle it quietly while the original is still live.

create or replace function "private"."apply_invoice_allocation"("invoice_row" "public"."invoices", "target_payment_event_id" "uuid", "target_deposit_event_id" "uuid", "new_amount_minor" bigint, "actor" "uuid", "new_reason" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  allocation_id uuid;
  remaining bigint;
begin
  if new_amount_minor is null or new_amount_minor <= 0 then
    raise exception 'A payment amount must be more than zero.' using errcode = 'check_violation';
  end if;

  -- An un-activated correction or rebill is not owed yet; money taken on it would quietly settle it while the
  -- bill it replaces is still live. Payments reach it when it is activated (D6).
  if invoice_row.predecessor_invoice_id is not null
     and invoice_row.issued_at is null and invoice_row.recognized_at is null then
    raise exception 'This invoice replaces an earlier one. Payments move onto it when it is activated.'
      using errcode = 'check_violation';
  end if;

  remaining := invoice_row.total_minor
    - private.invoice_allocated_minor(invoice_row.organization_id, invoice_row.id);
  if new_amount_minor > remaining then
    raise exception 'That is more than invoice #% still owes.', invoice_row.invoice_number
      using errcode = 'check_violation',
      detail = format('%s remaining, %s offered', remaining, new_amount_minor);
  end if;

  insert into public.invoice_payment_allocations (
    organization_id, invoice_id, invoice_number, client_id, entry_type, amount_minor, currency_code,
    payment_event_id, deposit_event_id, reason, actor_user_id
  ) values (
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'applied', new_amount_minor, invoice_row.currency_code,
    target_payment_event_id, target_deposit_event_id, nullif(trim(coalesce(new_reason, '')), ''), actor
  )
  returning id into allocation_id;

  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.payment_applied', actor, invoice_row.revision, new_reason,
    jsonb_build_object(
      'allocation_id', allocation_id,
      'amount_minor', new_amount_minor,
      'source', case when target_deposit_event_id is not null then 'quote_deposit' else 'payment' end
    ),
    true, null
  );

  perform private.recognize_invoice_if_settled(
    invoice_row.organization_id, invoice_row.id, actor
  );

  return allocation_id;
end;
$$;

create or replace function "public"."issue_invoice"("target_organization_id" "uuid", "target_invoice_id" "uuid", "expected_revision" integer, "new_issue_method" "text", "new_idempotency_key" "text", "new_request_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  settings_row public.organization_settings;
  invoice_row public.invoices;
  issued public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to issue an invoice.'
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

  replayed := private.begin_invoice_command(
    target_organization_id, 'issue_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for share;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision, 'invoices.send'
  );

  if invoice_row.issued_at is not null then
    raise exception 'This invoice has already been issued.' using errcode = 'check_violation';
  end if;
  -- A correction or rebill goes out only through activate_invoice_replacement, which retires the bill it
  -- replaces in the same step. Issued on its own, both bills would be live and the client billed twice.
  if invoice_row.predecessor_invoice_id is not null then
    raise exception 'This invoice replaces an earlier one. Use Replace invoice to send it.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.recognized_at is not null then
    raise exception 'This invoice was already settled and cannot be issued.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.currency_code is distinct from settings_row.currency_code then
    raise exception 'This draft was written in a different currency. Refresh it before issuing it.'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from public.invoice_lines
    where organization_id = target_organization_id and invoice_id = target_invoice_id
  ) then
    raise exception 'An invoice needs at least one line before it can be issued.'
      using errcode = 'check_violation';
  end if;

  update public.invoices
  set issued_at = now(),
      issued_by = caller,
      issue_method = new_issue_method,
      document_frozen_at = now(),
      revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id
  returning * into issued;

  perform private.record_invoice_event(
    target_organization_id, issued.id, issued.invoice_number, issued.client_id,
    'invoice.issued', caller, issued.revision, null,
    jsonb_build_object('method', new_issue_method), false, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'issue_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', issued.id,
      'invoice_number', issued.invoice_number,
      'revision', issued.revision,
      'issued_at', issued.issued_at,
      'issue_method', issued.issue_method,
      'due_date', issued.due_date
    )
  );
end;
$$;

create or replace function "public"."activate_invoice_replacement"("target_organization_id" "uuid", "target_invoice_id" "uuid", "expected_revision" integer, "previewed_difference_minor" bigint, "new_issue_method" "text", "new_idempotency_key" "text", "new_request_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  settings_row public.organization_settings;
  successor public.invoices;
  predecessor public.invoices;
  frozen_label text;
  actual_difference_minor bigint;
  issued public.invoices;
  live public.invoice_payment_allocations;
  room bigint;
  carried bigint := 0;
  carry bigint;
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

  -- D6: what the client already paid on the original still counts. Every live application on it -- payment or
  -- quote deposit -- is taken off and put on the replacement, oldest first, up to the replacement's total. Any
  -- excess simply stays with the client as credit. Taken off directly rather than through
  -- reverse_invoice_allocation: that helper refuses money that settled a draft, which is exactly the case a
  -- correction of a paid-on-the-spot bill has to move.
  room := issued.total_minor - private.invoice_allocated_minor(target_organization_id, issued.id);
  for live in
    select allocation.*
    from public.invoice_payment_allocations as allocation
    where allocation.organization_id = target_organization_id
      and allocation.invoice_id = predecessor.id
      and allocation.entry_type = 'applied'
      and not exists (
        select 1 from public.invoice_payment_allocations as reversal
        where reversal.organization_id = allocation.organization_id
          and reversal.reversed_allocation_id = allocation.id
      )
    order by allocation.created_at, allocation.id
  loop
    insert into public.invoice_payment_allocations (
      organization_id, invoice_id, invoice_number, client_id, entry_type, amount_minor, currency_code,
      payment_event_id, deposit_event_id, reversed_allocation_id, reason, actor_user_id
    ) values (
      live.organization_id, live.invoice_id, live.invoice_number, live.client_id, 'unapplied',
      live.amount_minor, live.currency_code, live.payment_event_id, live.deposit_event_id, live.id,
      'Moved to corrected invoice #' || issued.invoice_number, caller
    );
    carry := least(live.amount_minor, room);
    if carry > 0 then
      select * into issued from public.invoices
      where organization_id = target_organization_id and id = issued.id;
      perform private.apply_invoice_allocation(
        issued, live.payment_event_id, live.deposit_event_id, carry, caller,
        'Moved from invoice #' || predecessor.invoice_number
      );
      room := room - carry;
      carried := carried + carry;
    end if;
  end loop;

  perform private.record_invoice_event(
    target_organization_id, predecessor.id, predecessor.invoice_number, predecessor.client_id,
    'invoice.replaced', caller, null, null,
    jsonb_build_object(
      'replaced_by_invoice_id', successor.id,
      'replaced_by_invoice_number', successor.invoice_number,
      'replacement_kind', successor.replacement_kind,
      'frozen_status_label', frozen_label,
      'carried_minor', carried
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
      'difference_minor', actual_difference_minor,
      'carried_minor', carried
    )
  );
end;
$$;
