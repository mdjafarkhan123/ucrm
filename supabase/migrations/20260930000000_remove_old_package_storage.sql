-- Package builder P3b: remove the old package storage (ADR 0003 decision 1).
--
-- P3a moved every access and limit check onto package editions and agreements. This clears the test
-- organizations' old package, payment, exception, and free-access history (Jafar, 2026-09-29: every
-- organization is test data), points onboarding applications and email-template restrictions at the new
-- storage, and deletes the old package tables, columns, and commands. The old payment tables stay empty
-- until P4 replaces them; the free-access table stays until P5 rebuilds free access.

-- ---------------------------------------------------------------------------------------------------
-- 1. Clear the old commercial history. Lifecycle events (suspension, reactivation, setup resolved) stay.
-- ---------------------------------------------------------------------------------------------------

-- The append-only history triggers allow deletion only while this flag is set.
select set_config('app.organization_purge_in_progress', 'true', true);

create temporary table cleared_commercial_events on commit drop as
select id
from public.organization_commercial_events
where event_kind not in ('organization_suspended', 'organization_reactivated', 'pending_setup_resolved');

-- Allowance periods keep their usage counts; only the link to the payment that opened them goes.
update public.communication_email_allowance_periods
set opened_by_commercial_event_id = null
where opened_by_commercial_event_id in (select id from cleared_commercial_events);

update public.website_chat_allowance_periods
set opened_by_commercial_event_id = null
where opened_by_commercial_event_id in (select id from cleared_commercial_events);

update public.marketing_email_allowance_periods
set opened_by_commercial_event_id = null
where opened_by_commercial_event_id in (select id from cleared_commercial_events);

delete from public.organization_safe_events
where commercial_event_id in (select id from cleared_commercial_events);

-- Paid-through dates came from the cleared payments; P4 records coverage afresh.
update public.organization_commercial_state as state
set paid_through_date = null,
	paid_through_source = null,
	grace_ends_at = null,
	grace_basis_timezone = null,
	last_event_id = (
		select event.id
		from public.organization_commercial_events as event
		where event.organization_id = state.organization_id
			and event.id not in (select id from cleared_commercial_events)
		order by event.occurred_at desc, event.created_at desc
		limit 1
	),
	state_version = state.state_version + 1;

delete from public.organization_commercial_events
where id in (select id from cleared_commercial_events);

delete from public.organization_free_access_events;
delete from public.organization_payment_confirmations;
delete from public.organization_billing_accounts;

-- ---------------------------------------------------------------------------------------------------
-- 2. Free access no longer names a package version. Until P5 rebuilds it, the two active test
-- organizations get open-ended free access so their email and chat allowances keep working.
-- ---------------------------------------------------------------------------------------------------

alter table public.organization_free_access_events drop column package_version_id;

create or replace function private.validate_organization_free_access_event()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
	target_is_root boolean;
begin
	if new.occurred_at > now() then
		raise exception 'Free access events cannot be dated in the future.'
			using errcode = 'check_violation';
	end if;

	if new.target_grant_id is not null then
		select exists (
			select 1
			from public.organization_free_access_events as root
			where root.id = new.target_grant_id
				and root.organization_id = new.organization_id
				and root.target_grant_id is null
		)
		into target_is_root;

		if not target_is_root then
			raise exception 'The referenced free access grant was not found for this organization.'
				using errcode = 'foreign_key_violation';
		end if;
	end if;

	return new;
end;
$$;

insert into public.organization_free_access_events (
	organization_id, action, starts_at, access_until_date, reason, actor_kind, actor_owner_email
)
select o.id, 'grant', (now() at time zone 'UTC')::date, null,
	'Test reset when the old package storage was removed (package builder P3b, Jafar 2026-09-29).',
	'platform_owner', 'dev.jafarkhan@gmail.com'
from public.organizations as o
where o.lifecycle_status = 'active';

-- ---------------------------------------------------------------------------------------------------
-- 3. Onboarding applications point at package editions and keep their frozen snapshots.
-- ---------------------------------------------------------------------------------------------------

alter table public.platform_onboarding_applications
	add column package_edition_id uuid references public.package_editions (id),
	add column billing_interval text not null default 'month' check (billing_interval in ('month', 'year'));

update public.platform_onboarding_applications
set package_edition_id = (
	select e.id
	from public.package_editions as e
	join public.packages as p on p.id = e.package_id
	where p.slug = 'test-package' and e.status = 'published'
);

alter table public.platform_onboarding_applications
	alter column package_edition_id set not null,
	alter column billing_interval drop default,
	drop column package_version_id;

create index platform_onboarding_applications_edition_idx
	on public.platform_onboarding_applications (package_edition_id);

-- The application carries the edition; each confirmation keeps its amount and reference.
alter table public.platform_onboarding_application_payment_confirmations drop column package_version_id;

