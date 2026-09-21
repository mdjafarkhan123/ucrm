-- WC3: Public Contact Widget shell. One read function for the public embed page to call: given a
-- widget's public_token and the page's actual Origin, resolve whether that origin may see this
-- widget at all, and if so, its branding and current status. An unmatched token or origin returns
-- an empty set either way -- WC0.3's "never confirm or deny a widget exists" rule -- so the caller
-- cannot distinguish "wrong token" from "wrong domain" from a network log alone.
--
-- security invoker, granted only to service_role: called exclusively from the server's owner
-- (service-role) client, matching how the public Quote view resolves its own token (no anon grant,
-- no RLS bypass needed since the caller already bypasses RLS as service_role).
create or replace function public.get_website_chat_widget_public_config(
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
         w.launcher_position, w.teaser_text, w.greeting_text
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
  'Public-safe read for the Website Chat embed shell (WC3). Resolves branding and status only for '
  'a token/origin pair that is actually allowed; anything else returns no rows.';

revoke all on function public.get_website_chat_widget_public_config(uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_website_chat_widget_public_config(uuid, text) to service_role;
