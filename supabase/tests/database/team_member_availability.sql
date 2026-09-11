-- Team & access, part 3F: the three commands that say when a person can work.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention team_member_commands.sql documents. Do not
-- run it through a runner that executes each statement separately: `set local role` does not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

create temporary table tap_results (id serial primary key, line text);
-- Revisions are read before and after a save, so they are stashed as they are taken.
create temporary table revisions (label text primary key, value integer);

do $grant$
begin
  execute format(
    'grant usage on schema %I to service_role, authenticated',
    (select nspname from pg_namespace where oid = pg_my_temp_schema())
  );
end;
$grant$;
grant insert, select on tap_results to service_role, authenticated;
grant usage on sequence tap_results_id_seq to service_role, authenticated;
grant insert, select, update on revisions to service_role, authenticated;

-- 1. The shape of the thing -------------------------------------------------------------------------------

insert into tap_results (line) select has_table(
  'public', 'organization_member_availability', 'the weekly pattern table exists'
);
insert into tap_results (line) select has_table(
  'public', 'organization_member_availability_exceptions', 'the dated exception table exists'
);
insert into tap_results (line) select is(
  (select count(*)::int from pg_tables
    where schemaname = 'public'
      and tablename in (
        'organization_member_availability', 'organization_member_availability_exceptions'
      )
      and rowsecurity),
  2, 'row level security is on for both'
);

insert into tap_results (line) select has_function(
  'public', 'save_member_weekly_availability', 'the weekly pattern command exists'
);
insert into tap_results (line) select has_function(
  'public', 'save_member_availability_exception', 'the exception command exists'
);
insert into tap_results (line) select has_function(
  'public', 'delete_member_availability_exception', 'the exception removal command exists'
);

insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name in (
        'save_member_weekly_availability', 'save_member_availability_exception',
        'delete_member_availability_exception'
      )
      and grantee in ('anon', 'authenticated')),
  0, 'no browser session may call an availability command directly'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name in (
        'save_member_weekly_availability', 'save_member_availability_exception',
        'delete_member_availability_exception'
      )
      and grantee = 'service_role' and privilege_type = 'EXECUTE'),
  3, 'all three commands are callable by the server only'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'private'
      and routine_name = 'authorize_member_availability_command'
      and grantee in ('anon', 'authenticated', 'service_role')),
  0, 'the availability authority helper is nobody''s to call'
);

-- A browser session may read availability but never write it: the commands are the only way in.
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'organization_member_availability', 'organization_member_availability_exceptions'
      )
      and grantee = 'authenticated'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0, 'authenticated cannot insert, update or delete availability directly'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'organization_member_availability', 'organization_member_availability_exceptions'
      )
      and grantee = 'authenticated'
      and privilege_type = 'SELECT'),
  2, 'but may read both tables, because the Schedule has to'
);

-- 2. Fixtures ---------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at,
  raw_user_meta_data
)
values
  ('e2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'avail-owner@example.test', 'test', now(), now(), now(),
   '{"full_name": "Ava Owner"}'::jsonb),
  ('e2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'avail-admin@example.test', 'test', now(), now(), now(),
   '{"full_name": "Amir Admin"}'::jsonb),
  ('e2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'avail-field@example.test', 'test', now(), now(), now(),
   '{"full_name": "Farah Field"}'::jsonb),
  ('e2000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'avail-office@example.test', 'test', now(), now(), now(),
   '{"full_name": "Omar Office"}'::jsonb),
  ('e2000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'avail-off@example.test', 'test', now(), now(), now(),
   '{"full_name": "Dana Deactivated"}'::jsonb),
  ('e2000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'avail-other@example.test', 'test', now(), now(), now(),
   '{"full_name": "Otto Other"}'::jsonb);

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('e3000000-0000-0000-0000-000000000001', 'Availability Co', 'availability-co', 'active'),
  ('e3000000-0000-0000-0000-000000000002', 'Other Availability Co', 'other-availability-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000003', 'field', 'active'),
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000004', 'office', 'active'),
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000005', 'field', 'deactivated'),
  ('e3000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000006', 'owner', 'active');

