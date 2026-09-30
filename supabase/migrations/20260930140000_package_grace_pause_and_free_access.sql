-- Package builder P5a (ADR 0003, decision 9): the grace week, the automatic pause when it ends unpaid, and
-- free access rebuilt as dated coverage without payment.
--
-- Covered dates are paid-through plus any free access that has started. Access continues for seven
-- calendar days after the last covered day, to the end of that local day in the commercial time zone.
-- A scheduled job then pauses the organization (suspension category `nonpayment`, system actor).
-- Confirming coverage, correcting paid-through, or granting free access that covers today lifts a
-- nonpayment pause at once; the job also lifts its own pauses when later free access begins. Security,
-- support, dispute, and other pauses are never lifted by these paths.

-- ---------------------------------------------------------------------------------------------------
-- 1. Free access always has an end date (Jafar, 2026-09-30), so there is no "forever" action. The two
-- open-ended test grants from P3b are history, so the dated rule applies to new rows only (NOT VALID) and
-- each gets a dated extension.
-- ---------------------------------------------------------------------------------------------------

alter table public.organization_free_access_events
	drop constraint organization_free_access_events_action_check,
	drop constraint organization_free_access_event_state_check;

alter table public.organization_free_access_events
	add constraint organization_free_access_events_action_check
		check (action in ('grant', 'extend', 'end')),
	add constraint organization_free_access_event_dated_check
		check ((action = 'end' and access_until_date is null)
			or (action in ('grant', 'extend') and access_until_date is not null)) not valid;

insert into public.organization_free_access_events (
	organization_id, action, starts_at, access_until_date, target_grant_id, reason, actor_kind,
	actor_owner_email
)
select root.organization_id, 'extend', root.starts_at, date '2027-09-30', root.id,
	'Free access now always has an end date (package builder P5a, Jafar 2026-09-30).',
	'platform_owner', 'dev.jafarkhan@gmail.com'
from public.organization_free_access_events as root
where root.target_grant_id is null
	and root.access_until_date is null
	and not exists (
		select 1 from public.organization_free_access_events as later
		where later.target_grant_id = root.id
	);

-- ---------------------------------------------------------------------------------------------------
-- 2. Coverage: the last covered day, the moment access pauses, and whether free access covers today.
-- ---------------------------------------------------------------------------------------------------

-- Each free-access grant that has started, with the last day it covers. An ended grant covers through the
-- local day it was ended; one ended before it started covers nothing and is dropped.
create or replace function private.organization_free_access_days(target_organization_id uuid, today date)
returns table (grant_id uuid, starts_at date, last_day date)
language sql
stable
set search_path = ''
as $$
	with zone as (
		select coalesce((select s.commercial_timezone from public.organization_commercial_settings s
			where s.organization_id = target_organization_id), 'UTC') as name
	), chains as (
		select root.id, root.starts_at,
			coalesce((
				select e.access_until_date
				from public.organization_free_access_events e
				where e.organization_id = target_organization_id
					and coalesce(e.target_grant_id, e.id) = root.id and e.action <> 'end'
				order by e.occurred_at desc, e.id desc
				limit 1
			), 'infinity'::date) as until_date,
			(
				select (e.occurred_at at time zone (select name from zone))::date
				from public.organization_free_access_events e
				where e.organization_id = target_organization_id
					and e.target_grant_id = root.id and e.action = 'end'
				order by e.occurred_at, e.id
				limit 1
			) as ended_day
		from public.organization_free_access_events root
		where root.organization_id = target_organization_id
			and root.target_grant_id is null
			and root.starts_at <= today
	)
	select id, starts_at, last_day
	from (
		select id, starts_at, least(until_date, coalesce(ended_day, 'infinity'::date)) as last_day
		from chains
	) as days
	where last_day >= starts_at;
$$;

