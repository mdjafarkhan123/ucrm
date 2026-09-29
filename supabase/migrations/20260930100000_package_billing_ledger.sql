-- Package builder P4a: the offsite billing ledger (ADR 0003 decision 6).
--
-- A charge is the amount due for one service period. A receipt is money Jafar confirms he received
-- offsite. An application moves part of a receipt onto a charge; whatever a receipt has not applied or
-- refunded is credit. Refunds and voids are new reasoned records, and nothing is edited or deleted.
-- Paid-through moves only through an explicit coverage confirmation, which also adds the next period's
-- charge. Every command locks the organization's commercial-state row first and carries an idempotency key.
--
-- The receipt-only payment tables and the late-renewal command are removed; P5 rebuilds reactivation.

-- ---------------------------------------------------------------------------------------------------
-- 1. Remove the old payment storage.
-- ---------------------------------------------------------------------------------------------------

drop function public.apply_organization_late_renewal_reactivation(
	uuid, text, text, text, date, text, timestamptz, text, text, integer, uuid, boolean, text, jsonb
);
drop table public.organization_payment_confirmations;
drop function private.prevent_organization_payment_confirmation_mutation();
drop table public.organization_billing_accounts;

-- Coverage confirmations join the commercial history as their own event kind.
alter table public.organization_commercial_events
	drop constraint organization_commercial_events_event_kind_check,
	add constraint organization_commercial_events_event_kind_check check (event_kind = any (array[
		'initial_payment_confirmed', 'renewal_confirmed', 'coverage_confirmed', 'payment_correction_recorded',
		'refund_recorded', 'payment_reversal_recorded', 'paid_through_adjusted', 'commercial_timezone_changed',
		'free_access_granted', 'free_access_extended', 'free_access_converted_forever', 'free_access_ended',
		'organization_suspended', 'organization_reactivated', 'pending_setup_resolved', 'package_version_changed',
		'feature_exception_changed', 'limit_exception_changed', 'organization_closure_started',
		'organization_closure_restored', 'organization_closure_completed'
	]));

-- ---------------------------------------------------------------------------------------------------
-- 2. Ledger tables.
-- ---------------------------------------------------------------------------------------------------

create table public.organization_billing_charges (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	agreement_id uuid not null references public.organization_package_agreements (id) on delete cascade,
	-- Monthly periods count from the anchor so a period starting on the 31st does not drift.
	anchor_date date not null,
	period_start date not null,
	period_end date not null,
	amount_usd_cents integer not null check (amount_usd_cents >= 0),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now(),
	check (period_end >= period_start and period_start >= anchor_date)
);

create index organization_billing_charges_org_idx
	on public.organization_billing_charges (organization_id, period_start desc);
create index organization_billing_charges_agreement_idx on public.organization_billing_charges (agreement_id);

create table public.organization_billing_receipts (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	received_on date not null,
	amount_usd_cents integer not null check (amount_usd_cents > 0),
	method text not null check (char_length(trim(method)) between 1 and 80),
	private_reference text not null check (char_length(trim(private_reference)) between 1 and 240),
	note text check (note is null or char_length(trim(note)) between 1 and 1000),
	-- A corrected receipt names the voided receipt it replaces, so the two show side by side.
	replaces_receipt_id uuid unique references public.organization_billing_receipts (id),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now(),
	check (replaces_receipt_id <> id)
);

create index organization_billing_receipts_org_idx
	on public.organization_billing_receipts (organization_id, received_on desc, created_at desc);

create table public.organization_billing_applications (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	receipt_id uuid not null references public.organization_billing_receipts (id),
	charge_id uuid not null references public.organization_billing_charges (id),
	amount_usd_cents integer not null check (amount_usd_cents > 0),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now()
);

create index organization_billing_applications_receipt_idx on public.organization_billing_applications (receipt_id);
create index organization_billing_applications_charge_idx on public.organization_billing_applications (charge_id);
create index organization_billing_applications_org_idx on public.organization_billing_applications (organization_id);

