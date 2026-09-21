-- Quotes Part 6B: staff deposit configuration and offline recording.
--
-- Part 6A built the schema and the calculator; nothing let staff configure a deposit or record one being
-- paid. This file adds both: one draft command that replaces a version's deposit shape (following the same
-- lock/refresh/bump pattern every other rail dialog already uses), one new immutable table for offline
-- receipts and reversals, and the two commands that write it. Readiness gating and the customer-facing
-- display remain Part 6C.

-- 1. Who is allowed to record money changing hands off the app -------------------------------------------

insert into public.permissions (key, description)
values
  ('quotes.record_deposit', 'Record and reverse an offline deposit payment on a quote')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'quotes.record_deposit'),
  ('admin', 'quotes.record_deposit'),
  ('office', 'quotes.record_deposit'),
  ('finance', 'quotes.record_deposit')
on conflict (role, permission_key) do nothing;

-- 2. Configuring the deposit on a draft -------------------------------------------------------------------

-- The whole schedule is sent every time, the same way lines and packages already are: staff add, reorder,
-- and remove installments before saving once. Removing the deposit entirely (new_deposit_type is null)
-- clears every installment with it, because a payment schedule with no deposit type is not a smaller
-- schedule, it is no schedule.
--
-- Only a payment schedule's installments must add up to the quote total -- a single deposit-only
-- installment is priced and capped exactly like it already was in Part 6A, with nothing else on the
-- document for it to reconcile against.
create or replace function public.set_quote_draft_deposit(
  target_quote_id uuid,
  expected_revision integer,
  new_deposit_type text,
  new_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  item jsonb;
  item_index integer := 0;
  item_count integer;
  clean_description text;
  clean_value_type text;
  clean_value bigint;
  item_priced bigint;
  computed_sum bigint := 0;
begin
  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  if new_deposit_type is not null and new_deposit_type not in ('deposit_only', 'schedule') then
    raise exception 'A deposit is either a single deposit or a payment schedule.'
      using errcode = 'check_violation';
  end if;

  -- Every existing installment is replaced, whether or not a new one takes its place.
  delete from public.quote_version_schedule_items
  where organization_id = draft_row.organization_id
    and quote_version_id = draft_row.id;

  if new_deposit_type is null then
    update public.quote_versions set deposit_type = null where id = draft_row.id;
    return private.bump_quote_draft(draft_row.id);
  end if;

  if new_items is null or jsonb_typeof(new_items) <> 'array' then
    raise exception 'Send the deposit installments as a list.' using errcode = 'check_violation';
  end if;

  item_count := jsonb_array_length(new_items);
  if item_count < 1 then
    raise exception 'Add at least one installment.' using errcode = 'check_violation';
  end if;
  if item_count > 12 then
    raise exception 'A payment schedule can hold up to 12 installments.' using errcode = 'check_violation';
  end if;
  if new_deposit_type = 'deposit_only' and item_count <> 1 then
    raise exception 'A deposit only has one installment.' using errcode = 'check_violation';
  end if;
  -- A schedule prices its percentage installments against the quote's current total, so there is nothing
  -- honest to save until the quote has one.
  if new_deposit_type = 'schedule' and draft_row.total_minor <= 0 then
    raise exception 'Add line items to this quote before setting a payment schedule.'
      using errcode = 'check_violation';
  end if;

  for item in select * from jsonb_array_elements(new_items)
  loop
    clean_description := nullif(trim(coalesce(item ->> 'description', '')), '');
    clean_value_type := item ->> 'type';
    clean_value := nullif(item ->> 'value', '')::bigint;

    if clean_description is null or char_length(clean_description) < 2
       or char_length(clean_description) > 160 then
      raise exception 'Installment % needs a description between 2 and 160 characters.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type not in ('fixed', 'percentage') then
      raise exception 'Installment % must be a fixed amount or a percentage.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value is null or clean_value < 1 then
      raise exception 'Installment % needs an amount above zero.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type = 'percentage' and clean_value > 10000 then
      raise exception 'Installment % cannot be more than 100%%.', item_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_value_type = 'fixed' and clean_value > 1000000000000 then
      raise exception 'Installment % is too large.', item_index + 1 using errcode = 'check_violation';
    end if;

    insert into public.quote_version_schedule_items (
      organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
    ) values (
      draft_row.organization_id, draft_row.quote_id, draft_row.id, item_index, clean_description,
      clean_value_type, clean_value, item_index = 0
    );

    if clean_value_type = 'fixed' then
      item_priced := clean_value;
    else
      item_priced := round(draft_row.total_minor * clean_value / 10000);
    end if;
    computed_sum := computed_sum + item_priced;

    item_index := item_index + 1;
  end loop;

  if new_deposit_type = 'schedule' and computed_sum <> draft_row.total_minor then
    raise exception
      'Installments must add up to the quote total. They currently add up to % but the total is %.',
      computed_sum, draft_row.total_minor using errcode = 'check_violation';
  end if;

  update public.quote_versions set deposit_type = new_deposit_type where id = draft_row.id;

  return private.bump_quote_draft(draft_row.id);
end;
$$;

revoke all on function public.set_quote_draft_deposit(uuid, integer, text, jsonb) from public;
revoke execute on function public.set_quote_draft_deposit(uuid, integer, text, jsonb) from anon;
grant execute on function public.set_quote_draft_deposit(uuid, integer, text, jsonb) to authenticated;

-- 3. Recording money that actually changed hands ------------------------------------------------------------

-- An immutable ledger, the same shape as Pipeline's outcome events: nothing here is ever edited or deleted,
-- a mistake is corrected by reversing it, and the whole thing is replay-safe by idempotency key. A deposit
-- always binds to the quote's current published version, because that is the only version whose
-- `deposit_required_minor` is a frozen, agreed-on figure rather than a number still moving with the draft.
create table public.quote_deposit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  quote_version_id uuid not null,
  event_type text not null check (event_type in ('received', 'reversed')),
  amount_minor bigint not null check (amount_minor > 0),
  method text not null check (method in ('cash', 'check', 'other')),
  reference text check (reference is null or char_length(trim(reference)) <= 200),
  note text check (note is null or char_length(trim(note)) between 1 and 500),
  actor_user_id uuid references auth.users(id) on delete set null,
  -- Set only on a reversal, and only ever pointing at a 'received' row. This is what makes "already
  -- reversed" and "already recorded" answerable without a second status column to keep in sync.
  reversed_event_id uuid,
  idempotency_key text not null check (char_length(trim(idempotency_key)) >= 8),
  created_at timestamptz not null default now(),
  constraint quote_deposit_events_organization_id_unique unique (organization_id, id),
  constraint quote_deposit_events_quote_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete cascade,
  constraint quote_deposit_events_version_fk foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade,
  constraint quote_deposit_events_reversed_fk foreign key (organization_id, reversed_event_id)
    references public.quote_deposit_events(organization_id, id),
  constraint quote_deposit_events_idempotency_unique unique (organization_id, quote_id, idempotency_key),
  constraint quote_deposit_events_reversal_shape check (
    (event_type = 'received' and reversed_event_id is null)
    or (event_type = 'reversed' and reversed_event_id is not null)
  )
);

