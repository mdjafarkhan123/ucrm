-- Contractor Settings, Part 4C: public rendering and abuse boundary.
--
-- The first thing to ever let an anonymous customer touch this app. Three pieces:
--
--   1. Every form gets a stable public address: `forms.public_slug`, unique per organization, generated once
--      at creation time (like organizations.slug already is -- app-side slugify + a collision-number suffix,
--      see the api/settings/forms route) and never changed automatically, so a link stays good even if the
--      form is later renamed internally. The public page itself is a plain read of `organizations`/`forms`/
--      `form_versions` -- no new function needed, since the service-role client this app already uses for
--      every other public flow (get-started, onboarding) bypasses RLS and already has the same table grants
--      Supabase sets up by default.
--
--   2. The slot list is the one public read that IS real business logic (business hours, each member's own
--      availability, everything already on the calendar), so `get_form_available_slots`'s body is extracted
--      into a private helper the existing staff-only wrapper and a new public-safe wrapper both call --
--      keeping exactly one copy of that logic, matching its own comment ("Part 4C adds the public-safe
--      path").
--
--   3. A submission is received and held, never turned into a Lead/Request/Job here -- that atomic step is
--      Part 4D. `private.form_submissions` is a staging table (no RLS policy needed, same reasoning as
--      `form_booking_reservations`: nothing but the command below and 4D's future processor ever touch it),
--      written by `submit_form_response`, which re-checks everything the app layer already validated
--      (published/enabled/not archived, organization active, photo keys actually belong to this form) because
--      an anonymous caller's own claims are never trusted twice.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Public slug
-- ---------------------------------------------------------------------------------------------------------

alter table public.forms
  add column public_slug text check (public_slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');

-- One real row exists today (Raad LTD's "Kitchen Remodel Request"); backfill it the same way the app will
-- generate every future one, then make the column mandatory.
update public.forms
set public_slug = trim(both '-' from regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'))
where public_slug is null;

alter table public.forms
  alter column public_slug set not null;

create unique index forms_organization_public_slug_idx on public.forms(organization_id, public_slug);

comment on column public.forms.public_slug is
  'Stable public address, unique per organization, generated once at create_form time by the /api route '
  '(same slugify + collision-suffix convention as organizations.slug) and never regenerated automatically '
  '-- a shared link must keep working even after the form is renamed internally.';

drop function if exists public.create_form(uuid, text, text, text, text);

create or replace function public.create_form(
  target_organization_id uuid,
  new_outcome text,
  new_name text,
  new_public_slug text,
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
  clean_slug text;
  new_form public.forms;
  new_version public.form_versions;
  default_content jsonb := jsonb_build_object(
    'contact', jsonb_build_object(
      'name', jsonb_build_object('required', true),
      'email', jsonb_build_object('shown', true, 'required', true, 'marketing_consent', false),
      'phone', jsonb_build_object('shown', true, 'required', false, 'marketing_consent', false),
      'company', jsonb_build_object('shown', false, 'required', false),
      'address', jsonb_build_object('shown', true, 'required', false)
    ),
    'sections', jsonb_build_array(),
    'photos', jsonb_build_object('enabled', false, 'max', 10),
    'confirmation', jsonb_build_object(
      'title', 'Thanks — we got your request',
      'message', 'We''ll be in touch shortly to talk about your project.',
      'redirect_url', null
    )
  );
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

  clean_slug := nullif(trim(coalesce(new_public_slug, '')), '');
  if clean_slug is null or clean_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(clean_slug) > 140 then
    raise exception 'That form link is invalid.' using errcode = 'check_violation';
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

  insert into public.forms (organization_id, outcome, name, public_slug, created_by, updated_by)
  values (
    target_organization_id, new_outcome, clean_name, clean_slug, (select auth.uid()), (select auth.uid())
  )
  returning * into new_form;

  insert into public.form_versions (
    organization_id, form_id, version_number, status, title, description, content, created_by, updated_by
  ) values (
    target_organization_id, new_form.id, 1, 'draft', clean_title, clean_description, default_content,
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
    'public_slug', new_form.public_slug,
    'is_enabled', new_form.is_enabled, 'is_default', new_form.is_default, 'revision', new_form.revision,
    'draft_version_id', new_version.id, 'draft_version_number', new_version.version_number,
    'draft_revision', new_version.revision
  );
end;
$$;

revoke all on function public.create_form(uuid, text, text, text, text, text) from public;
revoke execute on function public.create_form(uuid, text, text, text, text, text) from anon;
grant execute on function public.create_form(uuid, text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 2. Public-safe availability read
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.compute_form_available_slots(
  target_organization_id uuid,
  target_form_id uuid,
  range_start date,
  range_end date
)
returns table (
  slot_date date,
  start_time time,
  end_time time,
  starts_at timestamptz,
  ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  rules public.form_booking_rules;
  org_timezone text;
  hours_mode text;
  earliest_allowed timestamp;
  visit_duration interval;
  slot_interval interval;
  current_day date;
  current_weekday smallint;
  day_bands tsrange[];
  band tsrange;
  band_start timestamp;
  band_end timestamp;
  candidate_start timestamp;
  candidate_end timestamp;
  free_member uuid;
  max_range_days constant integer := 60;
  max_rows constant integer := 2000;
  returned_rows integer := 0;
begin
  if range_start is null or range_end is null or range_end < range_start then
    raise exception 'Give a valid date range.' using errcode = 'check_violation';
  end if;
  if range_end - range_start > max_range_days then
    raise exception 'Ask for at most % days at a time.', max_range_days using errcode = 'check_violation';
  end if;

  select * into rules
  from public.form_booking_rules
  where form_id = target_form_id and organization_id = target_organization_id;

  if rules.form_id is null then
    raise exception 'This form has no booking rules.' using errcode = 'check_violation';
  end if;

  select settings.timezone, settings.hours_mode into org_timezone, hours_mode
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;

  if hours_mode is null or hours_mode = 'not_configured' then
    return;
  end if;

  earliest_allowed := (now() + make_interval(mins => rules.min_notice_minutes)) at time zone org_timezone;
  visit_duration := make_interval(mins => rules.visit_duration_minutes);
  slot_interval := make_interval(mins => rules.slot_interval_minutes);

  current_day := range_start;
  while current_day <= range_end loop
    if exists (
      select 1 from public.schedule_events as event
      where event.organization_id = target_organization_id
        and event.event_date = current_day
        and event.start_time is null
    ) then
      current_day := current_day + 1;
      continue;
    end if;

    current_weekday := extract(dow from current_day)::smallint;
    day_bands := private.form_booking_day_bands(
      target_organization_id, hours_mode, current_day, current_weekday
    );

    foreach band in array day_bands loop
      band_start := lower(band);
      band_end := upper(band);
      candidate_start := band_start;

      while candidate_start + visit_duration <= band_end loop
        candidate_end := candidate_start + visit_duration;

        if candidate_start >= earliest_allowed
          and not private.form_booking_slot_blocked_by_team_event(
            target_organization_id, candidate_start, candidate_end, rules.buffer_minutes
          )
        then
          free_member := private.form_booking_free_member_for_slot(
            target_organization_id, candidate_start, candidate_end, rules.buffer_minutes, org_timezone
          );

          if free_member is not null then
            slot_date := candidate_start::date;
            start_time := candidate_start::time;
            end_time := candidate_end::time;
            starts_at := candidate_start at time zone org_timezone;
            ends_at := candidate_end at time zone org_timezone;
            return next;

            returned_rows := returned_rows + 1;
            if returned_rows >= max_rows then
              return;
            end if;
          end if;
        end if;

        candidate_start := candidate_start + slot_interval;
      end loop;
    end loop;

    current_day := current_day + 1;
  end loop;

  return;
end;
$$;

revoke all on function private.compute_form_available_slots(uuid, uuid, date, date)
  from public, anon, authenticated;

comment on function private.compute_form_available_slots(uuid, uuid, date, date) is
  'The actual slot-computation loop, shared by the staff-only and public-safe readers below so there is '
  'exactly one place that decides what counts as an open slot.';

-- The staff-facing reader keeps its exact signature and grants; only its body changes, to call the shared
-- helper instead of repeating the loop.
create or replace function public.get_form_available_slots(
  target_organization_id uuid,
  target_form_id uuid,
  range_start date,
  range_end date
)
returns table (
  slot_date date,
  start_time time,
  end_time time,
  starts_at timestamptz,
  ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to view booking availability.'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from private.compute_form_available_slots(target_organization_id, target_form_id, range_start, range_end);
end;
$$;

comment on function public.get_form_available_slots(uuid, uuid, date, date) is
  'Every bookable slot for one form across a date window (capped at 60 days). Staff-only '
  '(settings.forms.manage) -- see get_public_form_available_slots for the anonymous-safe path.';

revoke all on function public.get_form_available_slots(uuid, uuid, date, date) from public;
revoke execute on function public.get_form_available_slots(uuid, uuid, date, date) from anon;
grant execute on function public.get_form_available_slots(uuid, uuid, date, date) to authenticated;

-- The public wrapper resolves the form by its public address instead of a permission check, and gives away
-- nothing more precise than "not available" when the form or organization doesn't qualify.
create or replace function public.get_public_form_available_slots(
  target_organization_slug text,
  target_form_slug text,
  range_start date,
  range_end date
)
returns table (
  slot_date date,
  start_time time,
  end_time time,
  starts_at timestamptz,
  ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  resolved_organization_id uuid;
  resolved_form_id uuid;
begin
  select o.id, f.id into resolved_organization_id, resolved_form_id
  from public.organizations as o
  join public.forms as f on f.organization_id = o.id
  where o.slug = target_organization_slug
    and f.public_slug = target_form_slug
    and f.archived_at is null
    and f.is_enabled
    and f.current_published_version_id is not null
    and o.lifecycle_status = 'active';

  if resolved_form_id is null then
    raise exception 'That form is not available.' using errcode = 'check_violation';
  end if;

  return query
  select * from private.compute_form_available_slots(
    resolved_organization_id, resolved_form_id, range_start, range_end
  );
end;
$$;

comment on function public.get_public_form_available_slots(text, text, date, date) is
  'The anonymous-safe counterpart to get_form_available_slots -- resolves the form by its public link '
  'instead of trusting an authenticated caller''s own organization.';

revoke all on function public.get_public_form_available_slots(text, text, date, date)
  from public, anon, authenticated;
grant execute on function public.get_public_form_available_slots(text, text, date, date) to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 3. Received submissions -- staged for Part 4D, never turned into a Lead/Request/Job here
-- ---------------------------------------------------------------------------------------------------------

create extension if not exists pgcrypto;

-- Lives in `private`, like `form_booking_reservations`: nothing reads this directly, so there is no RLS
-- policy to get right. Only `submit_form_response` below writes it; only 4D's future processor will read it.
create table private.form_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  form_id uuid not null,
  form_version_id uuid not null,
  -- Client-generated once when the form loads, so a double-click or a retried request after a dropped
  -- response can never create two submissions for the same visit.
  idempotency_key text not null check (char_length(idempotency_key) between 1 and 200),
  contact jsonb not null,
  answers jsonb not null default '{}'::jsonb,
  photo_object_keys text[] not null default '{}',
  -- Booking forms only (assessment/job); a request form never sets these.
  selected_catalog_item_id uuid,
  requested_starts_at timestamptz,
  requested_ends_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'processed', 'failed')),
  processing_error text,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint form_submissions_organization_id_unique unique (organization_id, id),
  constraint form_submissions_form_fk foreign key (organization_id, form_id)
    references public.forms(organization_id, id) on delete cascade,
  constraint form_submissions_version_fk foreign key (organization_id, form_version_id)
    references public.form_versions(organization_id, id) on delete restrict,
  constraint form_submissions_booking_pair
    check ((requested_starts_at is null) = (requested_ends_at is null)),
  constraint form_submissions_booking_time_order
    check (requested_ends_at is null or requested_ends_at > requested_starts_at),
  -- One row per {form, idempotency key} ever -- the function below treats a repeat as "already received",
  -- not an error.
  constraint form_submissions_idempotency_unique unique (form_id, idempotency_key)
);

comment on table private.form_submissions is
  'Raw, safely-received public form answers, held for Part 4D to turn into a Lead/Request/Job. Written only '
  'by submit_form_response.';

create index form_submissions_pending_idx on private.form_submissions(organization_id, created_at)
  where status = 'pending';

create or replace function public.submit_form_response(
  target_organization_slug text,
  target_form_slug text,
  target_idempotency_key text,
  target_contact jsonb,
  target_answers jsonb,
  target_photo_object_keys text[] default '{}',
  target_selected_catalog_item_id uuid default null,
  target_requested_starts_at timestamptz default null,
  target_requested_ends_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  resolved_org public.organizations;
  form_row public.forms;
  key_prefix text;
  bad_key text;
  existing_id uuid;
  new_id uuid;
  max_photos constant integer := 20;
  max_json_bytes constant integer := 32768;
begin
  if target_idempotency_key is null or char_length(trim(target_idempotency_key)) = 0
    or char_length(target_idempotency_key) > 200
  then
    raise exception 'That submission could not be read.' using errcode = 'check_violation';
  end if;

  select * into resolved_org from public.organizations
  where slug = target_organization_slug and lifecycle_status = 'active';
  if resolved_org.id is null then
    raise exception 'That form is not available.' using errcode = 'check_violation';
  end if;

  select * into form_row from public.forms
  where organization_id = resolved_org.id
    and public_slug = target_form_slug
    and archived_at is null
    and is_enabled
    and current_published_version_id is not null;
  if form_row.id is null then
    raise exception 'That form is not available.' using errcode = 'check_violation';
  end if;

  if form_row.outcome = 'request' then
    if target_selected_catalog_item_id is not null
      or target_requested_starts_at is not null or target_requested_ends_at is not null
    then
      raise exception 'This form does not book a time.' using errcode = 'check_violation';
    end if;
  else
    if target_requested_starts_at is null or target_requested_ends_at is null then
      raise exception 'Choose a time for this visit.' using errcode = 'check_violation';
    end if;
    if target_selected_catalog_item_id is not null and not exists (
      select 1 from public.form_bookable_services
      where form_id = form_row.id and catalog_item_id = target_selected_catalog_item_id
    ) then
      raise exception 'Choose one of the listed services.' using errcode = 'check_violation';
    end if;
  end if;

  if target_contact is null or jsonb_typeof(target_contact) <> 'object'
    or length(target_contact::text) > max_json_bytes
  then
    raise exception 'That submission could not be read.' using errcode = 'check_violation';
  end if;
  if target_answers is null or jsonb_typeof(target_answers) <> 'object'
    or length(target_answers::text) > max_json_bytes
  then
    raise exception 'That submission could not be read.' using errcode = 'check_violation';
  end if;

  if target_photo_object_keys is not null and array_length(target_photo_object_keys, 1) > max_photos then
    raise exception 'Too many photos on one submission.' using errcode = 'check_violation';
  end if;

  -- Every photo key must live under this exact form's own public-submission prefix, matching how every
  -- other upload prefix in this app is checked server-side (see r2.ts) -- a submitted key that points
  -- anywhere else is refused rather than trusted.
  if target_photo_object_keys is not null then
    key_prefix := resolved_org.id || '/public-form-submissions/' || form_row.id || '/';
    select each_key into bad_key
    from unnest(target_photo_object_keys) as each_key
    where left(each_key, char_length(key_prefix)) <> key_prefix
    limit 1;
    if bad_key is not null then
      raise exception 'That photo does not belong to this form.' using errcode = 'check_violation';
    end if;
  end if;

  select id into existing_id from private.form_submissions
  where form_id = form_row.id and idempotency_key = target_idempotency_key;
  if existing_id is not null then
    return jsonb_build_object('submission_id', existing_id, 'already_received', true);
  end if;

  begin
    insert into private.form_submissions (
      organization_id, form_id, form_version_id, idempotency_key, contact, answers,
      photo_object_keys, selected_catalog_item_id, requested_starts_at, requested_ends_at
    ) values (
      resolved_org.id, form_row.id, form_row.current_published_version_id, target_idempotency_key,
      target_contact, target_answers, coalesce(target_photo_object_keys, '{}'::text[]),
      target_selected_catalog_item_id, target_requested_starts_at, target_requested_ends_at
    )
    returning id into new_id;
  exception
    when unique_violation then
      -- A concurrent retry of the same idempotency key lost the race; the row it collided with is the real
      -- answer, not an error the customer should see.
      select id into new_id from private.form_submissions
      where form_id = form_row.id and idempotency_key = target_idempotency_key;
      return jsonb_build_object('submission_id', new_id, 'already_received', true);
  end;

  return jsonb_build_object('submission_id', new_id, 'already_received', false);
end;
$$;

comment on function public.submit_form_response(
  text, text, text, jsonb, jsonb, text[], uuid, timestamptz, timestamptz
) is
  'Safely receives one public form answer into private.form_submissions. Re-checks everything the /api '
  'route already validated -- published/enabled/not archived, organization active, photo keys scoped to '
  'this exact form -- because an anonymous caller''s own claims are never trusted twice. Idempotent by '
  '{form, idempotency key}: a repeat returns the original submission id rather than a second row.';

revoke all on function public.submit_form_response(
  text, text, text, jsonb, jsonb, text[], uuid, timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function public.submit_form_response(
  text, text, text, jsonb, jsonb, text[], uuid, timestamptz, timestamptz
) to service_role;
