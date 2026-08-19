-- Part 5a: explicit "Mark reviewed" transition (new -> awaiting_payment) plus duplicate
-- acknowledge/close handling. Duplicate matches themselves are computed at read time from
-- the existing platform_onboarding_applications rows (same fields the submission RPC already
-- checks), so nothing here stores a separate candidate list -- only the acknowledgment state.

alter table public.platform_onboarding_applications
  add column duplicate_acknowledged_at timestamptz,
  add column duplicate_acknowledged_by_owner_email text,
  add constraint platform_onboarding_applications_duplicate_ack_check check (
    (duplicate_acknowledged_at is null) = (duplicate_acknowledged_by_owner_email is null)
    and (duplicate_acknowledged_at is null or possible_duplicate)
  );

create or replace function public.mark_onboarding_application_reviewed(
  target_application_id uuid,
  actor_email text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
begin
  select stage into app_stage
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage <> 'new' then
    raise exception 'Only a new application can be marked reviewed.' using errcode = 'check_violation';
  end if;

  update public.platform_onboarding_applications
  set stage = 'awaiting_payment'
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key
  ) values (
    actor_email, 'onboarding_application.reviewed', 'onboarding_application', target_application_id::text
  );
end;
$$;

revoke all on function public.mark_onboarding_application_reviewed(uuid, text)
  from public, anon, authenticated;
grant execute on function public.mark_onboarding_application_reviewed(uuid, text)
  to service_role;

create or replace function public.acknowledge_onboarding_application_duplicate(
  target_application_id uuid,
  actor_email text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
  app_possible_duplicate boolean;
  app_already_acknowledged boolean;
begin
  select stage, possible_duplicate, duplicate_acknowledged_at is not null
  into app_stage, app_possible_duplicate, app_already_acknowledged
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if not app_possible_duplicate then
    raise exception 'This application was not flagged as a possible duplicate.' using errcode = 'check_violation';
  end if;
  if app_already_acknowledged then
    raise exception 'This possible duplicate was already acknowledged.' using errcode = 'check_violation';
  end if;
  if app_stage not in ('new', 'awaiting_payment', 'needs_attention') then
    raise exception 'Only an unpaid application can have its duplicate flag acknowledged.'
      using errcode = 'check_violation';
  end if;

  update public.platform_onboarding_applications
  set duplicate_acknowledged_at = now(), duplicate_acknowledged_by_owner_email = actor_email
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key
  ) values (
    actor_email, 'onboarding_application.duplicate_acknowledged', 'onboarding_application',
    target_application_id::text
  );
end;
$$;

revoke all on function public.acknowledge_onboarding_application_duplicate(uuid, text)
  from public, anon, authenticated;
grant execute on function public.acknowledge_onboarding_application_duplicate(uuid, text)
  to service_role;

-- Extend not-proceeding with an optional reason, required only while the application is
-- still an unacknowledged possible duplicate (the "close as duplicate" path). An ordinary
-- not-proceeding decision keeps working without a reason, matching the already-verified
-- Part 4 behavior for that case.
drop function if exists public.mark_onboarding_application_not_proceeding(uuid, text);

create or replace function public.mark_onboarding_application_not_proceeding(
  target_application_id uuid,
  actor_email text,
  reason text default null
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
  app_possible_duplicate boolean;
  app_already_acknowledged boolean;
  clean_reason text;
begin
  select stage, possible_duplicate, duplicate_acknowledged_at is not null
  into app_stage, app_possible_duplicate, app_already_acknowledged
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage not in ('new', 'awaiting_payment', 'needs_attention') then
    raise exception 'Only an unpaid application can be marked not proceeding.' using errcode = 'check_violation';
  end if;

  clean_reason := nullif(trim(coalesce(reason, '')), '');
  if app_possible_duplicate and not app_already_acknowledged and clean_reason is null then
    raise exception 'A private reason is required to close a possible duplicate.'
      using errcode = 'check_violation';
  end if;

  update public.platform_onboarding_applications
  set stage = 'not_proceeding', not_proceeding_at = now()
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    actor_email, 'onboarding_application.not_proceeding', 'onboarding_application', target_application_id::text,
    case when clean_reason is null then null else jsonb_build_object('reason', clean_reason) end
  );
end;
$$;

revoke all on function public.mark_onboarding_application_not_proceeding(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.mark_onboarding_application_not_proceeding(uuid, text, text)
  to service_role;