comment on table public.quote_deposit_events is
  'Immutable offline deposit receipts and reversals. A reversal is a new row, never an edit or delete of '
  'the one it corrects.';

create index quote_deposit_events_version_idx
  on public.quote_deposit_events(organization_id, quote_id, quote_version_id, created_at, id);

-- The "already reversed" check on a receipt walks this direction; without the index it would seq-scan the
-- whole ledger for every reversal attempt.
create index quote_deposit_events_reversed_idx
  on public.quote_deposit_events(organization_id, reversed_event_id)
  where reversed_event_id is not null;

alter table public.quote_deposit_events enable row level security;

create policy "permitted members can view quote deposit events"
on public.quote_deposit_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'quotes.view')
);

revoke all on public.quote_deposit_events from anon, authenticated;
grant select on public.quote_deposit_events to authenticated;

-- Deposits are recorded in full or not at all this campaign -- see the contract's "Deposits and payment
-- schedules" section. That collapses "outstanding balance" bookkeeping into one question: is there a
-- live (non-reversed) receipt for this version already?
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
  if method not in ('cash', 'check', 'other') then
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

revoke all on function public.record_quote_deposit_event(uuid, text, text, text, text) from public;
revoke execute on function public.record_quote_deposit_event(uuid, text, text, text, text) from anon;
grant execute on function public.record_quote_deposit_event(uuid, text, text, text, text) to authenticated;

-- A correction, not an undo: the receipt stays exactly as recorded, and this adds the row that says it no
-- longer counts. Two reversals of the same receipt cannot both land, because the second one's "already
-- reversed" check sees the first.
create or replace function public.reverse_quote_deposit_event(
  target_quote_id uuid,
  target_event_id uuid,
  idempotency_key text,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  original_event public.quote_deposit_events;
  existing_reversal public.quote_deposit_events;
  inserted_event public.quote_deposit_events;
  clean_reason text := nullif(trim(coalesce(reason, '')), '');
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if clean_reason is null then
    raise exception 'Say why this deposit is being reversed.' using errcode = 'check_violation';
  end if;

  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.record_deposit'
  ) then
    raise exception 'You do not have access to reverse a deposit on this quote.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into existing_reversal
  from public.quote_deposit_events
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and quote_deposit_events.idempotency_key = reverse_quote_deposit_event.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_reversal.id);
  end if;

  select * into original_event
  from public.quote_deposit_events
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and id = target_event_id
  for update;

  if original_event.id is null or original_event.event_type <> 'received' then
    raise exception 'That deposit record could not be found.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.quote_deposit_events reversal
    where reversal.organization_id = original_event.organization_id
      and reversal.reversed_event_id = original_event.id
  ) then
    raise exception 'This deposit was already reversed.' using errcode = 'check_violation';
  end if;

  insert into public.quote_deposit_events (
    organization_id, quote_id, quote_version_id, event_type, amount_minor, method, reference, note,
    actor_user_id, reversed_event_id, idempotency_key
  ) values (
    quote_row.organization_id, quote_row.id, original_event.quote_version_id, 'reversed',
    original_event.amount_minor, original_event.method, original_event.reference, clean_reason,
    (select auth.uid()), original_event.id, idempotency_key
  ) returning * into inserted_event;

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id);
end;
$$;

revoke all on function public.reverse_quote_deposit_event(uuid, uuid, text, text) from public;
revoke execute on function public.reverse_quote_deposit_event(uuid, uuid, text, text) from anon;
grant execute on function public.reverse_quote_deposit_event(uuid, uuid, text, text) to authenticated;
