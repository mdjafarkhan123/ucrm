-- Package builder P8a: changing a customer's package, and temporary exceptions.
--
-- Jafar previews a move to another published edition (capabilities gained and lost, allowance changes,
-- what is over the new limits, and the payment effect) and confirms exactly what he saw. A move at the
-- next renewal is an agreement dated the day after paid-through; the charge already waiting for that
-- period at the old price is swapped for the new price. A move now credits the unused days of the charge
-- covering today. With the same billing interval it charges the new price for the same remaining days and
-- keeps the renewal date; a monthly-yearly switch starts the new period today (Jafar, 2026-09-30,
-- following Stripe and Chargebee). Paid-through never moves by itself. A scheduled move can be
-- cancelled. Temporary exceptions carry a reason, a start, and an end, and can be ended early.

-- ---------------------------------------------------------------------------------------------------
-- 1. Storage.
-- ---------------------------------------------------------------------------------------------------

-- A scheduled move that has not started can be cancelled. Every agreement reader skips cancelled rows.
alter table public.organization_package_agreements
	add column cancelled_at timestamptz,
	add column cancel_reason text
		check (cancel_reason is null or char_length(trim(cancel_reason)) between 1 and 500),
	add column cancelled_by_email text
		check (cancelled_by_email is null or char_length(trim(cancelled_by_email)) between 3 and 320),
	add column cancel_idempotency_key text unique
		check (cancel_idempotency_key is null or char_length(trim(cancel_idempotency_key)) between 8 and 200),
	add constraint organization_package_agreements_cancel_complete check (
		(cancelled_at is null and cancel_reason is null and cancelled_by_email is null and cancel_idempotency_key is null)
		or (cancelled_at is not null and cancel_reason is not null and cancelled_by_email is not null
			and cancel_idempotency_key is not null)
	);

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
	if not exists (select 1 from public.package_editions e where e.id = new.edition_id and e.status = 'published') then
		raise exception 'An organization can only agree to a published package edition.'
			using errcode = 'check_violation';
	end if;
	return new;
end;
$$;

-- A change charge covers the rest of a period after an immediate move at the same billing interval.
alter table public.organization_billing_charges
	add column kind text not null default 'period' check (kind in ('period', 'change'));

-- Unused paid time returned by an immediate move: credit that is not money received (ADR 0003 decision 6).
create table public.organization_billing_credit_notes (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	agreement_id uuid not null references public.organization_package_agreements (id) on delete cascade,
	source_charge_id uuid not null references public.organization_billing_charges (id),
	unused_from date not null,
	unused_through date not null,
	amount_usd_cents integer not null check (amount_usd_cents > 0),
	reason text not null check (char_length(trim(reason)) between 1 and 500),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now(),
	check (unused_through >= unused_from)
);

create index organization_billing_credit_notes_org_idx on public.organization_billing_credit_notes (organization_id);
create index organization_billing_credit_notes_agreement_idx on public.organization_billing_credit_notes (agreement_id);
create index organization_billing_credit_notes_charge_idx on public.organization_billing_credit_notes (source_charge_id);

create trigger organization_billing_credit_notes_append_only before update or delete on public.organization_billing_credit_notes
	for each row execute function private.prevent_organization_billing_ledger_change();

alter table public.organization_billing_credit_notes enable row level security;
revoke all on public.organization_billing_credit_notes from anon, authenticated;
grant all on public.organization_billing_credit_notes to service_role;

-- An application moves money from a receipt or from a credit note onto a charge.
alter table public.organization_billing_applications
	alter column receipt_id drop not null,
	add column credit_note_id uuid references public.organization_billing_credit_notes (id),
	add constraint organization_billing_applications_one_source check (num_nonnulls(receipt_id, credit_note_id) = 1);

create index organization_billing_applications_credit_note_idx on public.organization_billing_applications (credit_note_id);

-- Exceptions carry an idempotency key and can be ended early; an exception ended before it started
-- keeps its record with an empty period.
alter table public.organization_package_exceptions
	add column idempotency_key text unique
		check (idempotency_key is null or char_length(trim(idempotency_key)) between 8 and 200),
	add column ended_early_at timestamptz,
	add column end_reason text check (end_reason is null or char_length(trim(end_reason)) between 1 and 1000),
	add column ended_by_email text check (ended_by_email is null or char_length(trim(ended_by_email)) between 3 and 320),
	drop constraint organization_package_exceptions_check,
	add constraint organization_package_exceptions_period_check
		check (ends_at > starts_at or (ended_early_at is not null and ends_at = starts_at)),
	add constraint organization_package_exceptions_end_complete check (
		(ended_early_at is null and end_reason is null and ended_by_email is null)
		or (ended_early_at is not null and end_reason is not null and ended_by_email is not null)
	);

-- ---------------------------------------------------------------------------------------------------
-- 2. Agreement readers skip cancelled moves.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.organization_agreement_edition(target_organization_id uuid, at timestamptz)
returns uuid
language sql
stable
set search_path = ''
as $$
	select a.edition_id
	from public.organization_package_agreements a
	where a.organization_id = target_organization_id and a.effective_from <= at and a.cancelled_at is null
	order by a.effective_from desc, a.created_at desc
	limit 1;
$$;

