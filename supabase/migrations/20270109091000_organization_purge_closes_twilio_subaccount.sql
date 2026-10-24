-- Closing a business also closes its Twilio subaccount (docs/data-privacy-deletion-behavior-contract.md,
-- Jafar 2026-10-24: follow HighLevel, whose sub-account delete closes the LC Phone account and releases its
-- numbers).
--
-- The purge already parks Amazon SES cleanup on the receipt as a retryable provider resource. It now parks the
-- business's Twilio subaccount the same way, read out before the cascade deletes communication_twilio_accounts.
-- The closure worker closes it with the parent credential (Twilio Subaccounts docs: closing releases every
-- number, cannot be undone, and Twilio deletes the subaccount's data 30 days later). The subaccount SID is an
-- opaque provider identifier, cleared from the receipt once Twilio confirms.

create or replace function public.apply_organization_purge(
	target_organization_id uuid,
	purge_trigger_kind text,
	actor_owner_email text default null
)
returns jsonb
language plpgsql
set search_path to ''
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

	-- SES is found from the organization id; Twilio by the subaccount SID, which the cascade below deletes.
	select coalesce(jsonb_agg(resources.resource), '[]'::jsonb)
	into provider_resources
	from (
		select jsonb_build_object('kind', 'ses_organization', 'provider_id', target_organization_id::text) as resource
		where exists (
			select 1 from public.communication_email_domains
			where organization_id = target_organization_id
		)
		union all
		select jsonb_build_object('kind', 'twilio_subaccount', 'provider_id', accounts.subaccount_sid)
		from public.communication_twilio_accounts accounts
		where accounts.organization_id = target_organization_id
	) resources;

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

comment on column public.organization_deletion_receipts.pending_provider_resources is
	'Transient retry anchor for provider cleanup that has not finished: a jsonb array of {kind, provider_id} with '
	'only opaque ids -- ses_organization (the organization id) or twilio_subaccount (the subaccount SID), never a '
	'domain name, sender address or phone number. Holds only the resources still failing; null once all succeed.';
