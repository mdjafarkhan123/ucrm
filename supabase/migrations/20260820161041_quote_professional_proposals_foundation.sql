-- Quotes Part 4A: professional proposal and immutable-version database foundation.
-- Staff publication controls arrive in Part 5. These commands establish exact calculation, freezing,
-- cloning, tenant-safe proposal children, and database guards without sending or changing Quote lifecycle.

-- 1. Drafts use version 0; published versions alone consume positive numbers -------------------------------

alter table public.quote_versions drop constraint quote_versions_version_number_check;
update public.quote_versions set version_number = 0 where status = 'draft';
alter table public.quote_versions
  add constraint quote_versions_number_matches_status check (
    (status = 'draft' and version_number = 0)
    or (status = 'published' and version_number >= 1)
  );

-- Older create/conversion commands still pass `1` while creating a draft. The database owns the new rule, so
-- every draft insert is normalized at the table boundary until those command signatures are replaced in 4B.
create or replace function private.normalize_quote_draft_number()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  if new.status = 'draft' then new.version_number := 0; end if;
  return new;
end;
$$;

revoke all on function private.normalize_quote_draft_number() from public;
revoke execute on function private.normalize_quote_draft_number() from anon, authenticated;

create trigger quote_versions_normalize_draft_number
before insert on public.quote_versions
for each row execute function private.normalize_quote_draft_number();

alter table public.quote_versions
  add column introduction text check (introduction is null or char_length(introduction) <= 10000),
  add column client_message text check (client_message is null or char_length(client_message) <= 5000),
  add column show_quantities boolean not null default true,
  add column show_unit_prices boolean not null default true,
  add column show_line_totals boolean not null default true,
  add column show_totals boolean not null default true,
  add column discount_name text,
  add column discount_type text,
  add column discount_value bigint,
  add column tax_name text,
  add column tax_rate_basis_points integer not null default 0,
  add column discount_minor bigint not null default 0,
  add column tax_minor bigint not null default 0,
  add column total_minor bigint not null default 0,
  add column cost_minor bigint not null default 0,
  add column profit_minor bigint not null default 0,
  add column margin_basis_points bigint,
  add column calculation jsonb not null default '{}'::jsonb,
  add column document_hash text,
  add column published_at timestamptz,
  add constraint quote_versions_discount_name_check check (
    discount_name is null or char_length(trim(discount_name)) between 1 and 80
  ),
  add constraint quote_versions_discount_check check (
    (discount_type is null and discount_value is null and discount_name is null)
    or (
      discount_type in ('fixed', 'percentage')
      and discount_value between 0 and case when discount_type = 'percentage' then 10000 else 9000000000000000000 end
      and discount_name is not null
    )
  ),
  add constraint quote_versions_tax_name_check check (
    tax_name is null or char_length(trim(tax_name)) between 1 and 80
  ),
  add constraint quote_versions_tax_check check (
    tax_rate_basis_points between 0 and 10000
    and ((tax_rate_basis_points = 0 and tax_name is null) or tax_name is not null)
  ),
  add constraint quote_versions_totals_check check (
    subtotal_minor >= 0 and discount_minor >= 0 and tax_minor >= 0 and total_minor >= 0
    and cost_minor >= 0 and discount_minor <= subtotal_minor
  ),
  add constraint quote_versions_publication_check check (
    (status = 'draft' and published_at is null and document_hash is null)
    or (
      status = 'published'
      and published_at is not null
      and document_hash ~ '^[0-9a-f]{64}$'
    )
  );

comment on column public.quote_versions.calculation is
  'Database-owned itemized calculation for the version default selection. Consumers display it; they do not recalculate it.';
comment on column public.quote_versions.document_hash is
  'SHA-256 of canonical customer-visible version content, assigned only when the version is frozen.';

alter table public.quotes
  add column current_published_version_id uuid;

alter table public.quotes
  add constraint quotes_current_published_version_fk
  foreign key (organization_id, id, current_published_version_id)
  references public.quote_versions(organization_id, quote_id, id)
  on delete restrict;

