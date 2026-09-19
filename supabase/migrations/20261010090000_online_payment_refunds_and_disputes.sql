-- Online payments Part 5: refunds, disputes, and disconnect safety.
--
-- docs/online-payments-behavior-contract.md §5. Two ways a Stripe-collected payment gives money back, both
-- ending in the exact same ledger shape refund_client_payment already writes for a manual refund (a
-- client_payment_events 'refunded' row pointing at the original) so invoice balances, client credit and
-- reports need no second reading:
--
--   * The contractor clicks "Refund" in UCRM. UCRM asks Stripe to send the money back and only records it once
--     Stripe confirms -- exactly the same rule Part 3 uses for the original payment, and for the same reason:
--     a card refund usually confirms in the same second, but a bank-funded one can stay pending for days, and
--     nothing here trusts a status this server has not been told twice (once synchronously, once by webhook).
--   * The contractor refunds in Stripe's own dashboard. UCRM never asked for it, so it is picked up entirely
--     from the webhook, matched back to the payment by its Stripe payment intent.
--
-- Both paths share one row per Stripe refund object (payment_stripe_refunds), keyed by Stripe's own refund id
-- so either path -- or a redelivered webhook -- lands on the same row and moves it out of 'pending' exactly
-- once. A dispute (chargeback) is simpler: docs/online-payments-behavior-contract.md is explicit that UCRM
-- does not try to handle it, only alert, so it writes nothing but the alert itself.
--
-- Disconnect safety: a customer can already be looking at a live Stripe Checkout page when the contractor
-- disconnects. Nothing before this file stopped that page from finishing -- the connection row disconnect
-- deletes is also the row the webhook route verifies signatures against, so a payment that completed after
-- disconnect would take the customer's money and then fail to record anywhere. Disconnecting now expires
-- every open session first, so the page the customer is looking at ends instead of silently succeeding into a
-- connection that is about to stop existing.

-- 1. Locating a paid checkout by the Stripe ids a refund or dispute event carries --------------------------------

alter table public.payment_stripe_checkouts
  add constraint payment_stripe_checkouts_organization_id_unique unique (organization_id, id);

-- Refunds and disputes arrive naming a payment intent, never our own checkout id. One paid checkout per
-- payment intent already holds in practice (Stripe issues a fresh intent per Checkout Session), and this
-- makes it an invariant instead of an assumption.
create unique index payment_stripe_checkouts_payment_intent_idx
  on public.payment_stripe_checkouts (organization_id, payment_intent_id)
  where payment_intent_id is not null;

-- 2. One row per Stripe refund object ------------------------------------------------------------------------

create table public.payment_stripe_refunds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  checkout_id uuid not null,
  -- Who asked for it in UCRM. Null means UCRM never asked -- Stripe's dashboard did, and this row was born
  -- from the webhook instead of a reservation.
  requested_by uuid references auth.users(id) on delete set null,
  -- Filled the moment Stripe assigns it: right after the synchronous refunds.create() call for a
  -- UCRM-initiated refund, or on first sight of the webhook for a dashboard one. Never reused across rows.
  stripe_refund_id text unique check (stripe_refund_id is null or stripe_refund_id ~ '^re_[A-Za-z0-9_]{1,255}$'),
  amount_minor bigint not null check (amount_minor > 0 and amount_minor <= 1000000000000),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  status text not null default 'pending' check (status in ('pending', 'succeeded', 'failed')),
  failure_message text check (failure_message is null or char_length(failure_message) <= 300),
  -- The client_payment_events 'refunded' row this became, once Stripe confirmed it.
  refund_event_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint payment_stripe_refunds_checkout_fk foreign key (organization_id, checkout_id)
    references public.payment_stripe_checkouts(organization_id, id) on delete restrict,
  constraint payment_stripe_refunds_event_fk foreign key (organization_id, refund_event_id)
    references public.client_payment_events(organization_id, id) on delete restrict,
  constraint payment_stripe_refunds_succeeded_shape check (
    (status = 'succeeded') = (refund_event_id is not null and completed_at is not null)
  )
);

comment on table public.payment_stripe_refunds is
  'One Stripe refund object, whether started in UCRM or seen for the first time in a webhook. Server-owned. '
  'Moves out of pending exactly once, keyed by Stripe''s own refund id so either origin, or a redelivered '
  'webhook, lands on the same row.';

create index payment_stripe_refunds_checkout_idx
  on public.payment_stripe_refunds (organization_id, checkout_id, created_at desc);

alter table public.payment_stripe_refunds enable row level security;
revoke all on table public.payment_stripe_refunds from public, anon, authenticated, service_role;
grant select, insert, update on table public.payment_stripe_refunds to service_role;

