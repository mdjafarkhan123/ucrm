-- Communications A2 / Stage 1: make the shared delivery spine channel-safe before any SMS worker exists.
-- This migration stores durable SMS facts only. It does not configure Twilio or enable live traffic.

alter table public.communication_delivery_intents
  add column recipient_phone text,
  add column sms_sender_identity_id uuid;

alter table public.communication_delivery_intents
  alter column recipient_email drop not null,
  alter column subject drop not null,
  alter column html_content drop not null;

alter table public.communication_delivery_intents
  drop constraint communication_delivery_intents_channel_check,
  drop constraint communication_delivery_intents_recipient_email_check,
  drop constraint communication_delivery_intents_subject_check,
  drop constraint communication_delivery_intents_html_content_check,
  add constraint communication_delivery_intents_channel_check
    check (channel in ('email', 'sms')),
  add constraint communication_delivery_intents_channel_payload_check check (
    (
      channel = 'email'
      and recipient_email is not null
      and position('@' in recipient_email) > 1
      and recipient_phone is null
      and subject is not null
      and char_length(trim(subject)) between 1 and 998
      and html_content is not null
      and char_length(trim(html_content)) > 0
      and sms_sender_identity_id is null
    )
    or
    (
      channel = 'sms'
      and recipient_email is null
      and recipient_phone is not null
      and recipient_phone ~ '^\+[1-9][0-9]{7,14}$'
      and subject is null
      and html_content is null
      and sender_id is null
      and reply_alias_id is null
    )
  );

create unique index communication_delivery_intents_org_id_channel_key
  on public.communication_delivery_intents (organization_id, id, channel);

create table public.communication_sms_sender_identities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  phone_number text not null,
  display_name text,
  lifecycle_state text not null default 'pending_setup',
  allows_manual boolean not null default false,
  allows_automated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_sender_identities_org_id_key unique (organization_id, id),
  constraint communication_sms_sender_identities_phone_check
    check (phone_number ~ '^\+[1-9][0-9]{7,14}$'),
  constraint communication_sms_sender_identities_display_name_check
    check (display_name is null or char_length(trim(display_name)) between 1 and 80),
  constraint communication_sms_sender_identities_lifecycle_check
    check (lifecycle_state in ('pending_setup', 'ready', 'restricted', 'suspended', 'released')),
  constraint communication_sms_sender_identities_release_check
    check (lifecycle_state <> 'released' or (not allows_manual and not allows_automated))
);

create unique index communication_sms_sender_identities_live_phone_key
  on public.communication_sms_sender_identities (phone_number)
  where lifecycle_state <> 'released';
create index communication_sms_sender_identities_org_state_idx
  on public.communication_sms_sender_identities (organization_id, lifecycle_state, created_at, id);

alter table public.communication_delivery_intents
  add constraint communication_delivery_intents_sms_sender_fk
  foreign key (organization_id, sms_sender_identity_id)
  references public.communication_sms_sender_identities (organization_id, id) on delete restrict;
create index communication_delivery_intents_sms_sender_idx
  on public.communication_delivery_intents (organization_id, sms_sender_identity_id)
  where sms_sender_identity_id is not null;

alter table public.communication_outbox_events add column channel text;
update public.communication_outbox_events event
set channel = intent.channel
from public.communication_delivery_intents intent
where intent.id = event.delivery_intent_id;
alter table public.communication_outbox_events
  alter column channel set default 'email',
  alter column channel set not null,
  add constraint communication_outbox_events_channel_check check (channel in ('email', 'sms')),
  add constraint communication_outbox_events_intent_channel_fk
    foreign key (organization_id, delivery_intent_id, channel)
    references public.communication_delivery_intents (organization_id, id, channel) on delete cascade;

drop index public.communication_outbox_events_claim_idx;
create index communication_outbox_events_email_claim_idx
  on public.communication_outbox_events (available_at, created_at, id)
  where channel = 'email' and status in ('pending', 'failed');
