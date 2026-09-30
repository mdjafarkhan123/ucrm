-- Package builder P11a: introductory offers.
--
-- An offer takes a percentage or a fixed USD amount off an edition's agreed price. On monthly billing it
-- lasts a set number of consecutive service periods; on yearly billing it covers the first year only. Jafar
-- chooses the eligible packages and billing, new or existing customers, the claim dates, an optional cap,
-- and whether the offer applies automatically or needs a code. A customer claims an offer when Jafar
-- activates them or confirms a package change, and that claim freezes the offer's terms onto the agreement,
-- so editing or archiving the offer later never changes what an existing customer agreed to. Every charge
-- whose service period starts inside the offer window is billed at the introductory price. Keeping an
-- offer through a package change is an explicit choice that keeps its original end date. Following Stripe's
-- coupons and promotion codes: a claim deadline stops new claims, not an existing customer's months.

-- ---------------------------------------------------------------------------------------------------
-- 1. Offers, the packages they apply to, and claims.
-- ---------------------------------------------------------------------------------------------------

create table public.package_offers (
	id uuid primary key default gen_random_uuid(),
	name text not null check (char_length(trim(name)) between 1 and 80),
	apply_mode text not null check (apply_mode in ('automatic', 'code')),
	-- Stored upper-case; customers may type it in any case.
	code text check (code is null or code ~ '^[A-Z0-9][A-Z0-9-]{2,31}$'),
	discount_kind text not null check (discount_kind in ('percent', 'fixed')),
	percent_off integer check (percent_off between 1 and 100),
	amount_off_usd_cents integer check (amount_off_usd_cents > 0),
	applies_to_monthly boolean not null,
	applies_to_yearly boolean not null,
	-- How many consecutive monthly periods are discounted. A yearly offer always covers the first year.
	monthly_periods integer check (monthly_periods between 1 and 36),
	customer_eligibility text not null check (customer_eligibility in ('new', 'existing', 'any')),
	claim_starts_at timestamptz not null,
	claim_ends_at timestamptz,
	redemption_cap integer check (redemption_cap > 0),
	archived_at timestamptz,
	revision integer not null default 1 check (revision > 0),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	check ((apply_mode = 'code') = (code is not null)),
	check ((discount_kind = 'percent' and percent_off is not null and amount_off_usd_cents is null)
		or (discount_kind = 'fixed' and amount_off_usd_cents is not null and percent_off is null)),
	check (applies_to_monthly or applies_to_yearly),
	check (applies_to_monthly = (monthly_periods is not null)),
	check (claim_ends_at is null or claim_ends_at > claim_starts_at)
);

create unique index package_offers_code_key on public.package_offers (code) where code is not null;

create table public.package_offer_packages (
	offer_id uuid not null references public.package_offers (id) on delete cascade,
	package_id uuid not null references public.packages (id) on delete cascade,
	primary key (offer_id, package_id)
);

create index package_offer_packages_package_idx on public.package_offer_packages (package_id);

-- One organization's claim of one offer. It stays in history; a claim made by a scheduled change that is
-- later cancelled is released and no longer counts toward the cap.
create table public.package_offer_claims (
	id uuid primary key default gen_random_uuid(),
	offer_id uuid not null references public.package_offers (id),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	agreement_id uuid not null unique references public.organization_package_agreements (id) on delete cascade,
	method text not null check (method in ('automatic', 'code')),
	-- Jafar honored an offer the customer was shown although it had since closed, filled, or been archived.
	honored boolean not null default false,
	released_at timestamptz,
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	created_at timestamptz not null default now()
);

create unique index package_offer_claims_one_active_per_organization
	on public.package_offer_claims (offer_id, organization_id) where released_at is null;
create index package_offer_claims_organization_idx on public.package_offer_claims (organization_id);

create or replace function private.prevent_package_offer_claim_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	if tg_op = 'UPDATE' and old.released_at is null and new.released_at is not null
		and (to_jsonb(new) - 'released_at') = (to_jsonb(old) - 'released_at') then
		return new;
	end if;
	raise exception 'An offer claim stays in history. It can only be released by cancelling its change.'
		using errcode = 'check_violation';
end;
$$;

create trigger package_offer_claims_append_only
	before update or delete on public.package_offer_claims
	for each row execute function private.prevent_package_offer_claim_change();

-- Cancelling a scheduled change releases the offer it claimed.
create or replace function private.release_offer_claim_of_cancelled_agreement()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	update public.package_offer_claims c
	set released_at = now()
	where c.agreement_id = new.id and c.released_at is null;
	return new;
end;
$$;

create trigger organization_package_agreements_release_offer_claim
	after update of cancelled_at on public.organization_package_agreements
	for each row when (old.cancelled_at is null and new.cancelled_at is not null)
	execute function private.release_offer_claim_of_cancelled_agreement();

alter table public.package_offers enable row level security;
alter table public.package_offer_packages enable row level security;
alter table public.package_offer_claims enable row level security;

revoke all on public.package_offers, public.package_offer_packages, public.package_offer_claims
	from public, anon, authenticated;
grant select, insert, update, delete on public.package_offers, public.package_offer_packages,
	public.package_offer_claims to service_role;

revoke all on function private.prevent_package_offer_claim_change() from public, anon, authenticated;
revoke all on function private.release_offer_claim_of_cancelled_agreement() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 2. Offer arithmetic.
-- ---------------------------------------------------------------------------------------------------

-- The introductory price for one normal price. `source` carries discount_kind, percent_off, and
-- amount_off_usd_cents, from an offer row or from frozen terms.
create or replace function private.package_offer_intro_price(source jsonb, normal_price integer)
returns integer
language sql
immutable
set search_path = ''
as $$
	select case
		when normal_price is null then null
		when source ->> 'discount_kind' = 'percent'
			then normal_price - round(normal_price * (source ->> 'percent_off')::numeric / 100)::integer
		else greatest(normal_price - (source ->> 'amount_off_usd_cents')::integer, 0)
	end;
$$;

-- The first day after the offer window: `periods` service periods on from the one starting on starts_on,
-- counted from the charge anchor so a window starting on the 31st does not drift.
create or replace function private.package_offer_window_end(anchor date, starts_on date, billing_interval text, periods integer)
returns date
language sql
immutable
set search_path = ''
as $$
	select (anchor + (max(n) + periods) * case billing_interval when 'year' then interval '1 year' else interval '1 month' end)::date
	from generate_series(0, 1200) as n
	where (anchor + n * case billing_interval when 'year' then interval '1 year' else interval '1 month' end)::date <= starts_on;
$$;

