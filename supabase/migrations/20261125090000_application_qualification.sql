-- Multi-industry platform foundation B3: One Application.
--
-- The shared Application records the work a buyer says it offers and the kind of business it proposes: a
-- Business type of an Industry experience Uplift sells to, "Something else" when none fits, or interest in
-- Medspa & clinic before that experience is offered. Uplift then confirms the experience and Business type,
-- or holds the Application while it checks a missing fact. Nothing asks for or records payment until the
-- newest decision is supported and the package is sold to the confirmed experience.
--
-- 1. An Application names its proposed kind of business. Every earlier Application was a Contractor one, so
--    it arrives proposing Contractor with no Business type (the old free-text trade stays as it was typed).
-- 2. An Application that does not fit a listed type skips the package: Uplift recommends one during review.
--    The package, billing and frozen terms are therefore present together or absent together.
-- 3. Uplift's qualification decisions are kept in order, never rewritten. The newest one counts.
-- 4. Asking for payment, recording payment and changing the package all check the decision and the fit.

-- ---------------------------------------------------------------------------------------------------
-- 1–2. What the buyer proposes
-- ---------------------------------------------------------------------------------------------------

alter table public.platform_onboarding_applications
	add column described_work text check (
		described_work is null or char_length(trim(described_work)) between 1 and 2000
	),
	add column proposed_experience_key text,
	add column proposed_definition_version integer,
	add column proposed_business_type_key text,
	add column proposed_other text check (proposed_other in ('something_else', 'medspa'));

update public.platform_onboarding_applications
set proposed_experience_key = 'contractor', proposed_definition_version = 1;

alter table public.platform_onboarding_applications
	alter column package_edition_id drop not null,
	alter column billing_interval drop not null,
	alter column package_snapshot drop not null,
	add constraint platform_onboarding_applications_proposal_check check (
		(proposed_other is null
			and proposed_experience_key is not null and proposed_definition_version is not null)
		or (proposed_other is not null
			and proposed_experience_key is null and proposed_definition_version is null
			and proposed_business_type_key is null)
	),
	add constraint platform_onboarding_applications_package_together_check check (
		(package_edition_id is null) = (billing_interval is null)
		and (package_edition_id is null) = (package_snapshot is null)
	),
	add constraint platform_onboarding_applications_listed_has_package_check check (
		package_edition_id is not null or proposed_other is not null
	),
	add constraint platform_onboarding_applications_proposed_definition_fkey
		foreign key (proposed_experience_key, proposed_definition_version)
		references public.industry_experience_definitions (experience_key, version),
	add constraint platform_onboarding_applications_proposed_business_type_fkey
		foreign key (proposed_experience_key, proposed_definition_version, proposed_business_type_key)
		references public.industry_experience_business_types (experience_key, definition_version, business_type_key);

comment on column public.platform_onboarding_applications.described_work is
	'The work the buyer says the business offers, in its own words. Uplift reviews it; it never decides the experience by itself.';
comment on column public.platform_onboarding_applications.proposed_other is
	'Set when the buyer chose no listed Business type: something_else, or medspa (interest before Medspa is offered). Such an Application has no package until Uplift recommends one.';

-- ---------------------------------------------------------------------------------------------------
-- 3. Uplift's qualification decisions
-- ---------------------------------------------------------------------------------------------------

create table public.platform_onboarding_application_qualifications (
	id uuid primary key default gen_random_uuid(),
	application_id uuid not null references public.platform_onboarding_applications (id),
	outcome text not null check (outcome in ('supported', 'holding')),
	experience_key text,
	definition_version integer,
	business_type_key text,
	reviewed_work text check (reviewed_work is null or char_length(trim(reviewed_work)) between 1 and 1000),
	buyer_message text check (buyer_message is null or char_length(trim(buyer_message)) between 1 and 500),
	reason text not null check (char_length(trim(reason)) between 1 and 1000),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	created_at timestamptz not null default clock_timestamp(),
	constraint onboarding_qualification_outcome_shape_check check (
		(outcome = 'supported' and experience_key is not null and definition_version is not null
			and business_type_key is not null and reviewed_work is not null and buyer_message is null)
		or (outcome = 'holding' and experience_key is null and definition_version is null
			and business_type_key is null and reviewed_work is null and buyer_message is not null)
	),
	constraint onboarding_qualification_business_type_fkey
		foreign key (experience_key, definition_version, business_type_key)
		references public.industry_experience_business_types (experience_key, definition_version, business_type_key)
);

comment on table public.platform_onboarding_application_qualifications is
	'Uplift''s decisions about which Industry experience and Business type an Application is, or what it is still checking. Append-only; the newest row counts.';
