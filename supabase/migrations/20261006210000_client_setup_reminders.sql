-- Client onboarding C6: setup reminder emails after about 24 hours, 3 days and 7 days of inactivity.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §5 — incomplete-setup email reminders go out
-- around 24 hours, 3 days and 7 days after inactivity, link to the exact unfinished task, and stop after
-- submission, an opt-out, or a human deferral. Industry reference: inactivity-triggered onboarding nudges
-- (Intercom series "wait until inactive", Customer.io and Appcues drip reminders): any activity restarts the
-- clock, a fixed number of reminders per quiet stretch, sent in the recipient's daytime, each pointing at the
-- next step.
--
-- Shape: the timer-table pattern already used by support's unseen-reply emails. Each paid client has one row,
-- created when its account is provisioned. Any setup activity (an answer saved or cleared, a section marked or
-- unmarked, the welcome seen) restarts its quiet stretch and makes the first reminder due 24 hours later. The
-- email worker's once-a-minute wake reads only due rows through a partial index, so its work grows with
-- reminders due now, never with clients or answers. Whether setup is still unfinished and which task is next
-- is decided in the app, where the task list lives (ADR 0005).

-- 1. The timer --------------------------------------------------------------------------------------------

create table public.organization_setup_reminders (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  -- The start of the current quiet stretch: the account's creation, or the last setup activity since.
  last_activity_at timestamptz not null,
  -- Reminders already sent in this quiet stretch, 0 to 3.
  reminders_sent smallint not null default 0,
  -- When the next reminder should be looked at. Null means none is waiting: three were sent, or setup is done.
  next_due_at timestamptz,
  last_sent_at timestamptz,
  -- Uplift's deferral (§5 "a human deferral"). While set, no reminder goes out.
  paused_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_setup_reminders_sent_check check (reminders_sent between 0 and 3)
);

comment on table public.organization_setup_reminders is
  'One setup-reminder timer per paid client (client onboarding C6). Written only by triggers on setup activity and provisioning and by the email worker''s functions. Service role only.';

-- The wake's only read: timers that are due and not paused, soonest first.
create index organization_setup_reminders_due_idx
  on public.organization_setup_reminders (next_due_at)
  where next_due_at is not null and paused_at is null;

create trigger organization_setup_reminders_set_updated_at
  before update on public.organization_setup_reminders
  for each row execute function public.set_updated_at();

alter table public.organization_setup_reminders enable row level security;
revoke all on table public.organization_setup_reminders from public, anon, authenticated;
grant select, insert, update, delete on table public.organization_setup_reminders to service_role;

-- 2. Turning them off for yourself ------------------------------------------------------------------------

