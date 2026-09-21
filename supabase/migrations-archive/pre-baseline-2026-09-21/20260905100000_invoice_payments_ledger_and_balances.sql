-- Invoices Part 3b-1: the money ledger, the three balances, and the four commands that move money.
--
-- 3a built the bill and left two seams behind: private.invoice_allocated_minor, which answered zero because
-- there was nowhere to record money, and private.recognize_invoice_if_settled, which was therefore a no-op.
-- This file fills both in, and it does it with the shape the approved design named: receipt facts and where
-- the money was put are two different records, and neither is ever edited.
--
-- Three rules shape everything here.
--
-- First, money history is append-only in privilege, not just in habit. A mistake is corrected by adding a
-- row that says what was corrected, never by updating or deleting the row that was wrong. UPDATE, DELETE
-- and TRUNCATE are revoked from every application role and refused by triggers, so a SECURITY DEFINER
-- command running as the table owner cannot rewrite them either.
--
-- Second, a receipt is not a payment on an invoice. Money arrives against a client; applying it to a bill is
-- a separate, retained decision that can be taken back or moved. That is what makes contract decision D1
-- (money on a draft is client credit, not a receivable) representable at all.
--
-- Third, "does this bill still count as money owed?" is asked by balances, by payment reminders, by
-- collection and by Client Hub. It is stored once, as a calculated column on the invoice, so those four
-- answers cannot drift apart.
--
-- Deliberately not here, and deliberately still absent rather than half-built: refunds, reversal of a
-- mistaken receipt, Void, Bad debt and Mark received. Each is 3b-2. The table shapes they need exist here,
-- for the same reason 3a wired seams: so the rule arrives complete rather than in two incompatible halves.

-- 1. Does this bill still count as money owed? ------------------------------------------------------------

-- Stored, not repeated. The five facts it reads all live on the invoice itself, so a generated column is the
-- honest home for it: there is no way for a command to forget to maintain it, and the partial indexes below
-- can use it directly.
--
-- Issued or settled-by-payment, and not cancelled, not superseded, not written off. Marked received stays
-- true on purpose: a status-only closure never extinguished the debt.
alter table public.invoices
  add column is_effective_receivable boolean
  generated always as (
    (issued_at is not null or recognized_at is not null)
    and voided_at is null
    and replaced_at is null
    and written_off_at is null
  ) stored;

comment on column public.invoices.is_effective_receivable is
  'The one effective-receivable predicate. Balances, payment reminders, collection commands and Client Hub '
  'all read this rather than restating the rule, so they cannot disagree about what a client owes.';

grant select (is_effective_receivable) on public.invoices to authenticated;

-- 3a indexed the receivable set on issued/voided/replaced alone, before write-off existed as a rule. Nothing
-- reads it yet, so it is replaced here rather than left slightly wrong.
drop index if exists public.invoices_receivable_due_idx;

-- What is past due, and what payment reminders select from. Stays the size of the open ledger.
create index invoices_receivable_due_idx
  on public.invoices(organization_id, due_date, id)
  where is_effective_receivable;

-- What one client still owes, for the account balance below.
create index invoices_receivable_client_idx
  on public.invoices(organization_id, client_id, id)
  where is_effective_receivable;

-- 2. Money received -----------------------------------------------------------------------------------------

