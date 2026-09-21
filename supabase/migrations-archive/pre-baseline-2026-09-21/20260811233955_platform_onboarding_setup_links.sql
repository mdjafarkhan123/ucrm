-- Single-use, 24-hour password-setup link for a newly provisioned administrator.
--
-- One row per application, like the provisions table: mutable operational state, not
-- immutable history. A resend overwrites this row (new token hash, reset expiry, cleared
-- consumed/error state), which is how "resend replaces the earlier unused link" is enforced --
-- the previous raw token no longer matches any stored hash once overwritten.

create table public.platform_onboarding_application_setup_links (
  application_id uuid primary key references public.platform_onboarding_applications(id),
  administrator_user_id uuid not null,
  intended_email text not null,
  token_hash text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  last_sent_at timestamptz not null default now(),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index platform_onboarding_application_setup_links_token_idx
  on public.platform_onboarding_application_setup_links (token_hash);

create trigger platform_onboarding_application_setup_links_set_updated_at
before update on public.platform_onboarding_application_setup_links
for each row execute function public.set_updated_at();

alter table public.platform_onboarding_application_setup_links enable row level security;

revoke all on public.platform_onboarding_application_setup_links from anon, authenticated;
grant select, insert, update on public.platform_onboarding_application_setup_links to service_role;
