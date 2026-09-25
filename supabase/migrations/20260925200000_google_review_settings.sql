-- Google review campaign Part 1: review permissions and the per-organization review settings.
--
-- Product truth: docs/google-review-campaign-owner-brief.md.
--
-- 1. Four permissions and their role defaults, matching the brief's Team access table. They ride on the
--    existing `growth.reputation` package feature (the app maps the `reviews.` prefix to it).
-- 2. review_settings: one row per organization. No row means "still on UCRM's ready-made defaults"; the app
--    supplies those, so the defaults live in one place (src/lib/reviews/defaults.ts). Written only through
--    public.save_review_settings, read only by the server.

-- 1. Permissions -------------------------------------------------------------------------------------------

insert into public.permissions (key, description, scope_model)
values
  ('reviews.manage', 'Set up Google review requests: the review link, review page, feedback form and messages', 'none'),
  ('reviews.request', 'Send a client a review request', 'assigned_or_all'),
  ('reviews.view', 'See review requests and what each customer did', 'none'),
  ('reviews.feedback', 'See and handle private customer feedback', 'none')
on conflict (key) do nothing;

insert into public.role_permissions (role, permission_key, access_scope)
values
  ('owner', 'reviews.manage', 'all'),
  ('owner', 'reviews.request', 'all'),
  ('owner', 'reviews.view', 'all'),
  ('owner', 'reviews.feedback', 'all'),
  ('admin', 'reviews.manage', 'all'),
  ('admin', 'reviews.request', 'all'),
  ('admin', 'reviews.view', 'all'),
  ('admin', 'reviews.feedback', 'all'),
  ('office', 'reviews.request', 'all'),
  ('office', 'reviews.view', 'all'),
  ('office', 'reviews.feedback', 'all'),
  -- A fieldworker asks for a review on their own completed work only.
  ('field', 'reviews.request', 'assigned')
on conflict do nothing;

-- 2. Settings ----------------------------------------------------------------------------------------------

create table public.review_settings (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  google_review_url text,
  routing_enabled boolean not null default false,
  -- Stars at or above this go to Google once routing is on; below it go to private feedback.
  routing_google_min_rating smallint not null default 4,
  routing_acknowledged_at timestamptz,
  routing_acknowledged_by uuid references auth.users (id) on delete set null,
  feedback_form jsonb not null,
  message_styles jsonb not null,
  revision integer not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  constraint review_settings_google_review_url_check check (
    google_review_url is null
    or (char_length(google_review_url) <= 2048 and google_review_url ~ '^https://')
  ),
  constraint review_settings_min_rating_check check (routing_google_min_rating between 2 and 5),
  -- Routing can only be on with a destination and the owner's recorded acceptance of the warning.
  constraint review_settings_routing_check check (
    not routing_enabled or (google_review_url is not null and routing_acknowledged_at is not null)
  ),
  -- Gross backstops only; the per-field shape is validated by the API's Zod schema before any write.
  constraint review_settings_feedback_form_check check (
    jsonb_typeof(feedback_form) = 'object' and octet_length(feedback_form::text) <= 65536
  ),
  constraint review_settings_message_styles_check check (
    jsonb_typeof(message_styles) = 'object' and octet_length(message_styles::text) <= 32768
  ),
  constraint review_settings_revision_check check (revision >= 1)
);

comment on table public.review_settings is
  'Google review setup for one organization. No row = UCRM defaults. Written only through public.save_review_settings.';

alter table public.review_settings enable row level security;
revoke all on table public.review_settings from public, anon, authenticated;
grant all on table public.review_settings to service_role;

create index review_settings_routing_acknowledged_by_idx
  on public.review_settings (routing_acknowledged_by) where routing_acknowledged_by is not null;
create index review_settings_updated_by_idx
  on public.review_settings (updated_by) where updated_by is not null;

-- Saves the whole settings document. p_expected_revision is the revision the editor loaded (0 when no row
-- existed), so two people saving at once cannot silently overwrite each other. Turning routing on needs
-- p_acknowledge_routing = true and stamps who accepted the warning; staying on keeps the original stamp;
-- turning it off clears it, so turning it on again asks again.
create or replace function public.save_review_settings(
  p_organization_id uuid,
  p_actor_id uuid,
  p_expected_revision integer,
  p_google_review_url text,
  p_routing_enabled boolean,
  p_routing_google_min_rating smallint,
  p_acknowledge_routing boolean,
  p_feedback_form jsonb,
  p_message_styles jsonb
) returns public.review_settings
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  current_row public.review_settings;
  clean_url text := nullif(trim(coalesce(p_google_review_url, '')), '');
  saved public.review_settings;
begin
  if p_organization_id is null or p_actor_id is null then
    raise exception 'An organization and an actor are required.' using errcode = 'check_violation';
  end if;
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.manage') then
    raise exception 'You do not have permission to change review settings.' using errcode = 'insufficient_privilege';
  end if;

  select * into current_row from public.review_settings
  where organization_id = p_organization_id
  for update;

  if coalesce(current_row.revision, 0) <> coalesce(p_expected_revision, -1) then
    raise exception 'Review settings changed since you opened them.' using errcode = 'serialization_failure';
  end if;

  if p_routing_enabled and clean_url is null then
    raise exception 'Add your Google review link before turning on review routing.' using errcode = 'check_violation';
  end if;
  if p_routing_enabled and not coalesce(current_row.routing_enabled, false) and not coalesce(p_acknowledge_routing, false) then
    raise exception 'Accept the review routing warning to turn it on.' using errcode = 'check_violation';
  end if;

  insert into public.review_settings as s (
    organization_id, google_review_url, routing_enabled, routing_google_min_rating,
    routing_acknowledged_at, routing_acknowledged_by, feedback_form, message_styles,
    revision, updated_at, updated_by
  )
  values (
    p_organization_id, clean_url, coalesce(p_routing_enabled, false), coalesce(p_routing_google_min_rating, 4),
    case when p_routing_enabled then now() end,
    case when p_routing_enabled then p_actor_id end,
    p_feedback_form, p_message_styles, 1, now(), p_actor_id
  )
  on conflict (organization_id) do update
  set google_review_url = excluded.google_review_url,
      routing_enabled = excluded.routing_enabled,
      routing_google_min_rating = excluded.routing_google_min_rating,
      routing_acknowledged_at = case
        when not excluded.routing_enabled then null
        when s.routing_enabled then s.routing_acknowledged_at
        else now() end,
      routing_acknowledged_by = case
        when not excluded.routing_enabled then null
        when s.routing_enabled then s.routing_acknowledged_by
        else p_actor_id end,
      feedback_form = excluded.feedback_form,
      message_styles = excluded.message_styles,
      revision = s.revision + 1,
      updated_at = now(),
      updated_by = p_actor_id
  returning * into saved;

  return saved;
end;
$$;

revoke all on function public.save_review_settings(uuid, uuid, integer, text, boolean, smallint, boolean, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.save_review_settings(uuid, uuid, integer, text, boolean, smallint, boolean, jsonb, jsonb) to service_role;
