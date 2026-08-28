-- Website Chat WC2 (first slice): contractor widget management. Covers the privilege matrix,
-- permission gating, entitlement-cap enforcement (create, disable frees a slot, reactivate re-checks
-- the cap), optimistic-concurrency on update, origin validation/uniqueness, and tenant isolation.
--
-- Written for `supabase test db`, which runs the file as one session. Run inside a single transaction
-- that is rolled back (see contractor_settings_business.sql's note): `set local role` does not survive
-- a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'wc2-admin@example.test', 'test', now(), now(), now()),
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'wc2-field@example.test', 'test', now(), now(), now()),
  ('f1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'wc2-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f2000000-0000-0000-0000-000000000001', 'WC2 Widget Test Co', 'wc2-widget-test-co', 'active'),
  ('f2000000-0000-0000-0000-000000000002', 'WC2 Other Co', 'wc2-other-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'admin'),
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000002', 'field'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000003', 'admin');

-- Cap at 2 widgets, no package assignment needed -- an override alone resolves the entitlement.
insert into public.organization_limit_overrides (
  organization_id, limit_key, limit_state, limit_value, is_unlimited, starts_at
) values (
  'f2000000-0000-0000-0000-000000000001', 'website_chat_widgets', 'numeric', 2, false, now() - interval '1 minute'
);

-- 1. Privilege matrix -----------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.create_website_chat_widget(uuid, text, text, text, text, text, text, text, jsonb)', 'execute'),
  false, 'anonymous callers cannot create a website chat widget'
);
select is(
  has_function_privilege('authenticated', 'public.create_website_chat_widget(uuid, text, text, text, text, text, text, text, jsonb)', 'execute'),
  true, 'a signed-in session can call widget create'
);
select is(
  has_function_privilege('anon', 'public.update_website_chat_widget(uuid, uuid, integer, text, text, text, text, text, text, text, jsonb, boolean, boolean)', 'execute'),
  false, 'anonymous callers cannot update a website chat widget'
);
select is(
  has_function_privilege('authenticated', 'public.update_website_chat_widget(uuid, uuid, integer, text, text, text, text, text, text, text, jsonb, boolean, boolean)', 'execute'),
  true, 'a signed-in session can call widget update'
);
select is(
  has_function_privilege('anon', 'public.add_website_chat_widget_origin(uuid, uuid, text)', 'execute'),
  false, 'anonymous callers cannot add an origin'
);
select is(
  has_function_privilege('authenticated', 'public.add_website_chat_widget_origin(uuid, uuid, text)', 'execute'),
  true, 'a signed-in session can add an origin'
);
select is(
  has_function_privilege('anon', 'public.remove_website_chat_widget_origin(uuid, uuid, uuid)', 'execute'),
  false, 'anonymous callers cannot remove an origin'
);
select is(
  has_function_privilege('authenticated', 'public.remove_website_chat_widget_origin(uuid, uuid, uuid)', 'execute'),
  true, 'a signed-in session can remove an origin'
);

-- 2. A field member has no conversations.manage_connections by default ----------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.create_website_chat_widget(
      'f2000000-0000-0000-0000-000000000001', 'Field Attempt', 'bottom_right', null, null,
      'either', 'hidden', null, '[]'::jsonb
    )$$,
  '42501', null, 'a field member cannot create a widget'
);

select is(
  (select count(*)::integer from public.website_chat_widgets
   where organization_id = 'f2000000-0000-0000-0000-000000000001'),
  0, 'a field member sees zero widgets -- RLS blocks a role without manage_connections'
);

-- 3. An outsider admin (different org) cannot touch this organization's widgets --------------------------

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', true);

select throws_ok(
  $$select public.create_website_chat_widget(
      'f2000000-0000-0000-0000-000000000001', 'Outsider Attempt', 'bottom_right', null, null,
      'either', 'hidden', null, '[]'::jsonb
    )$$,
  '42501', null, 'a non-member cannot create a widget for this organization'
);

-- 4. As the admin: create up to the cap, then hit it ------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

select is(
  (public.create_website_chat_widget(
    'f2000000-0000-0000-0000-000000000001', 'Storefront Widget', 'bottom_right', 'Hi there', 'How can we help?',
    'either', 'hidden', null, '[]'::jsonb
  ) ->> 'name'),
  'Storefront Widget', 'the admin creates the first widget'
);