-- One row per real-world money event against a client: cash handed over, a bank transfer that landed, a
-- refund actually sent, or a reversal saying a recorded receipt never happened. None of these processes a
-- payment; the product is recording money that moved somewhere else, honestly.
--
-- Quote deposits are not copied in here. They are already immutable receipts in quote_deposit_events, and
-- the allocation table below points at either kind, so the same money is never recorded twice.
create table public.client_payment_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  -- 'received' is the only one 3b-1 has a command for. The other two are 3b-2's, and are named here so the
  -- shape of a correction is fixed before anything can write a half-version of it.
  event_type text not null check (event_type in ('received', 'refunded', 'reversed')),
  -- Always positive. The event type carries the direction, so no row can be ambiguous about its own sign.
  amount_minor bigint not null check (amount_minor > 0 and amount_minor <= 1000000000000),
  -- Snapshot, like the invoice's. Every allocation and refund must match it.
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  -- The six methods the contract names. None of them is a processor; each acknowledges money received
  -- elsewhere. A reversal has no method because no money moved.
  method text check (method in ('other', 'bank_transfer', 'cash', 'check', 'card_external', 'paypal')),
  -- The organization's own calendar date that the money moved, not the instant the row was written.
  payment_date date not null,
  reference text check (reference is null or char_length(trim(reference)) between 1 and 200),
  note text check (note is null or char_length(note) <= 2000),
  actor_user_id uuid references auth.users(id) on delete set null,
  -- What a refund or a reversal corrects: exactly one manual receipt, or exactly one reused quote deposit.
  original_event_id uuid,
  original_deposit_event_id uuid,
  created_at timestamptz not null default now(),
  constraint client_payment_events_organization_id_unique unique (organization_id, id),
  -- Carries the client into the allocation table's foreign key, so no allocation can point a client's money
  -- at another client's invoice.
  constraint client_payment_events_client_identity_unique unique (organization_id, id, client_id),
  constraint client_payment_events_client_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict,
  constraint client_payment_events_original_fk foreign key (organization_id, original_event_id)
    references public.client_payment_events(organization_id, id) on delete restrict,
  constraint client_payment_events_original_deposit_fk
    foreign key (organization_id, original_deposit_event_id)
    references public.quote_deposit_events(organization_id, id) on delete restrict,
  constraint client_payment_events_shape check (
    case event_type
      when 'received' then
        method is not null and original_event_id is null and original_deposit_event_id is null
      when 'refunded' then
        (original_event_id is not null) <> (original_deposit_event_id is not null)
      when 'reversed' then
        method is null and original_event_id is not null and original_deposit_event_id is null
    end
  )
);

comment on table public.client_payment_events is
  'Money that actually moved, recorded against a client. Immutable: a mistake is corrected by a reversing '
  'or refunding row that points at the original, never by an edit or a delete. Quote deposits stay in '
  'quote_deposit_events and are reused from there rather than copied in.';

comment on column public.client_payment_events.original_deposit_event_id is
  'Set when a refund returns money that arrived as a quote deposit. The foreign key is what stops a quote '
  'whose deposit an invoice has used from being deleted out from under that history.';

-- A client's money history, newest first: the payment list, and the anchor for the credit calculation.
create index client_payment_events_client_idx
  on public.client_payment_events(organization_id, client_id, created_at desc, id);

-- "Has this receipt already been refunded or reversed?" walks this direction, once per correction attempt.
create index client_payment_events_original_idx
  on public.client_payment_events(organization_id, original_event_id)
  where original_event_id is not null;

create index client_payment_events_original_deposit_idx
  on public.client_payment_events(organization_id, original_deposit_event_id)
  where original_deposit_event_id is not null;

create index client_payment_events_actor_idx
  on public.client_payment_events(actor_user_id) where actor_user_id is not null;

-- 3. Where the money was put ---------------------------------------------------------------------------------

-- Applying money to a bill and taking it back off are both entries, never a running total someone edits.
-- Moving money between invoices is one of each, in one transaction, and both stay visible afterwards.
--
-- Deliberately not a child row of the invoice, for the same reason invoice_events is not: a draft may be
-- deleted once its money has been explicitly returned to credit, and what happened to that money may not
-- disappear with it. So the invoice reference is a plain column carrying the number beside it.
create table public.invoice_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  -- Copied, not joined: history still reads as "Invoice #14" after that draft is gone.
  invoice_number integer not null check (invoice_number >= 1),
  client_id uuid not null,
  entry_type text not null check (entry_type in ('applied', 'unapplied')),
  amount_minor bigint not null check (amount_minor > 0 and amount_minor <= 1000000000000),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  -- Exactly one source: a manual receipt, or a deposit already recorded on a quote.
  payment_event_id uuid,
  deposit_event_id uuid,
  -- Set only on an 'unapplied' entry, pointing at the 'applied' entry it takes back.
  reversed_allocation_id uuid,
  reason text check (reason is null or char_length(reason) <= 2000),
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint invoice_payment_allocations_organization_id_unique unique (organization_id, id),
  constraint invoice_payment_allocations_client_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict,
  -- Three columns, not two: the client travels into the key, so this money and this invoice must belong to
  -- the same client at the database level rather than by the discipline of a command.
  constraint invoice_payment_allocations_payment_fk
    foreign key (organization_id, payment_event_id, client_id)
    references public.client_payment_events(organization_id, id, client_id) on delete restrict,
  -- Quote deposits carry no client of their own; theirs is resolved through the quote under lock by the
  -- commands below. What this key does guarantee is that the deposit cannot vanish from beneath the bill.
  constraint invoice_payment_allocations_deposit_fk foreign key (organization_id, deposit_event_id)
    references public.quote_deposit_events(organization_id, id) on delete restrict,
  constraint invoice_payment_allocations_reversed_fk
    foreign key (organization_id, reversed_allocation_id)
    references public.invoice_payment_allocations(organization_id, id) on delete restrict,
  constraint invoice_payment_allocations_one_source check (
    (payment_event_id is not null) <> (deposit_event_id is not null)
  ),
  constraint invoice_payment_allocations_reversal_shape check (
    (entry_type = 'applied' and reversed_allocation_id is null)
    or (entry_type = 'unapplied' and reversed_allocation_id is not null)
  )
);

