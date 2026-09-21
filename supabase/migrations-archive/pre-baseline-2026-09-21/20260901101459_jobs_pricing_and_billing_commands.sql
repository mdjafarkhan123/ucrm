-- Jobs Part 11a: pricing a job after it exists.
--
-- Parts 4-10 gave a job its scope at creation and then froze it. Nothing could change a line, a price, the
-- price basis or the invoicing timing once the job was saved, and a job created directly could never carry
-- tax at all. This migration adds the four commands the job's money screen needs, each the twin of the quote
-- command that already does the same job on a draft version:
--
--   replace_job_line_items  ~ replace_quote_version_lines
--   set_job_billing         ~ (no quote twin: price basis and invoicing timing are job-only decisions)
--   set_job_discount        ~ set_quote_draft_discount
--   set_job_tax             ~ set_quote_draft_tax
--
-- All four share one lock helper so the permission check, the row lock and the optimistic-revision check are
-- written once and cannot drift apart. None of them recomputes money in SQL of its own: private.calculate_job
-- stays the single owner of job arithmetic, exactly as the contract requires.
--
-- Deliberately not here: invoice reminders (11b), payment installments and per-visit quantities (11c), and
-- any rule about editing a *closed* job -- closing does not exist yet and Part 13 owns its consequences.

-- One door for every staged job edit. Proves the caller is signed in, holds jobs.edit in this organization,
-- and is editing the revision it was shown; locks the row so the revision checked is the revision written.
create or replace function private.lock_job_for_edit(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer
)
returns public.jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
begin
  if caller is null then
    raise exception 'You must be signed in to edit a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id = target_job_id
  for update;

  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  if current_job.revision is distinct from expected_revision then
    raise exception 'Someone else changed this job. Reload to see the latest.' using errcode = 'P0409';
  end if;

  return current_job;
end;
$$;

comment on function private.lock_job_for_edit(uuid, uuid, integer) is
  'Shared entry check for every staged job edit: jobs.edit, row lock, and a stale revision refused as P0409.';

revoke all on function private.lock_job_for_edit(uuid, uuid, integer) from public;

-- The whole scope in one call, the same all-or-nothing replacement the quote lines command performs. The
-- 100-line cap is the table's own trigger and the shape of each line is the table's own constraint, so this
-- inserts and lets the table refuse what it must.
create or replace function public.replace_job_line_items(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  line_count integer;
begin
  current_job := private.lock_job_for_edit(target_organization_id, target_job_id, expected_revision);

  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'The job scope must be a list of lines.' using errcode = 'check_violation';
  end if;

  delete from public.job_line_items
  where organization_id = target_organization_id
    and job_id = target_job_id;

  insert into public.job_line_items (
    organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_attachment_id
  )
  select
    target_organization_id,
    target_job_id,
    (row_number() over (order by (line.value->>'position')::integer, ordinality) - 1)::integer,
    nullif(line.value->>'source_catalog_item_id', '')::uuid,
    coalesce(line.value->>'line_kind', 'priced'),
    nullif(line.value->>'category', ''),
    coalesce((line.value->>'is_labor')::boolean, false),
    line.value->>'name',
    nullif(line.value->>'description', ''),
    nullif(line.value->>'unit_label', ''),
    (line.value->>'quantity')::numeric,
    (line.value->>'unit_price_minor')::bigint,
    (line.value->>'unit_cost_minor')::bigint,
    coalesce((line.value->>'is_taxable')::boolean, true),
    nullif(line.value->>'image_attachment_id', '')::uuid
  from jsonb_array_elements(new_lines) with ordinality as line(value, ordinality);

  get diagnostics line_count = row_count;

  perform private.store_job_money(target_job_id);

  update public.jobs
  set revision = current_job.revision + 1
  where organization_id = target_organization_id
    and id = target_job_id;

  -- Redacted metadata: how many lines the job now carries, never what they say or what they cost.
  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'scope_updated',
    caller,
    jsonb_build_object('line_count', line_count)
  );

  return jsonb_build_object('revision', current_job.revision + 1, 'line_count', line_count);
end;
$$;

comment on function public.replace_job_line_items(uuid, uuid, integer, jsonb) is
  'Replaces a job''s whole scope in one transaction, recalculates its money through private.calculate_job, '
  'bumps revision and appends a scope_updated history row.';

revoke all on function public.replace_job_line_items(uuid, uuid, integer, jsonb) from public;
revoke execute on function public.replace_job_line_items(uuid, uuid, integer, jsonb) from anon;
grant execute on function public.replace_job_line_items(uuid, uuid, integer, jsonb) to authenticated;