create or replace function private.organization_access_coverage(
	target_organization_id uuid,
	at timestamptz default now()
)
returns table (covered_through date, pauses_at timestamptz, free_access_today boolean)
language sql
stable
set search_path = ''
as $$
	with zone as (
		select coalesce((select s.commercial_timezone from public.organization_commercial_settings s
			where s.organization_id = target_organization_id), 'UTC') as name
	), today as (
		select (at at time zone (select name from zone))::date as value
	), free as (
		select max(f.last_day) as last_day,
			coalesce(bool_or(f.last_day >= (select value from today)), false) as covers_today
		from private.organization_free_access_days(target_organization_id, (select value from today)) f
	), covered as (
		select greatest(
			(select st.paid_through_date from public.organization_commercial_state st
				where st.organization_id = target_organization_id),
			(select last_day from free)
		) as value
	)
	select c.value,
		case
			when c.value is null then null
			when c.value = 'infinity'::date then 'infinity'::timestamptz
			else private.organization_grace_ends_at(c.value, (select name from zone))
		end,
		(select covers_today from free)
	from covered c;
$$;

comment on function private.organization_access_coverage(uuid, timestamptz) is
	'Last covered day (paid-through or started free access), when access pauses (end of the seventh local day after it), and whether free access covers today. Null covered_through means the organization was never covered.';

-- ---------------------------------------------------------------------------------------------------
-- 3. Pause and restore for nonpayment, by the system. The caller holds the organization billing lock.
-- ---------------------------------------------------------------------------------------------------

create or replace function private.set_organization_nonpayment_pause(
	target_organization_id uuid,
	pause boolean,
	private_reason text
)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
	state public.organization_commercial_state;
	organization_row public.organizations;
	inserted_id uuid;
begin
	select * into state from public.organization_commercial_state s
	where s.organization_id = target_organization_id for update;
	select * into organization_row from public.organizations o
	where o.id = target_organization_id for update;

	if organization_row.lifecycle_status is distinct from (case when pause then 'active' else 'suspended' end) then
		return false;
	end if;

	insert into public.organization_commercial_events (
		organization_id, event_kind, actor_kind, actor_owner_email, summary, private_reason,
		suspension_category, paid_through_effect, paid_through_before, paid_through_after,
		grace_ends_at_after, change_before, change_after, idempotency_key
	) values (
		target_organization_id,
		case when pause then 'organization_suspended' else 'organization_reactivated' end,
		'system', null,
		case when pause then 'Access paused: the grace week ended unpaid.'
			else 'Access restored: coverage is in place again.' end,
		private_reason,
		case when pause then 'nonpayment' end,
		'unchanged', state.paid_through_date, state.paid_through_date, state.grace_ends_at,
		jsonb_build_object('lifecycle_status', organization_row.lifecycle_status),
		jsonb_build_object('lifecycle_status', case when pause then 'suspended' else 'active' end),
		(case when pause then 'nonpayment-pause:' else 'nonpayment-restore:' end)
			|| target_organization_id || ':v' || state.state_version
	)
	returning id into inserted_id;

	update public.organizations
	set lifecycle_status = case when pause then 'suspended' else 'active' end, updated_at = now()
	where id = target_organization_id;

	update public.organization_commercial_state
	set last_event_id = inserted_id, state_version = state.state_version + 1
	where organization_id = target_organization_id;

	insert into public.organization_safe_events (organization_id, commercial_event_id, safe_kind, safe_payload)
	values (
		target_organization_id, inserted_id,
		case when pause then 'account_suspended' else 'account_reactivated' end,
		jsonb_build_object('access_status', case when pause then 'suspended' else 'active' end)
	);
	return true;
end;
$$;

-- The latest pause, when the organization is paused for nonpayment; null otherwise.
create or replace function private.organization_nonpayment_pause(target_organization_id uuid)
returns public.organization_commercial_events
language sql
stable
set search_path = ''
as $$
	select e.*
	from public.organization_commercial_events e
	join public.organizations o on o.id = e.organization_id and o.lifecycle_status = 'suspended'
	where e.organization_id = target_organization_id
		and e.event_kind = 'organization_suspended'
		and e.suspension_category = 'nonpayment'
		and not exists (
			select 1 from public.organization_commercial_events later
			where later.organization_id = e.organization_id
				and later.event_kind = 'organization_suspended'
				and (later.occurred_at, later.id) > (e.occurred_at, e.id)
		)
	order by e.occurred_at desc, e.id desc
	limit 1;
$$;

