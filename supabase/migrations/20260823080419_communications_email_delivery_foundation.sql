-- Communications Part 1: tenant-scoped operational-email delivery foundation.
-- This deliberately creates no contractor-facing sender or compose UI. Provider work can only use
-- rows claimed by a server-side worker, and a worker must never hold a database lock during HTTP.

insert into public.permissions (key, description)
values
  ('conversations.view_assigned', 'See conversations assigned to, followed by, or mentioning the member'),
  ('conversations.view_team', 'See all organization conversations'),
  ('conversations.send', 'Send customer messages'),
  ('conversations.manage_assignment', 'Assign and follow conversations'),
  ('conversations.permanently_delete', 'Permanently delete conversations with an audit record'),
  ('conversations.manage_connections', 'Manage communications channel connections')
on conflict (key) do update set description = excluded.description;

insert into public.features (feature_key, description)
values ('communications', 'Shared customer conversations and approved communication channels')
on conflict (feature_key) do update set description = excluded.description;

create table public.communication_delivery_intents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  client_contact_method_id uuid not null,
  channel text not null default 'email' check (channel = 'email'),
  direction text not null default 'outbound' check (direction = 'outbound'),
  logical_send_key text not null check (char_length(trim(logical_send_key)) between 1 and 200),
  recipient_email text not null check (position('@' in recipient_email) > 1),
  subject text not null check (char_length(trim(subject)) between 1 and 998),
  html_content text not null check (char_length(trim(html_content)) > 0),
  text_content text not null check (char_length(trim(text_content)) > 0),
  status text not null default 'queued' check (status in ('queued', 'claimed', 'submitted', 'failed', 'cancelled', 'submission_unknown')),
  provider_message_id text,
  accepted_at timestamptz,
  failure_code text,
  failure_message text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_delivery_intents_client_fk
    foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete cascade,
  constraint communication_delivery_intents_contact_method_fk
    foreign key (organization_id, client_contact_method_id)
    references public.client_contact_methods(organization_id, id) on delete restrict,
  constraint communication_delivery_intents_unique_logical_send unique (organization_id, logical_send_key),
  constraint communication_delivery_intents_accepted_check check (
    (status = 'submitted') = (accepted_at is not null and provider_message_id is not null)
  )
);

create index communication_delivery_intents_client_created_idx
  on public.communication_delivery_intents (organization_id, client_id, created_at desc, id desc);
create unique index communication_delivery_intents_provider_message_idx
  on public.communication_delivery_intents (provider_message_id)
  where provider_message_id is not null;

create table public.communication_outbox_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  delivery_intent_id uuid not null references public.communication_delivery_intents(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'processing', 'submitted', 'failed', 'cancelled', 'submission_unknown')),
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  claim_token uuid,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_outbox_events_one_per_intent unique (delivery_intent_id),
  constraint communication_outbox_events_claim_check check (
    (status = 'processing') = (claimed_at is not null and claim_token is not null)
  )
);

create index communication_outbox_events_claim_idx
  on public.communication_outbox_events (available_at, created_at)
  where status in ('pending', 'failed');
create index communication_outbox_events_organization_status_idx
  on public.communication_outbox_events (organization_id, status, available_at);

create table public.communication_provider_callback_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'brevo' check (provider = 'brevo'),
  provider_event_key text not null check (char_length(trim(provider_event_key)) between 1 and 300),
  delivery_intent_id uuid references public.communication_delivery_intents(id) on delete set null,
  event_kind text not null check (char_length(trim(event_kind)) between 1 and 80),
  occurred_at timestamptz,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  received_at timestamptz not null default now(),
  constraint communication_provider_callback_events_dedupe unique (provider, provider_event_key)
);

create index communication_provider_callback_events_intent_idx
  on public.communication_provider_callback_events (delivery_intent_id, received_at desc)
  where delivery_intent_id is not null;

create table public.communication_email_usage_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  delivery_intent_id uuid not null references public.communication_delivery_intents(id) on delete cascade,
  recipient_count integer not null default 1 check (recipient_count > 0),
  event_kind text not null default 'provider_accepted' check (event_kind = 'provider_accepted'),
  occurred_at timestamptz not null default now(),
  constraint communication_email_usage_events_once_per_intent unique (delivery_intent_id)
);

create index communication_email_usage_events_organization_time_idx
  on public.communication_email_usage_events (organization_id, occurred_at desc, id desc);

