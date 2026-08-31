-- Quotes Part 5B2: the customer answers.
--
-- 5B1 gave the customer a door and a document to look at. This migration lets them do the two things
-- Jobber's client rail lets them do - approve, or ask for changes - and lets the office see that the
-- link was opened. Declining stays a staff-recorded outcome: Jafar's call on 2026-08-21, because a
-- Decline button hands an unsure client a one-click way to end the job instead of asking a question.
--
-- Two shapes carry the weight. `quote_decisions` is the immutable record of every answer a quote has
-- ever had, staff or customer, so signatures in 5C bind to a decision rather than to a status word. And
-- the view stamp lives on the link itself, because the customer path already finds that row by token
-- hash - recording a view costs nothing extra.
--
-- Everything a stranger can reach still goes through one token hash into one security definer function
-- that only the service role may call. `anon` gains nothing here either.

-- 1. Every answer a quote has ever had --------------------------------------------------------------------

create table public.quote_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  -- An answer is always about one frozen document. Without this the record would say "they approved it"
  -- without saying what "it" was.
  quote_version_id uuid not null,
  outcome text not null check (outcome in ('approved', 'changes_requested', 'declined')),
  actor_kind text not null check (actor_kind in ('customer', 'staff')),
  actor_user_id uuid references auth.users(id) on delete set null,
  -- Which door it came through. Null for anything staff recorded, and it also names the recipient,
  -- because the link already knows who it was issued to.
  quote_access_link_id uuid,
  method text not null check (method in ('online', 'offline_verbal', 'in_person')),
  note text check (note is null or char_length(trim(note)) between 1 and 1000),
  -- Truncated IP and user agent, cut to size before they ever reach here. Enough to say the answer came
  -- from a real browser, not enough to follow a person around.
  evidence jsonb not null default '{}'::jsonb,
  -- The one answer that counts right now. A material revision ends an approval without deleting it, so
  -- history keeps every row and exactly one of them is current.
  is_current boolean not null default true,
  decided_at timestamptz not null default now(),
  constraint quote_decisions_organization_id_unique unique (organization_id, id),
  constraint quote_decisions_quote_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete cascade,
  constraint quote_decisions_version_fk foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade,
  -- Only the link column is cleared if a link row ever goes: nulling the organization too would break
  -- the row, and losing the door is not a reason to lose the answer that came through it.
  constraint quote_decisions_link_fk foreign key (organization_id, quote_access_link_id)
    references public.quote_access_links(organization_id, id) on delete set null (quote_access_link_id),
  -- A customer answers online; staff answer some other way and hold no link.
  constraint quote_decisions_actor_matches_method check (
    case actor_kind
      when 'customer' then method = 'online'
      else method in ('offline_verbal', 'in_person') and quote_access_link_id is null
    end
  )
);

comment on table public.quote_decisions is
  'Immutable record of every answer a quote has received, from the customer through a link or from staff '
  'off the app. Exactly one row per quote is current. Rows are written only by the quote commands.';

comment on column public.quote_decisions.evidence is
  'Truncated IP and user agent for a customer answer, redacted before it arrives. Never shown to the '
  'customer and never treated as proof of who was holding the device.';

-- One current answer per quote, enforced rather than remembered. It is also the read every screen makes.
create unique index quote_decisions_one_current_idx
  on public.quote_decisions(organization_id, quote_id) where is_current;

-- Serves the version foreign key and the "what did they answer about this version" read 5C will need.
-- Leading with organization and quote means it answers the quote's own history too, so no third index.
create index quote_decisions_version_idx
  on public.quote_decisions(organization_id, quote_id, quote_version_id);

create index quote_decisions_link_idx
  on public.quote_decisions(quote_access_link_id) where quote_access_link_id is not null;

create index quote_decisions_actor_idx
  on public.quote_decisions(actor_user_id) where actor_user_id is not null;

-- 2. Whether the link was ever opened ---------------------------------------------------------------------

alter table public.quote_access_links
  add column first_viewed_at timestamptz,
  add column last_viewed_at timestamptz,
  add column view_count integer not null default 0 check (view_count >= 0);

comment on column public.quote_access_links.first_viewed_at is
  'Stamped once, by an explicit call from the customer''s browser after the document is on screen. Never '
  'by a page request, a HEAD, a mail scanner or a link preview - those open nothing a person read.';

alter table public.quote_access_links
  add constraint quote_access_links_view_count_agrees check ((view_count = 0) = (first_viewed_at is null)),
  add constraint quote_access_links_last_view_follows_first check (
    last_viewed_at is null or (first_viewed_at is not null and last_viewed_at >= first_viewed_at)
  );

-- No index. The only way anyone reaches these columns is the token hash lookup, which is already unique,
-- and the staff read is bounded by one quote.

-- 3. The link is opened -----------------------------------------------------------------------------------

-- Called by our server once the rendered document has actually appeared, so this is a view in the sense a
-- person means it. Every way of failing returns null and writes nothing, exactly like the resolver: a
-- forged call with a dead token must not be distinguishable from a live one.
--
-- Only the first view writes to the activity feed. The office reads that feed for things that happened;
-- a client who opens their quote eleven times over a weekend is one thing that happened, not eleven.
create or replace function public.record_quote_link_view(supplied_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  was_first boolean;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into quote_row from public.quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  was_first := link_row.first_viewed_at is null;

  update public.quote_access_links
  set first_viewed_at = coalesce(first_viewed_at, now()),
      last_viewed_at = now(),
      view_count = view_count + 1
  where id = link_row.id;

  if was_first then
    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      quote_row.organization_id, 'quote', quote_row.id, 'quote.viewed_by_client',
      'The client opened this quote', null,
      jsonb_build_object('quote_access_link_id', link_row.id)
    );
  end if;

  return jsonb_build_object('recorded', true, 'first_view', was_first);