create index quotes_current_published_version_idx
  on public.quotes(organization_id, current_published_version_id)
  where current_published_version_id is not null;

-- 2. Package, line-choice, and customer-visible attachment snapshots --------------------------------------

create table public.quote_version_packages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  quote_version_id uuid not null,
  position integer not null check (position between 0 and 2),
  name text not null check (char_length(trim(name)) between 2 and 80),
  description text check (description is null or char_length(description) <= 2000),
  is_recommended boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_version_packages_organization_id_unique unique (organization_id, id),
  constraint quote_version_packages_version_scoped_unique
    unique (organization_id, quote_id, quote_version_id, id),
  constraint quote_version_packages_position_unique
    unique (organization_id, quote_version_id, position),
  constraint quote_version_packages_version_fk
    foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade
);

create unique index quote_version_packages_one_recommended_idx
  on public.quote_version_packages(organization_id, quote_version_id)
  where is_recommended;

create index quote_version_packages_version_idx
  on public.quote_version_packages(organization_id, quote_id, quote_version_id, position, id);

create trigger quote_version_packages_set_updated_at
before update on public.quote_version_packages
for each row execute function public.set_updated_at();

alter table public.quote_version_lines
  drop constraint quote_version_lines_category_check,
  drop constraint quote_version_lines_labor_is_service,
  drop constraint quote_version_lines_quantity_check,
  drop constraint quote_version_lines_unit_price_minor_check,
  drop constraint quote_version_lines_unit_cost_minor_check,
  alter column category drop not null,
  alter column quantity drop not null,
  alter column unit_price_minor drop not null,
  alter column unit_price_minor drop default,
  alter column unit_cost_minor drop not null,
  alter column unit_cost_minor drop default,
  alter column line_total_minor drop not null,
  alter column line_cost_total_minor drop not null,
  add column line_kind text not null default 'priced',
  add column selection_kind text not null default 'required',
  add column package_id uuid,
  add column is_recommended boolean not null default false,
  add constraint quote_version_lines_kind_check check (line_kind in ('priced', 'text', 'heading')),
  add constraint quote_version_lines_selection_check check (
    selection_kind in ('required', 'optional', 'package')
    and ((selection_kind = 'package') = (package_id is not null))
  ),
  add constraint quote_version_lines_shape_check check (
    (
      line_kind = 'priced'
      and category in ('product', 'service')
      and quantity > 0 and quantity <= 1000000
      and unit_price_minor between 0 and 1000000000000
      and unit_cost_minor between 0 and 1000000000000
      and (not is_labor or category = 'service')
    )
    or (
      line_kind in ('text', 'heading')
      and category is null
      and not is_labor
      and quantity is null
      and unit_price_minor is null
      and unit_cost_minor is null
      and not is_taxable
      and selection_kind = 'required'
      and package_id is null
      and not is_recommended
    )
  ),
  add constraint quote_version_lines_recommended_check check (
    not is_recommended or (line_kind = 'priced' and selection_kind = 'optional')
  ),
  add constraint quote_version_lines_package_fk
    foreign key (organization_id, quote_id, quote_version_id, package_id)
    references public.quote_version_packages(organization_id, quote_id, quote_version_id, id)
    on delete restrict,
  add constraint quote_version_lines_image_fk
    foreign key (organization_id, image_attachment_id)
    references public.attachments(organization_id, id)
    on delete set null (image_attachment_id);

create index quote_version_lines_package_idx
  on public.quote_version_lines(organization_id, quote_version_id, package_id, position, id)
  where package_id is not null;

create index quote_version_lines_image_idx
  on public.quote_version_lines(organization_id, image_attachment_id)
  where image_attachment_id is not null;

