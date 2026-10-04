-- Client onboarding B9a: what the database itself promises about protected setup documents.
--
--   1. No browser can read or call any of it: the signed-in and anonymous roles see no rows and run no command.
--   2. Every stored file sits under its own organization's protected prefix.
--   3. Only the uploader can finish an upload, and finishing records "uploaded".
--   4. Opening records "opened" before anything is handed back, and a document of another organization, or
--      one not yet checked, opens as nothing and records nothing.
--   5. A refused file leaves storage at once and records "refused".
--   6. Removing clears the stored key, keeps the row and its history, and a second removal does nothing.
--   7. Scheduling deletion sets 90 days once; the sweep deletes what is due, unfinished uploads and files no
--      answer came to hold, and marks a held file so it is not looked at again.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
	('b9a00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
	 'authenticated', 'protected-owner@example.test', 'test', now(), now(), now()),
	('b9a00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
	 'authenticated', 'protected-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
	('b9a10000-0000-0000-0000-000000000001', 'Protected Co A', 'protected-co-a', 'active'),
	('b9a10000-0000-0000-0000-000000000002', 'Protected Co B', 'protected-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
	('b9a10000-0000-0000-0000-000000000001', 'b9a00000-0000-0000-0000-000000000001', 'owner', 'active'),
	('b9a10000-0000-0000-0000-000000000001', 'b9a00000-0000-0000-0000-000000000002', 'admin', 'active');

-- 1. Closed to browsers -----------------------------------------------------------------------------------

select ok(
	not has_table_privilege('authenticated', 'public.setup_protected_documents', 'select'),
	'A signed-in browser cannot read protected documents'
);
select ok(
	not has_table_privilege('anon', 'public.setup_protected_document_events', 'select'),
	'An anonymous browser cannot read their history'
);
select ok(
	not has_function_privilege('authenticated',
		'public.open_setup_protected_document(uuid, uuid, uuid, text, text)', 'execute'),
	'A signed-in browser cannot open a protected document directly'
);

-- 2. Its own prefix ---------------------------------------------------------------------------------------

select throws_ok(
	$$select public.register_setup_protected_document(
		'b9a10000-0000-0000-0000-000000000001', 'b9a00000-0000-0000-0000-000000000002', 'calls.port_bill',
		'bill.pdf', 'application/pdf', 1000, 'b9a10000-0000-0000-0000-000000000002/setup-protected/x-bill.pdf')$$,
	'23514', null,
	'A key under another organization is refused'
);
select throws_ok(
	$$select public.register_setup_protected_document(
		'b9a10000-0000-0000-0000-000000000001', 'b9a00000-0000-0000-0000-000000000002', 'calls.port_bill',
		'bill.pdf', 'application/pdf', 1000, 'b9a10000-0000-0000-0000-000000000001/files/x-bill.pdf')$$,
	'23514', null,
	'A key outside the protected prefix is refused'
);

create temporary table doc as
select (public.register_setup_protected_document(
	'b9a10000-0000-0000-0000-000000000001', 'b9a00000-0000-0000-0000-000000000002', 'calls.port_bill',
	'bill.pdf', 'application/pdf', 1000, 'b9a10000-0000-0000-0000-000000000001/setup-protected/a-bill.pdf')).id;

select is(
	(select state from public.setup_protected_documents where id = (select id from doc)),
	'uploading',
	'A registered document waits for its bytes'
);

-- 3. Finishing an upload ----------------------------------------------------------------------------------

select throws_ok(
	format($$select public.complete_setup_protected_document(%L, 'b9a10000-0000-0000-0000-000000000001',
		'b9a00000-0000-0000-0000-000000000001', 'Owner')$$, (select id from doc)),
	'P0002', null,
	'Somebody other than the uploader cannot finish the upload'
);

select public.complete_setup_protected_document((select id from doc), 'b9a10000-0000-0000-0000-000000000001',
	'b9a00000-0000-0000-0000-000000000002', 'Sara Admin');

select is(
	(select array_agg(action || ':' || actor_label) from public.setup_protected_document_events
		where document_id = (select id from doc)),
	array['uploaded:Sara Admin'],
	'Finishing records who uploaded it'
);

-- 4. Opening ----------------------------------------------------------------------------------------------

select is(
	(select count(*)::int from public.open_setup_protected_document((select id from doc),
		'b9a10000-0000-0000-0000-000000000001', 'b9a00000-0000-0000-0000-000000000001', 'Owner', null)),
	0,
	'A document still being checked cannot be opened'
);

create temporary table claim as select id, claim_token from public.claim_setup_protected_documents(10)
	where id = (select id from doc);
select is((select count(*)::int from claim), 1, 'The virus check claims the finished upload');

select is(
	(select count(*)::int from public.finish_setup_protected_document_check((select id from claim),
		(select claim_token from claim), true, repeat('a', 64))),
	0,
	'A clean file stays in storage'
);

select is(
	(select count(*)::int from public.open_setup_protected_document((select id from doc),
		'b9a10000-0000-0000-0000-000000000002', null, 'Uplift', 'jafar@example.test')),
	0,
	'Under the wrong organization it opens as nothing'
);

select is(
	(select object_key from public.open_setup_protected_document((select id from doc),
		'b9a10000-0000-0000-0000-000000000001', null, 'Uplift', 'jafar@example.test')),
	'b9a10000-0000-0000-0000-000000000001/setup-protected/a-bill.pdf',
	'Jafar opens it'
);

select is(
	(select array_agg(action || ':' || actor_label order by id) from public.setup_protected_document_events
		where document_id = (select id from doc)),
	array['uploaded:Sara Admin', 'opened:Uplift'],
	'Only the successful opening is recorded'
);

-- 5. A refused file ---------------------------------------------------------------------------------------

create temporary table bad as
select (public.register_setup_protected_document(
	'b9a10000-0000-0000-0000-000000000001', 'b9a00000-0000-0000-0000-000000000002', 'texting.tax_letter',
	'letter.pdf', 'application/pdf', 1000, 'b9a10000-0000-0000-0000-000000000001/setup-protected/b-letter.pdf')).id;
select public.complete_setup_protected_document((select id from bad), 'b9a10000-0000-0000-0000-000000000001',
	'b9a00000-0000-0000-0000-000000000002', 'Sara Admin');
create temporary table bad_claim as select id, claim_token from public.claim_setup_protected_documents(10)
	where id = (select id from bad);

select is(
	(select object_key from public.finish_setup_protected_document_check((select id from bad_claim),
		(select claim_token from bad_claim), false, repeat('b', 64), 'This file was flagged as unsafe.')),
	'b9a10000-0000-0000-0000-000000000001/setup-protected/b-letter.pdf',
	'A refused file hands back its key for deletion'
);
select is(
	(select state || ':' || coalesce(object_key, 'none') from public.setup_protected_documents
		where id = (select id from bad)),
	'refused:none',
	'A refused file keeps no stored key'
);

-- 6. Removing ---------------------------------------------------------------------------------------------

select public.schedule_setup_protected_document_deletion((select id from doc),
	'b9a10000-0000-0000-0000-000000000001', 'jafar@example.test');
update public.setup_protected_documents set delete_after = delete_after - interval '1 day'
	where id = (select id from doc);
select public.schedule_setup_protected_document_deletion((select id from doc),
	'b9a10000-0000-0000-0000-000000000001', 'jafar@example.test');

select ok(
	(select delete_after between now() + interval '88 days' and now() + interval '90 days'
		from public.setup_protected_documents where id = (select id from doc)),
	'Marking it finished again keeps the first deletion date'
);
select is(
	(select count(*)::int from public.setup_protected_document_events
		where document_id = (select id from doc) and action = 'deletion_scheduled'),
	1,
	'The deletion date is recorded once'
);

select is(
	(select object_key from public.delete_setup_protected_document((select id from doc),
		'b9a10000-0000-0000-0000-000000000001', 'removed', 'b9a00000-0000-0000-0000-000000000001', 'Owner', null)),
	'b9a10000-0000-0000-0000-000000000001/setup-protected/a-bill.pdf',
	'Removing hands back the key for deletion'
);
select is(
	(select count(*)::int from public.delete_setup_protected_document((select id from doc),
		'b9a10000-0000-0000-0000-000000000001', 'removed', 'b9a00000-0000-0000-0000-000000000001', 'Owner', null)),
	0,
	'Removing it again does nothing'
);
select is(
	(select array_agg(action order by id) from public.setup_protected_document_events
		where document_id = (select id from doc)),
	array['uploaded', 'opened', 'deletion_scheduled', 'removed'],
	'The history outlives the file'
);

-- 7. The sweep --------------------------------------------------------------------------------------------

insert into public.setup_protected_documents (id, organization_id, fact_key, display_name, mime_type, size_bytes,
	object_key, state, checksum_sha256, scanned_at, created_at, delete_after)
values
	-- Past its deletion date.
	('b9a20000-0000-0000-0000-000000000001', 'b9a10000-0000-0000-0000-000000000001', 'calls.port_bill', 'old.pdf',
	 'application/pdf', 10, 'b9a10000-0000-0000-0000-000000000001/setup-protected/old.pdf', 'ready', repeat('c', 64),
	 now() - interval '100 days', now() - interval '100 days', now() - interval '1 minute'),
	-- Checked three days ago, and its answer holds it.
	('b9a20000-0000-0000-0000-000000000002', 'b9a10000-0000-0000-0000-000000000001', 'calls.port_bill', 'held.pdf',
	 'application/pdf', 10, 'b9a10000-0000-0000-0000-000000000001/setup-protected/held.pdf', 'ready', repeat('d', 64),
	 now() - interval '3 days', now() - interval '3 days', null),
	-- Checked three days ago, and no answer ever held it.
	('b9a20000-0000-0000-0000-000000000003', 'b9a10000-0000-0000-0000-000000000001', 'calls.port_bill', 'lost.pdf',
	 'application/pdf', 10, 'b9a10000-0000-0000-0000-000000000001/setup-protected/lost.pdf', 'ready', repeat('e', 64),
	 now() - interval '3 days', now() - interval '3 days', null);
insert into public.setup_protected_documents (id, organization_id, fact_key, display_name, mime_type, size_bytes,
	object_key, state, created_at)
values
	-- An upload never finished, two days ago.
	('b9a20000-0000-0000-0000-000000000004', 'b9a10000-0000-0000-0000-000000000001', 'calls.port_bill', 'tab.pdf',
	 'application/pdf', 10, 'b9a10000-0000-0000-0000-000000000001/setup-protected/tab.pdf', 'uploading',
	 now() - interval '2 days');

insert into public.organization_setup_answers (organization_id, fact_key, availability, value)
values ('b9a10000-0000-0000-0000-000000000001', 'calls.port_bill', 'have',
	'["b9a20000-0000-0000-0000-000000000002"]'::jsonb);

select set_eq(
	$$select object_key from public.sweep_setup_protected_documents(100)
		where object_key like 'b9a10000-0000-0000-0000-000000000001/%'$$,
	array[
		'b9a10000-0000-0000-0000-000000000001/setup-protected/old.pdf',
		'b9a10000-0000-0000-0000-000000000001/setup-protected/lost.pdf',
		'b9a10000-0000-0000-0000-000000000001/setup-protected/tab.pdf'
	],
	'The sweep deletes the expired file, the unheld one and the unfinished upload'
);
select ok(
	(select held_at is not null and state = 'ready' from public.setup_protected_documents
		where id = 'b9a20000-0000-0000-0000-000000000002'),
	'A file its answer holds is kept and marked held'
);
select is(
	(select array_agg(action) from public.setup_protected_document_events
		where document_id = 'b9a20000-0000-0000-0000-000000000001'),
	array['expired'],
	'Deletion on its date is recorded'
);

select * from finish();

rollback;
