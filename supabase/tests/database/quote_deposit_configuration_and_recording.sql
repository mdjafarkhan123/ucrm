-- Quotes Part 6B: staff deposit configuration and offline recording.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(58);

-- 1. Shape and privileges -----------------------------------------------------------------------------------

select has_function('public', 'set_quote_draft_deposit',
  array['uuid', 'integer', 'text', 'jsonb'], 'staff can replace a draft''s deposit shape');
select has_function('public', 'record_quote_deposit_event',
  array['uuid', 'text', 'text', 'text', 'text'], 'staff can record an offline deposit');
select has_function('public', 'reverse_quote_deposit_event',
  array['uuid', 'uuid', 'text', 'text'], 'staff can reverse a recorded deposit');
select has_table('public', 'quote_deposit_events', 'deposits keep their own immutable ledger');
select has_column('public', 'quote_deposit_events', 'event_type', 'received or reversed');
select has_column('public', 'quote_deposit_events', 'idempotency_key', 'a retry replays instead of duplicating');
select has_column('public', 'quote_deposit_events', 'reversed_event_id', 'a reversal names what it corrects');
select has_index('public', 'quote_deposit_events', 'quote_deposit_events_version_idx',
  'deposit reads follow version order');
select has_index('public', 'quote_deposit_events', 'quote_deposit_events_reversed_idx',
  'the already-reversed check has its own index');
select is(has_table_privilege('authenticated', 'public.quote_deposit_events', 'insert'), false,
  'no direct write access -- only the two commands may write this table');
select is(has_table_privilege('authenticated', 'public.quote_deposit_events', 'select'), true,
  'members may read the deposit ledger the same way they read everything else on the quote');
select ok(exists(select 1 from public.permissions where key = 'quotes.record_deposit'),
  'the record-deposit permission is seeded');
select is(exists(
  select 1 from public.role_permissions where role = 'finance' and permission_key = 'quotes.record_deposit'
), true, 'finance can record and reverse deposits');
select is(exists(
  select 1 from public.role_permissions where role = 'sales' and permission_key = 'quotes.record_deposit'
), false, 'sales can edit a quote''s deposit configuration but not record money against it');

-- 2. Fixtures -------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('d9000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit6b-owner@example.test', 'test', now(), now(), now()),
  ('d9000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit6b-office@example.test', 'test', now(), now(), now()),
  ('d9000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit6b-sales@example.test', 'test', now(), now(), now()),
  ('d9000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit6b-field@example.test', 'test', now(), now(), now()),
  ('d9000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit6b-orgb@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d9100000-0000-0000-0000-000000000001', 'Deposit 6B Org A', 'deposit-6b-org-a', 'active'),
  ('d9100000-0000-0000-0000-000000000002', 'Deposit 6B Org B', 'deposit-6b-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('d9100000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000001', 'owner'),
  ('d9100000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000002', 'office'),
  ('d9100000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000003', 'sales'),
  ('d9100000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000004', 'field'),
  ('d9100000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000005', 'admin');

insert into public.clients (id, organization_id, display_name) values
  ('d9200000-0000-0000-0000-000000000001', 'd9100000-0000-0000-0000-000000000001', 'Deposit 6B Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('d9300000-0000-0000-0000-000000000001', 'd9100000-0000-0000-0000-000000000001', 'd9200000-0000-0000-0000-000000000001', '1 Deposit 6B Way', 'Testville');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('d9200000-0000-0000-0000-000000000001', 'd9300000-0000-0000-0000-000000000001', 'Deposit config quote', 'Approved scope only.')$$,
  'the config-workspace fixture quote gets a draft'
);
select lives_ok(
  $$select public.create_quote('d9200000-0000-0000-0000-000000000001', 'd9300000-0000-0000-0000-000000000001', 'Deposit empty quote', 'Approved scope only.')$$,
  'the empty fixture quote gets a draft with nothing priced yet'
);
select lives_ok(
  $$select public.create_quote('d9200000-0000-0000-0000-000000000001', 'd9300000-0000-0000-0000-000000000001', 'Deposit never sent quote', 'Approved scope only.')$$,
  'the never-sent fixture quote gets a draft that will stay a draft'
);
select lives_ok(
  $$select public.create_quote('d9200000-0000-0000-0000-000000000001', 'd9300000-0000-0000-0000-000000000001', 'Deposit unconfigured quote', 'Approved scope only.')$$,
  'the unconfigured fixture quote gets a draft that will be sent with no deposit'
);

set local role postgres;

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, category, name, quantity,
  unit_price_minor, unit_cost_minor, is_taxable, line_kind, selection_kind, is_recommended
) values
  ('d9400000-0000-0000-0000-000000000001', 'd9100000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Deposit config quote'),
    (select draft_version_id from public.quotes where title = 'Deposit config quote'), 0, 'service',
    'Required work', 1, 10000, 4000, false, 'priced', 'required', false),
  ('d9400000-0000-0000-0000-000000000002', 'd9100000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Deposit config quote'),
    (select draft_version_id from public.quotes where title = 'Deposit config quote'), 1, 'service',
    'Optional add-on', 1, 5000, 2000, false, 'priced', 'optional', false),
  ('d9400000-0000-0000-0000-000000000003', 'd9100000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Deposit unconfigured quote'),
    (select draft_version_id from public.quotes where title = 'Deposit unconfigured quote'), 0, 'service',
    'Required work', 1, 8000, 3000, false, 'priced', 'required', false);

