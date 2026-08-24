-- Sales Pipeline, Part 5C-i follow-up: a quote-backed opportunity's estimated_value is kept in sync with
-- its quote's current price, not left for a human to guess. Browser verification of 5C-i found every
-- Quote card and column total silently blank because nothing ever wrote estimated_value for a
-- quote-backed row; this is the read side of that fix.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention pipeline_quote_board_read_model.sql
-- documents.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('ca000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5c-value-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('cb000000-0000-0000-0000-000000000001', '5C Value Sync Org', '5c-value-sync-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('cb000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('cc000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', '5C Value Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('cd000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', '1 Value Street', 'Testville');

-- Q1: a real quote with a draft version priced at $50.00 before its Opportunity exists -- the same order
-- create_quote/convert_request_to_quote leave things in (draft_version_id set, total_minor computed).
insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, status, currency_code)
values ('ce000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', 'cd000000-0000-0000-0000-000000000001', 1, '5C Value Quote', 'draft', 'USD');

insert into public.quote_versions (id, organization_id, quote_id, version_number, status, currency_code, client_display_name, organization_name, total_minor)
values ('cf000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'ce000000-0000-0000-0000-000000000001', 1, 'draft', 'USD', '5C Value Client', '5C Value Sync Org', 5000);

update public.quotes set draft_version_id = 'cf000000-0000-0000-0000-000000000001'
where id = 'ce000000-0000-0000-0000-000000000001';

-- 1. Insert-time: a fresh quote-backed opportunity picks up the version's total without anyone writing it.

insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
values ('cb000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', 'cd000000-0000-0000-0000-000000000001', 'ce000000-0000-0000-0000-000000000001', '5C Value Quote');

select is(
  (select estimated_value from public.opportunities where quote_id = 'ce000000-0000-0000-0000-000000000001'),
  50.00::numeric, 'a new quote-backed opportunity picks up the draft version''s total at insert time'
);

-- A standalone Request-backed opportunity is untouched by the same trigger.

insert into public.requests (id, organization_id, client_id, property_id, title, status)
values ('d0000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', 'cd000000-0000-0000-0000-000000000001', '5C Value Request', 'new');

select is(
  (select estimated_value from public.opportunities where request_id = 'd0000000-0000-0000-0000-000000000001'),
  null, 'a request-backed opportunity is not touched by the quote-value trigger'
);

-- 2. A price edit on the current draft resyncs the card without anyone touching opportunities directly.

update public.quote_versions set total_minor = 12345 where id = 'cf000000-0000-0000-0000-000000000001';

select is(
  (select estimated_value from public.opportunities where quote_id = 'ce000000-0000-0000-0000-000000000001'),
  123.45::numeric, 'editing the draft''s total resyncs the card'
);

-- 3. Publishing (the "current" version pointer moving, not the total) resyncs too. A second version, same
--    total as the first edit landed on, simulates publish flipping draft_version_id to current_published.

insert into public.quote_versions (id, organization_id, quote_id, version_number, status, currency_code, client_display_name, organization_name, total_minor, published_at, document_hash)
values ('cf000000-0000-0000-0000-000000000002', 'cb000000-0000-0000-0000-000000000001', 'ce000000-0000-0000-0000-000000000001', 2, 'published', 'USD', '5C Value Client', '5C Value Sync Org', 9900, now(), repeat('a', 64));

update public.quotes
set draft_version_id = null, current_published_version_id = 'cf000000-0000-0000-0000-000000000002',
    status = 'awaiting_response', sent_at = now()
where id = 'ce000000-0000-0000-0000-000000000001';

select is(
  (select estimated_value from public.opportunities where quote_id = 'ce000000-0000-0000-0000-000000000001'),
  99.00::numeric, 'publishing moves the card to the newly-published version''s total'
);

-- 4. The manual editor refuses a quote-backed opportunity's value outright ------------------------------

-- Definer functions read the row by id, not by quote_id/request_id, so the two ids are fetched with the
-- privileged role first (`authenticated`'s column grant list on opportunities has neither pointer column)
-- and handed to the authenticated calls below as a setting rather than a re-query.
select set_config(
  'test.quote_opportunity_id',
  (select id::text from public.opportunities where quote_id = 'ce000000-0000-0000-0000-000000000001'),
  true
);
select set_config(
  'test.request_opportunity_id',
  (select id::text from public.opportunities where request_id = 'd0000000-0000-0000-0000-000000000001'),
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$select * from public.pipeline_update_opportunity_details(
    current_setting('test.quote_opportunity_id')::uuid,
    false, null, true, 1.00
  )$$,
  '23514', null, 'editing a quote-backed opportunity''s value by hand is refused'
);

-- ...but is still legal, and still works, for the Request-backed card beside it.

select lives_ok(
  $$select * from public.pipeline_update_opportunity_details(
    current_setting('test.request_opportunity_id')::uuid,
    false, null, true, 777.00
  )$$,
  'the manual editor is unchanged for a request-backed opportunity'
);

set local role postgres;

select is(
  (select estimated_value from public.opportunities where request_id = 'd0000000-0000-0000-0000-000000000001'),
  777.00::numeric, 'the request-backed card kept the value the manual editor just set'
);

-- 5. Same total the trigger applied, read back through the private helper directly ------------------------

select is(
  private.quote_current_total_minor('ce000000-0000-0000-0000-000000000001'),
  9900::bigint, 'the helper reads the same total the trigger just applied'
);

select * from finish();
rollback;