create or replace function public.organization_allowance(
	target_organization_id uuid,
	target_allowance_key text,
	at timestamptz default now()
)
returns table (state text, value integer, is_unlimited boolean, source text)
language sql
stable
security invoker
set search_path = ''
as $$
	with agreement_edition as (
		select a.edition_id
		from public.organization_package_agreements a
		where a.organization_id = target_organization_id and a.effective_from <= at and a.cancelled_at is null
		order by a.effective_from desc, a.created_at desc
		limit 1
	), exception_row as (
		select x.allowance_state, x.allowance_value
		from public.organization_package_exceptions x
		where x.organization_id = target_organization_id
			and x.allowance_key = target_allowance_key
			and x.starts_at <= at and x.ends_at > at
		order by x.starts_at desc, x.created_at desc
		limit 1
	), edition_row as (
		select ea.allowance_state, ea.allowance_value
		from public.package_edition_allowances ea
		where ea.edition_id = (select edition_id from agreement_edition)
			and ea.allowance_key = target_allowance_key
	), resolved as (
		select
			coalesce(x.allowance_state, e.allowance_state, 'not_included') as state,
			case when x.allowance_state is not null then x.allowance_value else e.allowance_value end as value,
			x.allowance_state is not null as from_exception
		from (select 1) as one
		left join exception_row x on true
		left join edition_row e on true
	)
	select r.state, r.value, r.state = 'unlimited', case when r.from_exception then 'override' else 'package' end
	from resolved r;
$$;

create or replace function public.organization_access_snapshot(
	target_organization_id uuid,
	target_user_id uuid default null,
	at timestamptz default now()
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
	with org as (
		select o.id, o.name, o.slug, o.lifecycle_status
		from public.organizations o
		where o.id = target_organization_id
	),
	agreement as (
		select a.id, a.edition_id, a.billing_interval, a.agreed_price_usd_cents, a.offer_terms,
			a.service_anchor_date, a.effective_from
		from public.organization_package_agreements a
		where a.organization_id = target_organization_id and a.effective_from <= at and a.cancelled_at is null
		order by a.effective_from desc, a.created_at desc
		limit 1
	),
	edition as (
		select e.id, e.package_id, e.edition_number, e.status, e.name, e.promise
		from public.package_editions e
		where e.id = (select edition_id from agreement)
	),
	package as (
		select p.id, p.slug, p.visibility, p.archived_at
		from public.packages p
		where p.id = (select package_id from edition)
	),
	membership as (
		select m.user_id, m.role
		from public.organization_members m
		where m.organization_id = target_organization_id
			and m.user_id = target_user_id
	)
	select case when not exists (select 1 from org) then null else jsonb_build_object(
		'organization', (select to_jsonb(org) from org),
		'agreement', (select to_jsonb(agreement) from agreement),
		'edition', (select to_jsonb(edition) from edition),
		'package', (select to_jsonb(package) from package),
		'capabilities', coalesce((
			select jsonb_agg(c.capability_key order by c.sort_order) from public.package_capabilities c
		), '[]'::jsonb),
		'edition_capabilities', coalesce((
			select jsonb_agg(ec.capability_key)
			from public.package_edition_capabilities ec
			where ec.edition_id = (select edition_id from agreement)
		), '[]'::jsonb),
		'capability_exceptions', coalesce((
			select jsonb_agg(jsonb_build_object(
				'capability_key', x.capability_key, 'state', x.capability_state,
				'starts_at', x.starts_at, 'ends_at', x.ends_at, 'reason', x.reason)
				order by x.starts_at desc, x.created_at desc)
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id and x.capability_key is not null
				and x.starts_at <= at and x.ends_at > at
		), '[]'::jsonb),
		'allowance_exceptions', coalesce((
			select jsonb_agg(jsonb_build_object(
				'allowance_key', x.allowance_key, 'state', x.allowance_state, 'value', x.allowance_value,
				'starts_at', x.starts_at, 'ends_at', x.ends_at)
				order by x.starts_at desc, x.created_at desc)
			from public.organization_package_exceptions x
			where x.organization_id = target_organization_id and x.allowance_key is not null
				and x.starts_at <= at and x.ends_at > at
		), '[]'::jsonb),
		'commercial_state', (
			select jsonb_build_object(
				'paid_through_date', cs.paid_through_date, 'paid_through_source', cs.paid_through_source,
				'grace_ends_at', cs.grace_ends_at)
			from public.organization_commercial_state cs
			where cs.organization_id = target_organization_id
		),
		'commercial_settings', (
			select jsonb_build_object('commercial_timezone', st.commercial_timezone)
			from public.organization_commercial_settings st
			where st.organization_id = target_organization_id
		),
		-- Free access is rebuilt in package-builder P5; until then the old grants are still read.
		'free_access_events', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', fe.id, 'target_grant_id', fe.target_grant_id, 'action', fe.action,
				'starts_at', fe.starts_at, 'access_until_date', fe.access_until_date,
				'occurred_at', fe.occurred_at))
			from public.organization_free_access_events fe
			where fe.organization_id = target_organization_id
		), '[]'::jsonb),
		'employee_seat_limit', (
			select to_jsonb(l) from public.organization_allowance(target_organization_id, 'employee_seats', at) l
		),
		'website_chat_widgets_limit', (
			select to_jsonb(l) from public.organization_allowance(target_organization_id, 'website_chat_widgets', at) l
		),
		'marketing_email_limit', (
			select to_jsonb(l) from public.organization_allowance(target_organization_id, 'marketing_email_recipients', at) l
		),
		'membership', (select to_jsonb(membership) from membership),
		'role_permissions', coalesce((
			select jsonb_agg(jsonb_build_object('permission_key', rp.permission_key, 'access_scope', rp.access_scope))
			from public.role_permissions rp
			where rp.role = (select role from membership)
		), '[]'::jsonb),
		'member_permission_overrides', coalesce((
			select jsonb_agg(jsonb_build_object(
				'permission_key', mo.permission_key, 'override_state', mo.override_state,
				'access_scope', mo.access_scope))
			from public.organization_member_permission_overrides mo
			where mo.organization_id = target_organization_id
				and mo.user_id = target_user_id
		), '[]'::jsonb)
	) end;
