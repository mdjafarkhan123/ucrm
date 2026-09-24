-- Files and Media, Part 7C: a work report's photos in order, under optional headings, with before/after pairs.
--
--   1. The arrangement saves and reads back exactly; a photo may appear only once, a pair needs both halves,
--      and a heading needs a name.
--   2. The customer document lists photos in the arranged order and places them with `layout`; a report with
--      no heading and no pair carries no `layout`, so it is the document it was before 7C.
--   3. The live customer link reports whether it still matches what a new link would show.
--   4. Trashing half of a pair leaves the other half as a single photo in the editor, and the customer's copy
--      keeps the pair's place with the trashed half shown as removed.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('c7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'layout-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c8000000-0000-0000-0000-000000000001', 'Layout Co', 'layout-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values ('c8000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001', 'admin', 'active');

insert into public.clients (id, organization_id, display_name)
values ('c9000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000001', 'Lena Layout');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values ('cc000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000001',
        'c9000000-0000-0000-0000-000000000001', 'email', 'lena@example.test');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('ca000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000001',
        'c9000000-0000-0000-0000-000000000001', '3 Layout Lane', 'Testville', 'TX', '78741');

insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code)
values ('cb000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000001',
        'c9000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001',
        900, 'Kitchen refit', 'one_off', 'job_total', 'USD');

-- Four job photos, uploaded 1 -> 4, so upload order is 1, 2, 3, 4.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, processing_state, uploaded_by, scanned_at, checksum_sha256, created_at)
select ('ce000000-0000-0000-0000-00000000000' || n)::uuid, 'c8000000-0000-0000-0000-000000000001',
       'photo-' || n || '.jpg', 'image/jpeg', 2048, 'c8/files/' || n || '.jpg', 'file_manager', 'available',
       'c7000000-0000-0000-0000-000000000001', now(), repeat(n::text, 64), now() - (5 - n) * interval '1 minute'
from generate_series(1, 4) as n;

insert into public.file_links (organization_id, file_id, entity_type, entity_id, role)
select 'c8000000-0000-0000-0000-000000000001', ('ce000000-0000-0000-0000-00000000000' || n)::uuid,
       'job', 'cb000000-0000-0000-0000-000000000001', 'attachment'
from generate_series(1, 4) as n;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c7000000-0000-0000-0000-000000000001', true);

-- ---------------------------------------------------------------------------------------------------------
-- 1. Saving and reading the arrangement
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
      '{"top": [{"file_id": "ce000000-0000-0000-0000-000000000001"}],
        "sections": [{"heading": "Again", "note": null,
                      "items": [{"file_id": "ce000000-0000-0000-0000-000000000001"}]}]}'::jsonb)$$,
  'P0400', 'A photo can appear only once in a report.', 'the same photo twice is refused');

select throws_ok(
  $$select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
      '{"top": [{"before_file_id": "ce000000-0000-0000-0000-000000000001"}], "sections": []}'::jsonb)$$,
  'P0400', 'A before/after pair needs both photos.', 'a pair with one half is refused');

select throws_ok(
  $$select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
      '{"top": [], "sections": [{"heading": "  ", "note": null, "items": []}]}'::jsonb)$$,
  'P0400', null, 'a heading with no name is refused');

-- Photo 4 on its own at the top; then "Kitchen" with a note holding a pair (before 3, after 1); then
-- "Extras" holding photo 2.
select lives_ok(
  $$select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
      '{"top": [{"file_id": "ce000000-0000-0000-0000-000000000004"}],
        "sections": [
          {"heading": " Kitchen ", "note": "Old units out, new ones in.",
           "items": [{"before_file_id": "ce000000-0000-0000-0000-000000000003",
                      "after_file_id": "ce000000-0000-0000-0000-000000000001"}]},
          {"heading": "Extras", "note": "", "items": [{"file_id": "ce000000-0000-0000-0000-000000000002"}]}
        ]}'::jsonb)$$,
  'an arranged report with a pair and two headings saves');

select is(
  public.job_report_state('cb000000-0000-0000-0000-000000000001') -> 'report' -> 'layout',
  '{"top": [{"file_id": "ce000000-0000-0000-0000-000000000004"}],
    "sections": [
      {"heading": "Kitchen", "note": "Old units out, new ones in.",
       "items": [{"before_file_id": "ce000000-0000-0000-0000-000000000003",
                  "after_file_id": "ce000000-0000-0000-0000-000000000001"}]},
      {"heading": "Extras", "note": null, "items": [{"file_id": "ce000000-0000-0000-0000-000000000002"}]}
    ]}'::jsonb,
  'the arrangement reads back as saved, heading trimmed and an empty note dropped');

select is(
  public.job_report_state('cb000000-0000-0000-0000-000000000001') -> 'report' -> 'photo_ids',
  '["ce000000-0000-0000-0000-000000000004", "ce000000-0000-0000-0000-000000000003",
    "ce000000-0000-0000-0000-000000000001", "ce000000-0000-0000-0000-000000000002"]'::jsonb,
  'photo_ids follow the arrangement, a pair''s before ahead of its after');

-- ---------------------------------------------------------------------------------------------------------
-- 2. The customer document
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select jsonb_agg(photo ->> 'file_name') from jsonb_array_elements(
     public.job_report_customer_preview('cb000000-0000-0000-0000-000000000001') -> 'document' -> 'photos') photo),
  '["photo-4.jpg", "photo-3.jpg", "photo-1.jpg", "photo-2.jpg"]'::jsonb,
  'the customer''s photos come in the arranged order');

