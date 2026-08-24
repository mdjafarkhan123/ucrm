-- Part 5A. Parts 3 and 4 built the freeze and clone machinery but left it unreachable: both functions had
-- their grants revoked, so no member could publish anything. This migration is what hands staff those two
-- moves and one more - recording a decision the customer gave off the app - and nothing customer-facing.
--
-- Three commands, one shape. Each locks the quote first and its draft second, exactly like every command in
-- 20260820160000, so two of them racing on one quote queue up instead of deadlocking. Business conflicts
-- answer P0409; none of them raise 40001.

-- 1. What a quote remembers about being sent and answered ------------------------------------------------

alter table public.quotes
  add column sent_at timestamptz,
  add column decision text check (decision is null or decision in ('approved', 'declined')),
  add column decided_at timestamptz,
  add column decision_method text
    check (decision_method is null or decision_method in ('offline_verbal', 'online', 'in_person')),
  add column decision_note text
    check (decision_note is null or char_length(trim(decision_note)) between 3 and 1000),
  add column decided_by uuid references auth.users(id) on delete set null;

comment on column public.quotes.sent_at is
  'When this quote first went out. Stamped by publish_quote and never cleared - a revision does not unsend '
  'what the customer already saw.';
comment on column public.quotes.decision is
  'The decision that is current right now, not a history. Revising an answered quote clears it, because the '
  'answer belonged to a version that is no longer the one on the table.';
comment on column public.quotes.decision_method is
  'Part 5A only ever writes offline_verbal. online arrives with the customer page, in_person with signatures.';

-- Quote #33 was published by hand during Part 4E testing, before any command stamped a date. Give it the
-- date its version carries so the constraint below describes every row, including the ones already here.
update public.quotes as quote
set sent_at = version.published_at
from public.quote_versions as version
where version.id = quote.current_published_version_id
  and quote.sent_at is null
  and version.published_at is not null;

alter table public.quotes
  add constraint quotes_publication_is_dated check (
    current_published_version_id is null or sent_at is not null
  );

alter table public.quotes
  add constraint quotes_decision_fields_agree check (
    (decision is null) = (decided_at is null)
    and (decision is null) = (decision_method is null)
    and (decision is not null or decision_note is null)
  );

-- Archived remembers its previous status separately, so this only constrains the live states.
alter table public.quotes
  add constraint quotes_decided_status_matches_decision check (
    status not in ('approved', 'declined') or decision = status
  );

-- One new index, and only because of the foreign key: without it, removing a user would sequentially scan
-- every quote in the system looking for rows to null out. It matches the shape created_by already uses.
create index quotes_decided_by_idx on public.quotes(decided_by) where decided_by is not null;

-- Nothing else here earns an index. No screen filters or sorts on sent_at or decided_at: the list pages by
-- created_at within a status, and a quote reads its own dates by primary key.

-- 2. Who is allowed to do it -----------------------------------------------------------------------------

insert into public.permissions (key, description)
values
  ('quotes.send', 'Publish a quote version and put it in front of the customer'),
  ('quotes.record_decision', 'Record an approval or decline the customer gave off the app')
on conflict (key) do update set description = excluded.description;

-- Publishing calls freeze_quote_version, which asks for quotes.edit on its own behalf, so send is only
-- given to roles that already edit. Finance still reads money without ever being able to send it out.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'quotes.send'),
  ('owner', 'quotes.record_decision'),
  ('admin', 'quotes.send'),
  ('admin', 'quotes.record_decision'),
  ('office', 'quotes.send'),
  ('office', 'quotes.record_decision'),
  ('sales', 'quotes.send'),
  ('sales', 'quotes.record_decision')
on conflict (role, permission_key) do nothing;

-- 3. Publishing ------------------------------------------------------------------------------------------

-- Publishing twice is a double-click, not an error. The second call finds the quote already awaiting a
-- response on the very revision it was asked to publish and hands back that same version, so a slow network
-- can never turn one proposal into two.
create or replace function public.publish_quote(
  target_quote_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  published_row public.quote_versions;
  draft_row public.quote_versions;
  priced_line_count integer;
  frozen jsonb;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.send'
     ) then
    raise exception 'You do not have access to send this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status = 'awaiting_response' then
    select * into published_row from public.quote_versions
    where id = quote_row.current_published_version_id;
    if published_row.id is not null and published_row.revision = expected_revision then
      return jsonb_build_object(
        'quote_id', quote_row.id, 'quote_version_id', published_row.id,
        'version_number', published_row.version_number, 'document_hash', published_row.document_hash,
        'sent_at', quote_row.sent_at, 'status', quote_row.status,
        'calculation', published_row.calculation, 'already_published', true
      );
    end if;
  end if;

  if quote_row.status <> 'draft' then
    raise exception 'Only a draft quote can be sent.' using errcode = 'check_violation';
  end if;

  select * into draft_row from public.quote_versions
  where organization_id = quote_row.organization_id and quote_id = quote_row.id and status = 'draft'
  for update;

  if draft_row.id is null then
    raise exception 'This quote has no draft to send.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this quote while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  -- A quote with nothing on it is not a proposal. Everything else the document needs was already required
  -- when the quote was created: a client, a property, a title, and a number.
  -- Named quote first, then version: that is the order quote_version_lines_version_idx is built in, and
  -- leaving quote_id out would drop the count to an organization-wide scan of every line ever quoted.
  select count(*) into priced_line_count
  from public.quote_version_lines
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and quote_version_id = draft_row.id
    and line_kind = 'priced';
  if priced_line_count = 0 then
    raise exception 'Add at least one line before sending this quote.' using errcode = 'check_violation';
  end if;

  -- The send date is stamped before the freeze, not after. quotes_publication_is_dated is a plain check
  -- constraint, so Postgres tests it the moment freeze points the quote at its new publication - stamping
  -- afterwards would fail on a row that is only half updated. Caught by the Part 5A database test.
  update public.quotes set sent_at = coalesce(sent_at, now()) where id = quote_row.id;

  frozen := public.freeze_quote_version(quote_row.id, expected_revision);

  update public.quotes
  set status = 'awaiting_response',
      decision = null, decided_at = null, decision_method = null,
      decision_note = null, decided_by = null
  where id = quote_row.id
  returning * into quote_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.published',
    'Sent version ' || (frozen ->> 'version_number') || ' to the customer',
    (select auth.uid()),
    jsonb_build_object(
      'quote_version_id', frozen ->> 'quote_version_id',
      'version_number', (frozen ->> 'version_number')::integer
    )
  );

  return frozen
    || jsonb_build_object('sent_at', quote_row.sent_at, 'status', quote_row.status,
                          'already_published', false);
