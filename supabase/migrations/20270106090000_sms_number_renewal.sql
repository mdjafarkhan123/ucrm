-- Stage 10 Part 7 (docs/global-sms-behavior-contract.md § Part 7): every texting number renews each month.
--
-- Twilio bills Uplift for a number every month until it is released, so the business pays the same way, the
-- GoHighLevel way: from its bought texting balance, on the number's purchase anniversary, at the number price in
-- effect that day. A short balance starts 14 days of grace: replies still arrive, sending from that number is
-- paused, and a confirmed top-up pays the overdue month at once. When grace runs out the number is released by the
-- SMS worker, which stays off while live SMS is off.
--
-- 1. Each number learns its renewal anchor, the month it renews next and whether that month is paid.
-- 2. One row per renewal month records what it cost and how it ended (the Control Room's history).
-- 3. The charge, the sweep that runs it every 15 minutes, and the warnings to the business owner.
-- 4. A confirmed top-up pays unpaid renewals first.
-- 5. Sending pauses on an unpaid number; another paid number of the same country is used instead when there is one.
-- 6. Release: the list the worker reads and the record it writes once Twilio lets the number go.

-- 1. Renewal state on each number -------------------------------------------------------------------------------

-- The renewal moment of month n: the anchor plus n calendar months in UTC. Postgres clamps a missing day to the
-- month's last day, and counting from the anchor (never from the previous renewal) keeps a number bought on the
-- 31st renewing on the 31st whenever the month has one.
create or replace function private.sms_number_renewal_at(p_anchor timestamptz, p_period integer)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select ((p_anchor at time zone 'UTC') + make_interval(months => p_period)) at time zone 'UTC';
$$;

revoke all on function private.sms_number_renewal_at(timestamptz, integer) from public, anon, authenticated;

alter table public.communication_sms_sender_identities
  add column renewal_anchor_at timestamptz,
  add column renewal_period integer not null default 1,
  add column renews_at timestamptz,
  add column renewal_state text not null default 'paid',
  add column unpaid_since timestamptz,
  add column grace_ends_at timestamptz,
  add column released_at timestamptz,
  add constraint communication_sms_sender_identities_renewal_state_check
    check (renewal_state in ('paid', 'unpaid', 'released')),
  add constraint communication_sms_sender_identities_renewal_period_check check (renewal_period >= 1),
  add constraint communication_sms_sender_identities_unpaid_check check (
    (renewal_state = 'unpaid') = (unpaid_since is not null and grace_ends_at is not null)
  );

-- Numbers already here renew on the next anniversary of the day they were attached; nothing is charged backwards.
update public.communication_sms_sender_identities s
set renewal_anchor_at = s.created_at,
    renewal_period = (
      select min(n)::integer from generate_series(1, 1200) as n
      where private.sms_number_renewal_at(s.created_at, n) > now()
    ),
    renewal_state = case when s.lifecycle_state = 'released' then 'released' else 'paid' end;

update public.communication_sms_sender_identities s
set renews_at = private.sms_number_renewal_at(s.renewal_anchor_at, s.renewal_period);

-- A new number's anchor is the moment it became the business's: the purchase time for a bought number (set by
-- communication_sms_complete_number_order), otherwise the moment it was attached.
create or replace function private.sms_sender_set_renewal_anchor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.renewal_anchor_at := coalesce(new.renewal_anchor_at, now());
  new.renewal_period := 1;
  new.renews_at := private.sms_number_renewal_at(new.renewal_anchor_at, 1);
  return new;
end;
$$;

revoke all on function private.sms_sender_set_renewal_anchor() from public, anon, authenticated;

create trigger communication_sms_sender_identities_renewal_anchor
  before insert on public.communication_sms_sender_identities
  for each row execute function private.sms_sender_set_renewal_anchor();

alter table public.communication_sms_sender_identities
  alter column renewal_anchor_at set not null,
  alter column renews_at set not null;

create index communication_sms_sender_identities_renews_idx
  on public.communication_sms_sender_identities (renews_at)
  where renewal_state <> 'released' and lifecycle_state <> 'released';

create index communication_sms_sender_identities_grace_idx
  on public.communication_sms_sender_identities (grace_ends_at)
  where renewal_state = 'unpaid';

-- 2. Renewal months ---------------------------------------------------------------------------------------------

create table public.communication_sms_number_renewals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sender_identity_id uuid not null,
  period_number integer not null,
  renews_at timestamptz not null,
  number_rate_id uuid not null references public.communication_sms_number_retail_rates(id) on delete restrict,
  currency_code text not null,
  amount_minor bigint not null,
  state text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz,
  released_at timestamptz,
  constraint communication_sms_number_renewals_period_key unique (sender_identity_id, period_number),
  constraint communication_sms_number_renewals_period_check check (period_number >= 1),
  constraint communication_sms_number_renewals_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_number_renewals_amount_check check (amount_minor > 0),
  constraint communication_sms_number_renewals_state_check check (
    (state = 'unpaid' and paid_at is null and released_at is null)
    or (state = 'paid' and paid_at is not null and released_at is null)
    or (state = 'released' and paid_at is null and released_at is not null)
  ),
  constraint communication_sms_number_renewals_sender_fk foreign key (organization_id, sender_identity_id)
    references public.communication_sms_sender_identities(organization_id, id) on delete cascade
);

