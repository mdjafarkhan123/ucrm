begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

select has_table('public', 'platform_operation_attempts', 'operation attempts table exists');
select has_table('public', 'platform_owner_notifications', 'owner notifications table exists');
select has_table('public', 'platform_outbox_deliveries', 'outbox deliveries table exists');
select has_index('public', 'platform_operation_attempts', 'platform_operation_attempts_operation_key_idx', 'operation type + idempotency key unique index exists');

select is((select relrowsecurity from pg_class where oid = 'public.platform_operation_attempts'::regclass), true, 'operation attempts RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.platform_owner_notifications'::regclass), true, 'owner notifications RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.platform_outbox_deliveries'::regclass), true, 'outbox deliveries RLS is enabled');

select is(has_table_privilege('anon', 'public.platform_operation_attempts', 'select'), false, 'anonymous callers cannot read operation attempts');
select is(has_table_privilege('authenticated', 'public.platform_operation_attempts', 'select'), false, 'contractors cannot read operation attempts');
select is(has_table_privilege('anon', 'public.platform_operation_attempts', 'insert'), false, 'anonymous callers cannot write operation attempts');
select is(has_table_privilege('service_role', 'public.platform_operation_attempts', 'select'), true, 'owner service role can read operation attempts');
select is(has_table_privilege('service_role', 'public.platform_operation_attempts', 'insert'), true, 'owner service role can insert operation attempts');

select is(has_table_privilege('anon', 'public.platform_owner_notifications', 'select'), false, 'anonymous callers cannot read owner notifications');
select is(has_table_privilege('authenticated', 'public.platform_owner_notifications', 'select'), false, 'contractors cannot read owner notifications');
select is(has_table_privilege('service_role', 'public.platform_owner_notifications', 'select'), true, 'owner service role can read owner notifications');

select is(has_table_privilege('anon', 'public.platform_outbox_deliveries', 'select'), false, 'anonymous callers cannot read outbox deliveries');
select is(has_table_privilege('authenticated', 'public.platform_outbox_deliveries', 'select'), false, 'contractors cannot read outbox deliveries');
select is(has_table_privilege('service_role', 'public.platform_outbox_deliveries', 'select'), true, 'owner service role can read outbox deliveries');

select has_column('public', 'platform_owner_audit_events', 'correlation_id', 'audit events gained a correlation id column');

set local role postgres;

-- Simulates the race `recordOperationOutcome` guards against: two concurrent failures for the
-- same operation instance both missing the row on lookup and both trying to insert it. The
-- unique index is the actual safety net -- the second insert must fail, not silently duplicate.
select lives_ok(
  $$insert into public.platform_operation_attempts (operation_type, idempotency_key, target_kind, target_id, status, attempt_count, last_error) values ('test_operations_foundation_op', 'dup-key-1', 'platform', null, 'retrying', 1, 'first failure')$$,
  'the first failed attempt for an operation instance is recorded'
);
select throws_ok(
  $$insert into public.platform_operation_attempts (operation_type, idempotency_key, target_kind, target_id, status, attempt_count, last_error) values ('test_operations_foundation_op', 'dup-key-1', 'platform', null, 'retrying', 1, 'concurrent duplicate')$$,
  '23505',
  null,
  'a second concurrent failure for the same operation instance cannot duplicate the row'
);

select throws_ok(
  $$insert into public.platform_operation_attempts (operation_type, idempotency_key, target_kind, target_id) values ('test_operations_foundation_op', 'bad-target-1', 'platform', gen_random_uuid())$$,
  '23514',
  null,
  'a platform-scoped operation attempt cannot carry a target id'
);
select throws_ok(
  $$insert into public.platform_operation_attempts (operation_type, idempotency_key, target_kind, target_id) values ('test_operations_foundation_op', 'bad-target-2', 'organization', null)$$,
  '23514',
  null,
  'an organization-scoped operation attempt requires a target id'
);

select throws_ok(
  $$insert into public.platform_operation_attempts (operation_type, idempotency_key, target_kind, target_id, status) values ('test_operations_foundation_op', 'bad-resolution-1', 'platform', null, 'manually_resolved')$$,
  '23514',
  null,
  'a manually resolved operation attempt requires its resolution fields'
);
select lives_ok(
  $$insert into public.platform_operation_attempts (operation_type, idempotency_key, target_kind, target_id, status, resolved_at, resolved_by_owner_email, resolution_note) values ('test_operations_foundation_op', 'resolved-1', 'platform', null, 'manually_resolved', now(), 'owner@example.test', 'Resolved for the operations foundation test.')$$,
  'a manually resolved operation attempt with complete resolution fields is accepted'
);

select lives_ok(
  $$insert into public.platform_owner_notifications (id, kind, severity, title, target_kind, target_id) values ('20000000-0000-0000-0000-000000000001', 'test.notification', 'attention', 'Test notification', 'platform', null)$$,
  'an owner notification can be created'
);
select lives_ok(
  $$update public.platform_owner_notifications set read_at = now() where id = '20000000-0000-0000-0000-000000000001'$$,
  'marking a notification read only changes read_at'
);
select throws_ok(
  $$update public.platform_owner_notifications set title = 'Changed title' where id = '20000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'a notification title cannot be changed after creation'
);
select throws_ok(
  $$delete from public.platform_owner_notifications where id = '20000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'an owner notification cannot be deleted'
);

insert into public.platform_owner_audit_events (actor_owner_email, event_type, target_type, target_key)
values ('owner@example.test', 'test.operations_foundation', 'platform', null);

select throws_ok(
  $$update public.platform_owner_audit_events set event_type = 'test.changed' where event_type = 'test.operations_foundation'$$,
  '23514',
  null,
  'an audit event cannot be changed after creation'
);
select throws_ok(
  $$delete from public.platform_owner_audit_events where event_type = 'test.operations_foundation'$$,
  '23514',
  null,
  'an audit event cannot be deleted'
);

select * from finish();
rollback;