select private.refresh_quote_draft_totals(
  (select draft_version_id from public.quotes where title = 'Deposit config quote')
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000001', true);

-- 3. Configuring a deposit -------------------------------------------------------------------------------------

select is(
  (public.set_quote_draft_deposit(
    (select id from public.quotes where title = 'Deposit config quote'), 1, 'deposit_only',
    '[{"description": "Deposit", "type": "fixed", "value": 2500}]'::jsonb
  ) -> 'totals' ->> 'deposit_required_minor')::bigint,
  2500::bigint, 'a deposit-only save prices its exact fixed amount, the same as raw 6A math did'
);
select is(
  (select deposit_type from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Deposit config quote')),
  'deposit_only', 'the draft records deposit-only'
);

select throws_ok(
  $$select public.set_quote_draft_deposit(
      (select id from public.quotes where title = 'Deposit config quote'), 2, 'deposit_only',
      '[{"description": "First", "type": "fixed", "value": 2000},
        {"description": "Second", "type": "fixed", "value": 2000}]'::jsonb)$$,
  '23514', null, 'a deposit-only save refuses more than one installment'
);

select throws_ok(
  $$select public.set_quote_draft_deposit(
      (select id from public.quotes where title = 'Deposit config quote'), 2, 'schedule',
      '[{"description": "First", "type": "fixed", "value": 3000},
        {"description": "Second", "type": "fixed", "value": 3000}]'::jsonb)$$,
  '23514', null, 'a schedule that does not add up to the total is refused, not silently accepted'
);

select is(
  (public.set_quote_draft_deposit(
    (select id from public.quotes where title = 'Deposit config quote'), 2, 'schedule',
    '[{"description": "Deposit", "type": "fixed", "value": 4000},
      {"description": "Final milestone", "type": "percentage", "value": 6000}]'::jsonb
  ) -> 'totals' ->> 'deposit_required_minor')::bigint,
  4000::bigint, 'a balanced schedule saves, priced from its first (deposit) installment'
);
select is(
  (select count(*)::integer from public.quote_version_schedule_items where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Deposit config quote')),
  2, 'both installments were written'
);
select is(
  (select is_deposit from public.quote_version_schedule_items where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Deposit config quote') and position = 0),
  true, 'the first installment is the deposit'
);
select is(
  (select is_deposit from public.quote_version_schedule_items where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Deposit config quote') and position = 1),
  false, 'the second installment is not'
);

select throws_ok(
  $$select public.set_quote_draft_deposit(
      (select id from public.quotes where title = 'Deposit empty quote'), 1, 'schedule',
      '[{"description": "Deposit", "type": "fixed", "value": 100}]'::jsonb)$$,
  '23514', null, 'a schedule cannot be saved before the quote has anything priced'
);

select throws_ok(
  $$select public.set_quote_draft_deposit(
      (select id from public.quotes where title = 'Deposit config quote'), 1, null, '[]'::jsonb)$$,
  'P0409', null, 'a stale revision is refused, same as every other draft command'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000004', true);
select throws_ok(
  $$select public.set_quote_draft_deposit(
      (select id from public.quotes where title = 'Deposit config quote'), 3, null, '[]'::jsonb)$$,
  '42501', null, 'a field member without quotes.edit cannot touch the deposit configuration'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000001', true);

select is(
  (public.set_quote_draft_deposit(
    (select id from public.quotes where title = 'Deposit config quote'), 3, null, '[]'::jsonb
  ) -> 'totals' ->> 'deposit_required_minor')::bigint,
  0::bigint, 'removing the deposit clears its price'
);
select is(
  (select deposit_type from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Deposit config quote')),
  null, 'and clears the stored type'
);
select is(
  (select count(*)::integer from public.quote_version_schedule_items where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Deposit config quote')),
  0, 'and clears every installment with it'
);

select is(
  (public.set_quote_draft_deposit(
    (select id from public.quotes where title = 'Deposit config quote'), 4, 'deposit_only',
    '[{"description": "Deposit", "type": "fixed", "value": 2500}]'::jsonb
  ) ->> 'revision')::integer,
  5, 'a deposit-only deposit is configured again, ready to publish and record against'
);

-- 4. Publishing carries the deposit forward, as Part 6A already proved end to end ------------------------------

select is(
  (public.publish_quote((select id from public.quotes where title = 'Deposit config quote'), 5)
    ->> 'version_number')::integer,
  1, 'the config quote publishes its first version'
);
select is(
  (select deposit_required_minor from public.quote_versions where id =
    (select current_published_version_id from public.quotes where title = 'Deposit config quote')),
  2500::bigint, 'the frozen version carries the $25 deposit'
);

select is(
  (public.publish_quote((select id from public.quotes where title = 'Deposit unconfigured quote'), 1)
    ->> 'version_number')::integer,
  1, 'the unconfigured quote (no deposit set) also publishes'
);

-- 5. Recording an offline deposit ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000004', true);
select throws_ok(
  $$select public.record_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit config quote'), 'field-attempt-key', 'cash')$$,
  '42501', null, 'a field member cannot record a deposit'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.record_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit config quote'), 'sales-attempt-key', 'cash')$$,
  '42501', null, 'a sales member can edit the deposit but still cannot record one being paid'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000004', true);
select throws_ok(
  $$select public.record_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit never sent quote'), 'never-sent-key', 'cash')$$,
  '42501', null, 'the permission check runs before the "no sent version" check, and this member has neither'
);

set local role postgres;
update public.organization_members set role = 'office'
where organization_id = 'd9100000-0000-0000-0000-000000000001'
  and user_id = 'd9000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000004', true);
select throws_ok(
  $$select public.record_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit never sent quote'), 'never-sent-key', 'cash')$$,
  '23514', null, 'a quote still in draft has no sent version to record a deposit against'
);
select throws_ok(
  $$select public.record_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit unconfigured quote'), 'no-deposit-key', 'cash')$$,
  '23514', null, 'a published quote with no deposit configured has nothing to record'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000002', true);
select is(
  (public.record_quote_deposit_event(
    (select id from public.quotes where title = 'Deposit config quote'), 'record-key-one', 'cash', 'Envelope #4', 'Handed over at the walkthrough'
  ) ->> 'amount_minor')::bigint,
  2500::bigint, 'the office member records the full required amount'
);
select is(
  (select count(*)::integer from public.quote_deposit_events where quote_id =
    (select id from public.quotes where title = 'Deposit config quote') and event_type = 'received'),
  1, 'exactly one receipt exists'
);
select is(
  (select method from public.quote_deposit_events where quote_id =
    (select id from public.quotes where title = 'Deposit config quote') and event_type = 'received'),
  'cash', 'the method was stored'
);

select is(
  (public.record_quote_deposit_event(
    (select id from public.quotes where title = 'Deposit config quote'), 'record-key-one', 'cash'
  ) ->> 'applied')::boolean,
  false, 'replaying the same idempotency key is recognised as a repeat, not a second receipt'
);
select is(
  (select count(*)::integer from public.quote_deposit_events where quote_id =
    (select id from public.quotes where title = 'Deposit config quote') and event_type = 'received'),
  1, 'the replay did not create a second row'
);

select throws_ok(
  $$select public.record_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit config quote'), 'record-key-two', 'cash')$$,
  '23514', null, 'a different key cannot record a second receipt while the first still stands'
);

-- 6. Reversing a recorded deposit -----------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.reverse_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit config quote'),
      (select id from public.quote_deposit_events where event_type = 'received'
        and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
      'reverse-attempt-key', 'Testing access')$$,
  '42501', null, 'reversing takes the same permission as recording -- sales can edit but not reverse'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.reverse_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit config quote'),
      (select id from public.quote_deposit_events where event_type = 'received'
        and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
      'reverse-key-one', '')$$,
  '23514', null, 'a reversal needs a reason'
);

select is(
  (public.reverse_quote_deposit_event(
    (select id from public.quotes where title = 'Deposit config quote'),
    (select id from public.quote_deposit_events where event_type = 'received'
      and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
    'reverse-key-one', 'Client asked for a refund before revising the quote'
  ) ->> 'applied')::boolean,
  true, 'the deposit is reversed'
);
select is(
  (select reversed_event_id from public.quote_deposit_events where event_type = 'reversed'
    and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
  (select id from public.quote_deposit_events where event_type = 'received'
    and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
  'the reversal names the exact receipt it corrects'
);
select is(
  (select amount_minor from public.quote_deposit_events where event_type = 'reversed'
    and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
  2500::bigint, 'the reversal carries the same amount as what it corrects'
);

select throws_ok(
  $$select public.reverse_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit config quote'),
      (select id from public.quote_deposit_events where event_type = 'received'
        and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
      'reverse-key-two', 'Trying to reverse it twice')$$,
  '23514', null, 'the same receipt cannot be reversed twice'
);

select is(
  (public.reverse_quote_deposit_event(
    (select id from public.quotes where title = 'Deposit config quote'),
    (select id from public.quote_deposit_events where event_type = 'received'
      and quote_id = (select id from public.quotes where title = 'Deposit config quote')),
    'reverse-key-one', 'A different reason on replay is irrelevant -- the key already answered this'
  ) ->> 'applied')::boolean,
  false, 'replaying the same reversal key is recognised as a repeat'
);

select throws_ok(
  $$select public.reverse_quote_deposit_event(
      (select id from public.quotes where title = 'Deposit config quote'),
      'ffffffff-ffff-ffff-ffff-ffffffffffff', 'missing-event-key', 'Does not exist')$$,
  '23514', null, 'reversing an event that does not belong to this quote is refused'
);

-- Now that the only receipt is reversed, the deposit may be recorded again.
select is(
  (public.record_quote_deposit_event(
    (select id from public.quotes where title = 'Deposit config quote'), 'record-key-three', 'check', 'Check #881'
  ) ->> 'applied')::boolean,
  true, 'a fresh receipt can be recorded once the earlier one is reversed'
);
select is(
  (select count(*)::integer from public.quote_deposit_events where quote_id =
    (select id from public.quotes where title = 'Deposit config quote') and event_type = 'received'
    and not exists (
      select 1 from public.quote_deposit_events reversal
      where reversal.reversed_event_id = quote_deposit_events.id
    )),
  1, 'exactly one live receipt exists again'
);

-- 7. RLS -----------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd9000000-0000-0000-0000-000000000005', true);
select is((select count(*)::integer from public.quote_deposit_events), 0,
  'another organization sees no deposit events at all');

select * from finish();
rollback;