comment on column public.platform_onboarding_application_qualifications.buyer_message is
	'What Uplift is checking, in words the buyer reads on their status page. reason stays private to Uplift.';

create index platform_onboarding_application_qualifications_application_idx
	on public.platform_onboarding_application_qualifications (application_id, created_at desc);

create trigger platform_onboarding_application_qualifications_immutable
	before update or delete on public.platform_onboarding_application_qualifications
	for each row execute function private.prevent_platform_onboarding_history_mutation();

alter table public.platform_onboarding_application_qualifications enable row level security;
revoke all on public.platform_onboarding_application_qualifications from anon, authenticated;
grant all on public.platform_onboarding_application_qualifications to service_role;

create or replace function private.onboarding_application_qualification(target_application_id uuid)
returns public.platform_onboarding_application_qualifications
language sql
stable
set search_path = ''
as $$
	select q.*
	from public.platform_onboarding_application_qualifications q
	where q.application_id = target_application_id
	order by q.created_at desc, q.id desc
	limit 1;
$$;

-- Why payment cannot be asked for or recorded yet, or null when it can. The hint lets the app tell this
-- apart from any other refusal.
create or replace function private.assert_onboarding_application_sellable(target_application_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
	decision public.platform_onboarding_application_qualifications;
	edition_keys text[];
begin
	decision := private.onboarding_application_qualification(target_application_id);
	if decision.id is null or decision.outcome <> 'supported' then
		raise exception 'Confirm what kind of business this is before asking for payment.'
			using errcode = 'check_violation', hint = 'application_not_qualified';
	end if;

	select e.experience_keys into edition_keys
	from public.platform_onboarding_applications a
	join public.package_editions e on e.id = a.package_edition_id
	where a.id = target_application_id;

	if edition_keys is null then
		raise exception 'Choose a package for this business before asking for payment.'
			using errcode = 'check_violation', hint = 'application_not_qualified';
	end if;
	if not decision.experience_key = any (edition_keys) then
		raise exception 'The package is not sold to % businesses. Change the package before asking for payment.',
			private.experience_names(array[decision.experience_key])
			using errcode = 'check_violation', hint = 'application_not_qualified';
	end if;
end;
$$;

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
	if app_stage not in ('new', 'awaiting_payment', 'needs_attention')
		or (private.onboarding_application_current_payment(target_application_id)).id is not null then
		raise exception 'The kind of business can only be decided before payment is confirmed.'
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

revoke all on function public.record_onboarding_application_qualification(uuid, text, text, text, text, text, text, text)
	from public, anon, authenticated;
grant execute on function public.record_onboarding_application_qualification(uuid, text, text, text, text, text, text, text)
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 1–2. Submitting: the proposal, and a package only when it fits
-- ---------------------------------------------------------------------------------------------------

drop function public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb);

create function public.submit_onboarding_application(
	target_business_name text,
	target_main_contact_name text,
	target_main_contact_email text,
	target_main_contact_phone text,
	target_initial_administrator_name text,
	target_initial_administrator_email text,
	target_described_work text,
	target_proposed_experience_key text,
	target_proposed_business_type_key text,
	target_proposed_other text,
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
	proposed_version integer;
	trade_label text;
	package_snapshot jsonb;
	clean_business_name text;
	clean_contact_email text;
	clean_admin_email text;
	is_duplicate boolean;
	new_application_id uuid;
begin
	if target_proposed_other is not null then
		if target_proposed_other not in ('something_else', 'medspa') then
			raise exception 'Choose what kind of business you run.' using errcode = 'check_violation';
		end if;
		if target_package_edition_id is not null then
			raise exception 'Uplift recommends a package for this kind of business after review.'
				using errcode = 'check_violation';
		end if;
		trade_label := case target_proposed_other when 'medspa' then 'Medspa or clinic' else 'Something else' end;
	else
		select d.version into proposed_version
		from private.offered_experience_definitions() d
		where d.experience_key = target_proposed_experience_key;

		select t.label into trade_label
		from public.industry_experience_business_types t
		where t.experience_key = target_proposed_experience_key
			and t.definition_version = proposed_version
			and t.business_type_key = target_proposed_business_type_key;
		if trade_label is null then
			raise exception 'Choose what kind of business you run.' using errcode = 'invalid_parameter_value';
		end if;

		if target_billing_interval not in ('month', 'year') then
			raise exception 'Choose monthly or yearly billing.' using errcode = 'check_violation';
		end if;

		select e.status, e.experience_keys, p.visibility, p.archived_at
		into edition
		from public.package_editions as e
		join public.packages as p on p.id = e.package_id
		where e.id = target_package_edition_id;

		if not found then
			raise exception 'The selected package no longer exists.' using errcode = 'foreign_key_violation';
		end if;

		package_snapshot := private.onboarding_package_snapshot(target_package_edition_id, target_billing_interval);

		if edition.status <> 'published' or edition.visibility <> 'public' or edition.archived_at is not null
			or not target_proposed_experience_key = any (edition.experience_keys)
			or package_snapshot ->> 'price_usd_cents' is null then
			raise exception 'The selected package is no longer available.' using errcode = 'check_violation';
		end if;
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
		initial_administrator_name, initial_administrator_email, trade, described_work,
		proposed_experience_key, proposed_definition_version, proposed_business_type_key, proposed_other,
		city_country, time_zone, note, package_edition_id, billing_interval, package_snapshot, possible_duplicate
	) values (
		clean_business_name, trim(target_main_contact_name), clean_contact_email, trim(target_main_contact_phone),
		nullif(trim(coalesce(target_initial_administrator_name, '')), ''), clean_admin_email,
		trade_label, trim(target_described_work),
		case when target_proposed_other is null then target_proposed_experience_key end,
		proposed_version,
		case when target_proposed_other is null then target_proposed_business_type_key end,
		target_proposed_other,
		trim(target_city_country), trim(target_time_zone),
		nullif(trim(coalesce(target_note, '')), ''),
		case when target_proposed_other is null then target_package_edition_id end,
		case when target_proposed_other is null then target_billing_interval end,
		package_snapshot, is_duplicate
	)
	returning id into new_application_id;

	insert into public.platform_onboarding_application_submissions (
		application_id, submitted_data, package_snapshot, privacy_policy_version, agreement_accepted_at
	) values (
		new_application_id, target_submitted_data, coalesce(package_snapshot, '{}'::jsonb),
		target_privacy_policy_version, now()
	);

	return new_application_id;
