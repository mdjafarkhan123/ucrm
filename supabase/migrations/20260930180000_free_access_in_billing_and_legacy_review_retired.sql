-- Package builder P5c: free access moves to the Billing workspace, and the legacy pending-setup review is retired.
--
-- 1. Riverside Legacy Demo, the last organization left in `pending_setup` from the retired direct-create path, is
--    resolved to active (it already has an owner and a package agreement), with a reasoned history row.
-- 2. `pending_setup` is no longer an organization status, and organizations have no default status: the
--    rebuilt activation path (P10) must name one.
-- 3. A manual reactivation after a nonpayment or payment-dispute pause is allowed when coverage
--    (`private.organization_access_coverage`, P5a) says access has not yet paused or free access covers today.
--    This replaces the older inline free-access check, which still treated grants with no end date as forever.
-- 4. The directory loses its legacy-review flag and pending-setup count.
-- 5. The Billing reader adds covered-through, the pause moment, and the current and later free-access grants.

-- ---------------------------------------------------------------------------------------------------
-- 1. Resolve Riverside Legacy Demo.
-- ---------------------------------------------------------------------------------------------------

do $$
declare
	legacy record;
begin
	for legacy in select o.id from public.organizations o where o.lifecycle_status = 'pending_setup' loop
		perform public.apply_organization_commercial_command(
			target_organization_id => legacy.id,
			event_kind => 'pending_setup_resolved',
			idempotency_key => 'p5c-legacy-review-retired-' || legacy.id,
			summary => 'Legacy organization reviewed and activated.',
			paid_through_effect => 'unchanged',
			actor_owner_email => 'dev.jafarkhan@gmail.com',
			private_reason => 'The legacy pending-setup review is retired (package builder P5c). This test organization already has an owner and a package agreement.'
		);
		update public.organizations set lifecycle_status = 'active', updated_at = now() where id = legacy.id;
	end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 2. No more pending_setup status.
-- ---------------------------------------------------------------------------------------------------

alter table public.organizations alter column lifecycle_status drop default;
alter table public.organizations drop constraint organizations_lifecycle_status_check;
alter table public.organizations add constraint organizations_lifecycle_status_check
	check (lifecycle_status in ('active', 'suspended', 'pending_closure', 'closed'));