select is(
  (public.create_website_chat_widget(
    'f2000000-0000-0000-0000-000000000001', 'Support Widget', 'bottom_left', null, null,
    'phone', 'always', 'Support page', '[]'::jsonb
  ) ->> 'name'),
  'Support Widget', 'the admin creates the second widget, reaching the cap of 2'
);

select throws_ok(
  $$select public.create_website_chat_widget(
      'f2000000-0000-0000-0000-000000000001', 'Third Widget', 'bottom_right', null, null,
      'either', 'hidden', null, '[]'::jsonb
    )$$,
  '23514', null, 'a third widget is refused at the entitlement cap'
);

-- 5. Origins: format validation, add, duplicate, remove ----------------------------------------------------

select throws_ok(
  format(
    $$select public.add_website_chat_widget_origin('f2000000-0000-0000-0000-000000000001', %L, 'not-a-url')$$,
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget')
  ),
  '23514', null, 'a malformed origin is refused'
);

select is(
  (public.add_website_chat_widget_origin(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget'),
    'https://Example.com'
  ) ->> 'origin'),
  'https://example.com', 'a valid origin is added and normalized to lowercase'
);

select throws_ok(
  format(
    $$select public.add_website_chat_widget_origin('f2000000-0000-0000-0000-000000000001', %L, 'https://example.com')$$,
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget')
  ),
  '23505', null, 'the same origin cannot be added twice to one widget'
);

select is(
  (public.remove_website_chat_widget_origin(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget'),
    (select id from public.website_chat_widget_origins where origin = 'https://example.com')
  ) ->> 'status'),
  'deleted', 'the origin is removed'
);

select throws_ok(
  format(
    $$select public.remove_website_chat_widget_origin('f2000000-0000-0000-0000-000000000001', %L, %L)$$,
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget'),
    gen_random_uuid()
  ),
  '23514', null, 'removing an origin that no longer exists is refused, not a silent no-op'
);

-- 6. Update: stale revision is refused, a correct revision saves --------------------------------------------

select throws_ok(
  format(
    $$select public.update_website_chat_widget(
        'f2000000-0000-0000-0000-000000000001', %L, 99, 'Storefront Widget', 'bottom_right', null, null,
        'either', 'hidden', null, '[]'::jsonb, true, false
      )$$,
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget')
  ),
  '40001', null, 'a stale expected_revision is refused'
);

select is(
  (public.update_website_chat_widget(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget'),
    1, 'Storefront Widget', 'bottom_right', null, null, 'either', 'hidden', null, '[]'::jsonb, true, false
  ) ->> 'published')::boolean,
  true, 'the correct revision publishes the widget'
);

-- 7. Disabling frees a slot; reactivating re-checks the cap ---------------------------------------------------

select is(
  (public.update_website_chat_widget(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget'),
    2, 'Storefront Widget', 'bottom_right', null, null, 'either', 'hidden', null, '[]'::jsonb, true, true
  ) ->> 'disabled_at') is not null,
  true, 'disabling the storefront widget frees its slot'
);

select is(
  (public.create_website_chat_widget(
    'f2000000-0000-0000-0000-000000000001', 'Third Widget', 'bottom_right', null, null,
    'either', 'hidden', null, '[]'::jsonb
  ) ->> 'name'),
  'Third Widget', 'a third widget can now be created because the disabled one freed a slot'
);

select throws_ok(
  format(
    $$select public.update_website_chat_widget(
        'f2000000-0000-0000-0000-000000000001', %L, 3, 'Storefront Widget', 'bottom_right', null, null,
        'either', 'hidden', null, '[]'::jsonb, true, false
      )$$,
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Storefront Widget')
  ),
  '23514', null, 'reactivating the disabled widget is refused -- the cap is full again'
);

-- 8. Cross-tenant isolation -------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::integer from public.website_chat_widgets
   where organization_id = 'f2000000-0000-0000-0000-000000000001'),
  0, 'an outsider admin sees zero widgets for the other organization'
);

select throws_ok(
  format(
    $$select public.update_website_chat_widget(
        'f2000000-0000-0000-0000-000000000001', %L, 2, 'Hijacked', 'bottom_right', null, null,
        'either', 'hidden', null, '[]'::jsonb, true, false
      )$$,
    (select id from public.website_chat_widgets
     where organization_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Support Widget')
  ),
  '42501', null, 'an outsider admin cannot update another organization''s widget'
);

select * from finish();

rollback;
