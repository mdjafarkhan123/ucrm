-- Jafar business management E5: Jafar connects his Google account in Booking settings, and a booking whose meeting
-- type makes Google Meet calls automatically gets its own Calendar event with its own Meet link (Calendly and
-- Cal.com's per-event Meet location). Built the way E4b built Zoom.
--
-- 1. Meeting types and bookings may be 'google_meet'.
-- 2. platform_google_connection: at most one row; Google's access and refresh tokens share one AES-GCM envelope,
--    so the table never holds a readable token. Platform owner's server only (service role).
-- 3. owner_booking_video_work replaces owner_booking_zoom_work: what each booking still needs from its provider
--    (make, move or delete a meeting). A provider only ever works on its own bookings, so Zoom never touches a
--    Meet event or the reverse.

alter table public.platform_meeting_types drop constraint platform_meeting_types_location_check;
alter table public.platform_meeting_types
  add constraint platform_meeting_types_location_check check (location_kind in ('phone', 'zoom', 'google_meet'));

alter table public.platform_bookings drop constraint platform_bookings_location_check;
alter table public.platform_bookings
  add constraint platform_bookings_location_check check (location_kind in ('phone', 'zoom', 'google_meet'));

comment on column public.platform_bookings.location_kind is
  'How the call happens, fixed when it was booked: phone, zoom or google_meet (E4a, E5).';

create table public.platform_google_connection (
  id boolean primary key default true check (id),
  google_user_id text not null check (char_length(google_user_id) between 1 and 200),
  google_email text not null check (char_length(google_email) between 1 and 320),
  google_name text check (google_name is null or char_length(google_name) <= 200),
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

create trigger platform_google_connection_set_updated_at
  before update on public.platform_google_connection
  for each row execute function public.set_updated_at();

alter table public.platform_google_connection enable row level security;
revoke all on table public.platform_google_connection from public, anon, authenticated;
grant all on table public.platform_google_connection to service_role;

drop function public.owner_booking_zoom_work(uuid, integer);

create or replace function public.owner_booking_video_work(
  target_provider text,
  target_booking_id uuid default null,
  max_rows integer default 20
)
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
              and e.ends_at > now() and t.video_link_mode = 'automatic' then 'create'
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
      where b.location_kind = target_provider
        and (target_booking_id is null or b.id = target_booking_id)
    ) s
    where s.item ->> 'action' is not null
    order by s.starts_at
    limit greatest(coalesce(max_rows, 20), 1)
  ) w;
$$;

revoke all on function public.owner_booking_video_work(text, uuid, integer) from public, anon, authenticated;
grant execute on function public.owner_booking_video_work(text, uuid, integer) to service_role;