set local role service_role;

-- 3. Nobody starts with a working week ---------------------------------------------------------------------

insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000001'),
  0, 'a new organization seeds no availability at all -- unset is not nine-to-five'
);
insert into tap_results (line) select is(
  (select availability_revision from public.organization_members
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  1, 'and every membership starts at revision 1'
);

-- 4. Who may change whose availability ----------------------------------------------------------------------

-- An office member is not a team manager, so somebody else's week is not theirs to set.
insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000004',
      'e2000000-0000-0000-0000-000000000003',
      null, 1
    )$$,
  '23514', null, 'an office member cannot set someone else''s availability'
);

-- The same office member setting their own is exactly what the blueprint allows, and is the case
-- private.authorize_team_member_command would have refused.
insert into tap_results (line) select lives_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000004',
      'e2000000-0000-0000-0000-000000000004',
      '[{"weekday":0,"is_working":false},{"weekday":1,"is_working":true,"starts_at":"09:00",
         "ends_at":"17:00"},{"weekday":2,"is_working":false},{"weekday":3,"is_working":false},
         {"weekday":4,"is_working":false},{"weekday":5,"is_working":false},{"weekday":6,"is_working":false}]'::jsonb,
      1
    )$$,
  'but may set their own'
);

-- Somebody with no membership at all is not an actor here, whichever organization they belong to.
insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000006',
      'e2000000-0000-0000-0000-000000000003',
      null, 1
    )$$,
  '23514', null, 'another company''s owner is not an actor in this one'
);

-- A deactivated person's week is not edited in place; restore them first, which is its own decision.
insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000005',
      null, 1
    )$$,
  '23514', null, 'a deactivated member''s availability is not editable'
);

insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000ff',
      null, 1
    )$$,
  -- plpgsql reports its own NO_DATA_FOUND as P0002, not the SQL standard's 02000.
  'P0002', null, 'and a stranger is not found at all'
);

-- 5. Seven days or none -------------------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      '[{"weekday":1,"is_working":true,"starts_at":"08:00","ends_at":"16:00"}]'::jsonb,
      1
    )$$,
  '23514', null, 'a pattern covering only Monday is refused -- a half-written week means nothing'
);

insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  0, 'and the refused save left no partial week behind'
);

-- A working day has to say when. The band constraint, not the application, is what refuses this.
insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      '[{"weekday":0,"is_working":false},{"weekday":1,"is_working":true},
        {"weekday":2,"is_working":false},{"weekday":3,"is_working":false},
        {"weekday":4,"is_working":false},{"weekday":5,"is_working":false},
        {"weekday":6,"is_working":false}]'::jsonb,
      1
    )$$,
  '23514', null, 'a working day with no hours is refused'
);

insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      '[{"weekday":0,"is_working":false},
        {"weekday":1,"is_working":true,"starts_at":"17:00","ends_at":"09:00"},
        {"weekday":2,"is_working":false},{"weekday":3,"is_working":false},
        {"weekday":4,"is_working":false},{"weekday":5,"is_working":false},
        {"weekday":6,"is_working":false}]'::jsonb,
      1
    )$$,
  '23514', null, 'and a day that ends before it starts is refused too'
);

-- The good save an administrator makes for somebody else.
insert into tap_results (line) select lives_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      '[{"weekday":0,"is_working":false},
        {"weekday":1,"is_working":true,"starts_at":"08:00","ends_at":"16:30"},
        {"weekday":2,"is_working":true,"starts_at":"08:00","ends_at":"16:30"},
        {"weekday":3,"is_working":true,"starts_at":"08:00","ends_at":"16:30"},
        {"weekday":4,"is_working":true,"starts_at":"08:00","ends_at":"16:30"},
        {"weekday":5,"is_working":true,"starts_at":"08:00","ends_at":"12:00"},
        {"weekday":6,"is_working":false}]'::jsonb,
      1
    )$$,
  'an administrator sets a field member''s working week'
);

insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  7, 'all seven days are stored'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'
      and is_working),
  5, 'five of them are working days'
);
insert into tap_results (line) select is(
  (select ends_at from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'
      and weekday = 5),
  time '12:00', 'and Friday keeps its short finish'
);
insert into tap_results (line) select is(
  (select availability_revision from public.organization_members
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  2, 'the accepted save moved the revision on by one'
);

-- 6. Conflict protection ------------------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      null, 1
    )$$,
  'P0409', null, 'a second editor holding the old revision conflicts instead of overwriting'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  7, 'and the week the first editor saved is still there'
);
insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      null, null
    )$$,
  'P0409', null, 'and sending no revision at all conflicts rather than being trusted'
);

-- 7. Dated exceptions ----------------------------------------------------------------------------------------

insert into tap_results (line) select lives_ok(
  $$select public.save_member_availability_exception(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      '2026-10-05', false, null, null, 'Annual leave', 2
    )$$,
  'an administrator marks a day off'
);
insert into tap_results (line) select is(
  (select reason from public.organization_member_availability_exceptions
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'
      and exception_date = '2026-10-05'),
  'Annual leave', 'the reason is kept, because this is the calendar and not the audit trail'
);

-- Saving the same date again corrects it rather than stacking a second answer behind the first.
insert into tap_results (line) select lives_ok(
  $$select public.save_member_availability_exception(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000003',
      'e2000000-0000-0000-0000-000000000003',
      '2026-10-05', true, '10:00', '14:00', 'Half day after all', 3
    )$$,
  'the member themselves corrects it to a short day'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability_exceptions
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'
      and exception_date = '2026-10-05'),
  1, 'and there is still exactly one answer for that date'
);
insert into tap_results (line) select is(
  (select starts_at from public.organization_member_availability_exceptions
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'
      and exception_date = '2026-10-05'),
  time '10:00', 'which is the corrected one'
);

insert into tap_results (line) select throws_ok(
  $$select public.save_member_availability_exception(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      '2026-10-06', true, '15:00', '09:00', null, 4
    )$$,
  '23514', null, 'an exception that ends before it starts is refused like any other band'
);

insert into tap_results (line) select throws_ok(
  $$select public.save_member_availability_exception(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000003',
      null, false, null, null, null, 4
    )$$,
  '23514', null, 'and an exception with no date is refused'
);

-- Removal, and the double-click that follows it.
insert into revisions (label, value)
select 'before_delete', availability_revision from public.organization_members
where organization_id = 'e3000000-0000-0000-0000-000000000001'
  and user_id = 'e2000000-0000-0000-0000-000000000003';

insert into tap_results (line) select lives_ok(
  format(
    $$select public.delete_member_availability_exception(
        'e3000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000002',
        'e2000000-0000-0000-0000-000000000003',
        %L, %s
      )$$,
    (select id from public.organization_member_availability_exceptions
      where organization_id = 'e3000000-0000-0000-0000-000000000001'
        and user_id = 'e2000000-0000-0000-0000-000000000003'
        and exception_date = '2026-10-05'),
    (select value from revisions where label = 'before_delete')
  ),
  'the exception is removed'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability_exceptions
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  0, 'and that date goes back to the ordinary week'
);

-- Removing something already gone changes nothing, so the second click of a double-click cannot conflict.
insert into revisions (label, value)
select 'after_delete', availability_revision from public.organization_members
where organization_id = 'e3000000-0000-0000-0000-000000000001'
  and user_id = 'e2000000-0000-0000-0000-000000000003';

