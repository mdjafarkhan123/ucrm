-- Jafar business management E2: the open times Jafar can offer a visitor whose booking request he approves at
-- another time. The public page's list answers nothing while the booking link is off, but switching the link off
-- only stops new visitors: a request already waiting can still be answered with any time the page would offer.
-- Only requests still waiting have times to offer; anything else answers an empty list.

create or replace function public.owner_booking_request_slots(
  target_booking_id uuid,
  range_from timestamptz,
  range_to timestamptz
)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select s.starts_at, s.ends_at
  from public.platform_bookings b
  cross join lateral private.booking_open_slots(b.meeting_type_id, range_from, range_to) s
  where b.id = target_booking_id and b.status = 'requested'
  order by s.starts_at;
$$;

revoke all on function public.owner_booking_request_slots(uuid, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.owner_booking_request_slots(uuid, timestamptz, timestamptz) to service_role;