create index communication_outbox_events_sms_claim_idx
  on public.communication_outbox_events (available_at, created_at, id)
  where channel = 'sms' and status in ('pending', 'failed');

alter table public.communication_provider_callback_events add column channel text;
update public.communication_provider_callback_events set channel = 'email';
alter table public.communication_provider_callback_events
  alter column channel set default 'email',
  alter column channel set not null,
  drop constraint communication_provider_callback_events_provider_check,
  add constraint communication_provider_callback_events_channel_check check (channel in ('email', 'sms')),
  add constraint communication_provider_callback_events_provider_channel_check check (
    (channel = 'email' and provider = 'brevo') or
    (channel = 'sms' and provider = 'twilio')
  ),
  add constraint communication_provider_callback_events_intent_channel_fk
    foreign key (organization_id, delivery_intent_id, channel)
    references public.communication_delivery_intents (organization_id, id, channel)
    on delete set null (delivery_intent_id);
drop index public.communication_provider_callback_events_unprocessed_idx;
create index communication_provider_callback_events_email_unprocessed_idx
  on public.communication_provider_callback_events (received_at, id)
  where channel = 'email' and processed_at is null;
create index communication_provider_callback_events_sms_unprocessed_idx
  on public.communication_provider_callback_events (received_at, id)
  where channel = 'sms' and processed_at is null;

create table public.communication_sms_message_snapshots (
  delivery_intent_id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  channel text not null default 'sms' check (channel = 'sms'),
  body text not null,
  encoding text not null,
  segment_count integer not null,
  created_at timestamptz not null default now(),
  constraint communication_sms_message_snapshots_intent_fk
    foreign key (organization_id, delivery_intent_id, channel)
    references public.communication_delivery_intents (organization_id, id, channel) on delete cascade,
  constraint communication_sms_message_snapshots_body_check
    check (char_length(body) between 1 and 1600),
  constraint communication_sms_message_snapshots_encoding_check
    check (encoding in ('gsm7', 'ucs2')),
  constraint communication_sms_message_snapshots_segments_check
    check (segment_count between 1 and 10)
);

create table public.communication_sms_submission_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  delivery_intent_id uuid not null,
  channel text not null default 'sms' check (channel = 'sms'),
  attempt_number integer not null,
  claim_token uuid not null,
  provider text not null default 'twilio',
  provider_message_id text,
  outcome text not null,
  error_code text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint communication_sms_submission_attempts_intent_fk
    foreign key (organization_id, delivery_intent_id, channel)
    references public.communication_delivery_intents (organization_id, id, channel) on delete cascade,
  constraint communication_sms_submission_attempts_one_number unique (delivery_intent_id, attempt_number),
  constraint communication_sms_submission_attempts_one_claim unique (delivery_intent_id, claim_token),
  constraint communication_sms_submission_attempts_number_check check (attempt_number > 0),
  constraint communication_sms_submission_attempts_provider_check check (provider = 'twilio'),
  constraint communication_sms_submission_attempts_outcome_check
    check (outcome in ('started', 'accepted', 'rejected', 'submission_unknown')),
  constraint communication_sms_submission_attempts_completion_check check (
    (outcome = 'started' and finished_at is null and provider_message_id is null)
    or (outcome = 'accepted' and finished_at is not null and provider_message_id is not null)
    or (outcome in ('rejected', 'submission_unknown') and finished_at is not null)
  )
);
create index communication_sms_submission_attempts_intent_created_idx
  on public.communication_sms_submission_attempts (organization_id, delivery_intent_id, started_at desc, id desc);
create unique index communication_sms_submission_attempts_provider_message_key
  on public.communication_sms_submission_attempts (provider, provider_message_id)
  where provider_message_id is not null;