comment on table public.invoice_payment_allocations is
  'Retained entries saying which money sits on which bill. Immutable: taking money off an invoice appends '
  'an ''unapplied'' entry pointing at the application it reverses, and moving money is one of each in a '
  'single transaction. Not a child of the invoice, so a deleted draft never erases what happened to money.';

-- An application can be taken back exactly once. The loser of a race to unapply the same entry fails here
-- rather than returning the same money to credit twice.
create unique index invoice_payment_allocations_reversed_once_idx
  on public.invoice_payment_allocations(organization_id, reversed_allocation_id)
  where reversed_allocation_id is not null;

-- What is on this bill: the balance read, and the invoice's payment history block.
create index invoice_payment_allocations_invoice_idx
  on public.invoice_payment_allocations(organization_id, invoice_id, created_at, id);

-- What this receipt has already been committed to: the "money not already spent" check on every apply.
create index invoice_payment_allocations_payment_idx
  on public.invoice_payment_allocations(organization_id, payment_event_id, id)
  where payment_event_id is not null;

create index invoice_payment_allocations_deposit_idx
  on public.invoice_payment_allocations(organization_id, deposit_event_id, id)
  where deposit_event_id is not null;

-- The client's committed money, for available credit.
create index invoice_payment_allocations_client_idx
  on public.invoice_payment_allocations(organization_id, client_id, created_at desc, id);

create index invoice_payment_allocations_actor_idx
  on public.invoice_payment_allocations(actor_user_id) where actor_user_id is not null;

-- 4. Append-only, enforced by the database ---------------------------------------------------------------------

-- The same protection invoice_events already has, and for a stronger reason: these rows are the money. The
-- trigger catches what a revoked grant cannot, which is a SECURITY DEFINER command running as the owner.
create or replace function private.payment_history_is_append_only()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Payment history is append-only. Correct it by recording a correction.'
    using errcode = 'check_violation';
end;
$$;

revoke all on function private.payment_history_is_append_only() from public;
revoke execute on function private.payment_history_is_append_only() from anon, authenticated;

create trigger client_payment_events_no_update_or_delete
before update or delete on public.client_payment_events
for each row execute function private.payment_history_is_append_only();

create trigger client_payment_events_no_truncate
before truncate on public.client_payment_events
for each statement execute function private.payment_history_is_append_only();

create trigger invoice_payment_allocations_no_update_or_delete
before update or delete on public.invoice_payment_allocations
for each row execute function private.payment_history_is_append_only();

create trigger invoice_payment_allocations_no_truncate
before truncate on public.invoice_payment_allocations
for each statement execute function private.payment_history_is_append_only();

-- Every column on both tables is money or points at money, so the read gate is the price permission and not
-- only the view permission. Someone who may see that invoices exist does not thereby see what was paid.
alter table public.client_payment_events enable row level security;

create policy "permitted members can view client payments"
on public.client_payment_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'invoices.view')
  and private.has_permission(organization_id, 'invoices.view_price')
);

revoke all on public.client_payment_events from anon, authenticated;
grant select on public.client_payment_events to authenticated;
revoke all on public.client_payment_events from service_role;
grant select, insert on public.client_payment_events to service_role;

alter table public.invoice_payment_allocations enable row level security;