-- The terms frozen onto an agreement. `source` is an offer row as JSON, or the offer an application showed.
create or replace function private.package_offer_terms(
	source jsonb,
	normal_price integer,
	billing_interval text,
	anchor date,
	starts_on date
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
	select jsonb_build_object(
		'offer_id', source -> 'id',
		'name', source ->> 'name',
		'code', source ->> 'code',
		'discount_kind', source ->> 'discount_kind',
		'percent_off', (source ->> 'percent_off')::integer,
		'amount_off_usd_cents', (source ->> 'amount_off_usd_cents')::integer,
		'billing_interval', billing_interval,
		'periods', case billing_interval when 'year' then 1 else (source ->> 'monthly_periods')::integer end,
		'starts_on', starts_on,
		'ends_before', private.package_offer_window_end(anchor, starts_on, billing_interval,
			case billing_interval when 'year' then 1 else (source ->> 'monthly_periods')::integer end),
		'normal_price_usd_cents', normal_price,
		'intro_price_usd_cents', private.package_offer_intro_price(source, normal_price)
	);
$$;

-- What a service period starting on period_start costs under an agreement's price and offer terms.
create or replace function private.agreement_period_price(agreed_price integer, offer_terms jsonb, period_start date)
returns integer
language sql
immutable
set search_path = ''
as $$
	select case
		when offer_terms is not null
			and period_start >= (offer_terms ->> 'starts_on')::date
			and period_start < (offer_terms ->> 'ends_before')::date
		then private.package_offer_intro_price(offer_terms, agreed_price)
		else agreed_price
	end;
$$;

-- Active claims toward an offer's cap.
create or replace function private.package_offer_claim_count(target_offer_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
	select count(*)::integer from public.package_offer_claims c
	where c.offer_id = target_offer_id and c.released_at is null;
$$;

-- Why an offer cannot be claimed now for this package and billing; empty when it can. A null organization
-- is a new customer. `availability` problems (archived, not open, closed, full) are the ones Jafar may
-- honor at activation for an offer the customer was shown.
create or replace function private.package_offer_problems(
	target_offer public.package_offers,
	target_organization_id uuid,
	target_package_id uuid,
	target_billing_interval text
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
	problems jsonb := '[]'::jsonb;
	claims integer;
	package_name text;
begin
	if target_offer.archived_at is not null then
		problems := problems || jsonb_build_object('code', 'archived', 'availability', true,
			'message', 'The offer "' || target_offer.name || '" has been archived.');
	end if;
	if target_offer.claim_starts_at > now() then
		problems := problems || jsonb_build_object('code', 'not_open', 'availability', true,
			'message', 'The offer "' || target_offer.name || '" opens on '
				|| to_char(target_offer.claim_starts_at at time zone 'UTC', 'YYYY-MM-DD') || '.');
	end if;
	if target_offer.claim_ends_at is not null and target_offer.claim_ends_at <= now() then
		problems := problems || jsonb_build_object('code', 'closed', 'availability', true,
			'message', 'The offer "' || target_offer.name || '" stopped taking new customers on '
				|| to_char(target_offer.claim_ends_at at time zone 'UTC', 'YYYY-MM-DD') || '.');
	end if;
	if target_offer.redemption_cap is not null then
		claims := private.package_offer_claim_count(target_offer.id);
		if claims >= target_offer.redemption_cap then
			problems := problems || jsonb_build_object('code', 'full', 'availability', true,
				'message', 'All ' || target_offer.redemption_cap || ' places on the offer "' || target_offer.name
					|| '" have been claimed.');
		end if;
	end if;
	if not exists (select 1 from public.package_offer_packages op
		where op.offer_id = target_offer.id and op.package_id = target_package_id) then
		select e.name into package_name from public.package_editions e
		where e.package_id = target_package_id and e.status = 'published';
		problems := problems || jsonb_build_object('code', 'package_not_eligible', 'availability', false,
			'message', 'The offer "' || target_offer.name || '" does not include the '
				|| coalesce(package_name, 'chosen') || ' package.');
	end if;
	if (target_billing_interval = 'month' and not target_offer.applies_to_monthly)
		or (target_billing_interval = 'year' and not target_offer.applies_to_yearly) then
		problems := problems || jsonb_build_object('code', 'interval_not_eligible', 'availability', false,
			'message', 'The offer "' || target_offer.name || '" is for '
				|| case when target_offer.applies_to_monthly then 'monthly' else 'yearly' end || ' billing only.');
	end if;
	if target_organization_id is null and target_offer.customer_eligibility = 'existing' then
		problems := problems || jsonb_build_object('code', 'existing_only', 'availability', false,
			'message', 'The offer "' || target_offer.name || '" is for existing customers only.');
	end if;
	if target_organization_id is not null and target_offer.customer_eligibility = 'new' then
		problems := problems || jsonb_build_object('code', 'new_only', 'availability', false,
			'message', 'The offer "' || target_offer.name || '" is for new customers only.');
	end if;
	if target_organization_id is not null and exists (
		select 1 from public.package_offer_claims c
		where c.offer_id = target_offer.id and c.organization_id = target_organization_id and c.released_at is null
	) then
		problems := problems || jsonb_build_object('code', 'already_claimed', 'availability', false,
			'message', 'This customer has already claimed the offer "' || target_offer.name || '".');
	end if;
	return problems;
end;
$$;

-- The automatic offer a new customer gets on this package and billing now: the one with the lowest first
-- charge, then the newest. Null when none applies.
create or replace function private.best_new_customer_offer(target_package_id uuid, target_billing_interval text, normal_price integer)
returns public.package_offers
language sql
stable
set search_path = ''
as $$
	select o.*
	from public.package_offers o
	join public.package_offer_packages op on op.offer_id = o.id and op.package_id = target_package_id
	where o.apply_mode = 'automatic'
		and normal_price is not null
		and jsonb_array_length(private.package_offer_problems(o, null, target_package_id, target_billing_interval)) = 0
	order by private.package_offer_intro_price(to_jsonb(o), normal_price), o.created_at desc
	limit 1;
$$;

-- What a visitor is shown for an offer: the discount, how long it lasts, both prices, and the claim deadline.
create or replace function private.package_offer_shown(target_offer public.package_offers, target_billing_interval text, normal_price integer)
returns jsonb
language sql
stable
set search_path = ''
as $$
	select case when target_offer.id is null then null else jsonb_build_object(
		'id', target_offer.id,
		'name', target_offer.name,
		'discount_kind', target_offer.discount_kind,
		'percent_off', target_offer.percent_off,
		'amount_off_usd_cents', target_offer.amount_off_usd_cents,
		'monthly_periods', target_offer.monthly_periods,
		'billing_interval', target_billing_interval,
		'periods', case target_billing_interval when 'year' then 1 else target_offer.monthly_periods end,
		'normal_price_usd_cents', normal_price,
		'intro_price_usd_cents', private.package_offer_intro_price(to_jsonb(target_offer), normal_price),
		'claim_ends_at', target_offer.claim_ends_at
	) end;
$$;

revoke all on function private.package_offer_intro_price(jsonb, integer) from public, anon, authenticated;
revoke all on function private.package_offer_window_end(date, date, text, integer) from public, anon, authenticated;
revoke all on function private.package_offer_terms(jsonb, integer, text, date, date) from public, anon, authenticated;
revoke all on function private.agreement_period_price(integer, jsonb, date) from public, anon, authenticated;
revoke all on function private.package_offer_claim_count(uuid) from public, anon, authenticated;
revoke all on function private.package_offer_problems(public.package_offers, uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.best_new_customer_offer(uuid, text, integer) from public, anon, authenticated;
revoke all on function private.package_offer_shown(public.package_offers, text, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 3. Offers for the public cards, details page, and /get-started.
-- ---------------------------------------------------------------------------------------------------

-- One row per public package and billing interval that has an automatic offer for new customers now.
create or replace function public.public_package_offers()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(shown order by slug, billing_interval), '[]'::jsonb)
	from (
		select p.slug, i.billing_interval,
			jsonb_build_object('edition_id', e.id, 'package_slug', p.slug)
				|| private.package_offer_shown(
					private.best_new_customer_offer(p.id, i.billing_interval, i.price), i.billing_interval, i.price) as shown
		from public.packages p
		join public.package_editions e on e.package_id = p.id and e.status = 'published'
		cross join lateral (values
			('month', e.monthly_price_usd_cents),
			('year', e.yearly_price_usd_cents)
		) as i (billing_interval, price)
		where p.visibility = 'public' and p.archived_at is null and i.price is not null
	) as offers
	where shown ? 'id';
$$;

revoke all on function public.public_package_offers() from public;
grant execute on function public.public_package_offers() to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Jafar's offer builder.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.owner_package_offers()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(jsonb_build_object(
		'id', o.id, 'name', o.name, 'apply_mode', o.apply_mode, 'code', o.code,
		'discount_kind', o.discount_kind, 'percent_off', o.percent_off, 'amount_off_usd_cents', o.amount_off_usd_cents,
		'applies_to_monthly', o.applies_to_monthly, 'applies_to_yearly', o.applies_to_yearly,
		'monthly_periods', o.monthly_periods, 'customer_eligibility', o.customer_eligibility,
		'claim_starts_at', o.claim_starts_at, 'claim_ends_at', o.claim_ends_at, 'redemption_cap', o.redemption_cap,
		'archived_at', o.archived_at, 'revision', o.revision, 'created_at', o.created_at, 'updated_at', o.updated_at,
		'status', case
			when o.archived_at is not null then 'archived'
			when o.claim_starts_at > now() then 'scheduled'
			when o.claim_ends_at is not null and o.claim_ends_at <= now() then 'ended'
			when o.redemption_cap is not null and private.package_offer_claim_count(o.id) >= o.redemption_cap then 'full'
			else 'open'
		end,
		'terms_locked', exists (select 1 from public.package_offer_claims c where c.offer_id = o.id),
		'claim_count', private.package_offer_claim_count(o.id),
		'package_ids', coalesce((select jsonb_agg(op.package_id) from public.package_offer_packages op
			where op.offer_id = o.id), '[]'::jsonb),
		'claims', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', c.id, 'organization_id', c.organization_id, 'organization_name', org.name,
				'method', c.method, 'honored', c.honored, 'claimed_at', c.created_at, 'released_at', c.released_at,
				'actor_owner_email', c.actor_owner_email) order by c.created_at desc)
			from public.package_offer_claims c
			join public.organizations org on org.id = c.organization_id
			where c.offer_id = o.id
		), '[]'::jsonb)
	) order by o.archived_at nulls first, o.created_at desc), '[]'::jsonb)
	from public.package_offers o;
