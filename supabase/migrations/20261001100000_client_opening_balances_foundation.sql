-- Financial reconciliation, Part 6: client opening balances (schema only).
--
-- Assisted import's only two opening facts (contract: docs/financial-reconciliation-contract.md, "Opening
-- balances"): a Client's receivable, or their unused credit, as of a stated date. Each fact is written once by
-- the assisted-import worker (entity_type = 'opening_balance', reusing the client-import pipeline's
-- public.import_batches/import_rows from 20260916090000_client_import_foundation.sql) and never edited
-- afterwards. Correcting a mistake appends a new row that points back at the one it replaces -- the same
-- root/predecessor/replaced correction chain public.invoices already uses -- so an accountant can always trace
-- what a number was and why it changed.
--
-- These rows never invent historic Jobs, Invoices, or Payments (contract). They will feed exactly two things,
-- neither built in this migration: the opening-balances CSV and each Client's reconciled balance. The
-- assisted-import worker RPC that writes these rows, and that reader/export wiring, follow once this shape is
-- confirmed -- the same table-then-processor split the client-import and forms features used.

create table public.client_opening_balances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,

  balance_type text not null check (balance_type in ('receivable', 'credit')),
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  -- The business date the fact was true as of, not when it was typed in. Reporting-date rules for this column
  -- follow the contract's calendar rules, same as every other stored business date.
  as_of_date date not null,
  source_note text check (source_note is null or char_length(source_note) <= 500),

  -- The correction chain, identical in shape to public.invoices: a fresh fact points at itself as its own
  -- root; a correction names the fact it replaces and shares that fact's root.
  predecessor_opening_balance_id uuid,
  root_opening_balance_id uuid not null,
  replaced_at timestamptz,
  replaced_by_opening_balance_id uuid,

  -- Only the assisted-import pipeline may write these rows -- never a form, never SQL run by hand.
  import_batch_id uuid not null,
  import_row_id uuid not null,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  constraint client_opening_balances_org_id_unique unique (organization_id, id),

  constraint client_opening_balances_client_fk foreign key (organization_id, client_id)
    references public.clients (organization_id, id) on delete restrict,
  constraint client_opening_balances_predecessor_fk foreign key (organization_id, predecessor_opening_balance_id)
    references public.client_opening_balances (organization_id, id) on delete restrict,
  constraint client_opening_balances_root_fk foreign key (organization_id, root_opening_balance_id)
    references public.client_opening_balances (organization_id, id) on delete restrict,
  constraint client_opening_balances_replaced_by_fk foreign key (organization_id, replaced_by_opening_balance_id)
    references public.client_opening_balances (organization_id, id) on delete restrict,
  -- A batch that produced a financial fact can never be deleted out from under it.
  constraint client_opening_balances_batch_fk foreign key (organization_id, import_batch_id)
    references public.import_batches (organization_id, id) on delete restrict,
  constraint client_opening_balances_import_row_fk foreign key (import_row_id)
    references public.import_rows (id) on delete restrict,

  constraint client_opening_balances_predecessor_not_self check (
    predecessor_opening_balance_id is null or predecessor_opening_balance_id <> id
  ),
  constraint client_opening_balances_replaced_facts_complete check (
    (replaced_at is null) = (replaced_by_opening_balance_id is null)
  )
);

comment on table public.client_opening_balances is
  'The two opening facts assisted import may record for a Client: receivable or unused credit, as of a date. '
  'Members read this table and never write it; every row is created only by the assisted-import worker. A '
  'correction appends a new fact and marks the one it replaces, so history is never edited or deleted.';

comment on column public.client_opening_balances.root_opening_balance_id is
  'The first fact in this correction chain, set to the fact''s own id when it starts one.';

comment on column public.client_opening_balances.replaced_at is
  'When a correction superseded this fact. A replaced fact stays in reconciliation history but is excluded '
  'from the Client''s current opening balance.';

-- Reconciled Client balance and the audit trail both need every active fact for one client, newest first.
create index client_opening_balances_client_active_idx
  on public.client_opening_balances (organization_id, client_id, created_at desc)
  where replaced_at is null;

-- Tracing a fact's full correction history.
create index client_opening_balances_root_idx
  on public.client_opening_balances (organization_id, root_opening_balance_id, created_at);

-- The Done screen and audit trail read every fact one import batch produced.
create index client_opening_balances_batch_idx
  on public.client_opening_balances (organization_id, import_batch_id);

-- ---------------------------------------------------------------------------------------------------------
-- What can never change -- mirrors private.invoices_set_root / private.invoices_guard_identity exactly.
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.client_opening_balances_set_root()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.root_opening_balance_id is null then
    new.root_opening_balance_id := new.id;
  end if;
  return new;
end;
$$;

revoke all on function private.client_opening_balances_set_root() from public;
revoke execute on function private.client_opening_balances_set_root() from anon, authenticated;

create trigger client_opening_balances_set_root
before insert on public.client_opening_balances
for each row execute function private.client_opening_balances_set_root();

create or replace function private.client_opening_balances_guard_identity()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.client_id is distinct from old.client_id
     or new.balance_type is distinct from old.balance_type
     or new.amount_minor is distinct from old.amount_minor
     or new.currency_code is distinct from old.currency_code
     or new.as_of_date is distinct from old.as_of_date
     or new.import_batch_id is distinct from old.import_batch_id
     or new.import_row_id is distinct from old.import_row_id
     or new.root_opening_balance_id is distinct from old.root_opening_balance_id
     or new.predecessor_opening_balance_id is distinct from old.predecessor_opening_balance_id then
    raise exception 'An opening balance fact cannot be changed, only corrected by a new linked fact.'
      using errcode = 'check_violation';
  end if;
  if old.replaced_at is not null
     and (new.replaced_at is distinct from old.replaced_at
          or new.replaced_by_opening_balance_id is distinct from old.replaced_by_opening_balance_id) then
    raise exception 'A replaced opening balance fact cannot be changed.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function private.client_opening_balances_guard_identity() from public;
revoke execute on function private.client_opening_balances_guard_identity() from anon, authenticated;

create trigger client_opening_balances_guard_identity
before update on public.client_opening_balances
for each row execute function private.client_opening_balances_guard_identity();

-- ---------------------------------------------------------------------------------------------------------
-- Access -- read-only, gated by the same Invoice financial visibility permission the contract names.
-- ---------------------------------------------------------------------------------------------------------

alter table public.client_opening_balances enable row level security;

create policy "permitted members can view opening balances"
on public.client_opening_balances for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'invoices.view')
);

revoke all on public.client_opening_balances from anon, authenticated;

grant select on public.client_opening_balances to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- The assisted-import pipeline gains a second entity type.
-- ---------------------------------------------------------------------------------------------------------

alter table public.import_batches drop constraint import_batches_entity_type_check;
alter table public.import_batches add constraint import_batches_entity_type_check
  check (entity_type in ('client', 'opening_balance'));

comment on column public.import_batches.entity_type is
  'What this batch imports. ''client'' creates/updates Clients (Part 1). ''opening_balance'' writes '
  'public.client_opening_balances facts (financial reconciliation Part 6) and never touches Job, Invoice, or '
  'Payment history.';
