-- Schedule Part 7a-3: property geocode status + on-save "needs geocoding" trigger.
--
-- The Map turns a property's address into coordinates once and stores them (the latitude/longitude columns
-- and their pair-consistency check already exist, added in 20260816103906). What was missing is a record of
-- WHERE that stands for each property, so a background job knows which rows still need geocoding and the stop
-- list knows why a stop has no pin. This migration adds that status and keeps it honest at the database level.
--
-- Three states, mapping onto the geocoder boundary's result (src/lib/server/geocoding/geocoder.ts):
--   * pending   -- the address has not been geocoded yet, or has changed since it was. It waits in the queue.
--   * succeeded -- the geocoder returned a location (GeocodeResult 'found'); coordinates are stored.
--   * failed    -- the geocoder ran and the address does not resolve (GeocodeResult 'not_found'). The stop
--                  stays in the route list with an explanation, never silently dropped.
-- A transient provider outage (GeocodingProviderError) is NOT 'failed': the worker leaves such a row 'pending'
-- to retry, so a real address is never marked unresolvable because Mapbox was briefly unreachable.
--
-- Coordinates only ever come from our geocoder. So the address-change logic lives in ONE trigger rather than
-- being repeated in each of the three save paths (POST /api/properties, PATCH /api/properties/[id], and the
-- create-client property_payload function). Whenever an address is inserted or a geocodable component of it
-- actually changes, the row is flipped back to pending and its stale coordinates are cleared -- the same
-- single-point invariant pattern this table already uses for primary and billing properties.

alter table public.properties
  add column geocode_status text not null default 'pending'
    check (geocode_status in ('pending', 'succeeded', 'failed'));

comment on column public.properties.geocode_status is
  'Where address-to-coordinate geocoding stands for this property: pending (queued/not yet done), succeeded '
  '(coordinates stored), failed (address does not resolve). Maintained by the '
  'private.mark_property_for_geocoding trigger and the background geocoding worker.';

-- Existing properties all start pending: none has been geocoded, so every one is a backfill candidate for the
-- worker. The column default already stamps 'pending' on the rows present when this runs, so no backfill UPDATE
-- is needed here.

-- A geocodable address is line 1, line 2, city, state/region, postal code and country. Label, access notes and
-- everything else describe the property, not its location, so changing them must not re-queue geocoding.
create or replace function private.mark_property_for_geocoding()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' then
    -- A new property's address has never been verified. Coordinates come only from our geocoder, so they start
    -- empty and the row waits in the pending queue regardless of what was supplied.
    new.geocode_status := 'pending';
    new.latitude := null;
    new.longitude := null;
    return new;
  end if;

  -- UPDATE: only a real change to a geocodable component invalidates the stored coordinates. `is distinct from`
  -- treats nulls correctly, so clearing or setting an optional line counts and a no-op rewrite does not. This
  -- also means the worker's own write of coordinates + status (which touches neither address column) never
  -- trips this trigger back to pending.
  if new.address_line1 is distinct from old.address_line1
     or new.address_line2 is distinct from old.address_line2
     or new.city is distinct from old.city
     or new.state_region is distinct from old.state_region
     or new.postal_code is distinct from old.postal_code
     or new.country is distinct from old.country then
    new.geocode_status := 'pending';
    new.latitude := null;
    new.longitude := null;
  end if;

  return new;
end;
$$;

-- Scoped to the address columns so the trigger body does not even run on unrelated updates (tax rate, primary
-- flag, soft delete). It fires on every insert, and on an update only when an address column is in the SET
-- list -- then the body confirms an actual change before re-queueing.
create trigger properties_mark_for_geocoding
before insert or update of
  address_line1, address_line2, city, state_region, postal_code, country
on public.properties
for each row execute function private.mark_property_for_geocoding();
