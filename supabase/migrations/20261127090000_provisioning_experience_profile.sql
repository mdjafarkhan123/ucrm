-- Multi-industry platform foundation B4: Safe provisioning.
--
-- A paid Application becomes an Organization only when Uplift has confirmed what kind of business it is and
-- its agreed package is sold to that experience. Activation copies the confirmed decision onto the new
-- Organization as its first experience profile, in the same step that creates it, so an Organization never
-- exists without one.
--
-- 1. Applications paid before B3 asked the kind of business have no decision. Uplift may now record one
--    after payment, up until the account is created.
-- 2. One function names what stops activation, shared by the preview and the activation itself.
-- 3. The activation preview lists that problem; activation refuses it and records the profile.

-- ---------------------------------------------------------------------------------------------------
-- 1. Deciding the kind of business until the account is created
-- ---------------------------------------------------------------------------------------------------

create or replace function public.record_onboarding_application_qualification(
	target_application_id uuid,
	actor_email text,
	target_outcome text,
	target_experience_key text,
	target_business_type_key text,
	target_reviewed_work text,
	target_buyer_message text,
	target_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	app_stage text;
	offered_version integer;
	inserted_id uuid;
begin
	select a.stage into app_stage
	from public.platform_onboarding_applications a
	where a.id = target_application_id
	for update;

	if not found then
		raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
	end if;
	-- B4: a paid Application can still be decided while its account waits to be created; activation then
	-- needs a supported decision whose experience the paid package is sold to.
	if app_stage not in ('new', 'awaiting_payment', 'payment_confirmed', 'needs_attention') then
		raise exception 'The kind of business can only be decided before the account is created.'
			using errcode = 'check_violation';
	end if;

	if target_outcome = 'supported' then
		select d.version into offered_version
		from private.offered_experience_definitions() d
		where d.experience_key = target_experience_key;
		if offered_version is null then
			raise exception 'Uplift does not offer that kind of business yet.' using errcode = 'check_violation';
		end if;
		if not exists (
			select 1 from public.industry_experience_business_types t
			where t.experience_key = target_experience_key
				and t.definition_version = offered_version
				and t.business_type_key = target_business_type_key
		) then
			raise exception 'Choose one of the listed business types.' using errcode = 'check_violation';
		end if;
	elsif target_outcome <> 'holding' then
		raise exception 'Choose whether the business is supported or still being checked.'
			using errcode = 'check_violation';
	end if;

	insert into public.platform_onboarding_application_qualifications (
		application_id, outcome, experience_key, definition_version, business_type_key, reviewed_work,
		buyer_message, reason, actor_owner_email
	) values (
		target_application_id, target_outcome,
		case when target_outcome = 'supported' then target_experience_key end,
		offered_version,
		case when target_outcome = 'supported' then target_business_type_key end,
		case when target_outcome = 'supported' then trim(target_reviewed_work) end,
		case when target_outcome = 'holding' then trim(target_buyer_message) end,
		trim(target_reason), actor_email
	)
	returning id into inserted_id;

	-- Holding an Application that was already asked to pay takes the request back: the buyer's page returns
	-- to "we're checking" and payment cannot be recorded until Uplift confirms it again.
	if target_outcome = 'holding' and app_stage = 'awaiting_payment' then
		update public.platform_onboarding_applications set stage = 'new' where id = target_application_id;
	end if;

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, after_state
	) values (
		actor_email,
		case target_outcome when 'supported' then 'onboarding_application.qualified'
			else 'onboarding_application.held' end,
		'onboarding_application', target_application_id::text,
		jsonb_build_object(
			'outcome', target_outcome, 'experience_key', target_experience_key,
			'definition_version', offered_version, 'business_type_key', target_business_type_key,
			'reason', trim(target_reason))
	);

	return inserted_id;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 2. What stops activation
-- ---------------------------------------------------------------------------------------------------