create table public.quote_version_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  quote_version_id uuid not null,
  attachment_id uuid not null,
  position integer not null check (position >= 0),
  customer_visible boolean not null default false,
  display_name text not null check (char_length(trim(display_name)) between 1 and 255),
  created_at timestamptz not null default now(),
  constraint quote_version_attachments_organization_id_unique unique (organization_id, id),
  constraint quote_version_attachments_version_unique unique (organization_id, quote_version_id, attachment_id),
  constraint quote_version_attachments_version_fk
    foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade,
  constraint quote_version_attachments_attachment_fk
    foreign key (organization_id, attachment_id)
    references public.attachments(organization_id, id) on delete restrict
);

create index quote_version_attachments_version_idx
  on public.quote_version_attachments(organization_id, quote_id, quote_version_id, position, id);

create index quote_version_attachments_attachment_idx
  on public.quote_version_attachments(organization_id, attachment_id);

-- 3. Immutability guards -----------------------------------------------------------------------------------

create or replace function private.reject_published_quote_version_change()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if old.status = 'published' then
    raise exception 'Published quote versions cannot be changed or deleted.' using errcode = 'P0409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function private.reject_published_quote_child_change()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  target_version_id uuid;
begin
  target_version_id := case when tg_op = 'DELETE' then old.quote_version_id else new.quote_version_id end;
  if exists (
    select 1 from public.quote_versions
    where id = target_version_id and status = 'published'
  ) then
    raise exception 'Published quote version content cannot be changed or deleted.' using errcode = 'P0409';
  end if;
  if tg_op = 'UPDATE' and old.quote_version_id is distinct from new.quote_version_id and exists (
    select 1 from public.quote_versions
    where id = old.quote_version_id and status = 'published'
  ) then
    raise exception 'Published quote version content cannot be moved.' using errcode = 'P0409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.reject_published_quote_version_change() from public;
revoke execute on function private.reject_published_quote_version_change() from anon, authenticated;
revoke all on function private.reject_published_quote_child_change() from public;
revoke execute on function private.reject_published_quote_child_change() from anon, authenticated;

create trigger quote_versions_reject_published_change
before update or delete on public.quote_versions
for each row execute function private.reject_published_quote_version_change();

create trigger quote_version_packages_reject_published_change
before insert or update or delete on public.quote_version_packages
for each row execute function private.reject_published_quote_child_change();

create trigger quote_version_lines_reject_published_change
before insert or update or delete on public.quote_version_lines
for each row execute function private.reject_published_quote_child_change();

create trigger quote_version_attachments_reject_published_change
before insert or update or delete on public.quote_version_attachments
for each row execute function private.reject_published_quote_child_change();

-- 4. The one exact calculation contract --------------------------------------------------------------------

