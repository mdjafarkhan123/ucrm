-- record_quote_deposit_event stopped working, and its answer changed shape.
--
-- 20261011090000 widened the list of accepted payment methods by rewriting this function from a wrong copy. The copy
-- inserted into a column that does not exist (`recorded_by`; the real one is `actor_user_id`), so every offline
-- deposit (cash, cheque, e-transfer...) failed. It also answered `{status, event_id}` instead of
-- `{applied, event_id, amount_minor, quote_version_id}` (which the client code and the database tests expect), lost
-- the lock on the published version, and dropped the "no sent version" check.
--
-- This restores the original body from 20260821104331 and keeps the wider method list. Grants are unchanged.

create or replace function public.record_quote_deposit_event(
  target_quote_id uuid,
  idempotency_key text,
  method text,
  reference text default null,
  note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
  existing_event public.quote_deposit_events;
  inserted_event public.quote_deposit_events;
  clean_reference text := nullif(trim(coalesce(reference, '')), '');
  clean_note text := nullif(trim(coalesce(note, '')), '');
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if method not in ('cash', 'check', 'other', 'venmo', 'zelle', 'cash_app', 'e_transfer') then
    raise exception 'Choose how the deposit was received.' using errcode = 'check_violation';
  end if;

  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.record_deposit'
  ) then
    raise exception 'You do not have access to record a deposit on this quote.'
      using errcode = 'insufficient_privilege';
  end if;

  -- A retry of the same command returns the first result untouched, even if the deposit has since been
  -- recorded or reversed by someone else. This runs before every other check, same as Pipeline's outcome
  -- commands, so a legitimate retry is never mistaken for a conflicting second attempt.
  select * into existing_event
  from public.quote_deposit_events
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and quote_deposit_events.idempotency_key = record_quote_deposit_event.idempotency_key;
  if found then
    return jsonb_build_object(
      'applied', false, 'event_id', existing_event.id, 'amount_minor', existing_event.amount_minor
    );
  end if;

  if quote_row.current_published_version_id is null then
    raise exception 'This quote has no sent version to record a deposit against.'
      using errcode = 'check_violation';
  end if;

  select * into version_row from public.quote_versions
  where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
  for update;

  if version_row.deposit_type is null or version_row.deposit_required_minor <= 0 then
    raise exception 'This quote has no deposit required.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from public.quote_deposit_events received
    where received.organization_id = quote_row.organization_id
      and received.quote_id = quote_row.id
      and received.quote_version_id = version_row.id
      and received.event_type = 'received'
      and not exists (
        select 1 from public.quote_deposit_events reversal
        where reversal.organization_id = received.organization_id
          and reversal.reversed_event_id = received.id
      )
  ) then
    raise exception 'This deposit has already been recorded.' using errcode = 'check_violation';
  end if;

  insert into public.quote_deposit_events (
    organization_id, quote_id, quote_version_id, event_type, amount_minor, method, reference, note,
    actor_user_id, idempotency_key
  ) values (
    quote_row.organization_id, quote_row.id, version_row.id, 'received', version_row.deposit_required_minor,
    method, clean_reference, clean_note, (select auth.uid()), idempotency_key
  ) returning * into inserted_event;

  return jsonb_build_object(
    'applied', true, 'event_id', inserted_event.id, 'amount_minor', inserted_event.amount_minor,
    'quote_version_id', version_row.id
  );
end;
$$;