-- The two billing decisions the contract insists on keeping apart: how the work is priced, and when we
-- remind ourselves to invoice. Collecting the money is a third decision and belongs to Payments; nothing
-- here enables a charge. The table's own constraint refuses a basis that contradicts the job's type.
create or replace function public.set_job_billing(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_price_basis text,
  new_billing_timing text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  clean_basis text := nullif(trim(coalesce(new_price_basis, '')), '');
  clean_timing text := nullif(trim(coalesce(new_billing_timing, '')), '');
  changed text[] := array[]::text[];
begin
  current_job := private.lock_job_for_edit(target_organization_id, target_job_id, expected_revision);

  clean_basis := coalesce(clean_basis, current_job.price_basis);
  clean_timing := coalesce(clean_timing, current_job.billing_timing);

  -- Said in the words of the choice the person made, before the table says it in the words of a constraint.
  if current_job.job_type = 'one_off' and clean_basis <> 'job_total' then
    raise exception 'A one-off job is priced as a whole job.' using errcode = 'check_violation';
  end if;
  if current_job.job_type = 'recurring' and clean_basis not in ('per_visit', 'fixed_per_period') then
    raise exception 'Repeating work is priced per visit or per billing period.' using errcode = 'check_violation';
  end if;
  if clean_timing not in ('on_closure', 'per_completed_visit', 'month_end', 'custom_dates', 'manual') then
    raise exception 'Choose when this job should be invoiced.' using errcode = 'check_violation';
  end if;

  if clean_basis is distinct from current_job.price_basis then
    changed := array_append(changed, 'price_basis');
  end if;
  if clean_timing is distinct from current_job.billing_timing then
    changed := array_append(changed, 'billing_timing');
  end if;

  update public.jobs
  set price_basis = clean_basis,
      billing_timing = clean_timing,
      revision = current_job.revision + 1
  where organization_id = target_organization_id
    and id = target_job_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'billing_updated',
    caller,
    jsonb_build_object(
      'changed', to_jsonb(changed),
      'price_basis', clean_basis,
      'billing_timing', clean_timing
    )
  );

  return jsonb_build_object(
    'revision', current_job.revision + 1,
    'price_basis', clean_basis,
    'billing_timing', clean_timing
  );
end;
$$;

comment on function public.set_job_billing(uuid, uuid, integer, text, text) is
  'Sets a job''s price basis and invoicing timing. Never enables a charge: collection belongs to Payments.';

revoke all on function public.set_job_billing(uuid, uuid, integer, text, text) from public;
revoke execute on function public.set_job_billing(uuid, uuid, integer, text, text) from anon;
grant execute on function public.set_job_billing(uuid, uuid, integer, text, text) to authenticated;

-- One discount on the job, named the way the customer will read it. A null type removes it.
create or replace function public.set_job_discount(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_name text,
  new_type text,
  new_value bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  clean_type text := nullif(trim(coalesce(new_type, '')), '');
  clean_name text := nullif(trim(coalesce(new_name, '')), '');
begin
  current_job := private.lock_job_for_edit(target_organization_id, target_job_id, expected_revision);

  if clean_type is null then
    update public.jobs
    set discount_name = null, discount_type = null, discount_value = null
    where organization_id = target_organization_id and id = target_job_id;
  else
    if clean_type not in ('fixed', 'percentage') then
      raise exception 'A discount is either a fixed amount or a percentage.' using errcode = 'check_violation';
    end if;
    if clean_name is null then
      raise exception 'Give this discount a name the customer will recognize.' using errcode = 'check_violation';
    end if;
    if coalesce(new_value, 0) < 0 then
      raise exception 'A discount cannot be negative.' using errcode = 'check_violation';
    end if;
    if clean_type = 'percentage' and coalesce(new_value, 0) > 10000 then
      raise exception 'A percentage discount is between 0 and 100 percent.' using errcode = 'check_violation';
    end if;

    update public.jobs
    set discount_name = clean_name, discount_type = clean_type, discount_value = coalesce(new_value, 0)
    where organization_id = target_organization_id and id = target_job_id;
  end if;

  perform private.store_job_money(target_job_id);

  update public.jobs
  set revision = current_job.revision + 1
  where organization_id = target_organization_id and id = target_job_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'discount_updated',
    caller,
    jsonb_build_object('removed', clean_type is null, 'discount_type', clean_type)
  );

  return jsonb_build_object('revision', current_job.revision + 1);
end;
$$;