$$;

-- Adds the charge for the period starting on period_start, priced from the agreement in effect that day.
-- The caller holds the organization lock. Returns null when no agreement covers that day.
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
		agreement.agreed_price_usd_cents, actor_owner_email, idempotency_key
	)
	returning * into inserted;

	return inserted;
end;
$$;

-- The Billing reader skips cancelled moves and adds credit notes, charge kinds, and agreement history.
create or replace function public.owner_organization_billing(target_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	with context as (
		select
			o.id,
			coalesce(cs.commercial_timezone, 'UTC') as commercial_timezone,
			(now() at time zone coalesce(cs.commercial_timezone, 'UTC'))::date as today,
			st.paid_through_date,
			st.grace_ends_at
		from public.organizations o
		left join public.organization_commercial_settings cs on cs.organization_id = o.id
		left join public.organization_commercial_state st on st.organization_id = o.id
		where o.id = target_organization_id
	),
	agreements as (
		select a.*, e.name as edition_name, e.edition_number, p.slug as package_slug,
			a.effective_from <= now() as in_effect
		from public.organization_package_agreements a
		join public.package_editions e on e.id = a.edition_id
		join public.packages p on p.id = e.package_id
		where a.organization_id = target_organization_id
	),
	current_agreement as (
		select * from agreements where in_effect and cancelled_at is null order by effective_from desc, created_at desc limit 1
	),
	voids as (
		select * from public.organization_billing_voids v where v.organization_id = target_organization_id
	),
	applications as (
		select a.*, v.id as void_id, v.reason as void_reason, v.created_at as voided_at
		from public.organization_billing_applications a
		left join voids v on v.application_id = a.id
		where a.organization_id = target_organization_id
	),
	refunds as (
		select f.*, v.id as void_id, v.reason as void_reason, v.created_at as voided_at
		from public.organization_billing_refunds f
		left join voids v on v.refund_id = f.id
		where f.organization_id = target_organization_id
	),
	charges as (
		select c.*,
			v.id as void_id, v.reason as void_reason, v.created_at as voided_at,
			coalesce((select sum(a.amount_usd_cents) from applications a where a.charge_id = c.id and a.void_id is null), 0)::integer
				as applied_usd_cents,
			cc.id as coverage_id, cc.created_at as coverage_confirmed_at
		from public.organization_billing_charges c
		left join voids v on v.charge_id = c.id
		left join public.organization_billing_coverage_confirmations cc on cc.charge_id = c.id
		where c.organization_id = target_organization_id
	),
	credit_notes as (
		select n.*,
			coalesce((select sum(a.amount_usd_cents) from applications a where a.credit_note_id = n.id and a.void_id is null), 0)::integer
				as applied_usd_cents
		from public.organization_billing_credit_notes n
		where n.organization_id = target_organization_id
	),
	receipts as (
		select r.*,
			v.id as void_id, v.reason as void_reason, v.created_at as voided_at,
			coalesce((select sum(a.amount_usd_cents) from applications a where a.receipt_id = r.id and a.void_id is null), 0)::integer
				as applied_usd_cents,
			coalesce((select sum(f.amount_usd_cents) from refunds f where f.receipt_id = r.id and f.void_id is null), 0)::integer
				as refunded_usd_cents
		from public.organization_billing_receipts r
		left join voids v on v.receipt_id = r.id
		where r.organization_id = target_organization_id
	)
	select jsonb_build_object(
		'commercial_timezone', ctx.commercial_timezone,
		'today', ctx.today,
		'paid_through_date', ctx.paid_through_date,
		'grace_ends_at', ctx.grace_ends_at,
		'next_renewal_date', ctx.paid_through_date + 1,
		'renewal_flag', case
			when ctx.paid_through_date is null then null
			when ctx.paid_through_date < ctx.today then 'overdue'
			when ctx.paid_through_date = ctx.today then 'due_tomorrow'
			when ctx.paid_through_date - ctx.today < 7 then 'due_within_seven_days'
		end,
		'current_agreement', (
			select jsonb_build_object(
				'id', ca.id, 'edition_id', ca.edition_id, 'edition_name', ca.edition_name,
				'edition_number', ca.edition_number, 'package_slug', ca.package_slug,
				'billing_interval', ca.billing_interval, 'agreed_price_usd_cents', ca.agreed_price_usd_cents,
				'offer_terms', ca.offer_terms, 'effective_from', ca.effective_from
			)
			from current_agreement ca
		),
		'upcoming_agreements', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', a.id, 'edition_name', a.edition_name, 'edition_number', a.edition_number,
				'billing_interval', a.billing_interval, 'agreed_price_usd_cents', a.agreed_price_usd_cents,
				'effective_from', a.effective_from
			) order by a.effective_from)
			from agreements a where not a.in_effect and a.cancelled_at is null
		), '[]'::jsonb),
		'totals', jsonb_build_object(
			'charged_usd_cents', coalesce((select sum(c.amount_usd_cents) from charges c where c.void_id is null), 0),
			'received_usd_cents', coalesce((select sum(r.amount_usd_cents) from receipts r where r.void_id is null), 0),
			'refunded_usd_cents', coalesce((select sum(r.refunded_usd_cents) from receipts r where r.void_id is null), 0),
			'outstanding_usd_cents', coalesce((
				select sum(c.amount_usd_cents - c.applied_usd_cents) from charges c where c.void_id is null
			), 0),
			'due_now_usd_cents', coalesce((
				select sum(c.amount_usd_cents - c.applied_usd_cents) from charges c
				where c.void_id is null and c.period_start <= ctx.today
			), 0),
			'credit_usd_cents', coalesce((
				select sum(r.amount_usd_cents - r.applied_usd_cents - r.refunded_usd_cents) from receipts r
				where r.void_id is null
			), 0) + coalesce((select sum(n.amount_usd_cents - n.applied_usd_cents) from credit_notes n), 0)
		),
		'charges', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', c.id, 'agreement_id', c.agreement_id, 'period_start', c.period_start,
				'period_end', c.period_end, 'amount_usd_cents', c.amount_usd_cents, 'kind', c.kind,
				'applied_usd_cents', c.applied_usd_cents,
				'outstanding_usd_cents', case when c.void_id is null then c.amount_usd_cents - c.applied_usd_cents else 0 end,
				'status', case
					when c.void_id is not null then 'cancelled'
					when c.applied_usd_cents >= c.amount_usd_cents then 'paid'
					when c.applied_usd_cents > 0 then 'partly_paid'
					else 'unpaid'
				end,
				'coverage_confirmed_at', c.coverage_confirmed_at,
				'void_reason', c.void_reason, 'voided_at', c.voided_at, 'created_at', c.created_at
			) order by c.period_start desc, c.created_at desc)
			from charges c
		), '[]'::jsonb),
		'receipts', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', r.id, 'received_on', r.received_on, 'amount_usd_cents', r.amount_usd_cents,
				'method', r.method, 'private_reference', r.private_reference, 'note', r.note,
				'replaces_receipt_id', r.replaces_receipt_id,
				'applied_usd_cents', r.applied_usd_cents, 'refunded_usd_cents', r.refunded_usd_cents,
				'unapplied_usd_cents', case when r.void_id is null
					then r.amount_usd_cents - r.applied_usd_cents - r.refunded_usd_cents else 0 end,
				'void_reason', r.void_reason, 'voided_at', r.voided_at,
				'actor_owner_email', r.actor_owner_email, 'created_at', r.created_at
			) order by r.received_on desc, r.created_at desc)
			from receipts r
		), '[]'::jsonb),
		'applications', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', a.id, 'receipt_id', a.receipt_id, 'credit_note_id', a.credit_note_id, 'charge_id', a.charge_id,
				'amount_usd_cents', a.amount_usd_cents, 'void_reason', a.void_reason, 'voided_at', a.voided_at,
				'created_at', a.created_at
			) order by a.created_at)
			from applications a
		), '[]'::jsonb),
		'refunds', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', f.id, 'receipt_id', f.receipt_id, 'refunded_on', f.refunded_on,
				'amount_usd_cents', f.amount_usd_cents, 'method', f.method,
				'private_reference', f.private_reference, 'reason', f.reason,
				'void_reason', f.void_reason, 'voided_at', f.voided_at, 'created_at', f.created_at
			) order by f.refunded_on desc, f.created_at desc)
			from refunds f
		), '[]'::jsonb),
		'credit_notes', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', n.id, 'agreement_id', n.agreement_id, 'source_charge_id', n.source_charge_id,
				'unused_from', n.unused_from, 'unused_through', n.unused_through,
				'amount_usd_cents', n.amount_usd_cents, 'applied_usd_cents', n.applied_usd_cents,
				'unapplied_usd_cents', n.amount_usd_cents - n.applied_usd_cents,
				'reason', n.reason, 'created_at', n.created_at
			) order by n.created_at desc)
			from credit_notes n
		), '[]'::jsonb),
		-- Every agreement, cancelled moves included, so earlier terms stay visible.
		'agreement_history', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', a.id, 'edition_id', a.edition_id, 'edition_name', a.edition_name,
				'edition_number', a.edition_number, 'package_slug', a.package_slug,
				'billing_interval', a.billing_interval, 'agreed_price_usd_cents', a.agreed_price_usd_cents,
				'effective_from', a.effective_from, 'source', a.source, 'reason', a.reason,
				'actor_owner_email', a.actor_owner_email, 'created_at', a.created_at,
				'cancelled_at', a.cancelled_at, 'cancel_reason', a.cancel_reason
			) order by a.effective_from desc, a.created_at desc)
			from agreements a
		), '[]'::jsonb),
		'covered_through', cov.covered_through,
		'pauses_at', cov.pauses_at,
		'free_access_today', coalesce(cov.free_access_today, false),
		'free_access', coalesce((
			select jsonb_agg(jsonb_build_object(
				'grant_id', g.grant_id, 'starts_at', g.starts_at, 'last_day', g.last_day,
				'is_current', g.is_current, 'reason', root.reason, 'granted_by', root.actor_owner_email,
				'granted_at', root.occurred_at
			) order by g.starts_at)
			from private.organization_open_free_access(target_organization_id, ctx.today) g
			join public.organization_free_access_events root on root.id = g.grant_id
		), '[]'::jsonb)
	)
	from context ctx
	left join lateral private.organization_access_coverage(target_organization_id) cov on true;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 3. Helpers.
