-- Invoices Part 5c-1: money fixtures and job-owned records for progress invoicing.
--
-- Two new job-owned collections and the arithmetic that governs one of them. A one-off job either bills as
-- a whole or carries one ordered payment schedule; a recurring per-visit job may customise what a single
-- visit charges for. Neither collection is writable from the browser: the commands that own them arrive in
-- 5c-2 and 5c-5, and every amount here stays behind jobs.view_price exactly as job money already does.

-- 1. A visit is addressable by its job ----------------------------------------------------------------------

-- Visit-owned lines have to name job and visit together so a row can never borrow a visit from another job,
-- the same shape quote_version_schedule_items uses to stay inside one version.
alter table public.job_visits
  add constraint job_visits_job_scoped_unique unique (organization_id, job_id, id);

-- 2. The job's own payment schedule ---------------------------------------------------------------------------

-- Deliberately the same vocabulary as quote_version_schedule_items, so a converted quote is a straight copy.
-- What it adds is the lock: once a stage has produced an invoice it stops being an editable plan and becomes
-- a historical amount, which is what locked_amount_minor records.
create table public.job_payment_schedule_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  position integer not null check (position >= 0),
  description text not null check (char_length(trim(description)) between 2 and 160),
  value_type text not null check (value_type in ('fixed', 'percentage')),
  value bigint not null,
  is_deposit boolean not null default false,
  -- Null while the stage is still a plan. Set by the invoice handoff, at the amount that was actually
  -- billed, so a later job edit can never quietly re-price work a customer has already been invoiced for.
  locked_amount_minor bigint check (locked_amount_minor is null or locked_amount_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_payment_schedule_items_organization_id_unique unique (organization_id, id),
  constraint job_payment_schedule_items_job_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  constraint job_payment_schedule_items_position_unique unique (organization_id, job_id, position),
  constraint job_payment_schedule_items_value_range_check check (
    (value_type = 'percentage' and value between 1 and 10000)
    or (value_type = 'fixed' and value between 1 and 1000000000000)
  )
);

comment on table public.job_payment_schedule_items is
  'A one-off job''s ordered payment stages. Either the job bills as a whole or it carries one schedule of '
  '2 to 12 stages in a single mode that reconciles exactly to the job total. Copied from an approved quote '
  'at conversion and owned by the job from that moment.';

comment on column public.job_payment_schedule_items.locked_amount_minor is
  'The amount this stage was billed at, written when its invoice is created. A stage carrying one is locked.';

-- At most one stage per job carries the quote deposit identity, matching the quote side.
create unique index job_payment_schedule_items_one_deposit_idx
  on public.job_payment_schedule_items(organization_id, job_id)
  where is_deposit;

create index job_payment_schedule_items_job_idx
  on public.job_payment_schedule_items(organization_id, job_id, position, id);

create trigger job_payment_schedule_items_set_updated_at
before update on public.job_payment_schedule_items
for each row execute function public.set_updated_at();

-- A stage that already has an invoice is history. Removal is refused by the invoice_sources foreign key
-- below; this is the other half -- it may not be re-described, re-priced, reordered, or re-locked either.
create or replace function private.job_payment_schedule_items_guard_locked()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1 from public.invoice_sources as source
    where source.organization_id = old.organization_id and source.installment_id = old.id
  ) then
    return new;
  end if;

  if new.description is distinct from old.description
     or new.value_type is distinct from old.value_type
     or new.value is distinct from old.value
     or new.position is distinct from old.position
     or new.is_deposit is distinct from old.is_deposit
     or new.locked_amount_minor is distinct from old.locked_amount_minor then
    raise exception 'A payment stage that already has an invoice cannot be changed.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function private.job_payment_schedule_items_guard_locked() from public;
revoke execute on function private.job_payment_schedule_items_guard_locked() from anon, authenticated;

create trigger job_payment_schedule_items_guard_locked
before update on public.job_payment_schedule_items
for each row execute function private.job_payment_schedule_items_guard_locked();

