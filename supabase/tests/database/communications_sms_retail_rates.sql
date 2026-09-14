-- Communications A2 / Stage 2C (part 2): SMS retail rates are immutable Jafar-set versions. The applicable rate
-- for a moment is the latest version whose effective_from has arrived; future-dated versions wait, retroactive
-- versions are refused, and provider cost stays server-owned so contractors never see cost or margin.
begin;

create extension if not exists pgtap with schema extensions;
select plan(26);

-- Shape and access boundary.
select has_table('public', 'communication_sms_retail_rates',
  'retail rate versions are a first-class record');
select col_is_pk('public', 'communication_sms_retail_rates', 'id',
  'each rate version has a stable identity');
select has_index('public', 'communication_sms_retail_rates',
  'communication_sms_retail_rates_version_key',
  'a unique index backs one version per rate key per instant and the latest-rate lookup');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_retail_rates'::regclass),
  'retail rates keep row-level security enabled'
);
select table_privs_are('public', 'communication_sms_retail_rates', 'authenticated', array[]::text[],
  'authenticated clients have no direct retail rate privileges');
select table_privs_are('public', 'communication_sms_retail_rates', 'anon', array[]::text[],
  'anonymous clients have no direct retail rate privileges');
select table_privs_are('public', 'communication_sms_retail_rates', 'service_role',
  array['SELECT', 'INSERT'],
  'the server role may read and publish rates but never update or delete a version');

-- Publishing a rate: the command returns the stored version at the requested price.
select is(
  (public.communication_sms_set_retail_rate(
    'US', 'long_code', 'segment', 0.0079, 'b2c15e70-0000-4000-8000-000000000001')).retail_rate_major,
  0.0079::numeric,
  'setting a rate stores the retail price per segment'
);
select is(
  (public.communication_sms_effective_retail_rate('US', 'long_code', 'segment')).retail_rate_major,
  0.0079::numeric,
  'the just-published rate is the applicable rate now'
);
select ok(
  (select provider_cost_major is null from public.communication_sms_retail_rates
   where destination = 'US' and sender_type = 'long_code'),
  'a rate may be published before its provider cost is known'
);

-- Provider cost is Jafar-only truth; margin is retail minus cost.
select is(
  (public.communication_sms_set_retail_rate(
    'US', 'toll_free', 'segment', 0.02, 'b2c15e70-0000-4000-8000-000000000001', 'USD', 0.0125)).provider_cost_major,
  0.0125::numeric,
  'a rate can record the provider cost'
);
select is(
  (select retail_rate_major - provider_cost_major from public.communication_sms_retail_rates
   where destination = 'US' and sender_type = 'toll_free'),
  0.0075::numeric,
  'margin is the retail price minus the provider cost'
);

-- A deterministic version timeline for one key: two past versions and one future version.
insert into public.communication_sms_retail_rates
  (destination, sender_type, message_unit, currency_code, retail_rate_major, effective_from, set_by) values
  ('CA', 'long_code', 'segment', 'USD', 0.030, now() - interval '10 days', 'b2c15e70-0000-4000-8000-000000000001'),
  ('CA', 'long_code', 'segment', 'USD', 0.035, now() - interval '2 days',  'b2c15e70-0000-4000-8000-000000000001'),
  ('CA', 'long_code', 'segment', 'USD', 0.040, now() + interval '5 days',  'b2c15e70-0000-4000-8000-000000000001');
select is(
  (public.communication_sms_effective_retail_rate('CA', 'long_code', 'segment', 'USD', now() - interval '5 days')).retail_rate_major,
  0.030::numeric,
  'a historical moment uses the version that was in effect then'
);
select is(
  (public.communication_sms_effective_retail_rate('CA', 'long_code', 'segment', 'USD', now() - interval '1 day')).retail_rate_major,
  0.035::numeric,
  'a later historical moment uses the later version'
);
select is(
  (public.communication_sms_effective_retail_rate('CA', 'long_code', 'segment', 'USD')).retail_rate_major,
  0.035::numeric,
  'the current applicable rate ignores a version dated in the future'
);
select is(
  (public.communication_sms_effective_retail_rate('CA', 'long_code', 'segment', 'USD', now() + interval '6 days')).retail_rate_major,
  0.040::numeric,
  'once its effective_from arrives, the future-dated version applies'
);

