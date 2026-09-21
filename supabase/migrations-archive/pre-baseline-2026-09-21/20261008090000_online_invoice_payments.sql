-- Online payments Part 3: a customer pays an issued invoice online through the contractor's own Stripe account.
--
-- docs/online-payments-behavior-contract.md §3. The customer's invoice page opens a Stripe Checkout session;
-- Stripe's signed webhook later confirms the money. Only that confirmation records anything in the ledger, and
-- it does so through the same append-only tables a recorded payment uses (client_payment_events +
-- invoice_payment_allocations), so balances, history, receipts and reports need no second path.
--
-- Three rules shape this file.
--
-- First, a payment counts once. Every webhook delivery is journaled by its Stripe event id, and each checkout
-- row moves to 'paid' exactly once under a row lock, so a retried or duplicated notification is a no-op.
--
-- Second, a confirmation never fails for a business reason. Stripe retries a failed delivery for days, so a
-- voided invoice or a balance paid by cash in the meantime must not raise: the money is recorded, only what
-- the bill still owes is applied, and the rest stays as client credit with an alert to refund it in Stripe.
--
-- Third, the tip is the contractor's money but not the invoice's. It is kept on the checkout row and named in
-- the receipt note; it is never applied to the bill and never becomes client credit.

-- 1. Online methods on the ledger -------------------------------------------------------------------------------

-- Money that arrived through Stripe. Kept apart from 'card_external' (a card taken on some other terminal) so
-- reports and the payment history can say "Card (online)". Never offered in the manual Record payment form.
alter table public.client_payment_events drop constraint client_payment_events_method_check;
alter table public.client_payment_events add constraint client_payment_events_method_check
  check (method in (
    'other', 'bank_transfer', 'cash', 'check', 'card_external', 'paypal',
    'stripe_card', 'stripe_bank', 'stripe_other'
  ));

-- 2. Partial online payments, per invoice ------------------------------------------------------------------------

-- Jobber's "Allow client to make partial payments for this invoice": off by default, never on a progress
-- (payment schedule) invoice, whose amount is already one agreed stage.
alter table public.invoices
  add column online_partial_payments_allowed boolean not null default false;

-- Invoices are granted column by column; this one is a plain setting, not money.
grant select (online_partial_payments_allowed) on public.invoices to authenticated;

