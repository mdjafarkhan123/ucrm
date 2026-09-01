-- Jobs Part 7: direct one-off job creation, and the visits a job is done on.
--
-- Part 5 gave a job its scope and the quote-to-job handoff. This part gives the office the other way in:
-- starting a one-off job from scratch, with the one or more appointments it will be done on, in one
-- transaction. A visit is the appointment; the job is still the agreement. Nothing here writes money the
-- reader is not entitled to, and members may read visits but only the create command may write them.

-- 1. The appointments a job is done on ---------------------------------------------------------------------

-- A visit has one of three schedule shapes, and the shape is read off the row rather than stored as a label:
--   * scheduled   -- a date and a start time (end optional)
--   * anytime     -- a date, no promised time (all_day)
--   * unscheduled -- no date yet, backlog work that still needs one
-- The clock passing never writes a row: a visit stores only its own fields plus completed_at.
create table public.job_visits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null,
  -- Order in the job's own list of visits, assigned by the create flow. Not a calendar order.
  position integer not null check (position >= 0),
  -- Null date is the backlog shape. A date with no start_time is the anytime shape. A date with a start_time
  -- is a booked appointment.
  visit_date date,
  start_time time,
  end_time time,
  -- Jobber's arrival-window state: the day is promised, the hour is not.
  all_day boolean not null default false,
  title text check (title is null or char_length(trim(title)) between 1 and 160),
  instructions text check (instructions is null or char_length(instructions) <= 2000),
  -- Where this visit came from. Direct creation and the create-visits modal both make manual visits;
  -- generation, return visits and duplication arrive with later parts but the vocabulary is fixed now.
  source text not null default 'manual' check (source in ('manual', 'generated', 'return', 'duplicated')),
  -- Null means not complete. One timestamp, never a boolean that can disagree with it.
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_visits_organization_id_unique unique (organization_id, id),
  constraint job_visits_job_organization_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  -- A timed visit must have a date to be timed on. This is the contract's "a timed Visit without a date"
  -- guard.
  constraint job_visits_timed_needs_date check (start_time is null or visit_date is not null),
  -- An end without a start is meaningless, and an end that is not after the start is a typo, not a visit.
  constraint job_visits_time_order check (
    end_time is null or (start_time is not null and end_time > start_time)
  ),
  -- Anytime is a day with no clock time, so it can carry neither a start nor an end, and it needs a date to
  -- be anytime on.
  constraint job_visits_all_day_no_time check (not all_day or (start_time is null and end_time is null)),
  constraint job_visits_all_day_needs_date check (not all_day or visit_date is not null),
  -- The stamp and its author travel together: a completed visit knows who completed it, an open one claims
  -- neither.
  constraint job_visits_completed_pairing check ((completed_at is null) = (completed_by is null))
);

comment on table public.job_visits is
  'One occurrence of doing a job''s work. Scheduled, anytime or unscheduled is read off visit_date and '
  'start_time, never stored. Members read this table; only the job commands write it.';

-- The Schedule's bounded date-window read (Part 9) and any per-job visit list both start from the
-- organization and walk by date, so incomplete work of a day is found without scanning a tenant.
create index job_visits_calendar_idx
  on public.job_visits(organization_id, visit_date)
  where completed_at is null;

create index job_visits_job_idx on public.job_visits(organization_id, job_id, position, id);
create index job_visits_completed_by_idx on public.job_visits(completed_by) where completed_by is not null;

create trigger job_visits_set_updated_at
before update on public.job_visits
for each row execute function public.set_updated_at();

-- 2. Who is going -------------------------------------------------------------------------------------------

-- The same shape assessment_assignees uses: a member per visit, tenant-safe by composite foreign key so a
-- visit can never be assigned to someone from another organization.
create table public.job_visit_assignments (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  visit_id uuid not null,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (visit_id, user_id),
  constraint job_visit_assignments_visit_organization_fk foreign key (organization_id, visit_id)
    references public.job_visits(organization_id, id) on delete cascade,
  constraint job_visit_assignments_member_fk foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade
);

create index job_visit_assignments_organization_user_idx
  on public.job_visit_assignments(organization_id, user_id);
create index job_visit_assignments_visit_idx on public.job_visit_assignments(visit_id);

-- 3. The command receipt log --------------------------------------------------------------------------------

-- A direct create has no natural unique key the way a conversion has its quote, so an unlucky double-submit
-- would make two jobs. This is the general idempotency ledger the contract names: an identical retry returns
-- the first job, and a changed payload under the same key is a conflict rather than a silent second job.
create table public.job_command_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  action text not null check (char_length(trim(action)) between 2 and 64),
  idempotency_key text not null check (char_length(trim(idempotency_key)) >= 8),
  request_hash text not null check (char_length(trim(request_hash)) >= 1),
  -- Filled in the same transaction that does the work, so a receipt only ever carries a committed result.
  result jsonb,
  created_at timestamptz not null default now(),
  constraint job_command_receipts_unique unique (organization_id, action, idempotency_key)
);

comment on table public.job_command_receipts is
  'Idempotency ledger for job commands with no other natural key. One row per (organization, action, key); '
  'a retry carrying the same key and request hash returns the first result.';

-- 4. Row level security -------------------------------------------------------------------------------------

alter table public.job_visits enable row level security;
alter table public.job_visit_assignments enable row level security;
alter table public.job_command_receipts enable row level security;

