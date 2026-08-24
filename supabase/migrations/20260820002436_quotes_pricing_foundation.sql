-- Quotes, Part 2: the pricing foundation.
-- Three things start here and nothing else does: a reusable price list, priced rows on a Request, and the
-- Quote-owned tables a converted Request copies itself into. There is no sending, no customer decision, no
-- deposit, and no Job here, and no placeholder pretending to be one.
--
-- Money is stored the only way money can be stored safely: whole minor units in a bigint. Quantity is
-- numeric, never float. One function does the multiplication, and both line tables call it from a stored
-- generated column, so a line total cannot disagree with itself no matter who wrote the row.

-- 1. The one rounding rule ---------------------------------------------------------------------------------

-- round() on numeric is half away from zero, which is the rule the Quote contract fixed. Both line tables
-- and every reader go through this function, so there is exactly one place this arithmetic exists.
create or replace function public.pricing_line_total_minor(
  quantity numeric,
  unit_price_minor bigint
)
returns bigint
language sql
immutable
set search_path = pg_catalog
as $$
  select round(quantity * unit_price_minor)::bigint;
$$;

comment on function public.pricing_line_total_minor(numeric, bigint) is
  'The only line-total arithmetic in the product. Minor units in, minor units out, half away from zero. '
  'Stored generated columns on request_pricing_lines and quote_version_lines call it, so no application '
  'code may reimplement it.';

revoke all on function public.pricing_line_total_minor(numeric, bigint) from public;
grant execute on function public.pricing_line_total_minor(numeric, bigint) to authenticated;

-- 2. Quote numbers -------------------------------------------------------------------------------------------

-- One row per organization holding the next number to hand out. Nothing reads this table but the allocator
-- below: it has RLS on and no policy and no grant at all, so a member cannot even see how many quotes exist.
create table public.organization_quote_counters (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  next_quote_number integer not null default 1 check (next_quote_number >= 1),
  updated_at timestamptz not null default now()
);

comment on table public.organization_quote_counters is
  'Per-organization quote number allocation. Written only by private.allocate_quote_number under a row '
  'lock; numbers are never reused and never decrease.';

alter table public.organization_quote_counters enable row level security;
revoke all on public.organization_quote_counters from anon, authenticated;

-- The update takes the row lock, so two conversions arriving together are serialised here and cannot be
-- handed the same number. The insert only matters the very first time an organization quotes anything.
create or replace function private.allocate_quote_number(target_organization_id uuid)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  allocated integer;
begin
  insert into public.organization_quote_counters (organization_id)
  values (target_organization_id)
  on conflict (organization_id) do nothing;

  update public.organization_quote_counters
  set next_quote_number = next_quote_number + 1, updated_at = now()
  where organization_id = target_organization_id
  returning next_quote_number - 1 into allocated;

  if allocated is null then
    raise exception 'That organization cannot be given a quote number.' using errcode = 'foreign_key_violation';
  end if;

  return allocated;
end;
$$;

revoke all on function private.allocate_quote_number(uuid) from public;
revoke execute on function private.allocate_quote_number(uuid) from anon, authenticated;

-- 3. The pricing catalog ---------------------------------------------------------------------------------------

-- Reusable defaults, not history. Editing one of these changes what the next line starts from and nothing
-- that was already written down. Labor is a service with a labor flag, not a second kind of pricing: the
-- flag only decides which part of a form the row shows up in.
create table public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category text not null check (category in ('product', 'service')),
  name text not null check (char_length(trim(name)) between 2 and 160),
  description text check (description is null or char_length(description) <= 2000),
  unit_label text check (unit_label is null or char_length(trim(unit_label)) between 1 and 24),
  -- The ceiling is not decoration: quantity is capped at a million and a price at ten billion minor units,
  -- so quantity * price can never leave signed bigint range no matter what a caller sends.
  unit_price_minor bigint not null default 0 check (unit_price_minor between 0 and 1000000000000),
  unit_cost_minor bigint not null default 0 check (unit_cost_minor between 0 and 1000000000000),
  is_taxable boolean not null default true,
  is_labor boolean not null default false,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint catalog_items_organization_id_unique unique (organization_id, id),
  constraint catalog_items_labor_is_service check (not is_labor or category = 'service')
);

comment on table public.catalog_items is
  'Organization-owned reusable product and service defaults. Never history: a change here affects the next '
  'line added and never rewrites a request pricing row or a quote version line already written.';

