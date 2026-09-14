-- Communications A2 / Stage 2C (part 4): outbound holds pause outbound at three distinct scopes and surface as
-- 'outbound_paused' only over a ready capability; promotional credit is a separate expiring bucket derived on
-- read; and standalone adjustments/refunds move the settled balance through immutable, uniquely-keyed ledger
-- entries without ever editing the balance or history directly.
begin;

create extension if not exists pgtap with schema extensions;
select plan(78);

-- ---------------------------------------------------------------------------------------------------------------
-- Shape and access boundary.
-- ---------------------------------------------------------------------------------------------------------------
select has_table('public', 'communication_sms_holds', 'holds are a first-class record');
select col_is_pk('public', 'communication_sms_holds', 'id', 'each hold has a stable identity');
select has_index('public', 'communication_sms_holds', 'communication_sms_holds_one_active_idx',
  'a unique partial index enforces one active hold per scope+target');
select has_index('public', 'communication_sms_holds', 'communication_sms_holds_active_idx',
  'a partial index backs governing-hold resolution over active holds');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_holds'::regclass),
  'holds keep row-level security enabled'
);
select table_privs_are('public', 'communication_sms_holds', 'authenticated', array[]::text[],
  'authenticated clients have no direct hold privileges');
select table_privs_are('public', 'communication_sms_holds', 'anon', array[]::text[],
  'anonymous clients have no direct hold privileges');
select table_privs_are('public', 'communication_sms_holds', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE'],
  'only the server role reads/writes holds directly, never deletes');

select has_table('public', 'communication_sms_promotional_credits', 'promotional credits are a first-class record');
select has_index('public', 'communication_sms_promotional_credits',
  'communication_sms_promotional_credits_active_idx',
  'a partial index backs the live promotional balance sum');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_promotional_credits'::regclass),
  'promotional credits keep row-level security enabled'
);
select table_privs_are('public', 'communication_sms_promotional_credits', 'authenticated', array[]::text[],
  'authenticated clients have no direct promotional-credit privileges');
select table_privs_are('public', 'communication_sms_promotional_credits', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE'],
  'only the server role reads/writes promotional credits directly, never deletes');

-- Fixtures: isolated organizations and stable actor ids.
insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c2c40000-0000-4000-8000-000000000001', 'Holds Org A', 'holds-org-a', 'active'),
  ('c2c40000-0000-4000-8000-000000000002', 'Holds Org B', 'holds-org-b', 'active'),
  ('c2c40000-0000-4000-8000-000000000003', 'Holds Org P', 'holds-org-p', 'active');

-- ---------------------------------------------------------------------------------------------------------------
-- Holds: scopes, reasons, single-active, release and governing-hold precedence.
-- ---------------------------------------------------------------------------------------------------------------

-- A platform hold names no organization; an organization/provider hold must.
select is(
  (public.communication_sms_place_hold('platform', null, 'global maintenance', null)).scope,
  'platform', 'a platform hold is placed without an organization'
);
select throws_ok(
  $$select public.communication_sms_place_hold('platform', 'c2c40000-0000-4000-8000-000000000001', 'bad')$$,
  '23514', null, 'a platform hold cannot target an organization'
);
select throws_ok(
  $$select public.communication_sms_place_hold('organization', null, 'bad')$$,
  '23514', null, 'an organization hold must name an organization'
);
select throws_ok(
  $$select public.communication_sms_place_hold('organization', 'c2c40000-0000-4000-8000-000000000001', '  ')$$,
  'P0001', null, 'a hold must record a reason'
);

-- Only one active hold per scope+target: a second active platform hold is refused with a friendly error.
select throws_ok(
  $$select public.communication_sms_place_hold('platform', null, 'second global')$$,
  'P0001', null, 'a second active platform hold is refused'
);