-- Null when the Application's newest decision is supported and its package is sold to that experience.
create or replace function private.onboarding_application_activation_problem(target_application_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
	decision public.platform_onboarding_application_qualifications;
	edition_keys text[];
begin
	decision := private.onboarding_application_qualification(target_application_id);
	if decision.id is null then
		return 'Confirm what kind of business this is before activating the account.';
	end if;
	if decision.outcome <> 'supported' then
		return 'This Application is on hold while Uplift checks a missing fact. Confirm the kind of business before activating the account.';
	end if;

	select e.experience_keys into edition_keys
	from public.platform_onboarding_applications a
	join public.package_editions e on e.id = a.package_edition_id
	where a.id = target_application_id;

	if edition_keys is null then
		return 'The Application has no package. Correct its package first.';
	end if;
	if not decision.experience_key = any (edition_keys) then
		return 'The package they paid for is not sold to ' || private.experience_names(array[decision.experience_key])
			|| ' businesses. Reverse the payment and change the package first.';
	end if;
	return null;
end;
$$;

revoke all on function private.onboarding_application_activation_problem(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 3. Preview and activation
-- ---------------------------------------------------------------------------------------------------

create or replace function public.owner_onboarding_activation_preview(
	target_application_id uuid,
	offer_decision text default null::text,
	offer_code text default null::text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	app record;
	edition record;
	payment public.platform_onboarding_application_payment_confirmations;
	agreed_price integer;
	covered_from date;
	covered_through date;
	problems text[] := array[]::text[];
	offer jsonb;
	terms jsonb;
	first_charge integer;
	experience_problem text;
begin
	select a.stage, a.time_zone, a.package_edition_id, a.billing_interval, a.package_snapshot, a.payment_reversed_at
	into app
	from public.platform_onboarding_applications a
	where a.id = target_application_id;

	if not found then
		return null;
	end if;

	select e.status, e.edition_number, e.name, p.archived_at
	into edition
	from public.package_editions e
	join public.packages p on p.id = e.package_id
	where e.id = app.package_edition_id;

	payment := private.onboarding_application_current_payment(target_application_id);
	agreed_price := (app.package_snapshot ->> 'price_usd_cents')::integer;
	covered_from := private.onboarding_application_today(app.time_zone);
	covered_through := private.billing_period_end(covered_from, covered_from, app.billing_interval);
	offer := private.onboarding_activation_offer(target_application_id, offer_decision, offer_code);
	if jsonb_typeof(offer -> 'offer') = 'object' and agreed_price is not null then
		terms := private.package_offer_terms(offer -> 'offer', agreed_price, app.billing_interval, covered_from, covered_from);
	end if;
	first_charge := private.agreement_period_price(agreed_price, terms, covered_from);

	if app.stage not in ('payment_confirmed', 'needs_attention') then
		problems := problems || 'Confirm the initial payment first.';
	elsif payment.id is null then
		problems := problems || 'The payment was reversed. Confirm the payment again first.';
	end if;
	experience_problem := private.onboarding_application_activation_problem(target_application_id);
	if experience_problem is not null then
		problems := problems || experience_problem;
	end if;
	if agreed_price is null then
		problems := problems || 'The application has no agreed price. Correct its package first.';
	elsif payment.id is not null and payment.amount_usd_cents < first_charge then
		problems := problems || 'The confirmed payment is less than the first charge.';
	end if;
	if (offer ->> 'blocking')::boolean then
		problems := problems || case when offer ->> 'source' = 'shown'
			then 'The offer they were shown is no longer available: ' || (offer -> 'problems' -> 0 ->> 'message')
				|| ' Honor it or activate at the normal price.'
			else offer -> 'problems' -> 0 ->> 'message' end;
	end if;
	if edition.status is null or edition.status = 'draft' then
		problems := problems || 'The application''s package edition was never published. Correct its package first.';
	end if;

	return jsonb_build_object(
		'edition_id', app.package_edition_id,
		'edition_name', coalesce(edition.name, app.package_snapshot ->> 'display_name'),
		'edition_number', edition.edition_number,
		'edition_superseded', edition.status = 'superseded',
		'package_archived', edition.archived_at is not null,
		'billing_interval', app.billing_interval,
		'agreed_price_usd_cents', agreed_price,
		'payment', case when payment.id is null then null else jsonb_build_object(
			'id', payment.id,
			'received_on', payment.received_on,
			'amount_usd_cents', payment.amount_usd_cents,
			'method', payment.method,
			'private_reference', payment.private_reference
		) end,
		'credit_usd_cents', case when payment.id is null or agreed_price is null then null
			else greatest(payment.amount_usd_cents - first_charge, 0) end,
		'first_charge_usd_cents', first_charge,
		'offer', offer || jsonb_build_object('terms', terms),
		'time_zone', app.time_zone,
		'covered_from', covered_from,
		'covered_through', covered_through,
		'next_renewal', covered_through + 1,
		'problems', to_jsonb(problems)
	);
end;
$$;

create or replace function public.provision_organization_from_application(
	target_application_id uuid,
	target_organization_id uuid,
	target_organization_name text,
	target_slug text,
	target_administrator_user_id uuid,
	target_actor_owner_email text,
	expected_covered_from date,
	expected_covered_through date,
	offer_decision text default null::text,
	offer_code text default null::text,
	expected_first_charge_usd_cents integer default null::integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	app record;
	payment public.platform_onboarding_application_payment_confirmations;
	agreed_price integer;
	today date;
	agreement_id uuid;
	charge public.organization_billing_charges;
	receipt_result jsonb;
	coverage_result jsonb;
	key_prefix text := 'application:' || target_application_id::text;
	offer jsonb;
	terms jsonb;
	claim_id uuid;
	experience_problem text;
	decision public.platform_onboarding_application_qualifications;
	profile_result jsonb;
begin
	if target_organization_name is null or char_length(trim(target_organization_name)) = 0 then
		raise exception 'An organization name is required for provisioning.' using errcode = 'check_violation';
	end if;
	if target_slug is null or char_length(trim(target_slug)) = 0 then
		raise exception 'An organization slug is required for provisioning.' using errcode = 'check_violation';
	end if;
	if target_actor_owner_email is null or char_length(trim(target_actor_owner_email)) = 0 then
		raise exception 'An acting owner email is required for provisioning.' using errcode = 'check_violation';
	end if;

	select a.stage, a.time_zone, a.package_edition_id, a.billing_interval, a.package_snapshot
	into app
	from public.platform_onboarding_applications a
	where a.id = target_application_id
	for update;

	if not found then
		raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
	end if;
	if app.stage not in ('payment_confirmed', 'needs_attention') then
		raise exception 'This application is not ready for provisioning.' using errcode = 'check_violation';
	end if;

	payment := private.onboarding_application_current_payment(target_application_id);
	if payment.id is null then
		raise exception 'Payment must be confirmed before provisioning.' using errcode = 'check_violation';
	end if;

	-- B4: the kind of business is confirmed and the paid package is sold to it. The Application row lock
	-- above keeps a new decision from landing between this check and the profile copied below.
	experience_problem := private.onboarding_application_activation_problem(target_application_id);
	if experience_problem is not null then
		raise exception '%', experience_problem using errcode = 'check_violation';
	end if;
	decision := private.onboarding_application_qualification(target_application_id);

	agreed_price := (app.package_snapshot ->> 'price_usd_cents')::integer;
	if agreed_price is null then
		raise exception 'The application has no agreed price. Correct its package first.' using errcode = 'check_violation';
	end if;

	-- Claims of one offer run one at a time, so its cap holds.
	perform 1 from public.package_offers o
	where o.id = (app.package_snapshot -> 'offer' ->> 'id')::uuid
		or o.code = upper(trim(coalesce(offer_code, '')))
	for update;
	offer := private.onboarding_activation_offer(target_application_id, offer_decision, offer_code);
	if (offer ->> 'blocking')::boolean then
		raise exception '%', case when offer ->> 'source' = 'shown'
			then 'The offer they were shown is no longer available: ' || (offer -> 'problems' -> 0 ->> 'message')
				|| ' Honor it or activate at the normal price.'
			else offer -> 'problems' -> 0 ->> 'message' end
			using errcode = 'check_violation';
	end if;

	insert into public.organizations (id, name, slug, lifecycle_status)
	values (target_organization_id, trim(target_organization_name), target_slug, 'active');

	update public.organization_settings
	set timezone = coalesce(nullif(trim(app.time_zone), ''), timezone)
	where organization_id = target_organization_id;

	insert into public.organization_members (organization_id, user_id, role)
	values (target_organization_id, target_administrator_user_id, 'owner');

	-- Creates the commercial rows (time zone imported from the settings above) and takes the money lock.
	perform private.lock_organization_billing(target_organization_id);
	today := private.organization_commercial_today(target_organization_id);

	if expected_covered_from is distinct from today
		or expected_covered_through is distinct from private.billing_period_end(today, today, app.billing_interval) then
		raise exception 'The dates to cover have changed since you reviewed them. Review them and try again.'
			using errcode = 'P0409';
	end if;

	if jsonb_typeof(offer -> 'offer') = 'object' then
		claim_id := gen_random_uuid();
		terms := private.package_offer_terms(offer -> 'offer', agreed_price, app.billing_interval, today, today)
			|| jsonb_build_object('claim_id', claim_id);
	end if;

	insert into public.organization_package_agreements (
		organization_id, edition_id, billing_interval, agreed_price_usd_cents, offer_terms, service_anchor_date,
		effective_from, source, reason, actor_owner_email, idempotency_key
	) values (
		target_organization_id, app.package_edition_id, app.billing_interval, agreed_price, terms, today,
		now(), 'activation', 'Activated from a paid onboarding application.', target_actor_owner_email,
		key_prefix || ':agreement'
	)
	returning id into agreement_id;

	-- B4: the Organization's first experience profile is Uplift's confirmed decision, tied to the Agreement
	-- just created. Its owner and reason are the person who confirmed it and why.
	profile_result := public.record_organization_experience_decision(
		target_organization_id => target_organization_id,
		target_experience_key => decision.experience_key,
		target_definition_version => decision.definition_version,
		target_business_type_key => decision.business_type_key,
		reviewed_service_shape => decision.reviewed_work,
		decision_reason => decision.reason,
		expected_previous_decision_id => null,
		idempotency_key => key_prefix || ':experience',
		actor_email => decision.actor_owner_email,
		decision_source => 'provisioning'
	);

	if claim_id is not null then
		insert into public.package_offer_claims (
			id, offer_id, organization_id, agreement_id, method, honored, actor_owner_email
		) values (
			claim_id, (terms ->> 'offer_id')::uuid, target_organization_id, agreement_id, offer ->> 'method',
			(offer ->> 'honored')::boolean, target_actor_owner_email
		);
	end if;

	charge := private.add_organization_billing_charge(
		target_organization_id, today, target_actor_owner_email, key_prefix || ':first-charge'
	);

	if expected_first_charge_usd_cents is not null and expected_first_charge_usd_cents <> charge.amount_usd_cents then
		raise exception 'The first charge has changed since you reviewed it. Review it and try again.' using errcode = 'P0409';
	end if;
	if payment.amount_usd_cents < charge.amount_usd_cents then
		raise exception 'The confirmed payment is less than the first charge.' using errcode = 'check_violation';
	end if;

	receipt_result := public.record_organization_billing_receipt(
		target_organization_id => target_organization_id,
		received_on => least(payment.received_on, today),
		amount_usd_cents => payment.amount_usd_cents,
		method => coalesce(payment.method, 'Recorded before activation'),
		private_reference => payment.private_reference,
		actor_owner_email => target_actor_owner_email,
		idempotency_key => key_prefix || ':initial-payment',
		note => payment.note,
		applications => case when charge.amount_usd_cents > 0
			then jsonb_build_array(jsonb_build_object('charge_id', charge.id, 'amount_usd_cents', charge.amount_usd_cents))
			else '[]'::jsonb end
	);

	coverage_result := public.confirm_organization_billing_coverage(
		target_organization_id, charge.id, charge.period_start, charge.period_end,
		target_actor_owner_email, key_prefix || ':first-coverage'
	);

	update public.platform_onboarding_applications
	set stage = 'account_created'
	where id = target_application_id;

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, after_state
	) values (
		target_actor_owner_email, 'onboarding_application.provisioned', 'organization',
		target_organization_id::text,
		jsonb_build_object(
			'application_id', target_application_id,
			'agreement_id', agreement_id,
			'covered_from', charge.period_start,
			'covered_through', charge.period_end,
			'offer_claim_id', claim_id,
			'experience_key', decision.experience_key,
			'business_type_key', decision.business_type_key,
			'experience_decision_id', profile_result ->> 'decision_id'
		)
	);

	return jsonb_build_object(
		'organization_id', target_organization_id,
		'agreement_id', agreement_id,
		'charge_id', charge.id,
		'receipt_id', receipt_result ->> 'receipt_id',
		'paid_through_date', coverage_result ->> 'paid_through_date',
		'experience_decision_id', profile_result ->> 'decision_id'
	);
end;
$$;
