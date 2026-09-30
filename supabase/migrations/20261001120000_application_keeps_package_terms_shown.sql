-- Package builder P9: an application keeps exactly what the visitor was shown. The published edition is
-- already frozen; the snapshot now also carries its app features, limits, and both prices, with the labels
-- shown at the time, so a later rename of a capability or allowance cannot change what they agreed to.

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
	-- existing snapshot shape; the rest freezes the customer-facing edition terms, including the app
	-- features and limits the visitor read on the details page, with the labels they read.
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
