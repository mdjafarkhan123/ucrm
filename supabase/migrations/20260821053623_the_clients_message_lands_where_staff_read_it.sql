-- Quotes Part 5B2 follow-up: the client's own words, on the line staff actually read.
--
-- The decision row already held the message, but the activity feed - the thing anybody opens after
-- seeing "changes requested" - only said that changes were asked for. A change request whose message
-- is buried in a table nobody opens is a change request nobody acts on.
create or replace function public.submit_quote_customer_decision(
  supplied_token_hash bytea,
  new_outcome text,
  customer_note text default null,
  supplied_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
  current_decision public.quote_decisions;
  clean_note text;
  new_status text;
begin
  if new_outcome is null or new_outcome not in ('approved', 'changes_requested') then
    raise exception 'That is not an answer this link can give.' using errcode = 'check_violation';
  end if;

  clean_note := nullif(trim(coalesce(customer_note, '')), '');
  if clean_note is not null and char_length(clean_note) > 1000 then
    raise exception 'That message is too long.' using errcode = 'check_violation';
  end if;

  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  -- Read the link once to learn which quote to lock, then take the lock, then check everything again on
  -- rows nobody can move underneath us.
  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null then
    return null;
  end if;

  select * into quote_row from public.quotes where id = link_row.quote_id for update;

  select * into link_row from public.quote_access_links where id = link_row.id;
  if link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  -- The same tap arriving twice. Answering again with the same answer, about the same document, is not a
  -- second answer - it is a phone that lost signal for a moment.
  select * into current_decision
  from public.quote_decisions
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and is_current;

  if current_decision.id is not null
     and current_decision.outcome = new_outcome
     and current_decision.quote_version_id = version_row.id
     and current_decision.actor_kind = 'customer' then
    return jsonb_build_object(
      'quote_id', quote_row.id, 'status', quote_row.status, 'outcome', current_decision.outcome,
      'decided_at', current_decision.decided_at, 'already_answered', true
    );
  end if;

  if quote_row.status not in ('awaiting_response', 'changes_requested') then
    raise exception 'This quote has already been answered.' using errcode = 'P0409';
  end if;

  -- Asking for changes twice in a row is the same request arriving again, not a new one.
  if new_outcome = 'changes_requested' and quote_row.status = 'changes_requested' then
    raise exception 'You have already asked for changes on this quote.' using errcode = 'P0409';
  end if;

  new_status := new_outcome;

  update public.quote_decisions
  set is_current = false
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and is_current;

  insert into public.quote_decisions (
    organization_id, quote_id, quote_version_id, outcome, actor_kind, quote_access_link_id,
    method, note, evidence
  ) values (
    quote_row.organization_id, quote_row.id, version_row.id, new_outcome, 'customer', link_row.id,
    'online', clean_note, coalesce(supplied_evidence, '{}'::jsonb)
  );

  -- `decision` on the quote is the answered-yes-or-no field, so a change request leaves it alone: the
  -- quote is back with the office, not decided. The message lives on the decision row above.
  if new_outcome = 'approved' then
    update public.quotes
    set status = new_status,
        decision = 'approved',
        decided_at = now(),
        decision_method = 'online',
        decision_note = clean_note,
        decided_by = null
    where id = quote_row.id
    returning * into quote_row;
  else
    update public.quotes
    set status = new_status
    where id = quote_row.id
    returning * into quote_row;
  end if;

  -- What they wrote goes in the line staff actually read. Trimmed to fit the summary's own limit.
  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id,
    case new_outcome when 'approved' then 'quote.approved' else 'quote.changes_requested' end,
    case new_outcome when 'approved' then 'The client approved this quote'
                     else 'The client asked for changes' end
      || case when clean_note is null then ''
              else ': ' || left(clean_note, 240) || case when char_length(clean_note) > 240 then '…' else '' end
         end,
    null,
    jsonb_build_object(
      'version_number', version_row.version_number,
      'method', 'online',
      'quote_access_link_id', link_row.id
    )
  );

  return jsonb_build_object(
    'quote_id', quote_row.id, 'status', quote_row.status, 'outcome', new_outcome,
    'decided_at', now(), 'already_answered', false
  );
end;
$$;

revoke all on function public.submit_quote_customer_decision(bytea, text, text, jsonb) from public;
revoke execute on function public.submit_quote_customer_decision(bytea, text, text, jsonb)
  from anon, authenticated;
grant execute on function public.submit_quote_customer_decision(bytea, text, text, jsonb) to service_role;
