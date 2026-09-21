-- Contractor Settings, Part 2C: Quote Settings (terms, representative, target margin, signature policy).
--
-- The last four Quote-Settings defaults from the approved blueprint: default terms and conditions, an
-- optional business-representative block copied into new drafts, a private target profit margin visible
-- only to cost-permitted staff, and the organization-wide Require-customer-signature choice. Each saves
-- independently with its own revision, matching the Taxes (2A) and Price Book (2B) precedent exactly --
-- same organization_settings section shape, same audit trail, same stale-conflict JSON return.
--
-- `quote_versions.contract_disclaimer` already exists as a free-typed box with no settings-backed default
-- (see 20260820104833_quote_workspace_commands.sql's column comment) -- this migration is exactly that
-- missing default. The representative block and signature-required flag are new, frozen the same way tax
-- already is: copied onto the version at draft-creation time, then carried untouched through
-- `freeze_quote_version` (which hashes and versions the whole row except an explicit exclusion list) and
-- through `clone_quote_version_to_draft` (which copies column-by-column from the prior version, not from
-- settings again) -- so a later Settings change never rewrites an existing draft or published Quote.
--
-- Target margin is deliberately NOT copied onto quote_versions: it is live guidance compared against the
-- version's own already-computed `margin_basis_points`, not a document fact to freeze.
--
-- Order: permission, the four organization_settings column groups, the audit-section extension, the four
-- section commands, then three edits to existing Quote functions (quote_versions columns, create_quote,
-- clone_quote_version_to_draft) so the new defaults are actually reachable end to end.

-- 1. Permission ---------------------------------------------------------------------------------------

-- One key covers seeing and managing every Quote Settings section, same one-key-per-area convention as
-- settings.taxes.manage and settings.price_book.manage. Target-margin *visibility inside a quote* stays on
-- the existing quotes.view_cost boundary -- this key is only about the Settings page itself.
insert into public.permissions (key, description)
values ('settings.quotes.manage', 'See and manage Quote Settings: terms, representative, target margin, and signature policy')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'settings.quotes.manage'),
  ('admin', 'settings.quotes.manage')
on conflict (role, permission_key) do nothing;

-- 2. organization_settings: four independently-revisioned sections -----------------------------------

alter table public.organization_settings
  -- Terms and conditions. Sanitized to the approved safe-formatting allow-list (paragraphs, headings,
  -- lists, bold, italic, links) by the API layer before this column ever sees it; the length check here is
  -- defense in depth, not the sanitization boundary itself.
  add column quote_terms text check (quote_terms is null or char_length(quote_terms) <= 20000),
  add column quote_terms_revision integer not null default 1,
  add column quote_terms_updated_by uuid references auth.users(id) on delete set null,
  add column quote_terms_updated_at timestamptz,

  -- Business representative. Presentation content only -- never an approval workflow. Enabling requires a
  -- name; title and a signature image (uploaded or drawn) are optional.
  add column quote_representative_enabled boolean not null default false,
  add column quote_representative_name text check (quote_representative_name is null or char_length(quote_representative_name) between 1 and 160),
  add column quote_representative_title text check (quote_representative_title is null or char_length(quote_representative_title) between 1 and 160),
  add column quote_representative_signature_object_key text,
  add column quote_representative_revision integer not null default 1,
  add column quote_representative_updated_by uuid references auth.users(id) on delete set null,
  add column quote_representative_updated_at timestamptz,
  add constraint organization_settings_quote_representative_needs_name check (
    not quote_representative_enabled or quote_representative_name is not null
  ),

  -- Target margin. Not set (null) is the honest starting state -- never guessed. When set: > 0% and < 100%.
  add column quote_target_margin_basis_points integer
    check (quote_target_margin_basis_points is null or (quote_target_margin_basis_points > 0 and quote_target_margin_basis_points < 10000)),
  add column quote_target_margin_revision integer not null default 1,
  add column quote_target_margin_updated_by uuid references auth.users(id) on delete set null,
  add column quote_target_margin_updated_at timestamptz,

  -- Require customer signature. Organization-wide, starts off. Copied into each new Quote and frozen at
  -- publish; changing this later never changes a link already sent.
  add column quote_require_customer_signature boolean not null default false,
  add column quote_signature_policy_revision integer not null default 1,
  add column quote_signature_policy_updated_by uuid references auth.users(id) on delete set null,
  add column quote_signature_policy_updated_at timestamptz;

