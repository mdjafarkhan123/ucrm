-- Jafar business management E4b: Jafar connects his Zoom account in Booking settings, and a booking whose meeting
-- type makes Zoom meetings automatically gets its own meeting (Calendly and Cal.com's per-event Zoom location).
--
-- 1. platform_zoom_connection: at most one row. Zoom's access and refresh tokens are kept together in one AES-GCM
--    envelope (the same discipline as Stripe's keys), so the table never holds a readable token.
-- 2. platform_bookings.video_synced_starts_at: the time Zoom's meeting was last set to, so a moved booking is noticed.
-- 3. owner_booking_zoom_work: what each booking still needs from Zoom -- make a meeting, move it, or delete it.
--    The server calls it right after a booking changes, and a periodic sweep calls it again to retry failures.
--
-- Platform owner's server only (service role).

create table public.platform_zoom_connection (
  id boolean primary key default true check (id),
  zoom_user_id text not null check (char_length(zoom_user_id) between 1 and 200),
  zoom_email text not null check (char_length(zoom_email) between 1 and 320),
  zoom_name text check (zoom_name is null or char_length(zoom_name) <= 200),
  credential_key_id text not null,
  credential_nonce text not null,
  credential_ciphertext text not null,
  credential_tag text not null,
  access_expires_at timestamptz not null,
  status text not null default 'connected' check (status in ('connected', 'needs_reconnect')),
  connected_by_email text,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger platform_zoom_connection_set_updated_at
  before update on public.platform_zoom_connection
  for each row execute function public.set_updated_at();

alter table public.platform_zoom_connection enable row level security;
revoke all on table public.platform_zoom_connection from public, anon, authenticated;
grant all on table public.platform_zoom_connection to service_role;

alter table public.platform_bookings add column video_synced_starts_at timestamptz;

comment on column public.platform_bookings.video_synced_starts_at is
  'The start time the booking''s Zoom meeting was last set to (E4b); null for a link the host supplied.';

-- What Zoom still has to do for one booking (or, with no booking named, up to max_rows bookings). A meeting UCRM
-- made ('provider' link) is moved when the call moved and deleted when the call or request is over; a booked,
-- upcoming Zoom call in automatic mode with no link yet needs a meeting. A link the host supplied is never touched.
create or replace function public.owner_booking_zoom_work(target_booking_id uuid default null, max_rows integer default 20)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select coalesce(jsonb_agg(w.item order by w.starts_at), '[]'::jsonb)
  from (
    select s.starts_at, s.item
    from (
      select
        coalesce(e.starts_at, b.requested_starts_at) as starts_at,
        jsonb_build_object(
          'booking_id', b.id,
          'entry_id', b.entry_id,
          'action', case
            when b.video_link_source = 'provider' and b.video_provider_meeting_id is not null
              and (e.status = 'cancelled' or b.status in ('declined', 'withdrawn')) then 'delete'
            when b.video_link_source = 'provider' and b.video_provider_meeting_id is not null
              and b.status = 'booked' and e.status = 'scheduled' and e.ends_at > now()
              and b.video_synced_starts_at is distinct from e.starts_at then 'update'
            when b.video_join_url is null and b.status = 'booked' and e.status = 'scheduled'
              and e.ends_at > now() and b.location_kind = 'zoom' and t.video_link_mode = 'automatic' then 'create'
          end,
          'meeting_id', b.video_provider_meeting_id,
          'starts_at', e.starts_at,
          'ends_at', e.ends_at,
          'topic', coalesce(t.name, 'Call') || ' with ' || r.business_name,
          'visitor_name', b.visitor_name
        ) as item
      from public.platform_bookings b
      join public.platform_business_relationships r on r.id = b.relationship_id
      left join public.platform_calendar_entries e on e.id = b.entry_id
      left join public.platform_meeting_types t on t.id = b.meeting_type_id
      where target_booking_id is null or b.id = target_booking_id
    ) s
    where s.item ->> 'action' is not null
    order by s.starts_at
    limit greatest(coalesce(max_rows, 20), 1)
  ) w;
$$;

revoke all on function public.owner_booking_zoom_work(uuid, integer) from public, anon, authenticated;
grant execute on function public.owner_booking_zoom_work(uuid, integer) to service_role;