-- Called by every command that adds coverage, after it has written. Lifts a nonpayment pause, from the
-- system or from Jafar, when access is covered again. Other pauses stay.
create or replace function private.restore_access_if_covered(target_organization_id uuid, private_reason text)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
	if (private.organization_nonpayment_pause(target_organization_id)).id is null then
		return false;
	end if;
	if not coalesce((select c.pauses_at > now() from private.organization_access_coverage(target_organization_id) c), false) then
		return false;
	end if;
	return private.set_organization_nonpayment_pause(target_organization_id, false, private_reason);
end;
$$;

-- The scheduled sweep. Pauses active organizations whose grace has ended and lifts the system's own
-- nonpayment pauses once later free access covers them. Each organization runs under its own lock and
-- its own subtransaction, so one failure does not stop the rest.
create or replace function private.enforce_package_grace()
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
	candidate record;
	paused integer := 0;
	restored integer := 0;
	failed integer := 0;
begin
	for candidate in
		-- Free access only adds coverage, so an active organization whose paid grace is still running is
		-- skipped without working out its free access.
		select o.id, o.lifecycle_status
		from public.organizations o
		left join public.organization_commercial_state st on st.organization_id = o.id
		where (o.lifecycle_status = 'active' and (st.grace_ends_at is null or st.grace_ends_at <= now())
				and (select c.pauses_at <= now() from private.organization_access_coverage(o.id) c))
			or (o.lifecycle_status = 'suspended'
				and (private.organization_nonpayment_pause(o.id)).actor_kind = 'system'
				and (select c.pauses_at > now() from private.organization_access_coverage(o.id) c))
	loop
		begin
			perform private.lock_organization_billing(candidate.id);
			if candidate.lifecycle_status = 'active' then
				if coalesce((select c.pauses_at <= now() from private.organization_access_coverage(candidate.id) c), false)
					and private.set_organization_nonpayment_pause(candidate.id, true,
						'The seven-day grace week after the last covered day ended without payment.') then
					paused := paused + 1;
				end if;
			elsif private.restore_access_if_covered(candidate.id, 'Free access now covers these dates.') then
				restored := restored + 1;
			end if;
		exception when others then
			failed := failed + 1;
			raise warning 'Package grace enforcement failed for organization %: %', candidate.id, sqlerrm;
		end;
	end loop;
	return jsonb_build_object('paused', paused, 'restored', restored, 'failed', failed);
end;
$$;

revoke all on function private.organization_free_access_days(uuid, date) from public, anon, authenticated;
revoke all on function private.organization_access_coverage(uuid, timestamptz) from public, anon, authenticated;
revoke all on function private.set_organization_nonpayment_pause(uuid, boolean, text) from public, anon, authenticated;
revoke all on function private.organization_nonpayment_pause(uuid) from public, anon, authenticated;
revoke all on function private.restore_access_if_covered(uuid, text) from public, anon, authenticated;
revoke all on function private.enforce_package_grace() from public, anon, authenticated;

-- Grace ends at local midnight, and some time zones are offset by 30 or 45 minutes.
select cron.schedule('package-grace-enforcement', '*/15 * * * *', $job$select private.enforce_package_grace();$job$);