create table public.communication_sms_consent_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  client_contact_method_id uuid not null,
  event_kind text not null,
  source text not null,
  source_event_key text not null,
  evidence jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  constraint communication_sms_consent_events_client_fk
    foreign key (organization_id, client_id) references public.clients(organization_id, id) on delete cascade,
  constraint communication_sms_consent_events_method_fk
    foreign key (organization_id, client_contact_method_id)
    references public.client_contact_methods(organization_id, id) on delete restrict,
  constraint communication_sms_consent_events_org_id_key unique (organization_id, id),
  constraint communication_sms_consent_events_source_key unique (organization_id, source, source_event_key),
  constraint communication_sms_consent_events_kind_check
    check (event_kind in ('opt_in', 'opt_out', 'help_requested')),
  constraint communication_sms_consent_events_source_check
    check (source in ('client_reply', 'staff', 'import', 'system')),
  constraint communication_sms_consent_events_source_key_check
    check (char_length(trim(source_event_key)) between 1 and 300),
  constraint communication_sms_consent_events_evidence_check check (jsonb_typeof(evidence) = 'object')
);
create unique index client_contact_methods_org_client_id_key
  on public.client_contact_methods (organization_id, client_id, id);
alter table public.communication_sms_consent_events
  drop constraint communication_sms_consent_events_method_fk,
  add constraint communication_sms_consent_events_method_fk
    foreign key (organization_id, client_id, client_contact_method_id)
    references public.client_contact_methods (organization_id, client_id, id) on delete restrict;
create index communication_sms_consent_events_projection_idx
  on public.communication_sms_consent_events
    (organization_id, client_contact_method_id, occurred_at desc, received_at desc, id desc);

create table public.communication_sms_consent_state (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_contact_method_id uuid not null,
  client_id uuid not null,
  state text not null,
  source_event_id uuid not null,
  effective_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (organization_id, client_contact_method_id),
  constraint communication_sms_consent_state_client_fk
    foreign key (organization_id, client_id) references public.clients(organization_id, id) on delete cascade,
  constraint communication_sms_consent_state_method_fk
    foreign key (organization_id, client_contact_method_id)
    references public.client_contact_methods(organization_id, id) on delete cascade,
  constraint communication_sms_consent_state_source_event_fk
    foreign key (organization_id, source_event_id)
    references public.communication_sms_consent_events(organization_id, id) on delete restrict,
  constraint communication_sms_consent_state_state_check
    check (state in ('unknown', 'opted_in', 'opted_out'))
);
create index communication_sms_consent_state_client_idx
  on public.communication_sms_consent_state (organization_id, client_id, state);

create function private.project_communication_sms_consent_event()
returns trigger
language plpgsql
set search_path = pg_catalog, public, private
as $$
begin
  if new.event_kind = 'help_requested' then
    return new;
  end if;

  insert into public.communication_sms_consent_state (
    organization_id, client_contact_method_id, client_id, state,
    source_event_id, effective_at, updated_at
  ) values (
    new.organization_id,
    new.client_contact_method_id,
    new.client_id,
    case new.event_kind when 'opt_in' then 'opted_in' else 'opted_out' end,
    new.id,
    new.occurred_at,
    now()
  )
  on conflict (organization_id, client_contact_method_id) do update
  set client_id = excluded.client_id,
      state = excluded.state,
      source_event_id = excluded.source_event_id,
      effective_at = excluded.effective_at,
      updated_at = now()
  where (
    excluded.effective_at,
    (select event.received_at from public.communication_sms_consent_events event
      where event.id = excluded.source_event_id),
    excluded.source_event_id
  ) > (
    public.communication_sms_consent_state.effective_at,
    (select event.received_at from public.communication_sms_consent_events event
      where event.id = public.communication_sms_consent_state.source_event_id),
    public.communication_sms_consent_state.source_event_id
  );

  return new;
end;
$$;

create trigger communication_sms_consent_events_project_after_insert
after insert on public.communication_sms_consent_events
for each row execute function private.project_communication_sms_consent_event();

revoke all on function private.project_communication_sms_consent_event() from public, anon, authenticated;