-- ---------------------------------------------------------------------------------------------------
-- 3. Manual lifecycle changes: coverage decides whether a payment pause may be lifted by hand.
-- ---------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_organization_lifecycle_change(target_organization_id uuid, target_status text, target_suspension_category text, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_state public.organization_commercial_state%rowtype;
  existing_event public.organization_commercial_events%rowtype;
  organization_row public.organizations%rowtype;
  inserted_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  last_suspension public.organization_commercial_events%rowtype;
  coverage record;
  active_owner_count integer;
begin
  if target_status not in ('active', 'suspended') then
    raise exception 'The organization status is invalid.' using errcode = 'check_violation';
  end if;
  if target_status = 'suspended'
     and coalesce(target_suspension_category, '') not in ('nonpayment', 'payment_dispute', 'security', 'support', 'other') then
    raise exception 'A suspension requires a valid category.' using errcode = 'check_violation';
  end if;
  if target_status = 'active' and target_suspension_category is not null then
    raise exception 'Reactivation cannot include a suspension category.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A private reason is required for a lifecycle change.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'Lifecycle changes cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  select * into current_state
  from public.organization_commercial_state
  where organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_lifecycle_change.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'change_after', existing_event.change_after);
  end if;

  select * into organization_row
  from public.organizations
  where id = target_organization_id
  for update;
  if not found then
    raise exception 'Organization was not found.' using errcode = 'foreign_key_violation';
  end if;

  if organization_row.lifecycle_status = target_status then
    raise exception 'The organization already has this status.' using errcode = 'check_violation';
  end if;

  if target_status = 'active' then
    select count(*) into active_owner_count
    from public.organization_members
    where organization_id = target_organization_id and role = 'owner';
    if active_owner_count = 0 then
      raise exception 'Invite the first administrator before activation.' using errcode = 'check_violation';
    end if;

    select * into last_suspension
    from public.organization_commercial_events
    where organization_id = target_organization_id
      and event_kind = 'organization_suspended'
    order by organization_commercial_events.occurred_at desc, organization_commercial_events.id desc
    limit 1;

    -- A payment pause is lifted by hand only while paid-through or free access still covers the day (P5a).
    if found and last_suspension.suspension_category in ('nonpayment', 'payment_dispute') then
      select * into coverage from private.organization_access_coverage(target_organization_id, command_time);
      if not (coalesce(coverage.free_access_today, false) or coalesce(coverage.pauses_at > command_time, false)) then
        raise exception 'Restore paid-through eligibility or active free access before reactivating.'
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    suspension_category, paid_through_effect, paid_through_before, paid_through_after,
    grace_ends_at_after, change_before, change_after, idempotency_key
  ) values (
    target_organization_id,
    case when target_status = 'suspended' then 'organization_suspended' else 'organization_reactivated' end,
    command_time, trim(actor_owner_email),
    case when target_status = 'suspended' then 'Organization suspended.' else 'Organization reactivated.' end,
    trim(private_reason),
    case when target_status = 'suspended' then target_suspension_category else null end,
    'unchanged', current_state.paid_through_date, current_state.paid_through_date, current_state.grace_ends_at,
    jsonb_build_object('lifecycle_status', organization_row.lifecycle_status),
    jsonb_build_object('lifecycle_status', target_status),
    idempotency_key
  ) returning * into inserted_event;

  update public.organizations
  set lifecycle_status = target_status, updated_at = now()
  where id = target_organization_id;

  update public.organization_commercial_state
  set last_event_id = inserted_event.id,
      state_version = current_state.state_version + 1
  where organization_id = target_organization_id
    and state_version = current_state.state_version;
  if not found then
    raise exception 'The commercial state changed during this command. Retry the command.'
      using errcode = 'P0409';
  end if;

  insert into public.organization_safe_events (
    organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at
  ) values (
    target_organization_id, inserted_event.id,
    case when target_status = 'suspended' then 'account_suspended' else 'account_reactivated' end,
    jsonb_build_object('access_status', target_status),
    command_time
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'lifecycle_status', target_status);
end;
$function$;

