-- Schedule Part 2: the calendar's own timezone and working hours, for the people who read the calendar.
--
-- Two facts decide what a calendar means. The organization's timezone decides which day "today" is, and so
-- which visits are Today and which are Late. The weekly working hours decide which part of the grid is a
-- working day, which Part 3 shades and Part 4 warns about.
--
-- Both live behind settings.business.view today, which is the right gate for the Business Profile screen and
-- the wrong one for a calendar: a dispatcher or crew member who can see Jobs but not Settings would silently
-- get UTC and no hours -- a calendar that disagrees with the office about what day it is.
--
-- This follows what the research established about Jobber and the mature field-service products: the
-- calendar's operating facts are readable by anyone who can see the schedule, while changing them stays an
-- administrator's job. private.organization_today already made exactly this argument for the calendar day;
-- this is the same helper, in public so a route can call it, carrying the two extra facts a calendar needs.
--
-- What it does NOT disclose is the point. The business's address, phone, website, description, branding,
-- currency, locale and every revision column stay behind settings.business.view. A caller gets the timezone
-- name, whether the business keeps weekly hours at all, and the weekly open/close rows. The calendar day
-- itself is not here: it is read from the timezone in the browser by $lib/time/calendar-day, so a tab left
-- open overnight does not keep yesterday's idea of Today.

create or replace function public.schedule_calendar_context(target_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    -- The same two checks the Schedule's own RLS makes: a member of this organization who may see jobs.
    -- A caller who fails either gets null, and the route answers that as a refusal, the way job_money
    -- simply returns no numbers to a reader without the price grant.
    when not private.is_organization_member(target_organization_id) then null
    when not private.has_permission(target_organization_id, 'jobs.view') then null
    else jsonb_build_object(
      'timezone', coalesce(
        nullif(btrim((
          select settings.timezone
          from public.organization_settings as settings
          where settings.organization_id = target_organization_id
        )), ''),
        'UTC'
      ),
      -- 'not_configured', 'weekly' or 'appointment_only'. A business that has never opened the Business
      -- Hours screen is not_configured, and so is one with no settings row at all, so only 'weekly' means
      -- there is a confirmed weekly pattern worth shading.
      'hours_mode', coalesce(
        (
          select settings.hours_mode
          from public.organization_settings as settings
          where settings.organization_id = target_organization_id
        ),
        'not_configured'
      ),
      'hours', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'weekday', hours.weekday,
              'period_index', hours.period_index,
              'is_open', hours.is_open,
              'is_open_24h', hours.is_open_24h,
              'opens_at', hours.opens_at,
              'closes_at', hours.closes_at
            )
            order by hours.weekday, hours.period_index
          )
          from public.organization_business_hours as hours
          where hours.organization_id = target_organization_id
        ),
        '[]'::jsonb
      )
    )
  end;
$$;

comment on function public.schedule_calendar_context(uuid) is
  'The calendar''s operating facts for a member who can see jobs: timezone, whether '
  'weekly hours are kept, and the weekly open/close rows. Definer because organization_settings and '
  'organization_business_hours are gated to settings.business.view, which is a Settings-screen gate rather '
  'than a calendar one. Discloses nothing else from either table; null for a caller without jobs.view.';

revoke all on function public.schedule_calendar_context(uuid) from public;
revoke execute on function public.schedule_calendar_context(uuid) from anon;
grant execute on function public.schedule_calendar_context(uuid) to authenticated;

notify pgrst, 'reload schema';
