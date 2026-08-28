-- Website Chat WC3: public Contact Widget shell. Covers the one new public-safe read function --
-- privilege matrix (anon/authenticated must never call it directly; only service_role can), the
-- "never confirm or deny" behavior for an unknown token or a mismatched origin, origin
-- normalization, branding passthrough, and the status priority (suspended > disabled > draft >
-- not_entitled > live).
--
-- Written for `supabase test db`, which runs the file as one session inside a rolled-back transaction.
begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

insert into public.organizations (id, name, slug, lifecycle_status, brand_color)
values ('f3000000-0000-0000-0000-000000000001', 'WC3 Widget Test Co', 'wc3-widget-test-co', 'active', '#112233');

-- A numeric override alone is enough entitlement, matching WC2's fixture shape -- no package
-- assignment needed.
insert into public.organization_limit_overrides (
  organization_id, limit_key, limit_state, limit_value, is_unlimited, starts_at
) values (
  'f3000000-0000-0000-0000-000000000001', 'website_chat_widgets', 'numeric', 2, false, now() - interval '1 minute'
);

insert into public.website_chat_widgets (
  id, organization_id, name, launcher_position, teaser_text, greeting_text, public_token, published
) values (
  'f4000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Main Widget',
  'bottom_right', 'Hi there', 'How can we help?', 'a5000000-0000-0000-0000-000000000001', true
);

insert into public.website_chat_widget_origins (organization_id, widget_id, origin)
values (
  'f3000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'https://example.com'
);

-- 1. Privilege matrix -----------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.get_website_chat_widget_public_config(uuid, text)', 'execute'),
  false, 'anonymous callers cannot call the config resolver directly'
);
select is(
  has_function_privilege('authenticated', 'public.get_website_chat_widget_public_config(uuid, text)', 'execute'),
  false, 'a signed-in member cannot call the config resolver directly'
);
select is(
  has_function_privilege('service_role', 'public.get_website_chat_widget_public_config(uuid, text)', 'execute'),
  true, 'only the server''s service-role client can resolve public widget config'
);

-- 2. Unknown token and mismatched origin both answer with nothing, never a distinguishing error ----------

select is(
  (select count(*)::integer from public.get_website_chat_widget_public_config(
    gen_random_uuid(), 'https://example.com'
  )),
  0, 'an unknown public_token returns no rows'
);

select is(
  (select count(*)::integer from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://wrong-site.test'
  )),
  0, 'a known token from an unapproved origin returns no rows'
);

-- 3. A matching token/origin resolves branding and a live status ------------------------------------------

select is(
  (select status from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://example.com'
  )),
  'live', 'a published, unrestricted, entitled widget resolves as live'
);

select is(
  (select business_name from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://example.com'
  )),
  'WC3 Widget Test Co', 'branding carries the organization name'
);

select is(
  (select brand_color from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://example.com'
  )),
  '#112233', 'branding carries the organization brand color'
);

-- 4. Origin comparison is normalized the same way storage already normalizes it ---------------------------

select is(
  (select status from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', '  HTTPS://Example.COM  '
  )),
  'live', 'origin comparison is case/whitespace-insensitive, matching the stored normalized form'
);

-- 5. Status priority: suspended beats disabled beats draft beats not_entitled ------------------------------

update public.website_chat_widgets set disabled_at = now()
where id = 'f4000000-0000-0000-0000-000000000001';

select is(
  (select status from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://example.com'
  )),
  'disabled', 'a self-service-disabled widget resolves as disabled'
);

update public.website_chat_widgets set suspended_at = now()
where id = 'f4000000-0000-0000-0000-000000000001';

select is(
  (select status from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://example.com'
  )),
  'suspended', 'a platform suspension outranks an existing self-service disable'
);

update public.website_chat_widgets set disabled_at = null, suspended_at = null, published = false
where id = 'f4000000-0000-0000-0000-000000000001';

select is(
  (select status from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://example.com'
  )),
  'draft', 'an unpublished draft widget resolves as draft, not live'
);

update public.website_chat_widgets set published = true
where id = 'f4000000-0000-0000-0000-000000000001';
delete from public.organization_limit_overrides
where organization_id = 'f3000000-0000-0000-0000-000000000001' and limit_key = 'website_chat_widgets';

select is(
  (select status from public.get_website_chat_widget_public_config(
    'a5000000-0000-0000-0000-000000000001', 'https://example.com'
  )),
  'not_entitled', 'a published widget with no active entitlement resolves as not_entitled'
);

select * from finish();

rollback;
