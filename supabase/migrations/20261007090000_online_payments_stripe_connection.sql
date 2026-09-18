-- Online payments Part 2: the contractor's own Stripe connection and their payment settings.
--
-- Each business connects its OWN Stripe account by pasting one restricted key (see
-- docs/online-payments-behavior-contract.md §1–2). UCRM creates the webhook endpoint inside that account and
-- keeps the key and the endpoint's signing secret as AES-256-GCM ciphertext only; plaintext never enters
-- Postgres. The connection table is server-owned (service role only) so no browser, staff member or Jafar
-- read can ever serialize a secret. Nothing here takes a payment -- Part 3 owns Checkout and the ledger.

-- 1. Who may connect Stripe ----------------------------------------------------------------------------------

insert into public.permissions (key, description)
values ('settings.payments.manage', 'Connect Stripe and manage online payment settings')
on conflict (key) do update set description = excluded.description;

-- Owner and admin only, per the contract: connecting the account money flows into is not delegated.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'settings.payments.manage'),
  ('admin', 'settings.payments.manage')
on conflict (role, permission_key) do nothing;

-- 2. The encrypted connection ---------------------------------------------------------------------------------

-- One row per organization. The row id is regenerated on every connect or key replacement and is the path
-- segment of the webhook URL, so an endpoint left over from an older connection can never be verified
-- against the current signing secret.
create table public.payment_stripe_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  stripe_account_id text not null,
  account_display_name text,
  livemode boolean not null,
  -- Last four characters of the pasted key so the contractor can tell which Stripe key is in use.
  api_key_last4 text not null,
  webhook_endpoint_id text not null,
  encryption_key_id text not null,
  api_key_nonce bytea not null,
  api_key_ciphertext bytea not null,
  api_key_tag bytea not null,
  webhook_secret_nonce bytea not null,
  webhook_secret_ciphertext bytea not null,
  webhook_secret_tag bytea not null,
  connected_by uuid references auth.users(id) on delete set null,
  connected_at timestamptz not null default now(),
  last_checked_at timestamptz not null default now(),
  -- 'ok' or a sanitized reason code; never a provider message or a secret.
  last_check_status text not null default 'ok',
  last_event_received_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint payment_stripe_connections_organization_key unique (organization_id),
  constraint payment_stripe_connections_account_id_check
    check (stripe_account_id ~ '^acct_[A-Za-z0-9]{1,64}$'),
  constraint payment_stripe_connections_endpoint_id_check
    check (webhook_endpoint_id ~ '^we_[A-Za-z0-9]{1,64}$'),
  constraint payment_stripe_connections_last4_check check (api_key_last4 ~ '^[A-Za-z0-9]{4}$'),
  constraint payment_stripe_connections_display_name_check
    check (account_display_name is null or char_length(account_display_name) <= 200),
  constraint payment_stripe_connections_key_id_check
    check (encryption_key_id ~ '^[A-Za-z0-9._-]{1,64}$'),
  constraint payment_stripe_connections_nonce_check
    check (octet_length(api_key_nonce) = 12 and octet_length(webhook_secret_nonce) = 12),
  constraint payment_stripe_connections_tag_check
    check (octet_length(api_key_tag) = 16 and octet_length(webhook_secret_tag) = 16),
  constraint payment_stripe_connections_ciphertext_check
    check (octet_length(api_key_ciphertext) > 0 and octet_length(webhook_secret_ciphertext) > 0),
  constraint payment_stripe_connections_check_status_check
    check (last_check_status in (
      'ok', 'key_rejected', 'permission_missing', 'account_unavailable', 'webhook_missing'
    ))
);

create index payment_stripe_connections_connected_by_idx
  on public.payment_stripe_connections (connected_by);

alter table public.payment_stripe_connections enable row level security;

revoke all on table public.payment_stripe_connections from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.payment_stripe_connections to service_role;

comment on table public.payment_stripe_connections is
  'Server-owned Stripe connection. AES-256-GCM ciphertext only; plaintext keys must never enter Postgres.';

-- 3. Payment settings the contractor controls ----------------------------------------------------------------

alter table public.organization_settings
  add column online_invoice_payments_enabled boolean not null default true,
  add column online_deposit_payments_enabled boolean not null default true,
  add column online_tips_enabled boolean not null default false,
  add column online_receipt_email_enabled boolean not null default true,
  add column payment_settings_revision integer not null default 1,
  add column payment_settings_updated_by uuid references auth.users(id) on delete set null,
  add column payment_settings_updated_at timestamptz;

create index organization_settings_payment_settings_updated_by_idx
  on public.organization_settings (payment_settings_updated_by);

alter table public.organization_settings_audit drop constraint organization_settings_audit_section_check;
alter table public.organization_settings_audit add constraint organization_settings_audit_section_check
  check (section = any (array[
    'profile', 'branding', 'hours', 'pipeline', 'taxes',
    'quote_terms', 'quote_representative', 'quote_target_margin', 'quote_signature_policy',
    'invoice_terms', 'payment_settings', 'stripe_connection'
  ]));

create or replace function public.set_organization_payment_settings(
  target_organization_id uuid,
  expected_revision integer,
  new_invoice_payments boolean,
  new_deposit_payments boolean,
  new_tips boolean,
  new_receipt_email boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  editor_name text;
  changed text[] := array[]::text[];
begin
  if not private.has_permission(target_organization_id, 'settings.payments.manage') then
    raise exception 'You do not have access to manage online payments.' using errcode = 'insufficient_privilege';
  end if;

  if new_invoice_payments is null or new_deposit_payments is null or new_tips is null
     or new_receipt_email is null then
    raise exception 'Every payment setting needs a value.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.payment_settings_revision then
    select profile.full_name into editor_name
    from public.profiles as profile
    where profile.id = settings_row.payment_settings_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(settings_row.payment_settings_updated_at, settings_row.updated_at)
    );
  end if;

  if new_invoice_payments is distinct from settings_row.online_invoice_payments_enabled then
    changed := array_append(changed, 'online_invoice_payments_enabled');
  end if;
  if new_deposit_payments is distinct from settings_row.online_deposit_payments_enabled then
    changed := array_append(changed, 'online_deposit_payments_enabled');
  end if;
  if new_tips is distinct from settings_row.online_tips_enabled then
    changed := array_append(changed, 'online_tips_enabled');
  end if;
  if new_receipt_email is distinct from settings_row.online_receipt_email_enabled then
    changed := array_append(changed, 'online_receipt_email_enabled');
  end if;

  update public.organization_settings
  set online_invoice_payments_enabled = new_invoice_payments,
      online_deposit_payments_enabled = new_deposit_payments,
      online_tips_enabled = new_tips,
      online_receipt_email_enabled = new_receipt_email,
      payment_settings_revision = payment_settings_revision + 1,
      payment_settings_updated_by = (select auth.uid()),
      payment_settings_updated_at = now()
  where organization_id = target_organization_id
  returning payment_settings_revision into settings_row.payment_settings_revision;

  if cardinality(changed) > 0 then
    insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
    values (target_organization_id, 'payment_settings', changed, (select auth.uid()));
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'payment_settings_revision', settings_row.payment_settings_revision
  );
end;
$$;

revoke all on function public.set_organization_payment_settings(uuid, integer, boolean, boolean, boolean, boolean) from public;
revoke execute on function public.set_organization_payment_settings(uuid, integer, boolean, boolean, boolean, boolean) from anon;
grant execute on function public.set_organization_payment_settings(uuid, integer, boolean, boolean, boolean, boolean) to authenticated;