create or replace function private.calculate_quote_version(
  target_version_id uuid,
  selected_package_id uuid default null,
  selected_addon_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.quote_versions;
  package_count integer;
  selected_subtotal numeric := 0;
  selected_cost numeric := 0;
  non_taxable_subtotal numeric := 0;
  taxable_subtotal numeric := 0;
  discount_amount numeric := 0;
  non_taxable_discount numeric := 0;
  taxable_discount numeric := 0;
  tax_amount numeric := 0;
  revenue numeric := 0;
  profit numeric := 0;
  margin_bps numeric;
  line_count integer := 0;
  line_result jsonb := '[]'::jsonb;
  current_line record;
  group_total numeric;
  group_discount numeric;
  allocated numeric;
  distributed numeric;
  group_position integer;
  group_remainder integer;
  net_amount numeric;
  line_tax numeric;
begin
  select * into version_row from public.quote_versions where id = target_version_id;
  if version_row.id is null then
    raise exception 'That quote version was not found.' using errcode = 'no_data_found';
  end if;

  select count(*) into package_count
  from public.quote_version_packages
  where organization_id = version_row.organization_id and quote_version_id = version_row.id;

  if package_count > 0 and (
    selected_package_id is null or not exists (
      select 1 from public.quote_version_packages
      where organization_id = version_row.organization_id
        and quote_version_id = version_row.id and id = selected_package_id
    )
  ) then
    raise exception 'Choose one package for this calculation.' using errcode = 'check_violation';
  end if;
  if package_count = 0 and selected_package_id is not null then
    raise exception 'This quote version has no packages.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from unnest(coalesce(selected_addon_ids, '{}'::uuid[])) chosen(id)
    where not exists (
      select 1 from public.quote_version_lines line
      where line.id = chosen.id
        and line.organization_id = version_row.organization_id
        and line.quote_version_id = version_row.id
        and line.line_kind = 'priced' and line.selection_kind = 'optional'
    )
  ) then
    raise exception 'One or more selected add-ons do not belong to this quote version.'
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(line_total_minor), 0), coalesce(sum(line_cost_total_minor), 0),
         coalesce(sum(line_total_minor) filter (where not is_taxable), 0),
         coalesce(sum(line_total_minor) filter (where is_taxable), 0), count(*)
  into selected_subtotal, selected_cost, non_taxable_subtotal, taxable_subtotal, line_count
  from public.quote_version_lines
  where organization_id = version_row.organization_id
    and quote_version_id = version_row.id
    and line_kind = 'priced'
    and (
      selection_kind = 'required'
      or (selection_kind = 'package' and package_id = selected_package_id)
      or (selection_kind = 'optional' and id = any(coalesce(selected_addon_ids, '{}'::uuid[])))
    );

  if selected_subtotal > 9223372036854775807 or selected_cost > 9223372036854775807 then
    raise exception 'The selected quote value is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  if version_row.discount_type = 'fixed' then
    discount_amount := least(version_row.discount_value, selected_subtotal);
  elsif version_row.discount_type = 'percentage' then
    discount_amount := round(selected_subtotal * version_row.discount_value / 10000);
  end if;
  non_taxable_discount := least(discount_amount, non_taxable_subtotal);
  taxable_discount := discount_amount - non_taxable_discount;

  for current_line in
    select id, position, name, is_taxable, line_total_minor, line_cost_total_minor
    from public.quote_version_lines
    where organization_id = version_row.organization_id
      and quote_version_id = version_row.id
      and line_kind = 'priced'
      and (
        selection_kind = 'required'
        or (selection_kind = 'package' and package_id = selected_package_id)
        or (selection_kind = 'optional' and id = any(coalesce(selected_addon_ids, '{}'::uuid[])))
      )
    order by position, id
  loop
    group_total := case when current_line.is_taxable then taxable_subtotal else non_taxable_subtotal end;
    group_discount := case when current_line.is_taxable then taxable_discount else non_taxable_discount end;
    if group_total = 0 or group_discount = 0 then
      allocated := 0;
    else
      allocated := floor(group_discount * current_line.line_total_minor / group_total);
      select coalesce(sum(floor(group_discount * prior.line_total_minor / group_total)), 0), count(*)
      into distributed, group_position
      from public.quote_version_lines prior
      where prior.organization_id = version_row.organization_id
        and prior.quote_version_id = version_row.id
        and prior.line_kind = 'priced'
        and prior.is_taxable = current_line.is_taxable
        and (
          prior.selection_kind = 'required'
          or (prior.selection_kind = 'package' and prior.package_id = selected_package_id)
          or (prior.selection_kind = 'optional' and prior.id = any(coalesce(selected_addon_ids, '{}'::uuid[])))
        )
        and (prior.position, prior.id) <= (current_line.position, current_line.id);
      group_remainder := (group_discount - (
        select coalesce(sum(floor(group_discount * candidate.line_total_minor / group_total)), 0)
        from public.quote_version_lines candidate
        where candidate.organization_id = version_row.organization_id
          and candidate.quote_version_id = version_row.id
          and candidate.line_kind = 'priced'
          and candidate.is_taxable = current_line.is_taxable
          and (
            candidate.selection_kind = 'required'
            or (candidate.selection_kind = 'package' and candidate.package_id = selected_package_id)
            or (candidate.selection_kind = 'optional' and candidate.id = any(coalesce(selected_addon_ids, '{}'::uuid[])))
          )
      ))::integer;
      if group_position <= group_remainder then allocated := allocated + 1; end if;
    end if;
    net_amount := current_line.line_total_minor - allocated;
    line_tax := case when current_line.is_taxable
      then round(net_amount * version_row.tax_rate_basis_points / 10000) else 0 end;
    tax_amount := tax_amount + line_tax;
    line_result := line_result || jsonb_build_array(jsonb_build_object(
      'line_id', current_line.id,
      'gross_minor', current_line.line_total_minor,
      'discount_minor', allocated::bigint,
      'net_minor', net_amount::bigint,
      'tax_minor', line_tax::bigint,
      'total_minor', (net_amount + line_tax)::bigint
    ));
  end loop;

  revenue := selected_subtotal - discount_amount;
  profit := revenue - selected_cost;
  margin_bps := case when revenue = 0 then null else round(profit * 10000 / revenue) end;
  if selected_subtotal - discount_amount + tax_amount > 9223372036854775807 then
    raise exception 'The selected quote total is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  return jsonb_build_object(
    'quote_version_id', version_row.id,
    'selected_package_id', selected_package_id,
    'selected_addon_ids', to_jsonb(coalesce(selected_addon_ids, '{}'::uuid[])),
    'selected_line_count', line_count,
    'subtotal_minor', selected_subtotal::bigint,
    'discount_minor', discount_amount::bigint,
    'tax_minor', tax_amount::bigint,
    'total_minor', (selected_subtotal - discount_amount + tax_amount)::bigint,
    'cost_minor', selected_cost::bigint,
    'profit_minor', profit::bigint,
    'margin_basis_points', margin_bps::bigint,
    'lines', line_result
  );
