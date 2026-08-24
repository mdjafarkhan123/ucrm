-- Communications Part 2, layer 1: stored authority for contractor email domains and senders.
-- Provider calls stay outside database transactions. This migration does not enable the live worker.

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'conversations.manage_connections'),
  ('admin', 'conversations.manage_connections')
on conflict (role, permission_key) do nothing;

create table public.communication_email_domains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purpose text not null check (purpose in ('sending', 'receiving')),
  domain_name text not null check (
    domain_name = lower(btrim(domain_name))
    and char_length(domain_name) between 4 and 253
    and domain_name ~ '^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'
  ),
  lifecycle_state text not null default 'pending_dns' check (
    lifecycle_state in (
      'pending_dns', 'verified', 'unhealthy', 'transitioning', 'removal_pending', 'removed'
    )
  ),
  provider text not null default 'brevo' check (provider = 'brevo'),
  provider_domain_id bigint,
  provider_verified boolean not null default false,
  provider_authenticated boolean not null default false,
  ownership_status text not null default 'unchecked' check (
    ownership_status in ('unchecked', 'pending', 'passing', 'failing')
  ),
  dkim_status text not null default 'unchecked' check (
    dkim_status in ('unchecked', 'pending', 'passing', 'failing')
  ),
  dmarc_status text not null default 'unchecked' check (
    dmarc_status in ('unchecked', 'pending', 'passing', 'failing')
  ),
  spf_status text not null default 'unchecked' check (
    spf_status in ('unchecked', 'pending', 'passing', 'failing')
  ),
  inbound_mx_status text not null default 'unchecked' check (
    inbound_mx_status in ('unchecked', 'pending', 'passing', 'failing')
  ),
  dns_records jsonb not null default '[]'::jsonb check (jsonb_typeof(dns_records) = 'array'),
  last_checked_at timestamptz,
  verified_at timestamptz,
  warmup_started_at timestamptz,
  replacement_of_domain_id uuid,
  transition_until timestamptz,
  provider_cleanup_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_email_domains_organization_id_id_key unique (organization_id, id),
  constraint communication_email_domains_replacement_fk
    foreign key (organization_id, replacement_of_domain_id)
    references public.communication_email_domains(organization_id, id) on delete set null,
  constraint communication_email_domains_provider_id_key unique (provider, provider_domain_id),
  constraint communication_email_domains_purpose_health_check check (
    (purpose = 'sending' and inbound_mx_status = 'unchecked')
    or (purpose = 'receiving' and dkim_status = 'unchecked' and dmarc_status = 'unchecked'
      and spf_status = 'unchecked' and provider_authenticated = false)
  ),
  constraint communication_email_domains_verified_state_check check (
    lifecycle_state <> 'verified'
    or (
      provider_verified
      and ownership_status = 'passing'
      and (
        (purpose = 'sending' and provider_authenticated and dkim_status = 'passing'
          and spf_status = 'passing')
        or (purpose = 'receiving' and inbound_mx_status = 'passing')
      )
    )
  ),
  constraint communication_email_domains_removed_cleanup_check check (
    lifecycle_state <> 'removed' or provider_cleanup_error is null
  ),
  constraint communication_email_domains_transition_check check (
    (lifecycle_state = 'transitioning') = (transition_until is not null)
  )
);

-- A non-removed domain remains claimed even while provider cleanup is pending. Reuse is safe only after
-- cleanup reaches the explicit removed state.
create unique index communication_email_domains_live_claim_idx
  on public.communication_email_domains (domain_name)
  where lifecycle_state <> 'removed';

create index communication_email_domains_organization_purpose_state_idx
  on public.communication_email_domains (organization_id, purpose, lifecycle_state, created_at desc);

create index communication_email_domains_replacement_idx
  on public.communication_email_domains (organization_id, replacement_of_domain_id)
  where replacement_of_domain_id is not null;

create index communication_email_domains_created_by_idx
  on public.communication_email_domains (created_by)
  where created_by is not null;

create table public.communication_email_senders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  domain_id uuid not null,
  email_address text not null check (
    email_address = lower(btrim(email_address))
    and char_length(email_address) between 3 and 320
    and position('@' in email_address) > 1
  ),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 160),
  provider text not null default 'brevo' check (provider = 'brevo'),
  provider_sender_id bigint,
  lifecycle_state text not null default 'pending_verification' check (
    lifecycle_state in (
      'pending_verification', 'enabled', 'restricted', 'disabled', 'removal_pending', 'removed'
    )
  ),
  assigned_user_id uuid,
  is_organization_default boolean not null default false,
  allows_manual boolean not null default true,
  allows_automated boolean not null default false,
  restriction_reason text check (
    restriction_reason is null or char_length(btrim(restriction_reason)) between 1 and 500
  ),
  provider_cleanup_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_email_senders_organization_id_id_key unique (organization_id, id),
  constraint communication_email_senders_domain_fk
    foreign key (organization_id, domain_id)
    references public.communication_email_domains(organization_id, id) on delete restrict,
  constraint communication_email_senders_member_fk
    foreign key (organization_id, assigned_user_id)
    references public.organization_members(organization_id, user_id),
  constraint communication_email_senders_provider_id_key unique (provider, provider_sender_id),
  constraint communication_email_senders_restriction_check check (
    (lifecycle_state = 'restricted') = (restriction_reason is not null)
  ),
  constraint communication_email_senders_removed_cleanup_check check (
    lifecycle_state <> 'removed' or provider_cleanup_error is null
  ),
  constraint communication_email_senders_use_check check (
    allows_manual or allows_automated or lifecycle_state <> 'enabled'
  )
);