create index communication_sms_number_renewals_org_idx
  on public.communication_sms_number_renewals (organization_id, sender_identity_id, renews_at desc);

create index communication_sms_number_renewals_rate_idx
  on public.communication_sms_number_renewals (number_rate_id);

alter table public.communication_sms_number_renewals enable row level security;
revoke all on table public.communication_sms_number_renewals from anon, authenticated;

-- 3. The charge, the sweep and the warnings ----------------------------------------------------------------------

insert into public.team_alert_kinds (kind, default_email, default_browser)
values ('communications.number_renewal', true, true);

alter table public.team_notifications drop constraint team_notifications_subject_type_check;
alter table public.team_notifications
  add constraint team_notifications_subject_type_check check (subject_type = any (array[
    'form_submission', 'website_chat_session', 'invoice', 'quote', 'review_feedback', 'opportunity',
    'task_batch', 'job', 'assessment', 'running_timer', 'inbound_message', 'sms_number'
  ]));

-- Renewal warnings go to the business owner (plan § Part 7), never wider.
create or replace function private.member_can_receive_alert(p_organization_id uuid, p_user_id uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
      select 1
      from public.organization_members as membership
      join public.organizations as organization on organization.id = membership.organization_id
      where membership.organization_id = p_organization_id
        and membership.user_id = p_user_id
        and membership.status = 'active'
        and organization.lifecycle_status = 'active'
    )
    and case
      when p_kind like 'website_inquiry.%'
        then private.member_receives_inquiry_alerts(p_organization_id, p_user_id)
      when p_kind in ('pipeline.task_assigned', 'pipeline.note_mention')
        then private.member_receives_task_alerts(p_organization_id, p_user_id)
      when p_kind in ('quote.customer_approved', 'quote.changes_requested', 'quote.customer_declined',
        'quote.delivery_failed')
        then private.member_receives_quote_alerts(p_organization_id, p_user_id)
      when p_kind like 'invoice.%'
        then private.member_has_permission(p_organization_id, p_user_id, 'invoices.record_payment')
          and private.member_has_permission(p_organization_id, p_user_id, 'invoices.view_price')
      when p_kind like 'quote.deposit_%'
        then private.member_has_permission(p_organization_id, p_user_id, 'quotes.record_deposit')
          and private.member_has_permission(p_organization_id, p_user_id, 'quotes.view_price')
      when p_kind = 'review.private_feedback'
        then private.member_has_permission(p_organization_id, p_user_id, 'reviews.feedback')
      when p_kind in ('schedule.assigned', 'schedule.removed', 'schedule.changed')
        then private.member_has_permission(p_organization_id, p_user_id, 'jobs.view')
          or private.member_has_permission(p_organization_id, p_user_id, 'requests.view')
      when p_kind = 'time.timer_running_long' then true
      when p_kind = 'communications.message_received'
        then private.member_has_permission(p_organization_id, p_user_id, 'conversations.view_team')
          or private.member_has_permission(p_organization_id, p_user_id, 'conversations.view_assigned')
      when p_kind = 'communications.number_renewal'
        then exists (
          select 1 from public.organization_members as owner_row
          where owner_row.organization_id = p_organization_id and owner_row.user_id = p_user_id
            and owner_row.role = 'owner'
        )
      else false
    end;