-- A row means this person asked not to get setup reminders for this business. Other owners and
-- administrators still get theirs.
create table public.organization_setup_reminder_opt_outs (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

comment on table public.organization_setup_reminder_opt_outs is
  'People who turned setup reminder emails off for one business. Each person reads only their own row; changes arrive through public.set_my_setup_reminder_emails.';

create index organization_setup_reminder_opt_outs_user_id_idx
  on public.organization_setup_reminder_opt_outs (user_id);

alter table public.organization_setup_reminder_opt_outs enable row level security;
revoke all on table public.organization_setup_reminder_opt_outs from public, anon, authenticated;
grant select on table public.organization_setup_reminder_opt_outs to authenticated;
grant select, insert, update, delete on table public.organization_setup_reminder_opt_outs to service_role;

create policy organization_setup_reminder_opt_outs_select_own
  on public.organization_setup_reminder_opt_outs
  for select to authenticated
  using (user_id = (select auth.uid()));

create function public.set_my_setup_reminder_emails(target_organization_id uuid, emails_on boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  if not private.is_organization_admin(target_organization_id)
    or not private.has_permission(target_organization_id, 'settings.business.view') then
    raise exception 'Only an owner or administrator can change setup.'
      using errcode = 'insufficient_privilege';
  end if;

  if emails_on then
    delete from public.organization_setup_reminder_opt_outs
    where organization_id = target_organization_id and user_id = (select auth.uid());
  else
    insert into public.organization_setup_reminder_opt_outs (organization_id, user_id)
    values (target_organization_id, (select auth.uid()))
    on conflict (organization_id, user_id) do nothing;
  end if;

  return jsonb_build_object('emails_on', emails_on);
end;
$$;

revoke all on function public.set_my_setup_reminder_emails(uuid, boolean) from public, anon;
grant execute on function public.set_my_setup_reminder_emails(uuid, boolean) to authenticated;

-- 3. Activity restarts the clock --------------------------------------------------------------------------

-- Only paid clients have a timer, so activity anywhere else changes nothing.
create function private.note_organization_setup_activity(target_organization_id uuid)
returns void
language sql
security definer
set search_path to ''
as $$
  update public.organization_setup_reminders
  set last_activity_at = now(),
      reminders_sent = 0,
      next_due_at = now() + interval '24 hours'
  where organization_id = target_organization_id
    -- An autosave writes several answers in one statement; the first one already restarted the clock.
    and last_activity_at <> now();
$$;

create function private.organization_setup_activity_trigger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform private.note_organization_setup_activity(
    case when tg_op = 'DELETE' then old.organization_id else new.organization_id end
  );
  return null;
end;
$$;

create trigger organization_setup_answers_note_activity
  after insert or update or delete on public.organization_setup_answers
  for each row execute function private.organization_setup_activity_trigger();

create trigger organization_setup_sections_note_activity
  after insert or delete on public.organization_setup_sections
  for each row execute function private.organization_setup_activity_trigger();

create trigger organization_setup_note_activity
  after insert or update of welcome_seen_at on public.organization_setup
  for each row execute function private.organization_setup_activity_trigger();

-- A paid client's account exists: its first quiet stretch starts now.
create function private.start_organization_setup_reminders()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into public.organization_setup_reminders (organization_id, last_activity_at, next_due_at)
  values (new.organization_id, now(), now() + interval '24 hours')
  on conflict (organization_id) do nothing;
  return null;
end;
$$;

create trigger platform_onboarding_application_provisions_start_setup_reminders
  after insert or update of status, organization_id on public.platform_onboarding_application_provisions
  for each row
  when (new.status = 'succeeded' and new.organization_id is not null)
  execute function private.start_organization_setup_reminders();

revoke all on function private.note_organization_setup_activity(uuid) from public, anon, authenticated;
revoke all on function private.organization_setup_activity_trigger() from public, anon, authenticated;
revoke all on function private.start_organization_setup_reminders() from public, anon, authenticated;

-- Paid clients that already exist start from their real last activity. Nobody is reminded sooner than 24
-- hours from now, so the change itself never sends a burst.
insert into public.organization_setup_reminders (organization_id, last_activity_at, next_due_at)
select
  provision.organization_id,
  greatest(
    provision.created_at,
    setup.welcome_seen_at,
    (select max(answer.updated_at) from public.organization_setup_answers as answer
      where answer.organization_id = provision.organization_id),
    (select max(section.completed_at) from public.organization_setup_sections as section
      where section.organization_id = provision.organization_id)
  ),
  now() + interval '24 hours'
from public.platform_onboarding_application_provisions as provision
left join public.organization_setup as setup on setup.organization_id = provision.organization_id
where provision.status = 'succeeded' and provision.organization_id is not null
on conflict (organization_id) do nothing;

-- 4. What the email worker sends --------------------------------------------------------------------------

-- Up to `batch_size` due reminders, each with the business, its quiet stretch, whether a support message of
-- theirs is waiting on Uplift, and the people to email: active owners and administrators who have an email
-- address and have not turned reminders off. Two kinds of due timer are moved on here instead of returned:
-- a business that is paused, closing, or whose payment was reversed is looked at again in a day, and one
-- whose local time is night (before 8:00 or from 20:00) waits for 9:00 there. Service role only.
create function public.due_organization_setup_reminders(batch_size integer)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  result jsonb;
begin
  with due as (
    select
      reminder.organization_id,
      reminder.last_activity_at,
      reminder.reminders_sent,
      organization.name as organization_name,
      organization.lifecycle_status,
      coalesce(settings.timezone, 'UTC') as timezone,
      exists (
        select 1
        from public.platform_onboarding_application_provisions as provision
        join public.platform_onboarding_applications as application on application.id = provision.application_id
        where provision.organization_id = reminder.organization_id
          and application.payment_reversed_at is not null
      ) as payment_reversed
    from public.organization_setup_reminders as reminder
    join public.organizations as organization on organization.id = reminder.organization_id
    left join public.organization_settings as settings on settings.organization_id = reminder.organization_id
    where reminder.next_due_at <= now() and reminder.paused_at is null
    order by reminder.next_due_at
    limit least(greatest(batch_size, 1), 200)
    for update of reminder skip locked
  ),
  placed as (
    select
      due.*,
      (now() at time zone due.timezone) as local_now
    from due
  ),
  decided as (
    select
      placed.*,
      case
        when placed.lifecycle_status <> 'active' or placed.payment_reversed then now() + interval '1 day'
        when extract(hour from placed.local_now) < 8 then
          (date_trunc('day', placed.local_now) + interval '9 hours') at time zone placed.timezone
        when extract(hour from placed.local_now) >= 20 then
          (date_trunc('day', placed.local_now) + interval '1 day 9 hours') at time zone placed.timezone
      end as wait_until
    from placed
  ),
  waited as (
    update public.organization_setup_reminders as reminder
    set next_due_at = decided.wait_until
    from decided
    where reminder.organization_id = decided.organization_id and decided.wait_until is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id', decided.organization_id,
    'organization_name', decided.organization_name,
    'last_activity_at', decided.last_activity_at,
    'reminders_sent', decided.reminders_sent,
    'support_waiting', exists (
      select 1 from public.support_threads as thread
      where thread.organization_id = decided.organization_id
        and thread.last_message_sender_kind = 'member'
        and thread.last_message_at > coalesce(thread.uplift_last_read_at, '-infinity'::timestamptz)
    ),
    'recipients', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', membership.user_id,
        'email', account.email,
        'name', private.support_member_name(membership.user_id)
      ) order by membership.created_at, membership.user_id)
      from public.organization_members as membership
      join auth.users as account on account.id = membership.user_id
      where membership.organization_id = decided.organization_id
        and membership.status = 'active'
        and membership.role in ('owner', 'admin')
        and nullif(btrim(account.email), '') is not null
        and not exists (
          select 1 from public.organization_setup_reminder_opt_outs as opt_out
          where opt_out.organization_id = decided.organization_id and opt_out.user_id = membership.user_id
        )
    ), '[]'::jsonb)
  ) order by decided.last_activity_at), '[]'::jsonb)
  into result
  from decided
  where decided.wait_until is null;

  return result;