create table public.communication_sms_credit_accounts (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  currency_code text not null default 'USD',
  settled_balance_minor bigint not null default 0,
  reserved_balance_minor bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint communication_sms_credit_accounts_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_credit_accounts_balances_check
    check (settled_balance_minor >= 0 and reserved_balance_minor >= 0 and reserved_balance_minor <= settled_balance_minor)
);

create table public.communication_sms_credit_reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.communication_sms_credit_accounts(organization_id) on delete cascade,
  delivery_intent_id uuid not null,
  channel text not null default 'sms' check (channel = 'sms'),
  source_key text not null,
  amount_minor bigint not null,
  segment_count integer not null,
  state text not null default 'reserved',
  reserved_at timestamptz not null default now(),
  settled_at timestamptz,
  constraint communication_sms_credit_reservations_intent_fk
    foreign key (organization_id, delivery_intent_id, channel)
    references public.communication_delivery_intents (organization_id, id, channel) on delete restrict,
  constraint communication_sms_credit_reservations_org_id_key unique (organization_id, id),
  constraint communication_sms_credit_reservations_one_intent unique (delivery_intent_id),
  constraint communication_sms_credit_reservations_one_source unique (organization_id, source_key),
  constraint communication_sms_credit_reservations_amount_check check (amount_minor > 0),
  constraint communication_sms_credit_reservations_segments_check check (segment_count between 1 and 10),
  constraint communication_sms_credit_reservations_state_check
    check (state in ('reserved', 'settled', 'released', 'submission_unknown')),
  constraint communication_sms_credit_reservations_settlement_check
    check ((state = 'reserved' and settled_at is null) or (state <> 'reserved' and settled_at is not null)),
  constraint communication_sms_credit_reservations_source_check
    check (char_length(trim(source_key)) between 1 and 200)
);
create index communication_sms_credit_reservations_active_idx
  on public.communication_sms_credit_reservations (organization_id, reserved_at, id)
  where state in ('reserved', 'submission_unknown');

create table public.communication_sms_credit_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.communication_sms_credit_accounts(organization_id) on delete cascade,
  reservation_id uuid,
  source_key text not null,
  entry_kind text not null,
  amount_minor bigint not null,
  balance_after_minor bigint not null,
  occurred_at timestamptz not null default now(),
  constraint communication_sms_credit_ledger_entries_reservation_fk
    foreign key (organization_id, reservation_id)
    references public.communication_sms_credit_reservations(organization_id, id) on delete restrict,
  constraint communication_sms_credit_ledger_entries_source_kind_key
    unique (organization_id, source_key, entry_kind),
  constraint communication_sms_credit_ledger_entries_kind_check
    check (entry_kind in ('credit', 'charge', 'refund', 'adjustment')),
  constraint communication_sms_credit_ledger_entries_amount_check check (amount_minor <> 0),
  constraint communication_sms_credit_ledger_entries_balance_check check (balance_after_minor >= 0),
  constraint communication_sms_credit_ledger_entries_source_check
    check (char_length(trim(source_key)) between 1 and 200)
);
create index communication_sms_credit_ledger_entries_history_idx
  on public.communication_sms_credit_ledger_entries (organization_id, occurred_at desc, id desc);