-- Release requires a releaser and a reason; only an active hold can be released.
insert into public.communication_sms_holds (id, scope, organization_id, reason)
values ('c2c4ce00-0000-4000-8000-000000000001', 'organization', 'c2c40000-0000-4000-8000-000000000001', 'billing review');
select throws_ok(
  $$select public.communication_sms_release_hold('c2c4ce00-0000-4000-8000-000000000001',
    'c2c4ac70-0000-4000-8000-000000000009', '   ')$$,
  'P0001', null, 'releasing a hold must record a reason'
);
select is(
  (public.communication_sms_release_hold('c2c4ce00-0000-4000-8000-000000000001',
    'c2c4ac70-0000-4000-8000-000000000009', 'review complete')).status,
  'released', 'an active hold can be released with a reason'
);
select throws_ok(
  $$select public.communication_sms_release_hold('c2c4ce00-0000-4000-8000-000000000001',
    'c2c4ac70-0000-4000-8000-000000000009', 'again')$$,
  'P0001', null, 'a released hold cannot be released again'
);
-- Releasing the org hold frees the scope+target: a fresh active org hold can now be placed.
select is(
  (public.communication_sms_place_hold('organization', 'c2c40000-0000-4000-8000-000000000001', 'new review')).status,
  'active', 'releasing a hold frees its scope+target for a new active hold'
);

-- Governing hold precedence: provider (emergency) outranks platform, which outranks organization.
select public.communication_sms_place_hold('organization', 'c2c40000-0000-4000-8000-000000000003', 'org level');
select public.communication_sms_place_hold('provider', 'c2c40000-0000-4000-8000-000000000003', 'provider suspension');
-- (a platform hold is already active from the first test and applies to every org)
select is(
  (select scope from public.communication_sms_active_outbound_hold('c2c40000-0000-4000-8000-000000000003')),
  'provider', 'provider suspension is the governing hold when several apply'
);
-- An org with no hold of its own is still governed by the active platform hold.
select is(
  (select scope from public.communication_sms_active_outbound_hold('c2c40000-0000-4000-8000-000000000002')),
  'platform', 'the active platform hold governs an org with no hold of its own'
);
-- Release everything, then no hold governs the org.
update public.communication_sms_holds
set status = 'released', released_by = 'c2c4ac70-0000-4000-8000-000000000009', released_at = now(),
    release_reason = 'test cleanup'
