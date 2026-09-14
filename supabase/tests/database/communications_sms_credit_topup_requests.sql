-- Communications A2 / Stage 2C (part 1): offsite credit top-up requests create no spendable credit until
-- Jafar confirms receipt, confirmation posts exactly one immutable ledger credit, and only an awaiting request
-- can be cancelled or rejected.
begin;

create extension if not exists pgtap with schema extensions;
select plan(29);

-- Shape and access boundary.
select has_table('public', 'communication_sms_credit_topup_requests',
  'top-up requests are a first-class record');
select col_is_pk('public', 'communication_sms_credit_topup_requests', 'id',
  'each top-up request has a stable identity');
select has_index('public', 'communication_sms_credit_topup_requests',
  'communication_sms_credit_topup_requests_org_history_idx',
  'a bounded ordered index backs one organization''s request history');
select has_index('public', 'communication_sms_credit_topup_requests',
  'communication_sms_credit_topup_requests_awaiting_idx',
  'a partial index backs the owner confirm queue');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_credit_topup_requests'::regclass),
  'top-up requests keep row-level security enabled'
);
select table_privs_are('public', 'communication_sms_credit_topup_requests', 'authenticated', array[]::text[],
  'authenticated clients have no direct top-up request privileges');
select table_privs_are('public', 'communication_sms_credit_topup_requests', 'anon', array[]::text[],
  'anonymous clients have no direct top-up request privileges');
select table_privs_are('public', 'communication_sms_credit_topup_requests', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE'],
  'only the server role reads/writes top-up requests directly, never deletes');

-- Fixtures: two isolated organizations and stable actor ids.
insert into public.organizations (id, name, slug, lifecycle_status) values
  ('b2c10000-0000-4000-8000-000000000001', 'Topup Org A', 'topup-org-a', 'active'),
  ('b2c10000-0000-4000-8000-000000000002', 'Topup Org B', 'topup-org-b', 'active');

-- A contractor request creates an awaiting row and, on its own, no spendable credit.
select is(
  (public.communication_sms_request_credit_topup(
    'b2c10000-0000-4000-8000-000000000001', 'b2c1ac70-0000-4000-8000-000000000001', 5000, 'USD', 'wire-0001', 'first top-up'
  )).status,
  'awaiting_confirmation',
  'a submitted request starts awaiting confirmation'
);
select is(
  (select count(*)::int from public.communication_sms_credit_accounts
   where organization_id = 'b2c10000-0000-4000-8000-000000000001'),
  0,
  'a request alone creates no credit account and no spendable balance'
);

-- A non-positive requested amount is refused by the constraint.
select throws_ok(
  $$select public.communication_sms_request_credit_topup(
    'b2c10000-0000-4000-8000-000000000001', 'b2c1ac70-0000-4000-8000-000000000001', -100)$$,
  '23514', null,
  'a request must ask for a positive amount'
);

-- Confirm posts one immutable credit and raises the balance atomically.
insert into public.communication_sms_credit_topup_requests (id, organization_id, requested_by, requested_amount_minor)
values ('b2c1e900-0000-4000-8000-000000000001', 'b2c10000-0000-4000-8000-000000000001',
        'b2c1ac70-0000-4000-8000-000000000001', 5000);

select is(
  (public.communication_sms_confirm_credit_topup(
    'b2c1e900-0000-4000-8000-000000000001', 'b2c1ad30-0000-4000-8000-000000000009', 5000, 'wire received')).status,
  'confirmed',
  'confirming a request marks it confirmed'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'b2c10000-0000-4000-8000-000000000001'),
  5000::bigint,
  'confirmation raises the settled balance by the settled amount'
);
select is(
  (select count(*)::int from public.communication_sms_credit_ledger_entries
   where organization_id = 'b2c10000-0000-4000-8000-000000000001'
     and source_key = 'topup:b2c1e900-0000-4000-8000-000000000001'),
  1,
  'confirmation posts exactly one ledger entry keyed to the request'
);
select is(
  (select entry_kind || ':' || amount_minor::text from public.communication_sms_credit_ledger_entries
   where source_key = 'topup:b2c1e900-0000-4000-8000-000000000001'),
  'credit:5000',
  'the posted entry is a purchased credit for the settled amount'
);
select is(
  (select settled_amount_minor from public.communication_sms_credit_topup_requests
   where id = 'b2c1e900-0000-4000-8000-000000000001'),
  5000::bigint,
  'the confirmed request records the settled amount'
);