-- ---------------------------------------------------------------------------------------------------

-- The first day of the regular service period that contains `day`, counted from the anchor. Pairs with
-- private.billing_period_end.
create or replace function private.billing_period_start(anchor date, day date, billing_interval text)
returns date
language sql
immutable
set search_path = ''
as $$
	select max(candidate)
	from (
		select (anchor + n * case billing_interval when 'year' then interval '1 year' else interval '1 month' end)::date
			as candidate
		from generate_series(0, 1200) as n
	) as starts
	where candidate <= day;
$$;

-- How much of a counted-at-one-time allowance the organization uses now. Null for allowances that reset
-- monthly: a package change does not cut short a month already under way.
create or replace function private.package_allowance_in_use(target_organization_id uuid, target_allowance_key text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
	select case target_allowance_key
		when 'employee_seats' then private.employee_seats_used(target_organization_id)
		when 'website_chat_widgets' then private.website_chat_widgets_used(target_organization_id)
		when 'automation_active_recipes' then (
			select count(*)::integer from public.automation_recipes r
			where r.organization_id = target_organization_id and r.status = 'active'
		)
	end;
$$;

create or replace function private.billing_credit_note_unapplied(target_credit_note_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
	select n.amount_usd_cents - coalesce((
		select sum(a.amount_usd_cents) from public.organization_billing_applications a
		where a.credit_note_id = n.id
			and not exists (select 1 from public.organization_billing_voids v where v.application_id = a.id)
	), 0)::integer
	from public.organization_billing_credit_notes n
	where n.id = target_credit_note_id;
$$;

-- Applies credit from a credit note to a charge. The caller holds the organization lock.
create or replace function private.apply_organization_billing_credit_note_money(
	target_organization_id uuid,
	source_credit_note_id uuid,
	target_charge_id uuid,
	amount_usd_cents integer,
	actor_owner_email text,
	idempotency_key text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
	charge public.organization_billing_charges;
	available integer;
	outstanding integer;
	inserted_id uuid;
begin
	if amount_usd_cents is null or amount_usd_cents <= 0 then
		raise exception 'The amount to apply must be more than zero.' using errcode = 'check_violation';
	end if;
	if not exists (
		select 1 from public.organization_billing_credit_notes n
		where n.id = source_credit_note_id and n.organization_id = target_organization_id
	) then
		raise exception 'That credit was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;

	select * into charge from public.organization_billing_charges c
	where c.id = target_charge_id and c.organization_id = target_organization_id;
	if charge.id is null then
		raise exception 'That charge was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;
	if exists (select 1 from public.organization_billing_voids v where v.charge_id = charge.id) then
		raise exception 'That charge was cancelled.' using errcode = 'check_violation';
	end if;

	available := private.billing_credit_note_unapplied(source_credit_note_id);
	outstanding := charge.amount_usd_cents - private.billing_charge_applied(charge.id);
	if amount_usd_cents > available then
		raise exception 'Only % cents of that credit is still unapplied.', available using errcode = 'check_violation';
	end if;
	if amount_usd_cents > outstanding then
		raise exception 'Only % cents is still owed on that charge.', outstanding using errcode = 'check_violation';
	end if;

	insert into public.organization_billing_applications (
		organization_id, credit_note_id, charge_id, amount_usd_cents, actor_owner_email, idempotency_key
	) values (
		target_organization_id, source_credit_note_id, charge.id, amount_usd_cents, actor_owner_email, idempotency_key
	)
	returning id into inserted_id;
	return inserted_id;
end;
$$;

revoke all on function private.billing_period_start(date, date, text) from public, anon, authenticated;
revoke all on function private.package_allowance_in_use(uuid, text) from public, anon, authenticated;
revoke all on function private.billing_credit_note_unapplied(uuid) from public, anon, authenticated;
revoke all on function private.apply_organization_billing_credit_note_money(uuid, uuid, uuid, integer, text, text)
	from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 4. The change plan: everything the preview shows and the command re-checks.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.package_change_plan(
	target_organization_id uuid,
	target_edition_id uuid,
	target_billing_interval text,
	target_timing text
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
	if current_agreement.edition_id = proposed.id and not interval_changes then
		blockers := blockers || jsonb_build_object('code', 'same_terms',
			'message', 'The customer already has this package and billing.');
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
					'amount_usd_cents', round(coalesce(price, 0)::numeric * remaining_days / (regular_end - regular_start + 1))::integer);
			else
				new_charge := jsonb_build_object(
					'kind', 'period', 'anchor_date', today, 'period_start', today,
					'period_end', private.billing_period_end(today, today, target_billing_interval),
					'amount_usd_cents', coalesce(price, 0));
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
				'amount_usd_cents', coalesce(price, 0));
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
			'agreed_price_usd_cents', current_agreement.agreed_price_usd_cents) end,
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
		'blockers', blockers
	);