-- ---------------------------------------------------------------------------------------------------
-- 4. Coverage and paid-through commands lift a nonpayment pause.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.confirm_organization_billing_coverage(
	target_organization_id uuid,
	charge_id uuid,
	covered_from date,
	covered_through date,
	actor_owner_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	state public.organization_commercial_state;
	existing public.organization_billing_coverage_confirmations;
	charge public.organization_billing_charges;
	command_result jsonb;
	next_charge public.organization_billing_charges;
	inserted_id uuid;
	restored boolean;
begin
	state := private.lock_organization_billing(target_organization_id);

	select * into existing from public.organization_billing_coverage_confirmations cc
	where cc.idempotency_key = confirm_organization_billing_coverage.idempotency_key;
	if existing.id is not null then
		return jsonb_build_object('applied', false, 'confirmation_id', existing.id,
			'paid_through_date', state.paid_through_date);
	end if;

	select * into charge from public.organization_billing_charges c
	where c.id = confirm_organization_billing_coverage.charge_id and c.organization_id = target_organization_id;
	if charge.id is null then
		raise exception 'That charge was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;
	if exists (select 1 from public.organization_billing_voids v where v.charge_id = charge.id) then
		raise exception 'That charge was cancelled.' using errcode = 'check_violation';
	end if;
	if exists (select 1 from public.organization_billing_coverage_confirmations cc where cc.charge_id = charge.id) then
		raise exception 'This charge''s dates are already confirmed as covered.' using errcode = 'check_violation';
	end if;
	if covered_from is distinct from charge.period_start or covered_through is distinct from charge.period_end then
		raise exception 'The dates to cover no longer match this charge. Review them and try again.'
			using errcode = 'P0409';
	end if;
	if private.billing_charge_applied(charge.id) < charge.amount_usd_cents then
		raise exception 'This charge is not fully paid yet, so its dates cannot be confirmed as covered.'
			using errcode = 'check_violation';
	end if;
	if state.paid_through_date is not null and charge.period_end <= state.paid_through_date then
		raise exception 'Access is already paid through %, which includes this period.', state.paid_through_date
			using errcode = 'check_violation';
	end if;

	command_result := public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => 'coverage_confirmed',
		idempotency_key => idempotency_key,
		summary => 'Coverage confirmed from ' || to_char(charge.period_start, 'YYYY-MM-DD')
			|| ' through ' || to_char(charge.period_end, 'YYYY-MM-DD') || '.',
		paid_through_effect => 'set',
		paid_through_date => charge.period_end,
		actor_owner_email => actor_owner_email,
		amount_usd_cents => nullif(charge.amount_usd_cents, 0),
		safe_kind => 'access_period_updated',
		safe_payload => jsonb_build_object('paid_through_date', charge.period_end)
	);

	insert into public.organization_billing_coverage_confirmations (
		organization_id, charge_id, covered_from, covered_through, commercial_event_id,
		actor_owner_email, idempotency_key
	) values (
		target_organization_id, charge.id, charge.period_start, charge.period_end,
		(command_result ->> 'event_id')::uuid, actor_owner_email, idempotency_key
	)
	returning id into inserted_id;

	if not exists (
		select 1 from public.organization_billing_charges c
		where c.organization_id = target_organization_id and c.period_end > charge.period_end
			and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
	) then
		next_charge := private.add_organization_billing_charge(
			target_organization_id, charge.period_end + 1, actor_owner_email, idempotency_key || ':next'
		);
	end if;

	restored := private.restore_access_if_covered(target_organization_id, 'Payment confirmed and coverage restored.');

	return jsonb_build_object(
		'applied', true,
		'confirmation_id', inserted_id,
		'paid_through_date', command_result ->> 'paid_through_date',
		'grace_ends_at', command_result ->> 'grace_ends_at',
		'next_charge_id', next_charge.id,
		'access_restored', restored
	);
end;
$$;

create or replace function public.adjust_organization_paid_through(
	target_organization_id uuid,
	paid_through_date date,
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
	command_result jsonb;
begin
	perform private.lock_organization_billing(target_organization_id);
	command_result := public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => 'paid_through_adjusted',
		idempotency_key => idempotency_key,
		summary => 'Paid-through date corrected to ' || to_char(paid_through_date, 'YYYY-MM-DD') || '.',
		paid_through_effect => 'set',
		paid_through_date => paid_through_date,
		actor_owner_email => actor_owner_email,
		private_reason => trim(reason),
		safe_kind => 'access_period_updated',
		safe_payload => jsonb_build_object('paid_through_date', paid_through_date)
	);
	if (command_result ->> 'applied')::boolean then
		command_result := command_result || jsonb_build_object('access_restored',
			private.restore_access_if_covered(target_organization_id, 'Paid-through date corrected.'));
	end if;
	return command_result;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 5. Free access commands: grant, extend, end. One current grant and one later non-overlapping grant.
-- ---------------------------------------------------------------------------------------------------

