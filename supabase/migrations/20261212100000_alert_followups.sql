-- Part 12 follow-ups found while testing the first alerts migration.
--
-- 1. A finished Visit is a record, not a plan: putting someone on one, or removing one, tells nobody anything.
-- 2. Registering a computer: a computer belongs to one person at a time. If a different person registers the
--    same browser (a shared office PC), the previous person's entry and its waiting alerts end there.

create or replace function private.alert_visit_assigned()
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
  if new.user_id is not distinct from auth.uid() then
    return new;
  end if;
  select v.visit_date, v.start_time, v.all_day, v.completed_at into visit
  from public.job_visits as v where v.organization_id = new.organization_id and v.id = new.visit_id;
  if visit.completed_at is not null then
    return new;
  end if;
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

create or replace function private.alert_visit_cancelled()
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
  if old.completed_at is not null then
    return old;
  end if;
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

create or replace function private.alert_visit_unassigned()
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
  select v.visit_date, v.start_time, v.all_day, v.completed_at into visit
  from public.job_visits as v where v.organization_id = old.organization_id and v.id = old.visit_id;
  -- Gone (a cancelled Visit is announced on its own) or already finished.
  if not found or visit.completed_at is not null then
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

create function public.register_push_subscription(
  p_user_id uuid, p_endpoint text, p_p256dh text, p_auth_secret text, p_label text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing public.push_subscriptions%rowtype;
  subscription_id uuid;
begin
  select * into existing from public.push_subscriptions where endpoint = p_endpoint for update;
  if found and existing.user_id = p_user_id then
    update public.push_subscriptions
    set p256dh = p_p256dh, auth_secret = p_auth_secret, label = p_label
    where id = existing.id;
    return existing.id;
  end if;
  if found then
    -- Someone else signed in on this computer: it is theirs now, and the old entry's queue goes with it.
    delete from public.push_subscriptions where id = existing.id;
  end if;
  if (select count(*) from public.push_subscriptions where user_id = p_user_id) >= 20 then
    raise exception 'Too many computers are registered. Remove one first.' using errcode = 'check_violation';
  end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth_secret, label)
  values (p_user_id, p_endpoint, p_p256dh, p_auth_secret, p_label)
  returning id into subscription_id;
  return subscription_id;
end;
$$;

revoke all on function public.register_push_subscription(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.register_push_subscription(uuid, text, text, text, text) to service_role;