-- A retroactive rate is refused: a rate can never change a charge that is already frozen.
select throws_ok(
  $$select public.communication_sms_set_retail_rate(
    'GB', 'long_code', 'segment', 0.05, 'b2c15e70-0000-4000-8000-000000000001', 'USD', null, now() - interval '1 day')$$,
  'P0001', null,
  'a rate cannot be published with an effective date in the past'
);

-- One version per rate key per instant.
insert into public.communication_sms_retail_rates
  (destination, sender_type, message_unit, currency_code, retail_rate_major, effective_from, set_by)
  values ('DE', 'long_code', 'segment', 'USD', 0.06, now() - interval '1 day', 'b2c15e70-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into public.communication_sms_retail_rates
    (destination, sender_type, message_unit, currency_code, retail_rate_major, effective_from, set_by)
    values ('DE', 'long_code', 'segment', 'USD', 0.07, now() - interval '1 day', 'b2c15e70-0000-4000-8000-000000000001')$$,
  '23505', null,
  'two versions of the same key cannot share an effective_from'
);

-- Value guards.
select throws_ok(
  $$insert into public.communication_sms_retail_rates
    (destination, sender_type, message_unit, retail_rate_major, set_by)
    values ('US', 'long_code', 'segment', 0, 'b2c15e70-0000-4000-8000-000000000001')$$,
  '23514', null,
  'a retail rate must be a positive price'
);
select throws_ok(
  $$insert into public.communication_sms_retail_rates
    (destination, sender_type, message_unit, retail_rate_major, set_by)
    values ('usa', 'long_code', 'segment', 0.01, 'b2c15e70-0000-4000-8000-000000000001')$$,
  '23514', null,
  'destination must be a two-letter uppercase country code'
);
select throws_ok(
  $$insert into public.communication_sms_retail_rates
    (destination, sender_type, message_unit, retail_rate_major, set_by)
    values ('US', 'pigeon', 'segment', 0.01, 'b2c15e70-0000-4000-8000-000000000001')$$,
  '23514', null,
  'sender type must be a supported sender kind'
);
select throws_ok(
  $$insert into public.communication_sms_retail_rates
    (destination, sender_type, message_unit, retail_rate_major, set_by)
    values ('US', 'long_code', 'message', 0.01, 'b2c15e70-0000-4000-8000-000000000001')$$,
  '23514', null,
  'message unit must be a supported billing unit'
);
select throws_ok(
  $$insert into public.communication_sms_retail_rates
    (destination, sender_type, message_unit, retail_rate_major, provider_cost_major, set_by)
    values ('US', 'long_code', 'segment', 0.02, -0.01, 'b2c15e70-0000-4000-8000-000000000001')$$,
  '23514', null,
  'a provider cost cannot be negative'
);

-- Currency is part of the rate key: a USD lookup never returns a GBP rate.
insert into public.communication_sms_retail_rates
  (destination, sender_type, message_unit, currency_code, retail_rate_major, effective_from, set_by) values
  ('FR', 'long_code', 'segment', 'USD', 0.050, now() - interval '1 day', 'b2c15e70-0000-4000-8000-000000000001'),
  ('FR', 'long_code', 'segment', 'GBP', 0.070, now() - interval '1 day', 'b2c15e70-0000-4000-8000-000000000001');
select is(
  (public.communication_sms_effective_retail_rate('FR', 'long_code', 'segment', 'USD')).retail_rate_major,
  0.050::numeric,
  'a USD lookup returns the USD rate'
);
select is(
  (public.communication_sms_effective_retail_rate('FR', 'long_code', 'segment', 'GBP')).retail_rate_major,
  0.070::numeric,
  'a GBP lookup returns the GBP rate'
);

-- No published rate for a key yields no applicable rate.
select ok(
  (public.communication_sms_effective_retail_rate('ZZ', 'long_code', 'segment')).id is null,
  'a key with no published rate has no applicable rate'
);

select * from finish();
rollback;