create function public.submit_onboarding_application(
	target_business_name text,
	target_main_contact_name text,
	target_main_contact_email text,
	target_main_contact_phone text,
	target_initial_administrator_name text,
	target_initial_administrator_email text,
	target_trade text,
	target_city_country text,
	target_time_zone text,
	target_note text,
	target_package_edition_id uuid,
	target_billing_interval text,
	target_privacy_policy_version text,
	target_submitted_data jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	edition record;
	agreed_price integer;
	package_snapshot jsonb;
	clean_business_name text;
	clean_contact_email text;
	clean_admin_email text;
	is_duplicate boolean;
	new_application_id uuid;
begin
	if target_billing_interval not in ('month', 'year') then
		raise exception 'Choose monthly or yearly billing.' using errcode = 'check_violation';
	end if;

	select e.id, e.status, e.edition_number, e.name, e.promise, e.highlights, e.included_services,
		e.exclusions, e.monthly_price_usd_cents, e.yearly_price_usd_cents,
		p.slug, p.visibility, p.archived_at
	into edition
	from public.package_editions as e
	join public.packages as p on p.id = e.package_id
	where e.id = target_package_edition_id;

	if not found then
		raise exception 'The selected package no longer exists.' using errcode = 'foreign_key_violation';
	end if;

	agreed_price := case target_billing_interval
		when 'month' then edition.monthly_price_usd_cents
		else edition.yearly_price_usd_cents
	end;

	if edition.status <> 'published' or edition.visibility <> 'public' or edition.archived_at is not null
		or agreed_price is null then
		raise exception 'The selected package is no longer available.' using errcode = 'check_violation';
	end if;

	-- `display_name`, `price_usd_cents`, `currency`, and `billing_period` keep the prospect screens'
	-- existing snapshot shape; the rest freezes the customer-facing edition terms.
	package_snapshot := jsonb_build_object(
		'edition_id', edition.id,
		'package_slug', edition.slug,
		'edition_number', edition.edition_number,
		'display_name', edition.name,
		'promise', edition.promise,
		'highlights', edition.highlights,
		'included_services', edition.included_services,
		'exclusions', edition.exclusions,
		'price_usd_cents', agreed_price,
		'currency', 'USD',
		'billing_period', target_billing_interval
	);

	clean_business_name := trim(target_business_name);
	clean_contact_email := lower(trim(target_main_contact_email));
	clean_admin_email := nullif(lower(trim(coalesce(target_initial_administrator_email, ''))), '');

	select exists (
		select 1
		from public.platform_onboarding_applications as existing
		where lower(existing.main_contact_email) = clean_contact_email
			or lower(existing.business_name) = lower(clean_business_name)
			or (clean_admin_email is not null
				and lower(existing.initial_administrator_email) = clean_admin_email)
	) into is_duplicate;

	insert into public.platform_onboarding_applications (
		business_name, main_contact_name, main_contact_email, main_contact_phone,
		initial_administrator_name, initial_administrator_email, trade, city_country, time_zone,
		note, package_edition_id, billing_interval, package_snapshot, possible_duplicate
	) values (
		clean_business_name, trim(target_main_contact_name), clean_contact_email, trim(target_main_contact_phone),
		nullif(trim(coalesce(target_initial_administrator_name, '')), ''), clean_admin_email,
		trim(target_trade), trim(target_city_country), trim(target_time_zone),
		nullif(trim(coalesce(target_note, '')), ''), target_package_edition_id, target_billing_interval,
		package_snapshot, is_duplicate
	)
	returning id into new_application_id;

	insert into public.platform_onboarding_application_submissions (
		application_id, submitted_data, package_snapshot, privacy_policy_version, agreement_accepted_at
	) values (
		new_application_id, target_submitted_data, package_snapshot, target_privacy_policy_version, now()
	);

	return new_application_id;
end;
$$;

revoke all on function public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb)
	from public, anon, authenticated;
grant execute on function public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb)
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Email templates are restricted by package identity, which survives new editions.
-- ---------------------------------------------------------------------------------------------------

drop table public.platform_email_template_packages;

create table public.platform_email_template_packages (
	template_id uuid not null references public.platform_email_templates (id) on delete cascade,
	package_id uuid not null references public.packages (id) on delete cascade,
	created_at timestamptz not null default now(),
	primary key (template_id, package_id)
);

create index platform_email_template_packages_package_idx on public.platform_email_template_packages (package_id);

