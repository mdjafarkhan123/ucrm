-- Correction to 20260902150000: platform_package_version_limits_value_check requires
-- limit_value > 0 for a numeric row (see 20260810053742), matching every existing package
-- limit (employee_seats, the two email allowances). manage_platform_package_website_chat_limits
-- validated >= 0, which would let a numeric-0 draft save pass its own check only to fail the
-- table constraint with a worse error. Floor raised to >= 1, matching
-- manage_platform_package_email_allowances exactly.

create or replace function public.manage_platform_package_website_chat_limits(
  target_version_id uuid,
  target_widgets_state text,
  target_widgets_value integer,
  target_accepted_conversations_state text,
  target_accepted_conversations_value integer,
  actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.platform_package_versions%rowtype;
begin
  if char_length(trim(coalesce(actor_email, ''))) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if target_widgets_state not in ('unlimited', 'not_included', 'numeric')
    or target_accepted_conversations_state not in ('unlimited', 'not_included', 'numeric') then
    raise exception 'Choose a valid Website Chat limit type.' using errcode = 'check_violation';
  end if;
  if (target_widgets_state = 'numeric' and coalesce(target_widgets_value, 0) < 1)
    or (target_widgets_state <> 'numeric' and target_widgets_value is not null)
    or (target_accepted_conversations_state = 'numeric' and coalesce(target_accepted_conversations_value, 0) < 1)
    or (target_accepted_conversations_state <> 'numeric' and target_accepted_conversations_value is not null) then
    raise exception 'A numeric Website Chat limit must be at least one.' using errcode = 'check_violation';
  end if;

  select * into version_row
  from public.platform_package_versions
  where id = target_version_id
  for update;
  if not found or version_row.status <> 'draft' then
    raise exception 'Website Chat limits can only be changed on a draft package version.' using errcode = 'check_violation';
  end if;

  delete from public.platform_package_version_limits
  where package_version_id = version_row.id
    and limit_key in ('website_chat_widgets', 'website_chat_accepted_conversations');

  insert into public.platform_package_version_limits (package_version_id, limit_key, limit_state, limit_value)
  values
    (version_row.id, 'website_chat_widgets', target_widgets_state,
      case when target_widgets_state = 'numeric' then target_widgets_value end),
    (version_row.id, 'website_chat_accepted_conversations', target_accepted_conversations_state,
      case when target_accepted_conversations_state = 'numeric' then target_accepted_conversations_value end);

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    lower(trim(actor_email)), 'package.website_chat_limits_changed', 'platform_package_version', version_row.id::text,
    jsonb_build_object(
      'widgets_state', target_widgets_state, 'widgets_value', target_widgets_value,
      'accepted_conversations_state', target_accepted_conversations_state,
      'accepted_conversations_value', target_accepted_conversations_value
    )
  );
  return version_row.id;
end;
$$;
