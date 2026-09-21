-- Platform-wide operational foundation: extends the existing owner audit log with a
-- correlation id and true immutability, then adds a durable retry/failure tracker
-- ("Operations" queue), in-app owner notifications, and a durable outbox for emails
-- that must survive a provider outage.
--
-- public.platform_owner_audit_events already existed (package publish/edit/retire
-- history from 20260810103725/20260811082825) -- it is extended here, not recreated.
-- The new tables are generic (target_kind + target_id) because failures span
-- onboarding applications, organizations, and platform-wide state, and the Operations
-- screen needs one query across all of them rather than a UNION of many domain tables.

alter table public.platform_owner_audit_events
  add column correlation_id uuid not null default gen_random_uuid();

create index platform_owner_audit_events_correlation_idx
  on public.platform_owner_audit_events (correlation_id, created_at);

-- The table's own migration intended select/insert-only for service_role, but Supabase's
-- default schema privileges still leave update/delete usable unless a trigger blocks them
-- (the same reason every other "immutable" history table in this codebase enforces it with
-- a trigger, e.g. organization_payment_confirmations). This closes that gap.
create or replace function private.prevent_platform_history_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'This platform history record is immutable.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_platform_history_mutation() from public;

create trigger platform_owner_audit_events_immutable
before update or delete on public.platform_owner_audit_events
for each row execute function private.prevent_platform_history_mutation();