create unique index communication_email_senders_live_address_idx
  on public.communication_email_senders (organization_id, email_address)
  where lifecycle_state <> 'removed';

create unique index communication_email_senders_one_enabled_default_idx
  on public.communication_email_senders (organization_id)
  where lifecycle_state = 'enabled' and is_organization_default;

-- Matches the sender-resolution predicates used by the future atomic worker claim.
create index communication_email_senders_eligible_idx
  on public.communication_email_senders (
    organization_id, assigned_user_id, is_organization_default, allows_manual, allows_automated, id
  )
  where lifecycle_state = 'enabled';

create index communication_email_senders_domain_idx
  on public.communication_email_senders (organization_id, domain_id, lifecycle_state);

create index communication_email_senders_created_by_idx
  on public.communication_email_senders (created_by)
  where created_by is not null;

create table public.communication_email_authority_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_kind text not null check (actor_kind in ('platform_owner', 'contractor_user', 'system')),
  -- Keep immutable attribution even after an Auth account is removed. Organization membership keeps the
  -- matching historical identity; this audit row deliberately has no auth.users foreign key.
  actor_user_id uuid,
  actor_owner_email text,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_type text not null check (target_type in ('domain', 'sender')),
  target_id uuid not null,
  before_state jsonb,
  after_state jsonb,
  reason text check (reason is null or char_length(btrim(reason)) between 1 and 500),
  idempotency_key text not null check (char_length(btrim(idempotency_key)) between 1 and 200),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint communication_email_authority_events_actor_check check (
    (actor_kind = 'contractor_user' and actor_user_id is not null and actor_owner_email is null)
    or (actor_kind = 'platform_owner' and actor_user_id is null and actor_owner_email is not null)
    or (actor_kind = 'system' and actor_user_id is null and actor_owner_email is null)
  ),
  constraint communication_email_authority_events_idempotency_key
    unique (organization_id, idempotency_key)
);

create index communication_email_authority_events_organization_time_idx
  on public.communication_email_authority_events (organization_id, occurred_at desc, id desc);

create index communication_email_authority_events_target_idx
  on public.communication_email_authority_events (
    organization_id, target_type, target_id, occurred_at desc, id desc
  );

create or replace function private.validate_communication_email_sender()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  sender_domain public.communication_email_domains;
  membership_status text;
begin
  select * into sender_domain
  from public.communication_email_domains
  where organization_id = new.organization_id and id = new.domain_id;

  if not found or sender_domain.purpose <> 'sending' or sender_domain.lifecycle_state = 'removed' then
    raise exception 'A sender requires a live sending domain in the same organization.'
      using errcode = 'foreign_key_violation';
  end if;

  if split_part(new.email_address, '@', 2) <> sender_domain.domain_name then
    raise exception 'The sender address must use its sending domain.' using errcode = 'check_violation';
  end if;

  if new.assigned_user_id is not null then
    select status into membership_status
    from public.organization_members
    where organization_id = new.organization_id and user_id = new.assigned_user_id;

    if membership_status is distinct from 'active' and new.lifecycle_state = 'enabled' then
      raise exception 'An enabled assigned sender requires an active organization member.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.validate_communication_email_sender()
  from public, anon, authenticated, service_role;

create trigger communication_email_senders_validate
before insert or update on public.communication_email_senders
for each row execute function private.validate_communication_email_sender();

create trigger communication_email_domains_set_updated_at
before update on public.communication_email_domains
for each row execute function public.set_updated_at();

create trigger communication_email_senders_set_updated_at
before update on public.communication_email_senders
for each row execute function public.set_updated_at();

alter table public.communication_email_domains enable row level security;
alter table public.communication_email_senders enable row level security;
alter table public.communication_email_authority_events enable row level security;

create policy "connection managers can view email domains"
on public.communication_email_domains for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.manage_connections')
);

create policy "authorized members can view email senders"
on public.communication_email_senders for select to authenticated
using (
  private.is_organization_member(organization_id)
  and (
    private.has_permission(organization_id, 'conversations.manage_connections')
    or private.has_permission(organization_id, 'conversations.send')
  )
);

create policy "connection managers can view email authority history"
on public.communication_email_authority_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.manage_connections')
);

revoke all on public.communication_email_domains, public.communication_email_senders,
  public.communication_email_authority_events from anon, authenticated;

grant select on public.communication_email_domains, public.communication_email_senders,
  public.communication_email_authority_events to authenticated;

grant select, insert, update, delete on public.communication_email_domains,
  public.communication_email_senders to service_role;
grant select, insert on public.communication_email_authority_events to service_role;

comment on table public.communication_email_domains is
  'UCRM authority for globally claimed contractor sending and receiving domains; provider calls stay server-side.';
comment on table public.communication_email_senders is
  'Stored contractor sender identities. Eligibility also requires a verified healthy sending domain and active assignment.';
comment on table public.communication_email_authority_events is
  'Append-only audit history for domain and sender authority changes.';