$$;

revoke all on function private.member_can_receive_alert(uuid, uuid, text) from public, anon, authenticated;

-- "$0.75" for dollars, "BDT 70.00" otherwise.
create or replace function private.sms_money_words(p_minor bigint, p_currency text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_currency = 'USD' then '$' else p_currency || ' ' end
    || to_char(p_minor / 100.0, 'FM999999990.00');
$$;

-- "Nov 2" on the business's own calendar.
create or replace function private.sms_business_date_words(p_organization_id uuid, p_at timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select to_char(
    p_at at time zone coalesce(
      (select st.timezone from public.organization_settings st where st.organization_id = p_organization_id),
      'UTC'
    ),
    'Mon FMDD'
  );
$$;

revoke all on function private.sms_money_words(bigint, text) from public, anon, authenticated;
revoke all on function private.sms_business_date_words(uuid, timestamptz) from public, anon, authenticated;

-- One alert per owner. The source key makes each warning happen once, however often the sweep runs.
create or replace function private.notify_sms_number_renewal(
  p_sender public.communication_sms_sender_identities,
  p_source_key text,
  p_title text,
  p_body text
)
returns void
language sql
set search_path = ''
as $$
  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key
  )
  select p_sender.organization_id, m.user_id, 'communications.number_renewal', 'sms_number', p_sender.id,
    left(p_title, 200), left(p_body, 500), p_source_key
  from public.organization_members m
  where m.organization_id = p_sender.organization_id and m.role = 'owner' and m.status = 'active'
  on conflict (organization_id, user_id, source_key) do nothing;
$$;

revoke all on function private.notify_sms_number_renewal(
  public.communication_sms_sender_identities, text, text, text
) from public, anon, authenticated;

-- A number with no kind on record (attached by hand before kinds existed) is priced as its sender type says.
create or replace function private.sms_sender_number_type(p_sender public.communication_sms_sender_identities)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_sender.number_type, case when p_sender.sender_type = 'toll_free' then 'toll_free' else 'local' end);
$$;

revoke all on function private.sms_sender_number_type(public.communication_sms_sender_identities)
  from public, anon, authenticated;

-- What a number's next (or overdue) month costs, at the price in effect on its renewal day.
create or replace function private.sms_number_renewal_price(
  p_sender public.communication_sms_sender_identities,
  p_currency text
)
returns public.communication_sms_number_retail_rates
language sql
stable
set search_path = ''
as $$
  select public.communication_sms_effective_number_rate(
    p_sender.country_code, private.sms_sender_number_type(p_sender), p_currency, p_sender.renews_at
  );
$$;

revoke all on function private.sms_number_renewal_price(public.communication_sms_sender_identities, text)
  from public, anon, authenticated;

-- Charge one number's due month. Returns what happened: paid, unpaid (grace started or still running),
-- not_due, no_price (the month waits until Jafar sets one) or released. Each month is charged once: the month
-- advances in the same step as the charge, and the ledger's (organization, source, kind) key backs that up.
create or replace function private.charge_sms_number_renewal(p_sender_id uuid, p_now timestamptz default now())
returns text
language plpgsql
set search_path = ''
as $$
declare
  sender public.communication_sms_sender_identities;
  rate public.communication_sms_number_retail_rates;
  account_currency text;
  settled bigint;
  reserved bigint;
  amount bigint;
  new_balance bigint;
  label text;
