-- Jobs, Part 5: the job's own scope lines, the arithmetic that owns job money, and the atomic
-- quote-to-job conversion.
--
-- The rule this part exists to make true: a job copies a quote's approved scope, it never points at it.
-- After conversion the quote's history can never rewrite the job's numbers, and editing the job can never
-- rewrite what the customer approved.

-- 1. What a job charges for, beyond its lines --------------------------------------------------------------

-- The same discount and tax shape a quote version carries, because a converted job has to reproduce the
-- approved total exactly, and a job somebody edits afterwards has to keep reproducing its own total from
-- its own configuration rather than from a document it no longer follows.
alter table public.jobs
  add column discount_name text,
  add column discount_type text,
  add column discount_value bigint,
  add column tax_source text not null default 'not_configured'
    check (tax_source in (
      'not_configured', 'business_default', 'property_default', 'saved_rate', 'no_tax', 'custom'
    )),
  add column tax_name text,
  add column tax_rate_basis_points integer not null default 0,
  add column tax_rate_id uuid,
  add constraint jobs_tax_rate_organization_fk foreign key (organization_id, tax_rate_id)
    references public.organization_tax_rates(organization_id, id) on delete set null (tax_rate_id),
  add constraint jobs_discount_name_check check (
    discount_name is null or char_length(trim(discount_name)) between 1 and 80
  ),
  add constraint jobs_discount_check check (
    (discount_type is null and discount_value is null and discount_name is null)
    or (
      discount_type in ('fixed', 'percentage')
      and discount_value between 0 and case when discount_type = 'percentage' then 10000 else 9000000000000000000 end
      and discount_name is not null
    )
  ),
  add constraint jobs_tax_name_check check (
    tax_name is null or char_length(trim(tax_name)) between 1 and 80
  ),
  add constraint jobs_tax_check check (
    tax_rate_basis_points between 0 and 10000
    and ((tax_rate_basis_points = 0 and tax_name is null) or tax_name is not null)
  ),
  -- A tax rate that is later deleted or deactivated never invalidates a job that already froze its name
  -- and percentage, exactly as a quote version does.
  add constraint jobs_tax_source_consistency check (
    case tax_source
      when 'not_configured' then tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null
      when 'no_tax' then tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null
      when 'custom' then tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is null
      when 'saved_rate' then tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is not null
      else
        (tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is not null)
        or (tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null)
    end
  ),
  add constraint jobs_discount_within_subtotal check (discount_minor <= subtotal_minor);

create index jobs_tax_rate_idx on public.jobs(organization_id, tax_rate_id) where tax_rate_id is not null;

-- 2. The job's own scope ------------------------------------------------------------------------------------

-- Deliberately the same vocabulary as quote_version_lines, so conversion is a straight copy that loses
-- nothing: priced product and service rows, plus the text and heading rows that explain the work. What it
-- does not carry is the quote's selling machinery -- optional add-ons and recommendations are a proposal
-- idea, and by the time work is agreed every line is simply part of the job.
create table public.job_line_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  position integer not null check (position >= 0),
  -- A note about where the price came from, never a foreign key: a catalog item disappearing must not
  -- reach into a job's own copy of it.
  source_catalog_item_id uuid,
  line_kind text not null default 'priced' check (line_kind in ('priced', 'text', 'heading')),
  category text,
  is_labor boolean not null default false,
  name text not null check (char_length(trim(name)) between 2 and 160),
  description text check (description is null or char_length(description) <= 2000),
  unit_label text check (unit_label is null or char_length(trim(unit_label)) between 1 and 24),
  quantity numeric(12, 3),
  unit_price_minor bigint,
  unit_cost_minor bigint,
  is_taxable boolean not null default true,
  image_attachment_id uuid,
  line_total_minor bigint
    generated always as (public.pricing_line_total_minor(quantity, unit_price_minor)) stored,
  line_cost_total_minor bigint
    generated always as (public.pricing_line_total_minor(quantity, unit_cost_minor)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_line_items_organization_id_unique unique (organization_id, id),
  constraint job_line_items_job_organization_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_line_items_image_fk foreign key (organization_id, image_attachment_id)
    references public.attachments(organization_id, id) on delete set null (image_attachment_id),
  constraint job_line_items_shape_check check (
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
    )
  )
);