alter table public.job_payment_schedule_items enable row level security;

create policy "permitted members can view job payment stages"
on public.job_payment_schedule_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

revoke all on public.job_payment_schedule_items from anon, authenticated;

-- Money is not in this grant, the same way it is not in the grant on jobs or job_line_items. A stage's
-- value and billed amount reach a route only through public.job_schedule_money below.
grant select (
  id, organization_id, job_id, position, description, value_type, is_deposit, created_at, updated_at
) on public.job_payment_schedule_items to authenticated;

-- 3. What a single visit actually charges for -------------------------------------------------------------------

-- Only meaningful for a recurring per-visit job. A visit with no rows here bills the job's own lines; a
-- visit with rows carries its complete effective set, snapshotted at the moment it was saved, so omitting a
-- job line is simply not copying it and a later job edit cannot rewrite a visit that has already happened.
create table public.job_visit_line_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  visit_id uuid not null,
  position integer not null check (position >= 0),
  -- Provenance, and the reason a job line can be overridden only once per visit. Not a price source: the
  -- numbers below are this visit's own copy.
  source_job_line_item_id uuid,
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
  constraint job_visit_line_items_organization_id_unique unique (organization_id, id),
  constraint job_visit_line_items_visit_fk foreign key (organization_id, job_id, visit_id)
    references public.job_visits(organization_id, job_id, id) on delete cascade,
  constraint job_visit_line_items_source_line_fk foreign key (organization_id, source_job_line_item_id)
    references public.job_line_items(organization_id, id) on delete set null (source_job_line_item_id),
  constraint job_visit_line_items_image_fk foreign key (organization_id, image_attachment_id)
    references public.attachments(organization_id, id) on delete set null (image_attachment_id),
  constraint job_visit_line_items_position_unique unique (organization_id, visit_id, position),
  constraint job_visit_line_items_source_line_unique
    unique (organization_id, visit_id, source_job_line_item_id),
  constraint job_visit_line_items_shape_check check (
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

comment on table public.job_visit_line_items is
  'One visit''s own effective lines, for recurring per-visit jobs. No rows means the visit bills the job''s '
  'lines unchanged; rows mean this visit''s complete billable set, snapshotted when it was saved.';

create index job_visit_line_items_visit_idx
  on public.job_visit_line_items(organization_id, visit_id, position, id);

create index job_visit_line_items_job_idx
  on public.job_visit_line_items(organization_id, job_id, visit_id);

create index job_visit_line_items_image_idx
  on public.job_visit_line_items(organization_id, image_attachment_id)
  where image_attachment_id is not null;

create index job_visit_line_items_source_line_idx
  on public.job_visit_line_items(organization_id, source_job_line_item_id)
  where source_job_line_item_id is not null;

create trigger job_visit_line_items_set_updated_at
before update on public.job_visit_line_items
for each row execute function public.set_updated_at();

-- The same hundred-line ceiling a job carries, checked once per statement so a bulk copy costs one count.
create or replace function private.job_visit_line_items_enforce_limit()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  offending uuid;
begin
  select item.visit_id into offending
  from public.job_visit_line_items as item
  where item.visit_id in (select distinct inserted.visit_id from inserted)
  group by item.visit_id
  having count(*) > 100
  limit 1;

  if offending is not null then
    raise exception 'A visit can hold up to 100 lines.' using errcode = '54000';
  end if;

  return null;
end;
$$;

revoke all on function private.job_visit_line_items_enforce_limit() from public;
revoke execute on function private.job_visit_line_items_enforce_limit() from anon, authenticated;

create trigger job_visit_line_items_enforce_limit
after insert on public.job_visit_line_items
referencing new table as inserted
for each statement execute function private.job_visit_line_items_enforce_limit();

alter table public.job_visit_line_items enable row level security;

create policy "permitted members can view visit lines"
on public.job_visit_line_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

revoke all on public.job_visit_line_items from anon, authenticated;

grant select (
  id, organization_id, job_id, visit_id, position, source_job_line_item_id, source_catalog_item_id,
  line_kind, category, is_labor, name, description, unit_label, quantity, is_taxable, image_attachment_id,
  created_at, updated_at
) on public.job_visit_line_items to authenticated;

-- 4. An invoice claim names the stage it came from ------------------------------------------------------------

-- The installment number stays: it is part of the frozen source identity a document was written against.
-- The foreign key is what makes the claim a real reference, and what stops a locked stage being deleted.
alter table public.invoice_sources
  add column installment_id uuid,
  add constraint invoice_sources_installment_fk foreign key (organization_id, installment_id)
    references public.job_payment_schedule_items(organization_id, id) on delete restrict,
  drop constraint invoice_sources_shape,
  add constraint invoice_sources_shape check (
    case source_kind
      when 'job_total' then
        visit_id is null and reminder_id is null and installment_number is null and installment_id is null
      when 'visit' then
        visit_id is not null and reminder_id is null and installment_number is null and installment_id is null
      when 'reminder_period' then
        visit_id is null and reminder_id is not null and installment_number is null and installment_id is null
      when 'installment' then
        visit_id is null and reminder_id is null
        and installment_number is not null and installment_id is not null
      else null::boolean
    end
  );

create unique index invoice_sources_installment_id_unique_idx
  on public.invoice_sources(organization_id, installment_id)
  where installment_id is not null;

-- 5. One function owns payment-schedule arithmetic -------------------------------------------------------------

-- Validation and pricing are one answer, so nothing can validate a schedule one way and bill it another.
-- Fixed stages are amounts and must add up to the job total exactly. Percentage stages must add up to 100%
-- and are priced with the same largest-remainder pass the job's discount allocation already uses, so the
-- residual cents land deterministically instead of the whole schedule missing the total by one.
create or replace function private.price_job_payment_schedule(
  target_job_id uuid,
  proposed_items jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  job_row public.jobs;
  source_items jsonb;
  item jsonb;
  item_index integer := 0;
  item_count integer;
  clean_description text;
  clean_value_type text;
  clean_value bigint;
  schedule_mode text;
  basis_points_total bigint;
  priced_items jsonb;
  priced_total bigint;
  locked_row record;
begin
  select * into job_row from public.jobs where id = target_job_id;
  if job_row.id is null then
    raise exception 'That job was not found.' using errcode = 'no_data_found';
  end if;
  if job_row.job_type <> 'one_off' then
    raise exception 'Only a one-off job can carry a payment schedule.' using errcode = 'check_violation';
  end if;

  if proposed_items is null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', stored.id,
      'description', stored.description,
      'type', stored.value_type,
      'value', stored.value
    ) order by stored.position, stored.id), '[]'::jsonb)
    into source_items
    from public.job_payment_schedule_items as stored
    where stored.organization_id = job_row.organization_id
      and stored.job_id = job_row.id;
  else
    source_items := proposed_items;
  end if;

  if jsonb_typeof(source_items) <> 'array' then
    raise exception 'Send the payment schedule as a list.' using errcode = 'check_violation';
  end if;

  item_count := jsonb_array_length(source_items);
  if item_count < 2 then
    raise exception 'A payment schedule needs at least 2 stages.' using errcode = 'check_violation';
  end if;
  if item_count > 12 then
    raise exception 'A payment schedule can hold up to 12 stages.' using errcode = 'check_violation';
  end if;
  -- Percentage stages are a share of the job total and fixed stages have to add up to it, so there is
  -- nothing honest to price until the job has one.
  if job_row.total_minor <= 0 then
    raise exception 'Add priced lines to this job before setting a payment schedule.'
      using errcode = 'check_violation';
  end if;

  for item in select * from jsonb_array_elements(source_items)
  loop
    clean_description := nullif(trim(coalesce(item ->> 'description', '')), '');
    clean_value_type := item ->> 'type';
    clean_value := nullif(item ->> 'value', '')::bigint;

    if clean_description is null or char_length(clean_description) < 2
       or char_length(clean_description) > 160 then
      raise exception 'Stage % needs a description between 2 and 160 characters.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type is null or clean_value_type not in ('fixed', 'percentage') then
      raise exception 'Stage % must be a fixed amount or a percentage.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if schedule_mode is null then
      schedule_mode := clean_value_type;
    elsif schedule_mode <> clean_value_type then
      raise exception 'A payment schedule is either all fixed amounts or all percentages, not a mix.'
        using errcode = 'check_violation';
    end if;
    if clean_value is null or clean_value < 1 then
      raise exception 'Stage % needs an amount above zero.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type = 'percentage' and clean_value > 10000 then
      raise exception 'Stage % cannot be more than 100%%.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type = 'fixed' and clean_value > 1000000000000 then
      raise exception 'Stage % is too large.', item_index + 1 using errcode = 'check_violation';
    end if;

    item_index := item_index + 1;
  end loop;

  if schedule_mode = 'percentage' then
    select coalesce(sum((entry ->> 'value')::bigint), 0) into basis_points_total
    from jsonb_array_elements(source_items) as entry;

    if basis_points_total <> 10000 then
      raise exception 'Percentage stages must add up to 100%%. They currently add up to %.',
        round(basis_points_total / 100.0, 2)::text || '%' using errcode = 'check_violation';
    end if;
  end if;

  with raw as (
    select
      (ord - 1)::integer as position,
      nullif(entry ->> 'id', '')::uuid as item_id,
      nullif(trim(coalesce(entry ->> 'description', '')), '') as description,
      entry ->> 'type' as value_type,
      (entry ->> 'value')::bigint as value
    from jsonb_array_elements(source_items) with ordinality as listed(entry, ord)
  ),
  computed as (
    select raw.*,
      case when raw.value_type = 'fixed'
        then raw.value::numeric
        else floor(job_row.total_minor::numeric * raw.value / 10000)
      end as base_amount,
      case when raw.value_type = 'fixed'
        then 0::numeric
        else job_row.total_minor::numeric * raw.value / 10000
             - floor(job_row.total_minor::numeric * raw.value / 10000)
      end as fractional_part
    from raw
  ),
  spread as (
    select computed.*,
      row_number() over (order by computed.fractional_part desc, computed.position) as remainder_rank,
      job_row.total_minor - sum(computed.base_amount) over () as residual
    from computed
  ),
  allocated as (
    select spread.position, spread.item_id, spread.description, spread.value_type, spread.value,
      (spread.base_amount + case
        when spread.value_type = 'percentage' and spread.remainder_rank <= spread.residual then 1
        else 0
      end)::bigint as amount_minor
    from spread
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'position', allocated.position,
      'installment_id', allocated.item_id,
      'description', allocated.description,
      'value_type', allocated.value_type,
      'value', allocated.value,
      'amount_minor', allocated.amount_minor
    ) order by allocated.position), '[]'::jsonb),
    coalesce(sum(allocated.amount_minor), 0)
  into priced_items, priced_total
  from allocated;

  if priced_total <> job_row.total_minor then
    raise exception
      'The payment stages must add up to the job total. They currently add up to % but the total is %.',
      priced_total, job_row.total_minor using errcode = 'check_violation';
  end if;

  -- Every stage that has already been invoiced has to survive this schedule unchanged, at the amount it was
  -- billed at. A job whose total moved after a stage was invoiced fails here until the remaining stages are
  -- corrected by hand -- nothing is redistributed implicitly.
  for locked_row in
    select stored.id, stored.position, stored.description, stored.value_type, stored.value,
           stored.locked_amount_minor
    from public.job_payment_schedule_items as stored
    where stored.organization_id = job_row.organization_id
      and stored.job_id = job_row.id
      and stored.locked_amount_minor is not null
  loop
    if not exists (
      select 1 from jsonb_array_elements(priced_items) as entry
      where nullif(entry ->> 'installment_id', '')::uuid = locked_row.id
        and entry ->> 'description' = locked_row.description
        and entry ->> 'value_type' = locked_row.value_type
        and (entry ->> 'value')::bigint = locked_row.value
        and (entry ->> 'position')::integer = locked_row.position
    ) then
      raise exception 'A payment stage that already has an invoice cannot be changed or removed.'
        using errcode = 'check_violation';
    end if;

    if not exists (
      select 1 from jsonb_array_elements(priced_items) as entry
      where nullif(entry ->> 'installment_id', '')::uuid = locked_row.id
        and (entry ->> 'amount_minor')::bigint = locked_row.locked_amount_minor
    ) then
      raise exception
        'This schedule no longer bills the stages that are already invoiced at the amounts they were '
        'invoiced for.' using errcode = 'check_violation';
    end if;
  end loop;

  return jsonb_build_object(
    'job_id', job_row.id,
    'mode', schedule_mode,
    'stage_count', item_count,
    'job_total_minor', job_row.total_minor,
    'total_minor', priced_total,
    'items', priced_items
  );