create policy "permitted members can view invoice payment allocations"
on public.invoice_payment_allocations for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'invoices.view')
  and private.has_permission(organization_id, 'invoices.view_price')
);

revoke all on public.invoice_payment_allocations from anon, authenticated;
grant select on public.invoice_payment_allocations to authenticated;
revoke all on public.invoice_payment_allocations from service_role;
grant select, insert on public.invoice_payment_allocations to service_role;

-- 5. The seams 3a left, filled in --------------------------------------------------------------------------

-- The real body. Applications less the entries that took them back, which is the whole of "how much money
-- is on this bill" -- there is no second column anywhere holding a running total that could disagree.
create or replace function private.invoice_allocated_minor(
  target_organization_id uuid,
  target_invoice_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    sum(case when entry_type = 'applied' then amount_minor else -amount_minor end), 0
  )::bigint
  from public.invoice_payment_allocations
  where organization_id = target_organization_id
    and invoice_id = target_invoice_id;
$$;

comment on function private.invoice_allocated_minor(uuid, uuid) is
  'Money currently applied to this invoice, in minor units: applications less unapplications. The only '
  'answer to that question in the product; callers never read the allocation table directly.';

revoke all on function private.invoice_allocated_minor(uuid, uuid) from public;
revoke execute on function private.invoice_allocated_minor(uuid, uuid) from anon, authenticated;

