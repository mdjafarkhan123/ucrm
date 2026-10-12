-- CRM launch readiness Part 12: Alerts (docs/alerts-behavior-contract.md).
--
-- One alert stays one `team_notifications` row per person; the bell always shows it. This migration adds:
--   1. a registry of alert types with today's channel defaults (one place for "Email on or off by default"),
--   2. each person's Email / Browser switches per type (sparse: only a change from the default is stored),
--   3. each person's registered computers and a per-computer browser delivery queue,
--   4. new alert types: put on / taken off / moved or cancelled Visits and Assessments, a timer running over
--      12 hours, and a new customer message,
--   5. the rule that decides, at the moment an alert is created, whether its email and browser copies exist.
-- Who receives an alert is NOT changed here: every existing creator keeps its recipient rules.

-- 1. Registry of alert types --------------------------------------------------------------------------------

create table public.team_alert_kinds (
  kind text primary key,
  default_email boolean not null,
  -- Applies once the person has registered at least one computer; before that the Browser column is greyed.
  default_browser boolean not null
);

alter table public.team_alert_kinds enable row level security;
revoke all on public.team_alert_kinds from public, anon, authenticated;

insert into public.team_alert_kinds (kind, default_email, default_browser) values
  ('website_inquiry.received', true, false),
  ('website_inquiry.customer_replied', true, false),
  ('invoice.paid_online', false, false),
  ('invoice.online_payment_failed', false, false),
  ('invoice.online_overpayment', false, false),
  ('invoice.online_refund_failed', false, false),
  ('invoice.payment_disputed', false, false),
  ('quote.deposit_paid_online', false, false),
  ('quote.deposit_payment_failed', false, false),
  ('quote.deposit_overpaid', false, false),
  ('quote.deposit_refund_failed', false, false),
  ('quote.deposit_disputed', false, false),
  ('review.private_feedback', false, false),
  ('quote.delivery_failed', false, false),
  ('quote.customer_declined', false, false),
  ('quote.customer_approved', true, false),
  ('quote.changes_requested', true, false),
  ('pipeline.task_assigned', true, true),
  ('pipeline.note_mention', true, true),
  ('schedule.assigned', true, true),
  ('schedule.removed', true, true),
  ('schedule.changed', true, true),
  ('time.timer_running_long', true, true),
  ('communications.message_received', false, true);

-- Every existing alert type is registered, so the old list check can become a reference to the registry.
alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications
  add constraint team_notifications_kind_fkey foreign key (kind) references public.team_alert_kinds (kind);

alter table public.team_notifications drop constraint team_notifications_subject_type_check;
alter table public.team_notifications
  add constraint team_notifications_subject_type_check check (subject_type = any (array[
    'form_submission', 'website_chat_session', 'invoice', 'quote', 'review_feedback', 'opportunity',
    'task_batch', 'job', 'assessment', 'running_timer', 'inbound_message'
  ]));

-- Several changes within one minute become one alert ("You're on 52 Visits ..."), as Jobber waits a minute
-- after the last schedule edit. The count and the first label let the alert be reworded as more arrive.
alter table public.team_notifications
  add column occurrence_count integer not null default 1 check (occurrence_count >= 1),
  add column occurrence_label text;

-- 2. Each person's switches ---------------------------------------------------------------------------------

create table public.team_notification_preferences (
  organization_id uuid not null,
  user_id uuid not null,
  kind text not null references public.team_alert_kinds (kind),
  channel text not null check (channel in ('email', 'browser')),
  enabled boolean not null,
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id, kind, channel),
  constraint team_notification_preferences_member_fk foreign key (organization_id, user_id)
    references public.organization_members (organization_id, user_id) on delete cascade
);

alter table public.team_notification_preferences enable row level security;
revoke all on public.team_notification_preferences from public, anon, authenticated;

-- 3. Registered computers and the browser delivery queue ------------------------------------------------------

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) between 1 and 2048),
  p256dh text not null check (char_length(p256dh) between 1 and 200),
  auth_secret text not null check (char_length(auth_secret) between 1 and 100),
  label text not null check (char_length(btrim(label)) between 1 and 80),
  created_at timestamptz not null default now(),
  last_success_at timestamptz
);

create index push_subscriptions_user_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from public, anon, authenticated;

create table public.team_notification_push_deliveries (
  notification_id uuid not null references public.team_notifications (id) on delete cascade,
  subscription_id uuid not null references public.push_subscriptions (id) on delete cascade,
  state text not null default 'pending' check (state in ('pending', 'sent', 'failed', 'skipped')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  claim_token uuid,
  claimed_until timestamptz,
  sent_at timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 500),
  primary key (notification_id, subscription_id),
  constraint push_deliveries_claim_pair check ((claim_token is null) = (claimed_until is null))
);