create table public.organization_billing_refunds (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	receipt_id uuid not null references public.organization_billing_receipts (id),
	refunded_on date not null,
	amount_usd_cents integer not null check (amount_usd_cents > 0),
	method text not null check (char_length(trim(method)) between 1 and 80),
	private_reference text check (private_reference is null or char_length(trim(private_reference)) between 1 and 240),
	reason text not null check (char_length(trim(reason)) between 1 and 1000),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now()
);

create index organization_billing_refunds_receipt_idx on public.organization_billing_refunds (receipt_id);
create index organization_billing_refunds_org_idx on public.organization_billing_refunds (organization_id);

-- A void cancels exactly one earlier record, with a reason. The record stays; it no longer counts.
create table public.organization_billing_voids (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	charge_id uuid unique references public.organization_billing_charges (id),
	receipt_id uuid unique references public.organization_billing_receipts (id),
	application_id uuid unique references public.organization_billing_applications (id),
	refund_id uuid unique references public.organization_billing_refunds (id),
	reason text not null check (char_length(trim(reason)) between 1 and 1000),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now(),
	check (num_nonnulls(charge_id, receipt_id, application_id, refund_id) = 1)
);

create index organization_billing_voids_org_idx on public.organization_billing_voids (organization_id);

-- Jafar's confirmation that one paid charge's exact dates are covered; it moved paid-through.
create table public.organization_billing_coverage_confirmations (
	id uuid primary key default gen_random_uuid(),
	organization_id uuid not null references public.organizations (id) on delete cascade,
	charge_id uuid not null unique references public.organization_billing_charges (id),
	covered_from date not null,
	covered_through date not null,
	commercial_event_id uuid not null unique references public.organization_commercial_events (id),
	actor_owner_email text not null check (char_length(trim(actor_owner_email)) between 3 and 320),
	idempotency_key text not null unique check (char_length(trim(idempotency_key)) between 8 and 200),
	created_at timestamptz not null default now(),
	check (covered_through >= covered_from)
);

create index organization_billing_coverage_org_idx on public.organization_billing_coverage_confirmations (organization_id);

-- Append-only: only an organization purge may remove ledger rows.
create or replace function private.prevent_organization_billing_ledger_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	if tg_op = 'DELETE' and current_setting('app.organization_purge_in_progress', true) = 'true' then
		return old;
	end if;
	raise exception 'Billing records cannot be changed or deleted. Record a correction instead.'
		using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_organization_billing_ledger_change() from public, anon, authenticated;

create trigger organization_billing_charges_append_only before update or delete on public.organization_billing_charges
	for each row execute function private.prevent_organization_billing_ledger_change();
create trigger organization_billing_receipts_append_only before update or delete on public.organization_billing_receipts
	for each row execute function private.prevent_organization_billing_ledger_change();
create trigger organization_billing_applications_append_only before update or delete on public.organization_billing_applications
	for each row execute function private.prevent_organization_billing_ledger_change();
create trigger organization_billing_refunds_append_only before update or delete on public.organization_billing_refunds
	for each row execute function private.prevent_organization_billing_ledger_change();
create trigger organization_billing_voids_append_only before update or delete on public.organization_billing_voids
	for each row execute function private.prevent_organization_billing_ledger_change();
create trigger organization_billing_coverage_append_only before update or delete on public.organization_billing_coverage_confirmations
	for each row execute function private.prevent_organization_billing_ledger_change();

-- Money is Jafar's business record: only the owner service role reads or writes it.
alter table public.organization_billing_charges enable row level security;
alter table public.organization_billing_receipts enable row level security;
alter table public.organization_billing_applications enable row level security;
alter table public.organization_billing_refunds enable row level security;
alter table public.organization_billing_voids enable row level security;
alter table public.organization_billing_coverage_confirmations enable row level security;

revoke all on public.organization_billing_charges, public.organization_billing_receipts,
	public.organization_billing_applications, public.organization_billing_refunds,
	public.organization_billing_voids, public.organization_billing_coverage_confirmations
	from anon, authenticated;
grant all on public.organization_billing_charges, public.organization_billing_receipts,
	public.organization_billing_applications, public.organization_billing_refunds,
	public.organization_billing_voids, public.organization_billing_coverage_confirmations
	to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. Helpers.
-- ---------------------------------------------------------------------------------------------------