-- Receiving money locks the currency too, and reads history to do it. A refund, a void or a deleted draft
-- therefore never unlocks it: the customer already saw an amount in that currency, and that is the fact the
-- lock protects.
create or replace function private.organization_currency_lock_reason(target_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when exists (
      select 1 from public.quotes
      where organization_id = target_organization_id
        and (current_published_version_id is not null or sent_at is not null)
    ) then 'quote_sent'
    when exists (
      select 1 from public.invoice_events
      where organization_id = target_organization_id
        and event_type in ('invoice.issued', 'invoice.recognized')
    ) then 'invoice_issued'
    when exists (
      select 1 from public.client_payment_events
      where organization_id = target_organization_id
    ) then 'money_received'
  end;
$$;

comment on function private.organization_currency_lock_reason(uuid) is
  'Why this organization''s currency is locked, or null when it is still free to change. The one predicate '
  'behind the settings reader, the business-profile save and the guard on organization_settings. It reads '
  'retained history on purpose, so refunding, voiding or deleting never unlocks it.';

-- 6. The three balances ---------------------------------------------------------------------------------------

-- What is left on one bill, added to the reader that already owns invoice money so a detail screen still
-- makes one gated call rather than two. Same permission shape as before: view to be here at all, view_price
-- to see any of it.
create or replace function public.invoice_money(target_invoice_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_invoice_ids is null or cardinality(target_invoice_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct invoice.organization_id) into organizations
  from public.invoices as invoice
  where invoice.id = any(target_invoice_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those invoices do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(org, caller, 'invoices.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(invoice.id::text, jsonb_build_object(
      'currency_code', invoice.currency_code,
      'subtotal_minor', invoice.subtotal_minor,
      'discount_minor', invoice.discount_minor,
      'discount_name', invoice.discount_name,
      'discount_type', invoice.discount_type,
      'discount_value', invoice.discount_value,
      'tax_minor', invoice.tax_minor,
      'tax_rate_basis_points', invoice.tax_rate_basis_points,
      'total_minor', invoice.total_minor,
      'allocated_minor', allocation.applied_minor,
      'remaining_minor', invoice.total_minor - allocation.applied_minor
    )), '{}'::jsonb)
  into answer
  from public.invoices as invoice
  cross join lateral (
    select coalesce(
      sum(case when entry.entry_type = 'applied' then entry.amount_minor else -entry.amount_minor end), 0
    )::bigint as applied_minor
    from public.invoice_payment_allocations as entry
    where entry.organization_id = invoice.organization_id
      and entry.invoice_id = invoice.id
  ) as allocation
  where invoice.organization_id = org
    and invoice.id = any(target_invoice_ids);

  return answer;
end;
$$;

comment on function public.invoice_money(uuid[]) is
  'Invoice amounts and what is left on them, for callers with price visibility. One permission check per '
  'call rather than per row, and one place that subtracts applied money from a total.';

revoke all on function public.invoice_money(uuid[]) from public;
revoke execute on function public.invoice_money(uuid[]) from anon;
grant execute on function public.invoice_money(uuid[]) to authenticated;

-- The other two balances, which are client-level rather than invoice-level, and which the contract is
-- careful to keep apart:
--
--   outstanding      -- what the client's effective bills still ask for
--   available credit -- money received that has not been refunded and is not committed to a bill
--   account balance  -- outstanding less that credit: the single number "what this client owes us"
--
-- Credit counts quote deposits as well as manual receipts, because a deposit is the client's money too.
-- It counts a receipt exactly once: a reversed receipt stops counting, a refund reduces it, and anything
-- already applied to a bill is committed rather than available.
create or replace function public.client_account_balance(target_client_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_client_ids is null or cardinality(target_client_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct client.organization_id) into organizations
  from public.clients as client
  where client.id = any(target_client_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those clients do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'invoices.view') then
    raise exception 'You do not have access to these clients'' billing.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(org, caller, 'invoices.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(client.id::text, jsonb_build_object(
      'currency_code', settings.currency_code,
      'outstanding_minor', outstanding.amount_minor,
      'available_credit_minor', credit.amount_minor,
      'account_balance_minor', outstanding.amount_minor - credit.amount_minor
    )), '{}'::jsonb)
  into answer
  from public.clients as client
  cross join public.organization_settings as settings
  -- What the effective bills still ask for. The partial index on is_effective_receivable is what keeps this
  -- to the client's open ledger instead of their whole billing history.
  cross join lateral (
    select coalesce(sum(invoice.total_minor - coalesce(entry.applied_minor, 0)), 0)::bigint as amount_minor
    from public.invoices as invoice
    left join lateral (
      select sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end) as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id
        and entry.invoice_id = invoice.id
    ) as entry on true
    where invoice.organization_id = client.organization_id
      and invoice.client_id = client.id
      and invoice.is_effective_receivable
  ) as outstanding
  cross join lateral (
    select (
      -- Manual receipts that were not reversed away.
      coalesce((
        select sum(receipt.amount_minor)
        from public.client_payment_events as receipt
        where receipt.organization_id = client.organization_id
          and receipt.client_id = client.id
          and receipt.event_type = 'received'
          and not exists (
            select 1 from public.client_payment_events as correction
            where correction.organization_id = receipt.organization_id
              and correction.original_event_id = receipt.id
              and correction.event_type = 'reversed'
          )
      ), 0)
      -- Quote deposits, reused where they already live, minus the ones the quote workspace reversed.
      + coalesce((
        select sum(deposit.amount_minor)
        from public.quote_deposit_events as deposit
        join public.quotes as quote
          on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
        where deposit.organization_id = client.organization_id
          and quote.client_id = client.id
          and deposit.event_type = 'received'
          and not exists (
            select 1 from public.quote_deposit_events as reversal
            where reversal.organization_id = deposit.organization_id
              and reversal.reversed_event_id = deposit.id
          )
      ), 0)
      -- Money actually sent back is no longer the client's to spend.
      - coalesce((
        select sum(refund.amount_minor)
        from public.client_payment_events as refund
        where refund.organization_id = client.organization_id
          and refund.client_id = client.id
          and refund.event_type = 'refunded'
      ), 0)
      -- Money committed to a bill is not available, whichever kind of receipt it came from.
      - coalesce((
        select sum(case when entry.entry_type = 'applied'
          then entry.amount_minor else -entry.amount_minor end)
        from public.invoice_payment_allocations as entry
        where entry.organization_id = client.organization_id
          and entry.client_id = client.id
      ), 0)
    )::bigint as amount_minor
  ) as credit
  where client.organization_id = org
    and client.id = any(target_client_ids)
    and settings.organization_id = org;

  return answer;
end;
$$;

comment on function public.client_account_balance(uuid[]) is
  'The two client-level money numbers the contract keeps apart: what their effective bills still ask for, '
  'and money of theirs that is neither refunded nor already committed to a bill. Never counts a receipt '
  'twice and never counts a voided, superseded or written-off bill.';

revoke all on function public.client_account_balance(uuid[]) from public;
revoke execute on function public.client_account_balance(uuid[]) from anon;
grant execute on function public.client_account_balance(uuid[]) to authenticated;