comment on table public.job_line_items is
  'A job''s own copy of the work it covers. Copied from the approved quote version at conversion and owned '
  'by the job from that moment: nothing in the catalog and nothing on the quote can change these numbers '
  'again.';

create index job_line_items_job_idx
  on public.job_line_items(organization_id, job_id, position, id);

create index job_line_items_image_idx
  on public.job_line_items(organization_id, image_attachment_id)
  where image_attachment_id is not null;

create trigger job_line_items_set_updated_at
before update on public.job_line_items
for each row execute function public.set_updated_at();

-- A hundred lines per job, matching Jobber and matching the quote limit the scope was copied from. One
-- statement-level check over the rows the statement actually inserted, so a bulk copy costs one count.
create or replace function private.job_line_items_enforce_limit()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  offending uuid;
begin
  select item.job_id into offending
  from public.job_line_items as item
  where item.job_id in (select distinct inserted.job_id from inserted)
  group by item.job_id
  having count(*) > 100
  limit 1;

  if offending is not null then
    raise exception 'A job can hold up to 100 lines.' using errcode = '54000';
  end if;

  return null;
end;
$$;

revoke all on function private.job_line_items_enforce_limit() from public;
revoke execute on function private.job_line_items_enforce_limit() from anon, authenticated;

create trigger job_line_items_enforce_limit
after insert on public.job_line_items
referencing new table as inserted
for each statement execute function private.job_line_items_enforce_limit();

alter table public.job_line_items enable row level security;

create policy "permitted members can view job lines"
on public.job_line_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

revoke all on public.job_line_items from anon, authenticated;

-- Money is not in this grant, the same way it is not in the grant on jobs. A crew member reads what the
-- work is; price and cost reach a route only through the gated reader below.
grant select (
  id, organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
  name, description, unit_label, quantity, is_taxable, image_attachment_id, created_at, updated_at
) on public.job_line_items to authenticated;

-- 3. One function owns job arithmetic -------------------------------------------------------------------------

-- The quote rules, unchanged and deliberately identical in shape to private.calculate_quote_version: per
-- line exclusive tax after a proportionally allocated discount, one rounding pass, largest-remainder
-- spreading so the allocated parts add back to the whole. No route, screen or document recomputes this.
create or replace function private.calculate_job(target_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  job_row public.jobs;
  line_subtotal numeric := 0;
  line_cost numeric := 0;
  non_taxable_subtotal numeric := 0;
  taxable_subtotal numeric := 0;
  discount_amount numeric := 0;
  non_taxable_discount numeric := 0;
  taxable_discount numeric := 0;
  tax_amount numeric := 0;
  total_amount numeric := 0;
  revenue numeric := 0;
  profit numeric := 0;
  margin_bps numeric;
  line_count integer := 0;
  line_result jsonb := '[]'::jsonb;
begin
  select * into job_row from public.jobs where id = target_job_id;
  if job_row.id is null then
    raise exception 'That job was not found.' using errcode = 'no_data_found';
  end if;

  select coalesce(sum(line_total_minor), 0), coalesce(sum(line_cost_total_minor), 0),
         coalesce(sum(line_total_minor) filter (where not is_taxable), 0),
         coalesce(sum(line_total_minor) filter (where is_taxable), 0), count(*)
  into line_subtotal, line_cost, non_taxable_subtotal, taxable_subtotal, line_count
  from public.job_line_items
  where organization_id = job_row.organization_id
    and job_id = job_row.id
    and line_kind = 'priced';

  if line_subtotal > 1000000000000 or line_cost > 1000000000000 then
    raise exception 'That job value is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  if job_row.discount_type = 'fixed' then
    discount_amount := least(job_row.discount_value, line_subtotal);
  elsif job_row.discount_type = 'percentage' then
    discount_amount := round(line_subtotal * job_row.discount_value / 10000);
  end if;
  non_taxable_discount := least(discount_amount, non_taxable_subtotal);
  taxable_discount := discount_amount - non_taxable_discount;

  with priced as (
    select id, position, is_taxable, line_total_minor
    from public.job_line_items
    where organization_id = job_row.organization_id
      and job_id = job_row.id
      and line_kind = 'priced'
  ),
  shared as (
    select priced.*,
      case when priced.is_taxable then taxable_subtotal else non_taxable_subtotal end as group_total,
      case when priced.is_taxable then taxable_discount else non_taxable_discount end as group_discount,
      row_number() over (partition by priced.is_taxable order by priced.position, priced.id) as group_rank
    from priced
  ),
  rounded as (
    select shared.*,
      case when shared.group_total = 0 or shared.group_discount = 0 then 0
        else floor(shared.group_discount * shared.line_total_minor / shared.group_total)
      end as raw_allocation
    from shared
  ),
  spread as (
    select rounded.*,
      rounded.group_discount - sum(rounded.raw_allocation) over (partition by rounded.is_taxable)
        as group_remainder
    from rounded
  ),
  allocated as (
    select spread.id, spread.position, spread.is_taxable, spread.line_total_minor,
      spread.raw_allocation + case when spread.group_rank <= spread.group_remainder then 1 else 0 end
        as line_discount
    from spread
  ),
  taxed as (
    select allocated.*,
      allocated.line_total_minor - allocated.line_discount as net_amount,
      case when allocated.is_taxable
        then round((allocated.line_total_minor - allocated.line_discount)
          * job_row.tax_rate_basis_points / 10000)
        else 0
      end as line_tax
    from allocated
  )
  select coalesce(sum(line_tax), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'line_id', id,
      'gross_minor', line_total_minor,
      'discount_minor', line_discount::bigint,
      'net_minor', net_amount::bigint,
      'tax_minor', line_tax::bigint,
      'total_minor', (net_amount + line_tax)::bigint
    ) order by position, id), '[]'::jsonb)
  into tax_amount, line_result
  from taxed;

  total_amount := line_subtotal - discount_amount + tax_amount;
  if total_amount > 1000000000000 then
    raise exception 'That job total is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  revenue := line_subtotal - discount_amount;
  profit := revenue - line_cost;
  margin_bps := case when revenue = 0 then null else round(profit * 10000 / revenue) end;

  return jsonb_build_object(
    'job_id', job_row.id,
    'line_count', line_count,
    'subtotal_minor', line_subtotal::bigint,
    'discount_minor', discount_amount::bigint,
    'tax_minor', tax_amount::bigint,
    'total_minor', total_amount::bigint,
    'cost_minor', line_cost::bigint,
    'profit_minor', profit::bigint,
    'margin_basis_points', margin_bps::bigint,
    'lines', line_result
  );
