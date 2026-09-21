-- Online payments Part 6: Venmo, Zelle, Cash App, PayPal and Interac e-Transfer.
--
-- docs/online-payments-behavior-contract.md §6. None of these are processed by UCRM -- there is no API to
-- connect to. The contractor tells UCRM their own Venmo/Cash App/PayPal.me handle, Zelle contact, e-Transfer
-- email and bank transfer instructions; the customer's invoice and deposit pages show an "Other ways to pay"
-- box built from whatever the contractor filled in, and the contractor records the payment themselves once
-- it arrives (Venmo, Zelle, Cash App and e-Transfer join PayPal and the other five as recorded methods --
-- see 20261008090000_online_invoice_payments.sql's own comment on that check constraint).

-- 1. The contractor's pay-by-app details -----------------------------------------------------------------

-- Handles only, not full URLs: UCRM builds the Venmo/Cash App/PayPal.me link itself (venmo.com/u/<handle>,
-- cash.app/$<handle>, paypal.me/<handle>), so a contractor pasting a full link or a leading @/$ still works --
-- the browser strips it before saving (src/lib/server/validation/settings.schema.ts).
alter table public.organization_settings
  add column pay_by_app_venmo_username text,
  add column pay_by_app_cash_app_cashtag text,
  add column pay_by_app_paypal_me_username text,
  add column pay_by_app_zelle_contact text,
  add column pay_by_app_e_transfer_email text,
  add column pay_by_app_bank_transfer_instructions text,
  add constraint organization_settings_venmo_username_check
    check (pay_by_app_venmo_username is null or char_length(pay_by_app_venmo_username) <= 30),
  add constraint organization_settings_cash_app_cashtag_check
    check (pay_by_app_cash_app_cashtag is null or char_length(pay_by_app_cash_app_cashtag) <= 20),
  add constraint organization_settings_paypal_me_username_check
    check (pay_by_app_paypal_me_username is null or char_length(pay_by_app_paypal_me_username) <= 50),
  add constraint organization_settings_zelle_contact_check
    check (pay_by_app_zelle_contact is null or char_length(pay_by_app_zelle_contact) <= 254),
  add constraint organization_settings_e_transfer_email_check
    check (pay_by_app_e_transfer_email is null or char_length(pay_by_app_e_transfer_email) <= 254),
  add constraint organization_settings_bank_transfer_instructions_check
    check (
      pay_by_app_bank_transfer_instructions is null
      or char_length(pay_by_app_bank_transfer_instructions) <= 1000
    );

-- 2. New recorded methods ---------------------------------------------------------------------------------

alter table public.client_payment_events drop constraint client_payment_events_method_check;
alter table public.client_payment_events add constraint client_payment_events_method_check
  check (method in (
    'other', 'bank_transfer', 'cash', 'check', 'card_external', 'paypal',
    'venmo', 'zelle', 'cash_app', 'e_transfer',
    'stripe_card', 'stripe_bank', 'stripe_other'
  ));

alter table public.quote_deposit_events drop constraint quote_deposit_events_method_check;
alter table public.quote_deposit_events add constraint quote_deposit_events_method_check
  check (method in ('cash', 'check', 'other', 'venmo', 'zelle', 'cash_app', 'e_transfer',
    'stripe_card', 'stripe_bank', 'stripe_other'));

-- record_quote_deposit_event's own whitelist (the manual-record path, not the online-checkout path) needs the
-- same four methods; it never accepted 'card_external' or 'paypal' before this and still doesn't -- that gap
-- is pre-existing and out of scope here.
create or replace function public.record_quote_deposit_event(
  target_quote_id uuid,
  idempotency_key text,
  method text,
  reference text default null,
  note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
  existing_event public.quote_deposit_events;
  inserted_event public.quote_deposit_events;
  clean_reference text := nullif(trim(coalesce(reference, '')), '');
  clean_note text := nullif(trim(coalesce(note, '')), '');
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if method not in ('cash', 'check', 'other', 'venmo', 'zelle', 'cash_app', 'e_transfer') then
    raise exception 'Choose how the deposit was received.' using errcode = 'check_violation';
  end if;

  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.record_deposit'
  ) then
    raise exception 'You do not have access to record a deposit on this quote.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into existing_event
  from public.quote_deposit_events
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and quote_deposit_events.idempotency_key = record_quote_deposit_event.idempotency_key;
  if existing_event.id is not null then
    return jsonb_build_object('status', 'recorded', 'event_id', existing_event.id);
  end if;

  select * into version_row from public.quote_versions
  where id = quote_row.current_published_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    raise exception 'This quote has no published version to record a deposit against.'
      using errcode = 'check_violation';
  end if;
  if version_row.deposit_type is null or version_row.deposit_required_minor <= 0 then
    raise exception 'This quote does not require a deposit.' using errcode = 'check_violation';
  end if;

  if exists (
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
  ) then
    raise exception 'A deposit has already been recorded for this quote.'
      using errcode = 'check_violation';
  end if;

  insert into public.quote_deposit_events (
    organization_id, quote_id, quote_version_id, event_type, amount_minor, method, reference, note,
    recorded_by, idempotency_key
  )
  values (
    version_row.organization_id, version_row.quote_id, version_row.id, 'received',
    version_row.deposit_required_minor, method, clean_reference, clean_note,
    (select auth.uid()), idempotency_key
  )
  returning * into inserted_event;

  return jsonb_build_object('status', 'recorded', 'event_id', inserted_event.id);
end;
$$;

-- 3. Save the contractor's pay-by-app details alongside the four existing switches -----------------------

drop function if exists public.set_organization_payment_settings(uuid, integer, boolean, boolean, boolean, boolean);

create or replace function public.set_organization_payment_settings(
  target_organization_id uuid,
  expected_revision integer,
  new_invoice_payments boolean,
  new_deposit_payments boolean,
  new_tips boolean,
  new_receipt_email boolean,
  new_venmo_username text,
  new_cash_app_cashtag text,
  new_paypal_me_username text,
  new_zelle_contact text,
  new_e_transfer_email text,
  new_bank_transfer_instructions text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  editor_name text;
  changed text[] := array[]::text[];
begin
  if not private.has_permission(target_organization_id, 'settings.payments.manage') then
    raise exception 'You do not have access to manage online payments.' using errcode = 'insufficient_privilege';
  end if;

  if new_invoice_payments is null or new_deposit_payments is null or new_tips is null
     or new_receipt_email is null then
    raise exception 'Every payment setting needs a value.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.payment_settings_revision then
    select profile.full_name into editor_name
    from public.profiles as profile
    where profile.id = settings_row.payment_settings_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(settings_row.payment_settings_updated_at, settings_row.updated_at)
    );
  end if;

  if new_invoice_payments is distinct from settings_row.online_invoice_payments_enabled then
    changed := array_append(changed, 'online_invoice_payments_enabled');
  end if;
  if new_deposit_payments is distinct from settings_row.online_deposit_payments_enabled then
    changed := array_append(changed, 'online_deposit_payments_enabled');
  end if;
  if new_tips is distinct from settings_row.online_tips_enabled then
    changed := array_append(changed, 'online_tips_enabled');
  end if;
  if new_receipt_email is distinct from settings_row.online_receipt_email_enabled then
    changed := array_append(changed, 'online_receipt_email_enabled');
  end if;
  if new_venmo_username is distinct from settings_row.pay_by_app_venmo_username then
    changed := array_append(changed, 'pay_by_app_venmo_username');
  end if;
  if new_cash_app_cashtag is distinct from settings_row.pay_by_app_cash_app_cashtag then
    changed := array_append(changed, 'pay_by_app_cash_app_cashtag');
  end if;
  if new_paypal_me_username is distinct from settings_row.pay_by_app_paypal_me_username then
    changed := array_append(changed, 'pay_by_app_paypal_me_username');
  end if;
  if new_zelle_contact is distinct from settings_row.pay_by_app_zelle_contact then
    changed := array_append(changed, 'pay_by_app_zelle_contact');
  end if;
  if new_e_transfer_email is distinct from settings_row.pay_by_app_e_transfer_email then
    changed := array_append(changed, 'pay_by_app_e_transfer_email');
  end if;
  if new_bank_transfer_instructions is distinct from settings_row.pay_by_app_bank_transfer_instructions then
    changed := array_append(changed, 'pay_by_app_bank_transfer_instructions');
  end if;

  update public.organization_settings
  set online_invoice_payments_enabled = new_invoice_payments,
      online_deposit_payments_enabled = new_deposit_payments,
      online_tips_enabled = new_tips,
      online_receipt_email_enabled = new_receipt_email,
      pay_by_app_venmo_username = new_venmo_username,
      pay_by_app_cash_app_cashtag = new_cash_app_cashtag,
      pay_by_app_paypal_me_username = new_paypal_me_username,
      pay_by_app_zelle_contact = new_zelle_contact,
      pay_by_app_e_transfer_email = new_e_transfer_email,
      pay_by_app_bank_transfer_instructions = new_bank_transfer_instructions,
      payment_settings_revision = payment_settings_revision + 1,
      payment_settings_updated_by = (select auth.uid()),
      payment_settings_updated_at = now()
  where organization_id = target_organization_id
  returning payment_settings_revision into settings_row.payment_settings_revision;

  if cardinality(changed) > 0 then
    insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
    values (target_organization_id, 'payment_settings', changed, (select auth.uid()));
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'payment_settings_revision', settings_row.payment_settings_revision
  );