end;
$$;

-- 4. Revising a published quote --------------------------------------------------------------------------

-- The customer is looking at a document that is now wrong, and the fix is a new version, never an edit of
-- the old one. Cloning gives back a draft; the decision that belonged to the published version stops being
-- current, because it answered a proposal that is no longer on the table.
create or replace function public.revise_quote(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  cloned jsonb;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.edit'
     ) then
    raise exception 'You do not have access to revise this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status not in ('awaiting_response', 'changes_requested', 'approved', 'declined') then
    raise exception 'Only a quote the customer already has can be revised.' using errcode = 'check_violation';
  end if;

  cloned := public.clone_quote_version_to_draft(quote_row.id);

  update public.quotes
  set status = 'draft',
      decision = null, decided_at = null, decision_method = null,
      decision_note = null, decided_by = null
  where id = quote_row.id;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.revised',
    'Started a new draft from the sent version', (select auth.uid()),
    jsonb_build_object('quote_version_id', cloned ->> 'quote_version_id')
  );

  return cloned || jsonb_build_object('status', 'draft');
end;
$$;

-- 5. Recording a decision the customer gave off the app --------------------------------------------------

-- "They rang and said yes." The quote must be in front of the customer for that sentence to be true, so a
-- decision recorded on an untouched draft publishes it first and then answers it. Recording the same
-- decision twice is the same answer, not a second one.
create or replace function public.record_quote_decision(
  target_quote_id uuid,
  new_decision text,
  decision_note text default null,
  expected_revision integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  clean_note text;
  published_version integer;
begin
  if new_decision is null or new_decision not in ('approved', 'declined') then
    raise exception 'A decision is either approved or declined.' using errcode = 'check_violation';
  end if;
  clean_note := nullif(trim(coalesce(decision_note, '')), '');
  if clean_note is not null and char_length(clean_note) > 1000 then
    raise exception 'That note is too long.' using errcode = 'check_violation';
  end if;

  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.record_decision'
     ) then
    raise exception 'You do not have access to answer this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status = new_decision then
    return jsonb_build_object(
      'quote_id', quote_row.id, 'status', quote_row.status, 'decision', quote_row.decision,
      'decided_at', quote_row.decided_at, 'already_decided', true
    );
  end if;

  if quote_row.status = 'draft' then
    -- Publishing here is the point: an answer with no sent document behind it would be a decision about
    -- nothing. publish_quote does its own permission check, and send sits with decision on every seeded role.
    perform public.publish_quote(quote_row.id, expected_revision);
    select * into quote_row from public.quotes where id = quote_row.id;
  elsif quote_row.status not in ('awaiting_response', 'changes_requested') then
    raise exception 'This quote is not waiting for an answer.' using errcode = 'check_violation';
  end if;

  update public.quotes
  set status = new_decision,
      decision = new_decision,
      decided_at = now(),
      decision_method = 'offline_verbal',
      decision_note = clean_note,
      decided_by = (select auth.uid())
  where id = quote_row.id
  returning * into quote_row;

  select version_number into published_version
  from public.quote_versions where id = quote_row.current_published_version_id;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.' || new_decision,
    case new_decision
      when 'approved' then 'Recorded the customer''s approval'
      else 'Recorded that the customer declined'
    end,
    (select auth.uid()),
    jsonb_build_object('version_number', published_version, 'method', 'offline_verbal')
  );

  return jsonb_build_object(
    'quote_id', quote_row.id, 'status', quote_row.status, 'decision', quote_row.decision,
    'decided_at', quote_row.decided_at, 'version_number', published_version,
    'already_decided', false
  );
end;
$$;

-- 6. Exposure --------------------------------------------------------------------------------------------

-- These three are the only new doors. freeze_quote_version and clone_quote_version_to_draft stay closed to
-- members: they are reached through the commands above, which check who is asking and what state the quote
-- is in first.
revoke all on function public.publish_quote(uuid, integer) from public;
revoke all on function public.revise_quote(uuid) from public;
revoke all on function public.record_quote_decision(uuid, text, text, integer) from public;
revoke execute on function public.publish_quote(uuid, integer) from anon;
revoke execute on function public.revise_quote(uuid) from anon;
revoke execute on function public.record_quote_decision(uuid, text, text, integer) from anon;
grant execute on function public.publish_quote(uuid, integer) to authenticated;
grant execute on function public.revise_quote(uuid) to authenticated;
grant execute on function public.record_quote_decision(uuid, text, text, integer) to authenticated;
