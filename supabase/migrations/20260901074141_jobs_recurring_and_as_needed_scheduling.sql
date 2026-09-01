-- Jobs Part 10a: recurring and as-needed scheduling.
--
-- A recurring job is an agreement with a repeat rule; its visits are generated from that rule, not typed in.
-- An as-needed job is the same agreement with no rule and no visits at all -- snow removal, on-call work --
-- and its visits get added when the work actually happens.
--
-- Two rules govern everything below:
--
-- 1. The rule is stored as columns, not as an iCalendar RRULE string. The approved behaviour contract asks for
--    frequency, interval, weekdays and an ordinal pattern, and columns let the database check them. We do not
--    need the exotic half of the iCal spec, and an RRULE string can still be printed from these columns later
--    if a calendar export ever needs one.
-- 2. The count a person sees before saving and the visits that actually get written come from ONE function.
--    A preview that promises 26 visits and a save that writes 27 is the classic failure here, and sharing the
--    date maths is the only way it cannot happen.

-- 1. How many visits one job may generate ---------------------------------------------------------------------

-- A ceiling, not a guess: weekly for five years is 260 and daily for a year is 365, so 400 clears the work
-- contractors actually sell while keeping generation one bounded insert and the job's own Visits list readable.
-- It is a function so the command, the preview and the tests can never disagree about the number.
create or replace function private.job_recurrence_limit()
returns integer
language sql
immutable
set search_path = pg_catalog
as $$ select 400 $$;

revoke all on function private.job_recurrence_limit() from public;
revoke execute on function private.job_recurrence_limit() from anon, authenticated;

-- 2. The rule --------------------------------------------------------------------------------------------------

-- One row per recurring job that has a schedule. An as-needed job has no row here at all: "no rule" is the
-- honest way to store "we will tell you when", rather than a flag on a rule that does not exist.
create table public.job_recurrence_rules (
  job_id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  frequency text not null check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),
  -- "Every 2 weeks" is interval_count 2 with frequency weekly. Capped so a rule cannot describe a span the
  -- generator would have to walk pointlessly.
  interval_count integer not null default 1 check (interval_count between 1 and 52),
  -- Which days a weekly rule lands on, 0 = Sunday through 6 = Saturday, matching extract(dow).
  weekdays smallint[],
  -- How a monthly rule picks its day: the 15th, the last day, or the second Tuesday.
  monthly_mode text check (monthly_mode in ('day_of_month', 'last_day', 'day_of_week')),
  month_day smallint check (month_day between 1 and 31),
  -- 1st through 4th, or 5 meaning last. "The last Friday" is what contractors say; a literal fifth Friday
  -- exists in barely half the months and is not what anyone means.
  ordinal_week smallint check (ordinal_week between 1 and 5),
  ordinal_weekday smallint check (ordinal_weekday between 0 and 6),
  start_date date not null,
  -- Jobber offers "ends after 6 months" or "ends on a date". Both are kept: the duration because it is what
  -- the person chose and what the form must show them again, and the resolved end date because generation
  -- should never have to re-do that arithmetic.
  end_mode text not null check (end_mode in ('after', 'on')),
  duration_count integer check (duration_count between 1 and 520),
  duration_unit text check (duration_unit in ('day', 'week', 'month', 'year')),
  end_date date not null,
  start_time time,
  end_time time,
  all_day boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_recurrence_rules_organization_id_unique unique (organization_id, job_id),
  constraint job_recurrence_rules_job_organization_fk foreign key (organization_id, job_id)
    references public.jobs(organization_id, id) on delete cascade,
  -- A weekly rule with no days is not a schedule.
  constraint job_recurrence_weekly_has_days check (
    frequency <> 'weekly'
    or (weekdays is not null and array_length(weekdays, 1) between 1 and 7)
  ),
  constraint job_recurrence_weekdays_valid check (
    weekdays is null or weekdays <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
  ),
  -- Each monthly shape carries exactly the fields it needs and none of the others, so a row can never describe
  -- two different days at once.
  constraint job_recurrence_monthly_shape check (
    frequency <> 'monthly'
    or (monthly_mode = 'day_of_month' and month_day is not null
        and ordinal_week is null and ordinal_weekday is null)
    or (monthly_mode = 'last_day' and month_day is null
        and ordinal_week is null and ordinal_weekday is null)
    or (monthly_mode = 'day_of_week' and month_day is null
        and ordinal_week is not null and ordinal_weekday is not null)
  ),
  constraint job_recurrence_non_monthly_clean check (frequency = 'monthly' or monthly_mode is null),
  constraint job_recurrence_duration_pairing check (
    (end_mode = 'after') = (duration_count is not null and duration_unit is not null)
  ),
  constraint job_recurrence_dates_ordered check (end_date >= start_date),
  -- Ten years is the outer edge of a service agreement anyone signs, and it keeps the generator's window
  -- bounded no matter what a caller sends.
  constraint job_recurrence_span_bounded check (end_date <= start_date + 3660),
  constraint job_recurrence_time_order check (
    end_time is null or (start_time is not null and end_time > start_time)
  ),
  constraint job_recurrence_all_day_no_time check (
    not all_day or (start_time is null and end_time is null)
  )
);

