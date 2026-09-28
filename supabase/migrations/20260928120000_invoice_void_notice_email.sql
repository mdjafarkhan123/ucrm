-- Deferred launch sweep Part 4a (decision D9): when an issued invoice is voided, the office can email the
-- client that it is cancelled.
--
-- 1. enqueue_invoice_void_notice_email queues that one email. It is the invoice email's twin -- same default
--    automated sender, same primary-email recipient, same outbox -- with three differences:
--    * the invoice must already be voided, and must have been issued (sent or marked sent), because a bill
--      the client never received needs no cancellation;
--    * the send key is fixed per invoice ('invoice-void-notice:<id>'), so a double click or a retry can never
--      send two notices;
--    * the delivery intent carries no invoice_id. invoice_id on an intent means "this bill was sent", which
--      drives the invoice's Last sent fact and the batch-deliver picker; a cancellation is not a send.
--    The email carries no link: the bill is cancelled and there is nothing left to view or pay.
-- 2. invoice_detail adds delivery.void_notice so the Voided banner can say whether the client was told.

create or replace function public.enqueue_invoice_void_notice_email(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_invoice_id uuid
)
returns public.communication_delivery_intents
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  send_key text := 'invoice-void-notice:' || target_invoice_id::text;
  invoice_row public.invoices; client_row public.clients;
  recipient public.client_contact_methods;
  business_name text; greeting_name text; money_text text; issued_text text;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
begin
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'invoices.void')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send') then
    raise exception 'You do not have permission to email this client.' using errcode = 'insufficient_privilege';
  end if;

  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = send_key for share;
  if intent.id is not null then
    return intent;
  end if;

  select * into invoice_row from public.invoices
    where organization_id = target_organization_id and id = target_invoice_id for share;
  if invoice_row.id is null or invoice_row.voided_at is null then
    raise exception 'Only a voided invoice has a cancellation notice.' using errcode = 'foreign_key_violation';
  end if;
  if invoice_row.issued_at is null then
    raise exception 'This invoice was never sent to the client, so there is nothing to cancel with them.'
      using errcode = 'check_violation';
  end if;

  select * into client_row from public.clients
    where organization_id = invoice_row.organization_id and id = invoice_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = invoice_row.organization_id and client_id = invoice_row.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if client_row.id is null or recipient.id is null then
    raise exception 'This client has no email address to send the cancellation to.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select organization.name into business_name from public.organizations as organization
    where organization.id = invoice_row.organization_id;
  business_name := coalesce(nullif(trim(business_name), ''), 'your contractor');
  greeting_name := nullif(trim(client_row.display_name), '');

  -- The organization's default automated sender, exactly as enqueue_invoice_communication_email chooses it.
  select * into sender from public.communication_email_senders
    where organization_id = invoice_row.organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    raise exception 'No automated email sender is ready for this business.' using errcode = 'object_not_in_prerequisite_state';
  end if;

  money_text := private.format_minor(invoice_row.total_minor, invoice_row.currency_code);
  issued_text := to_char(coalesce(invoice_row.issue_date, invoice_row.issued_at::date), 'FMMonth FMDD, YYYY');

  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by)
    values (invoice_row.organization_id, invoice_row.client_id, recipient.id, send_key, recipient.normalized_value,
      'Invoice #' || invoice_row.invoice_number || ' from ' || business_name || ' has been cancelled',
      coalesce('<p>Hi ' || private.html_escape(greeting_name) || ',</p>', '')
        || '<p>Invoice #' || invoice_row.invoice_number || ' for ' || private.html_escape(money_text)
        || ', sent on ' || issued_text || ', has been cancelled. You do not need to pay it.</p>'
        || '<p>If you have any questions, please get in touch.</p>'
        || '<p>' || private.html_escape(business_name) || '</p>',
      coalesce('Hi ' || greeting_name || E',\n\n', '')
        || 'Invoice #' || invoice_row.invoice_number || ' for ' || money_text || ', sent on ' || issued_text
        || E', has been cancelled. You do not need to pay it.\n\nIf you have any questions, please get in touch.\n\n'
        || business_name,
      'automated', 'essential', sender.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);
  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.void_notice_queued', target_actor_user_id, null, null,
    jsonb_build_object('delivery_intent_id', intent.id, 'recipient_email', recipient.normalized_value)
  );
  return intent;
end;
$$;

