-- Stage 10 Part 3 (docs/global-sms-behavior-contract.md § Part 3): number paperwork, GoHighLevel's Regulatory
-- Bundle / Address area. Some countries only sell a number to a business that has proved who it is and where it
-- is; Twilio calls that proof a Regulatory Bundle.
--
-- 1. A set of paperwork. One per business, country and number kind, the way the list shows it. It keeps what
--    the business filled in (the person or business answers and the address), the document chosen for each of
--    the country's requirements, and the Twilio records made from them, so sending again after a dropped
--    connection or a rejection reuses them instead of making a second set at Twilio.
-- 2. Its documents. One row per kind of document, so a document that proves several things (an Australian
--    company register extract shows the name, the address and the number) is uploaded once. The file itself is
--    a protected setup document (20261018090000): private, virus-checked, opened only by the owner and Jafar,
--    and deleted 90 days after the paperwork is approved.
-- 3. Its history: every send, check and outcome, never edited.
--
-- No browser reads these tables: row level security is on with no policies. The server checks who is asking.

-- 1. Paperwork sets ------------------------------------------------------------------------------------------

create table public.communication_sms_number_paperwork (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  country_code text not null,
  number_type text not null,
  end_user_type text not null default 'business',
  -- draft: being filled in. sending: Uplift is passing it to Twilio right now. under_review: Twilio has it.
  -- approved: numbers can be bought with it. needs_fix: Twilio or its check found something to correct.
  status text not null default 'draft',
  -- The answers Twilio asks for about the business or person, keyed by Twilio's field name.
  answers jsonb not null default '{}'::jsonb,
  -- The address: { customer_name, street, street_secondary, city, region, postal_code, country_code }.
  address jsonb,
  -- The document kind chosen for each of the country's requirements, keyed by Twilio's requirement name.
  document_choices jsonb not null default '{}'::jsonb,
  -- Raised by every saved change, so two open tabs cannot quietly overwrite each other.
  revision integer not null default 1,
  regulation_sid text,
  provider_address_sid text,
  provider_end_user_sid text,
  provider_bundle_sid text,
  provider_status text,
  -- What the phone company said was wrong, and the fields or documents it points at.
  failure_reason text,
  fixes jsonb not null default '[]'::jsonb,
  valid_until timestamptz,
  sending_claim_token uuid,
  sending_claimed_at timestamptz,
  submitted_at timestamptz,
  decided_at timestamptz,
  last_checked_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_number_paperwork_org_id_key unique (organization_id, id),
  constraint communication_sms_number_paperwork_kind_key unique (organization_id, country_code, number_type),
  constraint communication_sms_number_paperwork_country_check check (country_code ~ '^[A-Z]{2}$'),
  constraint communication_sms_number_paperwork_type_check
    check (number_type in ('local', 'mobile', 'national', 'toll_free')),
  constraint communication_sms_number_paperwork_end_user_check check (end_user_type in ('business', 'individual')),
  constraint communication_sms_number_paperwork_status_check
    check (status in ('draft', 'sending', 'under_review', 'approved', 'needs_fix')),
  constraint communication_sms_number_paperwork_answers_check check (
    jsonb_typeof(answers) = 'object' and pg_column_size(answers) <= 16384
  ),
  constraint communication_sms_number_paperwork_address_check check (
    address is null or (jsonb_typeof(address) = 'object' and pg_column_size(address) <= 4096)
  ),
  constraint communication_sms_number_paperwork_choices_check check (
    jsonb_typeof(document_choices) = 'object' and pg_column_size(document_choices) <= 4096
  ),
  constraint communication_sms_number_paperwork_fixes_check check (
    jsonb_typeof(fixes) = 'array' and pg_column_size(fixes) <= 16384
  ),
  constraint communication_sms_number_paperwork_revision_check check (revision >= 1),
  constraint communication_sms_number_paperwork_sids_check check (
    (regulation_sid is null or regulation_sid ~ '^RN[0-9A-Fa-f]{32}$')
    and (provider_address_sid is null or provider_address_sid ~ '^AD[0-9A-Fa-f]{32}$')
    and (provider_end_user_sid is null or provider_end_user_sid ~ '^IT[0-9A-Fa-f]{32}$')
    and (provider_bundle_sid is null or provider_bundle_sid ~ '^BU[0-9A-Fa-f]{32}$')
  ),
  constraint communication_sms_number_paperwork_reason_check
    check (failure_reason is null or char_length(failure_reason) <= 4000),
  -- Only a set being sent holds a claim, and a claim always has its time.
  constraint communication_sms_number_paperwork_claim_check check (
    (sending_claim_token is null) = (sending_claimed_at is null)
    and (status = 'sending' or sending_claim_token is null)
  ),
  -- A set Twilio has, or had, always has its Twilio bundle.
  constraint communication_sms_number_paperwork_bundle_check check (
    status not in ('under_review', 'approved') or provider_bundle_sid is not null or regulation_sid is null
  )
);

comment on table public.communication_sms_number_paperwork is
  'Stage 10 Part 3: a business''s paperwork (Twilio Regulatory Bundle and address) for one country and number kind. Server only.';

-- The bundle Twilio's status callback names, and the daily check's waiting sets.
create unique index communication_sms_number_paperwork_bundle_idx
  on public.communication_sms_number_paperwork (provider_bundle_sid)
  where provider_bundle_sid is not null;