$$;

-- Creates an offer (offer_id null) or saves the one Jafar loaded at expected_revision. Once any customer has
-- claimed an offer, its discount, billing, and length are fixed; name, code, dates, cap, customers, and
-- packages stay editable.
create or replace function public.save_package_offer(
	offer_id uuid,
	expected_revision integer,
	name text,
	apply_mode text,
	code text,
	discount_kind text,
	percent_off integer,
	amount_off_usd_cents integer,
	applies_to_monthly boolean,
	applies_to_yearly boolean,
	monthly_periods integer,
	customer_eligibility text,
	claim_starts_at timestamptz,
	claim_ends_at timestamptz,
	redemption_cap integer,
	package_ids uuid[],
	actor_owner_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing public.package_offers;
	saved public.package_offers;
	clean_code text := nullif(upper(trim(coalesce(code, ''))), '');
	claims integer;
begin
	if offer_id is null then
		select * into existing from public.package_offers o where o.idempotency_key = save_package_offer.idempotency_key;
		if existing.id is not null then
			return jsonb_build_object('applied', false, 'offer_id', existing.id, 'revision', existing.revision);
		end if;
	else
		select * into existing from public.package_offers o where o.id = save_package_offer.offer_id for update;
		if existing.id is null then
			raise exception 'That offer was not found.' using errcode = 'foreign_key_violation';
		end if;
		if existing.revision <> expected_revision then
			raise exception 'This offer was changed somewhere else. Reload it before saving.' using errcode = 'P0409';
		end if;
	end if;

	if name is null or char_length(trim(name)) = 0 then
		raise exception 'Give the offer a name.' using errcode = 'check_violation';
	end if;
	if apply_mode = 'code' and clean_code is null then
		raise exception 'Give the offer a code.' using errcode = 'check_violation';
	end if;
	if apply_mode = 'code' and clean_code !~ '^[A-Z0-9][A-Z0-9-]{2,31}$' then
		raise exception 'A code is 3 to 32 letters, numbers, or dashes.' using errcode = 'check_violation';
	end if;
	if apply_mode = 'code' and exists (select 1 from public.package_offers o
		where o.code = clean_code and o.id is distinct from save_package_offer.offer_id) then
		raise exception 'Another offer already uses the code %.', clean_code using errcode = 'unique_violation';
	end if;
	if package_ids is null or cardinality(package_ids) = 0 then
		raise exception 'Choose at least one package.' using errcode = 'check_violation';
	end if;
	if exists (select 1 from unnest(package_ids) as pid where not exists (select 1 from public.packages p where p.id = pid)) then
		raise exception 'One of the chosen packages was not found.' using errcode = 'foreign_key_violation';
	end if;
	if not coalesce(applies_to_monthly, false) and not coalesce(applies_to_yearly, false) then
		raise exception 'Choose monthly billing, yearly billing, or both.' using errcode = 'check_violation';
	end if;
	if coalesce(applies_to_monthly, false) and (monthly_periods is null or monthly_periods not between 1 and 36) then
		raise exception 'Choose how many months the monthly offer lasts, from 1 to 36.' using errcode = 'check_violation';
	end if;
	if discount_kind = 'percent' and (percent_off is null or percent_off not between 1 and 100) then
		raise exception 'A percentage discount is from 1 to 100.' using errcode = 'check_violation';
	end if;
	if discount_kind = 'fixed' and (amount_off_usd_cents is null or amount_off_usd_cents <= 0) then
		raise exception 'Enter the amount taken off.' using errcode = 'check_violation';
	end if;
	if claim_starts_at is null then
		raise exception 'Choose when customers can start claiming the offer.' using errcode = 'check_violation';
	end if;
	if claim_ends_at is not null and claim_ends_at <= claim_starts_at then
		raise exception 'The last claim day must come after the first.' using errcode = 'check_violation';
	end if;

	if existing.id is not null then
		claims := private.package_offer_claim_count(existing.id);
		if redemption_cap is not null and redemption_cap < claims then
			raise exception '% customers have already claimed this offer, so the cap cannot be lower than that.', claims
				using errcode = 'check_violation';
		end if;
		if exists (select 1 from public.package_offer_claims c where c.offer_id = existing.id) and (
			existing.discount_kind is distinct from save_package_offer.discount_kind
			or existing.percent_off is distinct from (case when save_package_offer.discount_kind = 'percent' then save_package_offer.percent_off end)
			or existing.amount_off_usd_cents is distinct from (case when save_package_offer.discount_kind = 'fixed' then save_package_offer.amount_off_usd_cents end)
			or existing.applies_to_monthly is distinct from save_package_offer.applies_to_monthly
			or existing.applies_to_yearly is distinct from save_package_offer.applies_to_yearly
			or existing.monthly_periods is distinct from (case when save_package_offer.applies_to_monthly then save_package_offer.monthly_periods end)
		) then
			raise exception 'Customers have claimed this offer, so its discount, billing, and length can no longer change. Create a new offer instead.'
				using errcode = 'check_violation';
		end if;

		update public.package_offers o set
			name = trim(save_package_offer.name), apply_mode = save_package_offer.apply_mode,
			code = case when save_package_offer.apply_mode = 'code' then clean_code end,
			discount_kind = save_package_offer.discount_kind,
			percent_off = case when save_package_offer.discount_kind = 'percent' then save_package_offer.percent_off end,
			amount_off_usd_cents = case when save_package_offer.discount_kind = 'fixed' then save_package_offer.amount_off_usd_cents end,
			applies_to_monthly = save_package_offer.applies_to_monthly,
			applies_to_yearly = save_package_offer.applies_to_yearly,
			monthly_periods = case when save_package_offer.applies_to_monthly then save_package_offer.monthly_periods end,
			customer_eligibility = save_package_offer.customer_eligibility,
			claim_starts_at = save_package_offer.claim_starts_at, claim_ends_at = save_package_offer.claim_ends_at,
			redemption_cap = save_package_offer.redemption_cap,
			revision = o.revision + 1, updated_at = now()
		where o.id = existing.id
		returning * into saved;

		delete from public.package_offer_packages op
		where op.offer_id = saved.id and op.package_id <> all (package_ids);
	else
		insert into public.package_offers (
			name, apply_mode, code, discount_kind, percent_off, amount_off_usd_cents, applies_to_monthly,
			applies_to_yearly, monthly_periods, customer_eligibility, claim_starts_at, claim_ends_at, redemption_cap,
			actor_owner_email, idempotency_key
		) values (
			trim(name), apply_mode, case when apply_mode = 'code' then clean_code end, discount_kind,
			case when discount_kind = 'percent' then percent_off end,
			case when discount_kind = 'fixed' then amount_off_usd_cents end,
			applies_to_monthly, applies_to_yearly, case when applies_to_monthly then monthly_periods end,
			customer_eligibility, claim_starts_at, claim_ends_at, redemption_cap, actor_owner_email, idempotency_key
		)
		returning * into saved;
	end if;

	insert into public.package_offer_packages (offer_id, package_id)
	select saved.id, pid from unnest(package_ids) as pid
	on conflict do nothing;

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, before_state, after_state
	) values (
		actor_owner_email, case when existing.id is null then 'package_offer.created' else 'package_offer.updated' end,
		'package_offer', saved.id::text,
		case when existing.id is null then null else to_jsonb(existing) end,
		to_jsonb(saved) || jsonb_build_object('package_ids', to_jsonb(package_ids))
	);

	return jsonb_build_object('applied', true, 'offer_id', saved.id, 'revision', saved.revision);