end;
$$;

-- 4. The customer answers ---------------------------------------------------------------------------------

-- Approve, or ask for changes. The quote is locked first, like every other quote command, so this queues
-- behind a staff member republishing instead of deadlocking with them - and so two taps on a slow phone
-- cannot become two answers.
--
-- This function never publishes anything. `record_quote_decision` may publish a draft before answering it,
-- because a staff member saying "they rang and said yes" is describing a document that already went out.
-- A customer can only ever answer the version that was actually sent to them.
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

  -- What they wrote goes in the line staff actually read. A change request whose message is buried in a
  -- table nobody opens is a change request nobody acts on. Trimmed to fit the summary's own limit.
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

-- 5. One history, not two ----------------------------------------------------------------------------------

-- Part 5A's staff command wrote the answer onto the quote and into the activity feed. Now that answers are
-- rows, it writes one too, so a quote has a single decision history whether the client tapped a button or
-- rang the office. Its behavior is otherwise unchanged.
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

  update public.quote_decisions
  set is_current = false
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and is_current;

  insert into public.quote_decisions (
    organization_id, quote_id, quote_version_id, outcome, actor_kind, actor_user_id,
    method, note
  ) values (
    quote_row.organization_id, quote_row.id, quote_row.current_published_version_id, new_decision,
    'staff', (select auth.uid()), 'offline_verbal', clean_note
  );

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

-- 5b. Revising ends the answer and closes the door -----------------------------------------------------------

-- Part 5A wrote this before customers could reach a quote at all, so it only had the quote's own decision
-- fields to clear. Two things are now true that were not: an answer is a row, and a live link exists.
--
-- The link matters more than it looks. Between starting a revision and publishing it, the quote still
-- points at its old published version, so an unrevoked link would keep working - and a customer could
-- approve the very document being rewritten. Revising revokes them, which is what the behavior contract
-- asked for from the start.
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

  -- The answer stays in history. It simply stops being the answer, because it was about a document that
  -- is no longer the one on the table.
  update public.quote_decisions
  set is_current = false
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and is_current;

  update public.quote_access_links
  set revoked_at = now(), revoked_reason = 'rotated'
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and revoked_at is null;

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

-- 6. An expired link says so --------------------------------------------------------------------------------

-- The one unavailable state worth naming. A person whose link ran out needs to know to ask for a new one,
-- and the behavior contract allows exactly this much: the word expired, and nothing else. Every other way
-- of failing still returns the same null, so the page cannot be used to find out whether a quote exists.
create or replace function public.resolve_quote_access_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
  recipient_row public.quote_recipients;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null or link_row.revoked_at is not null then
    return null;
  end if;

  if link_row.expires_at is not null and link_row.expires_at <= now() then
    return jsonb_build_object('expired', true);
  end if;

  select * into quote_row from public.quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  select * into recipient_row from public.quote_recipients where id = link_row.recipient_id;

  return private.quote_customer_document(
    quote_row, version_row, recipient_row.display_name, recipient_row.email, true
  );
end;
$$;

-- 7. What staff may know about the links, now including whether anyone opened them ---------------------------

create or replace function public.quote_access_link_state(target_quote_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
begin
  select * into quote_row from public.quotes where id = target_quote_id;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.view'
     ) then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'quote_access_link_id', link.id,
          'quote_version_id', link.quote_version_id,
          'version_number', version.version_number,
          'recipient_name', recipient.display_name,
          'recipient_email', recipient.email,
          'issued_at', link.issued_at,
          'expires_at', link.expires_at,
          'first_viewed_at', link.first_viewed_at,
          'last_viewed_at', link.last_viewed_at,
          'view_count', link.view_count,
          'is_current_version', link.quote_version_id = quote_row.current_published_version_id
        )
        order by link.issued_at desc
      )
      from public.quote_access_links as link
      join public.quote_recipients as recipient on recipient.id = link.recipient_id
      join public.quote_versions as version on version.id = link.quote_version_id
      where link.organization_id = quote_row.organization_id
        and link.quote_id = quote_row.id
        and link.revoked_at is null
    ),
    '[]'::jsonb
  );
end;
$$;

-- 8. Least privilege -----------------------------------------------------------------------------------------

alter table public.quote_decisions enable row level security;

create policy "permitted members can view quote decisions"
on public.quote_decisions for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));

revoke all on public.quote_decisions from anon, authenticated;
grant select on public.quote_decisions to authenticated;

-- Both customer commands are reachable only by our own server holding the service key, exactly like the
-- resolver. No member calls them either: a signed-in staff member answering on the customer's behalf is
-- record_quote_decision, which says so in the record.
revoke all on function public.record_quote_link_view(bytea) from public;
revoke execute on function public.record_quote_link_view(bytea) from anon, authenticated;
grant execute on function public.record_quote_link_view(bytea) to service_role;

revoke all on function public.submit_quote_customer_decision(bytea, text, text, jsonb) from public;
revoke execute on function public.submit_quote_customer_decision(bytea, text, text, jsonb)
  from anon, authenticated;
grant execute on function public.submit_quote_customer_decision(bytea, text, text, jsonb) to service_role;