where status = 'active';
select is(
  (select count(*)::int from public.communication_sms_active_outbound_hold('c2c40000-0000-4000-8000-000000000002')),
  0, 'no active hold means no governing outbound hold'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Promotional credit: grant validation, live balance, expiry-on-read, revocation.
-- ---------------------------------------------------------------------------------------------------------------
select throws_ok(
  $$select public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000001', -100, now() + interval '30 days', 'promo', 'grant-neg-amount')$$,
  'P0001', null, 'a promotional grant must be a positive amount'
);
select throws_ok(
  $$select public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000001', 500, now() - interval '1 day', 'promo', 'grant-past-expiry')$$,
  'P0001', null, 'a promotional grant must expire in the future'
);
select throws_ok(
  $$select public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000001', 500, now() + interval '30 days', '   ', 'grant-empty-reason')$$,
  'P0001', null, 'a promotional grant must record a reason'
);
select throws_ok(
  $$select public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000001', 500, now() + interval '30 days', 'promo', ' ')$$,
  'P0001', null, 'a promotional grant must record an idempotency key'
);
select is(
  (select status from public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000001', 500, now() + interval '30 days', 'welcome credit', 'org1-welcome')),
  'active', 'a valid promotional grant is active'
);
select public.communication_sms_grant_promotional_credit(
  'c2c40000-0000-4000-8000-000000000001', 300, now() + interval '10 days', 'second grant', 'org1-second-grant');
select is(
  public.communication_sms_promotional_balance('c2c40000-0000-4000-8000-000000000001'),
  800::bigint, 'the live promotional balance sums active, unexpired grants'
);

-- An expired grant does not count toward the live balance (expiry derived on read, not swept).
insert into public.communication_sms_promotional_credits
  (organization_id, amount_minor, expires_at, reason, granted_at, idempotency_key)
values ('c2c40000-0000-4000-8000-000000000001', 999, now() - interval '1 second', 'expired promo',
        now() - interval '2 days', 'org1-expired-promo');
select is(
  public.communication_sms_promotional_balance('c2c40000-0000-4000-8000-000000000001'),
  800::bigint, 'an expired grant is excluded from the live promotional balance'
);

-- Revocation validation and effect.
insert into public.communication_sms_promotional_credits
  (id, organization_id, amount_minor, expires_at, reason, idempotency_key)
values ('c2c4c9ed-0000-4000-8000-000000000001', 'c2c40000-0000-4000-8000-000000000001', 200,
        now() + interval '20 days', 'to be revoked', 'org1-to-be-revoked');
select throws_ok(
  $$select public.communication_sms_revoke_promotional_credit('c2c4c9ed-0000-4000-8000-000000000001',
    'c2c4ac70-0000-4000-8000-000000000009', '  ')$$,
  'P0001', null, 'revoking a promotional grant must record a reason'
);
select is(
  (public.communication_sms_revoke_promotional_credit('c2c4c9ed-0000-4000-8000-000000000001',
    'c2c4ac70-0000-4000-8000-000000000009', 'granted in error')).status,
  'revoked', 'an active grant can be revoked'
);
select is(
  public.communication_sms_promotional_balance('c2c40000-0000-4000-8000-000000000001'),
  800::bigint, 'a revoked grant stops counting immediately'
);
select throws_ok(
  $$select public.communication_sms_revoke_promotional_credit('c2c4c9ed-0000-4000-8000-000000000001',
    'c2c4ac70-0000-4000-8000-000000000009', 'again')$$,
  'P0001', null, 'a revoked grant cannot be revoked again'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Standalone adjustments and refunds move the settled balance through the immutable ledger.
-- ---------------------------------------------------------------------------------------------------------------

-- Fund Org B with a confirmed top-up so it has purchased (settled) credit to adjust and refund.
insert into public.communication_sms_credit_topup_requests (id, organization_id, requested_by, requested_amount_minor)
values ('c2c4700b-0000-4000-8000-000000000001', 'c2c40000-0000-4000-8000-000000000002',
        'c2c4ac70-0000-4000-8000-000000000001', 10000);
select public.communication_sms_confirm_credit_topup(
  'c2c4700b-0000-4000-8000-000000000001', 'c2c4ac70-0000-4000-8000-000000000009', 10000, 'wire received');

select throws_ok(
  $$select public.communication_sms_record_adjustment('c2c40000-0000-4000-8000-000000000002', 0, 'noop', 'adj-noop')$$,
  'P0001', null, 'an adjustment must move a non-zero amount'
);
select throws_ok(
  $$select public.communication_sms_record_adjustment('c2c40000-0000-4000-8000-000000000002', 100, '  ', 'adj-empty-reason')$$,
  'P0001', null, 'an adjustment must record a reason'
);
select throws_ok(
  $$select public.communication_sms_record_adjustment('c2c40000-0000-4000-8000-000000000002', 100, 'reason', ' ')$$,
  'P0001', null, 'an adjustment must record an idempotency key'
);
select is(
  (select entry_kind from public.communication_sms_record_adjustment(
    'c2c40000-0000-4000-8000-000000000002', 1500, 'goodwill correction', 'org2-adj-goodwill')),
  'adjustment', 'a positive adjustment posts an adjustment ledger entry'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'c2c40000-0000-4000-8000-000000000002'),
  11500::bigint, 'a positive adjustment raises the settled balance'
);
select is(
  (select amount_minor from public.communication_sms_record_adjustment(
    'c2c40000-0000-4000-8000-000000000002', -500, 'billing correction', 'org2-adj-billing')),
  -500::bigint, 'a negative adjustment posts a negative ledger entry'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'c2c40000-0000-4000-8000-000000000002'),
  11000::bigint, 'a negative adjustment lowers the settled balance'
);

-- An adjustment that would drop settled below reserved funds is refused, and nothing is left behind.
update public.communication_sms_credit_accounts
set reserved_balance_minor = 9000
where organization_id = 'c2c40000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.communication_sms_record_adjustment(
    'c2c40000-0000-4000-8000-000000000002', -5000, 'too much', 'org2-adj-too-much')$$,
  'P0001', null, 'an adjustment below the reserved funds is refused'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'c2c40000-0000-4000-8000-000000000002'),
  11000::bigint, 'a refused adjustment leaves the balance unchanged (rolled back)'
);
update public.communication_sms_credit_accounts
set reserved_balance_minor = 0
where organization_id = 'c2c40000-0000-4000-8000-000000000002';