end;
$$;

-- What the wake did with one due reminder, for the quiet stretch it read. If the client did something in the
-- meantime the stretch has restarted, and this changes nothing.
--   sent      the reminder went out: count it and set the next one (3 days, then 7 days, after the start of the
--             stretch, never sooner than a day from now), or none after the third
--   finished  setup has nothing left for the client to do: no reminder waits until they change something
--   later     not now (a support message of theirs is waiting on Uplift): look again at `look_again_at`
create function public.record_organization_setup_reminder(
  target_organization_id uuid,
  seen_last_activity_at timestamptz,
  outcome text,
  look_again_at timestamptz default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if outcome = 'sent' then
    update public.organization_setup_reminders
    set reminders_sent = reminders_sent + 1,
        last_sent_at = now(),
        next_due_at = case reminders_sent + 1
          when 1 then greatest(last_activity_at + interval '3 days', now() + interval '1 day')
          when 2 then greatest(last_activity_at + interval '7 days', now() + interval '1 day')
        end
    where organization_id = target_organization_id
      and last_activity_at = seen_last_activity_at
      and reminders_sent < 3;
  elsif outcome = 'finished' then
    update public.organization_setup_reminders
    set next_due_at = null
    where organization_id = target_organization_id and last_activity_at = seen_last_activity_at;
  elsif outcome = 'later' and look_again_at is not null then
    update public.organization_setup_reminders
    set next_due_at = look_again_at
    where organization_id = target_organization_id and last_activity_at = seen_last_activity_at;
  else
    raise exception 'Unknown setup reminder outcome.' using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.due_organization_setup_reminders(integer) from public, anon, authenticated;
revoke all on function public.record_organization_setup_reminder(uuid, timestamptz, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.due_organization_setup_reminders(integer) to service_role;
grant execute on function public.record_organization_setup_reminder(uuid, timestamptz, text, timestamptz)
  to service_role;
