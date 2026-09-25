-- Files and Media, Part 8B: the promises the organization export job makes in the database itself.
--
--   1. Requesting an export queues one row; requesting again while it is queued/processing hands back the
--      same row instead of piling up duplicates.
--   2. The worker claims the oldest queued row, marks it processing, and a second claim with nothing queued
--      returns null.
--   3. Finishing requires object_key + expires_at for 'available', accepts a plain error for 'failed', and
--      refuses to finish a row that was never claimed.
--   4. The expiry sweep clears object_key and moves an available-but-expired row to 'expired' without
--      deleting it; a row not yet due is untouched; the sweep is a no-op the second time.
--   5. files.export is owner-only -- unlike files.manage, an admin sees none of it -- and scoped to the
--      caller's own organization.
--   6. The table's own check constraints hold even bypassing the functions above.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'export-owner@example.test', 'test', now(), now(), now()),
  ('b1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'export-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('b2000000-0000-0000-0000-000000000001', 'Export Co', 'export-co', 'active'),
  ('b2000000-0000-0000-0000-000000000002', 'Export Co Two', 'export-co-two', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'admin', 'active');

-- ---------------------------------------------------------------------------------------------------------
-- 1. Requesting: queues once, dedupes while queued/processing
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select status from public.request_organization_export(
    'b2000000-0000-0000-0000-000000000001'::uuid, 'b1000000-0000-0000-0000-000000000001'::uuid)),
  'queued',
  'requesting an export queues one row'
);

select is(
  (select count(*)::integer from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  1,
  'exactly one row exists after the first request'
);

select is(
  (select id from public.request_organization_export(
    'b2000000-0000-0000-0000-000000000001'::uuid, 'b1000000-0000-0000-0000-000000000001'::uuid)),
  (select id from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  'requesting again while queued hands back the same row'
);

select is(
  (select count(*)::integer from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  1,
  'no duplicate row was inserted'
);

-- ---------------------------------------------------------------------------------------------------------
-- 2. Claiming
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select status from public.claim_next_organization_export()),
  'processing',
  'the worker claims the oldest queued row'
);

select is(
  (select status from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  'processing',
  'the row itself is now processing'
);

select is(
  (select count(*)::integer from public.claim_next_organization_export()),
  0,
  'a second claim with nothing queued returns nothing'
);

-- ---------------------------------------------------------------------------------------------------------
-- 3. Finishing
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.finalize_organization_export(
      (select id from public.organization_exports where organization_id = 'b2000000-0000-0000-0000-000000000001'),
      'available')$$,
  '23514',
  'An available export needs its object key and expiry.',
  'finishing available without an object key and expiry is refused'
);

select is(
  (select status from public.finalize_organization_export(
    (select id from public.organization_exports where organization_id = 'b2000000-0000-0000-0000-000000000001'),
    'available', 'b2000000-0000-0000-0000-000000000001/exports/one.zip', 12, 104857600,
    now() + interval '7 days')),
  'available',
  'a real object key and expiry finish the export as available'
);

select is(
  (select object_key from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  'b2000000-0000-0000-0000-000000000001/exports/one.zip',
  'the object key is recorded'
);

select ok(
  (select completed_at from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001') is not null,
  'completed_at is stamped'
);

select throws_ok(
  $$select public.finalize_organization_export(
      (select id from public.organization_exports where organization_id = 'b2000000-0000-0000-0000-000000000001'),
      'available', 'x', 1, 1, now() + interval '1 day')$$,
  'P0002',
  'That export was not claimed for processing.',
  'finishing an export that is not processing (it is already available) is refused'
);

-- A fresh request, claim, and a failed finish -- proves the error path independent of the success path above.
select public.request_organization_export(
  'b2000000-0000-0000-0000-000000000001'::uuid, 'b1000000-0000-0000-0000-000000000001'::uuid);
select public.claim_next_organization_export();

select is(
  (select status from public.finalize_organization_export(
    (select id from public.organization_exports
     where organization_id = 'b2000000-0000-0000-0000-000000000001' and status = 'processing'),
    'failed', null, null, null, null, 'R2 was unreachable.')),
  'failed',
  'a failed finish records the failure without an object key'
);

select is(
  (select error from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001' and status = 'failed'),
  'R2 was unreachable.',
  'the error message is kept'
);

select is(
  (select object_key from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001' and status = 'failed'),
  null,
  'a failed export never gets an object key'
);

-- ---------------------------------------------------------------------------------------------------------
-- 4. Expiry sweep
-- ---------------------------------------------------------------------------------------------------------

update public.organization_exports
set expires_at = now() - interval '1 hour'
where organization_id = 'b2000000-0000-0000-0000-000000000001' and status = 'available';

insert into public.organization_exports (organization_id, requested_by, status, object_key, expires_at, completed_at)
values ('b2000000-0000-0000-0000-000000000002', null, 'available',
        'b2000000-0000-0000-0000-000000000002/exports/still-valid.zip', now() + interval '7 days', now());

select is(
  (select object_key from public.purge_expired_organization_exports()),
  'b2000000-0000-0000-0000-000000000001/exports/one.zip',
  'the sweep hands back the object key of the export it just expired'
);

select is(
  (select status from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001' and object_key is null and error is null),
  'expired',
  'the expired export moves to the expired state'
);

select is(
  (select count(*)::integer from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001'
     and status = 'expired' and object_key is not null),
  0,
  'its object key is cleared, never left dangling'
);

select is(
  (select status from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000002'),
  'available',
  'a second organization''s not-yet-due export is untouched'
);

select is(
  (select count(*)::integer from public.purge_expired_organization_exports()),
  0,
  'nothing is left to purge on a second run'
);

-- ---------------------------------------------------------------------------------------------------------
-- 5. files.export is owner-only, scoped to the caller's own organization
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  2,
  'the owner sees their organization''s exports (the failed one and the now-expired one)'
);

select is(
  (select count(*)::integer from public.organization_exports
   where organization_id = 'b2000000-0000-0000-0000-000000000002'),
  0,
  'and none of a different organization''s'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::integer from public.organization_exports),
  0,
  'an admin -- who holds files.manage but not files.export -- sees none of it'
);

reset role;

-- ---------------------------------------------------------------------------------------------------------
-- 6. Table constraints hold on a direct write, not only through the functions
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$insert into public.organization_exports (organization_id, status)
    values ('b2000000-0000-0000-0000-000000000001', 'bogus')$$,
  '23514',
  null,
  'an unrecognized status is refused'
);

select * from finish();

rollback;
