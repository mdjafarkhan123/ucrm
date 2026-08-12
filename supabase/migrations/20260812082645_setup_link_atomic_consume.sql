-- Atomic single-use consume for the administrator password-setup link.
--
-- Replaces the previous select-then-check-then-update in application code (a check-then-act race:
-- two near-simultaneous submits with the same valid token could both pass the read check before
-- either had marked the row consumed) with one UPDATE whose WHERE clause is the entire check --
-- token match, not yet consumed, not expired, and recipient email match, all at once. Postgres
-- row-locking means only one concurrent caller can ever match and update the row; every other
-- concurrent or later caller sees consumed_at already set and matches zero rows. The route falls
-- back to a plain read-only lookup only when this returns consumed = false, purely to produce a
-- specific user-facing reason (expired/already used vs. wrong email) without mutating anything.
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
  update public.platform_onboarding_application_setup_links
  set consumed_at = now()
  where token_hash = target_token_hash
    and consumed_at is null
    and expires_at > now()
    and intended_email = target_email
  returning application_id, administrator_user_id
  into updated_row;

  if found then
    return query select true, updated_row.application_id, updated_row.administrator_user_id;
  else
    return query select false, null::uuid, null::uuid;
  end if;
end;
$$;

revoke all on function public.consume_onboarding_application_setup_link(text, text)
  from public, anon, authenticated;
grant execute on function public.consume_onboarding_application_setup_link(text, text)
  to service_role;