-- Owner-only: read and written by the service role, like the table it replaces.
alter table public.platform_email_template_packages enable row level security;
revoke all on public.platform_email_template_packages from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 5. Organization purge no longer touches package assignments.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.apply_organization_purge(
	target_organization_id uuid,
	purge_trigger_kind text,
	actor_owner_email text
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
	organization_row public.organizations%rowtype;
	closure_record public.organization_closure_records%rowtype;
	inserted_receipt public.organization_deletion_receipts%rowtype;
	member_user_ids uuid[];
	had_onboarding_provision boolean;
	provider_resources jsonb;
	auth_pending boolean;
	provider_pending boolean;
	receipt_status text;
	receipt_completed_at timestamptz;
begin
	if purge_trigger_kind not in ('scheduled', 'early_manual') then
		raise exception 'An invalid purge trigger kind was supplied.' using errcode = 'check_violation';
	end if;
	if purge_trigger_kind = 'early_manual'
		and char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
		raise exception 'An acting owner email is required for an early manual purge.'
			using errcode = 'check_violation';
	end if;

	select * into organization_row
	from public.organizations
	where id = target_organization_id
	for update;

	if not found then
		return jsonb_build_object('applied', false, 'reason', 'already_purged');
	end if;

	select * into closure_record
	from public.organization_closure_records
	where organization_id = target_organization_id
		and status in ('pending_closure', 'purge_in_progress')
	for update;

	if not found then
		raise exception 'No open closure window was found for this organization.'
			using errcode = 'check_violation';
	end if;

	select coalesce(array_agg(distinct organization_members.user_id), array[]::uuid[])
	into member_user_ids
	from public.organization_members
	where organization_members.organization_id = target_organization_id;

	select exists (
		select 1
		from public.platform_onboarding_application_provisions
		where platform_onboarding_application_provisions.organization_id = target_organization_id
	) into had_onboarding_provision;

	select case
		when exists (
			select 1 from public.communication_email_domains
			where organization_id = target_organization_id
		)
		then jsonb_build_array(
			jsonb_build_object('kind', 'ses_organization', 'provider_id', target_organization_id::text)
		)
		else '[]'::jsonb
	end
	into provider_resources;

	auth_pending := coalesce(array_length(member_user_ids, 1), 0) > 0;
	provider_pending := jsonb_array_length(provider_resources) > 0;

	if auth_pending or provider_pending then
		receipt_status := 'in_progress';
		receipt_completed_at := null;
	else
		receipt_status := 'completed';
		receipt_completed_at := now();
	end if;

	perform set_config('app.organization_purge_in_progress', 'true', true);

	delete from public.organization_free_access_events
	where organization_id = target_organization_id;

	update public.platform_onboarding_application_provisions
	set organization_id = null
	where organization_id = target_organization_id;

	-- Agreements and exceptions cascade with the organization.
	delete from public.organizations
	where id = target_organization_id;

	insert into public.organization_deletion_receipts (
		trigger_kind, status, completed_at, component_results,
		pending_auth_user_ids, pending_provider_resources
	) values (
		purge_trigger_kind, receipt_status, receipt_completed_at,
		jsonb_build_object(
			'organization_data', 'succeeded',
			'package_agreements', 'succeeded',
			'free_access_history', 'succeeded',
			'onboarding_provision_unlinked', case when had_onboarding_provision then 'succeeded' else 'not_applicable' end,
			'provider_resources', case when provider_pending then 'pending' else 'not_applicable' end,
			'auth_users', case when auth_pending then 'pending' else 'not_applicable' end
		),
		case when auth_pending then member_user_ids else null end,
		case when provider_pending then provider_resources else null end
	) returning * into inserted_receipt;

	return jsonb_build_object(
		'applied', true,
		'operation_id', inserted_receipt.operation_id,
		'member_user_ids', to_jsonb(member_user_ids),
		'provider_resources', provider_resources
	);
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 6. Delete the old package commands, tables, and columns.
-- ---------------------------------------------------------------------------------------------------

drop function public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, jsonb);
drop function public.confirm_onboarding_application_payment(uuid, text, integer, text, text);
drop function public.correct_onboarding_application_package(uuid, text, uuid, text);
drop function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, text);
drop function public.apply_organization_package_change(uuid, uuid, text, text, text, timestamptz);
drop function public.apply_organization_feature_exception(uuid, text, text, timestamptz, timestamptz, text, text, text, timestamptz);
drop function public.apply_organization_limit_exception(uuid, text, text, integer, timestamptz, timestamptz, text, text, text, timestamptz);
drop function public.apply_organization_free_access_change(uuid, text, uuid, date, date, text, text, text, timestamptz);
drop function public.record_legacy_organization_package(uuid, uuid, date, text);
drop function public.apply_organization_pending_setup_reconciliation(uuid, text, text, text, text, text, timestamptz);
drop function public.organization_legacy_readiness(uuid);
drop function public.manage_platform_package_version(text, text, uuid, text, text, text, integer, text[], text, integer, text);
drop function public.manage_platform_package_email_allowances(uuid, text, integer, text, integer, text);
drop function public.manage_platform_package_marketing_allowance(uuid, text, integer, text);
drop function public.manage_platform_package_website_chat_limits(uuid, text, integer, text, integer, text);
drop function public.manage_platform_package_automation_limits(uuid, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text);

alter table public.organizations
	drop column package_key,
	drop column scheduled_package_key,
	drop column scheduled_package_effective_at;

-- One statement, because the old tables' read policies refer to each other.
drop table
	public.organization_package_assignments,
	public.organization_feature_overrides,
	public.organization_limit_overrides,
	public.package_features,
	public.package_limits,
	public.platform_package_version_features,
	public.platform_package_version_limits,
	public.platform_package_versions,
	public.platform_packages;

drop function private.validate_organization_package_assignment();
drop function private.validate_platform_package_version();
drop function private.validate_published_package_version_feature();
drop function private.validate_published_package_version_limit();