end;
$$;

comment on function private.price_job_payment_schedule(uuid, jsonb) is
  'The one answer for what a job''s payment stages are worth. Called with a proposed list to validate an '
  'edit, or with nothing to price the stages the job already has.';

revoke all on function private.price_job_payment_schedule(uuid, jsonb) from public;
revoke execute on function private.price_job_payment_schedule(uuid, jsonb) from anon, authenticated;

-- 6. The gated readers ------------------------------------------------------------------------------------------

-- One job's payment stages with their money, the same shape and the same permission as public.job_money.
create or replace function public.job_schedule_money(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  priced jsonb;
  answer jsonb;
begin
  select job.organization_id into org from public.jobs as job where job.id = target_job_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  if not private.member_has_permission(org, caller, 'jobs.view_price') then
    return '{}'::jsonb;
  end if;

  -- A job edited after a stage was invoiced can leave the schedule unable to reconcile. That is a real
  -- state the billing screen has to show rather than an error it should die on, so the reader answers with
  -- the stored stages and says the schedule does not reconcile.
  begin
    priced := private.price_job_payment_schedule(target_job_id);
  exception when others then
    priced := null;
  end;

  select jsonb_build_object(
    'reconciles', priced is not null,
    'job_total_minor', (select job.total_minor from public.jobs as job where job.id = target_job_id),
    'stages', coalesce(jsonb_agg(jsonb_build_object(
      'installment_id', stage.id,
      'position', stage.position,
      'value_type', stage.value_type,
      'value', stage.value,
      'locked_amount_minor', stage.locked_amount_minor,
      'amount_minor', coalesce(stage.locked_amount_minor, (
        select (entry ->> 'amount_minor')::bigint
        from jsonb_array_elements(coalesce(priced -> 'items', '[]'::jsonb)) as entry
        where nullif(entry ->> 'installment_id', '')::uuid = stage.id
      ))
    ) order by stage.position, stage.id), '[]'::jsonb)
  )
  into answer
  from public.job_payment_schedule_items as stage
  where stage.organization_id = org and stage.job_id = target_job_id;

  return answer;
end;
$$;

comment on function public.job_schedule_money(uuid) is
  'Money for one job''s payment stages. Needs jobs.view_price; a reader without it gets an empty object.';

revoke all on function public.job_schedule_money(uuid) from public;
revoke execute on function public.job_schedule_money(uuid) from anon;
grant execute on function public.job_schedule_money(uuid) to authenticated;

-- One visit's own lines, keyed by line id, the same shape as public.job_line_money.
create or replace function public.visit_line_money(target_visit_id uuid)
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
  select visit.organization_id into org
  from public.job_visits as visit
  where visit.id = target_visit_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to this visit.' using errcode = 'insufficient_privilege';
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
  from public.job_visit_line_items as item
  where item.organization_id = org
    and item.visit_id = target_visit_id;

  return answer;
end;
$$;

comment on function public.visit_line_money(uuid) is
  'Money for one visit''s own lines, keyed by line id. Prices need jobs.view_price and cost needs '
  'jobs.view_cost; a reader holding neither gets an empty object.';

revoke all on function public.visit_line_money(uuid) from public;
revoke execute on function public.visit_line_money(uuid) from anon;
grant execute on function public.visit_line_money(uuid) to authenticated;

-- 7. Conversion carries the approved schedule -------------------------------------------------------------------

-- Unchanged from the shipped command except for the schedule copy at the end: same locks, same idempotency,
-- same total assertion. A quote's schedule is part of what the customer approved, so it travels with the
-- scope in the same transaction, as a copy the job owns.
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
  copied_stage_count integer := 0;
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

  select * into quote_row from public.quotes where id = target_quote_id for update;

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

  update public.jobs
  set discount_name = version_row.discount_name,
      discount_type = version_row.discount_type,
      discount_value = version_row.discount_value,
      tax_source = version_row.tax_source,
      tax_name = version_row.tax_name,
      tax_rate_basis_points = version_row.tax_rate_basis_points,
      tax_rate_id = version_row.tax_rate_id
  where id = created_job.id;

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

  if (calculated->>'total_minor')::bigint is distinct from version_row.total_minor then
    raise exception 'The job total does not match the approved quote total.' using errcode = 'check_violation';
  end if;

  -- A required deposit on its own is not a payment schedule -- it is one receipt against the approved
  -- quote, and it stays there. Only a real schedule becomes job-owned stages, and only a one-off job can
  -- carry them.
  if version_row.deposit_type = 'schedule' and created_job.job_type = 'one_off' then
    insert into public.job_payment_schedule_items (
      organization_id, job_id, position, description, value_type, value, is_deposit
    )
    select
      created_job.organization_id,
      created_job.id,
      (row_number() over (order by item.position, item.id))::integer - 1,
      item.description,
      item.value_type,
      item.value,
      item.is_deposit
    from public.quote_version_schedule_items as item
    where item.organization_id = quote_row.organization_id
      and item.quote_id = quote_row.id
      and item.quote_version_id = version_row.id;

    get diagnostics copied_stage_count = row_count;

    -- The same promise the total assertion above makes: if the copied stages cannot reconcile with the
    -- job total, the conversion fails loudly instead of leaving a job billing a schedule that does not add up.
    perform private.price_job_payment_schedule(created_job.id);
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
      'line_count', copied_count,
      'payment_stage_count', copied_stage_count
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
    'payment_stage_count', copied_stage_count,
    'quote_id', quote_row.id,
    'quote_status', 'converted'
  );
