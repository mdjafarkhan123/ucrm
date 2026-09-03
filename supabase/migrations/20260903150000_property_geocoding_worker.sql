-- Schedule Part 7a-4: background geocoding worker — claim queue, result write-back, and a derived-write
-- updated_at rule.
--
-- 7a-3 gave every property a geocode_status (pending|succeeded|failed) and re-queues it on an address change.
-- This migration adds the database side of the background worker that drains that queue:
--   1. A properties-specific updated_at trigger so writing a geocode RESULT does not reorder client lists.
--   2. A partial index over the pending queue for the claim.
--   3. claim_pending_property_for_geocoding() — atomic competing-consumer claim (for update skip locked).
--   4. finalize_property_geocode(...) — optimistic write-back of the provider outcome.
-- The worker itself (src/lib/server/geocoding/worker.ts) calls these over the service-role client.

-- 1. Derived-write updated_at rule --------------------------------------------------------------------------
--
-- INDUSTRY PATTERN: updated_at means "last user-meaningful change". Coordinates are DERIVED data produced by
-- the geocoder, not a user edit — the same reason Rails' update_columns / Django's update_fields write such
-- columns WITHOUT bumping the record timestamp. properties_organization_client_idx orders each client's
-- property list by updated_at desc, so if the worker's coordinate write bumped updated_at, a one-time backfill
-- of every pending property would reorder every client's list. It must not.
--
-- Rather than list every user column (an open, growing set) as 7a-3's re-queue trigger does, this masks the
-- small, CLOSED set of derived columns (latitude, longitude, geocode_status) plus the timestamp itself, then
-- bumps updated_at only when some remaining — user-meaningful — column actually changed. A future user column
-- is covered automatically; only a future derived column would need adding to the mask.
create or replace function private.properties_touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  candidate public.properties;
begin
  candidate := new;
  candidate.latitude := old.latitude;
  candidate.longitude := old.longitude;
  candidate.geocode_status := old.geocode_status;
  candidate.updated_at := old.updated_at;

  -- If anything OTHER than the derived geocoding columns changed, this is a real edit: stamp updated_at. A
  -- geocode-only write leaves `candidate` identical to `old`, so the timestamp — and the list order — is kept.
  if candidate is distinct from old then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

-- Replace the shared set_updated_at() trigger on properties with the derived-aware one. Every other table keeps
-- using public.set_updated_at() unchanged.
drop trigger if exists properties_set_updated_at on public.properties;
create trigger properties_set_updated_at
before update on public.properties
for each row execute function private.properties_touch_updated_at();

-- 2. Pending-queue index ------------------------------------------------------------------------------------
--
-- The worker claims the oldest-waiting pending property. A partial index over only pending rows keeps this cheap
-- and stays tiny once the backlog drains (succeeded/failed rows are excluded), and it avoids write amplification
-- on the far more common succeeded rows.
create index properties_pending_geocoding_idx
  on public.properties (updated_at)
  where geocode_status = 'pending';

-- 3. Claim ---------------------------------------------------------------------------------------------------
--
-- One atomic claim of the oldest pending property. `for update skip locked` is the standard competing-consumer
-- pattern: concurrent worker slots each get a different row and never block on one another. The row lock is held
-- only for this statement's transaction; the row stays 'pending' until finalize records the outcome. Returns the
-- id and the four address components the geocoder query is built from (line1, city, state/region, postal code),
-- which finalize also uses to detect an address that changed mid-flight.
create or replace function public.claim_pending_property_for_geocoding()
returns table (
  id uuid,
  address_line1 text,
  city text,
  state_region text,
  postal_code text
)
language sql
security definer
set search_path = pg_catalog, public
as $$
  select p.id, p.address_line1, p.city, p.state_region, p.postal_code
  from public.properties as p
  where p.geocode_status = 'pending'
  order by p.updated_at
  for update skip locked
  limit 1;
$$;

revoke all on function public.claim_pending_property_for_geocoding() from public, anon, authenticated;
grant execute on function public.claim_pending_property_for_geocoding() to service_role;

-- 4. Finalize ------------------------------------------------------------------------------------------------
--
-- Write the provider outcome back, guarded by two conditions so a stale result can never win:
--   * geocode_status = 'pending' — a concurrent finalize already recorded an outcome; do nothing.
--   * the four query components still match what was claimed — the address was edited mid-flight (the 7a-3
--     re-queue trigger cleared coordinates and set pending again); this result is for the old address, so drop
--     it and let the next wake geocode the new address. This is optimistic concurrency on exactly the fields
--     that define the geocoder query.
-- p_status is 'succeeded' (coordinates supplied) or 'failed' (address does not resolve; coordinates stay null).
-- A transient provider error is NOT finalized at all — the worker simply leaves the row pending to retry.
-- Returns true when the row was updated, false when the guard rejected the write (already finalized or address
-- changed). The write touches only latitude/longitude/geocode_status, so the derived-write rule above keeps
-- updated_at — and the client's list order — untouched.
create or replace function public.finalize_property_geocode(
  p_id uuid,
  p_address_line1 text,
  p_city text,
  p_state_region text,
  p_postal_code text,
  p_status text,
  p_latitude numeric,
  p_longitude numeric
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  updated_count integer;
begin
  if p_status not in ('succeeded', 'failed') then
    raise exception 'finalize_property_geocode: p_status must be succeeded or failed, got %', p_status;
  end if;

  update public.properties as p
  set latitude  = case when p_status = 'succeeded' then p_latitude else null end,
      longitude = case when p_status = 'succeeded' then p_longitude else null end,
      geocode_status = p_status
  where p.id = p_id
    and p.geocode_status = 'pending'
    and p.address_line1 is not distinct from p_address_line1
    and p.city is not distinct from p_city
    and p.state_region is not distinct from p_state_region
    and p.postal_code is not distinct from p_postal_code;

  get diagnostics updated_count = row_count;
  return updated_count > 0;
end;
$$;

revoke all on function public.finalize_property_geocode(uuid, text, text, text, text, text, numeric, numeric)
  from public, anon, authenticated;
grant execute on function public.finalize_property_geocode(uuid, text, text, text, text, text, numeric, numeric)
  to service_role;
