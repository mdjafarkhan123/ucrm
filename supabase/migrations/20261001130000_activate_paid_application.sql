-- Package builder P10: activating a paid application on the new package system.
--
-- Confirming the initial payment records a receipt on the application: date received, USD amount, method,
-- private reference, and an optional note. It must reach the agreed first-period price, because a partial
-- payment leaves that period unpaid and an organization is activated only after its initial payment is
-- confirmed; anything above it becomes credit. Activation is one transaction: the organization, its owner,
-- an agreement on the edition and billing the application carries, the first charge, the receipt applied
-- to it, and coverage confirmed for exactly the dates Jafar reviewed. Coverage starts on the organization's
-- local activation day. The agreement may name an edition superseded after the application was submitted:
-- the customer agreed to those frozen terms. A wrong package is corrected, with a reason, to any published
-- edition before payment is confirmed or after it is reversed.

-- ---------------------------------------------------------------------------------------------------
-- 1. The receipt fields on an application's payment confirmation.
-- ---------------------------------------------------------------------------------------------------

alter table public.platform_onboarding_application_payment_confirmations
	add column received_on date,
	add column method text check (method is null or char_length(trim(method)) between 1 and 80),
	add column note text check (note is null or char_length(trim(note)) between 1 and 1000);

-- ---------------------------------------------------------------------------------------------------
-- 2. Activation may agree to the superseded edition an application was submitted on.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.validate_organization_package_agreement()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	if tg_op = 'UPDATE' then
		-- The one allowed change: cancelling a move that has not started yet.
		if old.cancelled_at is null and new.cancelled_at is not null and old.effective_from > now()
			and (to_jsonb(new) - array['cancelled_at', 'cancel_reason', 'cancelled_by_email', 'cancel_idempotency_key'])
				= (to_jsonb(old) - array['cancelled_at', 'cancel_reason', 'cancelled_by_email', 'cancel_idempotency_key']) then
			return new;
		end if;
		raise exception 'A package agreement cannot be changed. Record a new agreement instead.'
			using errcode = 'check_violation';
	end if;
	if not exists (
		select 1 from public.package_editions e
		where e.id = new.edition_id
			and (e.status = 'published' or (e.status = 'superseded' and new.source = 'activation'))
	) then
		raise exception 'An organization can only agree to a published package edition.'
			using errcode = 'check_violation';
	end if;
	return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 3. Helpers.
-- ---------------------------------------------------------------------------------------------------

