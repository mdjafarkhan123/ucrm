-- Fix: the purge RPC's smoke test caught that three more organization-scoped tables also carry
-- an unconditional "history is append-only" BEFORE UPDATE OR DELETE trigger, on top of the two
-- already patched in 20260815124000 -- organization_payment_confirmations,
-- organization_commercial_events, organization_safe_events. All three cascade from organizations
-- normally (unlike the two originally patched tables), so the purge RPC needs no new DELETE
-- statements -- its existing single `delete from organizations` cascade fails on every one of
-- these three today, before this fix, because the cascade-triggered row delete still fires the
-- BEFORE DELETE trigger and finds the bypass flag unset for these three functions. Same bypass
-- shape as the original two: DELETE is allowed only when the purge RPC's transaction-local flag
-- is set; UPDATE stays blocked unconditionally for every caller, forever.

create or replace function private.prevent_organization_payment_confirmation_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' and current_setting('app.organization_purge_in_progress', true) = 'true' then
    return old;
  end if;
  raise exception 'Organization payment confirmations are immutable.' using errcode = 'check_violation';
end;
$$;

create or replace function private.prevent_organization_commercial_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' and current_setting('app.organization_purge_in_progress', true) = 'true' then
    return old;
  end if;
  raise exception 'Commercial history is append-only.' using errcode = 'check_violation';
end;
$$;

create or replace function private.prevent_organization_safe_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' and current_setting('app.organization_purge_in_progress', true) = 'true' then
    return old;
  end if;
  raise exception 'Contractor-safe history is append-only.' using errcode = 'check_violation';
end;
$$;
