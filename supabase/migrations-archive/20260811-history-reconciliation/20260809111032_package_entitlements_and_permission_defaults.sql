-- Package entitlements and employee permission defaults.
-- Package definitions are product-controlled seed data. Contractor users can read their
-- effective context but cannot mutate package definitions or platform-owner overrides directly.

create table public.platform_packages (
  package_key text primary key check (package_key in ('starter', 'growth', 'elite')),
  display_name text not null unique check (char_length(trim(display_name)) between 2 and 80),
  sort_order smallint not null unique check (sort_order > 0),
  created_at timestamptz not null default now()
);

create table public.features (
  feature_key text primary key check (feature_key ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  description text not null check (char_length(trim(description)) between 1 and 240),
  created_at timestamptz not null default now()
);

create table public.package_features (
  package_key text not null references public.platform_packages(package_key) on delete cascade,
  feature_key text not null references public.features(feature_key) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (package_key, feature_key)
);

create index package_features_feature_key_idx on public.package_features(feature_key);

create table public.package_limits (
  package_key text not null references public.platform_packages(package_key) on delete cascade,
  limit_key text not null check (limit_key = 'employee_seats'),
  limit_value integer,
  is_unlimited boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (package_key, limit_key),
  constraint package_limits_value_state_check check (
    (is_unlimited and limit_value is null)
    or (not is_unlimited and limit_value is not null and limit_value >= 0)
  )
);

insert into public.platform_packages (package_key, display_name, sort_order)
values
  ('starter', 'Starter', 1),
  ('growth', 'Growth', 2),
  ('elite', 'Elite', 3)
on conflict (package_key) do nothing;

insert into public.features (feature_key, description)
values
  ('core.dashboard', 'Dashboard and workspace overview'),
  ('core.customers_properties', 'Customers and properties'),
  ('core.requests_assessments', 'Requests and assessments'),
  ('core.quotes', 'Quotes and proposals'),
  ('core.jobs', 'Jobs and work records'),
  ('core.schedule', 'Visits and schedule'),
  ('core.invoices_payments', 'Invoices and payments'),
  ('core.team', 'Team and employee management'),
  ('sales.pipeline', 'Sales pipeline and opportunities'),
  ('communications.inbox', 'Unified inbox'),
  ('portal.client', 'Customer-facing portal'),
  ('automation.workflows', 'Workflow automations'),
  ('reporting.advanced', 'Advanced reporting'),
  ('growth.reputation', 'Reputation and growth tools'),
  ('dispatch.advanced', 'Advanced dispatch and routing'),
  ('integrations.api', 'API and integrations')
on conflict (feature_key) do nothing;

insert into public.package_features (package_key, feature_key)
values
  ('starter', 'core.dashboard'),
  ('starter', 'core.customers_properties'),
  ('starter', 'core.requests_assessments'),
  ('starter', 'core.quotes'),
  ('starter', 'core.jobs'),
  ('starter', 'core.schedule'),
  ('starter', 'core.invoices_payments'),
  ('starter', 'core.team'),
  ('growth', 'core.dashboard'),
  ('growth', 'core.customers_properties'),
  ('growth', 'core.requests_assessments'),
  ('growth', 'core.quotes'),
  ('growth', 'core.jobs'),
  ('growth', 'core.schedule'),
  ('growth', 'core.invoices_payments'),
  ('growth', 'core.team'),
  ('growth', 'sales.pipeline'),
  ('growth', 'communications.inbox'),
  ('growth', 'portal.client'),
  ('growth', 'automation.workflows'),
  ('growth', 'reporting.advanced'),
  ('elite', 'core.dashboard'),
  ('elite', 'core.customers_properties'),
  ('elite', 'core.requests_assessments'),
  ('elite', 'core.quotes'),
  ('elite', 'core.jobs'),
  ('elite', 'core.schedule'),
  ('elite', 'core.invoices_payments'),
  ('elite', 'core.team'),
  ('elite', 'sales.pipeline'),
  ('elite', 'communications.inbox'),
  ('elite', 'portal.client'),
  ('elite', 'automation.workflows'),
  ('elite', 'reporting.advanced'),
  ('elite', 'growth.reputation'),
  ('elite', 'dispatch.advanced'),
  ('elite', 'integrations.api')
on conflict (package_key, feature_key) do nothing;

-- Initial seat defaults follow the approved matrix and ContractorOs reference values.
insert into public.package_limits (package_key, limit_key, limit_value, is_unlimited)
values
  ('starter', 'employee_seats', 3, false),
  ('growth', 'employee_seats', 10, false),
  ('elite', 'employee_seats', 50, false)
on conflict (package_key, limit_key) do nothing;

alter table public.organizations
  add column package_key text not null default 'starter'
    references public.platform_packages(package_key),
  add column scheduled_package_key text
    references public.platform_packages(package_key),
  add column scheduled_package_effective_at timestamptz,
  add constraint organizations_scheduled_package_state_check check (
    (scheduled_package_key is null and scheduled_package_effective_at is null)
    or (scheduled_package_key is not null and scheduled_package_effective_at is not null)
  );

create table public.organization_feature_overrides (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  feature_key text not null references public.features(feature_key) on delete cascade,
  override_state text not null check (override_state in ('on', 'off')),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, feature_key),
  constraint organization_feature_overrides_window_check check (
    expires_at is null or expires_at > starts_at
  )
);

