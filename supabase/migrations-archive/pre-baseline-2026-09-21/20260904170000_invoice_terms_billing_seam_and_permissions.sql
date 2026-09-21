-- Invoices Part 3a, file 1 of 3: who may bill, when a bill is due, and where it is sent.
--
-- Nothing in this file creates an invoice. It builds the three things an invoice has to read before it can
-- exist: the permission catalog, the organization's named payment terms with its residential and commercial
-- defaults, and the client's own billing address and term override.
--
-- The approved design's resolution order is Invoice override -> Client term -> residential/commercial
-- account default, and a client's effective billing address is either a designated property or a custom
-- address on the client, never both and never a silent fallback to the primary property. Both rules live in
-- the database here so no screen can reimplement them differently.
--
-- Deliberately not here: invoices, lines, money, or any command that moves it. Files 2 and 3 own those.

-- 1. Who is allowed to do what with an invoice --------------------------------------------------------------

-- The full Invoice permission set lands in one place so the role matrix is reviewed once. Price visibility is
-- separate from view, exactly as jobs and quotes already split them: a crew member may need to know an
-- invoice exists without seeing what the customer was charged.
insert into public.permissions (key, description)
values
  ('invoices.view', 'See invoices and their contents'),
  ('invoices.view_price', 'See invoice amounts, totals and balances'),
  ('invoices.create', 'Create an invoice'),
  ('invoices.edit', 'Change an invoice''s details, lines and terms'),
  ('invoices.send', 'Issue an invoice by sending it or marking it sent'),
  ('invoices.record_payment', 'Record a payment received outside the app'),
  ('invoices.correct_payment', 'Reverse, move or refund a recorded payment'),
  ('invoices.void', 'Void an invalid or cancelled invoice'),
  ('invoices.bad_debt', 'Write off an uncollectable balance and reverse that write-off'),
  ('invoices.delete', 'Delete a draft invoice'),
  ('settings.invoices.manage', 'Manage payment terms and invoice defaults')
on conflict (key) do update set description = excluded.description;

-- Owner and admin only, on purpose. The approved design defers any Finance or Office grant to an explicit
-- role-matrix review rather than assuming a role that can record a quote deposit should also be able to void
-- a bill or write off a debt.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'invoices.view'),
  ('owner', 'invoices.view_price'),
  ('owner', 'invoices.create'),
  ('owner', 'invoices.edit'),
  ('owner', 'invoices.send'),
  ('owner', 'invoices.record_payment'),
  ('owner', 'invoices.correct_payment'),
  ('owner', 'invoices.void'),
  ('owner', 'invoices.bad_debt'),
  ('owner', 'invoices.delete'),
  ('owner', 'settings.invoices.manage'),
  ('admin', 'invoices.view'),
  ('admin', 'invoices.view_price'),
  ('admin', 'invoices.create'),
  ('admin', 'invoices.edit'),
  ('admin', 'invoices.send'),
  ('admin', 'invoices.record_payment'),
  ('admin', 'invoices.correct_payment'),
  ('admin', 'invoices.void'),
  ('admin', 'invoices.bad_debt'),
  ('admin', 'invoices.delete'),
  ('admin', 'settings.invoices.manage')
on conflict (role, permission_key) do nothing;

-- 2. Payment terms ------------------------------------------------------------------------------------------

-- Jobber's baseline set, stored as rows rather than an enum because staff may add their own named net terms.
-- The three protected rules are protected because a due date has to be derivable for every organization: if
-- a contractor could delete "Due on receipt" there would be nothing to fall back to.
create table public.invoice_payment_terms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 60),
  -- on_receipt: due the day it is issued. net_days: issue date plus n days. month_end and next_month_end
  -- are calendar rules, not day counts, so they cannot be expressed as net_days without lying.
  rule text not null check (rule in ('on_receipt', 'net_days', 'month_end', 'next_month_end')),
  net_days integer check (net_days is null or net_days between 1 and 365),
  -- Seeded rows carrying a calendar rule. Renaming one is allowed; deleting one is not.
  is_protected boolean not null default false,
  position integer not null default 0 check (position >= 0),
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoice_payment_terms_organization_id_unique unique (organization_id, id),
  -- A day count belongs to net_days and only to net_days. A calendar rule that also carried a day count
  -- would have two answers for the same question.
  constraint invoice_payment_terms_rule_shape check (
    (rule = 'net_days' and net_days is not null)
    or (rule <> 'net_days' and net_days is null)
  ),
  -- Only calendar rules are protectable. A net term is an ordinary named term staff own.
  constraint invoice_payment_terms_protected_is_calendar check (
    not is_protected or rule in ('on_receipt', 'month_end', 'next_month_end')
  )
);