end;
$$;

revoke all on function public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb)
	from public, anon, authenticated;
grant execute on function public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb)
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Asking for payment, recording it, and changing the package
-- ---------------------------------------------------------------------------------------------------

create or replace function public.mark_onboarding_application_reviewed(target_application_id uuid, actor_email text)
returns void
language plpgsql
-- Definer rights, like the payment and package commands, so it can read Uplift's decision helpers.
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  app_stage text;
begin
  select stage into app_stage
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage <> 'new' then
    raise exception 'Only a new application can be marked reviewed.' using errcode = 'check_violation';
  end if;

  perform private.assert_onboarding_application_sellable(target_application_id);

  update public.platform_onboarding_applications
  set stage = 'awaiting_payment'
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key
  ) values (
    actor_email, 'onboarding_application.reviewed', 'onboarding_application', target_application_id::text
  );
end;
$function$;

revoke all on function public.mark_onboarding_application_reviewed(uuid, text) from public, anon, authenticated;
grant execute on function public.mark_onboarding_application_reviewed(uuid, text) to service_role;

create or replace function public.confirm_onboarding_application_payment(target_application_id uuid, actor_email text, received_on date, amount_usd_cents integer, method text, private_reference text, note text default null::text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
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
	-- B3: money is only taken for a business Uplift has confirmed it serves, on a package sold to it.
	perform private.assert_onboarding_application_sellable(target_application_id);
	if received_on is null or received_on > private.onboarding_application_today(app.time_zone) then
		raise exception 'The date received cannot be in the future.' using errcode = 'check_violation';
	end if;

	agreed_price := coalesce((app.package_snapshot ->> 'first_payment_usd_cents')::integer,
		(app.package_snapshot ->> 'price_usd_cents')::integer);
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
$function$;

create or replace function public.correct_onboarding_application_package(target_application_id uuid, actor_email text, new_edition_id uuid, new_billing_interval text, correction_reason text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
	app record;
	decision public.platform_onboarding_application_qualifications;
	buyer_experience text;
	edition record;
	new_snapshot jsonb;
	before_state jsonb;
	after_state jsonb;
begin
	select a.stage, a.package_edition_id, a.billing_interval, a.package_snapshot, a.proposed_experience_key
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

	-- B3: the package must be sold to the experience Uplift confirmed, or, before that, the one the buyer
	-- proposed. A buyer who chose no listed type needs Uplift's decision first.
	decision := private.onboarding_application_qualification(target_application_id);
	buyer_experience := case when decision.outcome = 'supported' then decision.experience_key
		else app.proposed_experience_key end;
	if buyer_experience is null then
		raise exception 'Confirm what kind of business this is before choosing its package.'
			using errcode = 'check_violation';
	end if;

	select e.status, e.experience_keys, p.archived_at
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
	if not buyer_experience = any (edition.experience_keys) then
		raise exception 'This package is not available to % businesses. Choose a package made for them.',
			private.experience_names(array[buyer_experience])
			using errcode = 'check_violation';
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
$function$;