-- 3. New alert kinds ------------------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check
  check (kind in (
    'website_inquiry.received', 'website_inquiry.customer_replied',
    'invoice.paid_online', 'invoice.online_payment_failed', 'invoice.online_overpayment',
    'quote.deposit_paid_online', 'quote.deposit_payment_failed', 'quote.deposit_overpaid',
    'invoice.online_refund_failed', 'invoice.payment_disputed',
    'quote.deposit_refund_failed', 'quote.deposit_disputed'
  ));

-- 4. Reserving a refund from inside UCRM -----------------------------------------------------------------------

-- Same retry ledger and the same available-to-refund arithmetic refund_client_payment already uses (a
-- receipt's face value, less what is already applied to a bill and less any earlier refund), minus this
-- payment's own refund requests still waiting on Stripe -- so two clicks, or a refund racing an application of
-- the same receipt, cannot together send back more than the receipt is worth. The permission is the same one
-- a manual refund requires: refunding is refunding, whichever rail sends the money.
create or replace function public.reserve_stripe_payment_refund(
  target_organization_id uuid,
  target_payment_event_id uuid,
  new_amount_minor bigint,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  receipt public.client_payment_events;
  checkout public.payment_stripe_checkouts;
  available bigint;
  pending_holds bigint;
  refund_row public.payment_stripe_refunds;
begin
  if caller is null then
    raise exception 'You must be signed in to refund a payment.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.correct_payment') then
    raise exception 'You do not have access to refund payments here.' using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'reserve_stripe_payment_refund', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  select * into receipt
  from public.client_payment_events
  where organization_id = target_organization_id and id = target_payment_event_id
  for update;
  if not found then
    raise exception 'That payment could not be found.' using errcode = 'P0404';
  end if;
  if receipt.event_type <> 'received' or receipt.method not in ('stripe_card', 'stripe_bank', 'stripe_other') then
    raise exception 'Only a payment collected through Stripe can be refunded this way.'
      using errcode = 'check_violation';
  end if;

  select * into checkout
  from public.payment_stripe_checkouts
  where organization_id = target_organization_id and payment_event_id = receipt.id and status = 'paid'
  order by completed_at desc
  limit 1
  for update;
  if checkout.id is null or checkout.payment_intent_id is null then
    raise exception 'This payment has no Stripe checkout to refund it through.' using errcode = 'P0404';
  end if;

  if new_amount_minor is null or new_amount_minor <= 0 then
    raise exception 'A refund amount must be more than zero.' using errcode = 'check_violation';
  end if;

  select coalesce(sum(hold.amount_minor), 0) into pending_holds
  from public.payment_stripe_refunds as hold
  where hold.organization_id = target_organization_id
    and hold.checkout_id = checkout.id
    and hold.status = 'pending';
  available := private.payment_event_available_minor(target_organization_id, receipt.id) - pending_holds;

  if new_amount_minor > available then
    raise exception 'That is more than this payment has left to refund.'
      using errcode = 'check_violation',
      detail = format('%s available, %s offered', available, new_amount_minor),
      hint = 'Money applied to an invoice must be taken off that invoice before it can be refunded.';
  end if;

  insert into public.payment_stripe_refunds (
    organization_id, checkout_id, requested_by, amount_minor, currency_code, status
  ) values (
    target_organization_id, checkout.id, caller, new_amount_minor, checkout.currency_code, 'pending'
  )
  returning * into refund_row;

  return private.complete_invoice_command(
    target_organization_id, 'reserve_stripe_payment_refund', new_idempotency_key,
    jsonb_build_object(
      'refund_id', refund_row.id,
      'checkout_id', checkout.id,
      'payment_intent_id', checkout.payment_intent_id,
      'stripe_account_id', checkout.stripe_account_id,
      'amount_minor', refund_row.amount_minor,
      'currency_code', refund_row.currency_code
    )
  );
end;
$$;

comment on function public.reserve_stripe_payment_refund(uuid, uuid, bigint, text, text) is
  'Holds an amount against a Stripe-collected payment before the server asks Stripe to send it back. Does not '
  'move any money itself -- apply_stripe_refund_event does that once Stripe confirms.';

revoke all on function public.reserve_stripe_payment_refund(uuid, uuid, bigint, text, text)
  from public, anon;
grant execute on function public.reserve_stripe_payment_refund(uuid, uuid, bigint, text, text) to authenticated;

-- 5. Applying a Stripe refund confirmation, from either origin -------------------------------------------------

-- Called by the webhook route for charge.refunded and charge.refund.updated, and directly by the refund route
-- right after Stripe's synchronous response to its own refunds.create() call -- the same event, told to this
-- function twice from two different directions, so it is keyed by Stripe's refund id and moves out of
-- 'pending' exactly once regardless of which telling arrives first.
create or replace function public.apply_stripe_refund_event(
  target_organization_id uuid,
  stripe_event_id text,
  stripe_event_type text,
  target_stripe_refund_id text,
  target_payment_intent_id text,
  refund_status text,
  refund_amount_minor bigint,
  refund_currency text,
  refund_failure_message text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  refund public.payment_stripe_refunds;
  checkout public.payment_stripe_checkouts;
  original_receipt public.client_payment_events;
  original_deposit public.quote_deposit_events;
  ledger_event_id uuid;
  result_outcome text;
  refund_note text;
  invoice_row public.invoices;
  quote_row public.quotes;
begin
  insert into public.payment_stripe_webhook_events (organization_id, stripe_event_id, event_type, outcome)
  values (target_organization_id, stripe_event_id, stripe_event_type, 'pending')
  on conflict do nothing;
  if not found then
    return jsonb_build_object('outcome', 'duplicate');
  end if;

  select * into refund
  from public.payment_stripe_refunds
  where organization_id = target_organization_id and stripe_refund_id = target_stripe_refund_id
  for update;

  if refund.id is null then
    -- First sight of this refund. Either the dashboard made it (no reservation exists), or this webhook beat
    -- the reservation's own stripe_refund_id write -- both are found the same way, by the payment it refunds.
    select * into checkout
    from public.payment_stripe_checkouts
    where organization_id = target_organization_id
      and payment_intent_id = target_payment_intent_id
      and status = 'paid';

    if checkout.id is null then
      result_outcome := 'unknown_payment';
      update public.payment_stripe_webhook_events set outcome = result_outcome
        where organization_id = target_organization_id
          and payment_stripe_webhook_events.stripe_event_id = apply_stripe_refund_event.stripe_event_id;
      return jsonb_build_object('outcome', result_outcome);
    end if;

    insert into public.payment_stripe_refunds (
      organization_id, checkout_id, stripe_refund_id, amount_minor, currency_code, status
    ) values (
      target_organization_id, checkout.id, target_stripe_refund_id, refund_amount_minor,
      refund_currency, 'pending'
    )
    returning * into refund;
  else
    select * into checkout
    from public.payment_stripe_checkouts
    where organization_id = target_organization_id and id = refund.checkout_id;
  end if;

  if refund.status in ('succeeded', 'failed') then
    -- Already the last word. Stripe does not regress a refund's status, but a redelivered or racing event
    -- must never be told twice.
    result_outcome := 'already_' || refund.status;
  elsif refund_status = 'failed' then
    update public.payment_stripe_refunds
    set status = 'failed', failure_message = left(refund_failure_message, 300), updated_at = now(),
        completed_at = now()
    where id = refund.id;

    if checkout.kind = 'invoice' then
      select * into invoice_row from public.invoices where id = checkout.invoice_id;
      perform private.create_payment_alerts(
        target_organization_id, 'invoice.online_refund_failed', 'invoice', checkout.invoice_id,
        'invoices.record_payment', 'invoices.view_price', 'stripe:refund:' || refund.id || ':failed',
        'A Stripe refund failed on invoice #' || invoice_row.invoice_number,
        coalesce(refund_failure_message, 'Stripe could not send this refund.')
          || ' Check it in your Stripe dashboard.'
      );
    else
      select * into quote_row from public.quotes where id = checkout.quote_id;
      perform private.create_payment_alerts(
        target_organization_id, 'quote.deposit_refund_failed', 'quote', checkout.quote_id,
        'quotes.record_deposit', 'quotes.view_price', 'stripe:refund:' || refund.id || ':failed',
        'A Stripe refund failed on quote #' || quote_row.quote_number,
        coalesce(refund_failure_message, 'Stripe could not send this refund.')
          || ' Check it in your Stripe dashboard.'
      );
    end if;
    result_outcome := 'failed';
  elsif refund_status = 'succeeded' then
    refund_note := case when refund.requested_by is not null
      then 'Refunded through Stripe from UCRM.' else 'Refunded through Stripe (seen in your Stripe dashboard).' end;

    if checkout.kind = 'invoice' then
      select * into original_receipt
      from public.client_payment_events
      where organization_id = target_organization_id and id = checkout.payment_event_id
      for update;

      insert into public.client_payment_events (
        organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
        reference, note, actor_user_id, original_event_id
      ) values (
        target_organization_id, checkout.client_id, 'refunded', refund_amount_minor,
        original_receipt.currency_code, original_receipt.method,
        private.organization_today(target_organization_id), target_stripe_refund_id, refund_note,
        refund.requested_by, original_receipt.id
      )
      returning id into ledger_event_id;
    else
      select * into original_deposit
      from public.quote_deposit_events
      where organization_id = target_organization_id and id = checkout.quote_deposit_event_id
      for update;

      insert into public.client_payment_events (
        organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
        reference, note, actor_user_id, original_deposit_event_id
      ) values (
        target_organization_id, checkout.client_id, 'refunded', refund_amount_minor,
        checkout.currency_code, original_deposit.method,
        private.organization_today(target_organization_id), target_stripe_refund_id, refund_note,
        refund.requested_by, original_deposit.id
      )
      returning id into ledger_event_id;
    end if;

    update public.payment_stripe_refunds
    set status = 'succeeded', refund_event_id = ledger_event_id, completed_at = now(), updated_at = now()
    where id = refund.id;
    result_outcome := 'succeeded';
  else
    result_outcome := 'pending';
  end if;

  update public.payment_stripe_webhook_events set outcome = result_outcome
  where organization_id = target_organization_id
    and payment_stripe_webhook_events.stripe_event_id = apply_stripe_refund_event.stripe_event_id;

  return jsonb_build_object('outcome', result_outcome, 'refund_id', refund.id);
end;
$$;

comment on function public.apply_stripe_refund_event(uuid, text, text, text, text, text, bigint, text, text) is
  'Records a client_payment_events refund exactly once per Stripe refund id, whichever of the webhook or the '
  'synchronous refunds.create() response tells it first. Service role only.';

revoke all on function public.apply_stripe_refund_event(uuid, text, text, text, text, text, bigint, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_stripe_refund_event(uuid, text, text, text, text, text, bigint, text, text)
  to service_role;

-- 6. A dispute alerts; UCRM does not try to resolve it -----------------------------------------------------------

create or replace function public.apply_stripe_dispute_event(
  target_organization_id uuid,
  stripe_event_id text,
  stripe_event_type text,
  target_payment_intent_id text,
  dispute_amount_minor bigint,
  dispute_currency text,
  dispute_reason text
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
  result_outcome text;
  reason_note text;
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
    and payment_intent_id = target_payment_intent_id
    and status = 'paid';

  reason_note := case when dispute_reason is not null then ' (reason: ' || dispute_reason || ')' else '' end;

  if checkout.id is null then
    result_outcome := 'unknown_payment';
  elsif checkout.kind = 'invoice' then
    select * into invoice_row from public.invoices where id = checkout.invoice_id;
    perform private.create_payment_alerts(
      target_organization_id, 'invoice.payment_disputed', 'invoice', checkout.invoice_id,
      'invoices.record_payment', 'invoices.view_price', 'stripe:dispute:' || stripe_event_id,
      'A customer disputed a payment on invoice #' || invoice_row.invoice_number,
      private.format_minor(dispute_amount_minor, dispute_currency) || ' is disputed with their bank' ||
        reason_note || '. Respond in your Stripe dashboard -- UCRM cannot resolve a dispute itself.'
    );
    result_outcome := 'alerted';
  else
    select * into quote_row from public.quotes where id = checkout.quote_id;
    perform private.create_payment_alerts(
      target_organization_id, 'quote.deposit_disputed', 'quote', checkout.quote_id,
      'quotes.record_deposit', 'quotes.view_price', 'stripe:dispute:' || stripe_event_id,
      'A customer disputed a deposit on quote #' || quote_row.quote_number,
      private.format_minor(dispute_amount_minor, dispute_currency) || ' is disputed with their bank' ||
        reason_note || '. Respond in your Stripe dashboard -- UCRM cannot resolve a dispute itself.'
    );
    result_outcome := 'alerted';
  end if;

  update public.payment_stripe_webhook_events set outcome = result_outcome
  where organization_id = target_organization_id
    and payment_stripe_webhook_events.stripe_event_id = apply_stripe_dispute_event.stripe_event_id;

  return jsonb_build_object('outcome', result_outcome);
end;
$$;

comment on function public.apply_stripe_dispute_event(uuid, text, text, text, bigint, text, text) is
  'Alerts the contractor that a Stripe payment was disputed. Writes no ledger row -- docs/online-payments-'
  'behavior-contract.md is explicit that UCRM never tries to resolve a dispute itself. Service role only.';

revoke all on function public.apply_stripe_dispute_event(uuid, text, text, text, bigint, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_stripe_dispute_event(uuid, text, text, text, bigint, text, text)
  to service_role;
