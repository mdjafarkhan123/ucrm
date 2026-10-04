-- Client onboarding B9a: protected documents for setup (plan §§3.6, 9; Jafar's decisions of 2026-10-04 in
-- Memory/campaigns/client-onboarding-delivery/parts/B9-texting-facts.md).
--
-- A phone bill for moving a number, or a tax letter for texting registration, is not an ordinary setup file.
-- Ordinary setup files are File library Files, which the whole team may browse and which many database
-- commands accept by id (attach to a job, share with a customer). So a protected document lives here instead,
-- where none of those commands can reach it:
--
-- 1. Only the business owner and Jafar can open one. An administrator doing setup can upload one and sees that
--    it was received, nothing more. It never appears in the File library.
-- 2. Every upload, opening and removal is recorded with who and when; the owner and Jafar both see that list.
-- 3. It is checked for viruses like every upload, and a refused file is deleted at once.
-- 4. It is deleted 90 days after the provider step it served is finished, or sooner when Jafar deletes it.
--    The row and its history stay, so "who opened my bill?" still has an answer after the file is gone.
--
-- No browser ever reads these tables: row level security is on with no policies, and every command below is
-- for the server's service role only. The server decides who is asking (src/lib/server/setup/protected-documents.ts).

-- 1. A "protected file" setup question ----------------------------------------------------------------------

alter table public.setup_items drop constraint setup_items_kind_check;
alter table public.setup_items add constraint setup_items_kind_check
	check (kind in (
		'text', 'longtext', 'email', 'phone', 'choice', 'multi_choice', 'yes_no', 'yes_no_unsure', 'date', 'url',
		'number', 'money', 'percentage', 'distance', 'duration', 'colours', 'file', 'protected_file', 'list', 'pick',
		'reuse'
	));

-- A protected question always takes documents and photos, so it has no choice of file kinds; it does say how
-- many files one answer may hold.
alter table public.setup_items drop constraint setup_items_max_files_check;
alter table public.setup_items add constraint setup_items_max_files_check check (
	(kind in ('file', 'protected_file')) = (max_files is not null)
	and (max_files is null or max_files in (1, 5, 10, 20))
);

-- 2. The documents ------------------------------------------------------------------------------------------

create table public.setup_protected_documents (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	-- The setup question it answers.
	fact_key text not null,
	display_name text not null,
	mime_type text not null,
	size_bytes bigint not null,
	-- Cleared when the file is deleted from storage; the row stays for its history.
	object_key text unique,
	-- uploading: the bytes are on their way. checking: they arrived and wait for the virus check.
	-- ready: it can be opened. refused: it failed a check and was deleted. deleted: removed from storage.
	state text not null default 'uploading',
	problem text,
	checksum_sha256 text,
	uploaded_by uuid references auth.users (id) on delete set null,
	created_at timestamptz not null default now(),
	upload_completed_at timestamptz,
	scanned_at timestamptz,
	-- When the sweep first found the document held by its question's answer. Until then it may be an upload
	-- whose answer never saved.
	held_at timestamptz,
	claimed_at timestamptz,
	claim_token uuid,
	processing_attempts smallint not null default 0,
	-- Set when Jafar marks the provider step it served finished: 90 days later the file is deleted.
	delete_after timestamptz,
	deleted_at timestamptz,
	constraint setup_protected_documents_fact_key_check check (
		fact_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' and char_length(fact_key) <= 80
	),
	constraint setup_protected_documents_display_name_check check (char_length(display_name) between 1 and 255),
	constraint setup_protected_documents_size_check check (size_bytes > 0),
	constraint setup_protected_documents_state_check check (
		state in ('uploading', 'checking', 'ready', 'refused', 'deleted')
	),
	-- Every stored object sits under its own organization's protected prefix, apart from every other upload.
	constraint setup_protected_documents_object_key_check check (
		object_key is null or object_key like organization_id::text || '/setup-protected/%'
	),
	-- A file still in storage is one that may yet be opened; a refused or deleted one has none.
	constraint setup_protected_documents_stored_check check (
		(state in ('refused', 'deleted')) = (object_key is null)
	),
	constraint setup_protected_documents_deleted_check check ((state = 'deleted') = (deleted_at is not null)),
	constraint setup_protected_documents_ready_check check (
		state <> 'ready' or (checksum_sha256 is not null and scanned_at is not null)
	)
);

comment on table public.setup_protected_documents is
	'Client onboarding B9a: sensitive provider documents a client uploads in setup. Server only; only the owner and Jafar may open one.';

create index setup_protected_documents_organization_idx
	on public.setup_protected_documents (organization_id, fact_key);
