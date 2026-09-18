-- Online payments Part 4: a customer pays a quote's deposit online through the contractor's own Stripe account.
--
-- docs/online-payments-behavior-contract.md §4. This reuses Part 3's checkout table and webhook journal rather
-- than duplicating them: a Stripe Checkout attempt now points at either an invoice or a quote's deposit, and
-- the one function that reacts to Stripe's signed confirmation ("apply_stripe_checkout_event") gets a second
-- branch instead of a second copy. `quote_ready_for_job` already only asks "is there any live received
-- deposit event", so a Stripe-confirmed deposit makes a quote job-ready with no change to that function.
--
-- The same three rules from Part 3 still hold: a payment counts once (the webhook journal and the row lock
-- are unchanged), a confirmation never fails for a business reason (if the deposit was already recorded some
-- other way by the time Stripe confirms, the money is left recorded nowhere but alerted for a manual refund,
-- never silently double-recorded), and nothing here trusts an amount from the browser or the webhook payload.

-- 1. "Card (online)" joins the deposit's own methods --------------------------------------------------------

alter table public.quote_deposit_events drop constraint quote_deposit_events_method_check;
alter table public.quote_deposit_events add constraint quote_deposit_events_method_check
  check (method in ('cash', 'check', 'other', 'stripe_card', 'stripe_bank', 'stripe_other'));

-- 2. One checkout table, two kinds of target -----------------------------------------------------------------

alter table public.payment_stripe_checkouts
  alter column invoice_id drop not null;

alter table public.payment_stripe_checkouts
  add column kind text not null default 'invoice' check (kind in ('invoice', 'quote_deposit')),
  add column quote_id uuid,
  add column quote_version_id uuid,
  add column quote_deposit_event_id uuid;

alter table public.payment_stripe_checkouts
  add constraint payment_stripe_checkouts_quote_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete restrict,
  add constraint payment_stripe_checkouts_quote_version_fk foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete restrict,
  add constraint payment_stripe_checkouts_deposit_event_fk foreign key (organization_id, quote_deposit_event_id)
    references public.quote_deposit_events(organization_id, id) on delete restrict,
  add constraint payment_stripe_checkouts_target_shape check (
    (kind = 'invoice' and invoice_id is not null and quote_id is null and quote_version_id is null)
    or
    (kind = 'quote_deposit' and invoice_id is null and quote_id is not null and quote_version_id is not null)
  );

-- A quote-deposit checkout has no client_payment_events row to point at; it points at the deposit event
-- instead. Either way "paid" means the row that actually holds the money has been written.
alter table public.payment_stripe_checkouts drop constraint payment_stripe_checkouts_paid_shape;
alter table public.payment_stripe_checkouts add constraint payment_stripe_checkouts_paid_shape check (
  (status = 'paid') = (
    completed_at is not null and applied_minor is not null and (
      (kind = 'invoice' and payment_event_id is not null)
      or (kind = 'quote_deposit' and quote_deposit_event_id is not null)
    )
  )
);

comment on table public.payment_stripe_checkouts is
  'One Stripe Checkout attempt for an invoice or a quote deposit. Server-owned. Moves to paid exactly once, '
  'when a signed Stripe webhook confirms the money; the ledger row it points at (an invoice payment or a '
  'deposit event) is the payment itself.';

-- "Is a payment for this quote still open?" on every customer page load, and the quote's attempts.
create index payment_stripe_checkouts_quote_idx
  on public.payment_stripe_checkouts (organization_id, quote_id, created_at desc)
  where quote_id is not null;

-- 3. One alert helper for either kind of payment, instead of an invoice-only one -----------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check
  check (kind in (
    'website_inquiry.received', 'website_inquiry.customer_replied',
    'invoice.paid_online', 'invoice.online_payment_failed', 'invoice.online_overpayment',
    'quote.deposit_paid_online', 'quote.deposit_payment_failed', 'quote.deposit_overpaid'
  ));

alter table public.team_notifications drop constraint team_notifications_subject_type_check;
alter table public.team_notifications add constraint team_notifications_subject_type_check
  check (subject_type in ('form_submission', 'website_chat_session', 'invoice', 'quote'));