end;
$$;

comment on function public.convert_quote_to_job(uuid, text, text, text, text, text, text, boolean, text) is
  'The one quote-to-job handoff. Copies the approved version''s selected scope and payment schedule into '
  'job-owned rows, makes the quote terminally converted, and returns the first job again for a retry '
  'carrying the same key.';

-- 8. The quote schedule rule, aligned -----------------------------------------------------------------------------

-- A payment schedule means several invoices, so it needs at least two stages, and mixing a fixed stage with
-- a percentage stage produces a plan nobody can reason about once the total moves. Both are now refused
-- here, matching what a job's schedule enforces. A percentage schedule is checked on its percentages rather
-- than on its rounded amounts, because largest-remainder pricing makes 100% reconcile exactly by
-- construction. deposit_only is untouched: it is one required deposit, not a schedule.
create or replace function public.set_quote_draft_deposit(
  target_quote_id uuid,
  expected_revision integer,
  new_deposit_type text,
  new_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  item jsonb;
  item_index integer := 0;
  item_count integer;
  clean_description text;
  clean_value_type text;
  clean_value bigint;
  item_priced bigint;
  computed_sum bigint := 0;
  schedule_mode text;
  basis_points_total bigint := 0;
begin
  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  if new_deposit_type is not null and new_deposit_type not in ('deposit_only', 'schedule') then
    raise exception 'A deposit is either a single deposit or a payment schedule.'
      using errcode = 'check_violation';
  end if;

  -- Every existing installment is replaced, whether or not a new one takes its place.
  delete from public.quote_version_schedule_items
  where organization_id = draft_row.organization_id
    and quote_version_id = draft_row.id;

  if new_deposit_type is null then
    update public.quote_versions set deposit_type = null where id = draft_row.id;
    return private.bump_quote_draft(draft_row.id);
  end if;

  if new_items is null or jsonb_typeof(new_items) <> 'array' then
    raise exception 'Send the deposit installments as a list.' using errcode = 'check_violation';
  end if;

  item_count := jsonb_array_length(new_items);
  if item_count < 1 then
    raise exception 'Add at least one installment.' using errcode = 'check_violation';
  end if;
  if item_count > 12 then
    raise exception 'A payment schedule can hold up to 12 installments.' using errcode = 'check_violation';
  end if;
  if new_deposit_type = 'deposit_only' and item_count <> 1 then
    raise exception 'A deposit only has one installment.' using errcode = 'check_violation';
  end if;
  if new_deposit_type = 'schedule' and item_count < 2 then
    raise exception 'A payment schedule needs at least 2 installments.' using errcode = 'check_violation';
  end if;
  -- A schedule prices its percentage installments against the quote's current total, so there is nothing
  -- honest to save until the quote has one.
  if new_deposit_type = 'schedule' and draft_row.total_minor <= 0 then
    raise exception 'Add line items to this quote before setting a payment schedule.'
      using errcode = 'check_violation';
  end if;

  for item in select * from jsonb_array_elements(new_items)
  loop
    clean_description := nullif(trim(coalesce(item ->> 'description', '')), '');
    clean_value_type := item ->> 'type';
    clean_value := nullif(item ->> 'value', '')::bigint;

    if clean_description is null or char_length(clean_description) < 2
       or char_length(clean_description) > 160 then
      raise exception 'Installment % needs a description between 2 and 160 characters.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type not in ('fixed', 'percentage') then
      raise exception 'Installment % must be a fixed amount or a percentage.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if new_deposit_type = 'schedule' then
      if schedule_mode is null then
        schedule_mode := clean_value_type;
      elsif schedule_mode <> clean_value_type then
        raise exception 'A payment schedule is either all fixed amounts or all percentages, not a mix.'
          using errcode = 'check_violation';
      end if;
    end if;
    if clean_value is null or clean_value < 1 then
      raise exception 'Installment % needs an amount above zero.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type = 'percentage' and clean_value > 10000 then
      raise exception 'Installment % cannot be more than 100%%.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type = 'fixed' and clean_value > 1000000000000 then
      raise exception 'Installment % is too large.', item_index + 1 using errcode = 'check_violation';
    end if;

    insert into public.quote_version_schedule_items (
      organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
    ) values (
      draft_row.organization_id, draft_row.quote_id, draft_row.id, item_index, clean_description,
      clean_value_type, clean_value, item_index = 0
    );

    if clean_value_type = 'fixed' then
      item_priced := clean_value;
    else
      item_priced := round(draft_row.total_minor * clean_value / 10000);
      basis_points_total := basis_points_total + clean_value;
    end if;
    computed_sum := computed_sum + item_priced;

    item_index := item_index + 1;
  end loop;

  if new_deposit_type = 'schedule' then
    if schedule_mode = 'percentage' then
      if basis_points_total <> 10000 then
        raise exception 'Percentage installments must add up to 100%%. They currently add up to %.',
          round(basis_points_total / 100.0, 2)::text || '%' using errcode = 'check_violation';
      end if;
    elsif computed_sum <> draft_row.total_minor then
      raise exception
        'Installments must add up to the quote total. They currently add up to % but the total is %.',
        computed_sum, draft_row.total_minor using errcode = 'check_violation';
    end if;
  end if;

  update public.quote_versions set deposit_type = new_deposit_type where id = draft_row.id;

  return private.bump_quote_draft(draft_row.id);
end;
$$;