comment on table public.invoice_payment_terms is
  'Organization-owned named payment terms. The three calendar rules are seeded protected rows so every '
  'organization can always resolve a due date; net terms are ordinary rows staff may add, rename or remove.';

-- Two live terms may not share a name, because the picker would show the same label twice with different
-- meanings. Archived rows keep their name so historical invoices still read correctly.
create unique index invoice_payment_terms_live_name_idx
  on public.invoice_payment_terms(organization_id, lower(trim(name)))
  where archived_at is null;

-- One protected row per calendar rule per organization: the resolver below looks a rule up by name-free
-- identity, so a second "Due on receipt" would make that lookup ambiguous.
create unique index invoice_payment_terms_one_protected_rule_idx
  on public.invoice_payment_terms(organization_id, rule)
  where is_protected;

create index invoice_payment_terms_live_position_idx
  on public.invoice_payment_terms(organization_id, position, id)
  where archived_at is null;

alter table public.invoice_payment_terms enable row level security;

create policy "members can view invoice payment terms"
on public.invoice_payment_terms for select to authenticated
using (private.is_organization_member(organization_id));

revoke all on public.invoice_payment_terms from anon, authenticated;
grant select on public.invoice_payment_terms to authenticated;

-- Seeding. Every organization gets the same starting set, including ones that already exist.
create or replace function private.seed_invoice_payment_terms(target_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.invoice_payment_terms
    (organization_id, name, rule, net_days, is_protected, position)
  values
    (target_organization_id, 'Due on receipt', 'on_receipt', null, true, 0),
    (target_organization_id, 'Net 7', 'net_days', 7, false, 1),
    (target_organization_id, 'Net 15', 'net_days', 15, false, 2),
    (target_organization_id, 'Net 30', 'net_days', 30, false, 3),
    (target_organization_id, 'Net 45', 'net_days', 45, false, 4),
    (target_organization_id, 'Net 60', 'net_days', 60, false, 5),
    (target_organization_id, 'End of month', 'month_end', null, true, 6),
    (target_organization_id, 'End of next month', 'next_month_end', null, true, 7)
  on conflict do nothing;
end;
$$;

revoke all on function private.seed_invoice_payment_terms(uuid) from public;
revoke execute on function private.seed_invoice_payment_terms(uuid) from anon, authenticated;

create or replace function private.create_invoice_payment_terms()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform private.seed_invoice_payment_terms(new.id);
  return new;
end;
$$;

revoke all on function private.create_invoice_payment_terms() from public;
revoke execute on function private.create_invoice_payment_terms() from anon, authenticated;

create trigger organizations_create_invoice_payment_terms
after insert on public.organizations
for each row execute function private.create_invoice_payment_terms();

do $$
declare
  existing_organization uuid;
begin
  for existing_organization in select id from public.organizations loop
    perform private.seed_invoice_payment_terms(existing_organization);
  end loop;
end $$;

-- 3. The organization's invoice defaults ----------------------------------------------------------------------

-- Two defaults, matching the contract's resolution order: a company-name client bills on the commercial
-- default and everyone else on the residential one. Restrict, not cascade: deleting a term that an
-- organization still defaults to must fail loudly rather than quietly leaving no default at all.
alter table public.organization_settings
  add column invoice_default_term_residential_id uuid,
  add column invoice_default_term_commercial_id uuid,
  add column invoice_settings_revision integer not null default 0,
  add column invoice_settings_updated_by uuid references auth.users(id) on delete set null,
  add column invoice_settings_updated_at timestamptz;

alter table public.organization_settings
  add constraint organization_settings_invoice_residential_term_fk
    foreign key (organization_id, invoice_default_term_residential_id)
    references public.invoice_payment_terms(organization_id, id) on delete restrict,
  add constraint organization_settings_invoice_commercial_term_fk
    foreign key (organization_id, invoice_default_term_commercial_id)
    references public.invoice_payment_terms(organization_id, id) on delete restrict,
  add constraint organization_settings_invoice_revision_check
    check (invoice_settings_revision >= 0);

-- Point both defaults at "Due on receipt" for every organization, which is the same value the resolver falls
-- back to. Setting it explicitly means the settings screen has something real to show from day one.
update public.organization_settings as settings
set invoice_default_term_residential_id = protected_term.id,
    invoice_default_term_commercial_id = protected_term.id
from public.invoice_payment_terms as protected_term
where protected_term.organization_id = settings.organization_id
  and protected_term.rule = 'on_receipt'
  and protected_term.is_protected
  and settings.invoice_default_term_residential_id is null;

alter table public.organization_settings_audit
  drop constraint organization_settings_audit_section_check;

alter table public.organization_settings_audit
  add constraint organization_settings_audit_section_check check (
    section in (
      'profile', 'branding', 'hours', 'pipeline', 'taxes', 'quote_terms', 'quote_representative',
      'quote_target_margin', 'quote_signature_policy', 'invoice_terms'
    )
  );

-- 4. The client's billing address and term override -----------------------------------------------------------

-- A custom billing address lives on the client. The alternative is a designated property, which
-- properties.is_billing_address already records with its own one-per-client unique index. The check below
-- makes a half-written custom address impossible; the command in section 6 is what keeps the two choices
-- from both being set.
alter table public.clients
  add column billing_payment_term_id uuid,
  add column billing_address_line1 text,
  add column billing_address_line2 text,
  add column billing_city text,
  add column billing_state_region text,
  add column billing_postal_code text,
  add column billing_country text;

alter table public.clients
  add constraint clients_billing_term_fk
    foreign key (organization_id, billing_payment_term_id)
    references public.invoice_payment_terms(organization_id, id) on delete restrict,
  -- A custom billing address is a whole address or none of one. Line 1, city and country are what makes it
  -- deliverable; the rest are optional in the same way they already are on properties.
  add constraint clients_billing_address_complete check (
    (
      billing_address_line1 is null and billing_city is null and billing_country is null
      and billing_address_line2 is null and billing_state_region is null and billing_postal_code is null
    )
    or (
      char_length(trim(billing_address_line1)) between 2 and 200
      and char_length(trim(billing_city)) between 1 and 120
      and char_length(trim(billing_country)) between 2 and 80
    )
  );

-- The term FK is ON DELETE RESTRICT, so removing a term makes Postgres look for clients still pointing at
-- it. Without this index that lookup is a full scan of the tenant's client list.
create index clients_billing_payment_term_idx
  on public.clients(organization_id, billing_payment_term_id)
  where billing_payment_term_id is not null;

comment on column public.clients.billing_payment_term_id is
  'Client-level payment term override. Null means the organization default for this client type applies.';
comment on column public.clients.billing_address_line1 is
  'First line of a custom billing address. Mutually exclusive with a property carrying is_billing_address, '
  'enforced by public.set_client_billing.';

-- 5. Resolving a term and a billing address ---------------------------------------------------------------------

-- The contract's resolution order, written once. Callers pass the invoice's own override when it has one;
-- everything after that is this function's business. It always resolves to something, because "Due on
-- receipt" is protected and cannot be deleted.
create or replace function private.resolve_client_payment_term(
  target_organization_id uuid,
  target_client_id uuid,
  invoice_term_override_id uuid default null
)
returns public.invoice_payment_terms
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  client_row public.clients;
  settings_row public.organization_settings;
  resolved public.invoice_payment_terms;
  candidate_id uuid;
begin
  select * into client_row
  from public.clients
  where organization_id = target_organization_id and id = target_client_id;
  if not found then
    raise exception 'That client could not be found.' using errcode = 'P0404';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id;

  candidate_id := coalesce(
    invoice_term_override_id,
    client_row.billing_payment_term_id,
    case
      when client_row.client_type = 'company' then settings_row.invoice_default_term_commercial_id
      else settings_row.invoice_default_term_residential_id
    end
  );

  if candidate_id is not null then
    select * into resolved
    from public.invoice_payment_terms
    where organization_id = target_organization_id and id = candidate_id;
    if found then
      return resolved;
    end if;
  end if;

  -- Last resort, and the reason the receipt term is protected: an organization whose default was somehow
  -- lost still gets a real due date instead of an error on the invoice screen.
  select * into resolved
  from public.invoice_payment_terms
  where organization_id = target_organization_id and rule = 'on_receipt' and is_protected;

  if not found then
    raise exception 'This organization has no payment terms set up.' using errcode = 'P0404';
  end if;

  return resolved;
end;
$$;

revoke all on function private.resolve_client_payment_term(uuid, uuid, uuid) from public;
revoke execute on function private.resolve_client_payment_term(uuid, uuid, uuid) from anon, authenticated;

-- The due date arithmetic, kept beside the terms it reads. The issue date is already the organization's
-- local calendar date by the time it gets here -- this function does calendar maths on a date and never
-- touches now(), so it cannot pick up a server or browser timezone by accident.
create or replace function private.invoice_due_date(
  issue_date date,
  term public.invoice_payment_terms
)
returns date
language sql
immutable
set search_path = pg_catalog
as $$
  select case term.rule
    when 'on_receipt' then issue_date
    when 'net_days' then issue_date + term.net_days
    when 'month_end' then (date_trunc('month', issue_date::timestamp) + interval '1 month - 1 day')::date
    when 'next_month_end'
      then (date_trunc('month', issue_date::timestamp) + interval '2 months - 1 day')::date
  end;
$$;

comment on function private.invoice_due_date(date, public.invoice_payment_terms) is
  'The only due-date arithmetic in the product. Takes an organization-local issue date and a term row; '
  'never reads the clock, so no caller can leak a server or browser timezone into a due date.';

revoke all on function private.invoice_due_date(date, public.invoice_payment_terms) from public;
revoke execute on function private.invoice_due_date(date, public.invoice_payment_terms)
  from anon, authenticated;

-- The client's one effective billing address, as a snapshot-shaped object. A designated property wins only
-- because the client chose it; there is no fallback to the primary property, so a client with neither gets
-- a null address and the invoice command decides whether that is allowed.
create or replace function private.resolve_client_billing_address(
  target_organization_id uuid,
  target_client_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  client_row public.clients;
  billing_property public.properties;
begin
  select * into client_row
  from public.clients
  where organization_id = target_organization_id and id = target_client_id;
  if not found then
    raise exception 'That client could not be found.' using errcode = 'P0404';
  end if;

  if client_row.billing_address_line1 is not null then
    return jsonb_build_object(
      'source', 'client',
      'property_id', null,
      'address_line1', client_row.billing_address_line1,
      'address_line2', client_row.billing_address_line2,
      'city', client_row.billing_city,
      'state_region', client_row.billing_state_region,
      'postal_code', client_row.billing_postal_code,
      'country', client_row.billing_country
    );
  end if;

  select * into billing_property
  from public.properties
  where organization_id = target_organization_id
    and client_id = target_client_id
    and is_billing_address
    and deleted_at is null;

  if not found then
    return jsonb_build_object('source', 'none', 'property_id', null);
  end if;

  return jsonb_build_object(
    'source', 'property',
    'property_id', billing_property.id,
    'address_line1', billing_property.address_line1,
    'address_line2', billing_property.address_line2,
    'city', billing_property.city,
    'state_region', billing_property.state_region,
    'postal_code', billing_property.postal_code,
    'country', billing_property.country
  );
end;
$$;

revoke all on function private.resolve_client_billing_address(uuid, uuid) from public;
revoke execute on function private.resolve_client_billing_address(uuid, uuid) from anon, authenticated;

-- 6. The one guarded client billing command ----------------------------------------------------------------------

-- Address choice and term override in one call, because they are one decision on one screen and because
-- writing the address in two places is exactly how the two choices drift into both being set. Mode says
-- which kind of address this client uses, and the command clears whichever one the mode does not name.
create or replace function public.set_client_billing(
  target_organization_id uuid,
  target_client_id uuid,
  address_mode text,
  billing_property_id uuid default null,
  new_address_line1 text default null,
  new_address_line2 text default null,
  new_city text default null,
  new_state_region text default null,
  new_postal_code text default null,
  new_country text default null,
  new_payment_term_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  client_row public.clients;
  chosen_property public.properties;
  clean_line1 text := nullif(trim(coalesce(new_address_line1, '')), '');
  clean_line2 text := nullif(trim(coalesce(new_address_line2, '')), '');
  clean_city text := nullif(trim(coalesce(new_city, '')), '');
  clean_region text := nullif(trim(coalesce(new_state_region, '')), '');
  clean_postal text := nullif(trim(coalesce(new_postal_code, '')), '');
  clean_country text := nullif(trim(coalesce(new_country, '')), '');
begin
  if caller is null then
    raise exception 'You must be signed in to change billing details.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'customers.edit') then
    raise exception 'You do not have access to change this client''s billing details.'
      using errcode = 'insufficient_privilege';
  end if;
  if address_mode not in ('property', 'custom', 'none') then
    raise exception 'Choose whether billing uses a property, a custom address, or neither.'
      using errcode = 'check_violation';
  end if;

  select * into client_row
  from public.clients
  where organization_id = target_organization_id and id = target_client_id
  for update;
  if not found then
    raise exception 'That client could not be found.' using errcode = 'P0404';
  end if;

  if new_payment_term_id is not null and not exists (
    select 1 from public.invoice_payment_terms
    where organization_id = target_organization_id
      and id = new_payment_term_id
      and archived_at is null
  ) then
    raise exception 'That payment term is not available.' using errcode = 'check_violation';
  end if;

  if address_mode = 'custom' then
    if clean_line1 is null or clean_city is null or clean_country is null then
      raise exception 'A custom billing address needs a street address, a city and a country.'
        using errcode = 'check_violation';
    end if;
  end if;

  -- Whichever choice is not in force is cleared in the same statement that sets the other one, so the two
  -- can never both be true between two writes.
  update public.properties
  set is_billing_address = false, updated_at = now()
  where organization_id = target_organization_id
    and client_id = target_client_id
    and is_billing_address
    and (address_mode <> 'property' or id is distinct from billing_property_id);

  if address_mode = 'property' then
    select * into chosen_property
    from public.properties
    where organization_id = target_organization_id
      and id = billing_property_id
      and client_id = target_client_id
      and deleted_at is null
    for update;
    if not found then
      raise exception 'That property does not belong to this client.' using errcode = 'check_violation';
    end if;

    update public.properties
    set is_billing_address = true, updated_at = now()
    where organization_id = target_organization_id and id = chosen_property.id;
  end if;

  update public.clients
  set billing_payment_term_id = new_payment_term_id,
      billing_address_line1 = case when address_mode = 'custom' then clean_line1 end,
      billing_address_line2 = case when address_mode = 'custom' then clean_line2 end,
      billing_city = case when address_mode = 'custom' then clean_city end,
      billing_state_region = case when address_mode = 'custom' then clean_region end,
      billing_postal_code = case when address_mode = 'custom' then clean_postal end,
      billing_country = case when address_mode = 'custom' then clean_country end,
      updated_at = now()
  where organization_id = target_organization_id and id = target_client_id;

  return jsonb_build_object(
    'client_id', target_client_id,
    'billing_address', private.resolve_client_billing_address(target_organization_id, target_client_id),
    'payment_term_id', new_payment_term_id
  );
end;
$$;

revoke all on function public.set_client_billing(
  uuid, uuid, text, uuid, text, text, text, text, text, text, uuid
) from public;
revoke execute on function public.set_client_billing(
  uuid, uuid, text, uuid, text, text, text, text, text, text, uuid
) from anon;
grant execute on function public.set_client_billing(
  uuid, uuid, text, uuid, text, text, text, text, text, text, uuid
) to authenticated;

-- 7. Managing the organization's terms ------------------------------------------------------------------------

create or replace function private.lock_invoice_settings_for_edit(
  target_organization_id uuid,
  expected_revision integer
)
returns public.organization_settings
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  settings_row public.organization_settings;
begin
  if caller is null then
    raise exception 'You must be signed in to change invoice settings.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'settings.invoices.manage') then
    raise exception 'You do not have access to invoice settings.' using errcode = 'insufficient_privilege';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  if settings_row.invoice_settings_revision is distinct from expected_revision then
    raise exception 'Someone else changed invoice settings. Reload to see the latest.'
      using errcode = 'P0409';
  end if;

  return settings_row;
end;
$$;

revoke all on function private.lock_invoice_settings_for_edit(uuid, integer) from public;
revoke execute on function private.lock_invoice_settings_for_edit(uuid, integer) from anon, authenticated;

create or replace function private.bump_invoice_settings(
  target_organization_id uuid,
  changed_fields text[]
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  next_revision integer;
begin
  update public.organization_settings
  set invoice_settings_revision = invoice_settings_revision + 1,
      invoice_settings_updated_by = (select auth.uid()),
      invoice_settings_updated_at = now(),
      updated_at = now()
  where organization_id = target_organization_id
  returning invoice_settings_revision into next_revision;

  if array_length(changed_fields, 1) is not null then
    insert into public.organization_settings_audit
      (organization_id, section, changed_fields, actor_user_id)
    values (target_organization_id, 'invoice_terms', changed_fields, (select auth.uid()));
  end if;

  return next_revision;
end;
$$;

revoke all on function private.bump_invoice_settings(uuid, text[]) from public;
revoke execute on function private.bump_invoice_settings(uuid, text[]) from anon, authenticated;

create or replace function public.save_invoice_payment_term(
  target_organization_id uuid,
  expected_revision integer,
  target_term_id uuid,
  new_name text,
  new_rule text,
  new_net_days integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  existing_term public.invoice_payment_terms;
  saved_term public.invoice_payment_terms;
  clean_name text := nullif(trim(coalesce(new_name, '')), '');
  next_position integer;
begin
  settings_row := private.lock_invoice_settings_for_edit(target_organization_id, expected_revision);

  if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 60 then
    raise exception 'A payment term needs a name between 2 and 60 characters.'
      using errcode = 'check_violation';
  end if;
  if new_rule not in ('on_receipt', 'net_days', 'month_end', 'next_month_end') then
    raise exception 'Choose how this term works out its due date.' using errcode = 'check_violation';
  end if;
  if new_rule = 'net_days' and (new_net_days is null or new_net_days < 1 or new_net_days > 365) then
    raise exception 'A net term needs a day count between 1 and 365.' using errcode = 'check_violation';
  end if;

  if target_term_id is null then
    select coalesce(max(position), -1) + 1 into next_position
    from public.invoice_payment_terms
    where organization_id = target_organization_id;

    insert into public.invoice_payment_terms
      (organization_id, name, rule, net_days, is_protected, position, created_by)
    values (
      target_organization_id, clean_name, new_rule,
      case when new_rule = 'net_days' then new_net_days end,
      false, next_position, (select auth.uid())
    )
    returning * into saved_term;
  else
    select * into existing_term
    from public.invoice_payment_terms
    where organization_id = target_organization_id and id = target_term_id
    for update;
    if not found then
      raise exception 'That payment term could not be found.' using errcode = 'P0404';
    end if;
    if existing_term.archived_at is not null then
      raise exception 'That payment term has been removed.' using errcode = 'check_violation';
    end if;
    -- A protected term may be renamed, because "Due on receipt" is only a label. Its rule may not change,
    -- because the resolver's last-resort lookup finds it by rule.
    if existing_term.is_protected and new_rule is distinct from existing_term.rule then
      raise exception 'This term''s timing is built in and cannot be changed. Rename it instead.'
        using errcode = 'check_violation';
    end if;

    update public.invoice_payment_terms
    set name = clean_name,
        rule = new_rule,
        net_days = case when new_rule = 'net_days' then new_net_days end,
        updated_at = now()
    where organization_id = target_organization_id and id = target_term_id
    returning * into saved_term;
  end if;

  return jsonb_build_object(
    'term_id', saved_term.id,
    'invoice_settings_revision',
      private.bump_invoice_settings(target_organization_id, array['payment_terms'])
  );
end;
$$;

revoke all on function public.save_invoice_payment_term(uuid, integer, uuid, text, text, integer)
  from public;
revoke execute on function public.save_invoice_payment_term(uuid, integer, uuid, text, text, integer)
  from anon;
grant execute on function public.save_invoice_payment_term(uuid, integer, uuid, text, text, integer)
  to authenticated;

-- Removal is archival, not deletion, because an invoice issued under a term keeps pointing at it. The
-- contract's rule about a removed default is here: the organization falls back to the receipt term rather
-- than being left with no default.
create or replace function public.remove_invoice_payment_term(
  target_organization_id uuid,
  expected_revision integer,
  target_term_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  existing_term public.invoice_payment_terms;
  receipt_term public.invoice_payment_terms;
  changed text[] := array['payment_terms'];
begin
  settings_row := private.lock_invoice_settings_for_edit(target_organization_id, expected_revision);

  select * into existing_term
  from public.invoice_payment_terms
  where organization_id = target_organization_id and id = target_term_id
  for update;
  if not found then
    raise exception 'That payment term could not be found.' using errcode = 'P0404';
  end if;
  if existing_term.is_protected then
    raise exception 'This term is built in and cannot be removed.' using errcode = 'check_violation';
  end if;
  if existing_term.archived_at is not null then
    return jsonb_build_object(
      'term_id', existing_term.id,
      'invoice_settings_revision', settings_row.invoice_settings_revision
    );
  end if;

  select * into receipt_term
  from public.invoice_payment_terms
  where organization_id = target_organization_id and rule = 'on_receipt' and is_protected;

  if settings_row.invoice_default_term_residential_id = target_term_id
     or settings_row.invoice_default_term_commercial_id = target_term_id then
    update public.organization_settings
    set invoice_default_term_residential_id = case
          when invoice_default_term_residential_id = target_term_id then receipt_term.id
          else invoice_default_term_residential_id end,
        invoice_default_term_commercial_id = case
          when invoice_default_term_commercial_id = target_term_id then receipt_term.id
          else invoice_default_term_commercial_id end
    where organization_id = target_organization_id;
    changed := changed || array['defaults'];
  end if;

  -- Clients pointing at it fall back to the organization default the same way, so no client is left with a
  -- dangling override.
  update public.clients
  set billing_payment_term_id = null, updated_at = now()
  where organization_id = target_organization_id and billing_payment_term_id = target_term_id;

  update public.invoice_payment_terms
  set archived_at = now(), updated_at = now()
  where organization_id = target_organization_id and id = target_term_id;

  return jsonb_build_object(
    'term_id', target_term_id,
    'invoice_settings_revision', private.bump_invoice_settings(target_organization_id, changed)
  );
end;
$$;

revoke all on function public.remove_invoice_payment_term(uuid, integer, uuid) from public;
revoke execute on function public.remove_invoice_payment_term(uuid, integer, uuid) from anon;
grant execute on function public.remove_invoice_payment_term(uuid, integer, uuid) to authenticated;

create or replace function public.set_organization_invoice_defaults(
  target_organization_id uuid,
  expected_revision integer,
  new_residential_term_id uuid,
  new_commercial_term_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
begin
  settings_row := private.lock_invoice_settings_for_edit(target_organization_id, expected_revision);

  if new_residential_term_id is null or new_commercial_term_id is null then
    raise exception 'Both the residential and commercial defaults need a payment term.'
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from unnest(array[new_residential_term_id, new_commercial_term_id]) as chosen(term_id)
    where not exists (
      select 1 from public.invoice_payment_terms
      where organization_id = target_organization_id
        and id = chosen.term_id
        and archived_at is null
    )
  ) then
    raise exception 'One of those payment terms is not available.' using errcode = 'check_violation';
  end if;

  update public.organization_settings
  set invoice_default_term_residential_id = new_residential_term_id,
      invoice_default_term_commercial_id = new_commercial_term_id
  where organization_id = target_organization_id;

  return jsonb_build_object(
    'invoice_settings_revision',
      private.bump_invoice_settings(target_organization_id, array['defaults'])
  );
end;
$$;

revoke all on function public.set_organization_invoice_defaults(uuid, integer, uuid, uuid) from public;
revoke execute on function public.set_organization_invoice_defaults(uuid, integer, uuid, uuid) from anon;
grant execute on function public.set_organization_invoice_defaults(uuid, integer, uuid, uuid)
  to authenticated;
