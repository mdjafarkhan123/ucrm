-- Communications Website Chat, Part WC2 (first slice): contractor widget management.
-- Gives a contractor a real website_chat_widgets row to create, edit, publish, and disable, plus its
-- allowed-origin list and an install test. No public-facing code, session, or message exists yet --
-- that starts at WC3. The live desktop/mobile preview from WC0.5's blueprint is deferred to a later
-- WC2 slice once WC3's public widget component exists to render (nothing to preview before then).
--
-- No provider call is involved (unlike email senders/domains), so this follows the simpler
-- security-definer-checks-its-own-permission command shape already used by Settings' tax rates
-- (organization_tax_rates), not the service-role begin/finalize ceremony Brevo required. The
-- communication_website_chat_authority_events table WC0.1 scoped stays reserved for WC1's remaining
-- token/suspension work; ordinary contractor CRUD does not need a second audit trail on top of
-- revision-guarded optimistic concurrency, matching how organization_tax_rates itself has none.
--
-- public_token, disabled_at, and suspended_at are created now (full WC0.1 shape) even though only
-- disabled_at gets a UI in this slice -- WC1's remaining scope reuses the same table's other two
-- columns later without a second migration touching it.

create table public.website_chat_widgets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  launcher_position text not null default 'bottom_right' check (
    launcher_position in ('bottom_left', 'bottom_right')
  ),
  teaser_text text check (teaser_text is null or char_length(btrim(teaser_text)) between 1 and 300),
  greeting_text text check (greeting_text is null or char_length(btrim(greeting_text)) between 1 and 300),
  -- The contract requires at least one of phone or email, never both mandatory and never both optional.
  contact_requirement text not null default 'either' check (
    contact_requirement in ('phone', 'email', 'either')
  ),
  availability_visibility_mode text not null default 'hidden' check (
    availability_visibility_mode in ('hidden', 'show_when_available', 'always')
  ),
  source_label text check (source_label is null or char_length(btrim(source_label)) between 1 and 120),
  -- Ordered optional external destinations (WhatsApp/Messenger). Website Chat itself is implicit-first
  -- and never stored here.
  channel_options jsonb not null default '[]'::jsonb check (jsonb_typeof(channel_options) = 'array'),
  published boolean not null default false,
  -- Contractor self-service pause (this slice) and Platform Owner abuse/security suspension (WC1's
  -- remaining scope) stay two independent columns -- never one status enum -- so suspension can survive
  -- and override an org's own disable/enable actions once that control exists.
  disabled_at timestamptz,
  suspended_at timestamptz,
  public_token uuid not null default gen_random_uuid(),
  revision integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint website_chat_widgets_organization_id_id_key unique (organization_id, id),
  constraint website_chat_widgets_public_token_key unique (public_token)
);

comment on table public.website_chat_widgets is
  'Contractor-owned Website Chat widget configuration. Written only by the commands below -- never '
  'edited through RLS directly -- matching organization_tax_rates.';

create index website_chat_widgets_organization_created_idx
  on public.website_chat_widgets (organization_id, created_at desc);

-- Cap-counting scan: entitlement counts a widget as "active" while it is not contractor-disabled.
create index website_chat_widgets_organization_active_idx
  on public.website_chat_widgets (organization_id)
  where disabled_at is null;

create index website_chat_widgets_created_by_idx
  on public.website_chat_widgets (created_by)
  where created_by is not null;

create index website_chat_widgets_updated_by_idx
  on public.website_chat_widgets (updated_by)
  where updated_by is not null;

create table public.website_chat_widget_origins (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  widget_id uuid not null,
  -- Well-formed origin, no wildcards, per WC0.3's strict-allowlist decision -- an empty list allows
  -- nothing, the opposite of ContractorOs's flagged default.
  origin text not null check (
    origin = lower(btrim(origin))
    and origin ~ '^https?://[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+(:[0-9]{1,5})?$'
  ),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint website_chat_widget_origins_widget_fk
    foreign key (organization_id, widget_id)
    references public.website_chat_widgets(organization_id, id) on delete cascade,
  -- Plain unique index for an exact-match lookup, not an array containment check (WC0.2's decision).
  constraint website_chat_widget_origins_unique unique (widget_id, origin)
);

comment on table public.website_chat_widget_origins is
  'One row per allowed origin per Website Chat widget. Written only by the commands below.';

create index website_chat_widget_origins_organization_idx
  on public.website_chat_widget_origins (organization_id, widget_id);

create index website_chat_widget_origins_created_by_idx
  on public.website_chat_widget_origins (created_by)
  where created_by is not null;

alter table public.website_chat_widgets enable row level security;
alter table public.website_chat_widget_origins enable row level security;

create policy "connection managers can view website chat widgets"
on public.website_chat_widgets for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.manage_connections')
);

