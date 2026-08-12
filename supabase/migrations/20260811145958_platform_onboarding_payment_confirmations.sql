-- Payment confirmation for an onboarding application, before any organization exists.
-- Separate from public.organization_payment_confirmations, which is organization-scoped
-- and cannot represent a payment recorded before provisioning.

create table public.platform_onboarding_application_payment_confirmations (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.platform_onboarding_applications(id),
  actor_owner_email text not null,
  amount_usd_cents integer not null check (amount_usd_cents > 0),
  currency text not null default 'USD' check (currency = 'USD'),
  private_reference text not null check (char_length(trim(private_reference)) between 1 and 240),
  package_version_id uuid not null references public.platform_package_versions(id),
  mismatch_reason text check (
    mismatch_reason is null or char_length(trim(mismatch_reason)) between 1 and 500
  ),
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index platform_onboarding_application_payment_confirmations_app_idx
  on public.platform_onboarding_application_payment_confirmations (application_id, confirmed_at desc);

alter table public.platform_onboarding_application_payment_confirmations enable row level security;

revoke all on public.platform_onboarding_application_payment_confirmations from anon, authenticated;
grant select, insert on public.platform_onboarding_application_payment_confirmations to service_role;

create trigger platform_onboarding_application_payment_confirmations_immutable
before update or delete on public.platform_onboarding_application_payment_confirmations
for each row execute function private.prevent_platform_onboarding_history_mutation();