end;
$$;

revoke all on function private.package_change_plan(uuid, uuid, text, text) from public, anon, authenticated;

create or replace function public.owner_package_change_preview(
	target_organization_id uuid,
	target_edition_id uuid,
	billing_interval text,
	timing text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select private.package_change_plan(target_organization_id, target_edition_id, billing_interval, timing);
$$;

-- ---------------------------------------------------------------------------------------------------
-- 5. Commands.
-- ---------------------------------------------------------------------------------------------------

-- Confirms the change Jafar reviewed. The effective date, credit, and new charge must still match the
-- preview; otherwise nothing is written and the preview is shown again.
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
	idempotency_key text
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

	plan := private.package_change_plan(target_organization_id, target_edition_id, billing_interval, timing);
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

	insert into public.organization_package_agreements (
		organization_id, edition_id, billing_interval, agreed_price_usd_cents, offer_terms, service_anchor_date,
		effective_from, source, reason, actor_owner_email, idempotency_key
	) values (
		target_organization_id, target_edition_id, billing_interval, (plan -> 'proposed' ->> 'price_usd_cents')::integer,
		null, current_agreement.service_anchor_date, (plan ->> 'effective_from')::timestamptz, 'package_change',
		trim(reason), actor_owner_email, idempotency_key
	)
	returning * into inserted;

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
			|| (plan ->> 'effective_date') || '.',
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
		'next_charge_id', next_charge.id
	);