-- The end of the service period that starts on period_start, counted from the anchor.
create or replace function private.billing_period_end(anchor date, period_start date, billing_interval text)
returns date
language sql
immutable
set search_path = ''
as $$
	select min(candidate)
	from (
		select (anchor + n * case billing_interval when 'year' then interval '1 year' else interval '1 month' end)::date - 1
			as candidate
		from generate_series(1, 1200) as n
	) as ends
	where candidate >= period_start;
$$;

create or replace function private.billing_charge_applied(target_charge_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
	select coalesce(sum(a.amount_usd_cents), 0)::integer
	from public.organization_billing_applications a
	where a.charge_id = target_charge_id
		and not exists (select 1 from public.organization_billing_voids v where v.application_id = a.id);
$$;

-- Money on a receipt that is neither applied to a charge nor refunded: the receipt's credit.
create or replace function private.billing_receipt_unapplied(target_receipt_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
	select r.amount_usd_cents
		- coalesce((
			select sum(a.amount_usd_cents) from public.organization_billing_applications a
			where a.receipt_id = r.id
				and not exists (select 1 from public.organization_billing_voids v where v.application_id = a.id)
		), 0)
		- coalesce((
			select sum(f.amount_usd_cents) from public.organization_billing_refunds f
			where f.receipt_id = r.id
				and not exists (select 1 from public.organization_billing_voids v where v.refund_id = f.id)
		), 0)
	from public.organization_billing_receipts r
	where r.id = target_receipt_id;
$$;

-- Locks the organization's commercial row so money commands for one organization run one at a time.
create or replace function private.lock_organization_billing(target_organization_id uuid)
returns public.organization_commercial_state
language plpgsql
set search_path = ''
as $$
declare
	state public.organization_commercial_state;
begin
	perform private.ensure_organization_commercial_rows(target_organization_id);
	select * into state
	from public.organization_commercial_state s
	where s.organization_id = target_organization_id
	for update;
	return state;
end;
$$;

create or replace function private.organization_commercial_today(target_organization_id uuid)
returns date
language sql
stable
set search_path = ''
as $$
	select (now() at time zone coalesce(
		(select s.commercial_timezone from public.organization_commercial_settings s
			where s.organization_id = target_organization_id),
		'UTC'
	))::date;
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

-- Applies money from a receipt to a charge. The caller holds the organization lock.
create or replace function private.apply_organization_billing_money(
	target_organization_id uuid,
	source_receipt_id uuid,
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
	receipt_available integer;
	charge_outstanding integer;
	inserted_id uuid;
begin
	if amount_usd_cents is null or amount_usd_cents <= 0 then
		raise exception 'The amount to apply must be more than zero.' using errcode = 'check_violation';
	end if;

	select * into charge from public.organization_billing_charges c
	where c.id = target_charge_id and c.organization_id = target_organization_id;
	if charge.id is null then
		raise exception 'That charge was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;
	if exists (select 1 from public.organization_billing_voids v where v.charge_id = charge.id) then
		raise exception 'That charge was cancelled.' using errcode = 'check_violation';
	end if;

	if not exists (
		select 1 from public.organization_billing_receipts r
		where r.id = source_receipt_id and r.organization_id = target_organization_id
	) then
		raise exception 'That payment was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;
	if exists (select 1 from public.organization_billing_voids v where v.receipt_id = source_receipt_id) then
		raise exception 'That payment was cancelled.' using errcode = 'check_violation';
	end if;

	receipt_available := private.billing_receipt_unapplied(source_receipt_id);
	charge_outstanding := charge.amount_usd_cents - private.billing_charge_applied(charge.id);

	if amount_usd_cents > receipt_available then
		raise exception 'Only % cents of that payment is still unapplied.', receipt_available
			using errcode = 'check_violation';
	end if;
	if amount_usd_cents > charge_outstanding then
		raise exception 'Only % cents is still owed on that charge.', charge_outstanding
			using errcode = 'check_violation';
	end if;

	insert into public.organization_billing_applications (
		organization_id, receipt_id, charge_id, amount_usd_cents, actor_owner_email, idempotency_key
	) values (
		target_organization_id, source_receipt_id, charge.id, amount_usd_cents, actor_owner_email, idempotency_key
	)
	returning id into inserted_id;

	return inserted_id;
end;
$$;

revoke all on function private.billing_period_end(date, date, text) from public, anon, authenticated;
revoke all on function private.billing_charge_applied(uuid) from public, anon, authenticated;
revoke all on function private.billing_receipt_unapplied(uuid) from public, anon, authenticated;
revoke all on function private.lock_organization_billing(uuid) from public, anon, authenticated;
revoke all on function private.organization_commercial_today(uuid) from public, anon, authenticated;
revoke all on function private.add_organization_billing_charge(uuid, date, text, text) from public, anon, authenticated;
revoke all on function private.apply_organization_billing_money(uuid, uuid, uuid, integer, text, text)
	from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 4. Owner commands. Each returns { applied, ... }; a repeated idempotency key returns applied = false.
-- ---------------------------------------------------------------------------------------------------

-- Adds the next charge. period_start is required for the first charge or to restart after a break;
-- otherwise the charge follows on from the last one.
create or replace function public.add_organization_billing_charge(
	target_organization_id uuid,
	actor_owner_email text,
	idempotency_key text,
	period_start date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing public.organization_billing_charges;
	last_end date;
	inserted public.organization_billing_charges;
begin
	perform private.lock_organization_billing(target_organization_id);

	select * into existing from public.organization_billing_charges c
	where c.idempotency_key = add_organization_billing_charge.idempotency_key;
	if existing.id is not null then
		return jsonb_build_object('applied', false, 'charge_id', existing.id);
	end if;

	select max(c.period_end) into last_end
	from public.organization_billing_charges c
	where c.organization_id = target_organization_id
		and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id);

	if period_start is null and last_end is null then
		raise exception 'Choose the date the first service period starts.' using errcode = 'check_violation';
	end if;

	inserted := private.add_organization_billing_charge(
		target_organization_id, coalesce(period_start, last_end + 1), actor_owner_email, idempotency_key
	);
	if inserted.id is null then
		raise exception 'This organization has no package agreement in effect on that date.'
			using errcode = 'check_violation';
	end if;

	return jsonb_build_object('applied', true, 'charge_id', inserted.id);
end;
$$;

-- Records money received offsite and, optionally, applies it to charges in the same step.
-- applications is a JSON array of { "charge_id": uuid, "amount_usd_cents": integer }.
create or replace function public.record_organization_billing_receipt(
	target_organization_id uuid,
	received_on date,
	amount_usd_cents integer,
	method text,
	private_reference text,
	actor_owner_email text,
	idempotency_key text,
	note text default null,
	applications jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing_id uuid;
	inserted_id uuid;
	application jsonb;
	application_number integer := 0;
begin
	perform private.lock_organization_billing(target_organization_id);

	select r.id into existing_id from public.organization_billing_receipts r
	where r.idempotency_key = record_organization_billing_receipt.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'receipt_id', existing_id);
	end if;

	if received_on > private.organization_commercial_today(target_organization_id) then
		raise exception 'The date received cannot be in the future.' using errcode = 'check_violation';
	end if;
	if jsonb_typeof(coalesce(applications, '[]'::jsonb)) <> 'array' then
		raise exception 'Applications must be a list.' using errcode = 'check_violation';
	end if;

	insert into public.organization_billing_receipts (
		organization_id, received_on, amount_usd_cents, method, private_reference, note,
		actor_owner_email, idempotency_key
	) values (
		target_organization_id, received_on, amount_usd_cents, trim(method), trim(private_reference),
		nullif(trim(coalesce(note, '')), ''), actor_owner_email, idempotency_key
	)
	returning id into inserted_id;

	for application in select * from jsonb_array_elements(coalesce(applications, '[]'::jsonb)) loop
		application_number := application_number + 1;
		perform private.apply_organization_billing_money(
			target_organization_id, inserted_id, (application ->> 'charge_id')::uuid,
			(application ->> 'amount_usd_cents')::integer, actor_owner_email,
			idempotency_key || ':apply:' || application_number
		);
	end loop;

	return jsonb_build_object('applied', true, 'receipt_id', inserted_id);
end;
$$;

-- Applies a payment's unapplied money (credit) to a charge.
create or replace function public.apply_organization_billing_credit(
	target_organization_id uuid,
	receipt_id uuid,
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
	where a.idempotency_key = apply_organization_billing_credit.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'application_id', existing_id);
	end if;

	inserted_id := private.apply_organization_billing_money(
		target_organization_id, receipt_id, charge_id, amount_usd_cents, actor_owner_email, idempotency_key
	);
	return jsonb_build_object('applied', true, 'application_id', inserted_id);
end;
$$;

-- Records money returned offsite from a payment's unapplied money.
create or replace function public.record_organization_billing_refund(
	target_organization_id uuid,
	receipt_id uuid,
	refunded_on date,
	amount_usd_cents integer,
	method text,
	reason text,
	actor_owner_email text,
	idempotency_key text,
	private_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing_id uuid;
	available integer;
	inserted_id uuid;
begin
	perform private.lock_organization_billing(target_organization_id);

	select f.id into existing_id from public.organization_billing_refunds f
	where f.idempotency_key = record_organization_billing_refund.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'refund_id', existing_id);
	end if;

	if not exists (
		select 1 from public.organization_billing_receipts r
		where r.id = receipt_id and r.organization_id = target_organization_id
	) then
		raise exception 'That payment was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;
	if exists (select 1 from public.organization_billing_voids v where v.receipt_id = record_organization_billing_refund.receipt_id) then
		raise exception 'That payment was cancelled.' using errcode = 'check_violation';
	end if;
	if refunded_on > private.organization_commercial_today(target_organization_id) then
		raise exception 'The refund date cannot be in the future.' using errcode = 'check_violation';
	end if;

	available := private.billing_receipt_unapplied(receipt_id);
	if amount_usd_cents > available then
		raise exception 'Only % cents of that payment is unapplied. Remove it from a charge before refunding more.', available
			using errcode = 'check_violation';
	end if;

	insert into public.organization_billing_refunds (
		organization_id, receipt_id, refunded_on, amount_usd_cents, method, private_reference, reason,
		actor_owner_email, idempotency_key
	) values (
		target_organization_id, receipt_id, refunded_on, amount_usd_cents, trim(method),
		nullif(trim(coalesce(private_reference, '')), ''), trim(reason), actor_owner_email, idempotency_key
	)
	returning id into inserted_id;

	return jsonb_build_object('applied', true, 'refund_id', inserted_id);
end;
$$;

-- Cancels one record with a reason. record_kind is charge, receipt, application, or refund.
-- Cancelling a payment also cancels its applications, so that money is owed again; a payment with a
-- refund cannot be cancelled until the refund is. Only the latest charge, unpaid and not yet covered,
-- can be cancelled.
create or replace function public.void_organization_billing_record(
	target_organization_id uuid,
	record_kind text,
	record_id uuid,
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
	target_charge public.organization_billing_charges;
	application_row record;
	inserted_id uuid;
begin
	perform private.lock_organization_billing(target_organization_id);

	select v.id into existing_id from public.organization_billing_voids v
	where v.idempotency_key = void_organization_billing_record.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'void_id', existing_id);
	end if;

	if record_kind not in ('charge', 'receipt', 'application', 'refund') then
		raise exception 'Unknown billing record kind.' using errcode = 'check_violation';
	end if;

	if exists (
		select 1 from public.organization_billing_voids v
		where (record_kind = 'charge' and v.charge_id = record_id)
			or (record_kind = 'receipt' and v.receipt_id = record_id)
			or (record_kind = 'application' and v.application_id = record_id)
			or (record_kind = 'refund' and v.refund_id = record_id)
	) then
		raise exception 'That record is already cancelled.' using errcode = 'check_violation';
	end if;

	if not exists (
		select 1 from public.organization_billing_charges c
		where record_kind = 'charge' and c.id = record_id and c.organization_id = target_organization_id
		union all
		select 1 from public.organization_billing_receipts r
		where record_kind = 'receipt' and r.id = record_id and r.organization_id = target_organization_id
		union all
		select 1 from public.organization_billing_applications a
		where record_kind = 'application' and a.id = record_id and a.organization_id = target_organization_id
		union all
		select 1 from public.organization_billing_refunds f
		where record_kind = 'refund' and f.id = record_id and f.organization_id = target_organization_id
	) then
		raise exception 'That record was not found for this organization.' using errcode = 'foreign_key_violation';
	end if;

	if record_kind = 'charge' then
		select * into target_charge from public.organization_billing_charges c where c.id = record_id;
		if exists (
			select 1 from public.organization_billing_charges c
			where c.organization_id = target_organization_id and c.period_start > target_charge.period_start
				and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)
		) then
			raise exception 'Only the latest charge can be cancelled.' using errcode = 'check_violation';
		end if;
		if private.billing_charge_applied(record_id) > 0 then
			raise exception 'Remove the money applied to this charge before cancelling it.' using errcode = 'check_violation';
		end if;
		if exists (select 1 from public.organization_billing_coverage_confirmations cc where cc.charge_id = record_id) then
			raise exception 'This charge''s dates are confirmed as covered. Correct the paid-through date instead.'
				using errcode = 'check_violation';
		end if;
	end if;

	if record_kind = 'receipt' then
		if exists (
			select 1 from public.organization_billing_refunds f
			where f.receipt_id = record_id
				and not exists (select 1 from public.organization_billing_voids v where v.refund_id = f.id)
		) then
			raise exception 'Cancel this payment''s refund first.' using errcode = 'check_violation';
		end if;
		for application_row in
			select a.id from public.organization_billing_applications a
			where a.receipt_id = record_id
				and not exists (select 1 from public.organization_billing_voids v where v.application_id = a.id)
			order by a.created_at
		loop
			insert into public.organization_billing_voids (
				organization_id, application_id, reason, actor_owner_email, idempotency_key
			) values (
				target_organization_id, application_row.id, trim(reason), actor_owner_email,
				idempotency_key || ':application:' || application_row.id
			);
		end loop;
	end if;

	insert into public.organization_billing_voids (
		organization_id, charge_id, receipt_id, application_id, refund_id, reason, actor_owner_email, idempotency_key
	) values (
		target_organization_id,
		case when record_kind = 'charge' then record_id end,
		case when record_kind = 'receipt' then record_id end,
		case when record_kind = 'application' then record_id end,
		case when record_kind = 'refund' then record_id end,
		trim(reason), actor_owner_email, idempotency_key
	)
	returning id into inserted_id;

	return jsonb_build_object('applied', true, 'void_id', inserted_id);
end;
$$;

-- Replaces a wrongly recorded payment. The original is cancelled with the reason and stays visible; the
-- replacement names it and is applied to the same charges, in the same order, as far as it reaches.
-- Coverage is never changed by a correction.
create or replace function public.correct_organization_billing_receipt(
	target_organization_id uuid,
	original_receipt_id uuid,
	received_on date,
	amount_usd_cents integer,
	method text,
	private_reference text,
	reason text,
	actor_owner_email text,
	idempotency_key text,
	note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	existing_id uuid;
	previous_applications jsonb;
	replacement_id uuid;
	previous_application jsonb;
	remaining integer;
	outstanding integer;
	amount_to_apply integer;
	application_number integer := 0;
begin
	perform private.lock_organization_billing(target_organization_id);

	select r.id into existing_id from public.organization_billing_receipts r
	where r.idempotency_key = correct_organization_billing_receipt.idempotency_key;
	if existing_id is not null then
		return jsonb_build_object('applied', false, 'receipt_id', existing_id);
	end if;

	if received_on > private.organization_commercial_today(target_organization_id) then
		raise exception 'The date received cannot be in the future.' using errcode = 'check_violation';
	end if;

	select coalesce(jsonb_agg(jsonb_build_object('charge_id', a.charge_id, 'amount', a.amount_usd_cents)
		order by a.created_at), '[]'::jsonb)
	into previous_applications
	from public.organization_billing_applications a
	where a.receipt_id = original_receipt_id
		and not exists (select 1 from public.organization_billing_voids v where v.application_id = a.id);

	perform public.void_organization_billing_record(
		target_organization_id, 'receipt', original_receipt_id, reason, actor_owner_email, idempotency_key || ':void'
	);

	insert into public.organization_billing_receipts (
		organization_id, received_on, amount_usd_cents, method, private_reference, note, replaces_receipt_id,
		actor_owner_email, idempotency_key
	) values (
		target_organization_id, received_on, amount_usd_cents, trim(method), trim(private_reference),
		nullif(trim(coalesce(note, '')), ''), original_receipt_id, actor_owner_email, idempotency_key
	)
	returning id into replacement_id;

	remaining := amount_usd_cents;
	for previous_application in select * from jsonb_array_elements(previous_applications) loop
		exit when remaining <= 0;
		application_number := application_number + 1;
		outstanding := (
			select c.amount_usd_cents from public.organization_billing_charges c
			where c.id = (previous_application ->> 'charge_id')::uuid
		) - private.billing_charge_applied((previous_application ->> 'charge_id')::uuid);
		amount_to_apply := least(remaining, (previous_application ->> 'amount')::integer, outstanding);
		if amount_to_apply > 0 then
			perform private.apply_organization_billing_money(
				target_organization_id, replacement_id, (previous_application ->> 'charge_id')::uuid,
				amount_to_apply, actor_owner_email, idempotency_key || ':apply:' || application_number
			);
			remaining := remaining - amount_to_apply;
		end if;
	end loop;

	return jsonb_build_object('applied', true, 'receipt_id', replacement_id);
end;
$$;

-- Jafar confirms that a fully paid charge's exact dates are covered. Paid-through moves to the end of
-- that period and the next period's charge is added. covered_from and covered_through must match the
-- charge, so a confirmation never covers dates Jafar did not see.
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

	return jsonb_build_object(
		'applied', true,
		'confirmation_id', inserted_id,
		'paid_through_date', command_result ->> 'paid_through_date',
		'grace_ends_at', command_result ->> 'grace_ends_at',
		'next_charge_id', next_charge.id
	);
end;
$$;

-- A reasoned correction of the paid-through date, separate from any money record.
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
begin
	perform private.lock_organization_billing(target_organization_id);
	return public.apply_organization_commercial_command(
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
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 5. Owner reader: everything the Billing workspace shows, in one call.
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
		), '[]'::jsonb)
	)
	from context ctx;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 6. Only the owner service role runs the commands and the reader.
-- ---------------------------------------------------------------------------------------------------

revoke all on function public.add_organization_billing_charge(uuid, text, text, date) from public, anon, authenticated;
revoke all on function public.record_organization_billing_receipt(uuid, date, integer, text, text, text, text, text, jsonb)
	from public, anon, authenticated;
revoke all on function public.apply_organization_billing_credit(uuid, uuid, uuid, integer, text, text)
	from public, anon, authenticated;
revoke all on function public.record_organization_billing_refund(uuid, uuid, date, integer, text, text, text, text, text)
	from public, anon, authenticated;
revoke all on function public.void_organization_billing_record(uuid, text, uuid, text, text, text)
	from public, anon, authenticated;
revoke all on function public.correct_organization_billing_receipt(uuid, uuid, date, integer, text, text, text, text, text, text)
	from public, anon, authenticated;
revoke all on function public.confirm_organization_billing_coverage(uuid, uuid, date, date, text, text)
	from public, anon, authenticated;
revoke all on function public.adjust_organization_paid_through(uuid, date, text, text, text) from public, anon, authenticated;
revoke all on function public.owner_organization_billing(uuid) from public, anon, authenticated;

grant execute on function public.add_organization_billing_charge(uuid, text, text, date) to service_role;
grant execute on function public.record_organization_billing_receipt(uuid, date, integer, text, text, text, text, text, jsonb)
	to service_role;
grant execute on function public.apply_organization_billing_credit(uuid, uuid, uuid, integer, text, text) to service_role;
grant execute on function public.record_organization_billing_refund(uuid, uuid, date, integer, text, text, text, text, text)
	to service_role;
grant execute on function public.void_organization_billing_record(uuid, text, uuid, text, text, text) to service_role;
grant execute on function public.correct_organization_billing_receipt(uuid, uuid, date, integer, text, text, text, text, text, text)
	to service_role;
grant execute on function public.confirm_organization_billing_coverage(uuid, uuid, date, date, text, text) to service_role;
grant execute on function public.adjust_organization_paid_through(uuid, date, text, text, text) to service_role;
grant execute on function public.owner_organization_billing(uuid) to service_role;