comment on function public.set_job_discount(uuid, uuid, integer, text, text, bigint) is
  'Sets or removes the job''s single discount and recalculates its money. A null type removes the discount.';

revoke all on function public.set_job_discount(uuid, uuid, integer, text, text, bigint) from public;
revoke execute on function public.set_job_discount(uuid, uuid, integer, text, text, bigint) from anon;
grant execute on function public.set_job_discount(uuid, uuid, integer, text, text, bigint) to authenticated;

-- Tax on the job, resolved the same five ways a quote resolves it, through the same helper. A job's own
-- constraint keeps a one-off custom rate unlinked from the shared list, so a custom rate saved for reuse is
-- created here but the job still records that it was priced as a one-off.
create or replace function public.set_job_tax(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_source text,
  new_rate_id uuid default null,
  new_custom_name text default null,
  new_custom_rate_basis_points integer default null,
  save_as_reusable boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  rate_row public.organization_tax_rates;
  resolved_tax record;
  clean_name text;
  clean_rate integer;
begin
  current_job := private.lock_job_for_edit(target_organization_id, target_job_id, expected_revision);

  if new_source not in ('business_default', 'property_default', 'saved_rate', 'no_tax', 'custom') then
    raise exception 'Choose a tax option.' using errcode = 'check_violation';
  end if;

  if new_source in ('business_default', 'property_default') then
    select * into resolved_tax
    from private.resolve_property_tax(target_organization_id, current_job.property_id);

    update public.jobs
    set tax_source = resolved_tax.source, tax_name = resolved_tax.name,
        tax_rate_basis_points = resolved_tax.rate_basis_points, tax_rate_id = resolved_tax.rate_id
    where organization_id = target_organization_id and id = target_job_id;

  elsif new_source = 'saved_rate' then
    select * into rate_row
    from public.organization_tax_rates
    where id = new_rate_id and organization_id = target_organization_id and is_active;

    if rate_row.id is null then
      raise exception 'Choose an active saved tax rate.' using errcode = 'check_violation';
    end if;

    update public.jobs
    set tax_source = 'saved_rate', tax_name = rate_row.name,
        tax_rate_basis_points = rate_row.rate_basis_points, tax_rate_id = rate_row.id
    where organization_id = target_organization_id and id = target_job_id;

  elsif new_source = 'no_tax' then
    update public.jobs
    set tax_source = 'no_tax', tax_name = null, tax_rate_basis_points = 0, tax_rate_id = null
    where organization_id = target_organization_id and id = target_job_id;

  else -- custom
    clean_rate := coalesce(new_custom_rate_basis_points, 0);
    if clean_rate <= 0 or clean_rate > 10000 then
      raise exception 'A tax rate is between 0 and 100 percent.' using errcode = 'check_violation';
    end if;

    clean_name := nullif(trim(coalesce(new_custom_name, '')), '');
    if clean_name is null or char_length(clean_name) > 80 then
      raise exception 'Give this tax a name the customer will recognize, under 80 characters.'
        using errcode = 'check_violation';
    end if;

    if coalesce(save_as_reusable, false) then
      if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
        raise exception 'You do not have access to save a reusable tax rate.'
          using errcode = 'insufficient_privilege';
      end if;

      insert into public.organization_tax_rates (
        organization_id, name, rate_basis_points, created_by, updated_by
      ) values (target_organization_id, clean_name, clean_rate, caller, caller);
    end if;

    update public.jobs
    set tax_source = 'custom', tax_name = clean_name, tax_rate_basis_points = clean_rate,
        tax_rate_id = null
    where organization_id = target_organization_id and id = target_job_id;
  end if;

  perform private.store_job_money(target_job_id);

  update public.jobs
  set revision = current_job.revision + 1
  where organization_id = target_organization_id and id = target_job_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'tax_updated',
    caller,
    jsonb_build_object('source', new_source)
  );

  return jsonb_build_object('revision', current_job.revision + 1);
end;
$$;

comment on function public.set_job_tax(uuid, uuid, integer, text, uuid, text, integer, boolean) is
  'Resolves the job''s tax from the business or property default, a saved rate, no tax, or a one-off custom '
  'rate, then recalculates its money. Saving a custom rate for reuse needs settings.taxes.manage.';

revoke all on function public.set_job_tax(uuid, uuid, integer, text, uuid, text, integer, boolean) from public;
revoke execute on function public.set_job_tax(uuid, uuid, integer, text, uuid, text, integer, boolean) from anon;
grant execute on function public.set_job_tax(uuid, uuid, integer, text, uuid, text, integer, boolean) to authenticated;

notify pgrst, 'reload schema';
