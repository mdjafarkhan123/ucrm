-- Contractor Settings, Part 4B-2a: booking-rule settings foundation for assessment/job forms.
--
-- 4A gave every business a forms table split by outcome (request/assessment/job) and 4B-1 built the
-- request-form builder. This part is the DATA underneath the other two instant-booking outcomes: how much
-- notice a customer must give, how long a visit takes, the arrival-window wording, a fixed buffer between
-- bookings, whether a submission needs staff approval first, which of the business's existing services can
-- be booked, and whether a submission must fall inside the business's service area. No screens and no public
-- read/write yet -- that is 4B-2c and 4C. The actual "what slots are open" math is 4B-2b.
--
-- Deliberate launch scope, approved 2026-09-12:
--   * Service area is a straight-line radius from the business's own location, not a hand-drawn territory.
--     Jobber lets an owner draw an arbitrary shape; we ship the radius first because it needs no new map-
--     drawing tool and no new spatial storage, and it covers the same real job for a first release. The full
--     departure from Jobber's behavior, and what upgrading to it later would take, is recorded in
--     `.claude/skills/jobber/jobber-02-requests-leads.md` (§ 5, "How WE compare") so a later session
--     knows this was a scope choice, not an oversight.
--   * Efficient scheduling ships fixed buffer-time only. Jobber's real drive-time option needs a paid routing
--     API call per slot lookup we do not have; `efficient_scheduling_type` is left as an enum with only
--     'none'/'buffer_time' valid today so a future 'drive_time' value can slot in without a breaking change.
--     Same pointer as above records the deviation.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Booking-rule settings, one row per assessment/job form
-- ---------------------------------------------------------------------------------------------------------