end;
$$;

revoke all on function private.calculate_quote_version(uuid, uuid, uuid[]) from public;
revoke execute on function private.calculate_quote_version(uuid, uuid, uuid[]) from anon, authenticated;

-- 5. Freeze and clone foundations --------------------------------------------------------------------------

create or replace function public.freeze_quote_version(
  target_quote_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  draft_row public.quote_versions;
  default_package_id uuid;
  default_addon_ids uuid[];
  package_count integer;
  next_version_number integer;
  calculated jsonb;
  canonical jsonb;
  frozen_hash text;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to publish this quote.' using errcode = 'insufficient_privilege';
  end if;
  if quote_row.status <> 'draft' then
    raise exception 'Only a draft quote can be frozen.' using errcode = 'check_violation';
  end if;

  select * into draft_row from public.quote_versions
  where organization_id = quote_row.organization_id and quote_id = quote_row.id and status = 'draft'
  for update;
  if draft_row.id is null then
    raise exception 'This quote has no draft to freeze.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this quote while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  select count(*) into package_count
  from public.quote_version_packages
  where organization_id = quote_row.organization_id and quote_version_id = draft_row.id;
  select id into default_package_id
  from public.quote_version_packages
  where organization_id = quote_row.organization_id and quote_version_id = draft_row.id and is_recommended
  order by position, id limit 1;
  if package_count > 0 and default_package_id is null then
    raise exception 'Choose one recommended package before publishing.' using errcode = 'check_violation';
  end if;
  select coalesce(array_agg(id order by position, id), '{}'::uuid[])
  into default_addon_ids
  from public.quote_version_lines
  where organization_id = quote_row.organization_id and quote_version_id = draft_row.id
    and line_kind = 'priced' and selection_kind = 'optional' and is_recommended;

  calculated := private.calculate_quote_version(draft_row.id, default_package_id, default_addon_ids);
  select coalesce(max(version_number), 0) + 1 into next_version_number
  from public.quote_versions
  where organization_id = quote_row.organization_id and quote_id = quote_row.id and status = 'published';

  canonical := jsonb_build_object(
    'quote', jsonb_build_object('number', quote_row.quote_number, 'title', quote_row.title),
    'version', to_jsonb(draft_row) - array[
      'id','organization_id','quote_id','revision','status','version_number','created_by','created_at',
      'updated_at','published_at','document_hash','calculation','subtotal_minor','discount_minor','tax_minor',
      'total_minor','cost_minor','profit_minor','margin_basis_points'
    ],
    'packages', (select coalesce(jsonb_agg(to_jsonb(package_row) - array[
      'id','organization_id','quote_id','quote_version_id','created_at','updated_at'
    ] order by position, id), '[]'::jsonb)
      from public.quote_version_packages package_row where quote_version_id = draft_row.id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(line_row) - array[
      'id','organization_id','quote_id','quote_version_id','source_catalog_item_id','unit_cost_minor',
      'line_cost_total_minor','created_at','updated_at'
    ] order by position, id), '[]'::jsonb)
      from public.quote_version_lines line_row where quote_version_id = draft_row.id),
    'attachments', (select coalesce(jsonb_agg(to_jsonb(attachment_row) - array[
      'id','organization_id','quote_id','quote_version_id','created_at'
    ] order by position, id), '[]'::jsonb)
      from public.quote_version_attachments attachment_row where quote_version_id = draft_row.id and customer_visible),
    'calculation', calculated
  );
  frozen_hash := encode(extensions.digest(canonical::text, 'sha256'), 'hex');

  update public.quote_versions set
    status = 'published', version_number = next_version_number,
    subtotal_minor = (calculated ->> 'subtotal_minor')::bigint,
    discount_minor = (calculated ->> 'discount_minor')::bigint,
    tax_minor = (calculated ->> 'tax_minor')::bigint,
    total_minor = (calculated ->> 'total_minor')::bigint,
    cost_minor = (calculated ->> 'cost_minor')::bigint,
    profit_minor = (calculated ->> 'profit_minor')::bigint,
    margin_basis_points = (calculated ->> 'margin_basis_points')::bigint,
    calculation = calculated, document_hash = frozen_hash, published_at = now()
  where id = draft_row.id;

  update public.quotes set draft_version_id = null, current_published_version_id = draft_row.id
  where id = quote_row.id;

  return jsonb_build_object(
    'quote_id', quote_row.id, 'quote_version_id', draft_row.id,
    'version_number', next_version_number, 'document_hash', frozen_hash,
    'calculation', calculated
  );
