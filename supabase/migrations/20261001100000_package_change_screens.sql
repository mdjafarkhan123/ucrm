-- Package builder P8b: what Jafar's screens need beyond the P8a rules.
--
-- 1. The Packages page and the builder count current customers: organizations whose agreement in effect is
--    on the package, or that are scheduled to move onto it. Organizations that have moved away no longer
--    count (the P8a catalog counted everyone who ever agreed).
-- 2. A scheduled move lists what is over its limits right now, so Jafar's Billing tab can warn when a
--    customer has gone over a smaller package's limits again before its start date. Existing items keep
--    working either way; the warning tells Jafar to sort it out before the date.

create or replace function private.package_customer_count(target_package_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
	select count(distinct a.organization_id)::integer
	from public.organization_package_agreements a
	join public.package_editions e on e.id = a.edition_id
	where e.package_id = target_package_id
		and a.cancelled_at is null
		and (
			a.effective_from > now()
			or a.id = (
				select c.id from public.organization_package_agreements c
				where c.organization_id = a.organization_id and c.effective_from <= now() and c.cancelled_at is null
				order by c.effective_from desc, c.created_at desc
				limit 1
			)
		);
$$;

revoke all on function private.package_customer_count(uuid) from public, anon, authenticated;

-- Each counted limit where what is in use now is above what the agreement will allow when it starts. An
-- exception running on that date still applies on top, as in the change preview.
create or replace function private.package_agreement_over_limits(target_agreement_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(jsonb_build_object(
		'allowance_key', pa.allowance_key, 'label', pa.label, 'unit', pa.unit,
		'in_use', usage.in_use, 'limit', resolved.limit_value
	) order by pa.sort_order), '[]'::jsonb)
	from public.organization_package_agreements a
	cross join public.package_allowances pa
	left join public.package_edition_allowances ea
		on ea.edition_id = a.edition_id and ea.allowance_key = pa.allowance_key
	left join lateral (
		select x.allowance_state, x.allowance_value
		from public.organization_package_exceptions x
		where x.organization_id = a.organization_id and x.allowance_key = pa.allowance_key
			and x.starts_at <= a.effective_from and x.ends_at > a.effective_from
		order by x.starts_at desc, x.created_at desc
		limit 1
	) x on true
	cross join lateral (
		select coalesce(x.allowance_state, ea.allowance_state, 'not_included') as state,
			case coalesce(x.allowance_state, ea.allowance_state, 'not_included')
				when 'numeric' then case when x.allowance_state is not null then x.allowance_value else ea.allowance_value end
				else 0
			end as limit_value
	) resolved
	cross join lateral (
		select private.package_allowance_in_use(a.organization_id, pa.allowance_key) as in_use
	) usage
	where a.id = target_agreement_id
		and usage.in_use is not null
		and resolved.state <> 'unlimited'
		and usage.in_use > resolved.limit_value;
$$;

revoke all on function private.package_agreement_over_limits(uuid) from public, anon, authenticated;

create or replace function public.owner_package_catalog()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(row_json order by display_order, created_at), '[]'::jsonb)
	from (
		select
			p.display_order,
			p.created_at,
			jsonb_build_object(
				'id', p.id,
				'slug', p.slug,
				'visibility', p.visibility,
				'display_order', p.display_order,
				'archived_at', p.archived_at,
				'created_at', p.created_at,
				'website_update_pending_since', p.website_update_pending_since,
				'website_changes', case when p.website_update_pending_since is null then '[]'::jsonb else (
					select coalesce(jsonb_agg(jsonb_build_object(
						'event_type', ev.event_type, 'edition_number', ev.edition_number, 'detail', ev.detail,
						'created_at', ev.created_at
					) order by ev.created_at), '[]'::jsonb)
					from public.package_catalog_events ev
					where ev.package_id = p.id and ev.created_at >= p.website_update_pending_since
						and ev.event_type in ('published', 'visibility_changed', 'moved', 'archived', 'restored')
				) end,
				'draft', (
					select jsonb_build_object(
						'edition_id', d.id, 'revision', d.revision, 'name', d.name,
						'monthly_price_usd_cents', d.monthly_price_usd_cents,
						'yearly_price_usd_cents', d.yearly_price_usd_cents,
						'updated_at', d.updated_at
					)
					from public.package_editions d
					where d.package_id = p.id and d.status = 'draft'
				),
				'published', (
					select jsonb_build_object(
						'edition_id', pe.id, 'edition_number', pe.edition_number, 'name', pe.name,
						'monthly_price_usd_cents', pe.monthly_price_usd_cents,
						'yearly_price_usd_cents', pe.yearly_price_usd_cents,
						'published_at', pe.published_at
					)
					from public.package_editions pe
					where pe.package_id = p.id and pe.status = 'published'
				),
				'organization_count', private.package_customer_count(p.id)
			) as row_json
		from public.packages p
	) as rows;
$$;


create or replace function public.owner_package_builder(target_package_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'package', jsonb_build_object(
			'id', p.id,
			'slug', p.slug,
			'visibility', p.visibility,
			'archived_at', p.archived_at,
			'website_update_pending_since', p.website_update_pending_since,
			'ever_published', exists (
				select 1 from public.package_editions e where e.package_id = p.id and e.status <> 'draft'
			),
			'organization_count', private.package_customer_count(p.id),
			'email_template_count', (
				select count(*) from public.platform_email_template_packages t where t.package_id = p.id
			)
		),
		'draft', (
			select private.package_edition_terms(d.id)
				|| jsonb_build_object('publish_problems', private.package_publish_problems(d.id))
			from public.package_editions d where d.package_id = p.id and d.status = 'draft'
		),
		'published', (
			select private.package_edition_terms(pe.id)
			from public.package_editions pe where pe.package_id = p.id and pe.status = 'published'
		),
		'history', private.package_history(p.id),
		'capabilities', (
			select coalesce(jsonb_agg(jsonb_build_object(
				'key', c.capability_key, 'label', c.label, 'description', c.description, 'kind', c.kind,
				'sellable', c.sellable,
				'requires', coalesce((
					select jsonb_agg(r.required_capability_key order by r.required_capability_key)
					from public.package_capability_requirements r where r.capability_key = c.capability_key
				), '[]'::jsonb)
			) order by c.sort_order), '[]'::jsonb)
			from public.package_capabilities c
		),
		'allowances', (
			select coalesce(jsonb_agg(jsonb_build_object(
				'key', a.allowance_key, 'capability_key', a.capability_key, 'label', a.label, 'unit', a.unit,
				'resets_monthly', a.resets_monthly
			) order by a.sort_order), '[]'::jsonb)
			from public.package_allowances a
		)
	)
	from public.packages p
	where p.id = target_package_id;
$$;


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
				'effective_from', a.effective_from,
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

