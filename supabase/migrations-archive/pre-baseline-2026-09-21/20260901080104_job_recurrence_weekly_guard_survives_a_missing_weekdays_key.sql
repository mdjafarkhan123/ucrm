-- A weekly rule that omits `weekdays` entirely walked straight past the guard: jsonb_typeof of a missing key
-- is null, so `null = 'array'` made the whole condition null and the `if` never fired. The rule was still
-- refused a moment later -- with no days there is nothing to generate -- but by the wrong sentence. Coalesce
-- the missing key to zero days so the person is told what to fix.
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
  if chosen_frequency = 'weekly' and coalesce(
    case when jsonb_typeof(rule->'weekdays') = 'array' then jsonb_array_length(rule->'weekdays') end, 0
  ) not between 1 and 7 then
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

notify pgrst, 'reload schema';