end;
$$;

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
    discount_name, discount_type, discount_value, tax_name, tax_rate_basis_points
  ) values (
    source_row.organization_id, source_row.quote_id, 0, 'draft', source_row.currency_code,
    source_row.client_display_name, source_row.organization_name, source_row.service_address_line1,
    source_row.service_address_line2, source_row.service_city, source_row.service_state_region,
    source_row.service_postal_code, source_row.service_country, source_row.subtotal_minor,
    (select auth.uid()), 1, source_row.contract_disclaimer, source_row.introduction,
    source_row.client_message, source_row.show_quantities, source_row.show_unit_prices,
    source_row.show_line_totals, source_row.show_totals, source_row.discount_name,
    source_row.discount_type, source_row.discount_value, source_row.tax_name, source_row.tax_rate_basis_points
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

  update public.quotes set draft_version_id = new_draft.id where id = quote_row.id;
  return jsonb_build_object('quote_id', quote_row.id, 'quote_version_id', new_draft.id, 'revision', 1);
end;
$$;

revoke all on function public.freeze_quote_version(uuid, integer) from public;
revoke execute on function public.freeze_quote_version(uuid, integer) from anon, authenticated;
revoke all on function public.clone_quote_version_to_draft(uuid) from public;
revoke execute on function public.clone_quote_version_to_draft(uuid) from anon, authenticated;

-- 6. RLS and least-privilege Data API exposure -------------------------------------------------------------

alter table public.quote_version_packages enable row level security;
alter table public.quote_version_attachments enable row level security;

create policy "permitted members can view quote version packages"
on public.quote_version_packages for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));

create policy "permitted members can view quote version attachments"
on public.quote_version_attachments for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));

revoke all on public.quote_version_packages from anon, authenticated;
revoke all on public.quote_version_attachments from anon, authenticated;
grant select on public.quote_version_packages to authenticated;
grant select on public.quote_version_attachments to authenticated;

-- The existing version/line tables remain read-only to members. Every write continues through checked commands.