-- Refund validation and effect.
select throws_ok(
  $$select public.communication_sms_record_refund('c2c40000-0000-4000-8000-000000000002', -100, 'bad', 'refund-negative')$$,
  'P0001', null, 'a refund must be a positive amount'
);
select throws_ok(
  $$select public.communication_sms_record_refund('c2c40000-0000-4000-8000-000000000002', 100, '   ', 'refund-empty-reason')$$,
  'P0001', null, 'a refund must record a reason'
);
select throws_ok(
  $$select public.communication_sms_record_refund('c2c40000-0000-4000-8000-000000000002', 100, 'reason', ' ')$$,
  'P0001', null, 'a refund must record an idempotency key'
);
select throws_ok(
  $$select public.communication_sms_record_refund('c2c40000-0000-4000-8000-000000000001', 100, 'no account', 'refund-no-account')$$,
  'P0001', null, 'a refund needs an existing credit account'
);
select throws_ok(
  $$select public.communication_sms_record_refund('c2c40000-0000-4000-8000-000000000002', 999999, 'too big', 'refund-too-big')$$,
  'P0001', null, 'a refund exceeding the unreserved settled balance is refused'
);
select is(
  (select entry_kind from public.communication_sms_record_refund(
    'c2c40000-0000-4000-8000-000000000002', 1000, 'partial refund', 'org2-refund-partial')),
  'refund', 'a refund posts a refund ledger entry'
);
select is(
  (select amount_minor from public.communication_sms_credit_ledger_entries
   where organization_id = 'c2c40000-0000-4000-8000-000000000002' and entry_kind = 'refund'),
  -1000::bigint, 'the refund entry is a negative movement'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'c2c40000-0000-4000-8000-000000000002'),
  10000::bigint, 'a refund lowers the settled balance by the refunded amount'
);

-- Every correction is its own uniquely-keyed ledger entry; two adjustments never collide.
select is(
  (select count(*)::int from public.communication_sms_credit_ledger_entries
   where organization_id = 'c2c40000-0000-4000-8000-000000000002' and entry_kind = 'adjustment'),
  2, 'each adjustment is its own uniquely-keyed ledger entry'
);

-- Spendable balance = unreserved settled credit + live promotional credit.
select public.communication_sms_grant_promotional_credit(
  'c2c40000-0000-4000-8000-000000000002', 250, now() + interval '5 days', 'spendable check', 'org2-spendable-check');