end;
$$;

-- Archiving stops new claims; customers who claimed the offer keep their months. Restoring reopens it.
create or replace function public.set_package_offer_archived(
	offer_id uuid,
	archived boolean,
	actor_owner_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	saved public.package_offers;
begin
	update public.package_offers o
	set archived_at = case when archived then coalesce(o.archived_at, now()) end,
		revision = o.revision + case when (o.archived_at is null) = archived then 1 else 0 end,
		updated_at = now()
	where o.id = set_package_offer_archived.offer_id
	returning * into saved;
	if saved.id is null then
		raise exception 'That offer was not found.' using errcode = 'foreign_key_violation';
	end if;

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, after_state
	) values (
		actor_owner_email, case when archived then 'package_offer.archived' else 'package_offer.restored' end,
		'package_offer', saved.id::text, jsonb_build_object('archived_at', saved.archived_at)
	);

	return jsonb_build_object('offer_id', saved.id, 'archived_at', saved.archived_at, 'revision', saved.revision);
end;
$$;

revoke all on function public.owner_package_offers() from public, anon, authenticated;
revoke all on function public.save_package_offer(uuid, integer, text, text, text, text, integer, integer, boolean, boolean,
	integer, text, timestamptz, timestamptz, integer, uuid[], text, text) from public, anon, authenticated;