comment on table public.job_recurrence_rules is
  'The repeat rule behind a recurring job. Stored as columns rather than an iCalendar string so the database '
  'can check it. An as-needed job has no row here.';

create index job_recurrence_rules_organization_idx
  on public.job_recurrence_rules(organization_id, job_id);

create trigger job_recurrence_rules_set_updated_at
before update on public.job_recurrence_rules
for each row execute function public.set_updated_at();

alter table public.job_recurrence_rules enable row level security;

create policy "permitted members can view job recurrence rules"
on public.job_recurrence_rules for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'jobs.view')
);

-- Members read the rule on the job page and never write it; the commands are security definer and need no
-- grant of their own.
revoke all on public.job_recurrence_rules from anon, authenticated;
grant select on public.job_recurrence_rules to authenticated;

-- 3. The date maths --------------------------------------------------------------------------------------------

-- "The second Tuesday of this month", or the last one when ordinal is 5. For the first four the first matching
-- weekday of the month plus whole weeks always stays inside the month, because that lands on day 22 at the
-- latest; "last" walks back from the final day instead.
create or replace function private.nth_weekday_of_month(
  month_start date,
  ordinal smallint,
  weekday smallint
)
returns date
language sql
immutable
set search_path = pg_catalog
as $$
  select case
           when ordinal >= 5 then bounds.last_day - ((extract(dow from bounds.last_day)::integer - weekday + 7) % 7)
           else bounds.first_match + ((ordinal - 1) * 7)
         end
  from (
    select (month_start + interval '1 month - 1 day')::date as last_day,
           month_start + ((weekday - extract(dow from month_start)::integer + 7) % 7) as first_match
  ) as bounds;
$$;

revoke all on function private.nth_weekday_of_month(date, smallint, smallint) from public;
revoke execute on function private.nth_weekday_of_month(date, smallint, smallint) from anon, authenticated;