insert into tap_results (line) select lives_ok(
  format(
    $$select public.delete_member_availability_exception(
        'e3000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000002',
        'e2000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000000aa', %s
      )$$,
    (select value from revisions where label = 'after_delete')
  ),
  'removing an exception that is already gone is not an error'
);
insert into tap_results (line) select is(
  (select availability_revision from public.organization_members
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  (select value from revisions where label = 'after_delete'),
  'and it does not move the revision, so nobody else''s open editor is invalidated'
);

-- 8. Clearing the pattern -------------------------------------------------------------------------------------

insert into tap_results (line) select lives_ok(
  format(
    $$select public.save_member_weekly_availability(
        'e3000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000002',
        'e2000000-0000-0000-0000-000000000003',
        '[]'::jsonb, %s
      )$$,
    (select value from revisions where label = 'after_delete')
  ),
  'an empty pattern clears the week'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and user_id = 'e2000000-0000-0000-0000-000000000003'),
  0, 'back to nobody having said when this person works'
);

-- 9. The history ------------------------------------------------------------------------------------------------

insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and event_type = 'member.availability_updated'
      and subject_user_id = 'e2000000-0000-0000-0000-000000000003'),
  5, 'every accepted change recorded exactly one history line, and no refused one did'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and event_type = 'member.availability_updated'
      and summary -> 'changed' ? 'weekly_pattern'),
  3, 'three of them name the weekly pattern'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where organization_id = 'e3000000-0000-0000-0000-000000000001'
      and event_type = 'member.availability_updated'
      and summary -> 'changed' ? 'exceptions'),
  3, 'and three name the exceptions'
);

-- The allow-list still has no way to carry a reason, a date or a name into the audit trail.
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
    ) values (
      'e3000000-0000-0000-0000-000000000001', 'member.availability_updated', 'member',
      'e2000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000003',
      '{"changed": ["Annual leave"]}'::jsonb
    )$$,
  null, null, 'a free-text value cannot ride into the history on the availability event'
);

-- 10. Tenant isolation -----------------------------------------------------------------------------------------

set local role postgres;
insert into public.organization_member_availability
  (organization_id, user_id, weekday, is_working, starts_at, ends_at)
values
  ('e3000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000006', 1, true, '07:00', '15:00');

set local role authenticated;
set local request.jwt.claims to '{"sub": "e2000000-0000-0000-0000-000000000004", "role": "authenticated"}';

-- Everything this office member can see belongs to their own company. The seven rows are the week they set
-- for themselves earlier in this file; the row just written for the other company is not among them.
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id <> 'e3000000-0000-0000-0000-000000000001'),
  0, 'a member reads only their own organization''s availability'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where organization_id = 'e3000000-0000-0000-0000-000000000002'),
  0, 'and the other company''s week is invisible'
);

-- The office member can see a teammate's week even with no team.manage permission, because the Schedule
-- needs exactly that.
set local role postgres;
insert into public.organization_member_availability
  (organization_id, user_id, weekday, is_working, starts_at, ends_at)
values
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000003', 1, true, '08:00', '16:30');

set local role authenticated;
set local request.jwt.claims to '{"sub": "e2000000-0000-0000-0000-000000000004", "role": "authenticated"}';

insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_availability
    where user_id = 'e2000000-0000-0000-0000-000000000003'),
  1, 'an office member with no team permission still sees a teammate''s working week'
);

-- And still cannot write one by hand.
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_availability
      (organization_id, user_id, weekday, is_working, starts_at, ends_at)
    values ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000004', 2, true,
            '00:00', '23:00')$$,
  '42501', null, 'a browser session cannot write a working week directly, not even its own'
);
insert into tap_results (line) select throws_ok(
  $$select public.save_member_weekly_availability(
      'e3000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000004',
      'e2000000-0000-0000-0000-000000000004',
      null, 2
    )$$,
  '42501', null, 'nor reach the command that would have let it'
);

set local role postgres;

select * from finish();

select line from tap_results where line like 'not ok%' order by id;

rollback;