create index communication_sms_number_paperwork_waiting_idx
  on public.communication_sms_number_paperwork (last_checked_at nulls first)
  where status = 'under_review';

alter table public.communication_sms_number_paperwork enable row level security;
revoke all on table public.communication_sms_number_paperwork from anon, authenticated;

-- 2. Documents -----------------------------------------------------------------------------------------------

create table public.communication_sms_number_paperwork_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  paperwork_id uuid not null,
  -- Twilio's document kind, e.g. utility_bill or business_address.
  document_type text not null,
  -- The uploaded file. Null for a kind that is only the address (business_address), or before a file is added.
  protected_document_id uuid references public.setup_protected_documents(id) on delete set null,
  -- What the business typed about the document, e.g. its number, keyed by Twilio's field name.
  fields jsonb not null default '{}'::jsonb,
  provider_document_sid text,
  -- The file and fields the Twilio record was made from, so a change makes a new record.
  provider_protected_document_id uuid,
  provider_fields jsonb,
  provider_status text,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_number_paperwork_documents_set_fkey
    foreign key (organization_id, paperwork_id)
    references public.communication_sms_number_paperwork (organization_id, id) on delete cascade,
  constraint communication_sms_number_paperwork_documents_kind_key unique (paperwork_id, document_type),
  constraint communication_sms_number_paperwork_documents_type_check
    check (document_type ~ '^[a-z][a-z0-9_]{1,99}$'),
  constraint communication_sms_number_paperwork_documents_fields_check check (
    jsonb_typeof(fields) = 'object' and pg_column_size(fields) <= 8192
  ),
  constraint communication_sms_number_paperwork_documents_sid_check
    check (provider_document_sid is null or provider_document_sid ~ '^RD[0-9A-Fa-f]{32}$'),
  constraint communication_sms_number_paperwork_documents_reason_check
    check (failure_reason is null or char_length(failure_reason) <= 4000)
);

comment on table public.communication_sms_number_paperwork_documents is
  'Stage 10 Part 3: one document kind of a paperwork set, its protected file and its Twilio supporting document.';

create index communication_sms_number_paperwork_documents_file_idx
  on public.communication_sms_number_paperwork_documents (protected_document_id)
  where protected_document_id is not null;

alter table public.communication_sms_number_paperwork_documents enable row level security;
revoke all on table public.communication_sms_number_paperwork_documents from anon, authenticated;

-- 3. History -------------------------------------------------------------------------------------------------

create table public.communication_sms_number_paperwork_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  paperwork_id uuid not null,
  -- sent, check_failed, provider_unavailable, under_review, approved, needs_fix, checked
  action text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint communication_sms_number_paperwork_events_set_fkey
    foreign key (organization_id, paperwork_id)
    references public.communication_sms_number_paperwork (organization_id, id) on delete cascade,
  constraint communication_sms_number_paperwork_events_action_check
    check (action ~ '^[a-z][a-z_]{1,59}$'),
  constraint communication_sms_number_paperwork_events_detail_check check (
    jsonb_typeof(detail) = 'object' and pg_column_size(detail) <= 8192
  )
);

create index communication_sms_number_paperwork_events_set_idx
  on public.communication_sms_number_paperwork_events (paperwork_id, created_at);

alter table public.communication_sms_number_paperwork_events enable row level security;
revoke all on table public.communication_sms_number_paperwork_events from anon, authenticated;

-- 4. Protected files held by paperwork -----------------------------------------------------------------------

-- Approved paperwork has done its job at Twilio, so its files are deleted 90 days later, like a setup document
-- whose provider step is finished. Marking again keeps the first date.
create or replace function public.communication_sms_schedule_paperwork_file_deletion(target_paperwork_id uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  scheduled integer;
begin
  with due as (
    update public.setup_protected_documents d
    set delete_after = now() + interval '90 days'
    from public.communication_sms_number_paperwork_documents p
    where p.paperwork_id = target_paperwork_id
      and p.protected_document_id = d.id
      and p.organization_id = d.organization_id
      and d.state = 'ready'
      and d.delete_after is null
    returning d.id
  ),
  logged as (
    insert into public.setup_protected_document_events (document_id, action, actor_label)
    select due.id, 'deletion_scheduled', 'Automatic' from due
    returning 1
  )
  select count(*) into scheduled from logged;
  return scheduled;
end;
$$;

-- The setup sweep deletes a ready file that nothing holds after two days. A paperwork document holds its file
-- just as a setup answer does, so the sweep now looks there too. Otherwise unchanged from 20261018090000.
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
		and (
			exists (
				select 1 from public.organization_setup_answers a
				where a.organization_id = d.organization_id
					and a.fact_key = d.fact_key
					and a.value @> to_jsonb(array[d.id::text])
			)
			or exists (
				select 1 from public.communication_sms_number_paperwork_documents p
				where p.organization_id = d.organization_id
					and p.protected_document_id = d.id
			)
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

revoke all on function public.communication_sms_schedule_paperwork_file_deletion(uuid) from public, anon, authenticated;
revoke all on function public.sweep_setup_protected_documents(integer) from public, anon, authenticated;
grant execute on function public.communication_sms_schedule_paperwork_file_deletion(uuid) to service_role;
grant execute on function public.sweep_setup_protected_documents(integer) to service_role;