create index organization_feature_overrides_active_idx
  on public.organization_feature_overrides(organization_id, feature_key, starts_at, expires_at);

create table public.organization_limit_overrides (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  limit_key text not null check (limit_key = 'employee_seats'),
  limit_value integer,
  is_unlimited boolean not null default false,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, limit_key),
  constraint organization_limit_overrides_value_state_check check (
    (is_unlimited and limit_value is null)
    or (not is_unlimited and limit_value is not null and limit_value >= 0)
  ),
  constraint organization_limit_overrides_window_check check (
    expires_at is null or expires_at > starts_at
  )
);

create index organization_limit_overrides_active_idx
  on public.organization_limit_overrides(organization_id, limit_key, starts_at, expires_at);

create table public.organization_member_permission_overrides (
  organization_id uuid not null,
  user_id uuid not null,
  permission_key text not null references public.permissions(key) on delete cascade,
  override_state text not null check (override_state in ('grant', 'deny')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id, permission_key),
  constraint organization_member_permission_overrides_member_fk
    foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade
);

create index organization_member_permission_overrides_user_idx
  on public.organization_member_permission_overrides(organization_id, user_id);

create table public.access_audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_kind text not null check (actor_kind in ('platform_owner', 'contractor_user', 'system')),
  actor_user_id uuid,
  actor_owner_email text,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_type text not null check (target_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_key text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now(),
  constraint access_audit_events_actor_check check (
    (actor_kind = 'contractor_user' and actor_user_id is not null and actor_owner_email is null)
    or (actor_kind = 'platform_owner' and actor_user_id is null and actor_owner_email is not null)
    or (actor_kind = 'system' and actor_user_id is null and actor_owner_email is null)
  )
);

create index access_audit_events_organization_created_idx
  on public.access_audit_events(organization_id, created_at desc);

create index access_audit_events_target_idx
  on public.access_audit_events(organization_id, target_type, target_key, created_at desc);

create trigger organization_feature_overrides_set_updated_at
before update on public.organization_feature_overrides
for each row execute function public.set_updated_at();

create trigger organization_limit_overrides_set_updated_at
before update on public.organization_limit_overrides
for each row execute function public.set_updated_at();

create trigger organization_member_permission_overrides_set_updated_at
before update on public.organization_member_permission_overrides
for each row execute function public.set_updated_at();

create or replace function private.is_organization_admin(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.organization_members as membership
    join public.organizations as organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.role in ('owner', 'admin')
      and organization.lifecycle_status = 'active'
  );
$$;

revoke all on function private.is_organization_admin(uuid) from public;
grant execute on function private.is_organization_admin(uuid) to authenticated;

alter table public.platform_packages enable row level security;
alter table public.features enable row level security;
alter table public.package_features enable row level security;
alter table public.package_limits enable row level security;
alter table public.organization_feature_overrides enable row level security;
alter table public.organization_limit_overrides enable row level security;
alter table public.organization_member_permission_overrides enable row level security;
alter table public.access_audit_events enable row level security;

create policy "authenticated users can view platform packages"
on public.platform_packages for select to authenticated
using (true);

create policy "authenticated users can view features"
on public.features for select to authenticated
using (true);

create policy "authenticated users can view package features"
on public.package_features for select to authenticated
using (true);

create policy "authenticated users can view package limits"
on public.package_limits for select to authenticated
using (true);

create policy "members can view organization feature overrides"
on public.organization_feature_overrides for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view organization limit overrides"
on public.organization_limit_overrides for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view their permission overrides"
on public.organization_member_permission_overrides for select to authenticated
using (
  private.is_organization_admin(organization_id)
  or (
    user_id = (select auth.uid())
    and private.is_organization_member(organization_id)
  )
);

create policy "organization admins can create permission overrides"
on public.organization_member_permission_overrides for insert to authenticated
with check (private.is_organization_admin(organization_id));

create policy "organization admins can update permission overrides"
on public.organization_member_permission_overrides for update to authenticated
using (private.is_organization_admin(organization_id))
with check (private.is_organization_admin(organization_id));

create policy "organization admins can delete permission overrides"
on public.organization_member_permission_overrides for delete to authenticated
using (private.is_organization_admin(organization_id));

create policy "organization members can append access audit events"
on public.access_audit_events for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and actor_kind = 'contractor_user'
  and actor_user_id = (select auth.uid())
  and actor_owner_email is null
);

create policy "organization admins can view access audit events"
on public.access_audit_events for select to authenticated
using (private.is_organization_admin(organization_id));

revoke all on public.platform_packages, public.features, public.package_features,
  public.package_limits, public.organization_feature_overrides,
  public.organization_limit_overrides, public.organization_member_permission_overrides,
  public.access_audit_events from anon;

revoke all on public.platform_packages, public.features, public.package_features,
  public.package_limits, public.organization_feature_overrides,
  public.organization_limit_overrides, public.organization_member_permission_overrides,
  public.access_audit_events from authenticated;

grant select on public.platform_packages, public.features, public.package_features,
  public.package_limits to authenticated;
grant select on public.organization_feature_overrides, public.organization_limit_overrides
  to authenticated;
grant select, insert, update, delete on public.organization_member_permission_overrides
  to authenticated;
grant select, insert on public.access_audit_events to authenticated;