end;
$$;

revoke all on function private.calculate_job(uuid) from public;
revoke execute on function private.calculate_job(uuid) from anon, authenticated;

-- Calculating and storing are one step for every command that changes a job's scope, so they are one
-- function: nothing may write the money columns by hand.
create or replace function private.store_job_money(target_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  calculated jsonb := private.calculate_job(target_job_id);
begin
  update public.jobs
  set subtotal_minor = (calculated->>'subtotal_minor')::bigint,
      discount_minor = (calculated->>'discount_minor')::bigint,
      tax_minor = (calculated->>'tax_minor')::bigint,
      total_minor = (calculated->>'total_minor')::bigint,
      cost_minor = (calculated->>'cost_minor')::bigint
  where id = target_job_id;

  return calculated;
end;
$$;

revoke all on function private.store_job_money(uuid) from public;
revoke execute on function private.store_job_money(uuid) from anon, authenticated;

-- 4. The gated reader for line money --------------------------------------------------------------------------

-- One job's lines, keyed by line id, the same shape as public.quote_line_money.
create or replace function public.job_line_money(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  select job.organization_id into org
  from public.jobs as job
  where job.id = target_job_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(org, caller, 'jobs.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(item.id::text,
      (case when can_price then jsonb_build_object(
         'unit_price_minor', item.unit_price_minor,
         'line_total_minor', item.line_total_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'unit_cost_minor', item.unit_cost_minor,
         'line_cost_total_minor', item.line_cost_total_minor
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.job_line_items as item
  where item.organization_id = org
    and item.job_id = target_job_id;

  return answer;
end;
$$;

comment on function public.job_line_money(uuid) is
  'Money for one job''s lines, keyed by line id. Prices need jobs.view_price and cost needs jobs.view_cost; '
  'a reader holding neither gets an empty object.';

revoke all on function public.job_line_money(uuid) from public;
revoke execute on function public.job_line_money(uuid) from anon;
grant execute on function public.job_line_money(uuid) to authenticated;

-- The discount and tax a total was built from are part of reading that total, so they travel with it under
-- the same permission rather than sitting on the table for anyone with jobs.view.
create or replace function public.job_money(target_job_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  if target_job_ids is null or cardinality(target_job_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct job.organization_id) into organizations
  from public.jobs as job
  where job.id = any(target_job_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those jobs do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to these jobs.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(org, caller, 'jobs.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(job.id::text,
      (case when can_price then jsonb_build_object(
         'subtotal_minor', job.subtotal_minor,
         'discount_minor', job.discount_minor,
         'discount_name', job.discount_name,
         'discount_type', job.discount_type,
         'discount_value', job.discount_value,
         'tax_minor', job.tax_minor,
         'tax_name', job.tax_name,
         'tax_rate_basis_points', job.tax_rate_basis_points,
         'total_minor', job.total_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'cost_minor', job.cost_minor,
         'profit_minor', job.total_minor - job.tax_minor - job.cost_minor
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.jobs as job
  where job.organization_id = org
    and job.id = any(target_job_ids);

  return answer;
end;
$$;

revoke all on function public.job_money(uuid[]) from public;
revoke execute on function public.job_money(uuid[]) from anon;
grant execute on function public.job_money(uuid[]) to authenticated;

-- 5. Quote to job, in one transaction ---------------------------------------------------------------------------

-- The Quote contract owns this command and the Jobs contract owns what it produces, so it locks the quote,
-- checks its own readiness with the same function the quote screens read, and then calls private.create_job
-- for the row itself. Everything commits together or nothing does.
create or replace function public.convert_quote_to_job(
  target_quote_id uuid,
  idempotency_key text,
  request_hash text,
  new_job_type text default 'one_off',
  new_price_basis text default null,
  new_title text default null,
  new_billing_timing text default 'on_closure',
  new_is_as_needed boolean default false,
  new_instructions text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
  existing_job public.jobs;
  created_job public.jobs;
  chosen_addons uuid[];
  resolved_basis text;
  resolved_title text;
  copied_count integer;
  calculated jsonb;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(request_hash, ''))) < 1 then
    raise exception 'A quote fingerprint is required.' using errcode = 'check_violation';
  end if;
  if new_job_type not in ('one_off', 'recurring') then
    raise exception 'A job is either one-off or recurring.' using errcode = 'check_violation';
  end if;

  -- Quote first, then its approved version: the same order every other quote command locks in, so two
  -- conversions racing queue behind each other instead of deadlocking.
  select * into quote_row from public.quotes where id = target_quote_id for update;

  -- One answer for "no such quote" and "not your quote". Conversion needs both halves of the handoff:
  -- permission to convert the quote and permission to start a job.
  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.convert'
     )
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'jobs.create'
     ) then
    raise exception 'You do not have access to turn this quote into a job.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotency is checked before state, so a retry arriving after the first call succeeded is recognised
  -- as the same command rather than refused as "already converted".
  select * into existing_job
  from public.jobs
  where organization_id = quote_row.organization_id
    and quote_id = target_quote_id
  for update;

  if found then
    if existing_job.conversion_idempotency_key is not distinct from idempotency_key
       and existing_job.conversion_request_hash is not distinct from request_hash then
      return jsonb_build_object(
        'applied', false,
        'job_id', existing_job.id,
        'job_number', existing_job.job_number,
        'quote_id', quote_row.id,
        'quote_status', quote_row.status
      );
    end if;

    raise exception 'This quote already has a job.' using errcode = 'P0409';
  end if;

  if quote_row.status <> 'approved' then
    raise exception 'Only an approved quote can become a job.' using errcode = 'check_violation';
  end if;

  -- The deposit gate, read from the one function that already answers it for the quote screens rather
  -- than derived a second time here.
  if not public.quote_ready_for_job(target_quote_id) then
    raise exception 'This quote is not ready for a job yet.' using errcode = 'check_violation';
  end if;

  select * into version_row
  from public.quote_versions
  where organization_id = quote_row.organization_id
    and id = quote_row.current_published_version_id
  for update;

  if version_row.id is null then
    raise exception 'This quote has no approved version to copy.' using errcode = 'check_violation';
  end if;

  resolved_basis := coalesce(
    new_price_basis,
    case when new_job_type = 'one_off' then 'job_total' else 'per_visit' end
  );
  resolved_title := coalesce(nullif(trim(coalesce(new_title, '')), ''), quote_row.title);

  created_job := private.create_job(
    quote_row.organization_id,
    quote_row.client_id,
    quote_row.property_id,
    resolved_title,
    new_job_type,
    resolved_basis,
    quote_row.currency_code,
    (select auth.uid()),
    coalesce(new_is_as_needed, false),
    coalesce(new_billing_timing, 'on_closure'),
    new_instructions,
    quote_row.id,
    version_row.id,
    idempotency_key,
    request_hash
  );

  -- The approved document's discount and tax become the job's own, which is what makes the opening total
  -- match without copying the total itself.
  update public.jobs
  set discount_name = version_row.discount_name,
      discount_type = version_row.discount_type,
      discount_value = version_row.discount_value,
      tax_source = version_row.tax_source,
      tax_name = version_row.tax_name,
      tax_rate_basis_points = version_row.tax_rate_basis_points,
      tax_rate_id = version_row.tax_rate_id
  where id = created_job.id;

  -- What the customer actually agreed to: every required line, plus the optional add-ons the frozen
  -- calculation recorded as selected. Copies, renumbered from zero, never references.
  select coalesce(array_agg((chosen.value #>> '{}')::uuid), '{}'::uuid[])
  into chosen_addons
  from jsonb_array_elements(
    case
      when jsonb_typeof(version_row.calculation->'selected_addon_ids') = 'array'
        then version_row.calculation->'selected_addon_ids'
      else '[]'::jsonb
    end
  ) as chosen(value);

  insert into public.job_line_items (
    organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_attachment_id
  )
  select
    created_job.organization_id,
    created_job.id,
    (row_number() over (order by line.position, line.id))::integer - 1,
    line.source_catalog_item_id,
    line.line_kind,
    line.category,
    line.is_labor,
    line.name,
    line.description,
    line.unit_label,
    line.quantity,
    line.unit_price_minor,
    line.unit_cost_minor,
    line.is_taxable,
    line.image_attachment_id
  from public.quote_version_lines as line
  where line.organization_id = quote_row.organization_id
    and line.quote_id = quote_row.id
    and line.quote_version_id = version_row.id
    and (line.selection_kind = 'required' or line.id = any(chosen_addons));

  get diagnostics copied_count = row_count;

  calculated := private.store_job_money(created_job.id);

  -- The contract's promise, enforced rather than assumed: a converted job opens on the approved total. If
  -- these ever disagree the two calculators have drifted, and the conversion must fail loudly instead of
  -- quietly billing a different number than the customer approved.
  if (calculated->>'total_minor')::bigint is distinct from version_row.total_minor then
    raise exception 'The job total does not match the approved quote total.' using errcode = 'check_violation';
  end if;

  update public.quotes set status = 'converted' where id = quote_row.id;

  insert into public.job_events (
    organization_id, job_id, event_type, actor_id, new_status, related_quote_id, metadata
  ) values (
    created_job.organization_id,
    created_job.id,
    'job_converted_from_quote',
    (select auth.uid()),
    'active',
    quote_row.id,
    jsonb_build_object(
      'quote_number', quote_row.quote_number,
      'quote_version_number', version_row.version_number,
      'line_count', copied_count
    )
  );

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.converted',
    'Turned this quote into a job',
    (select auth.uid()),
    jsonb_build_object(
      'job_number', created_job.job_number,
      'version_number', version_row.version_number,
      'line_count', copied_count
    )
  );

  return jsonb_build_object(
    'applied', true,
    'job_id', created_job.id,
    'job_number', created_job.job_number,
    'job_type', created_job.job_type,
    'price_basis', created_job.price_basis,
    'line_count', copied_count,
    'quote_id', quote_row.id,
    'quote_status', 'converted'
  );
end;
$$;

comment on function public.convert_quote_to_job(uuid, text, text, text, text, text, text, boolean, text) is
  'The one quote-to-job handoff. Copies the approved version''s selected scope into job-owned lines, makes '
  'the quote terminally converted, and returns the first job again for a retry carrying the same key.';

revoke all on function public.convert_quote_to_job(uuid, text, text, text, text, text, text, boolean, text)
  from public;
revoke execute on function public.convert_quote_to_job(uuid, text, text, text, text, text, text, boolean, text)
  from anon;
grant execute on function public.convert_quote_to_job(uuid, text, text, text, text, text, text, boolean, text)
  to authenticated;