create or replace function private.create_payment_alerts(
  p_organization_id uuid,
  p_kind text,
  p_subject_type text,
  p_subject_id uuid,
  p_required_permission_1 text,
  p_required_permission_2 text,
  p_source_key text,
  p_title text,
  p_body text
)
returns void
language sql
security definer
set search_path = pg_catalog, public, private
as $$
  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key, email_state
  )
  select p_organization_id, membership.user_id, p_kind, p_subject_type, p_subject_id, left(p_title, 200),
    left(p_body, 500), p_source_key, 'not_needed'
  from public.organization_members as membership
  where membership.organization_id = p_organization_id
    and membership.status = 'active'
    and private.member_has_permission(p_organization_id, membership.user_id, p_required_permission_1)
    and private.member_has_permission(p_organization_id, membership.user_id, p_required_permission_2)
  on conflict (organization_id, user_id, source_key) do nothing;
$$;

revoke all on function private.create_payment_alerts(uuid, text, text, uuid, text, text, text, text, text)
  from public, anon, authenticated, service_role;

drop function private.create_invoice_payment_alerts(uuid, text, uuid, text, text, text);

-- 4. What the customer's quote page may offer ------------------------------------------------------------------

-- Mirrors invoice_online_payment_context: the customer page and the Pay endpoint ask the same question the
-- same way. Service role only. A quote link is tied to one version, so this only ever answers for the
-- version the customer is actually looking at, the same rule resolve_quote_access_link already follows.
create or replace function public.quote_online_deposit_context(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
  settings_row public.organization_settings;
  connection_row public.payment_stripe_connections;
  lifecycle text;
  satisfied boolean;
  unavailable text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into quote_row from public.quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  select organization.lifecycle_status into lifecycle
  from public.organizations as organization where organization.id = quote_row.organization_id;
  select * into settings_row
  from public.organization_settings where organization_id = quote_row.organization_id;
  select * into connection_row
  from public.payment_stripe_connections where organization_id = quote_row.organization_id;

  satisfied := exists (
    select 1 from public.quote_deposit_events received
    where received.organization_id = version_row.organization_id
      and received.quote_id = version_row.quote_id
      and received.quote_version_id = version_row.id
      and received.event_type = 'received'
      and not exists (
        select 1 from public.quote_deposit_events reversal
        where reversal.organization_id = received.organization_id
          and reversal.reversed_event_id = received.id
      )
  );

  unavailable := case
    when lifecycle is distinct from 'active' then 'business_unavailable'
    when connection_row.id is null then 'not_connected'
    when not settings_row.online_deposit_payments_enabled then 'turned_off'
    when quote_row.status <> 'approved' then 'not_approved'
    when version_row.deposit_type is null or version_row.deposit_required_minor <= 0 then 'no_deposit'
    when satisfied then 'already_paid'
  end;

  return jsonb_build_object(
    'organization_id', quote_row.organization_id,
    'quote_id', quote_row.id,
    'quote_version_id', version_row.id,
    'client_id', quote_row.client_id,
    'quote_number', quote_row.quote_number,
    'currency_code', version_row.currency_code,
    'available', unavailable is null,
    'unavailable_reason', unavailable,
    'deposit_required_minor', coalesce(version_row.deposit_required_minor, 0),
    'livemode', connection_row.livemode,
    'stripe_account_id', connection_row.stripe_account_id
  );
end;
$$;

revoke all on function public.quote_online_deposit_context(bytea) from public, anon, authenticated;
grant execute on function public.quote_online_deposit_context(bytea) to service_role;

-- 5. Opening a checkout for the deposit ---------------------------------------------------------------------

-- No amount or tip to negotiate: the deposit is one fixed figure the customer already agreed to when they
-- signed. Re-checks everything the page showed, under a lock on the quote (the same row record_quote_deposit_event
-- locks), then writes the attempt.
create or replace function public.open_quote_deposit_stripe_checkout(supplied_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  context jsonb;
  checkout_id uuid;
begin
  context := public.quote_online_deposit_context(supplied_token_hash);
  if context is null then
    raise exception 'This quote is not available.' using errcode = 'P0404';
  end if;

  perform 1 from public.quotes
  where organization_id = (context->>'organization_id')::uuid and id = (context->>'quote_id')::uuid
  for update;
  context := public.quote_online_deposit_context(supplied_token_hash);

  if not (context->>'available')::boolean then
    raise exception 'Online payment is not available for this quote.' using errcode = 'check_violation',
      detail = context->>'unavailable_reason';
  end if;

  insert into public.payment_stripe_checkouts (
    organization_id, kind, quote_id, quote_version_id, client_id, stripe_account_id, livemode,
    amount_minor, tip_minor, currency_code
  ) values (
    (context->>'organization_id')::uuid, 'quote_deposit', (context->>'quote_id')::uuid,
    (context->>'quote_version_id')::uuid, (context->>'client_id')::uuid, context->>'stripe_account_id',
    (context->>'livemode')::boolean, (context->>'deposit_required_minor')::bigint, 0,
    context->>'currency_code'
  )
  returning id into checkout_id;

  return context || jsonb_build_object('checkout_id', checkout_id);
end;
$$;

revoke all on function public.open_quote_deposit_stripe_checkout(bytea) from public, anon, authenticated;
grant execute on function public.open_quote_deposit_stripe_checkout(bytea) to service_role;

-- 6. Applying a Stripe confirmation, for either kind of checkout -----------------------------------------------

-- Same signature as Part 3; the caller (the webhook route) does not need to know or care what a checkout is
-- for. Everything is looked up inside the organization the verified connection belongs to.
create or replace function public.apply_stripe_checkout_event(
  target_organization_id uuid,
  stripe_event_id text,
  stripe_event_type text,
  target_checkout_id uuid,
  target_checkout_session_id text,
  session_payment_status text,
  session_amount_total bigint,
  session_currency text,
  new_payment_intent_id text,
  new_method text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  checkout public.payment_stripe_checkouts;
  invoice_row public.invoices;
  quote_row public.quotes;
  receipt public.client_payment_events;
  deposit_event public.quote_deposit_events;
  deposit_already_satisfied boolean;
  remaining bigint;
  applied bigint;
  result_outcome text;
  note text;
  receipt_email boolean;
  target_label text;
begin
  insert into public.payment_stripe_webhook_events (organization_id, stripe_event_id, event_type, outcome)
  values (target_organization_id, stripe_event_id, stripe_event_type, 'pending')
  on conflict do nothing;
  if not found then
    return jsonb_build_object('outcome', 'duplicate');
  end if;

  select * into checkout
  from public.payment_stripe_checkouts
  where organization_id = target_organization_id
    and (checkout_session_id = target_checkout_session_id
      or (id = target_checkout_id and checkout_session_id is null))
  for update;

  -- The session id is stored just after Stripe creates it; a confirmation that beats that write still finds
  -- its row through client_reference_id and fills the id in.
  if checkout.id is not null and checkout.checkout_session_id is null then
    update public.payment_stripe_checkouts set checkout_session_id = target_checkout_session_id
    where id = checkout.id;
  end if;

  target_label := case when checkout.kind = 'invoice' then 'invoice' else 'quote deposit' end;

  if checkout.id is null then
    result_outcome := 'unknown_session';
  elsif checkout.status = 'paid' then
    result_outcome := 'already_paid';
  elsif stripe_event_type = 'checkout.session.async_payment_failed' then
    update public.payment_stripe_checkouts set status = 'failed', updated_at = now() where id = checkout.id;
    if checkout.kind = 'invoice' then
      select * into invoice_row from public.invoices where id = checkout.invoice_id;
      perform private.create_payment_alerts(
        target_organization_id, 'invoice.online_payment_failed', 'invoice', checkout.invoice_id,
        'invoices.record_payment', 'invoices.view_price', 'stripe:' || checkout.id || ':failed',
        'Online payment failed on invoice #' || invoice_row.invoice_number,
        'The customer''s bank payment of ' || private.format_minor(checkout.amount_minor, checkout.currency_code)
          || ' did not go through. The invoice is still owed.'
      );
    else
      select * into quote_row from public.quotes where id = checkout.quote_id;
      perform private.create_payment_alerts(
        target_organization_id, 'quote.deposit_payment_failed', 'quote', checkout.quote_id,
        'quotes.record_deposit', 'quotes.view_price', 'stripe:' || checkout.id || ':failed',
        'Online deposit payment failed on quote #' || quote_row.quote_number,
        'The customer''s bank payment of ' || private.format_minor(checkout.amount_minor, checkout.currency_code)
          || ' did not go through. The deposit is still owed.'
      );
    end if;
    result_outcome := 'failed';
  elsif stripe_event_type = 'checkout.session.completed' and session_payment_status = 'unpaid' then
    -- A bank payment: the customer finished, the bank has not. Nothing is recorded until it clears.
    update public.payment_stripe_checkouts
    set status = 'processing', payment_intent_id = coalesce(new_payment_intent_id, payment_intent_id),
        updated_at = now()
    where id = checkout.id;
    result_outcome := 'processing';
  elsif (stripe_event_type = 'checkout.session.completed' and session_payment_status = 'paid')
     or stripe_event_type = 'checkout.session.async_payment_succeeded' then
    if session_amount_total is distinct from checkout.amount_minor + checkout.tip_minor
       or upper(session_currency) is distinct from checkout.currency_code then
      -- Stripe charged something other than what UCRM asked for. Record nothing; a person has to look.
      result_outcome := 'amount_mismatch';
      perform private.create_payment_alerts(
        target_organization_id,
        case when checkout.kind = 'invoice' then 'invoice.online_overpayment' else 'quote.deposit_overpaid' end,
        case when checkout.kind = 'invoice' then 'invoice' else 'quote' end,
        coalesce(checkout.invoice_id, checkout.quote_id),
        case when checkout.kind = 'invoice' then 'invoices.record_payment' else 'quotes.record_deposit' end,
        case when checkout.kind = 'invoice' then 'invoices.view_price' else 'quotes.view_price' end,
        'stripe:' || checkout.id || ':mismatch',
        'Check an online payment in Stripe',
        'Stripe reported a payment that does not match what the ' || target_label
          || ' asked for, so it was not recorded. Compare it in your Stripe dashboard.'
      );
    elsif checkout.kind = 'invoice' then
      -- The currency lock reads the ledger, so settings are held first, exactly as a recorded payment does.
      perform 1 from public.organization_settings where organization_id = target_organization_id for share;

      select * into invoice_row
      from public.invoices
      where organization_id = target_organization_id and id = checkout.invoice_id
      for update;

      note := 'Paid online through Stripe.';
      if checkout.tip_minor > 0 then
        note := note || ' Includes a tip of ' || private.format_minor(checkout.tip_minor, checkout.currency_code)
          || ', not applied to the invoice.';
      end if;

      insert into public.client_payment_events (
        organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
        reference, note, actor_user_id
      ) values (
        target_organization_id, checkout.client_id, 'received', checkout.amount_minor, checkout.currency_code,
        coalesce(new_method, 'stripe_other'), private.organization_today(target_organization_id),
        coalesce(new_payment_intent_id, checkout.payment_intent_id), note, null
      )
      returning * into receipt;

      -- Only what the bill still owes. A voided or written-off bill, or one someone paid in cash meanwhile,
      -- takes nothing more; the rest stays as the client's credit until the contractor refunds it.
      if invoice_row.voided_at is null and invoice_row.is_effective_receivable
         and invoice_row.written_off_at is null and invoice_row.currency_code = checkout.currency_code then
        remaining := invoice_row.total_minor
          - private.invoice_allocated_minor(target_organization_id, invoice_row.id);
      else
        remaining := 0;
      end if;
      applied := least(checkout.amount_minor, greatest(remaining, 0));

      if applied > 0 then
        perform private.apply_invoice_allocation(
          invoice_row, receipt.id, null, applied, null, 'Paid online through Stripe'
        );
      end if;

      update public.payment_stripe_checkouts
      set status = 'paid', payment_event_id = receipt.id, applied_minor = applied,
          payment_intent_id = coalesce(new_payment_intent_id, payment_intent_id),
          completed_at = now(), updated_at = now()
      where id = checkout.id;

      perform private.create_payment_alerts(
        target_organization_id, 'invoice.paid_online', 'invoice', checkout.invoice_id,
        'invoices.record_payment', 'invoices.view_price', 'stripe:' || checkout.id || ':paid',
        'Invoice #' || invoice_row.invoice_number || ' paid online',
        private.format_minor(checkout.amount_minor, checkout.currency_code) || ' received through Stripe'
          || case when checkout.tip_minor > 0
               then ' plus a ' || private.format_minor(checkout.tip_minor, checkout.currency_code) || ' tip.'
               else '.' end
      );

      if applied < checkout.amount_minor then
        perform private.create_payment_alerts(
          target_organization_id, 'invoice.online_overpayment', 'invoice', checkout.invoice_id,
          'invoices.record_payment', 'invoices.view_price', 'stripe:' || checkout.id || ':overpaid',
          'Refund needed on invoice #' || invoice_row.invoice_number,
          private.format_minor(checkout.amount_minor - applied, checkout.currency_code)
            || ' more than the invoice owed was paid online. It is held as client credit; refund it in Stripe '
            || 'if the customer should get it back.'
        );
      end if;

      select online_receipt_email_enabled into receipt_email
      from public.organization_settings where organization_id = target_organization_id;
      result_outcome := 'paid';
    else
      -- A quote deposit. A deposit is recorded in full or not at all, and only once per version (see
      -- record_quote_deposit_event); Stripe's confirmation follows the exact same rule.
      select * into quote_row from public.quotes where id = checkout.quote_id for update;

      deposit_already_satisfied := exists (
        select 1 from public.quote_deposit_events received
        where received.organization_id = target_organization_id
          and received.quote_id = checkout.quote_id
          and received.quote_version_id = checkout.quote_version_id
          and received.event_type = 'received'
          and not exists (
            select 1 from public.quote_deposit_events reversal
            where reversal.organization_id = received.organization_id
              and reversal.reversed_event_id = received.id
          )
      );

      if deposit_already_satisfied then
        -- Recorded some other way (cash, or a second tab) while this one was open. The checkout row is left
        -- as it was; the money still needs a human to look at it, so it is never silently swallowed.
        result_outcome := 'already_recorded_elsewhere';
        perform private.create_payment_alerts(
          target_organization_id, 'quote.deposit_overpaid', 'quote', checkout.quote_id,
          'quotes.record_deposit', 'quotes.view_price', 'stripe:' || checkout.id || ':already_recorded',
          'Refund needed on quote #' || quote_row.quote_number,
          'A deposit payment of ' || private.format_minor(checkout.amount_minor, checkout.currency_code)
            || ' came in through Stripe, but this quote''s deposit was already recorded another way. '
            || 'Refund it in Stripe if the customer should get it back.'
        );
      else
        insert into public.quote_deposit_events (
          organization_id, quote_id, quote_version_id, event_type, amount_minor, method, reference, note,
          actor_user_id, idempotency_key
        ) values (
          target_organization_id, checkout.quote_id, checkout.quote_version_id, 'received', checkout.amount_minor,
          coalesce(new_method, 'stripe_other'), coalesce(new_payment_intent_id, checkout.payment_intent_id),
          'Paid online through Stripe.', null, 'stripe:' || checkout.id
        )
        returning * into deposit_event;

        update public.payment_stripe_checkouts
        set status = 'paid', quote_deposit_event_id = deposit_event.id, applied_minor = checkout.amount_minor,
            payment_intent_id = coalesce(new_payment_intent_id, payment_intent_id),
            completed_at = now(), updated_at = now()
        where id = checkout.id;

        perform private.create_payment_alerts(
          target_organization_id, 'quote.deposit_paid_online', 'quote', checkout.quote_id,
          'quotes.record_deposit', 'quotes.view_price', 'stripe:' || checkout.id || ':paid',
          'Deposit paid online on quote #' || quote_row.quote_number,
          private.format_minor(checkout.amount_minor, checkout.currency_code) || ' received through Stripe.'
        );
      end if;

      result_outcome := coalesce(result_outcome, 'paid');
    end if;
  else
    result_outcome := 'ignored';
  end if;

  update public.payment_stripe_webhook_events set outcome = result_outcome
  where organization_id = target_organization_id
    and payment_stripe_webhook_events.stripe_event_id = apply_stripe_checkout_event.stripe_event_id;

  return jsonb_build_object(
    'outcome', result_outcome,
    'invoice_id', checkout.invoice_id,
    'payment_event_id', receipt.id,
    'send_receipt', result_outcome = 'paid' and checkout.kind = 'invoice' and coalesce(receipt_email, false)
  );
end;
$$;

revoke all on function public.apply_stripe_checkout_event(uuid, text, text, uuid, text, text, bigint, text, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_stripe_checkout_event(uuid, text, text, uuid, text, text, bigint, text, text, text)
  to service_role;
