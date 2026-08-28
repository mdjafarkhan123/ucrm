-- WC4.3: the identity form's privacy policy link, and the identity requirement the form obeys.
--
-- `docs/website-chat-behavior-contract.md` requires the identity form to link to *the organization's*
-- privacy policy. The only privacy policy URL in the schema belongs to the Platform Owner
-- (`platform_owner_settings`), and putting UCRM's policy in front of a contractor's customers breaks the
-- branding rule the same contract sets ("a contractor's customers see only the contractor"). So the URL
-- becomes a per-widget contractor setting, alongside the other public-facing widget copy.
--
-- Per widget rather than per organization on purpose: an organization can run several widgets across
-- separate marketing sites, and the policy a visitor is pointed at is a property of the site the widget
-- is embedded in, not of the company record.
--
-- The public config function also starts returning `contact_requirement`. That column has existed since
-- WC2 and the contractor already sets it, but nothing public could read it -- so the identity form had no
-- way to know whether this widget requires a phone, an email, or either. It is a read of shipped
-- configuration, not a new setting.

alter table public.website_chat_widgets
  add column privacy_policy_url text
    check (
      privacy_policy_url is null
      or (privacy_policy_url like 'https://%' and char_length(privacy_policy_url) between 12 and 500)
    );

comment on column public.website_chat_widgets.privacy_policy_url is
  'Contractor-owned https URL linked from the identity form (WC4.3). Null hides the link entirely.';

-- One place both commands normalize the URL, so "blank means no link" and "https only" cannot drift
-- apart between create and update. Rejects rather than silently dropping a bad value: a contractor who
-- typed `example.com/privacy` needs to be told, not to find the link quietly missing from their widget.
create or replace function private.clean_website_chat_privacy_policy_url(raw_url text)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  cleaned text := nullif(trim(coalesce(raw_url, '')), '');
begin
  if cleaned is null then
    return null;
  end if;
  if cleaned not like 'https://%' or char_length(cleaned) > 500 then
    raise exception 'Enter a privacy policy link starting with https://, up to 500 characters.'
      using errcode = 'check_violation';
  end if;
  return cleaned;
end;
$$;

revoke all on function private.clean_website_chat_privacy_policy_url(text)
  from public, anon, authenticated, service_role;

-- Commands ------------------------------------------------------------------------------------------
--
-- Both commands gain one argument. A `create or replace` with an extra parameter would leave the old
-- arity in place as a second overload, and PostgREST resolves RPCs by argument names -- an unnoticed
-- stale overload is exactly how a settings write silently starts hitting the wrong function. Dropped by
-- full signature, then recreated.

drop function if exists public.create_website_chat_widget(
  uuid, text, text, text, text, text, text, text, jsonb
);