-- The virus check's queue, and the abandoned-upload sweep.
create index setup_protected_documents_waiting_idx
	on public.setup_protected_documents (upload_completed_at, created_at)
	where state in ('uploading', 'checking');
create index setup_protected_documents_unheld_idx
	on public.setup_protected_documents (scanned_at)
	where state = 'ready' and held_at is null;
create index setup_protected_documents_delete_after_idx
	on public.setup_protected_documents (delete_after)
	where delete_after is not null and state <> 'deleted';

create table public.setup_protected_document_events (
	id bigint generated always as identity primary key,
	document_id uuid not null references public.setup_protected_documents (id) on delete cascade,
	action text not null,
	-- A member of the client's team, or null for Uplift and for the system.
	actor_user_id uuid references auth.users (id) on delete set null,
	-- Who it was, as shown in the list: the member's name, "Uplift", or "Automatic".
	actor_label text not null,
	-- Jafar's sign-in email when Uplift acted, for his own records.
	actor_owner_email text,
	created_at timestamptz not null default now(),
	constraint setup_protected_document_events_action_check check (
		action in ('uploaded', 'refused', 'opened', 'removed', 'deletion_scheduled', 'deleted_by_uplift', 'expired')
	),
	constraint setup_protected_document_events_actor_label_check check (char_length(actor_label) between 1 and 200)
);

comment on table public.setup_protected_document_events is
	'Client onboarding B9a: every upload, opening and removal of a protected setup document. Never edited.';

create index setup_protected_document_events_document_idx
	on public.setup_protected_document_events (document_id, created_at);

alter table public.setup_protected_documents enable row level security;
alter table public.setup_protected_document_events enable row level security;
revoke all on public.setup_protected_documents from anon, authenticated;
revoke all on public.setup_protected_document_events from anon, authenticated;

-- 3. Commands -------------------------------------------------------------------------------------------------

-- Step one of an upload: the server has already checked who is asking, the question and the file type.
create or replace function public.register_setup_protected_document(
	target_organization_id uuid,
	target_uploaded_by uuid,
	target_fact_key text,
	target_display_name text,
	target_mime_type text,
	target_size_bytes bigint,
	target_object_key text
)
returns public.setup_protected_documents
language plpgsql
set search_path = ''
as $$
declare
	registered public.setup_protected_documents;
begin
	-- A ceiling against a script filling storage: far more than any honest setup question needs.
	if (
		select count(*) from public.setup_protected_documents d
		where d.organization_id = target_organization_id and d.fact_key = target_fact_key and d.state <> 'deleted'
	) >= 40 then
		raise exception 'Too many files have been added to this question. Remove some and try again.'
			using errcode = 'check_violation';
	end if;

	insert into public.setup_protected_documents (
		organization_id, fact_key, display_name, mime_type, size_bytes, object_key, uploaded_by
	)
	values (
		target_organization_id, target_fact_key, target_display_name, target_mime_type, target_size_bytes,
		target_object_key, target_uploaded_by
	)
	returning * into registered;
	return registered;
end;
$$;

-- Step two: the browser says the bytes arrived. Only the uploader can say so, and only once.
create or replace function public.complete_setup_protected_document(
	target_document_id uuid,
	target_organization_id uuid,
	target_uploaded_by uuid,
	target_actor_label text
)
returns public.setup_protected_documents
language plpgsql
set search_path = ''
as $$
declare
	completed public.setup_protected_documents;
begin
	update public.setup_protected_documents d
	set state = 'checking', upload_completed_at = now()
	where d.id = target_document_id
		and d.organization_id = target_organization_id
		and d.uploaded_by = target_uploaded_by
		and d.state = 'uploading'
	returning * into completed;

	if completed.id is null then
		raise exception 'That upload is not waiting to be finished.' using errcode = 'P0002';
	end if;

	insert into public.setup_protected_document_events (document_id, action, actor_user_id, actor_label)
	values (completed.id, 'uploaded', target_uploaded_by, target_actor_label);
	return completed;
end;
$$;

-- The virus check's claim, the same shape as claim_file_processing_jobs.
create or replace function public.claim_setup_protected_documents(batch_size integer default 10)
returns setof public.setup_protected_documents
language plpgsql
set search_path = ''
as $$
declare
	new_claim_token uuid := gen_random_uuid();
begin
	if batch_size not between 1 and 50 then
		raise exception 'The batch is outside its safe bounds.' using errcode = 'check_violation';
	end if;

	return query
	update public.setup_protected_documents d
	set claimed_at = now(), claim_token = new_claim_token, processing_attempts = d.processing_attempts + 1
	from (
		select w.id
		from public.setup_protected_documents w
		where w.state = 'checking'
			and w.processing_attempts < 5
			and (w.claimed_at is null or w.claimed_at <= now() - interval '10 minutes')
		order by w.upload_completed_at, w.id
		limit batch_size
		for update skip locked
	) due
	where d.id = due.id
	returning d.*;