begin
  select * into sender from public.communication_sms_sender_identities where id = p_sender_id for update;
  if not found or sender.lifecycle_state = 'released' or sender.renewal_state = 'released' then
    return 'released';
  end if;
  if sender.renews_at > p_now then
    return 'not_due';
  end if;

  insert into public.communication_sms_credit_accounts (organization_id)
  values (sender.organization_id)
  on conflict (organization_id) do nothing;

  select a.currency_code, a.settled_balance_minor, a.reserved_balance_minor
  into account_currency, settled, reserved
  from public.communication_sms_credit_accounts a
  where a.organization_id = sender.organization_id
  for update;

  rate := private.sms_number_renewal_price(sender, account_currency);
  if rate.id is null then
    return 'no_price';
  end if;
  amount := round(rate.monthly_rate_major * 100)::bigint;
  label := coalesce(nullif(trim(sender.display_name), ''), sender.phone_number);

  if settled - reserved >= amount then
    update public.communication_sms_credit_accounts
    set settled_balance_minor = settled_balance_minor - amount, updated_at = now()
    where organization_id = sender.organization_id
    returning settled_balance_minor into new_balance;

    insert into public.communication_sms_credit_ledger_entries (
      organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at, reason
    ) values (
      sender.organization_id,
      'number_renewal:' || sender.id || ':' || sender.renewal_period,
      'charge', -amount, new_balance, now(),
      'Phone number ' || sender.phone_number || ' (month from '
        || private.sms_business_date_words(sender.organization_id, sender.renews_at) || ')'
    );

    insert into public.communication_sms_number_renewals (
      organization_id, sender_identity_id, period_number, renews_at, number_rate_id, currency_code, amount_minor,
      state, paid_at
    ) values (
      sender.organization_id, sender.id, sender.renewal_period, sender.renews_at, rate.id, account_currency, amount,
      'paid', now()
    )
    on conflict (sender_identity_id, period_number) do update
      set state = 'paid', paid_at = now(), number_rate_id = excluded.number_rate_id,
          amount_minor = excluded.amount_minor, currency_code = excluded.currency_code, updated_at = now();

    update public.communication_sms_sender_identities
    set renewal_period = renewal_period + 1,
        renews_at = private.sms_number_renewal_at(renewal_anchor_at, renewal_period + 1),
        renewal_state = 'paid',
        unpaid_since = null,
        grace_ends_at = null,
        updated_at = now()
    where id = sender.id;
    return 'paid';
  end if;

  if sender.renewal_state = 'unpaid' then
    return 'unpaid';
  end if;

  insert into public.communication_sms_number_renewals (
    organization_id, sender_identity_id, period_number, renews_at, number_rate_id, currency_code, amount_minor, state
  ) values (
    sender.organization_id, sender.id, sender.renewal_period, sender.renews_at, rate.id, account_currency, amount,
    'unpaid'
  )
  on conflict (sender_identity_id, period_number) do nothing;

  update public.communication_sms_sender_identities
  set renewal_state = 'unpaid',
      unpaid_since = renews_at,
      grace_ends_at = renews_at + interval '14 days',
      updated_at = now()
  where id = sender.id
  returning * into sender;

  perform private.notify_sms_number_renewal(
    sender,
    'number_renewal_failed:' || sender.id || ':' || sender.renewal_period,
    label || ' couldn''t renew',
    'Sending from this number is paused; replies still arrive. Add '
      || private.sms_money_words(amount - greatest(settled - reserved, 0), account_currency) || ' by '
      || private.sms_business_date_words(sender.organization_id, sender.grace_ends_at)
      || ' or the number is released.'
  );
  return 'unpaid';
end;
$$;

revoke all on function private.charge_sms_number_renewal(uuid, timestamptz) from public, anon, authenticated;