-- The picker and the settings list ask the same question: this organization''s live items, grouped by kind,
-- in name order. Partial, because archived items are the part that grows forever and neither screen wants
-- them by default.
create index catalog_items_active_idx
  on public.catalog_items(organization_id, category, name, id)
  where archived_at is null;

-- The whole list including archived, for the settings screen''s "show archived" and its keyset paging.
create index catalog_items_organization_name_idx on public.catalog_items(organization_id, name, id);

create index catalog_items_created_by_idx
  on public.catalog_items(created_by)
  where created_by is not null;

create trigger catalog_items_set_updated_at
before update on public.catalog_items
for each row execute function public.set_updated_at();

-- 4. Request pricing ---------------------------------------------------------------------------------------------

-- A Request owns its priced rows. They start from a catalog item or from nothing, and once written they are
-- the Request''s own copy: the catalog can change underneath them and they do not move.
alter table public.requests
  add column pricing_revision integer not null default 0 check (pricing_revision >= 0),
  add column pricing_subtotal_minor bigint not null default 0 check (pricing_subtotal_minor >= 0);

comment on column public.requests.pricing_revision is
  'Bumped once by every accepted replace_request_pricing_lines call. A caller sends the revision it read; a '
  'stale one is refused so two people editing pricing cannot silently overwrite each other.';

create table public.request_pricing_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  -- Zero based, assigned from the order the caller sent. Deliberately not unique: the whole set is
  -- rewritten in one statement, and a unique constraint would fire mid-statement on a simple reorder.
  position integer not null check (position >= 0),
  -- Provenance only. Null means somebody typed a one-off line.
  catalog_item_id uuid,
  category text not null check (category in ('product', 'service')),
  is_labor boolean not null default false,
  name text not null check (char_length(trim(name)) between 2 and 160),
  description text check (description is null or char_length(description) <= 2000),
  unit_label text check (unit_label is null or char_length(trim(unit_label)) between 1 and 24),
  quantity numeric(12, 3) not null check (quantity > 0 and quantity <= 1000000),
  unit_price_minor bigint not null default 0 check (unit_price_minor between 0 and 1000000000000),
  unit_cost_minor bigint not null default 0 check (unit_cost_minor between 0 and 1000000000000),
  is_taxable boolean not null default true,
  line_total_minor bigint not null
    generated always as (public.pricing_line_total_minor(quantity, unit_price_minor)) stored,
  line_cost_total_minor bigint not null
    generated always as (public.pricing_line_total_minor(quantity, unit_cost_minor)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint request_pricing_lines_organization_id_unique unique (organization_id, id),
  constraint request_pricing_lines_request_organization_fk foreign key (organization_id, request_id)
    references public.requests(organization_id, id) on delete cascade,
  constraint request_pricing_lines_catalog_organization_fk foreign key (organization_id, catalog_item_id)
    references public.catalog_items(organization_id, id) on delete set null,
  constraint request_pricing_lines_labor_is_service check (not is_labor or category = 'service')
);

comment on table public.request_pricing_lines is
  'Priced product, service, and labor rows on a request. Members may read this table, never write it: the '
  'whole set is replaced atomically by public.replace_request_pricing_lines, which is also what keeps '
  'requests.pricing_subtotal_minor and requests.pricing_revision true.';

create index request_pricing_lines_request_idx
  on public.request_pricing_lines(organization_id, request_id, position, id);

create index request_pricing_lines_catalog_item_idx
  on public.request_pricing_lines(organization_id, catalog_item_id)
  where catalog_item_id is not null;

create trigger request_pricing_lines_set_updated_at
before update on public.request_pricing_lines
for each row execute function public.set_updated_at();

-- 5. Quote identity and its version snapshots -------------------------------------------------------------------

-- Part 2 only ever writes 'draft'. The other six states are the vocabulary the approved contract fixed, and
-- writing them into the check now means the later parts add behavior, not a schema migration that rewrites
-- every row's constraint.
create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  property_id uuid not null,
  -- Null for a quote somebody started directly. Set, and permanent, for one made from a request.
  request_id uuid,
  quote_number integer not null check (quote_number >= 1),
  title text not null check (char_length(trim(title)) between 2 and 160),
  status text not null default 'draft' check (status in (
    'draft', 'awaiting_response', 'changes_requested', 'approved', 'declined', 'archived', 'converted'
  )),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  draft_version_id uuid,
  -- The conversion command's receipt, kept on the row it produced rather than in a generic receipts table,
  -- which is how every other command in this repository already does idempotency.
  conversion_idempotency_key text,
  conversion_request_hash text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotes_organization_id_unique unique (organization_id, id),
  constraint quotes_number_unique unique (organization_id, quote_number),
  constraint quotes_client_organization_fk foreign key (organization_id, client_id)
    references public.clients(organization_id, id) on delete restrict,
  constraint quotes_property_organization_fk foreign key (organization_id, property_id)
    references public.properties(organization_id, id) on delete restrict,
  constraint quotes_request_organization_fk foreign key (organization_id, request_id)
    references public.requests(organization_id, id) on delete restrict,
  constraint quotes_conversion_receipt_consistent check (
    (conversion_idempotency_key is null) = (conversion_request_hash is null)
  ),
  constraint quotes_conversion_needs_request check (
    conversion_idempotency_key is null or request_id is not null
  )
);

