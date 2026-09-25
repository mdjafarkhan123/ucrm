-- Google review campaign Part 1 fix: a stale save of review settings looped forever.
--
-- save_review_settings refused a stale revision with SQLSTATE 40001 (serialization_failure). PostgREST
-- treats 40001 as a transient transaction failure and re-runs the call itself, so a stale save never
-- returned: the request hung and the database re-ran the function in a tight loop. The refusal now uses
-- P0409, the project's conflict code, which PostgREST passes straight back. The body is otherwise unchanged.

create or replace function public.save_review_settings(
  p_organization_id uuid,
  p_actor_id uuid,
  p_expected_revision integer,
  p_google_review_url text,
  p_routing_enabled boolean,
  p_routing_google_min_rating smallint,
  p_acknowledge_routing boolean,
  p_feedback_form jsonb,
  p_message_styles jsonb
) returns public.review_settings
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  current_row public.review_settings;
  clean_url text := nullif(trim(coalesce(p_google_review_url, '')), '');
  saved public.review_settings;
begin
  if p_organization_id is null or p_actor_id is null then
    raise exception 'An organization and an actor are required.' using errcode = 'check_violation';
  end if;
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.manage') then
    raise exception 'You do not have permission to change review settings.' using errcode = 'insufficient_privilege';
  end if;

  select * into current_row from public.review_settings
  where organization_id = p_organization_id
  for update;

  if coalesce(current_row.revision, 0) <> coalesce(p_expected_revision, -1) then
    raise exception 'Review settings changed since you opened them.' using errcode = 'P0409';
  end if;

  if p_routing_enabled and clean_url is null then
    raise exception 'Add your Google review link before turning on review routing.' using errcode = 'check_violation';
  end if;
  if p_routing_enabled and not coalesce(current_row.routing_enabled, false) and not coalesce(p_acknowledge_routing, false) then
    raise exception 'Accept the review routing warning to turn it on.' using errcode = 'check_violation';
  end if;

  insert into public.review_settings as s (
    organization_id, google_review_url, routing_enabled, routing_google_min_rating,
    routing_acknowledged_at, routing_acknowledged_by, feedback_form, message_styles,
    revision, updated_at, updated_by
  )
  values (
    p_organization_id, clean_url, coalesce(p_routing_enabled, false), coalesce(p_routing_google_min_rating, 4),
    case when p_routing_enabled then now() end,
    case when p_routing_enabled then p_actor_id end,
    p_feedback_form, p_message_styles, 1, now(), p_actor_id
  )
  on conflict (organization_id) do update
  set google_review_url = excluded.google_review_url,
      routing_enabled = excluded.routing_enabled,
      routing_google_min_rating = excluded.routing_google_min_rating,
      routing_acknowledged_at = case
        when not excluded.routing_enabled then null
        when s.routing_enabled then s.routing_acknowledged_at
        else now() end,
      routing_acknowledged_by = case
        when not excluded.routing_enabled then null
        when s.routing_enabled then s.routing_acknowledged_by
        else p_actor_id end,
      feedback_form = excluded.feedback_form,
      message_styles = excluded.message_styles,
      revision = s.revision + 1,
      updated_at = now(),
      updated_by = p_actor_id
  returning * into saved;

  return saved;
end;
$$;
