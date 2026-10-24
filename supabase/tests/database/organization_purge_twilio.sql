-- Closing a business queues its Twilio subaccount for closure (migration 20270109091000).
begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-000000000920', '9 Purge T1 Twilio Test', '9-purge-t1-test', 'active'),
  ('90000000-0000-0000-0000-000000000921', '9 Purge T2 Twilio And SES Test', '9-purge-t2-test', 'active');

insert into public.communication_twilio_accounts (organization_id, subaccount_sid, lifecycle_state)
values
  ('90000000-0000-0000-0000-000000000920', 'AC9000000000000000000000000000920a', 'ready'),
  ('90000000-0000-0000-0000-000000000921', 'AC9000000000000000000000000000921a', 'ready');

insert into public.communication_email_domains (id, organization_id, purpose, domain_name, provider_domain_id)
values (
  '90000000-3333-0000-0000-000000000921', '90000000-0000-0000-0000-000000000921',
  'sending', 'mail.t2example.test', 'arn:aws:ses:us-east-1:000000000000:identity/mail.t2example.test'
);

select public.apply_organization_closure_start(
  '90000000-0000-0000-0000-000000000920', '9-purge-t1-close-1', 'Closing before purge test.', 'owner@example.test'
);
select public.apply_organization_closure_start(
  '90000000-0000-0000-0000-000000000921', '9-purge-t2-close-1', 'Closing before purge test.', 'owner@example.test'
);

select set_config(
  'test.t1_purge_result',
  public.apply_organization_purge('90000000-0000-0000-0000-000000000920', 'scheduled', null)::text,
  true
);
select set_config(
  'test.t2_purge_result',
  public.apply_organization_purge('90000000-0000-0000-0000-000000000921', 'scheduled', null)::text,
  true
);

select is(
  (select pending_provider_resources from public.organization_deletion_receipts
   where operation_id = (current_setting('test.t1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  '[{"kind":"twilio_subaccount","provider_id":"AC9000000000000000000000000000920a"}]'::jsonb,
  'the receipt parks the Twilio subaccount SID, read out before the cascade'
);
select is(
  (select status from public.organization_deletion_receipts
   where operation_id = (current_setting('test.t1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'in_progress', 'a receipt awaiting Twilio closure is not complete'
);
select is(
  current_setting('test.t1_purge_result', true)::jsonb -> 'provider_resources',
  '[{"kind":"twilio_subaccount","provider_id":"AC9000000000000000000000000000920a"}]'::jsonb,
  'the purge returns the subaccount for the worker to close straight away'
);
select is_empty(
  $$select 1 from public.communication_twilio_accounts
    where organization_id = '90000000-0000-0000-0000-000000000920'$$,
  'the business''s Twilio account row is gone with the organization'
);
select is(
  (select jsonb_array_length(pending_provider_resources) from public.organization_deletion_receipts
   where operation_id = (current_setting('test.t2_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  2, 'a business with email and texts queues both the SES and the Twilio cleanup'
);
select ok(
  (select position('t2example' in pending_provider_resources::text) = 0
   from public.organization_deletion_receipts
   where operation_id = (current_setting('test.t2_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'the receipt still holds no domain name -- only opaque provider ids'
);

select * from finish();
rollback;