create or replace function public.set_invoice_online_partial_payments(
  target_organization_id uuid,
  target_invoice_id uuid,
  new_allowed boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
begin
  if caller is null
     or not private.member_has_permission(target_organization_id, caller, 'invoices.edit') then
    raise exception 'You do not have access to change this invoice.' using errcode = 'insufficient_privilege';
  end if;
  if new_allowed is null then
    raise exception 'Choose whether partial payments are allowed.' using errcode = 'check_violation';
  end if;

  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id
  for update;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;
  if new_allowed and private.invoice_progress_context(invoice_row) is not null then
    raise exception 'Progress invoices are always paid in full.' using errcode = 'check_violation';
  end if;

  if invoice_row.online_partial_payments_allowed is distinct from new_allowed then
    update public.invoices
    set online_partial_payments_allowed = new_allowed
    where organization_id = target_organization_id and id = target_invoice_id;

    perform private.record_invoice_event(
      invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
      case when new_allowed then 'invoice.online_partial_allowed' else 'invoice.online_partial_disallowed' end,
      caller, invoice_row.revision
    );
  end if;

  return jsonb_build_object('online_partial_payments_allowed', new_allowed);
end;
$$;

revoke all on function public.set_invoice_online_partial_payments(uuid, uuid, boolean) from public, anon;
grant execute on function public.set_invoice_online_partial_payments(uuid, uuid, boolean) to authenticated;

-- 3. Checkout attempts -------------------------------------------------------------------------------------------

-- One row per "Pay" click. Written before the Stripe session exists, so the row id is the Stripe idempotency
-- key and a session can never exist without a row the webhook can find. The amounts here, not the ones in the
-- webhook payload, are what the ledger records.
create table public.payment_stripe_checkouts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  client_id uuid not null,
  stripe_account_id text not null check (stripe_account_id ~ '^acct_[A-Za-z0-9]{1,64}$'),
  livemode boolean not null,
  checkout_session_id text unique check (checkout_session_id ~ '^cs_[A-Za-z0-9_]{1,255}$'),
  -- What goes on the bill, and the tip beside it. Stripe charges their sum.
  amount_minor bigint not null check (amount_minor > 0 and amount_minor <= 1000000000000),
  tip_minor bigint not null default 0 check (tip_minor >= 0 and tip_minor <= 1000000000000),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  -- open: the customer is on Stripe's page. processing: a bank payment Stripe has not confirmed yet.
  status text not null default 'open' check (status in ('open', 'processing', 'paid', 'failed')),
  payment_intent_id text check (payment_intent_id is null or payment_intent_id ~ '^pi_[A-Za-z0-9_]{1,255}$'),
  payment_event_id uuid,
  applied_minor bigint check (applied_minor is null or applied_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint payment_stripe_checkouts_invoice_fk foreign key (organization_id, invoice_id)
    references public.invoices(organization_id, id) on delete restrict,
  constraint payment_stripe_checkouts_payment_fk foreign key (organization_id, payment_event_id)
    references public.client_payment_events(organization_id, id) on delete restrict,
  constraint payment_stripe_checkouts_paid_shape check (
    (status = 'paid') = (payment_event_id is not null and applied_minor is not null and completed_at is not null)
  )
);

comment on table public.payment_stripe_checkouts is
  'One Stripe Checkout attempt for an invoice. Server-owned. Moves to paid exactly once, when a signed Stripe '
  'webhook confirms the money; the ledger rows it points at are the payment itself.';

-- "Is a payment for this invoice still processing?" on every customer page load, and the invoice's attempts.
create index payment_stripe_checkouts_invoice_idx
  on public.payment_stripe_checkouts (organization_id, invoice_id, created_at desc);

create index payment_stripe_checkouts_payment_idx
  on public.payment_stripe_checkouts (organization_id, payment_event_id)
  where payment_event_id is not null;

alter table public.payment_stripe_checkouts enable row level security;
revoke all on table public.payment_stripe_checkouts from public, anon, authenticated, service_role;
grant select, insert, update on table public.payment_stripe_checkouts to service_role;

-- 4. Webhook journal ---------------------------------------------------------------------------------------------

-- Stripe delivers at least once and may deliver the same event again. The event id is written in the same
-- transaction that applies it, so a delivery that failed halfway leaves no row and is retried in full.
create table public.payment_stripe_webhook_events (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  stripe_event_id text not null check (stripe_event_id ~ '^evt_[A-Za-z0-9_]{1,255}$'),
  event_type text not null check (char_length(event_type) between 1 and 100),
  outcome text not null check (char_length(outcome) between 1 and 50),
  received_at timestamptz not null default now(),
  primary key (organization_id, stripe_event_id)
);

comment on table public.payment_stripe_webhook_events is
  'Every Stripe webhook event UCRM has acted on, by event id. Makes redelivery a no-op. Server-owned.';

alter table public.payment_stripe_webhook_events enable row level security;
revoke all on table public.payment_stripe_webhook_events from public, anon, authenticated, service_role;
grant select, insert on table public.payment_stripe_webhook_events to service_role;

-- 5. Payment alerts in the bell ----------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check
  check (kind in (
    'website_inquiry.received', 'website_inquiry.customer_replied',
    'invoice.paid_online', 'invoice.online_payment_failed', 'invoice.online_overpayment'
  ));

alter table public.team_notifications drop constraint team_notifications_subject_type_check;
alter table public.team_notifications add constraint team_notifications_subject_type_check
  check (subject_type in ('form_submission', 'website_chat_session', 'invoice'));

-- Everyone active who can take payments and see money: by default the owner and admins. In-app only; the
-- bell's email queue is for inquiries, so these rows are born 'not_needed'.
create or replace function private.create_invoice_payment_alerts(
  p_organization_id uuid,
  p_kind text,
  p_invoice_id uuid,
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
  select p_organization_id, membership.user_id, p_kind, 'invoice', p_invoice_id, left(p_title, 200),
    left(p_body, 500), p_source_key, 'not_needed'
  from public.organization_members as membership
  where membership.organization_id = p_organization_id
    and membership.status = 'active'
    and private.member_has_permission(p_organization_id, membership.user_id, 'invoices.record_payment')
    and private.member_has_permission(p_organization_id, membership.user_id, 'invoices.view_price')
  on conflict (organization_id, user_id, source_key) do nothing;
$$;

revoke all on function private.create_invoice_payment_alerts(uuid, text, uuid, text, text, text)
  from public, anon, authenticated, service_role;

create or replace function private.format_minor(amount_minor bigint, currency_code text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select trim(to_char(amount_minor / 100.0, 'FM999G999G990D00')) || ' ' || currency_code;
$$;

revoke all on function private.format_minor(bigint, text) from public, anon, authenticated, service_role;

-- 6. What the customer's page may offer --------------------------------------------------------------------------

-- The customer page and the Pay endpoint ask the same question the same way: may this link take money online
-- right now, and how much? Service role only; the token hash is the credential, as for the document itself.
create or replace function public.invoice_online_payment_context(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  link_row public.invoice_access_links;
  invoice_row public.invoices;
  settings_row public.organization_settings;
  connection_row public.payment_stripe_connections;
  lifecycle text;
  remaining bigint;
  processing bigint;
  recent_paid bigint;
  is_progress boolean;
  unavailable text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.invoice_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into invoice_row from public.invoices where id = link_row.invoice_id;
  if invoice_row.id is null
     or invoice_row.issued_at is null
     or invoice_row.voided_at is not null
     or invoice_row.replaced_at is not null then
    return null;
  end if;

  select organization.lifecycle_status into lifecycle
  from public.organizations as organization where organization.id = invoice_row.organization_id;
  select * into settings_row
  from public.organization_settings where organization_id = invoice_row.organization_id;
  select * into connection_row
  from public.payment_stripe_connections where organization_id = invoice_row.organization_id;

  remaining := invoice_row.total_minor
    - private.invoice_allocated_minor(invoice_row.organization_id, invoice_row.id);

  select coalesce(sum(checkout.amount_minor), 0)::bigint into processing
  from public.payment_stripe_checkouts as checkout
  where checkout.organization_id = invoice_row.organization_id
    and checkout.invoice_id = invoice_row.id
    and checkout.status = 'processing';

  -- What the customer just paid, so the page they return to from Stripe can thank them.
  select coalesce(sum(checkout.amount_minor + checkout.tip_minor), 0)::bigint into recent_paid
  from public.payment_stripe_checkouts as checkout
  where checkout.organization_id = invoice_row.organization_id
    and checkout.invoice_id = invoice_row.id
    and checkout.status = 'paid'
    and checkout.completed_at > now() - interval '30 minutes';

  is_progress := private.invoice_progress_context(invoice_row) is not null;

  unavailable := case
    when lifecycle is distinct from 'active' then 'business_unavailable'
    when connection_row.id is null then 'not_connected'
    when not settings_row.online_invoice_payments_enabled then 'turned_off'
    when not invoice_row.is_effective_receivable or invoice_row.written_off_at is not null then 'closed'
    when remaining - processing <= 0 then 'nothing_owed'
  end;

  return jsonb_build_object(
    'organization_id', invoice_row.organization_id,
    'invoice_id', invoice_row.id,
    'client_id', invoice_row.client_id,
    'invoice_number', invoice_row.invoice_number,
    'currency_code', invoice_row.currency_code,
    'available', unavailable is null,
    'unavailable_reason', unavailable,
    'balance_minor', greatest(remaining - processing, 0),
    'processing_minor', processing,
    'recent_paid_minor', recent_paid,
    'partial_allowed', invoice_row.online_partial_payments_allowed and not is_progress,
    'tips_enabled', coalesce(settings_row.online_tips_enabled, false),
    -- Tips are a percentage of the pre-tax, after-discount amount, as in Jobber.
    'tip_base_minor', greatest(invoice_row.subtotal_minor - invoice_row.discount_minor, 0),
    'livemode', connection_row.livemode,
    'stripe_account_id', connection_row.stripe_account_id
  );
end;
$$;

revoke all on function public.invoice_online_payment_context(bytea) from public, anon, authenticated;
grant execute on function public.invoice_online_payment_context(bytea) to service_role;

-- 7. Opening a checkout ------------------------------------------------------------------------------------------

-- Re-checks everything the page showed, under a lock on the invoice, then writes the attempt. The server then
-- creates the Stripe session with this row's id as its idempotency key and stores the session id on the row.
create or replace function public.open_invoice_stripe_checkout(
  supplied_token_hash bytea,
  new_amount_minor bigint,
  new_tip_minor bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  context jsonb;
  checkout_id uuid;
  balance bigint;
begin
  context := public.invoice_online_payment_context(supplied_token_hash);
  if context is null then
    raise exception 'This invoice is not available.' using errcode = 'P0404';
  end if;

  -- Serialize Pay clicks on one invoice so two tabs cannot both open checkouts for the whole balance.
  perform 1 from public.invoices
  where organization_id = (context->>'organization_id')::uuid and id = (context->>'invoice_id')::uuid
  for update;
  context := public.invoice_online_payment_context(supplied_token_hash);

  if not (context->>'available')::boolean then
    raise exception 'Online payment is not available for this invoice.' using errcode = 'check_violation',
      detail = context->>'unavailable_reason';
  end if;

  balance := (context->>'balance_minor')::bigint;
  if new_amount_minor is null or new_amount_minor <= 0 or new_amount_minor > balance then
    raise exception 'That amount is more than this invoice still owes.' using errcode = 'check_violation',
      detail = 'amount';
  end if;
  if new_amount_minor <> balance and not (context->>'partial_allowed')::boolean then
    raise exception 'This invoice has to be paid in full.' using errcode = 'check_violation',
      detail = 'amount';
  end if;
  if coalesce(new_tip_minor, 0) < 0
     or (coalesce(new_tip_minor, 0) > 0 and not (context->>'tips_enabled')::boolean)
     or coalesce(new_tip_minor, 0) > greatest(balance, (context->>'tip_base_minor')::bigint) then
    raise exception 'That tip cannot be added.' using errcode = 'check_violation', detail = 'tip';
  end if;

  insert into public.payment_stripe_checkouts (
    organization_id, invoice_id, client_id, stripe_account_id, livemode, amount_minor, tip_minor,
    currency_code
  ) values (
    (context->>'organization_id')::uuid, (context->>'invoice_id')::uuid, (context->>'client_id')::uuid,
    context->>'stripe_account_id', (context->>'livemode')::boolean, new_amount_minor,
    coalesce(new_tip_minor, 0), context->>'currency_code'
  )
  returning id into checkout_id;

  return context || jsonb_build_object('checkout_id', checkout_id);
end;
$$;

revoke all on function public.open_invoice_stripe_checkout(bytea, bigint, bigint) from public, anon, authenticated;
grant execute on function public.open_invoice_stripe_checkout(bytea, bigint, bigint) to service_role;

-- 8. Applying a Stripe confirmation ------------------------------------------------------------------------------

-- Called by the webhook route after the signature is verified, with the organization the verified connection
-- belongs to. Everything is looked up inside that organization, so nothing in the payload can reach another.
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
  receipt public.client_payment_events;
  remaining bigint;
  applied bigint;
  result_outcome text;
  note text;
  receipt_email boolean;
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

  if checkout.id is null then
    result_outcome := 'unknown_session';
  elsif checkout.status = 'paid' then
    result_outcome := 'already_paid';
  elsif stripe_event_type = 'checkout.session.async_payment_failed' then
    update public.payment_stripe_checkouts set status = 'failed', updated_at = now() where id = checkout.id;
    select * into invoice_row from public.invoices where id = checkout.invoice_id;
    perform private.create_invoice_payment_alerts(
      target_organization_id, 'invoice.online_payment_failed', checkout.invoice_id,
      'stripe:' || checkout.id || ':failed',
      'Online payment failed on invoice #' || invoice_row.invoice_number,
      'The customer''s bank payment of ' || private.format_minor(checkout.amount_minor, checkout.currency_code)
        || ' did not go through. The invoice is still owed.'
    );
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
      perform private.create_invoice_payment_alerts(
        target_organization_id, 'invoice.online_overpayment', checkout.invoice_id,
        'stripe:' || checkout.id || ':mismatch',
        'Check an online payment in Stripe',
        'Stripe reported a payment that does not match what the invoice asked for, so it was not recorded. '
          || 'Compare it in your Stripe dashboard.'
      );
    else
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

      perform private.create_invoice_payment_alerts(
        target_organization_id, 'invoice.paid_online', checkout.invoice_id,
        'stripe:' || checkout.id || ':paid',
        'Invoice #' || invoice_row.invoice_number || ' paid online',
        private.format_minor(checkout.amount_minor, checkout.currency_code) || ' received through Stripe'
          || case when checkout.tip_minor > 0
               then ' plus a ' || private.format_minor(checkout.tip_minor, checkout.currency_code) || ' tip.'
               else '.' end
      );

      if applied < checkout.amount_minor then
        perform private.create_invoice_payment_alerts(
          target_organization_id, 'invoice.online_overpayment', checkout.invoice_id,
          'stripe:' || checkout.id || ':overpaid',
          'Refund needed on invoice #' || invoice_row.invoice_number,
          private.format_minor(checkout.amount_minor - applied, checkout.currency_code)
            || ' more than the invoice owed was paid online. It is held as client credit; refund it in Stripe '
            || 'if the customer should get it back.'
        );
      end if;

      select online_receipt_email_enabled into receipt_email
      from public.organization_settings where organization_id = target_organization_id;
      result_outcome := 'paid';
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
    'send_receipt', result_outcome = 'paid' and coalesce(receipt_email, false)
  );
end;
$$;

revoke all on function public.apply_stripe_checkout_event(uuid, text, text, uuid, text, text, bigint, text, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_stripe_checkout_event(uuid, text, text, uuid, text, text, bigint, text, text, text)
  to service_role;

-- 9. The automatic receipt -----------------------------------------------------------------------------------

-- Unchanged from 20260906160000 except that a null actor is accepted for a Stripe-confirmed payment, so the
-- webhook can send the customer their receipt when "Email receipt automatically" is on.
create or replace function public.enqueue_payment_receipt_email(
  target_organization_id uuid, target_actor_user_id uuid, target_payment_event_id uuid,
  target_logical_send_key text, target_receipt_url text, target_receipt_token_hash bytea
) returns public.communication_delivery_intents
language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare
  receipt public.client_payment_events; client_row public.clients;
  recipient public.client_contact_methods;
  business_name text; money_text text;
  sender public.communication_email_senders; sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
begin
  -- A staff send names the person. The automatic receipt after an online payment names nobody, and is allowed
  -- only for a payment Stripe confirmed (checked once the payment is loaded below).
  if target_actor_user_id is not null and (
    not private.member_has_permission(target_organization_id, target_actor_user_id, 'invoices.record_payment')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send')) then
    raise exception 'You do not have permission to send this receipt by email.' using errcode = 'insufficient_privilege';
  end if;
  if target_receipt_url !~ '^https?://[^[:space:]]+$' or target_receipt_token_hash is null
    or octet_length(target_receipt_token_hash) <> 32 then
    raise exception 'The receipt link is not available.' using errcode = 'check_violation';
  end if;

  select * into intent from public.communication_delivery_intents
    where organization_id = target_organization_id and logical_send_key = target_logical_send_key for share;
  if intent.id is not null then
    if intent.client_payment_event_id is distinct from target_payment_event_id then
      raise exception 'This receipt retry does not match the original payment.' using errcode = 'unique_violation';
    end if;
    return intent;
  end if;

  select * into receipt from public.client_payment_events
    where organization_id = target_organization_id and id = target_payment_event_id for share;
  if receipt.id is null or receipt.event_type <> 'received' then
    raise exception 'This payment does not have a receipt to send.' using errcode = 'foreign_key_violation';
  end if;
  if target_actor_user_id is null and receipt.method not in ('stripe_card', 'stripe_bank', 'stripe_other') then
    raise exception 'You do not have permission to send this receipt by email.' using errcode = 'insufficient_privilege';
  end if;

  select * into client_row from public.clients
    where organization_id = receipt.organization_id and id = receipt.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = receipt.organization_id and client_id = receipt.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if client_row.id is null or recipient.id is null then
    raise exception 'This payment needs an active customer email address before a receipt can be sent.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select organization.name into business_name from public.organizations as organization
    where organization.id = receipt.organization_id;

  -- The organization's default automated sender, exactly as the invoice and quote emails choose it.
  select * into sender from public.communication_email_senders
    where organization_id = receipt.organization_id and lifecycle_state = 'enabled' and allows_automated
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

  update public.payment_receipt_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = receipt.organization_id and client_payment_event_id = receipt.id and revoked_at is null;
  insert into public.payment_receipt_access_links (organization_id, client_payment_event_id, recipient_name, recipient_email, token_hash, issued_by)
    values (receipt.organization_id, receipt.id,
      coalesce(nullif(trim(client_row.display_name), ''), recipient.normalized_value), recipient.normalized_value,
      target_receipt_token_hash, target_actor_user_id);

  money_text := trim(to_char(receipt.amount_minor / 100.0, 'FM999G999G990D00')) || ' ' || receipt.currency_code;
  insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, client_payment_event_id, logical_send_key, recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id, created_by)
    values (receipt.organization_id, receipt.client_id, recipient.id, receipt.id, target_logical_send_key, recipient.normalized_value,
      'Receipt for your payment to ' || coalesce(nullif(trim(business_name), ''), 'your contractor'),
      '<p>Thank you for your payment of ' || money_text || '.</p><p><a href="' || replace(target_receipt_url, '&', '&amp;') || '">View your receipt</a></p>',
      'Thank you for your payment of ' || money_text || '. View your receipt here: ' || target_receipt_url,
      'automated', 'essential', sender.id, target_actor_user_id)
    returning * into intent;
  insert into public.communication_outbox_events (organization_id, delivery_intent_id) values (intent.organization_id, intent.id);

  return intent;
end;
$$;

comment on function public.enqueue_payment_receipt_email(uuid, uuid, uuid, text, text, bytea) is
  'Queues one payment-receipt email as a hosted link (no PDF attachment -- we run no PDF engine). Idempotent '
  'on the logical send key; a deliberate resend passes a new key. A null actor is the automatic receipt for '
  'a Stripe-confirmed payment. Service role only.';

revoke all on function public.enqueue_payment_receipt_email(uuid, uuid, uuid, text, text, bytea) from public, anon, authenticated;
grant execute on function public.enqueue_payment_receipt_email(uuid, uuid, uuid, text, text, bytea) to service_role;