create table public.communication_sms_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  delivery_intent_id uuid,
  channel text not null default 'sms' check (channel = 'sms'),
  provider_message_id text,
  reason text not null,
  status text not null default 'open',
  available_at timestamptz not null default now(),
  attempt_count integer not null default 0,
  claimed_at timestamptz,
  claim_token uuid,
  last_error text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint communication_sms_reconciliation_items_intent_fk
    foreign key (organization_id, delivery_intent_id, channel)
    references public.communication_delivery_intents (organization_id, id, channel) on delete cascade,
  constraint communication_sms_reconciliation_items_identity_check
    check (delivery_intent_id is not null or provider_message_id is not null),
  constraint communication_sms_reconciliation_items_reason_check
    check (reason in ('submission_unknown', 'callback_before_finalize', 'missing_callback', 'billing_mismatch')),
  constraint communication_sms_reconciliation_items_status_check
    check (status in ('open', 'processing', 'resolved', 'failed')),
  constraint communication_sms_reconciliation_items_claim_check
    check ((status = 'processing') = (claimed_at is not null and claim_token is not null)),
  constraint communication_sms_reconciliation_items_resolution_check
    check ((status = 'resolved') = (resolved_at is not null)),
  constraint communication_sms_reconciliation_items_attempt_check check (attempt_count >= 0)
);
create unique index communication_sms_reconciliation_items_open_intent_key
  on public.communication_sms_reconciliation_items (delivery_intent_id, reason)
  where status in ('open', 'processing', 'failed') and delivery_intent_id is not null;
create index communication_sms_reconciliation_items_claim_idx
  on public.communication_sms_reconciliation_items (available_at, created_at, id)
  where status in ('open', 'failed');

-- Keep the existing email worker and callback projector strictly email-only before SMS rows can exist.
do $migration$
declare
  function_sql text;
  updated_sql text;
begin
  function_sql := pg_get_functiondef('public.claim_communication_outbox_event()'::regprocedure);
  updated_sql := replace(
    function_sql,
    $$where event.status in ('pending', 'failed') and event.available_at <= now()$$,
    $$where event.channel = 'email' and event.status in ('pending', 'failed') and event.available_at <= now()$$
  );
  if updated_sql = function_sql then
    raise exception 'Could not add email channel isolation to claim_communication_outbox_event().';
  end if;
  execute updated_sql;

  function_sql := pg_get_functiondef('public.process_communication_provider_callbacks(integer)'::regprocedure);
  updated_sql := replace(
    function_sql,
    $$where cb.processed_at is null$$,
    $$where cb.channel = 'email' and cb.processed_at is null$$
  );
  if updated_sql = function_sql then
    raise exception 'Could not add email channel isolation to process_communication_provider_callbacks(integer).';
  end if;
  execute updated_sql;

  function_sql := pg_get_functiondef('private.communication_email_reputation_metrics(uuid,timestamp with time zone)'::regprocedure);
  updated_sql := replace(
    function_sql,
    $$where callback.organization_id = p_organization_id$$,
    $$where callback.channel = 'email' and callback.organization_id = p_organization_id$$
  );
  if updated_sql = function_sql then
    raise exception 'Could not add email channel isolation to communication_email_reputation_metrics().';
  end if;
  execute updated_sql;
end;
$migration$;

create or replace function public.get_communication_provider_callback_health()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'processor_job_name', 'communications-provider-callback-processor',
    'unprocessed_count', (
      select count(*) from public.communication_provider_callback_events
      where channel = 'email' and processed_at is null
    ),
    'oldest_unprocessed_at', (
      select min(received_at) from public.communication_provider_callback_events
      where channel = 'email' and processed_at is null
    ),
    'oldest_unprocessed_age_seconds', (
      select extract(epoch from (now() - min(received_at)))::bigint
      from public.communication_provider_callback_events
      where channel = 'email' and processed_at is null
    ),
    'retrying_count', (
      select count(*) from public.communication_provider_callback_events
      where channel = 'email' and processed_at is null and processing_attempts > 0
    ),
    'parked_count', (
      select count(*) from public.communication_provider_callback_events
      where channel = 'email' and processed_at is not null and processing_error is not null
    ),
    'last_run', (
      select jsonb_build_object('status', d.status, 'ran_at', d.start_time, 'finished_at', d.end_time)
      from cron.job j
      join cron.job_run_details d on d.jobid = j.jobid
      where j.jobname = 'communications-provider-callback-processor'
      order by d.start_time desc
      limit 1
    ),
    'last_success_at', (
      select max(d.end_time)
      from cron.job j
      join cron.job_run_details d on d.jobid = j.jobid
      where j.jobname = 'communications-provider-callback-processor' and d.status = 'succeeded'
    ),
    'provider_blocking_24h', coalesce((
      select jsonb_object_agg(g.delivery_outcome, g.outcome_count)
      from (
        select delivery_outcome, count(*) as outcome_count
        from public.communication_delivery_intents
        where channel = 'email'
          and delivery_outcome in ('blocked', 'hard_bounce', 'complaint', 'unsubscribed')
          and delivery_outcome_at >= now() - interval '24 hours'
        group by delivery_outcome
      ) g
    ), '{}'::jsonb),
    'active_suppressions', coalesce((
      select jsonb_object_agg(s.reason, s.reason_count)
      from (
        select reason, count(*) as reason_count
        from public.communication_email_suppressions
        where released_at is null
        group by reason
      ) s
    ), '{}'::jsonb)
  );