create table public.form_booking_rules (
  form_id uuid primary key references public.forms(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Jobber's requiresBookingApproval, defaulting on for the same reason Jobber's own assessment forms do: an
  -- on-site estimate slot usually still wants a human glance before it lands on the calendar.
  requires_booking_approval boolean not null default true,
  -- Whether the org-wide service-area radius (organization_settings, §2) is enforced for this form. The
  -- radius itself and the business's own location are configured once, not per form -- matching Jobber's
  -- "Service areas" living under Company Settings and forms just opting in.
  service_area_enabled boolean not null default false,
  -- Earliest a slot may be booked, in minutes from now (Jobber's earliestAvailabilityMinutes).
  min_notice_minutes integer not null default 120 check (min_notice_minutes between 0 and 43200),
  -- Slot granularity offered to the customer (Jobber's intervalDurationMinutes).
  slot_interval_minutes integer not null default 30 check (slot_interval_minutes between 5 and 480),
  -- How long the visit itself is held on the calendar once booked.
  visit_duration_minutes integer not null default 60 check (visit_duration_minutes between 5 and 1440),
  -- Null means an exact time is shown; a value shows a window (e.g. 120 = "we'll arrive within 2 hours").
  arrival_window_minutes integer check (arrival_window_minutes is null or arrival_window_minutes between 0 and 480),
  -- Fixed gap kept clear on either side of a booking (Jobber's bufferDurationMinutes).
  buffer_minutes integer not null default 0 check (buffer_minutes between 0 and 480),
  -- Only 'none'/'buffer_time' are reachable today; 'drive_time' is a real future value, not a typo guard.
  efficient_scheduling_type text not null default 'none' check (efficient_scheduling_type in ('none', 'buffer_time')),
  revision integer not null default 1 check (revision >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint form_booking_rules_organization_fk foreign key (organization_id, form_id)
    references public.forms(organization_id, id) on delete cascade
);

comment on table public.form_booking_rules is
  'One row per assessment/job form, created alongside the form itself. Written only by '
  'update_form_booking_settings below -- never edited through RLS directly.';

alter table public.form_booking_rules enable row level security;

create policy "form managers can view booking rules"
on public.form_booking_rules for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'settings.forms.manage')
);

revoke insert, update, delete, truncate, references, trigger
  on public.form_booking_rules
  from anon, authenticated;

create trigger form_booking_rules_set_updated_at
before update on public.form_booking_rules
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------------------------------------
-- 2. Which of the business's existing services can be booked on a given form
-- ---------------------------------------------------------------------------------------------------------

-- Reuses the Price Book's service catalog (public.catalog_items, category = 'service') rather than a second
-- list -- the same reuse Jobber itself makes between its Products & Services and its booking forms.
create table public.form_bookable_services (
  form_id uuid not null references public.forms(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  catalog_item_id uuid not null,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  primary key (form_id, catalog_item_id),
  constraint form_bookable_services_form_fk foreign key (organization_id, form_id)
    references public.forms(organization_id, id) on delete cascade,
  constraint form_bookable_services_catalog_item_fk foreign key (organization_id, catalog_item_id)
    references public.catalog_items(organization_id, id) on delete cascade
);

comment on table public.form_bookable_services is
  'Which Price Book services a customer can pick on one assessment/job form, and their display order. '
  'Written only by update_form_booking_settings below.';

create index form_bookable_services_form_idx on public.form_bookable_services(form_id, position);

alter table public.form_bookable_services enable row level security;

create policy "form managers can view bookable services"
on public.form_bookable_services for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'settings.forms.manage')
);

revoke insert, update, delete, truncate, references, trigger
  on public.form_bookable_services
  from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 3. create_form now seeds a default booking-rules row for the two instant-booking outcomes
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.create_form(
  target_organization_id uuid,
  new_outcome text,
  new_name text,
  new_title text,
  new_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_name text;
  clean_title text;
  clean_description text;
  new_form public.forms;
  new_version public.form_versions;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  if new_outcome not in ('request', 'assessment', 'job') then
    raise exception 'Choose what this form creates: a request, an assessment, or a job.'
      using errcode = 'check_violation';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 120 then
    raise exception 'Give this form a name up to 120 characters.' using errcode = 'check_violation';
  end if;

  clean_title := nullif(trim(coalesce(new_title, '')), '');
  if clean_title is null or char_length(clean_title) > 160 then
    raise exception 'Give this form a title customers will see, up to 160 characters.'
      using errcode = 'check_violation';
  end if;

  clean_description := nullif(trim(coalesce(new_description, '')), '');
  if clean_description is not null and char_length(clean_description) > 2000 then
    raise exception 'The form description is too long.' using errcode = 'check_violation';
  end if;

  insert into public.forms (organization_id, outcome, name, created_by, updated_by)
  values (target_organization_id, new_outcome, clean_name, (select auth.uid()), (select auth.uid()))
  returning * into new_form;

  insert into public.form_versions (
    organization_id, form_id, version_number, status, title, description, created_by, updated_by
  ) values (
    target_organization_id, new_form.id, 1, 'draft', clean_title, clean_description,
    (select auth.uid()), (select auth.uid())
  )
  returning * into new_version;

  update public.forms set draft_version_id = new_version.id where id = new_form.id;

  -- Only the two instant-booking outcomes ever have booking rules; a 'request' form is reviewed by staff and
  -- never books a slot, so it never gets this row.
  if new_outcome in ('assessment', 'job') then
    insert into public.form_booking_rules (form_id, organization_id)
    values (new_form.id, target_organization_id);
  end if;

  return jsonb_build_object(
    'form_id', new_form.id, 'outcome', new_form.outcome, 'name', new_form.name,
    'is_enabled', new_form.is_enabled, 'is_default', new_form.is_default, 'revision', new_form.revision,
    'draft_version_id', new_version.id, 'draft_version_number', new_version.version_number,
    'draft_revision', new_version.revision
  );
end;
$$;

revoke all on function public.create_form(uuid, text, text, text, text) from public;
revoke execute on function public.create_form(uuid, text, text, text, text) from anon;
grant execute on function public.create_form(uuid, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 4. update_form_booking_settings -- the one command that saves rules + bookable services together
-- ---------------------------------------------------------------------------------------------------------

-- Matches 4B-1's "one command saves the whole draft" shape: one screen, one save, one revision to protect it.
create or replace function public.update_form_booking_settings(
  target_organization_id uuid,
  target_form_id uuid,
  expected_revision integer,
  new_requires_booking_approval boolean,
  new_service_area_enabled boolean,
  new_min_notice_minutes integer,
  new_slot_interval_minutes integer,
  new_visit_duration_minutes integer,
  new_arrival_window_minutes integer,
  new_buffer_minutes integer,
  new_service_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  form_row public.forms;
  rules_row public.form_booking_rules;
  org_settings public.organization_settings;
  clean_service_ids uuid[];
  invalid_service_count integer;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to manage forms.' using errcode = 'insufficient_privilege';
  end if;

  select * into form_row from public.forms
  where id = target_form_id and organization_id = target_organization_id
  for update;

  if form_row.id is null then
    raise exception 'That form was not found.' using errcode = 'check_violation';
  end if;
  if form_row.outcome not in ('assessment', 'job') then
    raise exception 'Only assessment and job forms have booking rules.' using errcode = 'check_violation';
  end if;
  if form_row.archived_at is not null then
    raise exception 'Restore this form before editing it.' using errcode = 'check_violation';
  end if;

  select * into rules_row from public.form_booking_rules
  where form_id = target_form_id
  for update;

  if expected_revision is distinct from rules_row.revision then
    raise exception 'Someone else changed these booking rules while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  if new_min_notice_minutes is null or new_min_notice_minutes not between 0 and 43200 then
    raise exception 'Minimum notice must be between 0 minutes and 30 days.' using errcode = 'check_violation';
  end if;
  if new_slot_interval_minutes is null or new_slot_interval_minutes not between 5 and 480 then
    raise exception 'Slot length must be between 5 minutes and 8 hours.' using errcode = 'check_violation';
  end if;
  if new_visit_duration_minutes is null or new_visit_duration_minutes not between 5 and 1440 then
    raise exception 'Visit duration must be between 5 minutes and 24 hours.' using errcode = 'check_violation';
  end if;
  if new_arrival_window_minutes is not null and new_arrival_window_minutes not between 0 and 480 then
    raise exception 'Arrival window must be between 0 minutes and 8 hours.' using errcode = 'check_violation';
  end if;
  if new_buffer_minutes is null or new_buffer_minutes not between 0 and 480 then
    raise exception 'Buffer time must be between 0 minutes and 8 hours.' using errcode = 'check_violation';
  end if;

  if coalesce(new_service_area_enabled, false) then
    select * into org_settings from public.organization_settings
    where organization_id = target_organization_id;

    if org_settings.latitude is null or org_settings.longitude is null then
      raise exception 'Confirm your business location in Business Profile before turning on the service area.'
        using errcode = 'check_violation';
    end if;
    if org_settings.service_area_radius_miles is null then
      raise exception 'Set a service area radius in Business Profile before turning it on here.'
        using errcode = 'check_violation';
    end if;
  end if;

  -- De-duplicate while keeping the caller's chosen order, and cap the list the same way 4B-1 caps sections.
  select array_agg(distinct service_id) into clean_service_ids
  from unnest(coalesce(new_service_ids, '{}')) as service_id;
  clean_service_ids := coalesce(clean_service_ids, '{}');
  if array_length(clean_service_ids, 1) > 20 then
    raise exception 'A form can offer up to 20 bookable services.' using errcode = 'check_violation';
  end if;

  if array_length(clean_service_ids, 1) > 0 then
    select count(*) into invalid_service_count
    from unnest(clean_service_ids) as service_id
    where not exists (
      select 1 from public.catalog_items as item
      where item.id = service_id
        and item.organization_id = target_organization_id
        and item.category = 'service'
        and item.archived_at is null
    );
    if invalid_service_count > 0 then
      raise exception 'One of the selected services is no longer available.' using errcode = 'check_violation';
    end if;
  end if;

  update public.form_booking_rules
  set requires_booking_approval = coalesce(new_requires_booking_approval, rules_row.requires_booking_approval),
      service_area_enabled = coalesce(new_service_area_enabled, false),
      min_notice_minutes = new_min_notice_minutes,
      slot_interval_minutes = new_slot_interval_minutes,
      visit_duration_minutes = new_visit_duration_minutes,
      arrival_window_minutes = new_arrival_window_minutes,
      buffer_minutes = new_buffer_minutes,
      revision = revision + 1,
      updated_by = (select auth.uid()),
      updated_at = now()
  where form_id = target_form_id
  returning * into rules_row;

  delete from public.form_bookable_services where form_id = target_form_id;

  if array_length(clean_service_ids, 1) > 0 then
    insert into public.form_bookable_services (form_id, organization_id, catalog_item_id, position)
    select target_form_id, target_organization_id, service_id, ordinality - 1
    from unnest(clean_service_ids) with ordinality as service_id;
  end if;

  return jsonb_build_object(
    'form_id', target_form_id,
    'revision', rules_row.revision,
    'requires_booking_approval', rules_row.requires_booking_approval,
    'service_area_enabled', rules_row.service_area_enabled,
    'min_notice_minutes', rules_row.min_notice_minutes,
    'slot_interval_minutes', rules_row.slot_interval_minutes,
    'visit_duration_minutes', rules_row.visit_duration_minutes,
    'arrival_window_minutes', rules_row.arrival_window_minutes,
    'buffer_minutes', rules_row.buffer_minutes,
    'service_ids', to_jsonb(clean_service_ids)
  );
end;
$$;

revoke all on function public.update_form_booking_settings(
  uuid, uuid, integer, boolean, boolean, integer, integer, integer, integer, integer, uuid[]
) from public;
revoke execute on function public.update_form_booking_settings(
  uuid, uuid, integer, boolean, boolean, integer, integer, integer, integer, integer, uuid[]
) from anon;
grant execute on function public.update_form_booking_settings(
  uuid, uuid, integer, boolean, boolean, integer, integer, integer, integer, integer, uuid[]
) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 5. The business's own location + service-area radius (Business Profile-owned, org-wide, not per form)
-- ---------------------------------------------------------------------------------------------------------

alter table public.organization_settings
  add column latitude numeric(9, 6) check (latitude is null or latitude between -90 and 90),
  add column longitude numeric(9, 6) check (longitude is null or longitude between -180 and 180),
  add column location_geocode_status text not null default 'pending'
    check (location_geocode_status in ('pending', 'succeeded', 'failed')),
  add column service_area_radius_miles numeric(6, 1)
    check (service_area_radius_miles is null or service_area_radius_miles between 0.1 and 500),
  add constraint organization_settings_location_pair check ((latitude is null) = (longitude is null));

comment on column public.organization_settings.location_geocode_status is
  'Where geocoding the business address stands: pending (queued/not yet done, or the address changed since), '
  'succeeded (latitude/longitude stored), failed (address does not resolve). Maintained by the '
  'private.mark_organization_for_geocoding trigger and the geocoding worker -- the same pattern properties use.';

-- Mirrors private.mark_property_for_geocoding (20260903140000): a real change to a geocodable address
-- component invalidates whatever coordinates were stored and re-queues the row. organization_settings starts
-- with no address at all, so every organization is already a backfill candidate via the 'pending' default --
-- no seed UPDATE needed here.
create or replace function private.mark_organization_for_geocoding()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.address_line1 is distinct from old.address_line1
     or new.address_line2 is distinct from old.address_line2
     or new.city is distinct from old.city
     or new.region is distinct from old.region
     or new.postal_code is distinct from old.postal_code
     or new.country_code is distinct from old.country_code
  then
    new.location_geocode_status := 'pending';
    new.latitude := null;
    new.longitude := null;
  end if;
  return new;
end;
$$;

create trigger organization_settings_mark_for_geocoding
before update on public.organization_settings
for each row execute function private.mark_organization_for_geocoding();

-- The worker's claim: oldest pending business address first, locked so two overlapping wakes cannot both grab
-- it. Internal only -- service_role, exactly like the property equivalent.
create or replace function public.claim_pending_organization_for_geocoding()
returns table (
  organization_id uuid,
  address_line1 text,
  city text,
  region text,
  postal_code text
)
language sql
security definer
set search_path = pg_catalog, public
as $$
  select s.organization_id, s.address_line1, s.city, s.region, s.postal_code
  from public.organization_settings as s
  where s.location_geocode_status = 'pending' and s.address_line1 is not null
  order by s.updated_at
  for update skip locked
  limit 1;
$$;

revoke all on function public.claim_pending_organization_for_geocoding() from public, anon, authenticated;
grant execute on function public.claim_pending_organization_for_geocoding() to service_role;

-- Guarded the same way finalize_property_geocode is: a stale result (address edited mid-flight, or someone
-- else already finalized this wake) is dropped rather than winning.
create or replace function public.finalize_organization_geocode(
  p_organization_id uuid,
  p_address_line1 text,
  p_city text,
  p_region text,
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
    raise exception 'finalize_organization_geocode: p_status must be succeeded or failed, got %', p_status;
  end if;

  update public.organization_settings as s
  set latitude = case when p_status = 'succeeded' then p_latitude else null end,
      longitude = case when p_status = 'succeeded' then p_longitude else null end,
      location_geocode_status = p_status
  where s.organization_id = p_organization_id
    and s.location_geocode_status = 'pending'
    and s.address_line1 is not distinct from p_address_line1
    and s.city is not distinct from p_city
    and s.region is not distinct from p_region
    and s.postal_code is not distinct from p_postal_code;

  get diagnostics updated_count = row_count;
  return updated_count > 0;
end;
$$;

revoke all on function public.finalize_organization_geocode(uuid, text, text, text, text, text, numeric, numeric)
  from public, anon, authenticated;
grant execute on function public.finalize_organization_geocode(uuid, text, text, text, text, text, numeric, numeric)
  to service_role;

-- The one Business Profile field this part adds: the service-area radius. Guarded by the same profile_revision
-- save_organization_business_profile already protects, since it is one more fact about the business's profile,
-- not a new section. Location itself is never set by hand -- it only ever comes from the geocoder above.
create or replace function public.update_organization_service_area_radius(
  target_organization_id uuid,
  expected_revision integer,
  new_radius_miles numeric
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_radius_miles is null or new_radius_miles < 0.1 or new_radius_miles > 500 then
    raise exception 'Service area radius must be between 0.1 and 500 miles.' using errcode = 'check_violation';
  end if;

  select * into settings_row from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.profile_revision then
    select profile.full_name, settings_row.profile_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.profile_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  update public.organization_settings
  set service_area_radius_miles = new_radius_miles,
      profile_revision = profile_revision + 1,
      profile_updated_by = (select auth.uid()),
      profile_updated_at = now()
  where organization_id = target_organization_id
  returning * into settings_row;

  return jsonb_build_object(
    'status', 'saved',
    'profile_revision', settings_row.profile_revision,
    'service_area_radius_miles', settings_row.service_area_radius_miles
  );
end;
$$;

revoke all on function public.update_organization_service_area_radius(uuid, integer, numeric) from public;
revoke execute on function public.update_organization_service_area_radius(uuid, integer, numeric) from anon;
grant execute on function public.update_organization_service_area_radius(uuid, integer, numeric) to authenticated;
