-- CRM launch readiness Part 4, Stage 4: the team hears about every website inquiry.
--
-- Established pattern (docs/research/website-speed-to-lead-patterns-2026-09-17.md, "Staff alert recipients"):
--   * Jobber — a new public request always alerts staff (activity/notifications plus email) through a settings-
--     level notification, not through an optional automation. Recipients are chosen from users who may see it.
--   * Housecall Pro — when nobody is chosen, the account owner is alerted instead, so a lead never reaches nobody.
--   * HighLevel — "Stop on Response" alerts the team when the contact replies to a workflow message.
-- Jafar approved 2026-09-17: the alert always goes out (independent of any recipe), and the contractor app's
-- header bell becomes a per-person alert list alongside the email.
--
-- Shape:
--   1. inquiry_alert_recipients — the contractor's chosen people. Empty means "account owner only".
--   2. team_notifications — one row per person per alert. It is the bell's list AND the email queue: the email
--      columns are claimed with SKIP LOCKED by the background worker, which sends from the platform's system
--      address (a team alert is not a customer message and never spends the contractor's email allowance).
--   3. Alerts are created inside the transaction that establishes the fact: a website_inquiry.received event
--      insert, or an inquiry enrollment pausing on a customer reply. A unique source key makes replay harmless.
--
-- Deliberately NOT here: per-person email opt-out, mobile push (excluded by the website chat contract), a
-- generic notification catalog for other domains, and Resume/Skip/Stop controls on the inquiry record (Stage 6).

-- ---------------------------------------------------------------------------------------------------
-- 1. Who may receive an inquiry alert: someone who can already see every inquiry.
-- ---------------------------------------------------------------------------------------------------
-- A form inquiry lands in Requests and a chat lands in the team inbox, so a recipient needs the whole team
-- inbox (conversations.view_team) and every Request, not only assigned ones. By default: owner and admin.
create function private.member_receives_inquiry_alerts(p_organization_id uuid, p_user_id uuid)
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
    and private.member_has_permission(p_organization_id, p_user_id, 'conversations.view_team')
    and private.member_has_permission(p_organization_id, p_user_id, 'requests.view')
    and private.member_permission_scope(p_organization_id, p_user_id, 'requests.view') = 'all';
$$;

revoke all on function private.member_receives_inquiry_alerts(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- 2. The chosen recipients.
-- ---------------------------------------------------------------------------------------------------
create table public.inquiry_alert_recipients (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id),
  constraint inquiry_alert_recipients_member_fk foreign key (organization_id, user_id)
    references public.organization_members (organization_id, user_id) on delete cascade
);

comment on table public.inquiry_alert_recipients is
  'Team members a contractor chose to alert about new website inquiries. Empty means only the account owner '
  'is alerted and Settings warns. Written only through public.set_inquiry_alert_recipients.';

create index inquiry_alert_recipients_created_by_idx
  on public.inquiry_alert_recipients (created_by) where created_by is not null;

alter table public.inquiry_alert_recipients enable row level security;
revoke all on public.inquiry_alert_recipients from anon, authenticated;
grant select on public.inquiry_alert_recipients to service_role;

-- The people an alert goes to right now: chosen recipients who still qualify, else the active owner.
-- A chosen person who lost access is skipped, and if that leaves nobody the owner is alerted instead.
create function private.inquiry_alert_recipient_ids(p_organization_id uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  found_any boolean := false;
  recipient uuid;
begin
  for recipient in
    select r.user_id from public.inquiry_alert_recipients as r
    where r.organization_id = p_organization_id
      and private.member_receives_inquiry_alerts(p_organization_id, r.user_id)
  loop
    found_any := true;
    return next recipient;
  end loop;

  if not found_any then
    return query
      select m.user_id from public.organization_members as m
      where m.organization_id = p_organization_id and m.role = 'owner' and m.status = 'active';
  end if;
end;
$$;

revoke all on function private.inquiry_alert_recipient_ids(uuid) from public, anon, authenticated, service_role;

-- Replace the whole chosen set in one step. Every person must qualify; an empty list restores owner-only.
create function public.set_inquiry_alert_recipients(
  p_organization_id uuid,
  p_actor_id uuid,
  p_user_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  wanted uuid[] := coalesce((select array_agg(distinct u) from unnest(p_user_ids) as u where u is not null), '{}');
begin
  if p_organization_id is null or p_actor_id is null then
    raise exception 'An organization and an actor are required.' using errcode = 'check_violation';
  end if;
  if cardinality(wanted) > 50 then
    raise exception 'Choose at most 50 people.' using errcode = 'check_violation';
  end if;
  if not private.member_has_permission(p_organization_id, p_actor_id, 'conversations.manage_connections') then
    raise exception 'You do not have permission to change inquiry alerts.' using errcode = 'insufficient_privilege';
  end if;
  if exists (
    select 1 from unnest(wanted) as u
    where not private.member_receives_inquiry_alerts(p_organization_id, u)
  ) then
    raise exception 'Someone chosen cannot see every website inquiry.' using errcode = 'check_violation';
  end if;

  -- Serialize concurrent saves for one organization so the last save wins as a whole set.
  perform pg_advisory_xact_lock(hashtextextended('inquiry_alert_recipients:' || p_organization_id::text, 0));

  delete from public.inquiry_alert_recipients
  where organization_id = p_organization_id and user_id <> all (wanted);

  insert into public.inquiry_alert_recipients (organization_id, user_id, created_by)
  select p_organization_id, u, p_actor_id from unnest(wanted) as u
  on conflict (organization_id, user_id) do nothing;

  return cardinality(wanted);
end;
$$;

revoke all on function public.set_inquiry_alert_recipients(uuid, uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.set_inquiry_alert_recipients(uuid, uuid, uuid[]) to service_role;

-- The Settings screen's list: active members, whether each may be chosen, and whether each is chosen.
create function public.inquiry_alert_members(p_organization_id uuid)
returns table (
  user_id uuid,
  role text,
  full_name text,
  email text,
  can_receive boolean,
  chosen boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select m.user_id, m.role, p.full_name, u.email::text,
    private.member_receives_inquiry_alerts(m.organization_id, m.user_id),
    exists (
      select 1 from public.inquiry_alert_recipients as r
      where r.organization_id = m.organization_id and r.user_id = m.user_id
    )
  from public.organization_members as m
  left join public.profiles as p on p.id = m.user_id
  left join auth.users as u on u.id = m.user_id
  where m.organization_id = p_organization_id and m.status = 'active'
  order by (m.role = 'owner') desc, p.full_name nulls last, m.user_id
  limit 500;
$$;

revoke all on function public.inquiry_alert_members(uuid) from public, anon, authenticated;
grant execute on function public.inquiry_alert_members(uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. The alerts: the bell list and the email queue.
-- ---------------------------------------------------------------------------------------------------
create table public.team_notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null,
  kind text not null check (kind in ('website_inquiry.received', 'website_inquiry.customer_replied')),
  subject_type text not null check (subject_type in ('form_submission', 'website_chat_session')),
  subject_id uuid not null,
  title text not null check (char_length(btrim(title)) between 1 and 200),
  body text check (body is null or char_length(body) <= 500),
  -- Makes creation idempotent: one alert per person per source fact.
  source_key text not null check (char_length(source_key) between 1 and 200),
  read_at timestamptz,
  created_at timestamptz not null default now(),
  email_state text not null default 'pending'
    check (email_state in ('pending', 'sent', 'failed', 'not_needed')),
  email_attempts integer not null default 0 check (email_attempts >= 0),
  email_available_at timestamptz not null default now(),
  email_claim_token uuid,
  email_claimed_until timestamptz,
  email_sent_at timestamptz,
  email_last_error text check (email_last_error is null or char_length(email_last_error) <= 500),
  constraint team_notifications_member_fk foreign key (organization_id, user_id)
    references public.organization_members (organization_id, user_id) on delete cascade,
  constraint team_notifications_source_unique unique (organization_id, user_id, source_key),
  constraint team_notifications_claim_pair_check
    check ((email_claim_token is null) = (email_claimed_until is null))
);

comment on table public.team_notifications is
  'Per-person team alerts shown in the contractor header bell and emailed once from the system address. '
  'Only read_at is changed by the person; email_* columns belong to the background worker.';

-- The bell: newest first for one person, and the unread count.
create index team_notifications_user_recent_idx
  on public.team_notifications (user_id, organization_id, created_at desc, id desc);
create index team_notifications_user_unread_idx
  on public.team_notifications (user_id, organization_id) where read_at is null;
-- The email queue.
create index team_notifications_email_queue_idx
  on public.team_notifications (email_available_at, id) where email_state = 'pending';

alter table public.team_notifications enable row level security;

create policy "members read their own team notifications"
  on public.team_notifications for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.team_notifications from anon, authenticated;
grant select on public.team_notifications to authenticated;
grant select on public.team_notifications to service_role;

-- Creates one alert per current recipient. Titles are frozen so the bell reads the same later.
create function private.create_inquiry_alerts(
  p_organization_id uuid,
  p_kind text,
  p_subject_type text,
  p_subject_id uuid,
  p_source_key text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  who text;
  form_name text;
  alert_title text;
  alert_body text;
  created_count integer;
begin
  if p_subject_type = 'form_submission' then
    select coalesce(nullif(btrim(c.display_name), ''), nullif(btrim(s.contact ->> 'name'), '')), f.name
    into who, form_name
    from private.form_submissions as s
    left join public.forms as f on f.id = s.form_id and f.organization_id = s.organization_id
    left join public.clients as c
      on c.organization_id = s.organization_id and c.id = nullif(s.result ->> 'client_id', '')::uuid
    where s.organization_id = p_organization_id and s.id = p_subject_id;
  elsif p_subject_type = 'website_chat_session' then
    select coalesce(nullif(btrim(c.display_name), ''), nullif(btrim(s.visitor_name), ''))
    into who
    from public.website_chat_sessions as s
    left join public.clients as c on c.organization_id = s.organization_id and c.id = s.client_id
    where s.organization_id = p_organization_id and s.id = p_subject_id;
  end if;
  who := left(coalesce(who, 'a website visitor'), 120);

  if p_kind = 'website_inquiry.received' then
    alert_title := 'New website inquiry from ' || who;
    alert_body := case when p_subject_type = 'website_chat_session'
      then 'Started a Website Chat.'
      else 'Sent the ' || left(coalesce(form_name, 'website'), 120) || ' form.' end;
  else
    alert_title := who || ' replied to your automatic follow-up';
    alert_body := 'The follow-up is paused so someone on your team can answer.';
  end if;

  insert into public.team_notifications (
    organization_id, user_id, kind, subject_type, subject_id, title, body, source_key
  )
  select p_organization_id, recipient, p_kind, p_subject_type, p_subject_id, alert_title, alert_body, p_source_key
  from private.inquiry_alert_recipient_ids(p_organization_id) as recipient
  on conflict (organization_id, user_id, source_key) do nothing;

  get diagnostics created_count = row_count;
  return created_count;
end;
$$;

revoke all on function private.create_inquiry_alerts(uuid, text, text, uuid, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. When alerts are created.
-- ---------------------------------------------------------------------------------------------------
-- A new inquiry: the event row exists only once per inquiry (its source key collapses replays), so this fires
-- once, in the same transaction as the form result or the accepted chat.
create function private.alert_team_on_inquiry_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  perform private.create_inquiry_alerts(
    new.organization_id, 'website_inquiry.received', new.subject_type, new.subject_id,
    'inquiry:' || new.subject_type || ':' || new.subject_id::text
  );
  return null;
end;
$$;

revoke all on function private.alert_team_on_inquiry_event() from public, anon, authenticated;

create trigger automation_events_alert_team_on_inquiry
  after insert on private.automation_events
  for each row
  when (new.event_type = 'website_inquiry.received')
  execute function private.alert_team_on_inquiry_event();

-- A customer reply paused an inquiry follow-up. Only the reply-pause moves customer_reply_after while pausing
-- (20261005120000); a staff Pause leaves it untouched, so a staff action never alerts the team about itself.
create function private.alert_team_on_inquiry_reply_pause()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  perform private.create_inquiry_alerts(
    new.organization_id, 'website_inquiry.customer_replied', new.subject_type, new.subject_id,
    'reply_pause:' || new.id::text || ':' || to_char(new.customer_reply_after at time zone 'UTC',
      'YYYYMMDDHH24MISSUS')
  );
  return null;
end;
$$;

revoke all on function private.alert_team_on_inquiry_reply_pause() from public, anon, authenticated;

create trigger automation_enrollments_alert_team_on_reply_pause
  after update of state, customer_reply_after on private.automation_enrollments
  for each row
  when (
    new.state = 'paused' and old.state = 'active'
    and new.subject_type in ('form_submission', 'website_chat_session')
    and new.customer_reply_after is not null
    and new.customer_reply_after is distinct from old.customer_reply_after
  )
  execute function private.alert_team_on_inquiry_reply_pause();

-- ---------------------------------------------------------------------------------------------------
-- 5. Reading and marking alerts (called by /api routes with the signed-in person's id).
-- ---------------------------------------------------------------------------------------------------
create function public.mark_team_notifications_read(
  p_organization_id uuid,
  p_user_id uuid,
  p_notification_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  changed integer;
begin
  if p_notification_ids is not null and cardinality(p_notification_ids) > 100 then
    raise exception 'Mark at most 100 alerts at once.' using errcode = 'check_violation';
  end if;

  -- Null ids means "mark all as read".
  update public.team_notifications
  set read_at = now()
  where organization_id = p_organization_id and user_id = p_user_id and read_at is null
    and (p_notification_ids is null or id = any (p_notification_ids));

  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke all on function public.mark_team_notifications_read(uuid, uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.mark_team_notifications_read(uuid, uuid, uuid[]) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 6. The email queue.
-- ---------------------------------------------------------------------------------------------------
-- Claims a bounded batch. A person who no longer qualifies (removed, deactivated, lost access) or has no
-- sign-in email is settled as not_needed instead of being emailed; that check runs only on the claimed batch.
-- An expired lease is claimable again.
create function public.claim_team_notification_emails(
  p_batch_size integer default 25,
  p_lease_seconds integer default 120
)
returns table (
  notification_id uuid,
  claim_token uuid,
  organization_id uuid,
  organization_name text,
  recipient_email text,
  kind text,
  subject_type text,
  subject_id uuid,
  title text,
  body text,
  attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  token uuid;
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
    if candidate.email is null
      or not private.member_receives_inquiry_alerts(candidate.organization_id, candidate.user_id) then
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

revoke all on function public.claim_team_notification_emails(integer, integer) from public, anon, authenticated;
grant execute on function public.claim_team_notification_emails(integer, integer) to service_role;

-- Settles one claimed email. A failure retries with exponential backoff (1, 2, 4, 8 minutes) and stops after
-- five attempts; the bell still shows the alert either way.
create function public.settle_team_notification_email(
  p_notification_id uuid,
  p_claim_token uuid,
  p_sent boolean,
  p_error text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  row_attempts integer;
  max_attempts constant integer := 5;
begin
  select email_attempts into row_attempts from public.team_notifications
  where id = p_notification_id and email_claim_token = p_claim_token and email_state = 'pending'
  for update;
  if not found then
    return 'claim_lost';
  end if;

  if p_sent then
    update public.team_notifications
    set email_state = 'sent', email_sent_at = now(), email_attempts = row_attempts + 1,
      email_claim_token = null, email_claimed_until = null, email_last_error = null
    where id = p_notification_id;
    return 'sent';
  end if;

  update public.team_notifications
  set email_attempts = row_attempts + 1,
    email_state = case when row_attempts + 1 >= max_attempts then 'failed' else 'pending' end,
    email_available_at = now() + make_interval(mins => power(2, row_attempts)::integer),
    email_claim_token = null, email_claimed_until = null,
    email_last_error = left(coalesce(p_error, 'The alert email could not be sent.'), 500)
  where id = p_notification_id;
  return case when row_attempts + 1 >= max_attempts then 'failed' else 'retry' end;
end;
$$;

revoke all on function public.settle_team_notification_email(uuid, uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.settle_team_notification_email(uuid, uuid, boolean, text) to service_role;
