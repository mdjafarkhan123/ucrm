-- Organization billing state and immutable offsite payment confirmations.
-- This is separate from package assignment history: package access and paid-through
-- dates change for different reasons and must not be represented by one event row.

create table public.organization_billing_accounts (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  paid_through_date date,
  paid_through_source text check (
    paid_through_source in ('legacy_owner_action', 'provisioning', 'renewal', 'manual_correction')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_billing_paid_through_state_check check (
    (paid_through_date is null and paid_through_source is null)
    or (paid_through_date is not null and paid_through_source is not null)
  )
);

create index organization_billing_accounts_paid_through_idx
  on public.organization_billing_accounts (paid_through_date, organization_id)
  where paid_through_date is not null;

create trigger organization_billing_accounts_set_updated_at
before update on public.organization_billing_accounts
for each row execute function public.set_updated_at();

create table public.organization_payment_confirmations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  payment_kind text not null check (payment_kind in ('initial', 'renewal')),
  amount_usd_cents integer not null check (amount_usd_cents > 0),
  currency text not null default 'USD' check (currency = 'USD'),
  private_reference text not null check (char_length(trim(private_reference)) between 1 and 240),
  confirmed_at timestamptz not null default now(),
  paid_through_date date not null,
  mismatch_reason text,
  created_at timestamptz not null default now(),
  constraint organization_payment_mismatch_reason_check check (
    mismatch_reason is null or char_length(trim(mismatch_reason)) between 1 and 500
  )
);

create index organization_payment_confirmations_org_date_idx
  on public.organization_payment_confirmations (organization_id, confirmed_at desc);

create or replace function private.prevent_organization_payment_confirmation_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Organization payment confirmations are immutable.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_organization_payment_confirmation_mutation() from public;

create trigger organization_payment_confirmations_immutable
before update or delete on public.organization_payment_confirmations
for each row execute function private.prevent_organization_payment_confirmation_mutation();

alter table public.organization_billing_accounts enable row level security;
alter table public.organization_payment_confirmations enable row level security;

revoke all on public.organization_billing_accounts, public.organization_payment_confirmations
  from anon, authenticated;
grant select, insert, update on public.organization_billing_accounts to service_role;
grant select, insert on public.organization_payment_confirmations to service_role;