comment on table public.quotes is
  'Quote identity. Members may read this table, never write it. Part 2 creates rows only through '
  'public.convert_request_to_quote; direct creation and every later lifecycle command arrive in Part 3 and '
  'after, each through its own checked function.';

-- One request may produce one quote, and this is what makes that true when two conversions race: the loser
-- fails on the index rather than creating a second quote.
create unique index quotes_request_lineage_idx
  on public.quotes(organization_id, request_id)
  where request_id is not null;

create unique index quotes_conversion_key_idx
  on public.quotes(organization_id, conversion_idempotency_key)
  where conversion_idempotency_key is not null;

create index quotes_client_idx on public.quotes(organization_id, client_id, created_at desc, id);
create index quotes_property_idx on public.quotes(organization_id, property_id);
create index quotes_created_by_idx on public.quotes(created_by) where created_by is not null;

create trigger quotes_set_updated_at
before update on public.quotes
for each row execute function public.set_updated_at();

create table public.quote_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  version_number integer not null check (version_number >= 1),
  status text not null default 'draft' check (status in ('draft', 'published')),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  -- Frozen copies, not joins. A later client rename or address correction must not rewrite what a customer
  -- was shown, so the version keeps its own text.
  client_display_name text not null,
  organization_name text not null,
  service_address_line1 text,
  service_address_line2 text,
  service_city text,
  service_state_region text,
  service_postal_code text,
  service_country text,
  -- Maintained by the same commands that write the lines. There is no other writer.
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_versions_organization_id_unique unique (organization_id, id),
  constraint quote_versions_quote_scoped_unique unique (organization_id, quote_id, id),
  constraint quote_versions_number_unique unique (organization_id, quote_id, version_number),
  constraint quote_versions_quote_organization_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete cascade
);

comment on table public.quote_versions is
  'Quote-owned proposal snapshots. Part 2 writes exactly one draft per quote. Published versions and their '
  'immutability guards belong to Part 4; the status vocabulary is here so that part adds behavior rather '
  'than rewriting this constraint.';

create unique index quote_versions_one_draft_idx
  on public.quote_versions(organization_id, quote_id)
  where status = 'draft';

create index quote_versions_created_by_idx
  on public.quote_versions(created_by)
  where created_by is not null;

create trigger quote_versions_set_updated_at
before update on public.quote_versions
for each row execute function public.set_updated_at();

alter table public.quotes
  add constraint quotes_draft_version_organization_fk foreign key (organization_id, draft_version_id)
    references public.quote_versions(organization_id, id) on delete set null;

create index quotes_draft_version_idx
  on public.quotes(organization_id, draft_version_id)
  where draft_version_id is not null;

create table public.quote_version_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Both parents are carried so a reader can filter by quote without joining, and the composite foreign key
  -- below makes it impossible for the two to disagree.
  quote_id uuid not null,
  quote_version_id uuid not null,
  position integer not null check (position >= 0),
  -- Deliberately not a foreign key. This is a note about where the price came from, and a catalog item
  -- disappearing must never reach into a quote's own copy of it.
  source_catalog_item_id uuid,
  category text not null check (category in ('product', 'service')),
  is_labor boolean not null default false,
  name text not null check (char_length(trim(name)) between 2 and 160),
  description text check (description is null or char_length(description) <= 2000),
  unit_label text check (unit_label is null or char_length(trim(unit_label)) between 1 and 24),
  quantity numeric(12, 3) not null check (quantity > 0 and quantity <= 1000000),
  unit_price_minor bigint not null default 0 check (unit_price_minor between 0 and 1000000000000),
  unit_cost_minor bigint not null default 0 check (unit_cost_minor between 0 and 1000000000000),
  is_taxable boolean not null default true,
  line_total_minor bigint not null
    generated always as (public.pricing_line_total_minor(quantity, unit_price_minor)) stored,
  line_cost_total_minor bigint not null
    generated always as (public.pricing_line_total_minor(quantity, unit_cost_minor)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_version_lines_organization_id_unique unique (organization_id, id),
  constraint quote_version_lines_version_organization_fk
    foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade,
  constraint quote_version_lines_labor_is_service check (not is_labor or category = 'service')
);