-- Retry an organization's unpaid months, oldest first. Run after money arrives.
create or replace function private.retry_sms_number_renewals(p_organization_id uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  candidate uuid;
  paid integer := 0;
begin
  for candidate in
    select s.id
    from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id and s.renewal_state = 'unpaid' and s.lifecycle_state <> 'released'
    order by s.unpaid_since, s.id
  loop
    if private.charge_sms_number_renewal(candidate) = 'paid' then
      paid := paid + 1;
    end if;
  end loop;
  return paid;
end;
$$;

revoke all on function private.retry_sms_number_renewals(uuid) from public, anon, authenticated;

-- The scheduled sweep: charge every due month, warn 3 days before a renewal the balance can't cover and 3 days
-- before a release. Each number runs in its own subtransaction, so one failure does not stop the rest.
create or replace function private.renew_sms_numbers(p_now timestamptz default now())
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  candidate public.communication_sms_sender_identities;
  outcome text;
  rate public.communication_sms_number_retail_rates;
  account record;
  amount bigint;
  label text;
  paid integer := 0;
  unpaid integer := 0;
  no_price integer := 0;
  warned integer := 0;
  failed integer := 0;
begin
  for candidate in
    select s.* from public.communication_sms_sender_identities s
    where s.renewal_state <> 'released' and s.lifecycle_state <> 'released' and s.renews_at <= p_now
    order by s.renews_at, s.id
  loop
    begin
      outcome := private.charge_sms_number_renewal(candidate.id, p_now);
      if outcome = 'paid' then paid := paid + 1;
      elsif outcome = 'unpaid' then unpaid := unpaid + 1;
      elsif outcome = 'no_price' then no_price := no_price + 1;
      end if;
    exception when others then
      failed := failed + 1;
      raise warning 'Number renewal failed for sender %: %', candidate.id, sqlerrm;
    end;
  end loop;

  for candidate in
    select s.* from public.communication_sms_sender_identities s
    where s.renewal_state = 'paid' and s.lifecycle_state <> 'released'
      and s.renews_at > p_now and s.renews_at <= p_now + interval '3 days'
  loop
    select a.currency_code, a.settled_balance_minor - a.reserved_balance_minor as available
    into account
    from public.communication_sms_credit_accounts a
    where a.organization_id = candidate.organization_id;
    rate := private.sms_number_renewal_price(candidate, coalesce(account.currency_code, 'USD'));
    continue when rate.id is null;
    amount := round(rate.monthly_rate_major * 100)::bigint;
    continue when coalesce(account.available, 0) >= amount;
    label := coalesce(nullif(trim(candidate.display_name), ''), candidate.phone_number);
    perform private.notify_sms_number_renewal(
      candidate,
      'number_renewal_short:' || candidate.id || ':' || candidate.renewal_period,
      label || ' can''t renew on ' || private.sms_business_date_words(candidate.organization_id, candidate.renews_at),
      'Your texting balance has ' || private.sms_money_words(greatest(coalesce(account.available, 0), 0),
        coalesce(account.currency_code, 'USD'))
        || ' and this number needs ' || private.sms_money_words(amount, coalesce(account.currency_code, 'USD'))
        || '. Add money so it keeps texting.'
    );
    warned := warned + 1;
  end loop;

  for candidate in
    select s.* from public.communication_sms_sender_identities s
    where s.renewal_state = 'unpaid' and s.lifecycle_state <> 'released'
      and s.grace_ends_at > p_now and s.grace_ends_at <= p_now + interval '3 days'
  loop
    label := coalesce(nullif(trim(candidate.display_name), ''), candidate.phone_number);
    perform private.notify_sms_number_renewal(
      candidate,
      'number_release_soon:' || candidate.id || ':' || candidate.renewal_period,
      label || ' is released on ' || private.sms_business_date_words(candidate.organization_id, candidate.grace_ends_at),
      'Its renewal is still unpaid. Add money to keep it; your conversations are kept either way.'
    );
    warned := warned + 1;
  end loop;

  return jsonb_build_object('paid', paid, 'unpaid', unpaid, 'no_price', no_price, 'warned', warned,
    'failed', failed);
end;
$$;

revoke all on function private.renew_sms_numbers(timestamptz) from public, anon, authenticated;

select cron.schedule('communications-sms-number-renewal', '*/15 * * * *',
  $job$select private.renew_sms_numbers();$job$);

-- A bought number's anchor is its purchase moment.
create or replace function public.communication_sms_complete_number_order(p_order_id uuid)
returns public.communication_sms_number_orders
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  o public.communication_sms_number_orders;
  v_sender_id uuid;
begin
  select * into o from public.communication_sms_number_orders where id = p_order_id for update;
  if not found then
    raise exception 'number_order_not_found' using errcode = 'P0001';
  end if;
  if o.state = 'completed' then
    return o;
  end if;
  if o.state <> 'purchased' then
    raise exception 'number_order_not_purchased' using errcode = 'P0001';
  end if;

  select s.id into v_sender_id
  from public.communication_sms_sender_identities s
  where s.organization_id = o.organization_id
    and s.phone_number = o.phone_number
    and s.lifecycle_state <> 'released';

  if v_sender_id is null then
    insert into public.communication_sms_sender_identities (
      organization_id, phone_number, country_code, sender_type, number_type, provider_phone_number_sid,
      capable_sms, capable_mms, capable_voice, renewal_anchor_at
    ) values (
      o.organization_id, o.phone_number, o.country_code,
      case when o.number_type = 'toll_free' then 'toll_free' else 'long_code' end,
      o.number_type, o.provider_phone_number_sid, o.capable_sms, o.capable_mms, o.capable_voice, o.purchased_at
    )
    returning id into v_sender_id;
  end if;

  update public.communication_sms_number_orders
  set state = 'completed', sender_identity_id = v_sender_id, completed_at = now(), updated_at = now()
  where id = p_order_id
  returning * into o;

  return o;
end;
$$;

-- 4. A confirmed top-up pays unpaid renewals first ----------------------------------------------------------------

create or replace function public.communication_sms_confirm_credit_topup(
  p_request_id uuid,
  p_decided_by uuid,
  p_settled_amount_minor bigint,
  p_decision_reason text default null
)
returns public.communication_sms_credit_topup_requests
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  req public.communication_sms_credit_topup_requests;
  new_balance bigint;
begin
  if p_settled_amount_minor is null or p_settled_amount_minor <= 0 then
    raise exception 'a confirmed top-up must record a positive settled amount'
      using errcode = 'P0001';
  end if;

  select * into req
  from public.communication_sms_credit_topup_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'top-up request % not found', p_request_id using errcode = 'P0001';
  end if;
  if req.status <> 'awaiting_confirmation' then
    raise exception 'top-up request % is % and can no longer be confirmed', p_request_id, req.status
      using errcode = 'P0001';
  end if;

  -- Ensure the organization has a credit account, then raise its settled balance.
  insert into public.communication_sms_credit_accounts (organization_id, currency_code)
  values (req.organization_id, req.currency_code)
  on conflict (organization_id) do nothing;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = settled_balance_minor + p_settled_amount_minor,
      updated_at = now()
  where organization_id = req.organization_id
  returning settled_balance_minor into new_balance;

  -- One immutable purchased-credit entry, keyed to this request so a retry cannot post twice.
  insert into public.communication_sms_credit_ledger_entries (
    organization_id, source_key, entry_kind, amount_minor, balance_after_minor
  ) values (
    req.organization_id, 'topup:' || req.id::text, 'credit', p_settled_amount_minor, new_balance
  );

  update public.communication_sms_credit_topup_requests
  set status = 'confirmed',
      decided_by = p_decided_by,
      decided_at = now(),
      decision_reason = p_decision_reason,
      settled_amount_minor = p_settled_amount_minor
  where id = p_request_id
  returning * into req;

  -- Part 7: the money pays any number waiting in grace before anything else, so sending resumes at once.
  perform private.retry_sms_number_renewals(req.organization_id);

  return req;
end;
$$;

-- 5. Sending pauses on an unpaid number ---------------------------------------------------------------------------

create or replace function private.communication_sms_route_check(
  p_organization_id uuid,
  p_sender public.communication_sms_sender_identities,
  p_recipient_country text,
  out ok boolean,
  out code text,
  out message text,
  out mms_route boolean
)
returns record
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  destination public.communication_sms_destinations;
  registration_status text;
begin
  ok := false;
  mms_route := false;

  if public.communication_sms_effective_mode(p_organization_id) = 'off' then
    code := 'not_included';
    message := 'Texting is not part of this business''s plan.';
    return;
  end if;

  -- Part 7: a number in renewal grace still receives replies, but sends nothing until its month is paid.
  if p_sender.renewal_state = 'unpaid' then
    code := 'number_unpaid';
    message := 'Sending is paused. ' || coalesce(nullif(trim(p_sender.display_name), ''), p_sender.phone_number)
      || ' couldn''t renew; replies still arrive.';
    return;
  end if;

  if p_recipient_country is null then
    code := 'unknown_country';
    message := 'This phone number doesn''t belong to a country we can text.';
    return;
  end if;

  select d.* into destination
  from public.communication_sms_destinations d
  where d.organization_id = p_organization_id and d.country_code = p_recipient_country;

  if destination.id is null or destination.status = 'off' then
    code := 'destination_off';
    message := coalesce(destination.business_message, 'Texting this country isn''t switched on for your business.');
    return;
  elsif destination.status <> 'ready' then
    code := 'destination_setting_up';
    message := 'Uplift is still switching texting on for this country.';
    return;
  end if;

  if not (
    p_sender.country_code = p_recipient_country
    or (p_sender.country_code in ('US', 'CA') and p_recipient_country in ('US', 'CA'))
  ) then
    code := 'sender_wrong_country';
    message := 'This number can''t text this country. Use a number from the same country.';
    return;
  end if;

  -- A US customer texted from a +1 local number needs the business's approved US registration (A2P 10DLC).
  -- Toll-free numbers carry their own check, passed before the number went live.
  if p_recipient_country = 'US' and p_sender.sender_type = 'long_code' then
    select r.status into registration_status
    from public.communication_sms_registrations r
    where r.organization_id = p_organization_id and r.id = p_sender.registration_id;
    if registration_status is distinct from 'approved' then
      code := 'us_registration_needed';
      message := 'This number needs the business''s approved US registration to text US customers.';
      return;
    end if;
  end if;

  if exists (select 1 from public.communication_sms_active_outbound_hold(p_organization_id)) then
    code := 'outbound_paused';
    message := 'Outbound SMS is paused for this organization right now.';
    return;
  end if;

  ok := true;
  -- Twilio carries real picture messages only between US and Canadian numbers.
  mms_route := p_sender.capable_mms
    and p_sender.country_code in ('US', 'CA') and p_recipient_country in ('US', 'CA');
end;
$$;

-- The number a send goes from: the chosen one, else among numbers that can text the customer's country a paid one
-- first (Part 7), the default, then one from that country (Twilio's Geo-match), else the default so the check
-- explains why not.
create or replace function private.communication_sms_pick_sender(
  p_organization_id uuid,
  p_sender_id uuid,
  p_recipient_country text
) returns public.communication_sms_sender_identities
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select s.*
  from public.communication_sms_sender_identities s
  where s.organization_id = p_organization_id
    and s.lifecycle_state = 'ready'
    and s.capable_sms
    and (p_sender_id is null or s.id = p_sender_id)
  order by
    (s.country_code = p_recipient_country
      or (s.country_code in ('US', 'CA') and p_recipient_country in ('US', 'CA'))) desc,
    (s.renewal_state = 'paid') desc,
    s.is_default_sender desc,
    (s.country_code = p_recipient_country) desc,
    s.created_at, s.id
  limit 1;
$$;

-- 6. Release ------------------------------------------------------------------------------------------------------

-- Numbers whose grace has run out, for the SMS worker to release at Twilio. Read-only.
create or replace function public.communication_sms_due_number_releases(p_limit integer default 10)
returns table (
  sender_id uuid,
  organization_id uuid,
  phone_number text,
  provider_phone_number_sid text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select s.id, s.organization_id, s.phone_number, s.provider_phone_number_sid
  from public.communication_sms_sender_identities s
  where s.renewal_state = 'unpaid' and s.lifecycle_state <> 'released' and s.grace_ends_at <= now()
  order by s.grace_ends_at, s.id
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

-- Twilio let the number go (or no longer has it): release it here. Conversations stay; the number can no longer
-- send or be the default. Only a number still unpaid past its grace is released, so a top-up confirmed while the
-- worker was busy wins.
create or replace function public.communication_sms_record_number_released(p_sender_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  sender public.communication_sms_sender_identities;
begin
  select * into sender from public.communication_sms_sender_identities where id = p_sender_id for update;
  if not found then
    raise exception 'sender_not_found' using errcode = 'P0001';
  end if;
  if sender.lifecycle_state = 'released' then
    return 'released';
  end if;
  if sender.renewal_state <> 'unpaid' or sender.grace_ends_at > now() then
    return 'kept';
  end if;

  update public.communication_sms_number_renewals
  set state = 'released', released_at = now(), updated_at = now()
  where sender_identity_id = sender.id and period_number = sender.renewal_period and state = 'unpaid';

  update public.communication_sms_sender_identities
  set lifecycle_state = 'released',
      allows_manual = false,
      allows_automated = false,
      is_default_sender = false,
      renewal_state = 'released',
      unpaid_since = null,
      grace_ends_at = null,
      released_at = now(),
      updated_at = now()
  where id = sender.id;
  return 'released';
end;
$$;

revoke all on function public.communication_sms_due_number_releases(integer) from public, anon, authenticated;
revoke all on function public.communication_sms_record_number_released(uuid) from public, anon, authenticated;
grant execute on function public.communication_sms_due_number_releases(integer) to service_role;
grant execute on function public.communication_sms_record_number_released(uuid) to service_role;