create policy "connection managers can view website chat widget origins"
on public.website_chat_widget_origins for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.manage_connections')
);

-- Every write goes through the security-definer commands below, matching organization_tax_rates.
revoke insert, update, delete, truncate, references, trigger
  on public.website_chat_widgets, public.website_chat_widget_origins
  from anon, authenticated;

-- Entitlement -----------------------------------------------------------------------------------------

-- Mirrors private.employee_seats_used exactly: a widget counts while it is not contractor-disabled.
-- Platform suspension does not free a slot once WC1's remaining scope can set it -- an org should not be
-- able to game the cap by being suspended -- but suspended_at is always null today (no writer exists
-- yet), so this only needs to read disabled_at for now.
create or replace function private.website_chat_widgets_used(target_organization_id uuid)
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select count(*)::integer
  from public.website_chat_widgets
  where organization_id = target_organization_id and disabled_at is null;
$$;

comment on function private.website_chat_widgets_used(uuid) is
  'Single authority for website_chat_widgets consumed. Counts widgets with disabled_at is null.';

-- Mirrors private.assert_employee_seat_available exactly.
create or replace function private.assert_website_chat_widget_available(target_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  widget_limit record;
  widgets_used integer;
begin
  perform pg_advisory_xact_lock(hashtext('website_chat_widgets:' || target_organization_id::text));

  select * into widget_limit
  from public.effective_website_chat_widgets_limit(target_organization_id);

  widgets_used := private.website_chat_widgets_used(target_organization_id);

  if not widget_limit.is_unlimited and widgets_used >= coalesce(widget_limit.value, 0) then
    raise exception 'No Website Chat widgets are available for this organization.'
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function private.assert_website_chat_widget_available(uuid) is
  'Advisory-lock-guarded widget-cap check. Not an RPC target -- called only from the commands below.';

revoke all on function private.website_chat_widgets_used(uuid) from public, anon, authenticated, service_role;
revoke all on function private.assert_website_chat_widget_available(uuid)
  from public, anon, authenticated, service_role;

-- Commands ----------------------------------------------------------------------------------------------

create or replace function public.create_website_chat_widget(
  target_organization_id uuid,
  new_name text,
  new_launcher_position text,
  new_teaser_text text,
  new_greeting_text text,
  new_contact_requirement text,
  new_availability_visibility_mode text,
  new_source_label text,
  new_channel_options jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_name text;
  clean_teaser text;
  clean_greeting text;
  clean_source text;
  option_count integer;
  option_item jsonb;
  new_row public.website_chat_widgets;
begin
  if not private.has_permission(target_organization_id, 'conversations.manage_connections') then
    raise exception 'You do not have access to manage Website Chat.' using errcode = 'insufficient_privilege';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 120 then
    raise exception 'Give this widget a name up to 120 characters.' using errcode = 'check_violation';
  end if;
  if new_launcher_position not in ('bottom_left', 'bottom_right') then
    raise exception 'Choose a valid launcher position.' using errcode = 'check_violation';
  end if;
  if new_contact_requirement not in ('phone', 'email', 'either') then
    raise exception 'Choose a valid identity requirement.' using errcode = 'check_violation';
  end if;
  if new_availability_visibility_mode not in ('hidden', 'show_when_available', 'always') then
    raise exception 'Choose a valid availability visibility mode.' using errcode = 'check_violation';
  end if;

  new_channel_options := coalesce(new_channel_options, '[]'::jsonb);
  if jsonb_typeof(new_channel_options) <> 'array' then
    raise exception 'Channel options must be a list.' using errcode = 'check_violation';
  end if;
  option_count := jsonb_array_length(new_channel_options);
  if option_count > 5 then
    raise exception 'Choose at most 5 additional channel options.' using errcode = 'check_violation';
  end if;
  for option_item in select * from jsonb_array_elements(new_channel_options) loop
    if (option_item ->> 'type') not in ('whatsapp', 'messenger') then
      raise exception 'Each channel option needs a valid type.' using errcode = 'check_violation';
    end if;
    if coalesce(trim(option_item ->> 'destination'), '') = '' then
      raise exception 'Each channel option needs a destination.' using errcode = 'check_violation';
    end if;
  end loop;

  clean_teaser := nullif(trim(coalesce(new_teaser_text, '')), '');
  clean_greeting := nullif(trim(coalesce(new_greeting_text, '')), '');
  clean_source := nullif(trim(coalesce(new_source_label, '')), '');

  perform private.assert_website_chat_widget_available(target_organization_id);

  insert into public.website_chat_widgets (
    organization_id, name, launcher_position, teaser_text, greeting_text, contact_requirement,
    availability_visibility_mode, source_label, channel_options, created_by, updated_by
  ) values (
    target_organization_id, clean_name, new_launcher_position, clean_teaser, clean_greeting,
    new_contact_requirement, new_availability_visibility_mode, clean_source, new_channel_options,
    (select auth.uid()), (select auth.uid())
  ) returning * into new_row;

  return to_jsonb(new_row);
end;
$$;

revoke all on function public.create_website_chat_widget(uuid, text, text, text, text, text, text, text, jsonb)
  from public;
revoke execute on function public.create_website_chat_widget(uuid, text, text, text, text, text, text, text, jsonb)
  from anon;
grant execute on function public.create_website_chat_widget(uuid, text, text, text, text, text, text, text, jsonb)
  to authenticated;

create or replace function public.update_website_chat_widget(
  target_organization_id uuid,
  target_widget_id uuid,
  expected_revision integer,
  new_name text,
  new_launcher_position text,
  new_teaser_text text,
  new_greeting_text text,
  new_contact_requirement text,
  new_availability_visibility_mode text,
  new_source_label text,
  new_channel_options jsonb,
  new_published boolean,
  new_disabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  widget_row public.website_chat_widgets;
  clean_name text;
  clean_teaser text;
  clean_greeting text;
  clean_source text;
  option_count integer;
  option_item jsonb;
  reactivating boolean;
begin
  if not private.has_permission(target_organization_id, 'conversations.manage_connections') then
    raise exception 'You do not have access to manage Website Chat.' using errcode = 'insufficient_privilege';
  end if;

  select * into widget_row
  from public.website_chat_widgets
  where organization_id = target_organization_id and id = target_widget_id
  for update;

  if widget_row.id is null then
    raise exception 'That widget was not found.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from widget_row.revision then
    raise exception 'Someone else changed this widget while you were editing. Reload and try again.'
      using errcode = 'serialization_failure';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 120 then
    raise exception 'Give this widget a name up to 120 characters.' using errcode = 'check_violation';
  end if;
  if new_launcher_position not in ('bottom_left', 'bottom_right') then
    raise exception 'Choose a valid launcher position.' using errcode = 'check_violation';
  end if;
  if new_contact_requirement not in ('phone', 'email', 'either') then
    raise exception 'Choose a valid identity requirement.' using errcode = 'check_violation';
  end if;
  if new_availability_visibility_mode not in ('hidden', 'show_when_available', 'always') then
    raise exception 'Choose a valid availability visibility mode.' using errcode = 'check_violation';
  end if;

  new_channel_options := coalesce(new_channel_options, '[]'::jsonb);
  if jsonb_typeof(new_channel_options) <> 'array' then
    raise exception 'Channel options must be a list.' using errcode = 'check_violation';
  end if;
  option_count := jsonb_array_length(new_channel_options);
  if option_count > 5 then
    raise exception 'Choose at most 5 additional channel options.' using errcode = 'check_violation';
  end if;
  for option_item in select * from jsonb_array_elements(new_channel_options) loop
    if (option_item ->> 'type') not in ('whatsapp', 'messenger') then
      raise exception 'Each channel option needs a valid type.' using errcode = 'check_violation';
    end if;
    if coalesce(trim(option_item ->> 'destination'), '') = '' then
      raise exception 'Each channel option needs a destination.' using errcode = 'check_violation';
    end if;
  end loop;

  clean_teaser := nullif(trim(coalesce(new_teaser_text, '')), '');
  clean_greeting := nullif(trim(coalesce(new_greeting_text, '')), '');
  clean_source := nullif(trim(coalesce(new_source_label, '')), '');

  -- Re-enabling a previously self-disabled widget consumes a slot again, exactly like creating a new one.
  reactivating := widget_row.disabled_at is not null and not coalesce(new_disabled, false);
  if reactivating then
    perform private.assert_website_chat_widget_available(target_organization_id);
  end if;

  update public.website_chat_widgets
  set name = clean_name, launcher_position = new_launcher_position, teaser_text = clean_teaser,
      greeting_text = clean_greeting, contact_requirement = new_contact_requirement,
      availability_visibility_mode = new_availability_visibility_mode, source_label = clean_source,
      channel_options = new_channel_options, published = coalesce(new_published, false),
      disabled_at = case when coalesce(new_disabled, false) then coalesce(disabled_at, now()) else null end,
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = widget_row.id
  returning * into widget_row;

  return to_jsonb(widget_row);
end;
$$;

revoke all on function public.update_website_chat_widget(
  uuid, uuid, integer, text, text, text, text, text, text, text, jsonb, boolean, boolean
) from public;
revoke execute on function public.update_website_chat_widget(
  uuid, uuid, integer, text, text, text, text, text, text, text, jsonb, boolean, boolean
) from anon;
grant execute on function public.update_website_chat_widget(
  uuid, uuid, integer, text, text, text, text, text, text, text, jsonb, boolean, boolean
) to authenticated;

create or replace function public.add_website_chat_widget_origin(
  target_organization_id uuid,
  target_widget_id uuid,
  new_origin text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_origin text;
  widget_exists boolean;
  existing_count integer;
  new_row public.website_chat_widget_origins;
begin
  if not private.has_permission(target_organization_id, 'conversations.manage_connections') then
    raise exception 'You do not have access to manage Website Chat.' using errcode = 'insufficient_privilege';
  end if;

  select exists(
    select 1 from public.website_chat_widgets
    where organization_id = target_organization_id and id = target_widget_id
  ) into widget_exists;
  if not widget_exists then
    raise exception 'That widget was not found.' using errcode = 'check_violation';
  end if;

  clean_origin := lower(btrim(coalesce(new_origin, '')));
  if clean_origin !~
    '^https?://[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+(:[0-9]{1,5})?$'
  then
    raise exception 'Enter a valid origin like https://example.com.' using errcode = 'check_violation';
  end if;

  select count(*) into existing_count
  from public.website_chat_widget_origins
  where widget_id = target_widget_id;
  if existing_count >= 20 then
    raise exception 'A widget can have at most 20 allowed domains.' using errcode = 'check_violation';
  end if;

  insert into public.website_chat_widget_origins (organization_id, widget_id, origin, created_by)
  values (target_organization_id, target_widget_id, clean_origin, (select auth.uid()))
  on conflict (widget_id, origin) do nothing
  returning * into new_row;

  if new_row.id is null then
    raise exception 'That domain is already allowed for this widget.' using errcode = 'unique_violation';
  end if;

  return to_jsonb(new_row);
end;
$$;

revoke all on function public.add_website_chat_widget_origin(uuid, uuid, text) from public;
revoke execute on function public.add_website_chat_widget_origin(uuid, uuid, text) from anon;
grant execute on function public.add_website_chat_widget_origin(uuid, uuid, text) to authenticated;

create or replace function public.remove_website_chat_widget_origin(
  target_organization_id uuid,
  target_widget_id uuid,
  target_origin_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  deleted_row public.website_chat_widget_origins;
begin
  if not private.has_permission(target_organization_id, 'conversations.manage_connections') then
    raise exception 'You do not have access to manage Website Chat.' using errcode = 'insufficient_privilege';
  end if;

  delete from public.website_chat_widget_origins
  where organization_id = target_organization_id
    and widget_id = target_widget_id
    and id = target_origin_id
  returning * into deleted_row;

  if deleted_row.id is null then
    raise exception 'That domain was not found.' using errcode = 'check_violation';
  end if;

  return jsonb_build_object('status', 'deleted', 'id', deleted_row.id);
end;
$$;

revoke all on function public.remove_website_chat_widget_origin(uuid, uuid, uuid) from public;
revoke execute on function public.remove_website_chat_widget_origin(uuid, uuid, uuid) from anon;
grant execute on function public.remove_website_chat_widget_origin(uuid, uuid, uuid) to authenticated;

comment on function public.create_website_chat_widget(uuid, text, text, text, text, text, text, text, jsonb) is
  'Permission-checked, entitlement-guarded creation of a contractor Website Chat widget.';
comment on function public.update_website_chat_widget(
  uuid, uuid, integer, text, text, text, text, text, text, text, jsonb, boolean, boolean
) is 'Revision-guarded edit of a Website Chat widget, bundling publish and self-service disable.';
comment on function public.add_website_chat_widget_origin(uuid, uuid, text) is
  'Adds one allowed origin to a Website Chat widget.';
comment on function public.remove_website_chat_widget_origin(uuid, uuid, uuid) is
  'Removes one allowed origin from a Website Chat widget.';