-- The single source of truth for which days a rule lands on. The preview counts these rows and the generator
-- inserts them, so the number a person is shown is the number they get. One row over the limit is returned on
-- purpose, so a caller can tell "exactly at the ceiling" from "over it" without counting twice.
create or replace function private.job_recurrence_dates(
  frequency text,
  interval_count integer,
  weekdays smallint[],
  monthly_mode text,
  month_day smallint,
  ordinal_week smallint,
  ordinal_weekday smallint,
  start_date date,
  end_date date
)
returns setof date
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  ceiling integer := private.job_recurrence_limit() + 1;
begin
  if start_date is null or end_date is null or end_date < start_date then
    return;
  end if;

  if frequency = 'daily' then
    return query
      select day::date
      from generate_series(start_date, end_date, make_interval(days => interval_count)) as day
      limit ceiling;

  elsif frequency = 'weekly' then
    -- Every day in the window that falls on one of the chosen weekdays, then thinned by the interval. Weeks are
    -- counted from the week the schedule starts and each week is aligned to its Sunday, so "every 2 weeks on
    -- Monday and Wednesday" keeps both days inside the same week rather than alternating between them.
    return query
      select day::date
      from generate_series(start_date, end_date, interval '1 day') as day
      where extract(dow from day)::smallint = any(weekdays)
        and (
          ((day::date - extract(dow from day)::integer)
           - (start_date - extract(dow from start_date)::integer)) / 7
        ) % interval_count = 0
      order by day
      limit ceiling;

  elsif frequency = 'monthly' then
    -- One candidate per month in the window, then keep the ones that exist and land inside it. A rule on the
    -- 31st simply has no February: the month is skipped rather than quietly moved to the 28th, which is what
    -- the iCalendar standard does and what "the 31st" plainly means. Anyone who wants February covered picks
    -- "the last day" instead.
    return query
      select occurrence
      from generate_series(
             date_trunc('month', start_date::timestamp),
             date_trunc('month', end_date::timestamp),
             make_interval(months => interval_count)
           ) as month_start
      cross join lateral (
        select case
                 when monthly_mode = 'last_day' then
                   (month_start + interval '1 month - 1 day')::date
                 when monthly_mode = 'day_of_month' then
                   case
                     when month_day <= extract(day from (month_start + interval '1 month - 1 day'))::integer
                       then (month_start + make_interval(days => month_day - 1))::date
                   end
                 else
                   private.nth_weekday_of_month(month_start::date, ordinal_week, ordinal_weekday)
               end as occurrence
      ) as candidate
      where occurrence is not null
        and occurrence between start_date and end_date
      order by occurrence
      limit ceiling;

  elsif frequency = 'yearly' then
    return query
      select day::date
      from generate_series(start_date, end_date, make_interval(years => interval_count)) as day
      limit ceiling;

  else
    raise exception 'That repeat frequency is not one we support.' using errcode = 'check_violation';
  end if;
end;
$$;

revoke all on function private.job_recurrence_dates(
  text, integer, smallint[], text, smallint, smallint, smallint, date, date
) from public;
revoke execute on function private.job_recurrence_dates(
  text, integer, smallint[], text, smallint, smallint, smallint, date, date
) from anon, authenticated;

-- 4. Reading a rule out of the form's json ----------------------------------------------------------------------

-- Both the preview and the create command receive the rule as jsonb from the same form, so the reading, the
-- shape checks and the "ends after 6 months" arithmetic happen once, here. Returning the resolved row means
-- neither caller has to know how a duration becomes an end date.
create or replace function private.read_job_recurrence(rule jsonb)
returns table (
  frequency text,
  interval_count integer,
  weekdays smallint[],
  monthly_mode text,
  month_day smallint,
  ordinal_week smallint,
  ordinal_weekday smallint,
  start_date date,
  end_mode text,
  duration_count integer,
  duration_unit text,
  end_date date,
  start_time time,
  end_time time,
  all_day boolean
)
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  resolved_start date := nullif(rule->>'start_date', '')::date;
  resolved_end date;
  chosen_frequency text := coalesce(nullif(rule->>'frequency', ''), 'weekly');
  chosen_end_mode text := coalesce(nullif(rule->>'end_mode', ''), 'after');
  chosen_duration integer := nullif(rule->>'duration_count', '')::integer;
  chosen_unit text := nullif(rule->>'duration_unit', '');