create index team_notification_push_deliveries_queue_idx
  on public.team_notification_push_deliveries (available_at) where state = 'pending';
create index team_notification_push_deliveries_subscription_idx
  on public.team_notification_push_deliveries (subscription_id);

alter table public.team_notification_push_deliveries enable row level security;
revoke all on public.team_notification_push_deliveries from public, anon, authenticated;

-- 4. Who can receive each type ------------------------------------------------------------------------------
--
-- Mirrors each creator's own recipient rule, so the My alerts screen only lists what a person can really get
-- and the email sender can re-check it. It never widens who an alert goes to.

create function private.member_can_receive_alert(p_organization_id uuid, p_user_id uuid, p_kind text)
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
      else false
    end;
$$;

revoke all on function private.member_can_receive_alert(uuid, uuid, text) from public, anon, authenticated;

-- A person's effective switch: their own choice, else the type's default.
create function private.alert_channel_enabled(
  p_organization_id uuid, p_user_id uuid, p_kind text, p_channel text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    (select preference.enabled
     from public.team_notification_preferences as preference
     where preference.organization_id = p_organization_id and preference.user_id = p_user_id
       and preference.kind = p_kind and preference.channel = p_channel),
    (select case p_channel when 'email' then registry.default_email else registry.default_browser end
     from public.team_alert_kinds as registry where registry.kind = p_kind),
    false
  );
$$;

revoke all on function private.alert_channel_enabled(uuid, uuid, text, text) from public, anon, authenticated;

-- 5. The moment an alert is created decides its email and browser copies --------------------------------------
--
-- Runs for every alert from every creator, so each keeps its own recipients and wording. A creator's own
-- 'not_needed' only ever meant "bell only by default"; the person's switch now decides.

create function private.team_notification_set_email_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  new.email_state := case
    when private.alert_channel_enabled(new.organization_id, new.user_id, new.kind, 'email')
      then 'pending'
    else 'not_needed'
  end;
  return new;
end;
$$;

revoke all on function private.team_notification_set_email_state() from public, anon, authenticated;

create trigger team_notifications_set_email_state
  before insert on public.team_notifications
  for each row execute function private.team_notification_set_email_state();

create function private.team_notification_queue_browser()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if not private.alert_channel_enabled(new.organization_id, new.user_id, new.kind, 'browser') then
    return new;
  end if;
  -- One delivery per registered computer: a retry only repeats the computers that did not get it.
  insert into public.team_notification_push_deliveries (notification_id, subscription_id, available_at)
  select new.id, subscription.id, new.email_available_at
  from public.push_subscriptions as subscription
  where subscription.user_id = new.user_id
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function private.team_notification_queue_browser() from public, anon, authenticated;

create trigger team_notifications_queue_browser
  after insert on public.team_notifications
  for each row execute function private.team_notification_queue_browser();

-- 6. Email claim re-checks the person's switch and who may receive -----------------------------------------------