comment on table public.quote_version_lines is
  'A quote version''s own copy of its priced lines. Copied from request pricing at conversion and owned by '
  'the quote from that moment: nothing in the catalog or on the request can change these numbers again.';

-- One index for both questions readers ask: every line on a quote, and every line on one of its versions.
create index quote_version_lines_version_idx
  on public.quote_version_lines(organization_id, quote_id, quote_version_id, position, id);

create trigger quote_version_lines_set_updated_at
before update on public.quote_version_lines
for each row execute function public.set_updated_at();

-- 6. Request pricing has one write path -----------------------------------------------------------------------

-- Replacing the whole set is the only sensible shape for a pricing table people reorder and retype, but it
-- has to be one statement pair inside one lock or a crash halfway leaves a request with no prices at all.
-- The expected revision is what stops the second of two people saving over the first without knowing.
create or replace function public.replace_request_pricing_lines(
  target_request_id uuid,
  expected_revision integer,
  new_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.requests;
  line jsonb;
  line_index integer := 0;
  clean_quantity numeric;
  clean_price bigint;
  clean_cost bigint;
  clean_category text;
  clean_name text;
  clean_catalog_item_id uuid;
  new_revision integer;
  new_subtotal bigint;
  new_count integer;
begin
  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'Pricing must be sent as a list of lines.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_lines) > 200 then
    raise exception 'A request can hold up to 200 pricing lines.' using errcode = 'program_limit_exceeded';
  end if;

  select * into request_row from public.requests where id = target_request_id for update;

  -- One answer for "no such request" and "not your request": a stranger learns nothing either way.
  if request_row.id is null
     or not private.is_organization_member(request_row.organization_id) then
    raise exception 'You do not have access to price this request.' using errcode = 'insufficient_privilege';
  end if;

  if request_row.status in ('converted', 'archived') then
    raise exception 'This request is closed and its pricing cannot be changed.'
      using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from request_row.pricing_revision then
    raise exception 'Someone else changed this pricing while you were editing. Reload and try again.'
      using errcode = '40001';
  end if;

  delete from public.request_pricing_lines where request_id = target_request_id;

  for line in select * from jsonb_array_elements(new_lines)
  loop
    clean_name := nullif(trim(coalesce(line ->> 'name', '')), '');
    clean_category := coalesce(line ->> 'category', 'service');
    clean_quantity := coalesce((line ->> 'quantity')::numeric, 0);
    clean_price := coalesce((line ->> 'unit_price_minor')::bigint, 0);
    clean_cost := coalesce((line ->> 'unit_cost_minor')::bigint, 0);
    clean_catalog_item_id := nullif(line ->> 'catalog_item_id', '')::uuid;

    if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
      raise exception 'Line % needs a name between 2 and 160 characters.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_category not in ('product', 'service') then
      raise exception 'Line % must be a product or a service.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_quantity <= 0 or clean_quantity > 1000000 then
      raise exception 'Line % needs a quantity above zero.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_price < 0 or clean_price > 1000000000000 or clean_cost < 0 or clean_cost > 1000000000000 then
      raise exception 'Line % has a price or cost outside the allowed range.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- An archived item is still readable, because old lines reference it, but it cannot start a new one.
    if clean_catalog_item_id is not null and not exists (
      select 1 from public.catalog_items
      where id = clean_catalog_item_id
        and organization_id = request_row.organization_id
        and archived_at is null
    ) then
      raise exception 'Line % points at a price list item that is no longer available.', line_index + 1
        using errcode = 'check_violation';
    end if;

    insert into public.request_pricing_lines (
      organization_id, request_id, position, catalog_item_id, category, is_labor,
      name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable
    ) values (
      request_row.organization_id,
      target_request_id,
      line_index,
      clean_catalog_item_id,
      clean_category,
      coalesce((line ->> 'is_labor')::boolean, false),
      clean_name,
      nullif(trim(coalesce(line ->> 'description', '')), ''),
      nullif(trim(coalesce(line ->> 'unit_label', '')), ''),
      clean_quantity,
      clean_price,
      clean_cost,
      coalesce((line ->> 'is_taxable')::boolean, true)
    );

    line_index := line_index + 1;
  end loop;

  select coalesce(sum(line_total_minor), 0), count(*)
  into new_subtotal, new_count
  from public.request_pricing_lines
  where request_id = target_request_id;

  update public.requests
  set pricing_revision = pricing_revision + 1, pricing_subtotal_minor = new_subtotal
  where id = target_request_id
  returning pricing_revision into new_revision;

  return jsonb_build_object(
    'revision', new_revision, 'line_count', new_count, 'subtotal_minor', new_subtotal
  );
end;
$$;

revoke all on function public.replace_request_pricing_lines(uuid, integer, jsonb) from public;
revoke execute on function public.replace_request_pricing_lines(uuid, integer, jsonb) from anon;
grant execute on function public.replace_request_pricing_lines(uuid, integer, jsonb) to authenticated;

-- 7. Permissions ------------------------------------------------------------------------------------------------

insert into public.permissions (key, description)
values
  ('catalog.view', 'See the reusable product and service price list'),
  ('catalog.edit', 'Add, change, and archive price list items'),
  ('quotes.view', 'See quotes and their contents'),
  ('quotes.view_price', 'See quote prices and totals'),
  ('quotes.view_cost', 'See internal cost and profit on a quote'),
  ('quotes.create', 'Start a quote, including from a request'),
  ('quotes.edit', 'Change a draft quote')
on conflict (key) do update set description = excluded.description;

-- Field is absent for the same reason it is absent from clients and the pipeline: a crew member reaches
-- work through their assignment, not through a price list. Finance reads money and cost but writes neither.
-- The sending, decision, deposit, and convert-to-job keys are not seeded: nothing can do those things yet.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'catalog.view'),
  ('owner', 'catalog.edit'),
  ('owner', 'quotes.view'),
  ('owner', 'quotes.view_price'),
  ('owner', 'quotes.view_cost'),
  ('owner', 'quotes.create'),
  ('owner', 'quotes.edit'),

  ('admin', 'catalog.view'),
  ('admin', 'catalog.edit'),
  ('admin', 'quotes.view'),
  ('admin', 'quotes.view_price'),
  ('admin', 'quotes.view_cost'),
  ('admin', 'quotes.create'),
  ('admin', 'quotes.edit'),

  ('office', 'catalog.view'),
  ('office', 'catalog.edit'),
  ('office', 'quotes.view'),
  ('office', 'quotes.view_price'),
  ('office', 'quotes.create'),
  ('office', 'quotes.edit'),

  ('sales', 'catalog.view'),
  ('sales', 'catalog.edit'),
  ('sales', 'quotes.view'),
  ('sales', 'quotes.view_price'),
  ('sales', 'quotes.create'),
  ('sales', 'quotes.edit'),

  ('finance', 'catalog.view'),
  ('finance', 'quotes.view'),
  ('finance', 'quotes.view_price'),
  ('finance', 'quotes.view_cost')