revoke all on function public.enqueue_invoice_void_notice_email(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.enqueue_invoice_void_notice_email(uuid, uuid, uuid) to service_role;

comment on function public.enqueue_invoice_void_notice_email(uuid, uuid, uuid) is
  'Queues the one "this invoice is cancelled" email for a voided, previously issued invoice. Idempotent per invoice. Carries no invoice_id so it never counts as sending the bill. Service role only.';

create or replace function "public"."invoice_detail"("target_organization_id" "uuid", "target_invoice_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  can_see_price boolean;
  today date;
  invoice_row public.invoices;
  applied_minor bigint;
  derived_status text;
  money jsonb;
  payment_history jsonb;
  current_document jsonb;
  document_history jsonb;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  can_see_price := private.member_has_permission(target_organization_id, caller, 'invoices.view_price');
  today := private.organization_today(target_organization_id);

  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;

  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into applied_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = target_organization_id and entry.invoice_id = target_invoice_id;

  derived_status := case
    when invoice_row.replaced_at is not null then invoice_row.frozen_status_label
    else private.invoice_live_status(
      invoice_row.voided_at, invoice_row.written_off_at, invoice_row.issued_at, invoice_row.recognized_at,
      invoice_row.marked_received_at, invoice_row.total_minor, applied_minor, invoice_row.due_date, today)
  end;

  if can_see_price then
    money := jsonb_build_object(
      'subtotal_minor', invoice_row.subtotal_minor,
      'discount_minor', invoice_row.discount_minor,
      'discount_name', invoice_row.discount_name,
      'discount_type', invoice_row.discount_type,
      'discount_value', invoice_row.discount_value,
      'tax_minor', invoice_row.tax_minor,
      'tax_source', invoice_row.tax_source,
      'tax_name', invoice_row.tax_name,
      'tax_rate_id', invoice_row.tax_rate_id,
      'tax_rate_basis_points', invoice_row.tax_rate_basis_points,
      'total_minor', invoice_row.total_minor,
      'allocated_minor', applied_minor,
      'remaining_minor', invoice_row.total_minor - applied_minor
    );

    -- The bill's money history: one row per application/unapplication, newest last so the list reads
    -- top-to-bottom as it happened. A source is either a manual receipt (client_payment_events) or a reused
    -- quote deposit (quote_deposit_events); exactly one side of the two left joins is ever populated, per
    -- invoice_payment_allocations_one_source. Gated the same as money -- this is money, not just a fact of
    -- the bill's existence.
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', allocation.id,
      'payment_event_id', allocation.payment_event_id,
      'entry_type', allocation.entry_type,
      'amount_minor', allocation.amount_minor,
      'created_at', allocation.created_at,
      'source', case when allocation.deposit_event_id is not null then 'deposit' else 'payment' end,
      'method', coalesce(payment.method, deposit.method),
      'payment_date', coalesce(payment.payment_date, deposit.created_at::date),
      'reference', coalesce(payment.reference, deposit.reference),
      'note', coalesce(payment.note, deposit.note),
      'reason', allocation.reason
    ) order by allocation.created_at, allocation.id), '[]'::jsonb)
    into payment_history
    from public.invoice_payment_allocations as allocation
    left join public.client_payment_events as payment
      on payment.organization_id = target_organization_id and payment.id = allocation.payment_event_id
    left join public.quote_deposit_events as deposit
      on deposit.organization_id = target_organization_id and deposit.id = allocation.deposit_event_id
    where allocation.organization_id = target_organization_id
      and allocation.invoice_id = target_invoice_id;

    -- The document's own edit history. `before` is the snapshot the event itself carries; `after` is the
    -- next edit's `before`, or -- for the newest edit -- the document as it stands right now. Empty on a
    -- draft (nothing has frozen yet, so retain_prior_invoice_document never wrote a row) and empty on an
    -- issued bill nobody has edited since.
    current_document := private.invoice_document_snapshot(invoice_row.id);

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', ordered.id,
      'created_at', ordered.created_at,
      'actor_name', profile.full_name,
      'reason', ordered.reason,
      'before', ordered.prior_document_snapshot,
      'after', coalesce(ordered.next_snapshot, current_document)
    ) order by ordered.created_at desc, ordered.id desc), '[]'::jsonb)
    into document_history
    from (
      select event.id, event.created_at, event.reason, event.actor_id, event.prior_document_snapshot,
             lead(event.prior_document_snapshot) over (order by event.created_at, event.id) as next_snapshot
      from public.invoice_events as event
      where event.organization_id = target_organization_id
        and event.invoice_id = target_invoice_id
        and event.event_type = 'invoice.document_edited'
    ) as ordered
    left join public.profiles as profile on profile.id = ordered.actor_id;
  else
    money := null;
    payment_history := null;
    document_history := null;
  end if;

  return jsonb_build_object(
    'invoice', jsonb_build_object(
      'id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'revision', invoice_row.revision,
      'subject', invoice_row.subject,
      'currency_code', invoice_row.currency_code,
      'issue_date', invoice_row.issue_date,
      'due_date', invoice_row.due_date,
      'due_date_source', invoice_row.due_date_source,
      'payment_term_snapshot', invoice_row.payment_term_snapshot,
      'contract_disclaimer', invoice_row.contract_disclaimer,
      'customer_snapshot', invoice_row.customer_snapshot,
      'billing_address_snapshot', invoice_row.billing_address_snapshot,
      'service_properties', invoice_row.service_properties,
      'issued_at', invoice_row.issued_at,
      'issue_method', invoice_row.issue_method,
      'voided_at', invoice_row.voided_at,
      'void_reason', invoice_row.void_reason,
      'void_note', invoice_row.void_note,
      'written_off_at', invoice_row.written_off_at,
      'write_off_note', invoice_row.write_off_note,
      'marked_received_at', invoice_row.marked_received_at,
      'recognized_at', invoice_row.recognized_at,
      'replaced_at', invoice_row.replaced_at,
      'replaced_by_invoice_id', invoice_row.replaced_by_invoice_id,
      'predecessor_invoice_id', invoice_row.predecessor_invoice_id,
      'replacement_kind', invoice_row.replacement_kind,
      'is_replaced', invoice_row.replaced_at is not null,
      'derived_status', derived_status,
      'client_id', invoice_row.client_id,
      'created_at', invoice_row.created_at
    ),
    'client', (
      select case when client.id is null then null else jsonb_build_object(
        'id', client.id,
        'display_name', client.display_name,
        'company_name', client.company_name,
        'email', (
          select lower(trim(method.value))
          from public.client_contact_methods as method
          where method.organization_id = target_organization_id
            and method.client_id = client.id
            and method.kind = 'email'
          order by method.is_primary desc, method.created_at
          limit 1
        )
      ) end
      from public.clients as client
      where client.organization_id = target_organization_id and client.id = invoice_row.client_id
    ),
    'money', money,
    'payment_history', payment_history,
    'document_history', document_history,
    'progress', private.invoice_progress_context(invoice_row),
    'delivery', jsonb_build_object(
      'last_sent', (
        select case when intent.id is null then null else jsonb_build_object(
          'sent_at', intent.created_at,
          'status', intent.status,
          'recipient_email', intent.recipient_email
        ) end
        from public.communication_delivery_intents as intent
        where intent.organization_id = target_organization_id and intent.invoice_id = target_invoice_id
        order by intent.created_at desc, intent.id desc
        limit 1
      ),
      -- The cancellation notice is deliberately not linked by invoice_id, so it never reads as the bill being
      -- sent. It is found by its one fixed send key instead.
      'void_notice', (
        select jsonb_build_object(
          'sent_at', intent.created_at,
          'status', intent.status,
          'recipient_email', intent.recipient_email
        )
        from public.communication_delivery_intents as intent
        where intent.organization_id = target_organization_id
          and intent.logical_send_key = 'invoice-void-notice:' || target_invoice_id::text
      ),
      'views', (
        select jsonb_build_object(
          'first_viewed_at', min(link.first_viewed_at),
          'last_viewed_at', max(link.last_viewed_at),
          'view_count', coalesce(sum(link.view_count), 0)
        )
        from public.invoice_access_links as link
        where link.organization_id = target_organization_id and link.invoice_id = target_invoice_id
      )
    ),
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', line.id,
        'position', line.position,
        'line_kind', line.line_kind,
        'category', line.category,
        'name', line.name,
        'description', line.description,
        'unit_label', line.unit_label,
        'quantity', line.quantity,
        'is_taxable', line.is_taxable,
        'service_date', line.service_date,
        'unit_price_minor', case when can_see_price then line.unit_price_minor else null end,
        'line_total_minor', case when can_see_price then line.line_total_minor else null end,
        'progress_original_amount_minor',
          case when can_see_price then line.progress_original_amount_minor else null end
      ) order by line.position, line.id), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = target_organization_id and line.invoice_id = target_invoice_id
    )
  );
end;
$$;