create or replace function public.claim_team_notification_emails(
  p_batch_size integer default 25,
  p_lease_seconds integer default 120
)
returns table (
  notification_id uuid, claim_token uuid, organization_id uuid, organization_name text, recipient_email text,
  kind text, subject_type text, subject_id uuid, title text, body text, attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  token uuid;
  receives boolean;
begin
  if p_batch_size < 1 or p_batch_size > 100 or p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The alert email claim is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select q.id, q.organization_id, q.user_id, q.kind, q.subject_type, q.subject_id, q.title, q.body,
      q.email_attempts, o.name as organization_name, nullif(btrim(u.email), '') as email
    from public.team_notifications as q
    join public.organizations as o on o.id = q.organization_id
    left join auth.users as u on u.id = q.user_id
    where q.email_state = 'pending' and q.email_available_at <= now()
      and (q.email_claimed_until is null or q.email_claimed_until < now())
    order by q.email_available_at, q.id
    limit p_batch_size
    for update of q skip locked
  loop
    -- Still allowed, and still switched on: a person who turned Email off after the alert was created is
    -- not emailed.
    receives := private.member_can_receive_alert(candidate.organization_id, candidate.user_id, candidate.kind)
      and private.alert_channel_enabled(candidate.organization_id, candidate.user_id, candidate.kind, 'email');

    if candidate.email is null or not receives then
      update public.team_notifications
      set email_state = 'not_needed', email_claim_token = null, email_claimed_until = null
      where id = candidate.id;
      continue;
    end if;

    token := gen_random_uuid();
    update public.team_notifications
    set email_claim_token = token, email_claimed_until = now() + make_interval(secs => p_lease_seconds)
    where id = candidate.id;

    notification_id := candidate.id;
    claim_token := token;
    organization_id := candidate.organization_id;
    organization_name := candidate.organization_name;
    recipient_email := candidate.email;
    kind := candidate.kind;
    subject_type := candidate.subject_type;
    subject_id := candidate.subject_id;
    title := candidate.title;
    body := candidate.body;
    attempts := candidate.email_attempts;
    return next;
  end loop;
end;
$$;

-- 7. Browser delivery: claim, then settle each computer on its own ---------------------------------------------

create function public.claim_push_deliveries(
  p_batch_size integer default 50,
  p_lease_seconds integer default 120
)
returns table (
  notification_id uuid, subscription_id uuid, claim_token uuid, endpoint text, p256dh text, auth_secret text,
  organization_id uuid, organization_name text, kind text, subject_type text, subject_id uuid,
  title text, body text, attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  token uuid;
begin
  if p_batch_size < 1 or p_batch_size > 200 or p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The browser alert claim is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select d.notification_id as nid, d.subscription_id as sid, d.attempts as tries,
      n.organization_id as org_id, n.user_id, n.kind as alert_kind, n.subject_type as alert_subject_type,
      n.subject_id as alert_subject_id, n.title as alert_title, n.body as alert_body, n.read_at,
      s.endpoint as push_endpoint, s.p256dh as push_p256dh, s.auth_secret as push_auth,
      o.name as org_name
    from public.team_notification_push_deliveries as d
    join public.team_notifications as n on n.id = d.notification_id
    join public.push_subscriptions as s on s.id = d.subscription_id
    join public.organizations as o on o.id = n.organization_id
    where d.state = 'pending' and d.available_at <= now()
      and (d.claimed_until is null or d.claimed_until < now())
    order by d.available_at, d.notification_id, d.subscription_id
    limit p_batch_size
    for update of d skip locked
  loop
    -- Already read in the app, no longer allowed, or switched off since: nothing to show.
    if candidate.read_at is not null
      or not private.member_can_receive_alert(candidate.org_id, candidate.user_id, candidate.alert_kind)
      or not private.alert_channel_enabled(candidate.org_id, candidate.user_id, candidate.alert_kind, 'browser')
    then
      update public.team_notification_push_deliveries
      set state = 'skipped', claim_token = null, claimed_until = null
      where team_notification_push_deliveries.notification_id = candidate.nid
        and team_notification_push_deliveries.subscription_id = candidate.sid;
      continue;
    end if;

    token := gen_random_uuid();
    update public.team_notification_push_deliveries
    set claim_token = token, claimed_until = now() + make_interval(secs => p_lease_seconds)
    where team_notification_push_deliveries.notification_id = candidate.nid
      and team_notification_push_deliveries.subscription_id = candidate.sid;

    notification_id := candidate.nid;
    subscription_id := candidate.sid;
    claim_token := token;
    endpoint := candidate.push_endpoint;
    p256dh := candidate.push_p256dh;
    auth_secret := candidate.push_auth;
    organization_id := candidate.org_id;
    organization_name := candidate.org_name;
    kind := candidate.alert_kind;
    subject_type := candidate.alert_subject_type;
    subject_id := candidate.alert_subject_id;
    title := candidate.alert_title;
    body := candidate.alert_body;
    attempts := candidate.tries;
    return next;
  end loop;
end;
$$;

-- outcome: 'sent' | 'retry' | 'gone' (the browser says the computer no longer exists) | 'failed'
create function public.settle_push_delivery(
  p_notification_id uuid, p_subscription_id uuid, p_claim_token uuid, p_outcome text, p_error text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  tries integer;
  max_attempts constant integer := 5;
begin
  select d.attempts into tries
  from public.team_notification_push_deliveries as d
  where d.notification_id = p_notification_id and d.subscription_id = p_subscription_id
    and d.claim_token = p_claim_token and d.state = 'pending'
  for update;
  if not found then
    return 'claim_lost';
  end if;

  if p_outcome = 'sent' then
    update public.team_notification_push_deliveries
    set state = 'sent', sent_at = now(), attempts = tries + 1, claim_token = null, claimed_until = null,
      last_error = null
    where notification_id = p_notification_id and subscription_id = p_subscription_id;
    update public.push_subscriptions set last_success_at = now() where id = p_subscription_id;
    return 'sent';
  end if;

  if p_outcome = 'gone' then
    -- The delivery rows go with the computer.
    delete from public.push_subscriptions where id = p_subscription_id;
    return 'gone';
  end if;

  update public.team_notification_push_deliveries
  set attempts = tries + 1,
    state = case when p_outcome = 'failed' or tries + 1 >= max_attempts then 'failed' else 'pending' end,
    available_at = now() + make_interval(mins => power(2, tries)::integer),
    claim_token = null, claimed_until = null,
    last_error = left(coalesce(p_error, 'The browser alert could not be sent.'), 500)
  where notification_id = p_notification_id and subscription_id = p_subscription_id;
  return case when p_outcome = 'failed' or tries + 1 >= max_attempts then 'failed' else 'retry' end;
end;
$$;

revoke all on function public.claim_push_deliveries(integer, integer) from public, anon, authenticated;
revoke all on function public.settle_push_delivery(uuid, uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.claim_push_deliveries(integer, integer) to service_role;
grant execute on function public.settle_push_delivery(uuid, uuid, uuid, text, text) to service_role;

-- 8. My alerts: read and change a person's own switches -------------------------------------------------------

create function public.team_alert_settings(p_organization_id uuid, p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select jsonb_build_object(
    'has_device', exists (select 1 from public.push_subscriptions as s where s.user_id = p_user_id),
    'rows', coalesce(jsonb_agg(jsonb_build_object(
      'kind', registry.kind,
      'email', private.alert_channel_enabled(p_organization_id, p_user_id, registry.kind, 'email'),
      'email_default', registry.default_email,
      'browser', private.alert_channel_enabled(p_organization_id, p_user_id, registry.kind, 'browser'),
      'browser_default', registry.default_browser
    ) order by registry.kind), '[]'::jsonb)
  )
  from public.team_alert_kinds as registry
  where private.member_can_receive_alert(p_organization_id, p_user_id, registry.kind)
    -- An inquiry alert only reaches the people the owner chose in Inquiry alerts.
    and (registry.kind not like 'website_inquiry.%'
      or p_user_id in (select private.inquiry_alert_recipient_ids(p_organization_id)));
$$;

create function public.set_team_alert_preference(
  p_organization_id uuid, p_user_id uuid, p_kind text, p_channel text, p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  default_value boolean;
begin
  if p_channel not in ('email', 'browser') then
    raise exception 'That alert channel cannot be changed.' using errcode = 'check_violation';
  end if;
  if not private.member_can_receive_alert(p_organization_id, p_user_id, p_kind) then
    raise exception 'You do not receive that alert.' using errcode = 'insufficient_privilege';
  end if;

  select case p_channel when 'email' then registry.default_email else registry.default_browser end
  into default_value from public.team_alert_kinds as registry where registry.kind = p_kind;

  -- Back at the default means nothing needs storing: a later change of the default then applies to them.
  if p_enabled = default_value then
    delete from public.team_notification_preferences
    where organization_id = p_organization_id and user_id = p_user_id and kind = p_kind and channel = p_channel;
  else
    insert into public.team_notification_preferences (organization_id, user_id, kind, channel, enabled)
    values (p_organization_id, p_user_id, p_kind, p_channel, p_enabled)
    on conflict (organization_id, user_id, kind, channel)
    do update set enabled = excluded.enabled, updated_at = now();
  end if;
end;
$$;

revoke all on function public.team_alert_settings(uuid, uuid) from public, anon, authenticated;
revoke all on function public.set_team_alert_preference(uuid, uuid, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.team_alert_settings(uuid, uuid) to service_role;
grant execute on function public.set_team_alert_preference(uuid, uuid, text, text, boolean) to service_role;

-- 9. Leaving the business ends that person's computers --------------------------------------------------------

create function private.drop_push_subscriptions_when_no_workspace()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.status is distinct from 'active' and old.status = 'active'
    and not exists (
      select 1 from public.organization_members as other
      where other.user_id = new.user_id and other.status = 'active'
    )
  then
    delete from public.push_subscriptions where user_id = new.user_id;
  end if;
  return new;
end;
$$;

revoke all on function private.drop_push_subscriptions_when_no_workspace() from public, anon, authenticated;

create trigger organization_members_drop_push_subscriptions
  after update of status on public.organization_members
  for each row execute function private.drop_push_subscriptions_when_no_workspace();

-- 10. Where an alert opens ---------------------------------------------------------------------------------------

create or replace function public.team_notification_links(p_organization_id uuid, p_subject_ids uuid[])
returns table (subject_type text, subject_id uuid, request_id uuid, job_id uuid, client_id uuid)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select 'form_submission', s.id,
    nullif(s.result ->> 'request_id', '')::uuid,
    nullif(s.result ->> 'job_id', '')::uuid,
    nullif(s.result ->> 'client_id', '')::uuid
  from private.form_submissions as s
  where s.organization_id = p_organization_id and s.id = any (p_subject_ids)
  union all
  select 'website_chat_session', w.id, null, null, w.client_id
  from public.website_chat_sessions as w
  where w.organization_id = p_organization_id and w.id = any (p_subject_ids)
  union all
  select 'assessment', a.id, a.request_id, null, null
  from public.assessments as a
  where a.organization_id = p_organization_id and a.id = any (p_subject_ids)
  union all
  select 'inbound_message', m.id, null, null, m.client_id
  from public.communication_inbound_messages as m
  where m.organization_id = p_organization_id and m.id = any (p_subject_ids);
$$;

-- 11. Schedule alerts --------------------------------------------------------------------------------------------

-- "Tue 14 Oct, 9:00 am" from a Visit's own date and time (they carry no time zone).
create function private.alert_visit_when(p_date date, p_start time, p_all_day boolean)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_date is null then ''
    when p_all_day or p_start is null then to_char(p_date, 'FMDy FMDD FMMon')
    else to_char(p_date, 'FMDy FMDD FMMon') || ', ' || to_char(p_start, 'FMHH12:MI am')
  end;
$$;

create function private.alert_assessment_when(p_organization_id uuid, p_starts timestamptz, p_all_day boolean)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select case
    when p_starts is null then ''
    else (
      with zone as (
        select coalesce((select settings.timezone from public.organization_settings as settings
                         where settings.organization_id = p_organization_id), 'UTC') as name
      )
      select case when p_all_day
          then to_char(p_starts at time zone zone.name, 'FMDy FMDD FMMon')
          else to_char(p_starts at time zone zone.name, 'FMDy FMDD FMMon, FMHH12:MI am')
        end
      from zone
    )
  end;
$$;

-- Creates a schedule alert, or folds it into one still waiting in its one-minute window. {n} and {first} in
-- the many-template become the count and the first change's label.
create function private.record_schedule_alert(
  p_organization_id uuid, p_user_id uuid, p_kind text, p_subject_type text, p_subject_id uuid,
  p_single_title text, p_many_template text, p_label text, p_body text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  waiting record;
begin
  if not private.member_can_receive_alert(p_organization_id, p_user_id, p_kind) then
    return;
  end if;

  select n.id, n.occurrence_count, n.occurrence_label into waiting
  from public.team_notifications as n
  where n.organization_id = p_organization_id and n.user_id = p_user_id and n.kind = p_kind
    and n.subject_type = p_subject_type and n.subject_id = p_subject_id
    and n.email_available_at > now()
  order by n.created_at desc
  limit 1
  for update;

  if found then
    update public.team_notifications
    set occurrence_count = waiting.occurrence_count + 1,
      title = left(replace(replace(p_many_template, '{n}', (waiting.occurrence_count + 1)::text),
        '{first}', coalesce(waiting.occurrence_label, '')), 200)
    where id = waiting.id;
    return;
  end if;

  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key, email_available_at,
    occurrence_label
  ) values (
    p_organization_id, p_user_id, p_kind, p_subject_type, p_subject_id, left(p_single_title, 200),
    left(p_body, 500), p_kind || ':' || p_subject_id || ':' || gen_random_uuid(),
    now() + interval '60 seconds', nullif(p_label, '')
  );
end;
$$;

revoke all on function private.record_schedule_alert(uuid, uuid, text, text, uuid, text, text, text, text)
  from public, anon, authenticated;

-- "Smith: Spring cleanup" for a Job.
create function private.alert_job_label(p_organization_id uuid, p_job_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    (select nullif(btrim(client.display_name), '') || ': ' || coalesce(nullif(btrim(job.title), ''), 'Job')
     from public.jobs as job
     join public.clients as client on client.organization_id = job.organization_id and client.id = job.client_id
     where job.organization_id = p_organization_id and job.id = p_job_id
       and nullif(btrim(client.display_name), '') is not null),
    (select coalesce(nullif(btrim(job.title), ''), 'a Job')
     from public.jobs as job where job.organization_id = p_organization_id and job.id = p_job_id),
    'a Job'
  );
$$;

revoke all on function private.alert_job_label(uuid, uuid) from public, anon, authenticated;

-- 11a. Put on a Visit
create function private.alert_visit_assigned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  visit record;
  subject text;
  label text;
begin
  -- A change you make yourself never alerts you.
  if new.user_id is not distinct from auth.uid() then
    return new;
  end if;
  select v.visit_date, v.start_time, v.all_day into visit
  from public.job_visits as v where v.organization_id = new.organization_id and v.id = new.visit_id;
  subject := private.alert_job_label(new.organization_id, new.job_id);
  label := private.alert_visit_when(visit.visit_date, visit.start_time, visit.all_day);
  perform private.record_schedule_alert(
    new.organization_id, new.user_id, 'schedule.assigned', 'job', new.job_id,
    'You''re on ' || subject || case when label = '' then '' else ', ' || label end,
    'You''re on {n} Visits for ' || subject || ', starting {first}',
    label
  );
  return new;
end;
$$;

revoke all on function private.alert_visit_assigned() from public, anon, authenticated;

create trigger job_visit_assignments_alert_assigned
  after insert on public.job_visit_assignments
  for each row execute function private.alert_visit_assigned();

-- 11b. Taken off a Visit (only while the Visit still exists; a deleted Visit is announced as cancelled)
create function private.alert_visit_unassigned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  visit record;
  subject text;
  label text;
begin
  if old.user_id is not distinct from auth.uid() then
    return old;
  end if;
  select v.visit_date, v.start_time, v.all_day into visit
  from public.job_visits as v where v.organization_id = old.organization_id and v.id = old.visit_id;
  if not found then
    return old;
  end if;
  subject := private.alert_job_label(old.organization_id, old.job_id);
  label := private.alert_visit_when(visit.visit_date, visit.start_time, visit.all_day);
  perform private.record_schedule_alert(
    old.organization_id, old.user_id, 'schedule.removed', 'job', old.job_id,
    'You''re off ' || subject || case when label = '' then '' else ', ' || label end,
    'You''re off {n} Visits for ' || subject || ', starting {first}',
    label
  );
  return old;
end;
$$;

revoke all on function private.alert_visit_unassigned() from public, anon, authenticated;

create trigger job_visit_assignments_alert_unassigned
  after delete on public.job_visit_assignments
  for each row execute function private.alert_visit_unassigned();

-- 11c. A Visit moved or cancelled, for everyone on it
create function private.alert_visit_moved()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  assignee record;
  subject text := private.alert_job_label(new.organization_id, new.job_id);
  label text := private.alert_visit_when(new.visit_date, new.start_time, new.all_day);
begin
  for assignee in
    select a.user_id from public.job_visit_assignments as a
    where a.organization_id = new.organization_id and a.visit_id = new.id
      and a.user_id is distinct from auth.uid()
      -- Just put on it a moment ago: the "you're on" alert already says when.
      and not exists (
        select 1 from public.team_notifications as n
        where n.organization_id = new.organization_id and n.user_id = a.user_id
          and n.kind = 'schedule.assigned' and n.subject_id = new.job_id and n.email_available_at > now())
  loop
    perform private.record_schedule_alert(
      new.organization_id, assignee.user_id, 'schedule.changed', 'job', new.job_id,
      'Your Visit moved: ' || subject || case when label = '' then '' else ', now ' || label end,
      '{n} of your Visits for ' || subject || ' changed, starting {first}',
      label
    );
  end loop;
  return new;
end;
$$;

revoke all on function private.alert_visit_moved() from public, anon, authenticated;

create trigger job_visits_alert_moved
  after update of visit_date, start_time, end_time, all_day on public.job_visits
  for each row
  when (old.visit_date is distinct from new.visit_date or old.start_time is distinct from new.start_time
    or old.end_time is distinct from new.end_time or old.all_day is distinct from new.all_day)
  execute function private.alert_visit_moved();

create function private.alert_visit_cancelled()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  assignee record;
  subject text := private.alert_job_label(old.organization_id, old.job_id);
  label text := private.alert_visit_when(old.visit_date, old.start_time, old.all_day);
begin
  for assignee in
    select a.user_id from public.job_visit_assignments as a
    where a.organization_id = old.organization_id and a.visit_id = old.id
      and a.user_id is distinct from auth.uid()
  loop
    perform private.record_schedule_alert(
      old.organization_id, assignee.user_id, 'schedule.changed', 'job', old.job_id,
      'Your Visit was cancelled: ' || subject || case when label = '' then '' else ', ' || label end,
      '{n} of your Visits for ' || subject || ' changed, starting {first}',
      label
    );
  end loop;
  return old;
end;
$$;

revoke all on function private.alert_visit_cancelled() from public, anon, authenticated;

create trigger job_visits_alert_cancelled
  before delete on public.job_visits
  for each row execute function private.alert_visit_cancelled();

-- 11d. Assessments: put on, taken off, moved, cancelled
create function private.alert_assessment_label(p_organization_id uuid, p_assessment_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    (select 'an Assessment for ' || nullif(btrim(client.display_name), '')
     from public.assessments as a
     join public.requests as r on r.organization_id = a.organization_id and r.id = a.request_id
     join public.clients as client on client.organization_id = r.organization_id and client.id = r.client_id
     where a.organization_id = p_organization_id and a.id = p_assessment_id
       and nullif(btrim(client.display_name), '') is not null),
    'an Assessment'
  );
$$;

revoke all on function private.alert_assessment_label(uuid, uuid) from public, anon, authenticated;

create function private.alert_assessment_assigned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  assessment record;
  subject text;
  label text;
begin
  if new.user_id is not distinct from auth.uid() then
    return new;
  end if;
  select a.starts_at, a.all_day into assessment
  from public.assessments as a where a.organization_id = new.organization_id and a.id = new.assessment_id;
  subject := private.alert_assessment_label(new.organization_id, new.assessment_id);
  label := private.alert_assessment_when(new.organization_id, assessment.starts_at, assessment.all_day);
  perform private.record_schedule_alert(
    new.organization_id, new.user_id, 'schedule.assigned', 'assessment', new.assessment_id,
    'You''re on ' || subject || case when label = '' then '' else ', ' || label end,
    'You''re on ' || subject || case when label = '' then '' else ', ' || label end,
    label
  );
  return new;
end;
$$;

revoke all on function private.alert_assessment_assigned() from public, anon, authenticated;

create trigger assessment_assignees_alert_assigned
  after insert on public.assessment_assignees
  for each row execute function private.alert_assessment_assigned();

create function private.alert_assessment_unassigned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  assessment record;
  subject text;
  label text;
begin
  if old.user_id is not distinct from auth.uid() then
    return old;
  end if;
  select a.starts_at, a.all_day into assessment
  from public.assessments as a where a.organization_id = old.organization_id and a.id = old.assessment_id;
  if not found then
    return old;
  end if;
  subject := private.alert_assessment_label(old.organization_id, old.assessment_id);
  label := private.alert_assessment_when(old.organization_id, assessment.starts_at, assessment.all_day);
  perform private.record_schedule_alert(
    old.organization_id, old.user_id, 'schedule.removed', 'assessment', old.assessment_id,
    'You''re off ' || subject || case when label = '' then '' else ', ' || label end,
    'You''re off ' || subject || case when label = '' then '' else ', ' || label end,
    label
  );
  return old;
end;
$$;

revoke all on function private.alert_assessment_unassigned() from public, anon, authenticated;

create trigger assessment_assignees_alert_unassigned
  after delete on public.assessment_assignees
  for each row execute function private.alert_assessment_unassigned();

create function private.alert_assessment_moved()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  assignee record;
  subject text := private.alert_assessment_label(new.organization_id, new.id);
  label text := private.alert_assessment_when(new.organization_id, new.starts_at, new.all_day);
begin
  for assignee in
    select a.user_id from public.assessment_assignees as a
    where a.organization_id = new.organization_id and a.assessment_id = new.id
      and a.user_id is distinct from auth.uid()
      and not exists (
        select 1 from public.team_notifications as n
        where n.organization_id = new.organization_id and n.user_id = a.user_id
          and n.kind = 'schedule.assigned' and n.subject_id = new.id and n.email_available_at > now())
  loop
    perform private.record_schedule_alert(
      new.organization_id, assignee.user_id, 'schedule.changed', 'assessment', new.id,
      'Your Assessment moved: ' || subject || case when label = '' then '' else ', now ' || label end,
      'Your Assessment moved: ' || subject || case when label = '' then '' else ', now ' || label end,
      label
    );
  end loop;
  return new;
end;
$$;

revoke all on function private.alert_assessment_moved() from public, anon, authenticated;

create trigger assessments_alert_moved
  after update of starts_at, ends_at, all_day on public.assessments
  for each row
  when (old.starts_at is distinct from new.starts_at or old.ends_at is distinct from new.ends_at
    or old.all_day is distinct from new.all_day)
  execute function private.alert_assessment_moved();

create function private.alert_assessment_cancelled()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  assignee record;
  subject text := private.alert_assessment_label(old.organization_id, old.id);
  label text := private.alert_assessment_when(old.organization_id, old.starts_at, old.all_day);
begin
  for assignee in
    select a.user_id from public.assessment_assignees as a
    where a.organization_id = old.organization_id and a.assessment_id = old.id
      and a.user_id is distinct from auth.uid()
  loop
    perform private.record_schedule_alert(
      old.organization_id, assignee.user_id, 'schedule.changed', 'assessment', old.id,
      'Your Assessment was cancelled: ' || subject || case when label = '' then '' else ', ' || label end,
      'Your Assessment was cancelled: ' || subject || case when label = '' then '' else ', ' || label end,
      label
    );
  end loop;
  return old;
end;
$$;

revoke all on function private.alert_assessment_cancelled() from public, anon, authenticated;

create trigger assessments_alert_cancelled
  before delete on public.assessments
  for each row execute function private.alert_assessment_cancelled();

-- 12. A timer left running over 12 hours -------------------------------------------------------------------------
--
-- Called by the one-minute worker wake. One alert per timer (its id is the source key), however often it runs.

create function public.create_long_timer_alerts()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  created integer;
begin
  with due as (
    select t.id, t.organization_id, t.user_id, t.started_at,
      coalesce((select settings.timezone from public.organization_settings as settings
                where settings.organization_id = t.organization_id), 'UTC') as zone
    from public.running_timers as t
    where t.started_at < now() - interval '12 hours'
      and not exists (
        select 1 from public.team_notifications as n
        where n.organization_id = t.organization_id and n.user_id = t.user_id
          and n.source_key = 'timer_running_long:' || t.id)
    limit 200
  ),
  inserted as (
    insert into public.team_notifications (
      organization_id, user_id, kind, subject_type, subject_id, title, body, source_key
    )
    select due.organization_id, due.user_id, 'time.timer_running_long', 'running_timer', due.id,
      'Your timer has run over 12 hours',
      'It started ' || to_char(due.started_at at time zone due.zone, 'FMDy FMDD FMMon, FMHH12:MI am')
        || '. Stop it, or ask a manager to correct the end time, on Timesheets.',
      'timer_running_long:' || due.id
    from due
    where private.member_can_receive_alert(due.organization_id, due.user_id, 'time.timer_running_long')
    on conflict (organization_id, user_id, source_key) do nothing
    returning 1
  )
  select count(*) into created from inserted;
  return created;
end;
$$;

revoke all on function public.create_long_timer_alerts() from public, anon, authenticated;
grant execute on function public.create_long_timer_alerts() to service_role;

-- 13. A new customer message ----------------------------------------------------------------------------------------
--
-- Goes to the person who owns the conversation, else to everyone who can see the team's conversations.
-- Only a real, accepted customer reply: not auto-responses, delivery notices, or senders waiting for review.

create function private.alert_inbound_message()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  sender text;
  preview text;
  recipient uuid;
begin
  if new.message_kind <> 'reply' or new.review_status <> 'accepted' then
    return new;
  end if;

  select coalesce(
    (select nullif(btrim(client.display_name), '') from public.clients as client
     where client.organization_id = new.organization_id and client.id = new.client_id),
    nullif(btrim(new.sender_name), ''), nullif(btrim(new.sender_phone), ''),
    nullif(btrim(new.sender_email), ''), 'a customer'
  ) into sender;
  preview := left(regexp_replace(btrim(coalesce(new.text_content, '')), '\s+', ' ', 'g'), 200);

  for recipient in
    select membership.user_id
    from public.organization_members as membership
    where membership.organization_id = new.organization_id and membership.status = 'active'
      and (
        (new.owner_user_id is not null and membership.user_id = new.owner_user_id)
        or (new.owner_user_id is null
          and private.member_has_permission(new.organization_id, membership.user_id, 'conversations.view_team'))
      )
  loop
    if private.member_can_receive_alert(new.organization_id, recipient, 'communications.message_received') then
      insert into public.team_notifications (
        organization_id, user_id, kind, subject_type, subject_id, title, body, source_key
      ) values (
        new.organization_id, recipient, 'communications.message_received', 'inbound_message', new.id,
        left('New ' || case new.channel when 'sms' then 'text' else 'email' end || ' from ' || sender, 200),
        nullif(preview, ''), 'inbound_message:' || new.id
      )
      on conflict (organization_id, user_id, source_key) do nothing;
    end if;
  end loop;
  return new;
end;
$$;

revoke all on function private.alert_inbound_message() from public, anon, authenticated;

create trigger communication_inbound_messages_alert
  after insert on public.communication_inbound_messages
  for each row execute function private.alert_inbound_message();