-- The frozen terms an application keeps for one edition and billing interval (P9's snapshot shape).
create or replace function private.onboarding_package_snapshot(target_edition_id uuid, target_billing_interval text)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
	edition record;
	agreed_price integer;
begin
	select e.id, e.edition_number, e.name, e.promise, e.highlights, e.included_services, e.exclusions,
		e.monthly_price_usd_cents, e.yearly_price_usd_cents, p.slug
	into edition
	from public.package_editions as e
	join public.packages as p on p.id = e.package_id
	where e.id = target_edition_id;

	if not found then
		return null;
	end if;

	agreed_price := case target_billing_interval
		when 'month' then edition.monthly_price_usd_cents
		when 'year' then edition.yearly_price_usd_cents
	end;

	return jsonb_build_object(
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
		'billing_period', target_billing_interval,
		'monthly_price_usd_cents', edition.monthly_price_usd_cents,
		'yearly_price_usd_cents', edition.yearly_price_usd_cents,
		'capabilities', coalesce((
			select jsonb_agg(jsonb_build_object('key', c.capability_key, 'label', pc.label) order by pc.sort_order)
			from public.package_edition_capabilities as c
			join public.package_capabilities as pc on pc.capability_key = c.capability_key
			where c.edition_id = edition.id
		), '[]'::jsonb),
		'allowances', coalesce((
			select jsonb_agg(jsonb_build_object(
				'key', a.allowance_key, 'label', pa.label, 'state', a.allowance_state, 'value', a.allowance_value,
				'unit', pa.unit, 'resets_monthly', pa.resets_monthly
			) order by pa.sort_order)
			from public.package_edition_allowances as a
			join public.package_allowances as pa on pa.allowance_key = a.allowance_key
			where a.edition_id = edition.id and a.allowance_state <> 'not_included'
		), '[]'::jsonb)
	);
end;
$$;

-- Today in an application's time zone, falling back to UTC exactly as the organization's commercial
-- settings will when activation imports it.
create or replace function private.onboarding_application_today(target_time_zone text)
returns date
language sql
stable
set search_path = ''
as $$
	select (now() at time zone coalesce(
		(select z.name from pg_catalog.pg_timezone_names z where z.name = nullif(trim(coalesce(target_time_zone, '')), '')),
		'UTC'
	))::date;
$$;

-- The latest payment confirmation that has not been reversed, or nothing.
create or replace function private.onboarding_application_current_payment(target_application_id uuid)
returns public.platform_onboarding_application_payment_confirmations
language sql
stable
set search_path = ''
as $$
	select c.*
	from public.platform_onboarding_application_payment_confirmations c
	where c.application_id = target_application_id
		and not exists (
			select 1 from public.platform_onboarding_application_payment_reversals r where r.confirmation_id = c.id
		)
	order by c.confirmed_at desc
	limit 1;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 4. Submission uses the shared snapshot. Behavior is unchanged from P9.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.submit_onboarding_application(
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

	select e.status, p.visibility, p.archived_at
	into edition
	from public.package_editions as e
	join public.packages as p on p.id = e.package_id
	where e.id = target_package_edition_id;

	if not found then
		raise exception 'The selected package no longer exists.' using errcode = 'foreign_key_violation';
	end if;

	package_snapshot := private.onboarding_package_snapshot(target_package_edition_id, target_billing_interval);

	if edition.status <> 'published' or edition.visibility <> 'public' or edition.archived_at is not null
		or package_snapshot ->> 'price_usd_cents' is null then
		raise exception 'The selected package is no longer available.' using errcode = 'check_violation';
	end if;

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

-- ---------------------------------------------------------------------------------------------------
-- 5. Owner commands.
-- ---------------------------------------------------------------------------------------------------

-- Records the initial payment Jafar confirms was received offsite.
create or replace function public.confirm_onboarding_application_payment(
	target_application_id uuid,
	actor_email text,
	received_on date,
	amount_usd_cents integer,
	method text,
	private_reference text,
	note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
	app record;
	agreed_price integer;
	inserted_id uuid;
begin
	select a.stage, a.time_zone, a.package_snapshot
	into app
	from public.platform_onboarding_applications a
	where a.id = target_application_id
	for update;

	if not found then
		raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
	end if;
	if app.stage not in ('new', 'awaiting_payment', 'needs_attention') then
		raise exception 'This application can no longer be confirmed for payment.' using errcode = 'check_violation';
	end if;
	if (private.onboarding_application_current_payment(target_application_id)).id is not null then
		raise exception 'This application already has a confirmed payment.' using errcode = 'check_violation';
	end if;
	if received_on is null or received_on > private.onboarding_application_today(app.time_zone) then
		raise exception 'The date received cannot be in the future.' using errcode = 'check_violation';
	end if;

	agreed_price := (app.package_snapshot ->> 'price_usd_cents')::integer;
	if agreed_price is not null and amount_usd_cents < agreed_price then
		raise exception 'The payment is less than the agreed first payment of % cents. Record it once the full amount has arrived.', agreed_price
			using errcode = 'check_violation';
	end if;

	insert into public.platform_onboarding_application_payment_confirmations (
		application_id, actor_owner_email, amount_usd_cents, private_reference, received_on, method, note
	) values (
		target_application_id, actor_email, amount_usd_cents, trim(private_reference), received_on, trim(method),
		nullif(trim(coalesce(note, '')), '')
	)
	returning id into inserted_id;

	update public.platform_onboarding_applications
	set stage = 'payment_confirmed', payment_reversed_at = null
	where id = target_application_id;

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, after_state
	) values (
		actor_email, 'onboarding_application.payment_confirmed', 'onboarding_application',
		target_application_id::text,
		jsonb_build_object('amount_usd_cents', amount_usd_cents, 'received_on', received_on, 'method', trim(method))
	);

	return inserted_id;
end;
$$;

-- Moves an application to another published edition or billing interval, with a reason.
create or replace function public.correct_onboarding_application_package(
	target_application_id uuid,
	actor_email text,
	new_edition_id uuid,
	new_billing_interval text,
	correction_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	app record;
	edition record;
	new_snapshot jsonb;
	before_state jsonb;
	after_state jsonb;
begin
	select a.stage, a.package_edition_id, a.billing_interval, a.package_snapshot
	into app
	from public.platform_onboarding_applications a
	where a.id = target_application_id
	for update;

	if not found then
		raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
	end if;
	if app.stage not in ('new', 'awaiting_payment', 'needs_attention') then
		raise exception 'This application can no longer be corrected.' using errcode = 'check_violation';
	end if;
	if (private.onboarding_application_current_payment(target_application_id)).id is not null then
		raise exception 'The package can no longer be changed after payment is confirmed. Reverse the payment first.'
			using errcode = 'check_violation';
	end if;
	if new_billing_interval not in ('month', 'year') then
		raise exception 'Choose monthly or yearly billing.' using errcode = 'check_violation';
	end if;
	if new_edition_id = app.package_edition_id and new_billing_interval = app.billing_interval then
		raise exception 'Choose a different package or billing to change.' using errcode = 'check_violation';
	end if;

	select e.status, p.archived_at
	into edition
	from public.package_editions e
	join public.packages p on p.id = e.package_id
	where e.id = new_edition_id;

	if not found then
		raise exception 'The selected package no longer exists.' using errcode = 'foreign_key_violation';
	end if;
	if edition.status <> 'published' or edition.archived_at is not null then
		raise exception 'The selected package is not available.' using errcode = 'check_violation';
	end if;

	new_snapshot := private.onboarding_package_snapshot(new_edition_id, new_billing_interval);
	if new_snapshot ->> 'price_usd_cents' is null then
		raise exception 'The selected package has no % price. Choose the other billing.',
			case new_billing_interval when 'year' then 'yearly' else 'monthly' end
			using errcode = 'check_violation';
	end if;

	before_state := jsonb_build_object(
		'package_edition_id', app.package_edition_id,
		'billing_interval', app.billing_interval,
		'package_snapshot', app.package_snapshot
	);
	after_state := jsonb_build_object(
		'package_edition_id', new_edition_id,
		'billing_interval', new_billing_interval,
		'package_snapshot', new_snapshot
	);

	update public.platform_onboarding_applications
	set package_edition_id = new_edition_id,
		billing_interval = new_billing_interval,
		package_snapshot = new_snapshot
	where id = target_application_id;

	insert into public.platform_onboarding_application_corrections (
		application_id, actor_owner_email, reason, before_state, after_state
	) values (
		target_application_id, actor_email, correction_reason, before_state, after_state
	);

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, before_state, after_state
	) values (
		actor_email, 'onboarding_application.package_corrected', 'onboarding_application',
		target_application_id::text, before_state, after_state || jsonb_build_object('reason', correction_reason)
	);
end;
$$;

-- What activation will record, for Jafar to review. `problems` lists what stops it now.
create or replace function public.owner_onboarding_activation_preview(target_application_id uuid)
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

	if app.stage not in ('payment_confirmed', 'needs_attention') then
		problems := problems || 'Confirm the initial payment first.';
	elsif payment.id is null then
		problems := problems || 'The payment was reversed. Confirm the payment again first.';
	end if;
	if agreed_price is null then
		problems := problems || 'The application has no agreed price. Correct its package first.';
	elsif payment.id is not null and payment.amount_usd_cents < agreed_price then
		problems := problems || 'The confirmed payment is less than the agreed first payment.';
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
			else greatest(payment.amount_usd_cents - agreed_price, 0) end,
		'time_zone', app.time_zone,
		'covered_from', covered_from,
		'covered_through', covered_through,
		'next_renewal', covered_through + 1,
		'problems', to_jsonb(problems)
	);
end;
$$;

-- Creates the organization, its owner, agreement, first charge, payment, and coverage in one step.
-- expected_covered_from and expected_covered_through are the dates Jafar reviewed; a mismatch (the day
-- changed since the preview) refuses with P0409 so he reviews again.
create or replace function public.provision_organization_from_application(
	target_application_id uuid,
	target_organization_id uuid,
	target_organization_name text,
	target_slug text,
	target_administrator_user_id uuid,
	target_actor_owner_email text,
	expected_covered_from date,
	expected_covered_through date
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

	agreed_price := (app.package_snapshot ->> 'price_usd_cents')::integer;
	if agreed_price is null then
		raise exception 'The application has no agreed price. Correct its package first.' using errcode = 'check_violation';
	end if;
	if payment.amount_usd_cents < agreed_price then
		raise exception 'The confirmed payment is less than the agreed first payment.' using errcode = 'check_violation';
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

	insert into public.organization_package_agreements (
		organization_id, edition_id, billing_interval, agreed_price_usd_cents, service_anchor_date,
		effective_from, source, reason, actor_owner_email, idempotency_key
	) values (
		target_organization_id, app.package_edition_id, app.billing_interval, agreed_price, today,
		now(), 'activation', 'Activated from a paid onboarding application.', target_actor_owner_email,
		key_prefix || ':agreement'
	)
	returning id into agreement_id;

	charge := private.add_organization_billing_charge(
		target_organization_id, today, target_actor_owner_email, key_prefix || ':first-charge'
	);

	receipt_result := public.record_organization_billing_receipt(
		target_organization_id => target_organization_id,
		received_on => least(payment.received_on, today),
		amount_usd_cents => payment.amount_usd_cents,
		method => coalesce(payment.method, 'Recorded before activation'),
		private_reference => payment.private_reference,
		actor_owner_email => target_actor_owner_email,
		idempotency_key => key_prefix || ':initial-payment',
		note => payment.note,
		applications => case when agreed_price > 0
			then jsonb_build_array(jsonb_build_object('charge_id', charge.id, 'amount_usd_cents', agreed_price))
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
			'covered_through', charge.period_end
		)
	);

	return jsonb_build_object(
		'organization_id', target_organization_id,
		'agreement_id', agreement_id,
		'charge_id', charge.id,
		'receipt_id', receipt_result ->> 'receipt_id',
		'paid_through_date', coverage_result ->> 'paid_through_date'
	);
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 6. Only the owner service role runs the commands and the reader.
-- ---------------------------------------------------------------------------------------------------

revoke all on function private.onboarding_package_snapshot(uuid, text) from public, anon, authenticated;
revoke all on function private.onboarding_application_today(text) from public, anon, authenticated;
revoke all on function private.onboarding_application_current_payment(uuid) from public, anon, authenticated;

revoke all on function public.confirm_onboarding_application_payment(uuid, text, date, integer, text, text, text)
	from public, anon, authenticated;
grant execute on function public.confirm_onboarding_application_payment(uuid, text, date, integer, text, text, text)
	to service_role;

revoke all on function public.correct_onboarding_application_package(uuid, text, uuid, text, text)
	from public, anon, authenticated;
grant execute on function public.correct_onboarding_application_package(uuid, text, uuid, text, text)
	to service_role;

revoke all on function public.owner_onboarding_activation_preview(uuid) from public, anon, authenticated;
grant execute on function public.owner_onboarding_activation_preview(uuid) to service_role;

revoke all on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, date, date)
	from public, anon, authenticated;
grant execute on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, date, date)
	to service_role;
