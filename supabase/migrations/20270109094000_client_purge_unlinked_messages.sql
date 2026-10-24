-- Data privacy Part 3 follow-up (docs/data-privacy-deletion-engine.md § What happens to each kind of record): a
-- permanent customer delete also removes messages that came from the customer's own email address or phone but
-- were never linked to them. HubSpot's permanent delete removes the contact's conversations; in our inbox a message
-- stays unlinked when it arrived before that address was on the customer's card, or while it waits in review.
--
-- Only client_deletion_plan changes: the delete reads its message list from the plan, so attachments, forwards,
-- provider callbacks and the stored attachment files of these messages go with them, and the confirmation counts
-- them. Emails compare lower-cased, phones by digits, the same rules inbound matching uses.

create index if not exists communication_inbound_messages_unlinked_sender_idx
  on public.communication_inbound_messages (
    organization_id, (coalesce(lower(btrim(sender_email)), regexp_replace(sender_phone, '\D', '', 'g')))
  )
  where client_id is null;

create or replace function private.client_deletion_plan(target_organization_id uuid, target_client_id uuid)
  returns jsonb
  language plpgsql stable security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  org uuid := target_organization_id;
  c uuid := target_client_id;
  request_ids uuid[];
  quote_ids uuid[];
  shell_quote_ids uuid[];
  job_ids uuid[];
  visit_ids uuid[];
  assessment_ids uuid[];
  expense_ids uuid[];
  property_ids uuid[];
  shell_property_ids uuid[];
  draft_invoice_ids uuid[];
  kept_invoice_ids uuid[];
  opportunity_ids uuid[];
  review_request_ids uuid[];
  review_feedback_ids uuid[];
  inbound_message_ids uuid[];
  chat_session_ids uuid[];
  form_submission_ids uuid[];
  currency text;
  opening_receivable bigint := 0;
  opening_credit bigint := 0;
  payment_credit bigint;
  deposit_credit bigint;
  leftover bigint;
  blockers jsonb;
  counts jsonb;
  kept jsonb;