begin
  if resolved_start is null then
    raise exception 'A repeating schedule needs a start date.' using errcode = 'check_violation';
  end if;

  -- The table's own constraints would catch these, but a person reading "violates check constraint
  -- job_recurrence_weekly_has_days" learns nothing. Say the thing they need to go and fix.
  if chosen_frequency = 'weekly' and not (
    jsonb_typeof(rule->'weekdays') = 'array' and jsonb_array_length(rule->'weekdays') between 1 and 7
  ) then
    raise exception 'Pick at least one day of the week.' using errcode = 'check_violation';
  end if;
  if chosen_frequency = 'monthly'
    and coalesce(nullif(rule->>'monthly_mode', ''), '') not in ('day_of_month', 'last_day', 'day_of_week')
  then
    raise exception 'Choose how the monthly schedule picks its day.' using errcode = 'check_violation';
  end if;

  if chosen_end_mode = 'on' then
    resolved_end := nullif(rule->>'end_date', '')::date;
    if resolved_end is null then
      raise exception 'A repeating schedule needs an end date.' using errcode = 'check_violation';
    end if;
  else
    if chosen_duration is null or chosen_unit is null then
      raise exception 'A repeating schedule needs a length.' using errcode = 'check_violation';
    end if;
    -- "Ends after 6 months" runs to the day before the same date six months later, so a six-month agreement
    -- starting on the 1st ends on the last day of the sixth month rather than spilling a day into the seventh.
    resolved_end := (
      resolved_start
      + make_interval(
          days => case when chosen_unit = 'day' then chosen_duration else 0 end,
          weeks => case when chosen_unit = 'week' then chosen_duration else 0 end,
          months => case when chosen_unit = 'month' then chosen_duration else 0 end,
          years => case when chosen_unit = 'year' then chosen_duration else 0 end
        )
      - interval '1 day'
    )::date;
  end if;

  if resolved_end < resolved_start then
    raise exception 'A repeating schedule cannot end before it starts.' using errcode = 'check_violation';
  end if;
  if resolved_end > resolved_start + 3660 then
    raise exception 'A repeating schedule cannot run more than ten years.' using errcode = 'check_violation';
  end if;

  return query
    select
      chosen_frequency,
      coalesce(nullif(rule->>'interval_count', '')::integer, 1),
      case
        when jsonb_typeof(rule->'weekdays') = 'array' then (
          select array_agg((value #>> '{}')::smallint order by (value #>> '{}')::smallint)
          from jsonb_array_elements(rule->'weekdays') as day(value)
        )
      end,
      nullif(rule->>'monthly_mode', ''),
      nullif(rule->>'month_day', '')::smallint,
      nullif(rule->>'ordinal_week', '')::smallint,
      nullif(rule->>'ordinal_weekday', '')::smallint,
      resolved_start,
      chosen_end_mode,
      case when chosen_end_mode = 'after' then chosen_duration end,
      case when chosen_end_mode = 'after' then chosen_unit end,
      resolved_end,
      nullif(rule->>'start_time', '')::time,
      nullif(rule->>'end_time', '')::time,
      coalesce((rule->>'all_day')::boolean, false);
end;
$$;

revoke all on function private.read_job_recurrence(jsonb) from public;
revoke execute on function private.read_job_recurrence(jsonb) from anon, authenticated;

-- 5. The preview -------------------------------------------------------------------------------------------------

-- What the form shows above the end-date controls: how many visits this rule makes and the first and last one.
-- It touches no tenant data at all -- it is arithmetic on dates a person just typed -- so it needs no permission
-- beyond being signed in, and it reveals nothing about anybody's jobs.
create or replace function public.preview_job_recurrence(rule jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  parsed record;
  found_dates date[];
  ceiling integer := private.job_recurrence_limit();
begin
  if (select auth.uid()) is null then
    raise exception 'You must be signed in.' using errcode = 'insufficient_privilege';
  end if;

  select * into parsed from private.read_job_recurrence(rule);

  select array_agg(day order by day) into found_dates
  from private.job_recurrence_dates(
    parsed.frequency, parsed.interval_count, parsed.weekdays, parsed.monthly_mode,
    parsed.month_day, parsed.ordinal_week, parsed.ordinal_weekday, parsed.start_date, parsed.end_date
  ) as day;

  return jsonb_build_object(
    'visit_count', coalesce(array_length(found_dates, 1), 0),
    'first_date', found_dates[1],
    'last_date', found_dates[array_length(found_dates, 1)],
    'end_date', parsed.end_date,
    'limit', ceiling,
    'over_limit', coalesce(array_length(found_dates, 1), 0) > ceiling
  );
end;
$$;

comment on function public.preview_job_recurrence(jsonb) is
  'How many visits a repeat rule makes, and its first and last date. Pure date arithmetic on unsaved form '
  'input; shares private.job_recurrence_dates with generation so the count cannot disagree with the save.';

revoke all on function public.preview_job_recurrence(jsonb) from public;
revoke execute on function public.preview_job_recurrence(jsonb) from anon;
grant execute on function public.preview_job_recurrence(jsonb) to authenticated;

-- 6. Writing the rule and its visits ------------------------------------------------------------------------------

-- Creation calls this now; the schedule edit in Part 10b will call it again after clearing the visits it is
-- allowed to replace. Every visit lands in one insert rather than a loop, so a four-hundred-visit contract is
-- one statement inside the transaction that made the job.
create or replace function private.write_job_recurrence(
  target_organization_id uuid,
  target_job_id uuid,
  rule jsonb,
  first_position integer default 0
)
returns integer
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  parsed record;
  written integer;
  ceiling integer := private.job_recurrence_limit();
begin
  select * into parsed from private.read_job_recurrence(rule);

  insert into public.job_recurrence_rules (
    job_id, organization_id, frequency, interval_count, weekdays, monthly_mode, month_day,
    ordinal_week, ordinal_weekday, start_date, end_mode, duration_count, duration_unit, end_date,
    start_time, end_time, all_day
  ) values (
    target_job_id, target_organization_id, parsed.frequency, parsed.interval_count, parsed.weekdays,
    parsed.monthly_mode, parsed.month_day, parsed.ordinal_week, parsed.ordinal_weekday, parsed.start_date,
    parsed.end_mode, parsed.duration_count, parsed.duration_unit, parsed.end_date,
    parsed.start_time, parsed.end_time, parsed.all_day
  )
  on conflict (job_id) do update set
    frequency = excluded.frequency,
    interval_count = excluded.interval_count,
    weekdays = excluded.weekdays,
    monthly_mode = excluded.monthly_mode,
    month_day = excluded.month_day,
    ordinal_week = excluded.ordinal_week,
    ordinal_weekday = excluded.ordinal_weekday,
    start_date = excluded.start_date,
    end_mode = excluded.end_mode,
    duration_count = excluded.duration_count,
    duration_unit = excluded.duration_unit,
    end_date = excluded.end_date,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    all_day = excluded.all_day;

  insert into public.job_visits (
    organization_id, job_id, position, visit_date, start_time, end_time, all_day, source
  )
  select
    target_organization_id,
    target_job_id,
    first_position + (row_number() over (order by day))::integer - 1,
    day,
    parsed.start_time,
    parsed.end_time,
    parsed.all_day,
    'generated'
  from private.job_recurrence_dates(
    parsed.frequency, parsed.interval_count, parsed.weekdays, parsed.monthly_mode,
    parsed.month_day, parsed.ordinal_week, parsed.ordinal_weekday, parsed.start_date, parsed.end_date
  ) as day;

  get diagnostics written = row_count;

  if written < 1 then
    raise exception 'That schedule does not land on any day. Check the days and dates.'
      using errcode = 'check_violation';
  end if;
  if written > ceiling then
    raise exception 'That schedule makes % visits. The most we create at once is %. Try a nearer end date.',
      written, ceiling using errcode = 'check_violation';
  end if;

  -- The contract window is what "Ending soon" reads, and it is the rule's window, not the last visit's date.
  update public.jobs
  set contract_start_date = parsed.start_date, contract_end_date = parsed.end_date
  where id = target_job_id and organization_id = target_organization_id;

  return written;
end;
$$;

revoke all on function private.write_job_recurrence(uuid, uuid, jsonb, integer) from public;
revoke execute on function private.write_job_recurrence(uuid, uuid, jsonb, integer) from anon, authenticated;

-- 7. One create command for all three kinds of job -----------------------------------------------------------------

-- The old ten-argument version only knew how to make a one-off. It is dropped rather than overloaded, because
-- two functions differing only by a defaulted argument are ambiguous to call.
drop function if exists public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text
);

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
  new_request_hash text,
  new_job_type text default 'one_off',
  new_is_as_needed boolean default false,
  new_recurrence jsonb default null
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
  job_type text := coalesce(nullif(trim(coalesce(new_job_type, '')), ''), 'one_off');
  as_needed boolean := coalesce(new_is_as_needed, false);
  has_rule boolean := new_recurrence is not null and jsonb_typeof(new_recurrence) = 'object';
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

  if job_type not in ('one_off', 'recurring') then
    raise exception 'A job is either one-off or recurring.' using errcode = 'check_violation';
  end if;

  visit_count := coalesce(jsonb_array_length(visits), 0);

  -- The three shapes, each refused in the words of the thing the person actually did. A one-off is the visits
  -- they typed; a recurring job is the rule they set; an as-needed job is deliberately empty and stays empty.
  if job_type = 'one_off' then
    if has_rule or as_needed then
      raise exception 'A one-off job does not repeat. Create a recurring job instead.'
        using errcode = 'check_violation';
    end if;
    if visit_count < 1 or visit_count > 20 then
      raise exception 'A one-off job is created with between 1 and 20 visits.' using errcode = 'check_violation';
    end if;
  elsif as_needed then
    if has_rule or visit_count > 0 then
      raise exception 'An as-needed job starts with no schedule and no visits.' using errcode = 'check_violation';
    end if;
  else
    if not has_rule then
      raise exception 'A recurring job needs a repeat schedule.' using errcode = 'check_violation';
    end if;
    if visit_count > 0 then
      raise exception 'A recurring job builds its own visits from the schedule.'
        using errcode = 'check_violation';
    end if;
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

  -- The job row, its number, its guards and its first history event. A one-off is priced as a whole and
  -- reminded on close; repeating work defaults to a fixed amount each period, which is the shape Jobber opens
  -- on too. Part 11 owns changing that -- this only has to be a defensible starting point the guards accept.
  created_job := private.create_job(
    target_organization_id,
    target_client_id,
    target_property_id,
    new_title,
    job_type,
    case when job_type = 'one_off' then 'job_total' else 'fixed_per_period' end,
    organization_currency,
    caller,
    as_needed,
    case
      when job_type = 'recurring' then 'month_end'
      when coalesce(invoice_on_close, true) then 'on_closure'
      else 'manual'
    end,
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

  if has_rule then
    -- Generated visits carry the schedule's own time and no assignees; who goes is decided per visit, exactly
    -- as it is for a one-off.
    visit_count := private.write_job_recurrence(created_job.organization_id, created_job.id, new_recurrence);

    insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
    values (
      created_job.organization_id,
      created_job.id,
      'visits_generated',
      caller,
      jsonb_build_object('visit_count', visit_count, 'reason', 'created')
    );
  else
    -- The visits, in the order the form listed them, each with its own people. A visit's shape is checked by
    -- the table's constraints; an assignee who is not a member of this organization is refused by the
    -- assignment's composite foreign key.
    for visit_element in select value from jsonb_array_elements(coalesce(visits, '[]'::jsonb)) as v(value)
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
  end if;

  calculated := private.store_job_money(created_job.id);

  final_result := jsonb_build_object(
    'applied', true,
    'job_id', created_job.id,
    'job_number', created_job.job_number,
    'job_type', job_type,
    'is_as_needed', as_needed,
    'visit_count', visit_count,
    'line_count', line_count,
    'total_minor', (calculated->>'total_minor')::bigint
  );

  update public.job_command_receipts set result = final_result where id = receipt_id;

  return final_result;
end;
$$;

comment on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb
) is
  'The one direct job create. One-off with typed visits, recurring generated from a rule, or as-needed with '
  'neither. Written in one transaction, idempotent per (organization, key) through job_command_receipts.';

revoke all on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb
) from public;
revoke execute on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb
) from anon;
grant execute on function public.create_job_with_visits(
  uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb
) to authenticated;

notify pgrst, 'reload schema';