on conflict (role, permission_key) do nothing;

-- 8. Row level security --------------------------------------------------------------------------------------

alter table public.catalog_items enable row level security;
alter table public.request_pricing_lines enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_versions enable row level security;
alter table public.quote_version_lines enable row level security;

create policy "permitted members can view catalog items"
on public.catalog_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'catalog.view')
);

create policy "permitted members can create catalog items"
on public.catalog_items for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'catalog.edit')
);

create policy "permitted members can update catalog items"
on public.catalog_items for update to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'catalog.edit')
)
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'catalog.edit')
);

-- Read only, like tasks. Members see request pricing the same way they see the request itself, and the
-- replace command is the only thing that writes it.
create policy "members can view request pricing"
on public.request_pricing_lines for select to authenticated
using (private.is_organization_member(organization_id));

create policy "permitted members can view quotes"
on public.quotes for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'quotes.view')
);

create policy "permitted members can view quote versions"
on public.quote_versions for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'quotes.view')
);

create policy "permitted members can view quote version lines"
on public.quote_version_lines for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'quotes.view')
);

revoke all on public.catalog_items from anon, authenticated;
revoke all on public.request_pricing_lines from anon, authenticated;
revoke all on public.quotes from anon, authenticated;
revoke all on public.quote_versions from anon, authenticated;
revoke all on public.quote_version_lines from anon, authenticated;

-- Archiving is an update, so no delete grant is needed anywhere here.
grant select, insert, update on public.catalog_items to authenticated;
grant select on public.request_pricing_lines to authenticated;
grant select on public.quotes to authenticated;
grant select on public.quote_versions to authenticated;
grant select on public.quote_version_lines to authenticated;
