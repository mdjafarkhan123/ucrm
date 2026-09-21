-- Marketing (M1, slice 1a): the Marketing feature, its three permissions, and the marketing-email
-- consent ledger.
--
-- Mirrors two proven, already-shipped patterns:
--   * the SMS consent ledger (public.communication_sms_consent_events / _state, 20260913023817) for the
--     append-only event log, the projected current-state table, and the last-writer-wins projection;
--   * automations feature + permission registration (20260830093226) for the catalog entries.
--
-- Eligibility to send marketing email is read ONLY from client_marketing_consent_state. The legacy
-- clients.marketing boolean holds no evidence and is never treated as consent; it is retired in a later
-- slice after a one-time count is shown to Jafar.
--
-- The `marketing` feature is added to the catalog but attached to NO package, so it resolves false for
-- every organization until a later slice publishes it (Marketing stays globally disabled until M6).
-- Owner and admin receive all three permissions now, but see nothing until the feature is published,
-- exactly as automations (6B) did.

-- 1. Feature catalog: add marketing, attached to no package. -----------------------------------------
insert into public.features (feature_key, description)
values ('marketing', 'Marketing email campaigns')
on conflict (feature_key) do nothing;

-- 2. Permission keys and owner/admin defaults. ------------------------------------------------------
-- All-or-nothing settings-area capabilities (no assigned/all scope), like automations. The `marketing.`
-- prefix is mapped to the `marketing` feature in src/lib/server/access/effective.ts, so these fold the
-- plan entitlement in automatically. `marketing.launch` is additionally enforced in the launch command,
-- not only the UI.
insert into public.permissions (key, description)
values
  ('marketing.view', 'View marketing campaigns and history'),
  ('marketing.draft', 'Create and edit marketing campaign drafts'),
  ('marketing.launch', 'Launch marketing campaigns')
on conflict (key) do nothing;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'marketing.view'),
  ('owner', 'marketing.draft'),
  ('owner', 'marketing.launch'),
  ('admin', 'marketing.view'),
  ('admin', 'marketing.draft'),
  ('admin', 'marketing.launch')
on conflict (role, permission_key) do nothing;

-- 3. Append-only marketing-email consent ledger. ----------------------------------------------------
-- One row per consent change for a specific email contact method. Mirrors communication_sms_consent_events;
-- the SMS-only 'help_requested' kind and 'client_reply'/'system' sources do not apply to marketing email.
create table public.client_marketing_consent_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  client_contact_method_id uuid not null,
  event_kind text not null,
  source text not null,
  source_event_key text not null,
  disclosure text,
  evidence jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  constraint client_marketing_consent_events_method_fk
    foreign key (organization_id, client_id, client_contact_method_id)
    references public.client_contact_methods (organization_id, client_id, id) on delete restrict,
  constraint client_marketing_consent_events_org_id_key unique (organization_id, id),
  constraint client_marketing_consent_events_source_key unique (organization_id, source, source_event_key),
  constraint client_marketing_consent_events_kind_check
    check (event_kind in ('opt_in', 'opt_out')),
  constraint client_marketing_consent_events_source_check
    check (source in ('public_form', 'staff', 'unsubscribe', 'complaint')),
  constraint client_marketing_consent_events_source_key_check
    check (char_length(btrim(source_event_key)) between 1 and 300),
  constraint client_marketing_consent_events_disclosure_check
    check (disclosure is null or char_length(btrim(disclosure)) between 1 and 2000),
  constraint client_marketing_consent_events_evidence_check
    check (jsonb_typeof(evidence) = 'object')
);

comment on table public.client_marketing_consent_events is
  'Append-only evidence of marketing-email consent changes per email contact method. The only source of '
  'truth for marketing-email eligibility, projected into client_marketing_consent_state.';
comment on column public.client_marketing_consent_events.source is
  'How the change was captured: public_form (opt-in box on a public form), staff (a real verbal/written '
  'preference recorded on the Customer page), unsubscribe (one-click link), or complaint (spam report).';
comment on column public.client_marketing_consent_events.disclosure is
  'The exact opt-in wording shown to the customer at the moment of consent; null for opt-outs.';

create index client_marketing_consent_events_projection_idx
  on public.client_marketing_consent_events
    (organization_id, client_contact_method_id, occurred_at desc, received_at desc, id desc);

-- 4. Projected current state, one row per email contact method. Mirrors communication_sms_consent_state.
create table public.client_marketing_consent_state (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_contact_method_id uuid not null,
  client_id uuid not null,
  state text not null,
  source_event_id uuid not null,
  effective_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (organization_id, client_contact_method_id),
  constraint client_marketing_consent_state_client_fk
    foreign key (organization_id, client_id) references public.clients(organization_id, id) on delete cascade,
  constraint client_marketing_consent_state_method_fk
    foreign key (organization_id, client_contact_method_id)
    references public.client_contact_methods(organization_id, id) on delete cascade,
  constraint client_marketing_consent_state_source_event_fk
    foreign key (organization_id, source_event_id)
    references public.client_marketing_consent_events(organization_id, id) on delete restrict,
  constraint client_marketing_consent_state_state_check
    check (state in ('unknown', 'opted_in', 'opted_out'))
);

comment on table public.client_marketing_consent_state is
  'Current marketing-email consent per email contact method, projected from '
  'client_marketing_consent_events. Marketing eligibility reads this; a method with no row is not '
  'consented.';

-- 5. Idempotent, last-writer-wins projection: events -> state. Verbatim shape of the proven SMS
--    projection (private.project_communication_sms_consent_event), minus the help_requested branch.
create function private.project_client_marketing_consent_event()
returns trigger
language plpgsql
set search_path = pg_catalog, public, private
as $$
begin
  insert into public.client_marketing_consent_state (
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
    (select event.received_at from public.client_marketing_consent_events event
      where event.id = excluded.source_event_id),
    excluded.source_event_id
  ) > (
    public.client_marketing_consent_state.effective_at,
    (select event.received_at from public.client_marketing_consent_events event
      where event.id = public.client_marketing_consent_state.source_event_id),
    public.client_marketing_consent_state.source_event_id
  );

  return new;
end;
$$;

create trigger client_marketing_consent_events_project_after_insert
after insert on public.client_marketing_consent_events
for each row execute function private.project_client_marketing_consent_event();

revoke all on function private.project_client_marketing_consent_event() from public, anon, authenticated;

-- 6. RLS: enabled with no policy, so only the service role reaches these tables. Every read and write
--    goes through server code, exactly like the SMS consent ledger.
alter table public.client_marketing_consent_events enable row level security;
alter table public.client_marketing_consent_state enable row level security;