-- The current and the later grant, each with its start and last covered day. Grants that ended or ran out
-- before today are neither.
create or replace function private.organization_open_free_access(target_organization_id uuid, today date)
returns table (grant_id uuid, starts_at date, last_day date, is_current boolean)
language sql
stable
set search_path = ''
as $$
	select root.id, root.starts_at, latest.access_until_date, root.starts_at <= today
	from public.organization_free_access_events root
	cross join lateral (
		select e.action, e.access_until_date
		from public.organization_free_access_events e
		where e.organization_id = target_organization_id and coalesce(e.target_grant_id, e.id) = root.id
		order by e.occurred_at desc, e.id desc
		limit 1
	) latest
	where root.organization_id = target_organization_id
		and root.target_grant_id is null
		and latest.action <> 'end'
		and coalesce(latest.access_until_date, 'infinity'::date) >= today;
$$;

create or replace function private.record_free_access_event(
	target_organization_id uuid,
	action text,
	grant_id uuid,
	starts_at date,
	access_until_date date,
	reason text,
	actor_owner_email text,
	idempotency_key text
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
	inserted public.organization_free_access_events;
	command_result jsonb;
begin
	insert into public.organization_free_access_events (
		organization_id, action, starts_at, access_until_date, target_grant_id, reason, actor_owner_email
	) values (
		target_organization_id, action, starts_at, access_until_date, grant_id, trim(reason), trim(actor_owner_email)
	)
	returning * into inserted;

	command_result := public.apply_organization_commercial_command(
		target_organization_id => target_organization_id,
		event_kind => case action when 'grant' then 'free_access_granted' when 'extend' then 'free_access_extended'
			else 'free_access_ended' end,
		idempotency_key => idempotency_key,
		summary => case action
			when 'grant' then 'Free access granted from ' || to_char(starts_at, 'YYYY-MM-DD')
				|| ' through ' || to_char(access_until_date, 'YYYY-MM-DD') || '.'
			when 'extend' then 'Free access extended through ' || to_char(access_until_date, 'YYYY-MM-DD') || '.'
			else 'Free access ended.' end,
		paid_through_effect => 'unchanged',
		actor_owner_email => trim(actor_owner_email),
		private_reason => trim(reason),
		safe_kind => 'free_access_updated',
		safe_payload => jsonb_build_object('free_access_until_date', access_until_date)
	);

	return jsonb_build_object(
		'applied', true,
		'grant_id', coalesce(grant_id, inserted.id),
		'event_id', command_result ->> 'event_id',
		'access_restored', private.restore_access_if_covered(target_organization_id, 'Free access granted.')
	);
end;
$$;

create or replace function private.check_free_access_command(reason text, actor_owner_email text, idempotency_key text)
returns void
language plpgsql
set search_path = ''
as $$
begin
	if char_length(trim(coalesce(reason, ''))) not between 1 and 500 then
		raise exception 'A reason is required for a free access change.' using errcode = 'check_violation';
	end if;
	if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
		raise exception 'An acting owner email is required.' using errcode = 'check_violation';
	end if;
	if char_length(trim(coalesce(idempotency_key, ''))) not between 8 and 200 then
		raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
	end if;
end;
$$;

create or replace function public.grant_organization_free_access(
	target_organization_id uuid,
	starts_on date,
	ends_on date,
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
	today date;
	existing_id uuid;
	current_grant record;
	later_grant record;
begin
	perform private.check_free_access_command(reason, actor_owner_email, idempotency_key);
	perform private.lock_organization_billing(target_organization_id);

	select e.id into existing_id from public.organization_commercial_events e
	where e.organization_id = target_organization_id
		and e.idempotency_key = grant_organization_free_access.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'event_id', existing_id);
	end if;

	today := private.organization_commercial_today(target_organization_id);
	if starts_on is null or starts_on < today then
		raise exception 'Free access must start today or later.' using errcode = 'check_violation';
	end if;
	if ends_on is null or ends_on < starts_on then
		raise exception 'Free access needs an end date on or after its start date.' using errcode = 'check_violation';
	end if;

	select * into current_grant from private.organization_open_free_access(target_organization_id, today) g
	where g.is_current;
	select * into later_grant from private.organization_open_free_access(target_organization_id, today) g
	where not g.is_current;

	if starts_on <= today then
		if current_grant.grant_id is not null then
			raise exception 'Free access is already running. Extend it instead.' using errcode = 'check_violation';
		end if;
		if later_grant.grant_id is not null and ends_on >= later_grant.starts_at then
			raise exception 'This would overlap the free access already starting on %.', later_grant.starts_at
				using errcode = 'check_violation';
		end if;
	else
		if later_grant.grant_id is not null then
			raise exception 'Later free access is already scheduled. Change or end it instead.'
				using errcode = 'check_violation';
		end if;
		if current_grant.grant_id is not null and starts_on <= current_grant.last_day then
			raise exception 'This would overlap the current free access, which runs through %.', current_grant.last_day
				using errcode = 'check_violation';
		end if;
	end if;

	return private.record_free_access_event(target_organization_id, 'grant', null, starts_on, ends_on, reason,
		actor_owner_email, idempotency_key);
end;
$$;

create or replace function public.extend_organization_free_access(
	target_organization_id uuid,
	grant_id uuid,
	ends_on date,
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
	today date;
	existing_id uuid;
	target_grant record;
	later_grant record;
begin
	perform private.check_free_access_command(reason, actor_owner_email, idempotency_key);
	perform private.lock_organization_billing(target_organization_id);

	select e.id into existing_id from public.organization_commercial_events e
	where e.organization_id = target_organization_id
		and e.idempotency_key = extend_organization_free_access.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'event_id', existing_id);
	end if;

	today := private.organization_commercial_today(target_organization_id);
	select * into target_grant from private.organization_open_free_access(target_organization_id, today) g
	where g.grant_id = extend_organization_free_access.grant_id;
	if target_grant.grant_id is null then
		raise exception 'That free access has ended or was not found.' using errcode = 'check_violation';
	end if;
	if ends_on is null or ends_on <= target_grant.last_day then
		raise exception 'The new end date must be later than %.', target_grant.last_day using errcode = 'check_violation';
	end if;
	if target_grant.is_current then
		select * into later_grant from private.organization_open_free_access(target_organization_id, today) g
		where not g.is_current;
		if later_grant.grant_id is not null and ends_on >= later_grant.starts_at then
			raise exception 'This would overlap the free access already starting on %.', later_grant.starts_at
				using errcode = 'check_violation';
		end if;
	end if;

	return private.record_free_access_event(target_organization_id, 'extend', target_grant.grant_id,
		target_grant.starts_at, ends_on, reason, actor_owner_email, idempotency_key);
end;
$$;

create or replace function public.end_organization_free_access(
	target_organization_id uuid,
	grant_id uuid,
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
	today date;
	existing_id uuid;
	target_grant record;
begin
	perform private.check_free_access_command(reason, actor_owner_email, idempotency_key);
	perform private.lock_organization_billing(target_organization_id);

	select e.id into existing_id from public.organization_commercial_events e
	where e.organization_id = target_organization_id
		and e.idempotency_key = end_organization_free_access.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'event_id', existing_id);
	end if;

	today := private.organization_commercial_today(target_organization_id);
	select * into target_grant from private.organization_open_free_access(target_organization_id, today) g
	where g.grant_id = end_organization_free_access.grant_id;
	if target_grant.grant_id is null then
		raise exception 'That free access has already ended or was not found.' using errcode = 'check_violation';
	end if;

	return private.record_free_access_event(target_organization_id, 'end', target_grant.grant_id,
		target_grant.starts_at, null, reason, actor_owner_email, idempotency_key);
end;
$$;

revoke all on function private.organization_open_free_access(uuid, date) from public, anon, authenticated;
revoke all on function private.record_free_access_event(uuid, text, uuid, date, date, text, text, text)
	from public, anon, authenticated;
revoke all on function private.check_free_access_command(text, text, text) from public, anon, authenticated;
revoke all on function public.grant_organization_free_access(uuid, date, date, text, text, text)
	from public, anon, authenticated;
revoke all on function public.extend_organization_free_access(uuid, uuid, date, text, text, text)
	from public, anon, authenticated;
revoke all on function public.end_organization_free_access(uuid, uuid, text, text, text)
	from public, anon, authenticated;
grant execute on function public.grant_organization_free_access(uuid, date, date, text, text, text) to service_role;
grant execute on function public.extend_organization_free_access(uuid, uuid, date, text, text, text) to service_role;
grant execute on function public.end_organization_free_access(uuid, uuid, text, text, text) to service_role;