select is(
  public.job_report_customer_preview('cb000000-0000-0000-0000-000000000001') -> 'document' -> 'layout',
  '{"top": [{"photo": 0}],
    "sections": [
      {"heading": "Kitchen", "note": "Old units out, new ones in.", "items": [{"before": 1, "after": 2}]},
      {"heading": "Extras", "note": null, "items": [{"photo": 3}]}
    ]}'::jsonb,
  'the layout places each photo, and the pair, by its index in that list');

select lives_ok(
  $$select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
      '{"top": [{"file_id": "ce000000-0000-0000-0000-000000000002"},
                {"file_id": "ce000000-0000-0000-0000-000000000001"}], "sections": []}'::jsonb)$$,
  'a plain reordered list saves, and the headings go');

select ok(
  not (public.job_report_customer_preview('cb000000-0000-0000-0000-000000000001') -> 'document' ? 'layout'),
  'with no heading and no pair the document carries no layout');

select is(
  (select jsonb_agg(photo ->> 'file_name') from jsonb_array_elements(
     public.job_report_customer_preview('cb000000-0000-0000-0000-000000000001') -> 'document' -> 'photos') photo),
  '["photo-2.jpg", "photo-1.jpg"]'::jsonb,
  'but its photos still follow the contractor''s order, not upload time');

reset role;

select is(
  (select count(*)::int from public.job_report_sections where job_id = 'cb000000-0000-0000-0000-000000000001'),
  0, 'the removed headings are gone from the table');

-- ---------------------------------------------------------------------------------------------------------
-- 3. Is the customer's link up to date?
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c7000000-0000-0000-0000-000000000001', true);

select is(
  public.job_report_state('cb000000-0000-0000-0000-000000000001') -> 'live_link',
  'null'::jsonb, 'before any link is issued there is no live link');

select lives_ok(
  $$select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
      '{"top": [],
        "sections": [{"heading": "Kitchen", "note": null,
                      "items": [{"before_file_id": "ce000000-0000-0000-0000-000000000003",
                                 "after_file_id": "ce000000-0000-0000-0000-000000000001"},
                                {"file_id": "ce000000-0000-0000-0000-000000000002"}]}]}'::jsonb)$$,
  'a report with a pair is saved');

select public.issue_job_report_access_link('cb000000-0000-0000-0000-000000000001', decode(repeat('cd', 32), 'hex'));

select is(
  public.job_report_state('cb000000-0000-0000-0000-000000000001') -> 'live_link' ->> 'up_to_date',
  'true', 'right after issuing, the link matches the report');

-- Swap the pair's sides.
select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
  '{"top": [],
    "sections": [{"heading": "Kitchen", "note": null,
                  "items": [{"before_file_id": "ce000000-0000-0000-0000-000000000001",
                             "after_file_id": "ce000000-0000-0000-0000-000000000003"},
                            {"file_id": "ce000000-0000-0000-0000-000000000002"}]}]}'::jsonb);

select is(
  public.job_report_state('cb000000-0000-0000-0000-000000000001') -> 'live_link' ->> 'up_to_date',
  'false', 'after swapping the pair, the customer''s link is behind');

-- Swap back: the report is again exactly what the customer has.
select public.save_job_report('cb000000-0000-0000-0000-000000000001', false, false, null, null,
  '{"top": [],
    "sections": [{"heading": "Kitchen", "note": null,
                  "items": [{"before_file_id": "ce000000-0000-0000-0000-000000000003",
                             "after_file_id": "ce000000-0000-0000-0000-000000000001"},
                            {"file_id": "ce000000-0000-0000-0000-000000000002"}]}]}'::jsonb);

select is(
  public.job_report_state('cb000000-0000-0000-0000-000000000001') -> 'live_link' ->> 'up_to_date',
  'true', 'putting it back the way it was sent makes the link current again');

reset role;

-- ---------------------------------------------------------------------------------------------------------
-- 4. Trashing half of a pair
-- ---------------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.trash_file('c8000000-0000-0000-0000-000000000001', 'ce000000-0000-0000-0000-000000000003',
      'c7000000-0000-0000-0000-000000000001', true)$$,
  'the pair''s before photo goes to Trash');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c7000000-0000-0000-0000-000000000001', true);

select is(
  public.job_report_state('cb000000-0000-0000-0000-000000000001') -> 'report' -> 'layout' -> 'sections' -> 0 -> 'items',
  '[{"file_id": "ce000000-0000-0000-0000-000000000001"}, {"file_id": "ce000000-0000-0000-0000-000000000002"}]'::jsonb,
  'the editor now shows the surviving half as a single photo in the pair''s place');

reset role;

select is(
  (select jsonb_build_object(
     'removed', resolved -> 'photos' -> 0 -> 'removed',
     'items', resolved -> 'layout' -> 'sections' -> 0 -> 'items')
   from public.resolve_job_report_access_link(decode(repeat('cd', 32), 'hex')) as resolved),
  '{"removed": true, "items": [{"before": 0, "after": 1}, {"photo": 2}]}'::jsonb,
  'the customer''s copy keeps the pair, with the trashed half shown as removed');

select * from finish();

rollback;