update public.communication_sms_credit_accounts
set reserved_balance_minor = 2000
where organization_id = 'c2c40000-0000-4000-8000-000000000002';
select is(
  public.communication_sms_spendable_balance('c2c40000-0000-4000-8000-000000000002'),
  8250::bigint, 'spendable balance is unreserved settled credit plus live promotional credit'
);
select is(
  public.communication_sms_spendable_balance('c2c40000-0000-4000-8000-000000000003'),
  0::bigint, 'an org with no account and no promo has zero spendable balance'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Outbound state: a hold surfaces as 'outbound_paused' only over an otherwise-ready capability.
-- ---------------------------------------------------------------------------------------------------------------

-- Make Org A fully ready for (US, toll_free, operational notifications).
select public.communication_sms_set_org_mode(
  'c2c40000-0000-4000-8000-000000000001', 'c2c4ac70-0000-4000-8000-000000000009', 'operational', 'operational');
select public.communication_sms_start_registration(
  'c2c40000-0000-4000-8000-000000000001', 'US', 'toll_free', 'operational notifications',
  'c2c4ac70-0000-4000-8000-000000000009');

do $$
declare
  reg_id uuid;
begin
  select id into reg_id from public.communication_sms_registrations
  where organization_id = 'c2c40000-0000-4000-8000-000000000001'
    and country_code = 'US' and sender_type = 'toll_free' and use_case = 'operational notifications';

  perform public.communication_sms_submit_registration(reg_id, 'c2c4ac70-0000-4000-8000-000000000009');
  perform public.communication_sms_record_registration_outcome(
    reg_id, 'approved', 'c2c4ac70-0000-4000-8000-000000000009', 'carrier approved');

  insert into public.communication_sms_sender_identities (id, organization_id, phone_number, lifecycle_state)
  values ('c2c45e11-0000-4000-8000-000000000001', 'c2c40000-0000-4000-8000-000000000001', '+18005550100', 'ready');
  perform public.communication_sms_set_sender_capabilities(
    'c2c45e11-0000-4000-8000-000000000001', 'US', 'toll_free', true, false, false, reg_id);
end $$;

-- Ready with no hold: outbound_state passes through 'ready', no pause.
select is(
  (select state from public.communication_sms_outbound_state(
    'c2c40000-0000-4000-8000-000000000001', 'US', 'toll_free', 'operational notifications')),
  'ready', 'a ready capability with no hold reports ready'
);
select is(
  (select pause_scope from public.communication_sms_outbound_state(
    'c2c40000-0000-4000-8000-000000000001', 'US', 'toll_free', 'operational notifications')),
  null, 'a ready capability with no hold has no pause cause'
);

-- An organization hold over a ready capability surfaces as outbound_paused with its scope and reason.
select public.communication_sms_place_hold(
  'organization', 'c2c40000-0000-4000-8000-000000000001', 'safety review', 'c2c4ac70-0000-4000-8000-000000000009');
select is(
  (select state from public.communication_sms_outbound_state(
    'c2c40000-0000-4000-8000-000000000001', 'US', 'toll_free', 'operational notifications')),
  'outbound_paused', 'a hold over a ready capability surfaces as outbound_paused'
);
select is(
  (select pause_scope from public.communication_sms_outbound_state(
    'c2c40000-0000-4000-8000-000000000001', 'US', 'toll_free', 'operational notifications')),
  'organization', 'the pause cause names the governing hold scope'
);
select is(
  (select pause_reason from public.communication_sms_outbound_state(
    'c2c40000-0000-4000-8000-000000000001', 'US', 'toll_free', 'operational notifications')),
  'safety review', 'the pause cause carries the hold reason'
);

-- A hold never masks a setup state: an org still in setup reports its setup state, not a pause.
select public.communication_sms_set_org_mode(
  'c2c40000-0000-4000-8000-000000000002', 'c2c4ac70-0000-4000-8000-000000000009', 'operational', 'operational');
select public.communication_sms_place_hold(
  'organization', 'c2c40000-0000-4000-8000-000000000002', 'held while setting up', 'c2c4ac70-0000-4000-8000-000000000009');
select is(
  (select state from public.communication_sms_outbound_state(
    'c2c40000-0000-4000-8000-000000000002', 'US', 'toll_free', 'operational notifications')),
  'needs_setup', 'a hold does not mask a not-yet-ready setup state'
);
select is(
  (select pause_scope from public.communication_sms_outbound_state(
    'c2c40000-0000-4000-8000-000000000002', 'US', 'toll_free', 'operational notifications')),
  null, 'a not-yet-ready capability shows no pause cause'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Retry safety: grant / adjustment / refund never double-apply when called twice with the same idempotency key.
-- ---------------------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c2c40000-0000-4000-8000-000000000004', 'Holds Org R', 'holds-org-r', 'active');

select is(
  (select applied from public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000004', 500, now() + interval '30 days', 'retry test', 'grant-key-one')),
  true, 'a fresh promotional grant is applied'
);
select is(
  (select applied from public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000004', 500, now() + interval '30 days', 'retry test', 'grant-key-one')),
  false, 'a repeated grant with the same idempotency key is a no-op replay'
);
select is(
  (select count(*)::int from public.communication_sms_promotional_credits
   where organization_id = 'c2c40000-0000-4000-8000-000000000004'),
  1, 'a repeated grant call never creates a second row'
);
select is(
  public.communication_sms_promotional_balance('c2c40000-0000-4000-8000-000000000004'),
  500::bigint, 'a repeated grant never doubles the promotional balance'
);
select is(
  (select applied from public.communication_sms_grant_promotional_credit(
    'c2c40000-0000-4000-8000-000000000004', 100, now() + interval '30 days', 'second real grant', 'grant-key-two')),
  true, 'a different idempotency key is a genuinely new grant'
);
select is(
  public.communication_sms_promotional_balance('c2c40000-0000-4000-8000-000000000004'),
  600::bigint, 'a genuinely new grant does add to the balance'
);

-- Fund Org R with a confirmed top-up so adjustment/refund retries have a real balance to move.
insert into public.communication_sms_credit_topup_requests (id, organization_id, requested_by, requested_amount_minor)
values ('c2c4700b-0000-4000-8000-000000000002', 'c2c40000-0000-4000-8000-000000000004',
        'c2c4ac70-0000-4000-8000-000000000001', 5000);
select public.communication_sms_confirm_credit_topup(
  'c2c4700b-0000-4000-8000-000000000002', 'c2c4ac70-0000-4000-8000-000000000009', 5000, 'wire received');

select is(
  (select applied from public.communication_sms_record_adjustment(
    'c2c40000-0000-4000-8000-000000000004', 300, 'goodwill', 'adj-key-one')),
  true, 'a fresh adjustment is applied'
);
select is(
  (select applied from public.communication_sms_record_adjustment(
    'c2c40000-0000-4000-8000-000000000004', 300, 'goodwill', 'adj-key-one')),
  false, 'a repeated adjustment with the same idempotency key is a no-op replay'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'c2c40000-0000-4000-8000-000000000004'),
  5300::bigint, 'a repeated adjustment call never doubles the settled balance'
);
select is(
  (select count(*)::int from public.communication_sms_credit_ledger_entries
   where organization_id = 'c2c40000-0000-4000-8000-000000000004' and entry_kind = 'adjustment'),
  1, 'a repeated adjustment call never creates a second ledger entry'
);

select is(
  (select applied from public.communication_sms_record_refund(
    'c2c40000-0000-4000-8000-000000000004', 200, 'offsite refund', 'refund-key-one')),
  true, 'a fresh refund is applied'
);
select is(
  (select applied from public.communication_sms_record_refund(
    'c2c40000-0000-4000-8000-000000000004', 200, 'offsite refund', 'refund-key-one')),
  false, 'a repeated refund with the same idempotency key is a no-op replay'
);
select is(
  (select settled_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'c2c40000-0000-4000-8000-000000000004'),
  5100::bigint, 'a repeated refund call never doubles the settled-balance reduction'
);
select is(
  (select count(*)::int from public.communication_sms_credit_ledger_entries
   where organization_id = 'c2c40000-0000-4000-8000-000000000004' and entry_kind = 'refund'),
  1, 'a repeated refund call never creates a second ledger entry'
);

-- Tenant isolation: none of Org A's/Org B's money or holds touched Org P.
select is(
  (select count(*)::int from public.communication_sms_credit_ledger_entries
   where organization_id = 'c2c40000-0000-4000-8000-000000000003'),
  0, 'no adjustment or refund ever touched an uninvolved org'
);

select * from finish();
rollback;