end;
$$;

create or replace function public.release_setup_protected_document_claim(
	target_document_id uuid,
	target_claim_token uuid
)
returns void
language sql
set search_path = ''
as $$
	update public.setup_protected_documents d
	set claimed_at = null, claim_token = null, processing_attempts = greatest(d.processing_attempts - 1, 0)
	where d.id = target_document_id and d.claim_token = target_claim_token and d.state = 'checking';
$$;

-- The check's result. A refused file leaves storage at once: its key comes back for the worker to delete.
create or replace function public.finish_setup_protected_document_check(
	target_document_id uuid,
	target_claim_token uuid,
	target_ready boolean,
	target_checksum_sha256 text,
	target_problem text default null
)
returns table (object_key text)
language plpgsql
set search_path = ''
as $$
declare
	claimed public.setup_protected_documents;
begin
	select * into claimed
	from public.setup_protected_documents d
	where d.id = target_document_id and d.claim_token = target_claim_token and d.state = 'checking'
	for update;
	if claimed.id is null then
		raise exception 'That check is no longer current.' using errcode = 'no_data_found';
	end if;

	if target_ready then
		update public.setup_protected_documents d
		set state = 'ready', checksum_sha256 = target_checksum_sha256, scanned_at = now(), problem = null,
			claimed_at = null, claim_token = null
		where d.id = claimed.id;
		return;
	end if;

	update public.setup_protected_documents d
	set state = 'refused', object_key = null, checksum_sha256 = target_checksum_sha256,
		problem = coalesce(target_problem, 'This file could not be accepted.'), claimed_at = null, claim_token = null
	where d.id = claimed.id;
	insert into public.setup_protected_document_events (document_id, action, actor_label)
	values (claimed.id, 'refused', 'Automatic');
	return query select claimed.object_key;
end;
$$;

-- Opening is recorded before the link exists, so nobody can see a document without leaving a line in its
-- history. Returns the key to sign a link for, or nothing when the document cannot be opened.
create or replace function public.open_setup_protected_document(
	target_document_id uuid,
	target_organization_id uuid,
	target_actor_user_id uuid,
	target_actor_label text,
	target_actor_owner_email text
)
returns table (object_key text, display_name text, mime_type text)
language plpgsql
set search_path = ''
as $$
declare
	found public.setup_protected_documents;
begin
	select * into found
	from public.setup_protected_documents d
	where d.id = target_document_id and d.organization_id = target_organization_id and d.state = 'ready';
	if found.id is null then
		return;
	end if;

	insert into public.setup_protected_document_events (
		document_id, action, actor_user_id, actor_label, actor_owner_email
	)
	values (found.id, 'opened', target_actor_user_id, target_actor_label, target_actor_owner_email);
	return query select found.object_key, found.display_name, found.mime_type;
end;
$$;

-- Removed by the client ('removed') or deleted by Uplift ('deleted_by_uplift'). Returns the key to delete
-- from storage, or nothing when there is no stored file left.
create or replace function public.delete_setup_protected_document(
	target_document_id uuid,
	target_organization_id uuid,
	target_action text,
	target_actor_user_id uuid,
	target_actor_label text,
	target_actor_owner_email text
)
returns table (object_key text)
language plpgsql
set search_path = ''
as $$
declare
	found public.setup_protected_documents;
begin
	if target_action not in ('removed', 'deleted_by_uplift') then
		raise exception 'A document can only be removed or deleted by Uplift here.' using errcode = 'check_violation';
	end if;

	select * into found
	from public.setup_protected_documents d
	where d.id = target_document_id and d.organization_id = target_organization_id
	for update;
	if found.id is null or found.state in ('deleted', 'refused') then
		return;
	end if;

	update public.setup_protected_documents d
	set state = 'deleted', object_key = null, deleted_at = now(), claimed_at = null, claim_token = null
	where d.id = found.id;
	insert into public.setup_protected_document_events (
		document_id, action, actor_user_id, actor_label, actor_owner_email
	)
	values (found.id, target_action, target_actor_user_id, target_actor_label, target_actor_owner_email);
	return query select found.object_key;
end;
$$;

-- Jafar marks the provider step finished: the file is deleted 90 days from now. Marking it again keeps the
-- first date, so a second click never quietly extends how long a client's papers are kept.
create or replace function public.schedule_setup_protected_document_deletion(
	target_document_id uuid,
	target_organization_id uuid,
	target_actor_owner_email text
)
returns public.setup_protected_documents
language plpgsql
set search_path = ''
as $$
declare
	scheduled public.setup_protected_documents;