$$;

revoke all on function public.get_communication_provider_callback_health() from public, anon, authenticated;
grant execute on function public.get_communication_provider_callback_health() to service_role;

-- Stage 1 tables are server-owned. Contractor reads and writes arrive through checked APIs in later stages.
alter table public.communication_sms_sender_identities enable row level security;
alter table public.communication_sms_message_snapshots enable row level security;
alter table public.communication_sms_submission_attempts enable row level security;
alter table public.communication_sms_consent_events enable row level security;
alter table public.communication_sms_consent_state enable row level security;
alter table public.communication_sms_credit_accounts enable row level security;
alter table public.communication_sms_credit_reservations enable row level security;
alter table public.communication_sms_credit_ledger_entries enable row level security;
alter table public.communication_sms_reconciliation_items enable row level security;

revoke all on table public.communication_sms_sender_identities from public, anon, authenticated;
revoke all on table public.communication_sms_message_snapshots from public, anon, authenticated;
revoke all on table public.communication_sms_submission_attempts from public, anon, authenticated;
revoke all on table public.communication_sms_consent_events from public, anon, authenticated;
revoke all on table public.communication_sms_consent_state from public, anon, authenticated;
revoke all on table public.communication_sms_credit_accounts from public, anon, authenticated;
revoke all on table public.communication_sms_credit_reservations from public, anon, authenticated;
revoke all on table public.communication_sms_credit_ledger_entries from public, anon, authenticated;
revoke all on table public.communication_sms_reconciliation_items from public, anon, authenticated;

revoke all on table public.communication_sms_sender_identities from service_role;
revoke all on table public.communication_sms_message_snapshots from service_role;
revoke all on table public.communication_sms_submission_attempts from service_role;
revoke all on table public.communication_sms_consent_events from service_role;
revoke all on table public.communication_sms_consent_state from service_role;
revoke all on table public.communication_sms_credit_accounts from service_role;
revoke all on table public.communication_sms_credit_reservations from service_role;
revoke all on table public.communication_sms_credit_ledger_entries from service_role;
revoke all on table public.communication_sms_reconciliation_items from service_role;

grant select, insert, update, delete on table public.communication_sms_sender_identities to service_role;
grant select, insert, update, delete on table public.communication_sms_message_snapshots to service_role;
grant select, insert, update, delete on table public.communication_sms_submission_attempts to service_role;
grant select, insert on table public.communication_sms_consent_events to service_role;
grant select, insert, update, delete on table public.communication_sms_consent_state to service_role;
grant select, insert, update, delete on table public.communication_sms_credit_accounts to service_role;
grant select, insert, update, delete on table public.communication_sms_credit_reservations to service_role;
grant select, insert on table public.communication_sms_credit_ledger_entries to service_role;
grant select, insert, update, delete on table public.communication_sms_reconciliation_items to service_role;

comment on table public.communication_sms_consent_events is
  'Append-only SMS consent evidence. Current eligibility is projected separately so delayed events can be ordered by occurred_at, received_at and id.';
comment on table public.communication_sms_credit_ledger_entries is
  'Append-only SMS money history. One logical source and kind can produce only one entry.';