end;
$$;

revoke all on function public.set_organization_payment_settings(
  uuid, integer, boolean, boolean, boolean, boolean, text, text, text, text, text, text
) from public;
revoke execute on function public.set_organization_payment_settings(
  uuid, integer, boolean, boolean, boolean, boolean, text, text, text, text, text, text
) from anon;
grant execute on function public.set_organization_payment_settings(
  uuid, integer, boolean, boolean, boolean, boolean, text, text, text, text, text, text
) to authenticated;

-- 4. Show pay-by-app details on the customer's invoice and deposit pages ----------------------------------

-- Both read models already select the full organization_settings row; add the six handles to what they hand
-- back. Unlike 'available', this has nothing to do with Stripe -- a business with no Stripe connection at all
-- can still fill these in, so the customer page decides on its own whether to show the Pay button
-- (needs Stripe) and separately whether to show "Other ways to pay" (needs at least one of these).
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
    'tip_base_minor', greatest(invoice_row.subtotal_minor - invoice_row.discount_minor, 0),
    'livemode', connection_row.livemode,
    'stripe_account_id', connection_row.stripe_account_id,
    'pay_by_app', jsonb_build_object(
      'venmo_username', settings_row.pay_by_app_venmo_username,
      'cash_app_cashtag', settings_row.pay_by_app_cash_app_cashtag,
      'paypal_me_username', settings_row.pay_by_app_paypal_me_username,
      'zelle_contact', settings_row.pay_by_app_zelle_contact,
      'e_transfer_email', settings_row.pay_by_app_e_transfer_email,
      'bank_transfer_instructions', settings_row.pay_by_app_bank_transfer_instructions
    )
  );
end;
$$;

revoke all on function public.invoice_online_payment_context(bytea) from public, anon, authenticated;
grant execute on function public.invoice_online_payment_context(bytea) to service_role;

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
    'stripe_account_id', connection_row.stripe_account_id,
    'pay_by_app', jsonb_build_object(
      'venmo_username', settings_row.pay_by_app_venmo_username,
      'cash_app_cashtag', settings_row.pay_by_app_cash_app_cashtag,
      'paypal_me_username', settings_row.pay_by_app_paypal_me_username,
      'zelle_contact', settings_row.pay_by_app_zelle_contact,
      'e_transfer_email', settings_row.pay_by_app_e_transfer_email,
      'bank_transfer_instructions', settings_row.pay_by_app_bank_transfer_instructions
    )
  );
end;
$$;

revoke all on function public.quote_online_deposit_context(bytea) from public, anon, authenticated;
grant execute on function public.quote_online_deposit_context(bytea) to service_role;
