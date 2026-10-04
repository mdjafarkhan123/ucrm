-- Client onboarding B13: Check and send to Uplift — the submitted snapshot.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §3.10 and the setup content blueprint's
-- stage 12. Storage decision: docs/adr/0005-client-setup-answers-draft-snapshot-accepted.md (the second of the
-- three layers). Industry reference: GOV.UK "Check answers" and "Complete multiple tasks" — submit once every
-- task is done, and keep what was submitted.
--
-- Each Send to Uplift adds one row: a copy of the answers the client was asked at that moment (an answer an
-- earlier answer hides stays in the draft but is left out here), the setup version and package services it was
-- taken against, the exact confirmation wording ticked, who sent it and when. A later edit is compared with the
-- newest row to show it as a change; "Send changes to Uplift" adds the next row (Jafar, 2026-10-04). No row is
-- ever changed.

create table public.organization_setup_submissions (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	-- 1 for the first send, 2 for the first "Send changes", and so on.
	submission_number integer not null check (submission_number > 0),
	setup_version_id uuid not null references public.setup_versions (id) on delete restrict,
	service_keys text[] not null,
	-- { "<fact_key>": { "availability": ..., "value": ..., "note": ... } }, copied from the draft rows.
	answers jsonb not null,
	-- [{ "key": text, "wording": text }], exactly as shown and ticked.
	confirmations jsonb not null,
	confirmations_version text not null check (char_length(confirmations_version) between 1 and 40),
	submitted_by uuid references auth.users (id) on delete set null,
	-- Kept as they were at the time, so the record still reads correctly after the person leaves.
	submitted_by_name text not null,
	submitted_by_email text not null,
	submitted_at timestamptz not null default now(),
	constraint organization_setup_submissions_number_key unique (organization_id, submission_number),
	constraint organization_setup_submissions_answers_check check (
		jsonb_typeof(answers) = 'object' and octet_length(answers::text) <= 4000000
	),
	constraint organization_setup_submissions_confirmations_check check (
		jsonb_typeof(confirmations) = 'array' and jsonb_array_length(confirmations) between 1 and 20
	)
);

comment on table public.organization_setup_submissions is
	'Client setup as sent to Uplift (ADR 0005, the submitted snapshot). Never updated. Administrators may read it; rows arrive only through public.submit_organization_setup.';

create index organization_setup_submissions_version_idx
	on public.organization_setup_submissions (setup_version_id);
create index organization_setup_submissions_submitted_by_idx
	on public.organization_setup_submissions (submitted_by) where submitted_by is not null;

-- What was sent stays as it was sent, for everyone, the service role included. Deleting the organization
-- still removes its rows.
create function private.refuse_setup_submission_change()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
	raise exception 'Setup that was sent to Uplift cannot be changed.' using errcode = 'check_violation';
end;
$$;

create trigger organization_setup_submissions_frozen
	before update on public.organization_setup_submissions
	for each row execute function private.refuse_setup_submission_change();

alter table public.organization_setup_submissions enable row level security;
revoke all on table public.organization_setup_submissions from public, anon, authenticated;
grant select on table public.organization_setup_submissions to authenticated;
grant all on table public.organization_setup_submissions to service_role;

create policy "administrators can view their setup submissions"
	on public.organization_setup_submissions
	for select
	to authenticated
	using ((select private.is_organization_admin(organization_id)));

-- Takes the snapshot. The server has already checked that every task is done and every confirmation ticked,
-- and names the questions this client is asked now (`fact_keys`); the values themselves are copied here, from
-- the draft rows, in the same transaction. `previous_number` is the newest submission the person was looking
-- at (0 for none): a double press or a second device sending first returns 'stale' and adds nothing.
create function public.submit_organization_setup(
	target_organization_id uuid,
	previous_number integer,
	target_version_id uuid,
	package_service_keys text[],
	fact_keys text[],
	new_confirmations jsonb,
	new_confirmations_version text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
	latest integer;
	sender_name text;
	sender_email text;
	created public.organization_setup_submissions;
begin
	perform private.require_organization_setup_editor(target_organization_id);

	if previous_number is null or target_version_id is null or package_service_keys is null
		or fact_keys is null or new_confirmations_version is null then
		raise exception 'The setup to send is incomplete.' using errcode = 'check_violation';
	end if;

	if jsonb_typeof(new_confirmations) is distinct from 'array'
		or exists (
			select 1
			from jsonb_array_elements(new_confirmations) as item(confirmation)
			where coalesce(item.confirmation ->> 'key', '') = ''
				or char_length(coalesce(item.confirmation ->> 'wording', '')) not between 1 and 600
		) then
		raise exception 'Each confirmation needs its wording.' using errcode = 'check_violation';
	end if;

	-- One send at a time per organization.
	insert into public.organization_setup (organization_id)
	values (target_organization_id)
	on conflict (organization_id) do nothing;
	perform 1 from public.organization_setup
	where organization_id = target_organization_id
	for update;

	select coalesce(max(submission_number), 0) into latest
	from public.organization_setup_submissions
	where organization_id = target_organization_id;
	if latest <> previous_number then
		return jsonb_build_object('status', 'stale', 'latest_number', latest);
	end if;

	select coalesce(nullif(btrim(p.full_name), ''), u.email), u.email
	into sender_name, sender_email
	from auth.users u
	left join public.profiles p on p.id = u.id
	where u.id = (select auth.uid());

	insert into public.organization_setup_submissions (
		organization_id, submission_number, setup_version_id, service_keys, answers, confirmations,
		confirmations_version, submitted_by, submitted_by_name, submitted_by_email
	)
	values (
		target_organization_id,
		latest + 1,
		target_version_id,
		package_service_keys,
		coalesce((
			select jsonb_object_agg(
				a.fact_key,
				jsonb_build_object('availability', a.availability, 'value', a.value, 'note', a.note)
			)
			from public.organization_setup_answers a
			where a.organization_id = target_organization_id
				and a.fact_key = any (fact_keys)
		), '{}'::jsonb),
		new_confirmations,
		new_confirmations_version,
		(select auth.uid()),
		coalesce(sender_name, 'Unknown'),
		coalesce(sender_email, '')
	)
	returning * into created;

	return jsonb_build_object(
		'status', 'sent',
		'submission_number', created.submission_number,
		'submitted_at', created.submitted_at
	);
end;
$$;

revoke all on function public.submit_organization_setup(uuid, integer, uuid, text[], text[], jsonb, text)
	from public, anon;
grant execute on function public.submit_organization_setup(uuid, integer, uuid, text[], text[], jsonb, text)
	to authenticated, service_role;
