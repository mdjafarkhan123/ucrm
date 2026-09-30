-- Package builder P11b: a scheduled package change carries the intro offer it claimed or kept, so the
-- Billing tab can show the price the customer really pays from that date. Only the upcoming agreements'
-- `offer_terms` is new; the rest of owner_organization_billing is unchanged from 20261001100000.

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
				'effective_from', a.effective_from, 'offer_terms', a.offer_terms,
				'over_limits', private.package_agreement_over_limits(a.id)
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