create function public.create_website_chat_widget(
  target_organization_id uuid,
  new_name text,
  new_launcher_position text,
  new_teaser_text text,
  new_greeting_text text,
  new_contact_requirement text,
  new_availability_visibility_mode text,
  new_source_label text,
  new_privacy_policy_url text,
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
  clean_privacy text;
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
  clean_privacy := private.clean_website_chat_privacy_policy_url(new_privacy_policy_url);

  perform private.assert_website_chat_widget_available(target_organization_id);

  insert into public.website_chat_widgets (
    organization_id, name, launcher_position, teaser_text, greeting_text, contact_requirement,
    availability_visibility_mode, source_label, privacy_policy_url, channel_options, created_by, updated_by
  ) values (
    target_organization_id, clean_name, new_launcher_position, clean_teaser, clean_greeting,
    new_contact_requirement, new_availability_visibility_mode, clean_source, clean_privacy,
    new_channel_options, (select auth.uid()), (select auth.uid())
  ) returning * into new_row;

  return to_jsonb(new_row);
end;
$$;

revoke all on function public.create_website_chat_widget(
  uuid, text, text, text, text, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.create_website_chat_widget(
  uuid, text, text, text, text, text, text, text, text, jsonb
) to authenticated;

drop function if exists public.update_website_chat_widget(
  uuid, uuid, integer, text, text, text, text, text, text, text, jsonb, boolean, boolean
);

create function public.update_website_chat_widget(
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
  new_privacy_policy_url text,
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
  clean_privacy text;
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
  clean_privacy := private.clean_website_chat_privacy_policy_url(new_privacy_policy_url);

  -- Re-enabling a previously self-disabled widget consumes a slot again, exactly like creating a new one.
  reactivating := widget_row.disabled_at is not null and not coalesce(new_disabled, false);
  if reactivating then
    perform private.assert_website_chat_widget_available(target_organization_id);
  end if;

  update public.website_chat_widgets
  set name = clean_name, launcher_position = new_launcher_position, teaser_text = clean_teaser,
      greeting_text = clean_greeting, contact_requirement = new_contact_requirement,
      availability_visibility_mode = new_availability_visibility_mode, source_label = clean_source,
      privacy_policy_url = clean_privacy,
      channel_options = new_channel_options, published = coalesce(new_published, false),
      disabled_at = case when coalesce(new_disabled, false) then coalesce(disabled_at, now()) else null end,
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = widget_row.id
  returning * into widget_row;

  return to_jsonb(widget_row);
end;
$$;

revoke all on function public.update_website_chat_widget(
  uuid, uuid, integer, text, text, text, text, text, text, text, text, jsonb, boolean, boolean
) from public, anon;
grant execute on function public.update_website_chat_widget(
  uuid, uuid, integer, text, text, text, text, text, text, text, text, jsonb, boolean, boolean
) to authenticated;

-- Public config -------------------------------------------------------------------------------------
--
-- `returns table` is part of the function's result type, so adding two output columns needs a drop and
-- recreate rather than a replace.

drop function if exists public.get_website_chat_widget_public_config(uuid, text);

create function public.get_website_chat_widget_public_config(
  widget_public_token uuid,
  requesting_origin text
)
returns table (
  widget_id uuid,
  organization_id uuid,
  business_name text,
  brand_color text,
  launcher_position text,
  teaser_text text,
  greeting_text text,
  contact_requirement text,
  privacy_policy_url text,
  status text
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $function$
declare
  widget record;
  normalized_origin text := lower(btrim(coalesce(requesting_origin, '')));
  origin_allowed boolean;
  entitlement_state text;
begin
  if normalized_origin = '' then
    return;
  end if;

  select w.id, w.organization_id, w.published, w.disabled_at, w.suspended_at,
         w.launcher_position, w.teaser_text, w.greeting_text, w.contact_requirement,
         w.privacy_policy_url
  into widget
  from public.website_chat_widgets w
  where w.public_token = widget_public_token;

  if not found then
    return;
  end if;

  select exists (
    select 1
    from public.website_chat_widget_origins o
    where o.widget_id = widget.id
      and o.origin = normalized_origin
  ) into origin_allowed;

  if not origin_allowed then
    return;
  end if;

  select l.state into entitlement_state
  from public.effective_website_chat_widgets_limit(widget.organization_id) l;

  widget_id := widget.id;
  organization_id := widget.organization_id;
  launcher_position := widget.launcher_position;
  teaser_text := widget.teaser_text;
  greeting_text := widget.greeting_text;
  contact_requirement := widget.contact_requirement;
  privacy_policy_url := widget.privacy_policy_url;

  select o.name, s.brand_color into business_name, brand_color
  from public.organizations o
  left join public.organization_settings s on s.organization_id = o.id
  where o.id = widget.organization_id;

  status := case
    when widget.suspended_at is not null then 'suspended'
    when widget.disabled_at is not null then 'disabled'
    when not widget.published then 'draft'
    when entitlement_state = 'not_included' then 'not_entitled'
    else 'live'
  end;

  return next;
end;
$function$;

comment on function public.get_website_chat_widget_public_config(uuid, text) is
  'Public-safe read for the Website Chat widget (WC3, extended by WC4.3). Resolves branding, the '
  'identity requirement, the privacy policy link and status only for a token/origin pair that is '
  'actually allowed; anything else returns no rows.';

revoke all on function public.get_website_chat_widget_public_config(uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_website_chat_widget_public_config(uuid, text) to service_role;