begin
	update public.setup_protected_documents d
	set delete_after = now() + interval '90 days'
	where d.id = target_document_id
		and d.organization_id = target_organization_id
		and d.state = 'ready'
		and d.delete_after is null
	returning * into scheduled;

	if scheduled.id is null then
		select * into scheduled
		from public.setup_protected_documents d
		where d.id = target_document_id and d.organization_id = target_organization_id;
		if scheduled.id is null then
			raise exception 'That document was not found.' using errcode = 'P0002';
		end if;
		return scheduled;
	end if;

	insert into public.setup_protected_document_events (document_id, action, actor_label, actor_owner_email)
	values (scheduled.id, 'deletion_scheduled', 'Uplift', target_actor_owner_email);
	return scheduled;
end;
$$;

-- The sweep: deletes what is due, and hands back the keys for storage.
--   * past its deletion date;
--   * an upload never finished after a day (a closed tab);
--   * a file five checks could not finish;
--   * a ready file its question's answer never came to hold after two days (added, then the page closed
--     before the answer saved). An answer holds its documents' ids, as a photo or file answer does. A file
--     found held is marked so, and is never looked at again for this reason.
create or replace function public.sweep_setup_protected_documents(batch_size integer default 100)
returns table (object_key text)
language plpgsql
set search_path = ''
as $$
declare
	due record;
begin
	if batch_size not between 1 and 500 then
		raise exception 'The batch is outside its safe bounds.' using errcode = 'check_violation';
	end if;

	update public.setup_protected_documents d
	set held_at = now()
	where d.state = 'ready'
		and d.held_at is null
		and d.scanned_at <= now() - interval '2 days'
		and exists (
			select 1 from public.organization_setup_answers a
			where a.organization_id = d.organization_id
				and a.fact_key = d.fact_key
				and a.value @> to_jsonb(array[d.id::text])
		);

	for due in
		select d.id, d.object_key, d.delete_after is not null and d.delete_after <= now() as expired
		from public.setup_protected_documents d
		where (d.state <> 'deleted' and d.delete_after <= now())
			or (d.state = 'uploading' and d.created_at <= now() - interval '1 day')
			or (d.state = 'checking' and d.processing_attempts >= 5
				and (d.claimed_at is null or d.claimed_at <= now() - interval '10 minutes'))
			or (d.state = 'ready' and d.held_at is null and d.scanned_at <= now() - interval '2 days')
		order by d.created_at
		limit batch_size
		for update skip locked
	loop
		update public.setup_protected_documents d
		set state = 'deleted', object_key = null, deleted_at = now(), claimed_at = null, claim_token = null
		where d.id = due.id;
		if due.expired then
			insert into public.setup_protected_document_events (document_id, action, actor_label)
			values (due.id, 'expired', 'Automatic');
		end if;
		object_key := due.object_key;
		return next;
	end loop;
end;
$$;

revoke all on function public.register_setup_protected_document(uuid, uuid, text, text, text, bigint, text)
	from public, anon, authenticated;
revoke all on function public.complete_setup_protected_document(uuid, uuid, uuid, text)
	from public, anon, authenticated;
revoke all on function public.claim_setup_protected_documents(integer) from public, anon, authenticated;
revoke all on function public.release_setup_protected_document_claim(uuid, uuid) from public, anon, authenticated;
revoke all on function public.finish_setup_protected_document_check(uuid, uuid, boolean, text, text)
	from public, anon, authenticated;
revoke all on function public.open_setup_protected_document(uuid, uuid, uuid, text, text)
	from public, anon, authenticated;
revoke all on function public.delete_setup_protected_document(uuid, uuid, text, uuid, text, text)
	from public, anon, authenticated;
revoke all on function public.schedule_setup_protected_document_deletion(uuid, uuid, text)
	from public, anon, authenticated;
revoke all on function public.sweep_setup_protected_documents(integer) from public, anon, authenticated;

grant execute on function public.register_setup_protected_document(uuid, uuid, text, text, text, bigint, text)
	to service_role;
grant execute on function public.complete_setup_protected_document(uuid, uuid, uuid, text) to service_role;
grant execute on function public.claim_setup_protected_documents(integer) to service_role;
grant execute on function public.release_setup_protected_document_claim(uuid, uuid) to service_role;
grant execute on function public.finish_setup_protected_document_check(uuid, uuid, boolean, text, text)
	to service_role;
grant execute on function public.open_setup_protected_document(uuid, uuid, uuid, text, text) to service_role;
grant execute on function public.delete_setup_protected_document(uuid, uuid, text, uuid, text, text)
	to service_role;
grant execute on function public.schedule_setup_protected_document_deletion(uuid, uuid, text) to service_role;
grant execute on function public.sweep_setup_protected_documents(integer) to service_role;