-- ---------------------------------------------------------------------------------------------------
-- 4. The directory without the legacy review.
-- ---------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."owner_organization_directory"("search_term" "text" DEFAULT NULL::"text", "attention_reason" "text" DEFAULT NULL::"text", "cursor_created_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_id" "uuid" DEFAULT NULL::"uuid", "page_size" integer DEFAULT 50) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
  with org_context as (
    select
      o.id,
      o.name,
      o.slug,
      o.lifecycle_status,
      o.created_at,
      o.updated_at,
      coalesce(cs.commercial_timezone, 'UTC') as commercial_timezone,
      (now() at time zone coalesce(cs.commercial_timezone, 'UTC'))::date as today_date,
      st.paid_through_date,
      st.grace_ends_at
    from public.organizations o
    left join public.organization_commercial_settings cs on cs.organization_id = o.id
    left join public.organization_commercial_state st on st.organization_id = o.id
  ),
  member_counts as (
    select
      organization_id,
      count(*) as member_count,
      count(*) filter (where role = 'owner') as owner_count
    from public.organization_members
    group by organization_id
  ),
  free_access_latest as (
    select distinct on (event.organization_id, coalesce(event.target_grant_id, event.id))
      event.organization_id,
      event.action,
      event.starts_at,
      event.access_until_date
    from public.organization_free_access_events event
    order by event.organization_id, coalesce(event.target_grant_id, event.id), event.occurred_at desc, event.id desc
  ),
  free_access_summary as (
    select
      oc.id as organization_id,
      coalesce(bool_or(
        fal.action <> 'end'
        and fal.starts_at <= oc.today_date
        and (fal.access_until_date is null or fal.access_until_date >= oc.today_date)
      ), false) as free_access_active,
      coalesce(bool_or(
        fal.action <> 'end'
        and fal.starts_at <= oc.today_date
        and fal.access_until_date is not null
        and fal.access_until_date >= oc.today_date
        and (fal.access_until_date - oc.today_date) <= 7
      ), false) as free_access_expiring_soon
    from org_context oc
    left join free_access_latest fal on fal.organization_id = oc.id
    group by oc.id
  ),
  package_exception_summary as (
    select
      oc.id as organization_id,
      exists (
        select 1 from public.organization_package_exceptions x
        where x.organization_id = oc.id
          and x.starts_at <= now()
          and x.ends_at > now()
          and ((x.ends_at at time zone oc.commercial_timezone)::date - oc.today_date) between 0 and 7
      ) as package_exception_expiring_soon
    from org_context oc
  ),
  setup_recovery_summary as (
    select
      oc.id as organization_id,
      exists (
        select 1 from public.platform_operation_attempts op
        where op.target_kind = 'organization'
          and op.target_id = oc.id
          and op.status in ('pending', 'retrying')
      ) as setup_or_recovery_failed
    from org_context oc
  ),
  owner_emails as (
    select
      m.organization_id,
      array_agg(distinct u.email) filter (where u.email is not null) as owner_email_list
    from public.organization_members m
    join auth.users u on u.id = m.user_id
    where m.role = 'owner'
    group by m.organization_id
  ),
  computed as (
    select
      oc.id,
      oc.name,
      oc.slug,
      oc.lifecycle_status,
      oc.created_at,
      oc.updated_at,
      coalesce(mc.member_count, 0) as member_count,
      coalesce(mc.owner_count, 0) as owner_count,
      oc.today_date,
      oc.paid_through_date,
      oc.grace_ends_at,
      (
        oc.paid_through_date is not null
        and (oc.paid_through_date >= oc.today_date or (oc.grace_ends_at is not null and oc.grace_ends_at >= now()))
      ) as paid_through_eligible,
      coalesce(fas.free_access_active, false) as free_access_active,
      coalesce(fas.free_access_expiring_soon, false) as free_access_expiring_soon,
      coalesce(pes.package_exception_expiring_soon, false) as package_exception_expiring_soon,
      coalesce(srs.setup_or_recovery_failed, false) as setup_or_recovery_failed,
      exists (
        select 1 from public.communication_email_setup_requests_waiting w
        where w.organization_id = oc.id
      ) as email_setup_requested,
      coalesce(oe.owner_email_list, array[]::text[]) as owner_email_list
    from org_context oc
    left join member_counts mc on mc.organization_id = oc.id
    left join free_access_summary fas on fas.organization_id = oc.id
    left join package_exception_summary pes on pes.organization_id = oc.id
    left join setup_recovery_summary srs on srs.organization_id = oc.id
    left join owner_emails oe on oe.organization_id = oc.id
  ),
  reasoned as (
    select
      c.*,
      (c.lifecycle_status = 'active' and not c.paid_through_eligible and not c.free_access_active)
        as is_access_overdue,
      (c.lifecycle_status = 'active' and not c.free_access_active
        and c.paid_through_date is not null
        and c.paid_through_date - c.today_date between 0 and 6) as is_renewal_due,
      (c.lifecycle_status = 'active' and not c.free_access_active
        and c.paid_through_date is not null
        and c.paid_through_date < c.today_date
        and c.grace_ends_at is not null and c.grace_ends_at >= now()) as is_payment_overdue,
      (c.free_access_expiring_soon or c.package_exception_expiring_soon) as is_expiring_soon,
      (c.owner_count = 0) as is_administrator_missing,
      (c.owner_count > 1) as is_administrator_ownership_unclear,
      c.setup_or_recovery_failed as is_setup_or_recovery_failed,
      c.email_setup_requested as is_email_setup_requested
    from computed c
  ),
  tagged as (
    select
      r.*,
      array_remove(
        array[
          case when is_access_overdue then 'access_overdue' end,
          case when is_payment_overdue then 'payment_overdue' end,
          case when is_renewal_due then 'renewal_due' end,
          case when is_administrator_missing then 'administrator_missing' end,
          case when is_administrator_ownership_unclear then 'administrator_ownership_unclear' end,
          case when is_setup_or_recovery_failed then 'setup_or_recovery_failed' end,
          case when is_expiring_soon then 'expiring_soon' end,
          case when is_email_setup_requested then 'email_setup_requested' end
        ],
        null
      ) as attention_reasons
    from reasoned r
  ),
  matching as (
    select t.*
    from tagged t
    where
      search_term is null
      or trim(search_term) = ''
      or t.name ilike '%' || search_term || '%'
      or t.slug ilike '%' || search_term || '%'
      or exists (select 1 from unnest(t.owner_email_list) as email where email ilike '%' || search_term || '%')
  ),
  filtered as (
    select m.*
    from matching m
    where attention_reason is null or attention_reason = any(m.attention_reasons)
  ),
  page as (
    select f.*
    from filtered f
    where cursor_created_at is null or (f.created_at, f.id) < (cursor_created_at, cursor_id)
    order by f.created_at desc, f.id desc
    limit least(greatest(coalesce(page_size, 50), 1), 100)
  ),
  page_meta as (
    select count(*) as returned_count from page
  ),
  page_last as (
    select created_at, id from page order by created_at asc, id asc limit 1
  ),
  totals as (
    select
      count(*) as all_count,
      count(*) filter (where lifecycle_status = 'active') as active_count,
      count(*) filter (where lifecycle_status = 'suspended') as suspended_count,
      count(*) filter (where is_access_overdue) as access_overdue_count,
      count(*) filter (where is_payment_overdue) as payment_overdue_count,
      count(*) filter (where is_renewal_due) as renewal_due_count,
      count(*) filter (where is_expiring_soon) as expiring_soon_count,
      count(*) filter (where is_administrator_missing) as administrator_missing_count,
      count(*) filter (where is_administrator_ownership_unclear) as administrator_ownership_unclear_count,
      count(*) filter (where is_setup_or_recovery_failed) as setup_or_recovery_failed_count,
      count(*) filter (where is_email_setup_requested) as email_setup_requested_count
    from tagged
  ),
  matching_totals as (
    select count(*) as matching_count from filtered
  )
  select jsonb_build_object(
    'organizations', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'name', p.name,
            'slug', p.slug,
            'lifecycle_status', p.lifecycle_status,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'member_count', p.member_count,
            'attention_reasons', to_jsonb(p.attention_reasons)
          )
          order by p.created_at desc, p.id desc
        )
        from page p
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select returned_count from page_meta) >= least(greatest(coalesce(page_size, 50), 1), 100)
        then (select jsonb_build_object('created_at', pl.created_at, 'id', pl.id) from page_last pl)
      else null
    end,
    'totals', jsonb_build_object(
      'all', (select all_count from totals),
      'active', (select active_count from totals),
      'suspended', (select suspended_count from totals),
      'matching', (select matching_count from matching_totals),
      'attention', jsonb_build_object(
        'access_overdue', (select access_overdue_count from totals),
        'payment_overdue', (select payment_overdue_count from totals),
        'renewal_due', (select renewal_due_count from totals),
        'expiring_soon', (select expiring_soon_count from totals),
        'administrator_missing', (select administrator_missing_count from totals),
        'administrator_ownership_unclear', (select administrator_ownership_unclear_count from totals),
        'setup_or_recovery_failed', (select setup_or_recovery_failed_count from totals),
        'email_setup_requested', (select email_setup_requested_count from totals)
      )
    )
  );
$$;

-- ---------------------------------------------------------------------------------------------------
-- 5. The Billing reader adds coverage and free access.
-- ---------------------------------------------------------------------------------------------------

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
		select * from agreements where in_effect order by effective_from desc, created_at desc limit 1
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
			from agreements a where not a.in_effect
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
			), 0)
		),
		'charges', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', c.id, 'agreement_id', c.agreement_id, 'period_start', c.period_start,
				'period_end', c.period_end, 'amount_usd_cents', c.amount_usd_cents,
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
				'id', a.id, 'receipt_id', a.receipt_id, 'charge_id', a.charge_id,
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
