-- Platform-owned onboarding applications. These records are not tenant data.

create table public.platform_onboarding_applications (
  id uuid primary key default gen_random_uuid(),
  stage text not null default 'new' check (stage in (
    'new', 'awaiting_payment', 'payment_confirmed', 'needs_attention',
    'account_created', 'not_proceeding'
  )),
  business_name text not null,
  main_contact_name text not null,
  main_contact_email text not null,
  main_contact_phone text not null,
  initial_administrator_name text,
  initial_administrator_email text,
  trade text not null,
  city_country text not null,
  time_zone text not null,
  note text,
  package_version_id uuid not null references public.platform_package_versions(id),
  package_snapshot jsonb not null check (jsonb_typeof(package_snapshot) = 'object'),
  possible_duplicate boolean not null default false,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  not_proceeding_at timestamptz,
  personal_data_purge_after date not null default (current_date + 365),
  constraint platform_onboarding_applications_admin_email_check check (
    initial_administrator_email is null or position('@' in initial_administrator_email) > 1
  ),
  constraint platform_onboarding_applications_not_proceeding_check check (
    (stage = 'not_proceeding' and not_proceeding_at is not null)
    or (stage <> 'not_proceeding' and not_proceeding_at is null)
  )
);

create index platform_onboarding_applications_stage_idx
  on public.platform_onboarding_applications (stage, submitted_at desc);
create index platform_onboarding_applications_contact_email_idx
  on public.platform_onboarding_applications (lower(main_contact_email));
create index platform_onboarding_applications_admin_email_idx
  on public.platform_onboarding_applications (lower(initial_administrator_email))
  where initial_administrator_email is not null;

create trigger platform_onboarding_applications_set_updated_at
before update on public.platform_onboarding_applications
for each row execute function public.set_updated_at();

create table public.platform_onboarding_application_submissions (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.platform_onboarding_applications(id) on delete cascade,
  submitted_data jsonb not null check (jsonb_typeof(submitted_data) = 'object'),
  package_snapshot jsonb not null check (jsonb_typeof(package_snapshot) = 'object'),
  privacy_policy_version text not null,
  agreement_accepted_at timestamptz not null,
  submitted_at timestamptz not null default now()
);

create table public.platform_onboarding_application_corrections (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.platform_onboarding_applications(id),
  actor_owner_email text not null,
  reason text not null check (char_length(trim(reason)) > 0),
  before_state jsonb not null check (jsonb_typeof(before_state) = 'object'),
  after_state jsonb not null check (jsonb_typeof(after_state) = 'object'),
  created_at timestamptz not null default now()
);

create index platform_onboarding_application_corrections_application_idx
  on public.platform_onboarding_application_corrections (application_id, created_at desc);

alter table public.platform_onboarding_applications enable row level security;
alter table public.platform_onboarding_application_submissions enable row level security;
alter table public.platform_onboarding_application_corrections enable row level security;

revoke all on public.platform_onboarding_applications,
  public.platform_onboarding_application_submissions,
  public.platform_onboarding_application_corrections from anon, authenticated;
grant select, insert, update on public.platform_onboarding_applications to service_role;
grant select, insert on public.platform_onboarding_application_submissions to service_role;
grant select, insert on public.platform_onboarding_application_corrections to service_role;

create or replace function private.prevent_platform_onboarding_history_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Onboarding history is immutable.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_platform_onboarding_history_mutation() from public;

create trigger platform_onboarding_application_submissions_immutable
before update or delete on public.platform_onboarding_application_submissions
for each row execute function private.prevent_platform_onboarding_history_mutation();

create trigger platform_onboarding_application_corrections_immutable
before update or delete on public.platform_onboarding_application_corrections
for each row execute function private.prevent_platform_onboarding_history_mutation();