-- One mutable row per operation instance (operation_type + idempotency_key), updated in
-- place across retries rather than appended -- the same "durable retry anchor" pattern
-- already used by platform_onboarding_application_provisions. This is the backbone of the
-- global Operations screen: a row only exists here once something has actually failed.
create table public.platform_operation_attempts (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null default gen_random_uuid(),
  operation_type text not null check (operation_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_kind text not null check (target_kind in ('onboarding_application', 'organization', 'platform')),
  target_id uuid,
  idempotency_key text not null check (char_length(trim(idempotency_key)) between 1 and 200),
  status text not null default 'pending' check (
    status in ('pending', 'retrying', 'succeeded', 'acknowledged', 'manually_resolved')
  ),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  next_retry_at timestamptz,
  acknowledged_at timestamptz,
  acknowledged_by_owner_email text,
  resolved_at timestamptz,
  resolved_by_owner_email text,
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_operation_attempts_target_check check (
    (target_kind = 'platform' and target_id is null)
    or (target_kind <> 'platform' and target_id is not null)
  ),
  constraint platform_operation_attempts_resolved_check check (
    (status = 'manually_resolved')
    = (resolved_at is not null and resolved_by_owner_email is not null and resolution_note is not null)
  )
);

create unique index platform_operation_attempts_operation_key_idx
  on public.platform_operation_attempts (operation_type, idempotency_key);
create index platform_operation_attempts_open_idx
  on public.platform_operation_attempts (status, updated_at desc)
  where status <> 'succeeded';
create index platform_operation_attempts_target_idx
  on public.platform_operation_attempts (target_kind, target_id);

create trigger platform_operation_attempts_set_updated_at
before update on public.platform_operation_attempts
for each row execute function public.set_updated_at();

alter table public.platform_operation_attempts enable row level security;

revoke all on public.platform_operation_attempts from anon, authenticated;
grant select, insert, update on public.platform_operation_attempts to service_role;

-- In-app owner notifications (header bell). Append-only except for read_at: the trigger
-- below rejects any update that changes another column, so a notification's content can
-- never quietly drift after the owner has seen it.
create table public.platform_owner_notifications (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid,
  kind text not null check (kind ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  severity text not null default 'info' check (severity in ('info', 'attention', 'urgent')),
  title text not null check (char_length(trim(title)) between 1 and 200),
  body text,
  target_kind text not null check (
    target_kind in ('onboarding_application', 'organization', 'operation_attempt', 'platform')
  ),
  target_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint platform_owner_notifications_target_check check (
    (target_kind = 'platform' and target_id is null)
    or (target_kind <> 'platform' and target_id is not null)
  )
);

create index platform_owner_notifications_unread_idx
  on public.platform_owner_notifications (read_at, created_at desc)
  where read_at is null;
create index platform_owner_notifications_target_idx
  on public.platform_owner_notifications (target_kind, target_id);

create or replace function private.restrict_platform_notification_update()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.id <> old.id
    or new.correlation_id is distinct from old.correlation_id
    or new.kind <> old.kind
    or new.severity <> old.severity
    or new.title <> old.title
    or new.body is distinct from old.body
    or new.target_kind <> old.target_kind
    or new.target_id is distinct from old.target_id
    or new.created_at <> old.created_at
  then
    raise exception 'Only the read state of a notification can change.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function private.restrict_platform_notification_update() from public;

create trigger platform_owner_notifications_restrict_update
before update on public.platform_owner_notifications
for each row execute function private.restrict_platform_notification_update();

create trigger platform_owner_notifications_prevent_delete
before delete on public.platform_owner_notifications
for each row execute function private.prevent_platform_history_mutation();

alter table public.platform_owner_notifications enable row level security;

revoke all on public.platform_owner_notifications from anon, authenticated;
grant select, insert, update on public.platform_owner_notifications to service_role;

-- Durable outbox for emails that must not be silently lost to a Brevo outage. The full
-- rendered subject/html/text is stored in payload at enqueue time, so a later retry from
-- the Operations screen re-sends the exact same content without re-rendering anything.
create table public.platform_outbox_deliveries (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null default gen_random_uuid(),
  channel text not null default 'email' check (channel in ('email')),
  template_key text not null check (template_key ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_kind text not null check (target_kind in ('onboarding_application', 'organization', 'platform')),
  target_id uuid,
  idempotency_key text not null check (char_length(trim(idempotency_key)) between 1 and 200),
  recipient_email text not null check (position('@' in recipient_email) > 1),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_outbox_deliveries_target_check check (
    (target_kind = 'platform' and target_id is null)
    or (target_kind <> 'platform' and target_id is not null)
  ),
  constraint platform_outbox_deliveries_sent_check check (
    (status = 'sent') = (sent_at is not null)
  )
);

create unique index platform_outbox_deliveries_idempotency_idx
  on public.platform_outbox_deliveries (idempotency_key);
create index platform_outbox_deliveries_pending_idx
  on public.platform_outbox_deliveries (status, next_attempt_at)
  where status in ('pending', 'failed');

create trigger platform_outbox_deliveries_set_updated_at
before update on public.platform_outbox_deliveries
for each row execute function public.set_updated_at();

alter table public.platform_outbox_deliveries enable row level security;

revoke all on public.platform_outbox_deliveries from anon, authenticated;
grant select, insert, update on public.platform_outbox_deliveries to service_role;

-- Atomic state-transition functions: each existing owner write below now happens in the
-- same transaction as its matching audit event (reusing the existing
-- actor_owner_email/event_type/target_type/target_key/before_state/after_state shape), so a
-- correction, payment confirmation, or not-proceeding decision can never change state
-- without leaving a matching history row.

create or replace function public.correct_onboarding_application(
  target_application_id uuid,
  actor_email text,
  correction_reason text,
  new_business_name text,
  new_main_contact_name text,
  new_main_contact_email text,
  new_main_contact_phone text,
  new_initial_administrator_name text,
  new_initial_administrator_email text,
  new_trade text,
  new_city_country text,
  new_time_zone text,
  new_note text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  current record;
  before_state jsonb;
  after_state jsonb;
begin
  select stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
    initial_administrator_name, initial_administrator_email, trade, city_country, time_zone, note
  into current
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if current.stage not in ('new', 'awaiting_payment', 'payment_confirmed', 'needs_attention') then
    raise exception 'This application can no longer be corrected.' using errcode = 'check_violation';
  end if;

  before_state := jsonb_build_object(
    'business_name', current.business_name,
    'main_contact_name', current.main_contact_name,
    'main_contact_email', current.main_contact_email,
    'main_contact_phone', current.main_contact_phone,
    'initial_administrator_name', current.initial_administrator_name,
    'initial_administrator_email', current.initial_administrator_email,
    'trade', current.trade,
    'city_country', current.city_country,
    'time_zone', current.time_zone,
    'note', current.note
  );
  after_state := jsonb_build_object(
    'business_name', new_business_name,
    'main_contact_name', new_main_contact_name,
    'main_contact_email', new_main_contact_email,
    'main_contact_phone', new_main_contact_phone,
    'initial_administrator_name', new_initial_administrator_name,
    'initial_administrator_email', new_initial_administrator_email,
    'trade', new_trade,
    'city_country', new_city_country,
    'time_zone', new_time_zone,
    'note', new_note
  );

  update public.platform_onboarding_applications
  set business_name = new_business_name,
    main_contact_name = new_main_contact_name,
    main_contact_email = new_main_contact_email,
    main_contact_phone = new_main_contact_phone,
    initial_administrator_name = new_initial_administrator_name,
    initial_administrator_email = new_initial_administrator_email,
    trade = new_trade,
    city_country = new_city_country,
    time_zone = new_time_zone,
    note = new_note
  where id = target_application_id;

  insert into public.platform_onboarding_application_corrections (
    application_id, actor_owner_email, reason, before_state, after_state
  ) values (
    target_application_id, actor_email, correction_reason, before_state, after_state
  );

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor_email, 'onboarding_application.corrected', 'onboarding_application',
    target_application_id::text, before_state, after_state || jsonb_build_object('reason', correction_reason)
  );
end;
$$;

revoke all on function public.correct_onboarding_application(
  uuid, text, text, text, text, text, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.correct_onboarding_application(
  uuid, text, text, text, text, text, text, text, text, text, text, text, text
) to service_role;

create or replace function public.confirm_onboarding_application_payment(
  target_application_id uuid,
  actor_email text,
  amount_usd_cents integer,
  private_reference text,
  mismatch_reason text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
  app_package_version_id uuid;
begin
  select stage, package_version_id into app_stage, app_package_version_id
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage not in ('new', 'awaiting_payment', 'needs_attention') then
    raise exception 'This application can no longer be confirmed for payment.' using errcode = 'check_violation';
  end if;

  insert into public.platform_onboarding_application_payment_confirmations (
    application_id, actor_owner_email, amount_usd_cents, private_reference,
    package_version_id, mismatch_reason
  ) values (
    target_application_id, actor_email, amount_usd_cents, private_reference,
    app_package_version_id, mismatch_reason
  );

  update public.platform_onboarding_applications
  set stage = 'payment_confirmed'
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    actor_email, 'onboarding_application.payment_confirmed', 'onboarding_application',
    target_application_id::text,
    jsonb_build_object('amount_usd_cents', amount_usd_cents, 'mismatch_reason', mismatch_reason)
  );
end;
$$;

revoke all on function public.confirm_onboarding_application_payment(uuid, text, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.confirm_onboarding_application_payment(uuid, text, integer, text, text)
  to service_role;

create or replace function public.mark_onboarding_application_not_proceeding(
  target_application_id uuid,
  actor_email text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
begin
  select stage into app_stage
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage not in ('new', 'awaiting_payment', 'needs_attention') then
    raise exception 'Only an unpaid application can be marked not proceeding.' using errcode = 'check_violation';
  end if;

  update public.platform_onboarding_applications
  set stage = 'not_proceeding', not_proceeding_at = now()
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key
  ) values (
    actor_email, 'onboarding_application.not_proceeding', 'onboarding_application', target_application_id::text
  );
end;
$$;

revoke all on function public.mark_onboarding_application_not_proceeding(uuid, text)
  from public, anon, authenticated;
grant execute on function public.mark_onboarding_application_not_proceeding(uuid, text)
  to service_role;

-- Extend provisioning with an actor-attributed audit event in the same transaction as the
-- organization it creates. Adding a parameter requires dropping the old signature first;
-- the new parameter defaults to null but the function requires a real value at call time
-- (platform_owner_audit_events.actor_owner_email is not nullable), so a caller that forgets
-- to pass it fails with a clear message instead of a raw constraint violation.
drop function if exists public.provision_organization_from_application(uuid, uuid, text, text, uuid, text);

create or replace function public.provision_organization_from_application(
  target_application_id uuid,
  target_organization_id uuid,
  target_organization_name text,
  target_slug text,
  target_administrator_user_id uuid,
  target_administrator_role text default 'owner',
  target_actor_owner_email text default null
)
returns uuid
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
  app_package_version_id uuid;
  app_time_zone text;
  version_status text;
  package_status text;
  payment record;
  paid_through date;
begin
  if target_organization_name is null or char_length(trim(target_organization_name)) = 0 then
    raise exception 'An organization name is required for provisioning.' using errcode = 'check_violation';
  end if;
  if target_slug is null or char_length(trim(target_slug)) = 0 then
    raise exception 'An organization slug is required for provisioning.' using errcode = 'check_violation';
  end if;
  if target_actor_owner_email is null or char_length(trim(target_actor_owner_email)) = 0 then
    raise exception 'An acting owner email is required for provisioning.' using errcode = 'check_violation';
  end if;

  select stage, package_version_id, time_zone
  into app_stage, app_package_version_id, app_time_zone
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage not in ('payment_confirmed', 'needs_attention') then
    raise exception 'This application is not ready for provisioning.' using errcode = 'check_violation';
  end if;

  select version.status, package.status
  into version_status, package_status
  from public.platform_package_versions as version
  join public.platform_packages as package on package.package_id = version.package_id
  where version.id = app_package_version_id;

  if version_status is null or package_status is null then
    raise exception 'The activated package version does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if version_status = 'draft' or package_status = 'draft' then
    raise exception 'The activated package version was never published.' using errcode = 'check_violation';
  end if;

  select amount_usd_cents, currency, private_reference, confirmed_at, mismatch_reason
  into payment
  from public.platform_onboarding_application_payment_confirmations
  where application_id = target_application_id;

  if not found then
    raise exception 'Payment must be confirmed before provisioning.' using errcode = 'check_violation';
  end if;

  paid_through := (payment.confirmed_at::date + interval '1 month')::date;

  insert into public.organizations (id, name, slug, lifecycle_status)
  values (target_organization_id, trim(target_organization_name), target_slug, 'active');

  insert into public.organization_package_assignments (
    organization_id, package_version_id, assignment_source, reason
  ) values (
    target_organization_id, app_package_version_id, 'provisioning',
    'Initial provisioning from paid onboarding application.'
  );

  insert into public.organization_billing_accounts (
    organization_id, paid_through_date, paid_through_source
  ) values (
    target_organization_id, paid_through, 'provisioning'
  );

  insert into public.organization_payment_confirmations (
    organization_id, payment_kind, amount_usd_cents, currency,
    private_reference, confirmed_at, paid_through_date, mismatch_reason
  ) values (
    target_organization_id, 'initial', payment.amount_usd_cents, payment.currency,
    payment.private_reference, payment.confirmed_at, paid_through, payment.mismatch_reason
  );

  update public.organization_settings
  set timezone = coalesce(nullif(trim(app_time_zone), ''), timezone)
  where organization_id = target_organization_id;

  insert into public.organization_members (organization_id, user_id, role)
  values (target_organization_id, target_administrator_user_id, target_administrator_role);

  update public.platform_onboarding_applications
  set stage = 'account_created'
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    target_actor_owner_email, 'onboarding_application.provisioned', 'organization',
    target_organization_id::text, jsonb_build_object('application_id', target_application_id)
  );

  return target_organization_id;
end;
$$;

revoke all on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, text)
  to service_role;
