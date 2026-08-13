-- Fixes a bug found while writing Part 5f's pgTAP coverage: consume_onboarding_application_setup_link
-- has crashed on every real call since it was created (20260812082645_setup_link_atomic_consume).
-- Its RETURNS TABLE output columns are named application_id/administrator_user_id, which are the
-- same names as the columns read by its own `returning application_id, administrator_user_id`
-- clause -- Postgres's default plpgsql.variable_conflict = 'error' refuses to guess which one is
-- meant and raises 42702 instead of running. Confirmed live in production: the user hit this exact
-- error submitting a real password-setup form ("column reference \"application_id\" is ambiguous").
-- Fix: alias the updated table and qualify the RETURNING columns with it, so they can no longer be
-- read as the function's own output variables.
create or replace function public.consume_onboarding_application_setup_link(
  target_token_hash text,
  target_email text
)
returns table (
  consumed boolean,
  application_id uuid,
  administrator_user_id uuid
)
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  updated_row record;
begin
  update public.platform_onboarding_application_setup_links as links
  set consumed_at = now()
  where links.token_hash = target_token_hash
    and links.consumed_at is null
    and links.expires_at > now()
    and links.intended_email = target_email
  returning links.application_id, links.administrator_user_id
  into updated_row;

  if found then
    return query select true, updated_row.application_id, updated_row.administrator_user_id;
  else
    return query select false, null::uuid, null::uuid;
  end if;
end;
$$;