end;
$$;

-- Cancels a move that has not started. Its charge at the new price goes back to the current terms.
create or replace function public.cancel_scheduled_package_change(
	target_organization_id uuid,
	agreement_id uuid,
	reason text,
	actor_owner_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing public.organization_package_agreements;
	target public.organization_package_agreements;
	target_name text;
	restart date;
	charge_row record;
	next_charge public.organization_billing_charges;
begin
	perform private.lock_organization_billing(target_organization_id);

	select * into existing from public.organization_package_agreements a
	where a.cancel_idempotency_key = cancel_scheduled_package_change.idempotency_key;
	if existing.id is not null then
		return jsonb_build_object('applied', false, 'agreement_id', existing.id);
	end if;

	if reason is null or char_length(trim(reason)) = 0 then
		raise exception 'Give a reason for cancelling the change.' using errcode = 'check_violation';
	end if;

	select * into target from public.organization_package_agreements a
	where a.id = cancel_scheduled_package_change.agreement_id and a.organization_id = target_organization_id
	for update;
	if target.id is null then
		raise exception 'That scheduled change was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;
	if target.cancelled_at is not null then
		raise exception 'That change is already cancelled.' using errcode = 'check_violation';
	end if;
	if target.effective_from <= now() then
		raise exception 'This change has already started. Change the package again instead.' using errcode = 'check_violation';
	end if;

	if exists (
		select 1 from public.organization_billing_charges c
		where c.agreement_id = target.id
			and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
			and private.billing_charge_applied(c.id) > 0
	) then
		raise exception 'Money is already applied to the charge at the new price. Remove it from that charge first.'
			using errcode = 'check_violation';
	end if;

	select min(c.period_start) into restart from public.organization_billing_charges c
	where c.agreement_id = target.id
		and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id);

	for charge_row in
		select c.id from public.organization_billing_charges c
		where c.agreement_id = target.id
			and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
		order by c.period_start desc
	loop
		insert into public.organization_billing_voids (
			organization_id, charge_id, reason, actor_owner_email, idempotency_key
		) values (
			target_organization_id, charge_row.id, 'The scheduled package change was cancelled.', actor_owner_email,
			idempotency_key || ':void:' || charge_row.id
		);
	end loop;

	update public.organization_package_agreements a
	set cancelled_at = now(), cancel_reason = trim(cancel_scheduled_package_change.reason),
		cancelled_by_email = cancel_scheduled_package_change.actor_owner_email,
		cancel_idempotency_key = cancel_scheduled_package_change.idempotency_key
	where a.id = target.id;

	if restart is not null then
		next_charge := private.add_organization_billing_charge(
			target_organization_id, restart, actor_owner_email, idempotency_key || ':next'
		);
	end if;

	select e.name into target_name from public.package_editions e where e.id = target.edition_id;
	perform public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => 'package_version_changed',
		idempotency_key => idempotency_key,
		summary => 'Scheduled change to ' || target_name || ' cancelled.',
		paid_through_effect => 'unchanged',
		actor_owner_email => actor_owner_email,
		private_reason => trim(reason)
	);

	return jsonb_build_object('applied', true, 'agreement_id', target.id, 'next_charge_id', next_charge.id);
end;
$$;

-- Applies unapplied credit from a package change to a charge.
create or replace function public.apply_organization_billing_credit_note(
	target_organization_id uuid,
	credit_note_id uuid,
	charge_id uuid,
	amount_usd_cents integer,
	actor_owner_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing_id uuid;
	inserted_id uuid;
begin
	perform private.lock_organization_billing(target_organization_id);

	select a.id into existing_id from public.organization_billing_applications a
	where a.idempotency_key = apply_organization_billing_credit_note.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'application_id', existing_id);
	end if;

	inserted_id := private.apply_organization_billing_credit_note_money(
		target_organization_id, credit_note_id, charge_id, amount_usd_cents, actor_owner_email, idempotency_key
	);
	return jsonb_build_object('applied', true, 'application_id', inserted_id);
end;
$$;

