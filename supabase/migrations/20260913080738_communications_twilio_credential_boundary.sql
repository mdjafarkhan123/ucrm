-- Communications A2 / Stage 2A: server-only Twilio account and encrypted credential boundary.
-- This migration stores no plaintext secret and does not configure or contact Twilio.

create table public.communication_twilio_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null default 'twilio',
  subaccount_sid text not null,
  messaging_service_sid text,
  lifecycle_state text not null default 'provisioning',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_twilio_accounts_organization_key unique (organization_id),
  constraint communication_twilio_accounts_org_id_key unique (organization_id, id),
  constraint communication_twilio_accounts_subaccount_key unique (subaccount_sid),
  constraint communication_twilio_accounts_provider_check check (provider = 'twilio'),
  constraint communication_twilio_accounts_subaccount_sid_check
    check (subaccount_sid ~ '^AC[0-9A-Fa-f]{32}$'),
  constraint communication_twilio_accounts_messaging_service_sid_check
    check (messaging_service_sid is null or messaging_service_sid ~ '^MG[0-9A-Fa-f]{32}$'),
  constraint communication_twilio_accounts_lifecycle_check
    check (lifecycle_state in ('provisioning', 'ready', 'restricted', 'suspended', 'closed'))
);

create table public.communication_twilio_credentials (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  twilio_account_id uuid not null,
  credential_purpose text not null,
  lifecycle_state text not null,
  credential_sid text,
  algorithm text not null default 'aes-256-gcm',
  format_version smallint not null default 1,
  encryption_key_id text not null,
  nonce bytea not null,
  ciphertext bytea not null,
  authentication_tag bytea not null,
  retire_after timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_twilio_credentials_account_fk
    foreign key (organization_id, twilio_account_id)
    references public.communication_twilio_accounts (organization_id, id) on delete cascade,
  constraint communication_twilio_credentials_purpose_check
    check (credential_purpose in ('restricted_api_key', 'auth_token')),
  constraint communication_twilio_credentials_lifecycle_check
    check (lifecycle_state in ('staged', 'current', 'prior')),
  constraint communication_twilio_credentials_sid_check check (
    (credential_purpose = 'restricted_api_key'
      and credential_sid is not null
      and credential_sid ~ '^SK[0-9A-Fa-f]{32}$')
    or (credential_purpose = 'auth_token' and credential_sid is null)
  ),
  constraint communication_twilio_credentials_algorithm_check check (algorithm = 'aes-256-gcm'),
  constraint communication_twilio_credentials_format_check check (format_version = 1),
  constraint communication_twilio_credentials_key_id_check
    check (encryption_key_id ~ '^[A-Za-z0-9._-]{1,64}$'),
  constraint communication_twilio_credentials_nonce_check check (octet_length(nonce) = 12),
  constraint communication_twilio_credentials_ciphertext_check check (octet_length(ciphertext) > 0),
  constraint communication_twilio_credentials_tag_check check (octet_length(authentication_tag) = 16),
  constraint communication_twilio_credentials_retirement_check check (
    (lifecycle_state = 'prior' and retire_after is not null)
    or (lifecycle_state <> 'prior' and retire_after is null)
  )
);

create unique index communication_twilio_credentials_one_lifecycle_key
  on public.communication_twilio_credentials (
    twilio_account_id,
    credential_purpose,
    lifecycle_state
  );

alter table public.communication_twilio_accounts enable row level security;
alter table public.communication_twilio_credentials enable row level security;

revoke all on table public.communication_twilio_accounts from public, anon, authenticated;
revoke all on table public.communication_twilio_credentials from public, anon, authenticated;
revoke all on table public.communication_twilio_accounts from service_role;
revoke all on table public.communication_twilio_credentials from service_role;

grant select, insert, update, delete on table public.communication_twilio_accounts to service_role;
grant select, insert, update, delete on table public.communication_twilio_credentials to service_role;

comment on table public.communication_twilio_accounts is
  'Server-owned Twilio subaccount identity and safe provider references. No provider secret belongs here.';
comment on table public.communication_twilio_credentials is
  'Server-owned AES-256-GCM ciphertext only. Plaintext Twilio credentials must never enter Postgres.';