create trigger communication_delivery_intents_set_updated_at
before update on public.communication_delivery_intents
for each row execute function public.set_updated_at();
create trigger communication_outbox_events_set_updated_at
before update on public.communication_outbox_events
for each row execute function public.set_updated_at();

-- The API never writes delivery records directly. This command gives a server endpoint one short,
-- idempotent transaction that creates the intent and its worker row together. The eligibility policy
-- is intentionally rechecked by the worker immediately before provider submission.
create or replace function public.enqueue_communication_email(
  target_organization_id uuid,
  target_client_id uuid,
  target_contact_method_id uuid,
  target_logical_send_key text,
  target_recipient_email text,
  target_subject text,
  target_html_content text,
  target_text_content text
)
returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  intent public.communication_delivery_intents;
begin
  if not private.is_organization_member(target_organization_id)
    or not private.has_permission(target_organization_id, 'conversations.send') then
    raise exception 'You do not have permission to send a customer message.' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1
    from public.client_contact_methods
    where organization_id = target_organization_id
      and id = target_contact_method_id
      and client_id = target_client_id
      and kind = 'email'
      and normalized_value = lower(trim(target_recipient_email))
  ) then
    raise exception 'The recipient email does not belong to this client.' using errcode = 'foreign_key_violation';
  end if;

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
    subject, html_content, text_content, created_by
  ) values (
    target_organization_id, target_client_id, target_contact_method_id, target_logical_send_key,
    lower(trim(target_recipient_email)), target_subject, target_html_content, target_text_content,
    (select auth.uid())
  ) on conflict (organization_id, logical_send_key) do update
    set logical_send_key = excluded.logical_send_key
  returning * into intent;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
  values (intent.organization_id, intent.id)
  on conflict (delivery_intent_id) do nothing;

  return intent;
end;
$$;

-- Claims exactly one due row. The transaction ends before an HTTP call, and SKIP LOCKED lets several
-- workers make progress without waiting on one another.
create or replace function public.claim_communication_outbox_event()
returns table (
  outbox_event_id uuid,
  delivery_intent_id uuid,
  claim_token uuid,
  recipient_email text,
  subject text,
  html_content text,
  text_content text,
  logical_send_key text
)
language sql
security definer
set search_path = pg_catalog, public
as $$
  with due as (
    select id
    from public.communication_outbox_events
    where status in ('pending', 'failed') and available_at <= now()
    order by available_at, created_at, id
    limit 1
    for update skip locked
  ), claimed as (
    update public.communication_outbox_events event
    set status = 'processing', claimed_at = now(), claim_token = gen_random_uuid(),
      attempt_count = event.attempt_count + 1, last_error = null
    from due
    where event.id = due.id
    returning event.id, event.delivery_intent_id, event.claim_token
  ), intents as (
    update public.communication_delivery_intents intent
    set status = 'claimed', failure_code = null, failure_message = null
    from claimed
    where intent.id = claimed.delivery_intent_id
    returning intent.id, intent.recipient_email, intent.subject, intent.html_content, intent.text_content,
      intent.logical_send_key
  )
  select claimed.id, claimed.delivery_intent_id, claimed.claim_token, intents.recipient_email,
    intents.subject, intents.html_content, intents.text_content, intents.logical_send_key
  from claimed join intents on intents.id = claimed.delivery_intent_id;
$$;

revoke all on function public.enqueue_communication_email(uuid, uuid, uuid, text, text, text, text, text)
  from public;
grant execute on function public.enqueue_communication_email(uuid, uuid, uuid, text, text, text, text, text)
  to authenticated;
revoke all on function public.claim_communication_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_outbox_event() to service_role;

alter table public.communication_delivery_intents enable row level security;
alter table public.communication_outbox_events enable row level security;
alter table public.communication_provider_callback_events enable row level security;
alter table public.communication_email_usage_events enable row level security;

revoke all on public.communication_delivery_intents, public.communication_outbox_events,
  public.communication_provider_callback_events, public.communication_email_usage_events
  from anon, authenticated;
grant select, insert, update on public.communication_delivery_intents to service_role;
grant select, insert, update on public.communication_outbox_events to service_role;
grant select, insert, update on public.communication_provider_callback_events to service_role;
grant select, insert on public.communication_email_usage_events to service_role;