-- Reuse the same audit trail every other Settings section writes to.
alter table public.organization_settings_audit drop constraint organization_settings_audit_section_check;
alter table public.organization_settings_audit add constraint organization_settings_audit_section_check
  check (section = any (array[
    'profile', 'branding', 'hours', 'pipeline', 'taxes',
    'quote_terms', 'quote_representative', 'quote_target_margin', 'quote_signature_policy'
  ]));

-- 3. quote_versions: the frozen per-document copy -------------------------------------------------------

-- Terms already has its column (contract_disclaimer). These four are new. Nothing here needs its own
-- freeze-time handling: `freeze_quote_version`'s canonical hash already covers every quote_versions column
-- it does not explicitly exclude, so these are hashed and versioned for free.
alter table public.quote_versions
  add column representative_enabled boolean not null default false,
  add column representative_name text,
  add column representative_title text,
  add column representative_signature_object_key text,
  add column require_customer_signature boolean not null default false;

-- 4. Section commands, one per independently-saved part ---------------------------------------------------

create or replace function public.set_organization_quote_terms(
  target_organization_id uuid,
  expected_revision integer,
  new_terms text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  clean_terms text;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.quotes.manage') then
    raise exception 'You do not have access to manage Quote Settings.' using errcode = 'insufficient_privilege';
  end if;

  clean_terms := nullif(trim(coalesce(new_terms, '')), '');
  if clean_terms is not null and char_length(clean_terms) > 20000 then
    raise exception 'Keep the terms under 20,000 characters.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.quote_terms_revision then
    select profile.full_name, settings_row.quote_terms_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.quote_terms_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  update public.organization_settings
  set quote_terms = clean_terms, quote_terms_revision = quote_terms_revision + 1,
      quote_terms_updated_by = (select auth.uid()), quote_terms_updated_at = now()
  where organization_id = target_organization_id
  returning quote_terms_revision into settings_row.quote_terms_revision;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (target_organization_id, 'quote_terms', array['quote_terms'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'quote_terms_revision', settings_row.quote_terms_revision,
    'quote_terms', clean_terms
  );
end;
$$;

revoke all on function public.set_organization_quote_terms(uuid, integer, text) from public;
revoke execute on function public.set_organization_quote_terms(uuid, integer, text) from anon;
grant execute on function public.set_organization_quote_terms(uuid, integer, text) to authenticated;

create or replace function public.set_organization_quote_representative(
  target_organization_id uuid,
  expected_revision integer,
  new_enabled boolean,
  new_name text,
  new_title text,
  new_signature_object_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  clean_name text;
  clean_title text;
  previous_object_key text;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.quotes.manage') then
    raise exception 'You do not have access to manage Quote Settings.' using errcode = 'insufficient_privilege';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  clean_title := nullif(trim(coalesce(new_title, '')), '');

  if new_enabled and clean_name is null then
    raise exception 'Enter a representative name.' using errcode = 'check_violation';
  end if;
  if clean_name is not null and char_length(clean_name) > 160 then
    raise exception 'Keep the representative name under 160 characters.' using errcode = 'check_violation';
  end if;
  if clean_title is not null and char_length(clean_title) > 160 then
    raise exception 'Keep the title under 160 characters.' using errcode = 'check_violation';
  end if;

  -- Same trust boundary as the logo: a key issued for this organization can never be committed by another.
  if new_signature_object_key is not null
     and new_signature_object_key !~ ('^' || target_organization_id::text || '/quote-representative-signature/')
  then
    raise exception 'That signature upload is invalid.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.quote_representative_revision then
    select profile.full_name, settings_row.quote_representative_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.quote_representative_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  previous_object_key := settings_row.quote_representative_signature_object_key;

  update public.organization_settings
  set quote_representative_enabled = new_enabled,
      quote_representative_name = clean_name,
      quote_representative_title = clean_title,
      quote_representative_signature_object_key = new_signature_object_key,
      quote_representative_revision = quote_representative_revision + 1,
      quote_representative_updated_by = (select auth.uid()),
      quote_representative_updated_at = now()
  where organization_id = target_organization_id
  returning quote_representative_revision into settings_row.quote_representative_revision;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (
    target_organization_id, 'quote_representative',
    array['quote_representative_enabled', 'quote_representative_name', 'quote_representative_title', 'quote_representative_signature_object_key'],
    (select auth.uid())
  );

  return jsonb_build_object(
    'status', 'saved',
    'quote_representative_revision', settings_row.quote_representative_revision,
    'quote_representative_enabled', new_enabled,
    'quote_representative_name', clean_name,
    'quote_representative_title', clean_title,
    'quote_representative_signature_object_key', new_signature_object_key,
    'previous_signature_object_key', previous_object_key
  );
end;
$$;

revoke all on function public.set_organization_quote_representative(uuid, integer, boolean, text, text, text) from public;
revoke execute on function public.set_organization_quote_representative(uuid, integer, boolean, text, text, text) from anon;
grant execute on function public.set_organization_quote_representative(uuid, integer, boolean, text, text, text) to authenticated;

create or replace function public.set_organization_quote_target_margin(
  target_organization_id uuid,
  expected_revision integer,
  new_margin_basis_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.quotes.manage') then
    raise exception 'You do not have access to manage Quote Settings.' using errcode = 'insufficient_privilege';
  end if;

  if new_margin_basis_points is not null and (new_margin_basis_points <= 0 or new_margin_basis_points >= 10000) then
    raise exception 'Target margin must be greater than 0%% and below 100%%.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.quote_target_margin_revision then
    select profile.full_name, settings_row.quote_target_margin_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.quote_target_margin_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  update public.organization_settings
  set quote_target_margin_basis_points = new_margin_basis_points,
      quote_target_margin_revision = quote_target_margin_revision + 1,
      quote_target_margin_updated_by = (select auth.uid()),
      quote_target_margin_updated_at = now()
  where organization_id = target_organization_id
  returning quote_target_margin_revision into settings_row.quote_target_margin_revision;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (target_organization_id, 'quote_target_margin', array['quote_target_margin_basis_points'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'quote_target_margin_revision', settings_row.quote_target_margin_revision,
    'quote_target_margin_basis_points', new_margin_basis_points
  );
end;
$$;

revoke all on function public.set_organization_quote_target_margin(uuid, integer, integer) from public;
revoke execute on function public.set_organization_quote_target_margin(uuid, integer, integer) from anon;
grant execute on function public.set_organization_quote_target_margin(uuid, integer, integer) to authenticated;

create or replace function public.set_organization_quote_signature_policy(
  target_organization_id uuid,
  expected_revision integer,
  new_require_signature boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.quotes.manage') then
    raise exception 'You do not have access to manage Quote Settings.' using errcode = 'insufficient_privilege';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.quote_signature_policy_revision then
    select profile.full_name, settings_row.quote_signature_policy_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.quote_signature_policy_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  update public.organization_settings
  set quote_require_customer_signature = new_require_signature,
      quote_signature_policy_revision = quote_signature_policy_revision + 1,
      quote_signature_policy_updated_by = (select auth.uid()),
      quote_signature_policy_updated_at = now()
  where organization_id = target_organization_id
  returning quote_signature_policy_revision into settings_row.quote_signature_policy_revision;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (target_organization_id, 'quote_signature_policy', array['quote_require_customer_signature'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'quote_signature_policy_revision', settings_row.quote_signature_policy_revision,
    'quote_require_customer_signature', new_require_signature
  );
end;
$$;

revoke all on function public.set_organization_quote_signature_policy(uuid, integer, boolean) from public;
revoke execute on function public.set_organization_quote_signature_policy(uuid, integer, boolean) from anon;
grant execute on function public.set_organization_quote_signature_policy(uuid, integer, boolean) to authenticated;

-- 5. Wire the defaults into a new Quote draft ------------------------------------------------------------

create or replace function public.create_quote(
  target_client_id uuid,
  target_property_id uuid,
  quote_title text,
  disclaimer text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  client_row public.clients;
  property_row public.properties;
  new_quote public.quotes;
  new_version public.quote_versions;
  allocated_number integer;
  organization_currency text;
  organization_display_name text;
  clean_title text;
  clean_disclaimer text;
  resolved_tax record;
  quote_settings public.organization_settings;
begin
  clean_title := nullif(trim(coalesce(quote_title, '')), '');
  if clean_title is null or char_length(clean_title) < 2 or char_length(clean_title) > 160 then
    raise exception 'A quote needs a title between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  clean_disclaimer := nullif(trim(coalesce(disclaimer, '')), '');
  if clean_disclaimer is not null and char_length(clean_disclaimer) > 5000 then
    raise exception 'The contract disclaimer is too long.' using errcode = 'check_violation';
  end if;

  select * into client_row from public.clients where id = target_client_id;

  -- One answer for "no such client" and "not your client": a stranger learns nothing either way.
  if client_row.id is null
     or not private.member_has_permission(
       client_row.organization_id, (select auth.uid()), 'quotes.create'
     ) then
    raise exception 'You do not have access to create a quote for this client.'
      using errcode = 'insufficient_privilege';
  end if;

  if client_row.deleted_at is not null then
    raise exception 'That client is no longer available.' using errcode = 'check_violation';
  end if;
  if client_row.archived_at is not null then
    raise exception 'That client is archived. Restore them before quoting new work.'
      using errcode = 'check_violation';
  end if;

  select * into property_row
  from public.properties
  where id = target_property_id
    and organization_id = client_row.organization_id
    and client_id = client_row.id;

  if property_row.id is null
     or property_row.deleted_at is not null
     or property_row.archived_at is not null then
    raise exception 'Choose a live property belonging to this client.' using errcode = 'check_violation';
  end if;

  select * into quote_settings
  from public.organization_settings
  where organization_id = client_row.organization_id;

  organization_currency := quote_settings.currency_code;

  select organization.name into organization_display_name
  from public.organizations as organization
  where organization.id = client_row.organization_id;

  allocated_number := private.allocate_quote_number(client_row.organization_id);

  select * into resolved_tax
  from private.resolve_property_tax(client_row.organization_id, property_row.id);

  -- No disclaimer typed by the caller falls back to the Quote Settings default. An explicit disclaimer
  -- (used by conversion flows that already compose their own) always wins.
  if clean_disclaimer is null then
    clean_disclaimer := quote_settings.quote_terms;
  end if;

  insert into public.quotes (
    organization_id, client_id, property_id, quote_number, title, currency_code, created_by
  ) values (
    client_row.organization_id,
    client_row.id,
    property_row.id,
    allocated_number,
    clean_title,
    coalesce(organization_currency, 'USD'),
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code,
    client_display_name, organization_name, contract_disclaimer,
    service_address_line1, service_address_line2, service_city,
    service_state_region, service_postal_code, service_country,
    tax_source, tax_name, tax_rate_basis_points, tax_rate_id,
    representative_enabled, representative_name, representative_title, representative_signature_object_key,
    require_customer_signature,
    created_by
  ) values (
    new_quote.organization_id,
    new_quote.id,
    1,
    'draft',
    new_quote.currency_code,
    client_row.display_name,
    organization_display_name,
    clean_disclaimer,
    property_row.address_line1,
    property_row.address_line2,
    property_row.city,
    property_row.state_region,
    property_row.postal_code,
    property_row.country,
    resolved_tax.source, resolved_tax.name, resolved_tax.rate_basis_points, resolved_tax.rate_id,
    coalesce(quote_settings.quote_representative_enabled, false),
    quote_settings.quote_representative_name,
    quote_settings.quote_representative_title,
    quote_settings.quote_representative_signature_object_key,
    coalesce(quote_settings.quote_require_customer_signature, false),
    (select auth.uid())
  )
  returning * into new_version;

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  -- Same card the conversion command creates, for the same reason: every quote is one piece of commercial
  -- work with one identity. The stage trigger parks it off the board until the Quote columns exist.
  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title);

  return jsonb_build_object(
    'quote_id', new_quote.id,
    'quote_number', new_quote.quote_number,
    'quote_version_id', new_version.id,
    'status', new_quote.status,
    'revision', new_version.revision
  );
end;
$$;

revoke all on function public.create_quote(uuid, uuid, text, text) from public;
revoke execute on function public.create_quote(uuid, uuid, text, text) from anon;
grant execute on function public.create_quote(uuid, uuid, text, text) to authenticated;

-- 6. Revising an existing Quote keeps what it already had, not the current Settings default -------------

create or replace function public.clone_quote_version_to_draft(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  source_row public.quote_versions;
  new_draft public.quote_versions;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to revise this quote.' using errcode = 'insufficient_privilege';
  end if;
  if quote_row.draft_version_id is not null then
    raise exception 'This quote already has a draft.' using errcode = 'P0409';
  end if;
  select * into source_row from public.quote_versions
  where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
  for share;
  if source_row.id is null or source_row.status <> 'published' then
    raise exception 'This quote has no published version to revise.' using errcode = 'check_violation';
  end if;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code, client_display_name,
    organization_name, service_address_line1, service_address_line2, service_city, service_state_region,
    service_postal_code, service_country, subtotal_minor, created_by, revision, contract_disclaimer,
    introduction, client_message, show_quantities, show_unit_prices, show_line_totals, show_totals,
    discount_name, discount_type, discount_value, tax_name, tax_rate_basis_points,
    representative_enabled, representative_name, representative_title, representative_signature_object_key,
    require_customer_signature
  ) values (
    source_row.organization_id, source_row.quote_id, 0, 'draft', source_row.currency_code,
    source_row.client_display_name, source_row.organization_name, source_row.service_address_line1,
    source_row.service_address_line2, source_row.service_city, source_row.service_state_region,
    source_row.service_postal_code, source_row.service_country, source_row.subtotal_minor,
    (select auth.uid()), 1, source_row.contract_disclaimer, source_row.introduction,
    source_row.client_message, source_row.show_quantities, source_row.show_unit_prices,
    source_row.show_line_totals, source_row.show_totals, source_row.discount_name,
    source_row.discount_type, source_row.discount_value, source_row.tax_name, source_row.tax_rate_basis_points,
    source_row.representative_enabled, source_row.representative_name, source_row.representative_title,
    source_row.representative_signature_object_key, source_row.require_customer_signature
  ) returning * into new_draft;

  insert into public.quote_version_packages (
    organization_id, quote_id, quote_version_id, position, name, description, is_recommended
  ) select organization_id, quote_id, new_draft.id, position, name, description, is_recommended
  from public.quote_version_packages where quote_version_id = source_row.id;

  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_attachment_id, line_kind, selection_kind, package_id, is_recommended
  ) select line.organization_id, line.quote_id, new_draft.id, line.position,
    line.source_catalog_item_id, line.category, line.is_labor, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_attachment_id, line.line_kind, line.selection_kind, new_package.id, line.is_recommended
  from public.quote_version_lines line
  left join public.quote_version_packages old_package on old_package.id = line.package_id
  left join public.quote_version_packages new_package
    on new_package.organization_id = line.organization_id
   and new_package.quote_version_id = new_draft.id
   and new_package.position = old_package.position
  where line.quote_version_id = source_row.id order by line.position, line.id;

  insert into public.quote_version_attachments (
    organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
  ) select organization_id, quote_id, new_draft.id, attachment_id, position, customer_visible, display_name
  from public.quote_version_attachments where quote_version_id = source_row.id order by position, id;

  perform private.refresh_quote_draft_totals(new_draft.id);

  update public.quotes set draft_version_id = new_draft.id where id = quote_row.id;
  return jsonb_build_object('quote_id', quote_row.id, 'quote_version_id', new_draft.id, 'revision', 1);
end;
$$;

revoke all on function public.clone_quote_version_to_draft(uuid) from public;
revoke execute on function public.clone_quote_version_to_draft(uuid) from anon, authenticated;