-- Adds a temporary exception: one feature switched on or off, or one allowance set, for a reasoned
-- period. Only one exception per feature or allowance may cover any moment.
create or replace function public.add_organization_package_exception(
	target_organization_id uuid,
	capability_key text,
	capability_state text,
	allowance_key text,
	allowance_state text,
	allowance_value integer,
	starts_at timestamptz,
	ends_at timestamptz,
	reason text,
	actor_owner_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing_id uuid;
	capability public.package_capabilities;
	allowance public.package_allowances;
	effective_start timestamptz := greatest(starts_at, now());
	missing_label text;
	dependent_label text;
	overlapping public.organization_package_exceptions;
	in_use integer;
	new_limit integer;
	inserted public.organization_package_exceptions;
begin
	perform private.lock_organization_billing(target_organization_id);

	select x.id into existing_id from public.organization_package_exceptions x
	where x.idempotency_key = add_organization_package_exception.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'exception_id', existing_id);
	end if;

	if (capability_key is null) = (allowance_key is null) then
		raise exception 'Choose one feature or one limit for the exception.' using errcode = 'check_violation';
	end if;
	if reason is null or char_length(trim(reason)) = 0 then
		raise exception 'Give a reason for the exception.' using errcode = 'check_violation';
	end if;
	if starts_at is null or ends_at is null then
		raise exception 'Choose when the exception starts and ends.' using errcode = 'check_violation';
	end if;
	if ends_at <= effective_start then
		raise exception 'The exception must end after it starts, and in the future.' using errcode = 'check_violation';
	end if;

	if capability_key is not null then
		select * into capability from public.package_capabilities c where c.capability_key = add_organization_package_exception.capability_key;
		if capability.capability_key is null then
			raise exception 'That feature was not found.' using errcode = 'foreign_key_violation';
		end if;
		if capability.kind = 'core' then
			raise exception '% is in every package and cannot be changed by an exception.', capability.label
				using errcode = 'check_violation';
		end if;
		if capability.kind = 'planned' then
			raise exception '% is not built yet, so it cannot be switched on or off.', capability.label
				using errcode = 'check_violation';
		end if;
		if capability_state is null or capability_state not in ('on', 'off') then
			raise exception 'Choose whether the feature is switched on or off.' using errcode = 'check_violation';
		end if;

		if capability_state = 'on' then
			select c.label into missing_label
			from public.package_capability_requirements r
			join public.package_capabilities c on c.capability_key = r.required_capability_key
			where r.capability_key = capability.capability_key
				and not private.organization_has_capability(target_organization_id, r.required_capability_key, effective_start)
			limit 1;
			if missing_label is not null then
				raise exception '% needs %. Switch % on first.', capability.label, missing_label, missing_label
					using errcode = 'check_violation';
			end if;
		else
			select c.label into dependent_label
			from public.package_capability_requirements r
			join public.package_capabilities c on c.capability_key = r.capability_key
			where r.required_capability_key = capability.capability_key
				and private.organization_has_capability(target_organization_id, r.capability_key, effective_start)
			limit 1;
			if dependent_label is not null then
				raise exception '% needs %. Switch % off first.', dependent_label, capability.label, dependent_label
					using errcode = 'check_violation';
			end if;
		end if;
	else
		select * into allowance from public.package_allowances a where a.allowance_key = add_organization_package_exception.allowance_key;
		if allowance.allowance_key is null then
			raise exception 'That limit was not found.' using errcode = 'foreign_key_violation';
		end if;
		if allowance_state is null or allowance_state not in ('numeric', 'unlimited', 'not_included') then
			raise exception 'Choose a number, unlimited, or not included.' using errcode = 'check_violation';
		end if;
		if allowance_state = 'numeric' and (allowance_value is null or allowance_value < 0) then
			raise exception 'Enter a number of zero or more.' using errcode = 'check_violation';
		end if;
		in_use := private.package_allowance_in_use(target_organization_id, allowance.allowance_key);
		new_limit := case when allowance_state = 'numeric' then allowance_value else 0 end;
		if in_use is not null and allowance_state <> 'unlimited' and in_use > new_limit then
			raise exception '% % are in use now, so the limit cannot be lower than that.', in_use, allowance.unit
				using errcode = 'check_violation';
		end if;
	end if;

	select * into overlapping from public.organization_package_exceptions x
	where x.organization_id = target_organization_id
		and (x.capability_key = add_organization_package_exception.capability_key
			or x.allowance_key = add_organization_package_exception.allowance_key)
		and x.starts_at < add_organization_package_exception.ends_at and x.ends_at > effective_start
	order by x.starts_at
	limit 1;
	if overlapping.id is not null then
		raise exception 'An exception for this already runs until %. End it first or choose dates after it.',
			to_char(overlapping.ends_at, 'YYYY-MM-DD HH24:MI') || ' UTC'
			using errcode = 'check_violation';
	end if;

	insert into public.organization_package_exceptions (
		organization_id, capability_key, capability_state, allowance_key, allowance_state, allowance_value,
		reason, starts_at, ends_at, actor_owner_email, idempotency_key
	) values (
		target_organization_id, add_organization_package_exception.capability_key,
		case when add_organization_package_exception.capability_key is not null then capability_state end,
		add_organization_package_exception.allowance_key,
		case when add_organization_package_exception.allowance_key is not null then allowance_state end,
		case when add_organization_package_exception.allowance_key is not null and allowance_state = 'numeric'
			then allowance_value end,
		trim(reason), effective_start, ends_at, actor_owner_email, idempotency_key
	)
	returning * into inserted;

	perform public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => case when inserted.capability_key is not null then 'feature_exception_changed' else 'limit_exception_changed' end,
		idempotency_key => idempotency_key,
		summary => coalesce(capability.label, allowance.label) || ' exception added until '
			|| to_char(inserted.ends_at, 'YYYY-MM-DD HH24:MI') || ' UTC.',
		paid_through_effect => 'unchanged',
		actor_owner_email => actor_owner_email,
		private_reason => trim(reason),
		safe_kind => case when inserted.capability_key is not null then 'feature_access_changed' else 'limit_access_changed' end,
		safe_payload => case when inserted.capability_key is not null
			then jsonb_build_object('feature_key', inserted.capability_key, 'effective_at', inserted.starts_at)
			else jsonb_build_object('limit_key', inserted.allowance_key, 'limit_state', inserted.allowance_state,
				'limit_value', inserted.allowance_value, 'effective_at', inserted.starts_at)
		end
	);

	return jsonb_build_object('applied', true, 'exception_id', inserted.id);