create policy "permitted members can view job visits"
on public.job_visits for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

create policy "permitted members can view job visit assignments"
on public.job_visit_assignments for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

-- Members never read the receipt log; it is bookkeeping for the commands, not a screen. No select policy is
-- created, so with RLS on the table no authenticated row is visible.

-- Ordinary clients read visits and assignments and write neither. The create command is the only writer, and
-- it is security definer, so it does not need a grant here.
revoke all on public.job_visits from anon, authenticated;
revoke all on public.job_visit_assignments from anon, authenticated;
revoke all on public.job_command_receipts from anon, authenticated;

grant select on public.job_visits to authenticated;
grant select on public.job_visit_assignments to authenticated;

-- 5. The one direct-create command --------------------------------------------------------------------------

-- One one-off job, its scope lines, and its one-to-twenty visits, in one transaction. Mirrors
-- public.convert_quote_to_job: check permission, check idempotency, do the work under the job's own guards,
-- store the money once, and return the same job again for a retry carrying the same key.
create or replace function public.create_job_with_visits(
  target_organization_id uuid,
  target_client_id uuid,
  target_property_id uuid,
  new_title text,
  new_instructions text,
  invoice_on_close boolean,
  scope_lines jsonb,
  visits jsonb,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  receipt_id uuid;
  existing_receipt public.job_command_receipts;
  organization_currency text;
  created_job public.jobs;
  visit_element jsonb;
  new_visit public.job_visits;
  assignee_element jsonb;
  visit_count integer;
  line_count integer;
  calculated jsonb;
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to create a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.create') then
    raise exception 'You do not have access to create a job here.'
      using errcode = 'insufficient_privilege';
  end if;

  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A job fingerprint is required.' using errcode = 'check_violation';
  end if;

  visit_count := coalesce(jsonb_array_length(visits), 0);
  if visit_count < 1 or visit_count > 20 then
    raise exception 'A one-off job is created with between 1 and 20 visits.' using errcode = 'check_violation';
  end if;

  -- Claim the idempotency key before doing any work. on conflict do nothing waits for a racing transaction
  -- to commit and then returns no row, so the loser reads the winner's committed result instead of building
  -- a second job.
  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'create_job', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'create_job'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'That job was already started with different details.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  select settings.currency_code into organization_currency
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  organization_currency := coalesce(organization_currency, 'USD');

  -- The job row, its number, its guards and its first history event. Direct one-off work: no quote lineage,
  -- whole-job pricing, and invoicing either reminded on close or left entirely manual.
  created_job := private.create_job(
    target_organization_id,
    target_client_id,
    target_property_id,
    new_title,
    'one_off',
    'job_total',
    organization_currency,
    caller,
    false,
    case when coalesce(invoice_on_close, true) then 'on_closure' else 'manual' end,
    new_instructions,
    null,
    null,
    null,
    null
  );

  -- The job's own scope. The 100-line cap is a table trigger; the shape of each line is a table constraint.
  insert into public.job_line_items (
    organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable
  )
  select
    created_job.organization_id,
    created_job.id,
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
    coalesce((line.value->>'is_taxable')::boolean, true)
  from jsonb_array_elements(coalesce(scope_lines, '[]'::jsonb)) with ordinality as line(value, ordinality);

  get diagnostics line_count = row_count;

  -- The visits, in the order the form listed them, each with its own people. A visit's shape is checked by
  -- the table's constraints; an assignee who is not a member of this organization is refused by the
  -- assignment's composite foreign key.
  for visit_element in select value from jsonb_array_elements(visits) as v(value)
  loop
    insert into public.job_visits (
      organization_id, job_id, position, visit_date, start_time, end_time, all_day, title, instructions,
      source
    ) values (
      created_job.organization_id,
      created_job.id,
      (visit_element->>'position')::integer,
      nullif(visit_element->>'visit_date', '')::date,
      nullif(visit_element->>'start_time', '')::time,
      nullif(visit_element->>'end_time', '')::time,
      coalesce((visit_element->>'all_day')::boolean, false),
      nullif(trim(visit_element->>'title'), ''),
      nullif(trim(visit_element->>'instructions'), ''),
      'manual'
    )
    returning * into new_visit;

    if jsonb_typeof(visit_element->'assignee_ids') = 'array' then
      for assignee_element in select value from jsonb_array_elements(visit_element->'assignee_ids') as a(value)
      loop
        insert into public.job_visit_assignments (organization_id, visit_id, user_id)
        values (created_job.organization_id, new_visit.id, (assignee_element #>> '{}')::uuid)
        on conflict do nothing;
      end loop;
    end if;
  end loop;

  calculated := private.store_job_money(created_job.id);

  final_result := jsonb_build_object(
    'applied', true,
    'job_id', created_job.id,
    'job_number', created_job.job_number,
    'visit_count', visit_count,
    'line_count', line_count,
    'total_minor', (calculated->>'total_minor')::bigint
  );

  update public.job_command_receipts set result = final_result where id = receipt_id;

  return final_result;
end;
$$;

comment on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text
) is
  'The one direct one-off job create. Writes the job, its scope and its 1-20 visits in one transaction, '
  'idempotent per (organization, key) through job_command_receipts.';

revoke all on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text
) from public;
revoke execute on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text
) from anon;
grant execute on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text
) to authenticated;

notify pgrst, 'reload schema';