revoke all on function public.set_package_offer_archived(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.owner_package_offers() to service_role;
grant execute on function public.save_package_offer(uuid, integer, text, text, text, text, integer, integer, boolean, boolean,
	integer, text, timestamptz, timestamptz, integer, uuid[], text, text) to service_role;
grant execute on function public.set_package_offer_archived(uuid, boolean, text) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. Every charge is priced from its agreement, with the offer for periods inside its window.
-- ---------------------------------------------------------------------------------------------------
create or replace function private.add_organization_billing_charge(
	target_organization_id uuid,
	period_start date,
	actor_owner_email text,
	idempotency_key text
)
returns public.organization_billing_charges
language plpgsql
set search_path = ''
as $$
declare
	commercial_timezone text;
	agreement public.organization_package_agreements;
	previous public.organization_billing_charges;
	previous_interval text;
	next_anchor date;
	inserted public.organization_billing_charges;
begin
	select s.commercial_timezone into commercial_timezone
	from public.organization_commercial_settings s
	where s.organization_id = target_organization_id;

	-- The agreement in effect by the end of the period's first local day.
	select * into agreement
	from public.organization_package_agreements a
	where a.organization_id = target_organization_id
		and a.cancelled_at is null
		and a.effective_from < ((period_start + 1)::timestamp at time zone coalesce(commercial_timezone, 'UTC'))
	order by a.effective_from desc, a.created_at desc
	limit 1;

	if agreement.id is null then
		return null;
	end if;

	select c.* into previous
	from public.organization_billing_charges c
	where c.organization_id = target_organization_id
		and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
	order by c.period_start desc
	limit 1;

	if previous.id is not null and period_start <= previous.period_end then
		raise exception 'A charge already covers %. The next charge starts on %.', period_start, previous.period_end + 1
			using errcode = 'check_violation';
	end if;

	select a.billing_interval into previous_interval
	from public.organization_package_agreements a
	where a.id = previous.agreement_id;

	-- A charge that follows on from the last one keeps its anchor; a break or an interval change starts afresh.
	next_anchor := case
		when previous.id is not null and period_start = previous.period_end + 1
			and previous_interval = agreement.billing_interval then previous.anchor_date
		else period_start
	end;

	insert into public.organization_billing_charges (
		organization_id, agreement_id, anchor_date, period_start, period_end, amount_usd_cents,
		actor_owner_email, idempotency_key
	) values (
		target_organization_id, agreement.id, next_anchor, period_start,
		private.billing_period_end(next_anchor, period_start, agreement.billing_interval),
		private.agreement_period_price(agreement.agreed_price_usd_cents, agreement.offer_terms, period_start),
		actor_owner_email, idempotency_key
	)
	returning * into inserted;

	return inserted;
end;
$$;


-- ---------------------------------------------------------------------------------------------------
-- 6. Package changes carry a new offer or keep the current one.
-- ---------------------------------------------------------------------------------------------------
drop function public.owner_package_change_preview(uuid, uuid, text, text);
drop function public.change_organization_package(uuid, uuid, text, text, date, integer, integer, text, text, text);
drop function private.package_change_plan(uuid, uuid, text, text);

create or replace function private.package_change_plan(
	target_organization_id uuid,
	target_edition_id uuid,
	target_billing_interval text,
	target_timing text,
	target_offer_id uuid default null,
	target_offer_code text default null,
	keep_offer boolean default false
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
	tz text;
	today date;
	commercial public.organization_commercial_state;
	current_agreement public.organization_package_agreements;
	scheduled public.organization_package_agreements;
	current_edition public.package_editions;
	current_package public.packages;
	proposed public.package_editions;
	proposed_package public.packages;
	price integer;
	blockers jsonb := '[]'::jsonb;
	effective_date date;
	effective_from timestamptz;
	interval_changes boolean;
	current_charge public.organization_billing_charges;
	replaced jsonb := '[]'::jsonb;
	replaced_locked boolean := false;
	previous_anchor date;
	credit integer := 0;
	remaining_days integer;
	regular_start date;
	regular_end date;
	new_charge jsonb;
	next_charge jsonb;
	next_start date;
	next_anchor date;
	allowances jsonb;
	over_limits jsonb;
	capabilities jsonb;
	offer_row public.package_offers;
	offer_terms jsonb;
	offer_starts date;
	window_anchor date;
	can_keep boolean;
	available jsonb;
	asks_offer boolean := target_offer_id is not null
		or nullif(trim(coalesce(target_offer_code, '')), '') is not null;
begin
	if target_timing is null or target_timing not in ('next_renewal', 'now') then
		raise exception 'Choose when the change starts.' using errcode = 'check_violation';
	end if;
	if target_billing_interval is null or target_billing_interval not in ('month', 'year') then
		raise exception 'Choose monthly or yearly billing.' using errcode = 'check_violation';
	end if;

	select * into proposed from public.package_editions e where e.id = target_edition_id;
	if proposed.id is null then
		raise exception 'That package edition was not found.' using errcode = 'foreign_key_violation';
	end if;
	select * into proposed_package from public.packages p where p.id = proposed.package_id;

	select coalesce((select s.commercial_timezone from public.organization_commercial_settings s
		where s.organization_id = target_organization_id), 'UTC') into tz;
	today := (now() at time zone tz)::date;
	select * into commercial from public.organization_commercial_state s where s.organization_id = target_organization_id;

	select * into current_agreement from public.organization_package_agreements a
	where a.organization_id = target_organization_id and a.effective_from <= now() and a.cancelled_at is null
	order by a.effective_from desc, a.created_at desc
	limit 1;
	select * into scheduled from public.organization_package_agreements a
	where a.organization_id = target_organization_id and a.effective_from > now() and a.cancelled_at is null
	order by a.effective_from
	limit 1;
	select * into current_edition from public.package_editions e where e.id = current_agreement.edition_id;
	select * into current_package from public.packages p where p.id = current_edition.package_id;

	price := case target_billing_interval
		when 'month' then proposed.monthly_price_usd_cents else proposed.yearly_price_usd_cents end;
	interval_changes := current_agreement.billing_interval is distinct from target_billing_interval;

	if proposed.status <> 'published' then
		blockers := blockers || jsonb_build_object('code', 'edition_not_current',
			'message', 'This edition has been replaced by a newer one. Choose the current edition.');
	end if;
	if proposed_package.archived_at is not null then
		blockers := blockers || jsonb_build_object('code', 'package_archived',
			'message', 'This package is archived. Restore it before moving a customer onto it.');
	end if;
	if price is null then
		blockers := blockers || jsonb_build_object('code', 'price_missing',
			'message', 'This package has no ' || case target_billing_interval when 'month' then 'monthly' else 'yearly' end
				|| ' price.');
	end if;
	if current_agreement.edition_id = proposed.id and not interval_changes and not asks_offer then
		blockers := blockers || jsonb_build_object('code', 'same_terms',
			'message', 'The customer already has this package and billing. Choose an offer to add one.');
	end if;
	if scheduled.id is not null then
		blockers := blockers || jsonb_build_object('code', 'change_scheduled',
			'message', 'A change is already scheduled for ' || to_char((scheduled.effective_from at time zone tz)::date, 'YYYY-MM-DD')
				|| '. Cancel it first.');
	end if;

	if target_timing = 'next_renewal' then
		if commercial.paid_through_date is null then
			blockers := blockers || jsonb_build_object('code', 'no_renewal_date',
				'message', 'This customer has no paid period yet, so there is no renewal date. Move them now instead.');
		elsif commercial.paid_through_date < today then
			blockers := blockers || jsonb_build_object('code', 'renewal_passed',
				'message', 'Their renewal date has already passed. Move them now instead.');
		else
			effective_date := commercial.paid_through_date + 1;
			effective_from := effective_date::timestamp at time zone tz;
		end if;
	else
		effective_date := today;
		effective_from := now();
	end if;

	if effective_date is not null then
		if target_timing = 'now' then
			select * into current_charge from public.organization_billing_charges c
			where c.organization_id = target_organization_id and c.period_start <= today and c.period_end >= today
				and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
			order by c.period_start desc, c.created_at desc
			limit 1;
		end if;

		-- A kept offer keeps its window with the new price. A new offer starts with the first full period
		-- under the new terms; a part period after a same-billing move now is charged at the normal price.
		can_keep := current_agreement.offer_terms is not null and not interval_changes
			and (current_agreement.offer_terms ->> 'ends_before')::date > effective_date;
		if keep_offer and asks_offer then
			blockers := blockers || jsonb_build_object('code', 'offer_choice',
				'message', 'Choose a new offer or keep the current one, not both.');
		elsif keep_offer then
			if current_agreement.offer_terms is null or (current_agreement.offer_terms ->> 'ends_before')::date <= effective_date then
				blockers := blockers || jsonb_build_object('code', 'no_offer_to_keep',
					'message', 'There is no intro offer left to keep on the day the change starts.');
			elsif interval_changes then
				blockers := blockers || jsonb_build_object('code', 'offer_interval',
					'message', 'An intro offer can only be kept when the billing stays '
						|| case current_agreement.billing_interval when 'month' then 'monthly' else 'yearly' end || '.');
			elsif price is not null then
				offer_terms := current_agreement.offer_terms || jsonb_build_object(
					'normal_price_usd_cents', price,
					'intro_price_usd_cents', private.package_offer_intro_price(current_agreement.offer_terms, price));
			end if;
		elsif asks_offer then
			select * into offer_row from public.package_offers o
			where (target_offer_id is not null and o.id = target_offer_id)
				or (target_offer_id is null and o.code = upper(trim(target_offer_code)));
			if offer_row.id is null then
				blockers := blockers || jsonb_build_object('code', 'offer_not_found',
					'message', case when target_offer_id is null
						then 'No offer has the code ' || upper(trim(target_offer_code)) || '.'
						else 'That offer was not found.' end);
			else
				blockers := blockers || private.package_offer_problems(
					offer_row, target_organization_id, proposed.package_id, target_billing_interval);
				if target_timing = 'now' and (interval_changes or current_charge.id is null) then
					offer_starts := today;
					window_anchor := today;
				elsif target_timing = 'now' then
					offer_starts := current_charge.period_end + 1;
					window_anchor := current_charge.anchor_date;
				else
					offer_starts := effective_date;
					window_anchor := case when interval_changes then effective_date else coalesce((
						select c.anchor_date from public.organization_billing_charges c
						where c.organization_id = target_organization_id and c.period_end = effective_date - 1
							and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
						order by c.period_start desc
						limit 1
					), effective_date) end;
				end if;
				if price is not null then
					offer_terms := private.package_offer_terms(
						to_jsonb(offer_row), price, target_billing_interval, window_anchor, offer_starts);
				end if;
			end if;
		end if;

		-- Charges already waiting for dates after the change starts were priced on the old terms.
		select
			coalesce(jsonb_agg(jsonb_build_object(
				'id', c.id, 'period_start', c.period_start, 'period_end', c.period_end,
				'amount_usd_cents', c.amount_usd_cents) order by c.period_start), '[]'::jsonb),
			coalesce(bool_or(private.billing_charge_applied(c.id) > 0
				or exists (select 1 from public.organization_billing_coverage_confirmations cc where cc.charge_id = c.id)), false)
		into replaced, replaced_locked
		from public.organization_billing_charges c
		where c.organization_id = target_organization_id
			and c.period_start > case when target_timing = 'now' then today else effective_date - 1 end
			and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id);

		if replaced_locked then
			blockers := blockers || jsonb_build_object('code', 'future_charge_paid',
				'message', 'A later charge already has money applied at the old price. Remove that money from it first.');
		end if;

		if current_charge.id is not null then
			remaining_days := current_charge.period_end - today + 1;
			credit := round(current_charge.amount_usd_cents::numeric * remaining_days
				/ (current_charge.period_end - current_charge.period_start + 1))::integer;
			if not interval_changes then
				regular_start := private.billing_period_start(current_charge.anchor_date, today, target_billing_interval);
				regular_end := private.billing_period_end(current_charge.anchor_date, today, target_billing_interval);
				new_charge := jsonb_build_object(
					'kind', 'change', 'anchor_date', current_charge.anchor_date, 'period_start', today,
					'period_end', current_charge.period_end,
					'amount_usd_cents', round(coalesce(private.agreement_period_price(price, offer_terms, today), 0)::numeric
						* remaining_days / (regular_end - regular_start + 1))::integer);
			else
				new_charge := jsonb_build_object(
					'kind', 'period', 'anchor_date', today, 'period_start', today,
					'period_end', private.billing_period_end(today, today, target_billing_interval),
					'amount_usd_cents', coalesce(private.agreement_period_price(price, offer_terms, today), 0));
			end if;
		end if;

		-- The waiting charge comes back at the new price, except after a monthly-yearly switch made now:
		-- the new period starting today already covers those dates.
		if jsonb_array_length(replaced) > 0 and not (current_charge.id is not null and interval_changes) then
			next_start := (replaced -> 0 ->> 'period_start')::date;
			select c.anchor_date into previous_anchor from public.organization_billing_charges c
			where c.organization_id = target_organization_id and c.period_end = next_start - 1
				and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
			order by c.period_start desc
			limit 1;
			next_anchor := case
				when new_charge is not null then (new_charge ->> 'anchor_date')::date
				when previous_anchor is not null and not interval_changes then previous_anchor
				else next_start
			end;
			next_charge := jsonb_build_object(
				'period_start', next_start,
				'period_end', private.billing_period_end(next_anchor, next_start, target_billing_interval),
				'amount_usd_cents', coalesce(private.agreement_period_price(price, offer_terms, next_start), 0));
		end if;
	end if;

	-- Allowances on both sides. An exception active when the change starts still applies on top.
	select
		jsonb_agg(row_json order by sort_order),
		coalesce(jsonb_agg(row_json order by sort_order) filter (where (row_json ->> 'excess')::integer > 0), '[]'::jsonb)
	into allowances, over_limits
	from (
		select pa.sort_order, jsonb_build_object(
			'allowance_key', pa.allowance_key, 'label', pa.label, 'unit', pa.unit, 'resets_monthly', pa.resets_monthly,
			'current', jsonb_build_object('state', coalesce(ce.allowance_state, 'not_included'), 'value', ce.allowance_value),
			'proposed', jsonb_build_object('state', coalesce(pe.allowance_state, 'not_included'), 'value', pe.allowance_value),
			'exception', case when x.id is null then null
				else jsonb_build_object('state', x.allowance_state, 'value', x.allowance_value, 'ends_at', x.ends_at) end,
			'in_use', usage.in_use,
			'excess', case
				when usage.in_use is null then 0
				when coalesce(x.allowance_state, pe.allowance_state, 'not_included') = 'unlimited' then 0
				else greatest(usage.in_use - case coalesce(x.allowance_state, pe.allowance_state, 'not_included')
					when 'numeric' then coalesce(x.allowance_value, pe.allowance_value) else 0 end, 0)
			end
		) as row_json
		from public.package_allowances pa
		left join public.package_edition_allowances ce
			on ce.edition_id = current_agreement.edition_id and ce.allowance_key = pa.allowance_key
		left join public.package_edition_allowances pe
			on pe.edition_id = proposed.id and pe.allowance_key = pa.allowance_key
		left join lateral (
			select * from public.organization_package_exceptions e
			where e.organization_id = target_organization_id and e.allowance_key = pa.allowance_key
				and e.starts_at <= coalesce(effective_from, now()) and e.ends_at > coalesce(effective_from, now())
			order by e.starts_at desc, e.created_at desc
			limit 1
		) x on true
		cross join lateral (
			select private.package_allowance_in_use(target_organization_id, pa.allowance_key) as in_use
		) usage
	) as allowance_rows;

	if jsonb_array_length(over_limits) > 0 then
		blockers := blockers || jsonb_build_object('code', 'over_limits',
			'message', 'Resolve what is over the new package''s limits first.');
	end if;

	select jsonb_agg(jsonb_build_object(
		'capability_key', c.capability_key, 'label', c.label, 'kind', c.kind,
		'current', exists (select 1 from public.package_edition_capabilities ec
			where ec.edition_id = current_agreement.edition_id and ec.capability_key = c.capability_key),
		'proposed', exists (select 1 from public.package_edition_capabilities ec
			where ec.edition_id = proposed.id and ec.capability_key = c.capability_key),
		'exception', (
			select e.capability_state from public.organization_package_exceptions e
			where e.organization_id = target_organization_id and e.capability_key = c.capability_key
				and e.starts_at <= coalesce(effective_from, now()) and e.ends_at > coalesce(effective_from, now())
			order by e.starts_at desc, e.created_at desc
			limit 1
		)
	) order by c.sort_order)
	into capabilities
	from public.package_capabilities c;

	-- Automatic offers this customer could take on the proposed package and billing.
	select coalesce(jsonb_agg(private.package_offer_shown(o, target_billing_interval, price)
		order by private.package_offer_intro_price(to_jsonb(o), price), o.created_at desc), '[]'::jsonb)
	into available
	from public.package_offers o
	join public.package_offer_packages op on op.offer_id = o.id and op.package_id = proposed.package_id
	where o.apply_mode = 'automatic' and price is not null
		and jsonb_array_length(private.package_offer_problems(o, target_organization_id, proposed.package_id,
			target_billing_interval)) = 0;

	return jsonb_build_object(
		'organization_id', target_organization_id,
		'commercial_timezone', tz,
		'today', today,
		'paid_through_date', commercial.paid_through_date,
		'timing', target_timing,
		'effective_date', effective_date,
		'effective_from', effective_from,
		'current', case when current_agreement.id is null then null else jsonb_build_object(
			'agreement_id', current_agreement.id, 'edition_id', current_edition.id, 'name', current_edition.name,
			'edition_number', current_edition.edition_number, 'package_slug', current_package.slug,
			'billing_interval', current_agreement.billing_interval,
			'agreed_price_usd_cents', current_agreement.agreed_price_usd_cents,
			'offer_terms', current_agreement.offer_terms) end,
		'proposed', jsonb_build_object(
			'edition_id', proposed.id, 'name', proposed.name, 'edition_number', proposed.edition_number,
			'package_slug', proposed_package.slug, 'visibility', proposed_package.visibility,
			'billing_interval', target_billing_interval, 'price_usd_cents', price),
		'capabilities', coalesce(capabilities, '[]'::jsonb),
		'allowances', coalesce(allowances, '[]'::jsonb),
		'over_limits', over_limits,
		'money', jsonb_build_object(
			'credit_usd_cents', credit,
			'credit_from', case when credit > 0 then today end,
			'credit_through', case when credit > 0 then current_charge.period_end end,
			'credit_source_charge_id', case when credit > 0 then current_charge.id end,
			'new_charge', new_charge,
			'credit_applied_usd_cents', least(credit, coalesce((new_charge ->> 'amount_usd_cents')::integer, 0)),
			'replaced_charges', replaced,
			'next_charge', next_charge
		),
		'offer', jsonb_build_object(
			'proposed', offer_terms,
			'kept', keep_offer and offer_terms is not null,
			'can_keep', coalesce(can_keep, false),
			'available', coalesce(available, '[]'::jsonb)
		),
		'blockers', blockers
	);
end;
$$;


revoke all on function private.package_change_plan(uuid, uuid, text, text, uuid, text, boolean) from public, anon, authenticated;

create or replace function public.owner_package_change_preview(
	target_organization_id uuid,
	target_edition_id uuid,
	billing_interval text,
	timing text,
	target_offer_id uuid default null,
	offer_code text default null,
	keep_offer boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select private.package_change_plan(target_organization_id, target_edition_id, billing_interval, timing,
		target_offer_id, offer_code, keep_offer);
$$;


create or replace function public.change_organization_package(
	target_organization_id uuid,
	target_edition_id uuid,
	billing_interval text,
	timing text,
	expected_effective_date date,
	expected_credit_usd_cents integer,
	expected_charge_usd_cents integer,
	reason text,
	actor_owner_email text,
	idempotency_key text,
	target_offer_id uuid default null,
	offer_code text default null,
	keep_offer boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing public.organization_package_agreements;
	plan jsonb;
	money jsonb;
	current_agreement public.organization_package_agreements;
	inserted public.organization_package_agreements;
	replaced_charge record;
	new_charge public.organization_billing_charges;
	next_charge public.organization_billing_charges;
	credit_note_id uuid;
	credit integer;
	credit_applied integer;
	terms jsonb;
	claim_id uuid;
	claim_method text;
begin
	perform private.lock_organization_billing(target_organization_id);

	select * into existing from public.organization_package_agreements a
	where a.idempotency_key = change_organization_package.idempotency_key;
	if existing.id is not null then
		return jsonb_build_object('applied', false, 'agreement_id', existing.id);
	end if;

	if reason is null or char_length(trim(reason)) = 0 then
		raise exception 'Give a reason for the change.' using errcode = 'check_violation';
	end if;

	-- Claims of one offer run one at a time, so its cap holds.
	perform 1 from public.package_offers o
	where o.id = target_offer_id
		or (target_offer_id is null and o.code = upper(trim(coalesce(offer_code, ''))))
	for update;

	plan := private.package_change_plan(target_organization_id, target_edition_id, billing_interval, timing,
		target_offer_id, offer_code, keep_offer);
	if jsonb_array_length(plan -> 'blockers') > 0 then
		raise exception '%', plan -> 'blockers' -> 0 ->> 'message' using errcode = 'check_violation';
	end if;

	money := plan -> 'money';
	credit := (money ->> 'credit_usd_cents')::integer;
	if (plan ->> 'effective_date')::date is distinct from expected_effective_date
		or credit is distinct from coalesce(expected_credit_usd_cents, 0)
		or coalesce((money -> 'new_charge' ->> 'amount_usd_cents')::integer, 0) is distinct from coalesce(expected_charge_usd_cents, 0)
	then
		raise exception 'The change has moved on since you reviewed it. Review it again.' using errcode = 'P0409';
	end if;

	select * into current_agreement from public.organization_package_agreements a
	where a.organization_id = target_organization_id and a.effective_from <= now() and a.cancelled_at is null
	order by a.effective_from desc, a.created_at desc
	limit 1;

	terms := case when jsonb_typeof(plan -> 'offer' -> 'proposed') = 'object' then plan -> 'offer' -> 'proposed' end;
	if terms is not null and not keep_offer then
		claim_id := gen_random_uuid();
		terms := terms || jsonb_build_object('claim_id', claim_id);
		select o.apply_mode into claim_method from public.package_offers o where o.id = (terms ->> 'offer_id')::uuid;
	end if;

	insert into public.organization_package_agreements (
		organization_id, edition_id, billing_interval, agreed_price_usd_cents, offer_terms, service_anchor_date,
		effective_from, source, reason, actor_owner_email, idempotency_key
	) values (
		target_organization_id, target_edition_id, billing_interval, (plan -> 'proposed' ->> 'price_usd_cents')::integer,
		terms, current_agreement.service_anchor_date, (plan ->> 'effective_from')::timestamptz, 'package_change',
		trim(reason), actor_owner_email, idempotency_key
	)
	returning * into inserted;

	if claim_id is not null then
		insert into public.package_offer_claims (id, offer_id, organization_id, agreement_id, method, actor_owner_email)
		values (claim_id, (terms ->> 'offer_id')::uuid, target_organization_id, inserted.id, claim_method, actor_owner_email);
	end if;

	for replaced_charge in
		select (item ->> 'id')::uuid as id from jsonb_array_elements(money -> 'replaced_charges') item
	loop
		insert into public.organization_billing_voids (
			organization_id, charge_id, reason, actor_owner_email, idempotency_key
		) values (
			target_organization_id, replaced_charge.id, 'Replaced by the package change.', actor_owner_email,
			idempotency_key || ':void:' || replaced_charge.id
		);
	end loop;

	if jsonb_typeof(money -> 'new_charge') = 'object' then
		insert into public.organization_billing_charges (
			organization_id, agreement_id, anchor_date, period_start, period_end, amount_usd_cents, kind,
			actor_owner_email, idempotency_key
		) values (
			target_organization_id, inserted.id, (money -> 'new_charge' ->> 'anchor_date')::date,
			(money -> 'new_charge' ->> 'period_start')::date, (money -> 'new_charge' ->> 'period_end')::date,
			(money -> 'new_charge' ->> 'amount_usd_cents')::integer, money -> 'new_charge' ->> 'kind',
			actor_owner_email, idempotency_key || ':charge'
		)
		returning * into new_charge;
	end if;

	if credit > 0 then
		insert into public.organization_billing_credit_notes (
			organization_id, agreement_id, source_charge_id, unused_from, unused_through, amount_usd_cents, reason,
			actor_owner_email, idempotency_key
		) values (
			target_organization_id, inserted.id, (money ->> 'credit_source_charge_id')::uuid,
			(money ->> 'credit_from')::date, (money ->> 'credit_through')::date, credit,
			'Unused time returned by the package change.', actor_owner_email, idempotency_key || ':credit'
		)
		returning id into credit_note_id;

		credit_applied := (money ->> 'credit_applied_usd_cents')::integer;
		if new_charge.id is not null and credit_applied > 0 then
			perform private.apply_organization_billing_credit_note_money(
				target_organization_id, credit_note_id, new_charge.id, credit_applied, actor_owner_email,
				idempotency_key || ':credit:apply'
			);
		end if;
	end if;

	if jsonb_typeof(money -> 'next_charge') = 'object' then
		next_charge := private.add_organization_billing_charge(
			target_organization_id, (money -> 'next_charge' ->> 'period_start')::date, actor_owner_email,
			idempotency_key || ':next'
		);
	end if;

	perform public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => 'package_version_changed',
		idempotency_key => idempotency_key,
		summary => 'Package ' || case when timing = 'now' then 'changed' else 'change scheduled' end || ' to '
			|| (plan -> 'proposed' ->> 'name') || ' (edition ' || (plan -> 'proposed' ->> 'edition_number') || ', '
			|| case billing_interval when 'month' then 'monthly' else 'yearly' end || ') from '
			|| (plan ->> 'effective_date') || '.'
			|| case when claim_id is not null then ' Intro offer: ' || (terms ->> 'name') || '.'
				when terms is not null then ' Keeps the intro offer ' || (terms ->> 'name') || '.' else '' end,
		paid_through_effect => 'unchanged',
		actor_owner_email => actor_owner_email,
		private_reason => trim(reason),
		safe_kind => 'package_changed',
		safe_payload => jsonb_build_object(
			'effective_at', plan ->> 'effective_from',
			'package_display_name', plan -> 'proposed' ->> 'name',
			'package_version_number', (plan -> 'proposed' ->> 'edition_number')::integer)
	);

	return jsonb_build_object(
		'applied', true,
		'agreement_id', inserted.id,
		'effective_from', inserted.effective_from,
		'charge_id', new_charge.id,
		'credit_note_id', credit_note_id,
		'next_charge_id', next_charge.id,
		'offer_claim_id', claim_id
	);
end;
$$;


revoke all on function public.owner_package_change_preview(uuid, uuid, text, text, uuid, text, boolean)
	from public, anon, authenticated;
revoke all on function public.change_organization_package(uuid, uuid, text, text, date, integer, integer, text, text, text,
	uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.owner_package_change_preview(uuid, uuid, text, text, uuid, text, boolean) to service_role;
grant execute on function public.change_organization_package(uuid, uuid, text, text, date, integer, integer, text, text, text,
	uuid, text, boolean) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 7. Applications keep the automatic offer shown; activation claims it, honors it, drops it, or takes a code.
-- ---------------------------------------------------------------------------------------------------
create or replace function private.onboarding_package_snapshot(target_edition_id uuid, target_billing_interval text)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
	edition record;
	agreed_price integer;
	shown jsonb;
begin
	select e.id, e.edition_number, e.name, e.promise, e.highlights, e.included_services, e.exclusions,
		e.monthly_price_usd_cents, e.yearly_price_usd_cents, p.slug, p.id as package_id
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

	shown := private.package_offer_shown(
		private.best_new_customer_offer(edition.package_id, target_billing_interval, agreed_price),
		target_billing_interval, agreed_price);

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
		'offer', shown,
		'first_payment_usd_cents', coalesce((shown ->> 'intro_price_usd_cents')::integer, agreed_price),
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
$$;


-- The offer activation would record. `source` is 'shown' (the automatic offer on the application), 'code'
-- (one Jafar typed), 'dropped', or null. `blocking` is true while Jafar still has to decide: an offer the
-- customer was shown that has since closed, filled, or changed must be honored or dropped; a typed code must
-- be claimable now.
create or replace function private.onboarding_activation_offer(
	target_application_id uuid,
	offer_decision text,
	offer_code text
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
	app record;
	target_package_id uuid;
	shown jsonb;
	offer_row public.package_offers;
	problems jsonb := '[]'::jsonb;
begin
	if offer_decision is not null and offer_decision not in ('honor', 'drop') then
		raise exception 'Choose to honor the offer or activate at the normal price.' using errcode = 'check_violation';
	end if;

	select a.package_edition_id, a.billing_interval, a.package_snapshot into app
	from public.platform_onboarding_applications a
	where a.id = target_application_id;
	select e.package_id into target_package_id from public.package_editions e where e.id = app.package_edition_id;

	if nullif(trim(coalesce(offer_code, '')), '') is not null then
		select * into offer_row from public.package_offers o where o.code = upper(trim(offer_code));
		if offer_row.id is null then
			return jsonb_build_object('source', 'code', 'offer', null, 'blocking', true, 'honored', false,
				'problems', jsonb_build_array(jsonb_build_object('code', 'offer_not_found', 'availability', false,
					'message', 'No offer has the code ' || upper(trim(offer_code)) || '.')));
		end if;
		problems := private.package_offer_problems(offer_row, null, target_package_id, app.billing_interval);
		return jsonb_build_object('source', 'code', 'offer', to_jsonb(offer_row), 'method', 'code',
			'problems', problems, 'blocking', jsonb_array_length(problems) > 0, 'honored', false);
	end if;

	shown := app.package_snapshot -> 'offer';
	if jsonb_typeof(shown) is distinct from 'object' then
		return jsonb_build_object('source', null, 'offer', null, 'problems', '[]'::jsonb, 'blocking', false, 'honored', false);
	end if;
	if offer_decision = 'drop' then
		return jsonb_build_object('source', 'dropped', 'offer', null, 'shown', shown, 'problems', '[]'::jsonb,
			'blocking', false, 'honored', false);
	end if;

	select * into offer_row from public.package_offers o where o.id = (shown ->> 'id')::uuid;
	problems := private.package_offer_problems(offer_row, null, target_package_id, app.billing_interval);
	return jsonb_build_object(
		'source', 'shown',
		-- The customer agreed to the discount they were shown, even if the offer was edited since.
		'offer', shown || jsonb_build_object('code', offer_row.code),
		'method', coalesce(offer_row.apply_mode, 'automatic'),
		'problems', problems,
		'blocking', jsonb_array_length(problems) > 0 and offer_decision is distinct from 'honor',
		'honored', jsonb_array_length(problems) > 0 and offer_decision = 'honor'
	);
end;
$$;

revoke all on function private.onboarding_activation_offer(uuid, text, text) from public, anon, authenticated;

drop function public.owner_onboarding_activation_preview(uuid);
drop function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, date, date);

create or replace function public.owner_onboarding_activation_preview(
	target_application_id uuid,
	offer_decision text default null,
	offer_code text default null
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
	offer_decision text default null,
	offer_code text default null,
	expected_first_charge_usd_cents integer default null
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
			'offer_claim_id', claim_id
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


revoke all on function public.owner_onboarding_activation_preview(uuid, text, text) from public, anon, authenticated;
grant execute on function public.owner_onboarding_activation_preview(uuid, text, text) to service_role;
revoke all on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, date, date, text, text, integer)
	from public, anon, authenticated;
grant execute on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, date, date, text, text, integer)
	to service_role;