begin
  select coalesce(array_agg(id order by id), '{}') into request_ids
  from public.requests where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into quote_ids
  from public.quotes where organization_id = org and client_id = c;

  -- A quote that took a deposit or has a card checkout anchors money records (the deposit report and the
  -- invoice's payment list read the deposit through it), so it stays as an anonymous shell.
  select coalesce(array_agg(quote.id order by quote.id), '{}') into shell_quote_ids
  from public.quotes as quote
  where quote.organization_id = org and quote.client_id = c
    and (
      exists (
        select 1 from public.quote_deposit_events as deposit
        where deposit.organization_id = org and deposit.quote_id = quote.id
      )
      or exists (
        select 1 from public.payment_stripe_checkouts as checkout
        where checkout.organization_id = org and checkout.quote_id = quote.id
      )
    );

  select coalesce(array_agg(id order by id), '{}') into job_ids
  from public.jobs where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into visit_ids
  from public.job_visits where organization_id = org and job_id = any(job_ids);

  select coalesce(array_agg(id order by id), '{}') into assessment_ids
  from public.assessments where organization_id = org and request_id = any(request_ids);

  select coalesce(array_agg(id order by id), '{}') into expense_ids
  from public.job_expenses where organization_id = org and job_id = any(job_ids);

  select coalesce(array_agg(id order by id), '{}') into property_ids
  from public.properties where organization_id = org and client_id = c;

  select coalesce(array_agg(distinct property_id), '{}') into shell_property_ids
  from public.quotes where organization_id = org and id = any(shell_quote_ids);

  -- A settled bill is kept even if it was never issued, as delete_invoice_draft refuses it too.
  select coalesce(array_agg(id order by id) filter (where issued_at is null and recognized_at is null), '{}'),
         coalesce(array_agg(id order by id) filter (where issued_at is not null or recognized_at is not null), '{}')
  into draft_invoice_ids, kept_invoice_ids
  from public.invoices where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into opportunity_ids
  from public.opportunities where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into review_request_ids
  from public.review_requests where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into review_feedback_ids
  from public.review_feedback where organization_id = org and request_id = any(review_request_ids);

  -- Messages from this customer's own email address or phone that were never linked to them (they arrived before
  -- that address was on their card, or wait in review) are theirs too, as HubSpot's permanent delete removes the
  -- contact's conversations. Unlinked rows are found through their own partial index.
  select coalesce(array_agg(id order by id), '{}') into inbound_message_ids
  from (
    select message.id
    from public.communication_inbound_messages as message
    where message.organization_id = org and message.client_id = c
    union
    select message.id
    from public.communication_inbound_messages as message
    where message.organization_id = org and message.client_id is null
      and coalesce(lower(btrim(message.sender_email)), regexp_replace(message.sender_phone, '\D', '', 'g')) = any(array(
        select method.normalized_value
        from public.client_contact_methods as method
        where method.organization_id = org and method.client_id = c and method.kind in ('email', 'phone')
      ))
  ) as customer_messages;

  select coalesce(array_agg(id order by id), '{}') into chat_session_ids
  from public.website_chat_sessions where organization_id = org and client_id = c;

  select coalesce(array_agg(id order by id), '{}') into form_submission_ids
  from private.form_submissions where organization_id = org and result ->> 'client_id' = c::text;

  -- Money still open refuses the delete. An opening balance and unused credit settle against each other, so
  -- only what is left over between them counts.
  select coalesce(settings.currency_code, 'USD') into currency
  from public.organization_settings as settings where settings.organization_id = org;

  select coalesce(totals.receivable_minor, 0), coalesce(totals.credit_minor, 0)
  into opening_receivable, opening_credit
  from private.client_opening_balance_totals(org, array[c]) as totals;
  opening_receivable := coalesce(opening_receivable, 0);
  opening_credit := coalesce(opening_credit, 0);

  select coalesce(sum(private.payment_event_available_minor(org, receipt.id)), 0)::bigint into payment_credit
  from public.client_payment_events as receipt
  where receipt.organization_id = org and receipt.client_id = c and receipt.event_type = 'received';

  select coalesce(sum(private.deposit_event_available_minor(org, deposit.id)), 0)::bigint into deposit_credit
  from public.quote_deposit_events as deposit
  where deposit.organization_id = org and deposit.quote_id = any(quote_ids) and deposit.event_type = 'received';

  leftover := opening_receivable - opening_credit - payment_credit - deposit_credit;

  select coalesce(jsonb_agg(blocker - 'sort' order by blocker ->> 'sort'), '[]'::jsonb) into blockers
  from (
    select jsonb_build_object(
      'sort', 'a' || lpad(invoice.invoice_number::text, 12, '0'),
      'kind', 'invoice_unpaid',
      'label', 'Invoice #' || invoice.invoice_number
        || ' has an unpaid balance. Record the payment, void the invoice or write it off.',
      'invoice_id', invoice.id,
      'amount_minor', invoice.total_minor - coalesce(applied.amount_minor, 0),
      'currency_code', invoice.currency_code
    ) as blocker
    from public.invoices as invoice
    left join lateral (
      select sum(case when entry.entry_type = 'applied' then entry.amount_minor else -entry.amount_minor end)
        as amount_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = org and entry.invoice_id = invoice.id
    ) as applied on true
    where invoice.organization_id = org and invoice.client_id = c and invoice.is_effective_receivable
      and invoice.total_minor - coalesce(applied.amount_minor, 0) > 0

    -- A payment or deposit applied to a draft is the customer's money on a bill that was never issued, so the
    -- draft cannot go with them; delete_invoice_draft refuses it the same way.
    union all
    select jsonb_build_object(
      'sort', 'a' || lpad(invoice.invoice_number::text, 12, '0'),
      'kind', 'draft_invoice_holds_money',
      'label', 'Draft invoice #' || invoice.invoice_number
        || ' has money on it. Return it to client credit, then apply it to an invoice or refund it.',
      'invoice_id', invoice.id,
      'amount_minor', private.invoice_allocated_minor(org, invoice.id),
      'currency_code', invoice.currency_code
    )
    from public.invoices as invoice
    where invoice.organization_id = org and invoice.client_id = c
      and invoice.id = any(draft_invoice_ids)
      and private.invoice_allocated_minor(org, invoice.id) <> 0

    union all
    select jsonb_build_object(
      'sort', 'b', 'kind', 'opening_balance_owed',
      'label', 'They still owe an opening balance. Record the payment first.',
      'amount_minor', leftover, 'currency_code', currency)
    where leftover > 0

    union all
    select jsonb_build_object(
      'sort', 'c', 'kind', 'credit_unused',
      'label', 'They have unused credit or a deposit. Apply it to an invoice or refund it first.',
      'amount_minor', -leftover, 'currency_code', currency)
    where leftover < 0

    union all
    select jsonb_build_object(
      'sort', 'd', 'kind', 'card_payment_in_progress',
      'label', 'A card payment is still being processed. Try again once it has finished.')
    where exists (
      select 1 from public.payment_stripe_checkouts
      where organization_id = org and client_id = c and status in ('open', 'processing')
    )

    union all
    select jsonb_build_object(
      'sort', 'e', 'kind', 'refund_in_progress',
      'label', 'A card refund is still being processed. Try again once it has finished.')
    where exists (
      select 1 from public.payment_stripe_refunds as refund
      join public.payment_stripe_checkouts as checkout
        on checkout.organization_id = refund.organization_id and checkout.id = refund.checkout_id
      where refund.organization_id = org and checkout.client_id = c and refund.status = 'pending'
    )

    union all
    select jsonb_build_object(
      'sort', 'f', 'kind', 'message_sending',
      'label', 'A message to this customer is being sent right now. Try again in a minute.')
    where exists (
      select 1 from public.communication_delivery_intents as intent
      where intent.organization_id = org and intent.client_id = c
        and (
          intent.status in ('claimed', 'submission_unknown')
          or exists (
            select 1 from public.communication_outbox_events as outbox
            where outbox.delivery_intent_id = intent.id and outbox.status = 'processing'
          )
        )
    )
  ) as found;

  with gone(entity_type, entity_id) as (
    select 'client', c
    union all select 'property', unnest(property_ids)
    union all select 'request', unnest(request_ids)
    union all select 'quote', unnest(quote_ids)
    union all select 'job', unnest(job_ids)
    union all select 'visit', unnest(visit_ids)
    union all select 'job_expense', unnest(expense_ids)
    union all select 'assessment', unnest(assessment_ids)
    union all select 'invoice', unnest(draft_invoice_ids)
    union all select 'opportunity', unnest(opportunity_ids)
  )
  select jsonb_build_object(
    'requests', cardinality(request_ids),
    'quotes', cardinality(quote_ids),
    'jobs', cardinality(job_ids),
    'visits', cardinality(visit_ids),
    'properties', cardinality(property_ids),
    'contact_methods', (
      select count(*) from public.client_contact_methods where organization_id = org and client_id = c
    ),
    'messages',
      (select count(*) from public.communication_delivery_intents where organization_id = org and client_id = c)
      + cardinality(inbound_message_ids)
      + (select count(*) from public.website_chat_messages where organization_id = org and client_id = c),
    'notes', (
      select count(distinct link.note_id) from public.note_links as link
      join gone on gone.entity_type = link.entity_type and gone.entity_id = link.entity_id
      where link.organization_id = org
    ),
    'files', (
      select count(distinct file_id) from (
        select link.file_id from public.file_links as link
        join gone on gone.entity_type = link.entity_type and gone.entity_id = link.entity_id
        where link.organization_id = org
        union all
        select attachment.file_id from public.attachments as attachment
        join gone on gone.entity_type = attachment.entity_type and gone.entity_id = attachment.entity_id
        where attachment.organization_id = org and attachment.file_id is not null
      ) as linked
    ),
    'review_requests', cardinality(review_request_ids),
    'opportunities', cardinality(opportunity_ids),
    'draft_invoices', cardinality(draft_invoice_ids)
  ) into counts;

  select jsonb_build_object(
    'invoices', cardinality(kept_invoice_ids),
    'payments', (
      select count(*) from public.client_payment_events where organization_id = org and client_id = c
    ),
    'deposits', (
      select count(*) from public.quote_deposit_events
      where organization_id = org and quote_id = any(shell_quote_ids)
    ),
    'opening_balances', (
      select count(*) from public.client_opening_balances where organization_id = org and client_id = c
    )
  ) into kept;

  return jsonb_build_object(
    'request_ids', to_jsonb(request_ids),
    'quote_ids', to_jsonb(quote_ids),
    'shell_quote_ids', to_jsonb(shell_quote_ids),
    'job_ids', to_jsonb(job_ids),
    'visit_ids', to_jsonb(visit_ids),
    'assessment_ids', to_jsonb(assessment_ids),
    'expense_ids', to_jsonb(expense_ids),
    'property_ids', to_jsonb(property_ids),
    'shell_property_ids', to_jsonb(shell_property_ids),
    'draft_invoice_ids', to_jsonb(draft_invoice_ids),
    'kept_invoice_ids', to_jsonb(kept_invoice_ids),
    'opportunity_ids', to_jsonb(opportunity_ids),
    'review_request_ids', to_jsonb(review_request_ids),
    'review_feedback_ids', to_jsonb(review_feedback_ids),
    'inbound_message_ids', to_jsonb(inbound_message_ids),
    'chat_session_ids', to_jsonb(chat_session_ids),
    'form_submission_ids', to_jsonb(form_submission_ids),
    'counts', counts,
    'kept', kept,
    'blockers', blockers
  );
end;
$$;

alter function private.client_deletion_plan(uuid, uuid) owner to postgres;
revoke all on function private.client_deletion_plan(uuid, uuid) from public, anon, authenticated;

comment on function private.client_deletion_plan(uuid, uuid) is
  'What a permanent delete of one customer removes, what it keeps for the money records, and what refuses it. The one rule behind both the confirmation and the delete, so they can never disagree.';