end;
$$;

-- Ends an exception early. One that has not started keeps its record with an empty period.
create or replace function public.end_organization_package_exception(
	target_organization_id uuid,
	exception_id uuid,
	reason text,
	actor_owner_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	target public.organization_package_exceptions;
	label text;
begin
	perform private.lock_organization_billing(target_organization_id);

	select * into target from public.organization_package_exceptions x
	where x.id = end_organization_package_exception.exception_id and x.organization_id = target_organization_id
	for update;
	if target.id is null then
		raise exception 'That exception was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;
	if target.ended_early_at is not null then
		return jsonb_build_object('applied', false, 'exception_id', target.id);
	end if;
	if reason is null or char_length(trim(reason)) = 0 then
		raise exception 'Give a reason for ending the exception.' using errcode = 'check_violation';
	end if;
	if target.ends_at <= now() then
		raise exception 'This exception has already ended.' using errcode = 'check_violation';
	end if;

	update public.organization_package_exceptions x
	set ends_at = greatest(x.starts_at, now()), ended_early_at = now(),
		end_reason = trim(end_organization_package_exception.reason),
		ended_by_email = end_organization_package_exception.actor_owner_email
	where x.id = target.id;

	select coalesce(
		(select c.label from public.package_capabilities c where c.capability_key = target.capability_key),
		(select a.label from public.package_allowances a where a.allowance_key = target.allowance_key)
	) into label;

	perform public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => case when target.capability_key is not null then 'feature_exception_changed' else 'limit_exception_changed' end,
		idempotency_key => idempotency_key,
		summary => label || ' exception ended early.',
		paid_through_effect => 'unchanged',
		actor_owner_email => actor_owner_email,
		private_reason => trim(reason),
		safe_kind => case when target.capability_key is not null then 'feature_access_changed' else 'limit_access_changed' end,
		safe_payload => case when target.capability_key is not null
			then jsonb_build_object('feature_key', target.capability_key, 'effective_at', now())
			else jsonb_build_object('limit_key', target.allowance_key, 'effective_at', now())
		end
	);

	return jsonb_build_object('applied', true, 'exception_id', target.id);
end;
$$;

-- Every exception the organization has had, newest first, with labels, for Jafar's Access tab.
create or replace function public.owner_organization_package_exceptions(target_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(jsonb_build_object(
		'id', x.id,
		'capability_key', x.capability_key, 'capability_state', x.capability_state,
		'allowance_key', x.allowance_key, 'allowance_state', x.allowance_state, 'allowance_value', x.allowance_value,
		'label', coalesce(c.label, a.label), 'unit', a.unit,
		'reason', x.reason, 'starts_at', x.starts_at, 'ends_at', x.ends_at,
		'status', case
			when x.ended_early_at is not null and x.ends_at = x.starts_at then 'cancelled'
			when x.ends_at <= now() then 'ended'
			when x.starts_at > now() then 'scheduled'
			else 'active'
		end,
		'ended_early_at', x.ended_early_at, 'end_reason', x.end_reason, 'ended_by_email', x.ended_by_email,
		'actor_owner_email', x.actor_owner_email, 'created_at', x.created_at
	) order by x.starts_at desc, x.created_at desc), '[]'::jsonb)
	from public.organization_package_exceptions x
	left join public.package_capabilities c on c.capability_key = x.capability_key
	left join public.package_allowances a on a.allowance_key = x.allowance_key
	where x.organization_id = target_organization_id;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 6. Only the owner service role runs the preview, the commands, and the readers.
-- ---------------------------------------------------------------------------------------------------

revoke all on function public.owner_package_change_preview(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.change_organization_package(uuid, uuid, text, text, date, integer, integer, text, text, text)
	from public, anon, authenticated;
revoke all on function public.cancel_scheduled_package_change(uuid, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.apply_organization_billing_credit_note(uuid, uuid, uuid, integer, text, text)
	from public, anon, authenticated;
revoke all on function public.add_organization_package_exception(uuid, text, text, text, text, integer, timestamptz, timestamptz, text, text, text)
	from public, anon, authenticated;
revoke all on function public.end_organization_package_exception(uuid, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.owner_organization_package_exceptions(uuid) from public, anon, authenticated;

grant execute on function public.owner_package_change_preview(uuid, uuid, text, text) to service_role;
grant execute on function public.change_organization_package(uuid, uuid, text, text, date, integer, integer, text, text, text)
	to service_role;
grant execute on function public.cancel_scheduled_package_change(uuid, uuid, text, text, text) to service_role;
grant execute on function public.apply_organization_billing_credit_note(uuid, uuid, uuid, integer, text, text) to service_role;
grant execute on function public.add_organization_package_exception(uuid, text, text, text, text, integer, timestamptz, timestamptz, text, text, text)
	to service_role;
grant execute on function public.end_organization_package_exception(uuid, uuid, text, text, text) to service_role;
grant execute on function public.owner_organization_package_exceptions(uuid) to service_role;