-- Confirming again is refused: the awaiting guard makes confirmation single-shot.
select throws_ok(
  $$select public.communication_sms_confirm_credit_topup(
    'b2c1e900-0000-4000-8000-000000000001', 'b2c1ad30-0000-4000-8000-000000000009', 5000)$$,
  'P0001', null,
  'a confirmed request cannot be confirmed twice'
);

-- The settled amount may differ from the requested amount; a zero settlement is refused.
insert into public.communication_sms_credit_topup_requests (id, organization_id, requested_by, requested_amount_minor)
values ('b2c1e900-0000-4000-8000-000000000002', 'b2c10000-0000-4000-8000-000000000001',
        'b2c1ac70-0000-4000-8000-000000000001', 8000);
select throws_ok(
  $$select public.communication_sms_confirm_credit_topup(
    'b2c1e900-0000-4000-8000-000000000002', 'b2c1ad30-0000-4000-8000-000000000009', 0)$$,
  'P0001', null,
  'a confirmation must record a positive settled amount'
);
select is(
  (public.communication_sms_confirm_credit_topup(
    'b2c1e900-0000-4000-8000-000000000002', 'b2c1ad30-0000-4000-8000-000000000009', 6000)).settled_amount_minor,
  6000::bigint,
  'the settled amount, not the requested amount, is what is credited'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'b2c10000-0000-4000-8000-000000000001'),
  11000::bigint,
  'the balance reflects both confirmed settlements'
);

-- Reject: needs a reason, posts no credit, leaves the balance untouched.
insert into public.communication_sms_credit_topup_requests (id, organization_id, requested_by, requested_amount_minor)
values ('b2c1e900-0000-4000-8000-000000000003', 'b2c10000-0000-4000-8000-000000000001',
        'b2c1ac70-0000-4000-8000-000000000001', 3000);
select throws_ok(
  $$select public.communication_sms_reject_credit_topup(
    'b2c1e900-0000-4000-8000-000000000003', 'b2c1ad30-0000-4000-8000-000000000009', '   ')$$,
  'P0001', null,
  'a rejection must record a reason'
);
select is(
  (public.communication_sms_reject_credit_topup(
    'b2c1e900-0000-4000-8000-000000000003', 'b2c1ad30-0000-4000-8000-000000000009', 'no payment received')).status,
  'rejected',
  'a rejected request is marked rejected'
);
select throws_ok(
  $$select public.communication_sms_reject_credit_topup(
    'b2c1e900-0000-4000-8000-000000000003', 'b2c1ad30-0000-4000-8000-000000000009', 'again')$$,
  'P0001', null,
  'only an awaiting request can be rejected'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'b2c10000-0000-4000-8000-000000000001'),
  11000::bigint,
  'a rejection never changes the balance'
);
select is(
  (select count(*)::int from public.communication_sms_credit_ledger_entries
   where organization_id = 'b2c10000-0000-4000-8000-000000000001'),
  2,
  'a rejection posts no ledger entry'
);

-- Cancel: a contractor may cancel only a still-awaiting request.
insert into public.communication_sms_credit_topup_requests (id, organization_id, requested_by, requested_amount_minor)
values ('b2c1e900-0000-4000-8000-000000000004', 'b2c10000-0000-4000-8000-000000000001',
        'b2c1ac70-0000-4000-8000-000000000001', 2000);
select is(
  (public.communication_sms_cancel_credit_topup(
    'b2c1e900-0000-4000-8000-000000000004', 'b2c1ac70-0000-4000-8000-000000000001')).status,
  'cancelled',
  'a contractor can cancel an awaiting request'
);
select throws_ok(
  $$select public.communication_sms_cancel_credit_topup(
    'b2c1e900-0000-4000-8000-000000000004', 'b2c1ac70-0000-4000-8000-000000000001')$$,
  'P0001', null,
  'a cancelled request cannot be cancelled again'
);

-- Tenant isolation: none of Org A's activity touched Org B.
select is(
  (select count(*)::int from public.communication_sms_credit_accounts
   where organization_id = 'b2c10000-0000-4000-8000-000000000002'),
  0,
  'confirming Org A top-ups never creates or funds Org B credit'
);

-- The lifecycle constraint forbids a confirmed row without settlement evidence.
select throws_ok(
  $$insert into public.communication_sms_credit_topup_requests
    (organization_id, requested_by, requested_amount_minor, status, decided_by, decided_at)
    values ('b2c10000-0000-4000-8000-000000000001', 'b2c1ac70-0000-4000-8000-000000000001',
            1000, 'confirmed', 'b2c1ad30-0000-4000-8000-000000000009', now())$$,
  '23514', null,
  'a confirmed request must carry a settled amount'
);

select * from finish();
rollback;
