-- Quotes Part 5C: putting a name to an answer.
--
-- 5B2 made every answer a row. This migration lets an approval carry a signature: the client types or
-- draws one on their own page, or a staff member collects it in person on their own device. Jobber's rule
-- is that signing is offered rather than demanded ("Since signatures aren't required to approve a quote"),
-- and Jafar asked to follow Jobber, so approve still works with nothing signed. Making it compulsory is an
-- organization setting, and Settings is not on this campaign's path.
--
-- A signature belongs to one decision, one frozen version, and the exact document hash that was on screen.
-- It is written in the same transaction as the answer it belongs to, so there is no moment where a quote
-- is approved and the signature it was approved with is missing.
--
-- A drawn signature is a small private PNG in object storage. The bytes never enter Postgres: these rows
-- are read on every quote detail page, and an image column would be dragged through every read that never
-- shows it. The upload happens before the command and outside any lock, because the behavior contract
-- forbids external calls while rows are locked.

-- 1. The signature itself ---------------------------------------------------------------------------------

create table public.quote_signatures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  -- Which frozen document was signed, and which answer this signature is part of.
  quote_version_id uuid not null,
  quote_decision_id uuid not null,
  signer_name text not null check (char_length(trim(signer_name)) between 1 and 120),
  method text not null check (method in ('typed', 'drawn', 'in_person')),
  -- Copied at signing rather than read back through the version. A signature has to be able to say which
  -- bytes were on the screen without trusting a row somebody could have touched since.
  document_hash text not null check (document_hash ~ '^[0-9a-f]{64}$'),
  -- Null for a typed name. Everything drawn keeps its private object key; there is no public URL for it
  -- anywhere, and staff read it back through an authenticated stream.
  image_object_key text check (image_object_key is null or char_length(image_object_key) between 1 and 500),
  image_byte_size integer check (image_byte_size is null or image_byte_size between 1 and 262144),
  -- Truncated IP and user agent, cut to size before they arrive, same as a decision's.
  evidence jsonb not null default '{}'::jsonb,
  signed_at timestamptz not null default now(),
  constraint quote_signatures_organization_id_unique unique (organization_id, id),
  constraint quote_signatures_quote_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete cascade,
  constraint quote_signatures_version_fk foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade,
  constraint quote_signatures_decision_fk foreign key (organization_id, quote_decision_id)
    references public.quote_decisions(organization_id, id) on delete cascade,
  -- A typed signature is a name in a box; anything drawn is a picture. The two never half-swap.
  constraint quote_signatures_image_matches_method check (
    (method = 'typed') = (image_object_key is null)
    and (image_object_key is null) = (image_byte_size is null)
  ),
  -- One answer, one signature, by one person, at one moment.
  constraint quote_signatures_one_per_decision unique (organization_id, quote_decision_id)
);

comment on table public.quote_signatures is
  'A signature bound to one published version, its document hash, and the decision it belongs to. Written '
  'only by the quote decision commands, in the same transaction as the answer. Verbal approval records no '
  'signature at all rather than a fabricated one.';

comment on column public.quote_signatures.document_hash is
  'The signed version''s hash, copied at signing so the row proves what was on screen on its own.';

comment on column public.quote_signatures.evidence is
  'Truncated IP and user agent, redacted before arrival. Never rendered back to the customer and never '
  'presented to staff as proof of who was holding the device.';

-- The unique constraint above already indexes the decision foreign key. This one serves the quote's own
-- history read, and its leading columns cover the version foreign key's checks too - a quote holds a
-- handful of signatures, so no third index earns its write cost.
create index quote_signatures_quote_idx
  on public.quote_signatures(organization_id, quote_id, signed_at desc);

-- Whether a signature is the current one is the decision's business, not a column here. Two places
-- claiming the same truth is two places to keep in step.

-- 2. The customer signs on their own page -----------------------------------------------------------------

-- The old four-argument form is replaced rather than overloaded: two functions with the same name and a
-- different idea of what a decision is would be exactly the drift this campaign keeps avoiding.
drop function if exists public.submit_quote_customer_decision(bytea, text, text, jsonb);

create or replace function public.submit_quote_customer_decision(
  supplied_token_hash bytea,
  new_outcome text,
  customer_note text default null,
  supplied_evidence jsonb default '{}'::jsonb,
  signature_name text default null,
  signature_method text default null,
  signature_object_key text default null,
  signature_byte_size integer default null
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
  new_decision_id uuid;
  clean_note text;
  clean_signer text;
  new_status text;
begin
  if new_outcome is null or new_outcome not in ('approved', 'changes_requested') then
    raise exception 'That is not an answer this link can give.' using errcode = 'check_violation';
  end if;

  clean_note := nullif(trim(coalesce(customer_note, '')), '');
  if clean_note is not null and char_length(clean_note) > 1000 then
    raise exception 'That message is too long.' using errcode = 'check_violation';
  end if;

  clean_signer := nullif(trim(coalesce(signature_name, '')), '');

  -- Nobody signs a request to change something.
  if clean_signer is not null and new_outcome <> 'approved' then
    raise exception 'Only an approval is signed.' using errcode = 'check_violation';
  end if;

  if clean_signer is not null then
    if char_length(clean_signer) > 120 then
      raise exception 'That name is too long.' using errcode = 'check_violation';
    end if;
    if signature_method is null or signature_method not in ('typed', 'drawn') then
      raise exception 'That is not a way to sign.' using errcode = 'check_violation';
    end if;
    if (signature_method = 'drawn') <> (signature_object_key is not null) then
      raise exception 'That signature is incomplete.' using errcode = 'check_violation';
    end if;
  elsif signature_object_key is not null then
    -- A drawing with nobody's name on it is not a signature.
    raise exception 'That signature is incomplete.' using errcode = 'check_violation';
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
  -- second answer - it is a phone that lost signal for a moment. The first signature stands; a second
  -- upload that arrived with it is left unreferenced and swept up by the caller.
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
  )
  returning id into new_decision_id;

  -- Same transaction as the answer, on purpose. A signature that could arrive a moment later is a
  -- signature that could fail to arrive at all.
  if clean_signer is not null then
    insert into public.quote_signatures (
      organization_id, quote_id, quote_version_id, quote_decision_id, signer_name, method,
      document_hash, image_object_key, image_byte_size, evidence
    ) values (
      quote_row.organization_id, quote_row.id, version_row.id, new_decision_id, clean_signer,
      signature_method, version_row.document_hash, signature_object_key, signature_byte_size,
      coalesce(supplied_evidence, '{}'::jsonb)
    );
  end if;

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
      'signed', clean_signer is not null,
      'quote_access_link_id', link_row.id
    )
  );

  return jsonb_build_object(
    'quote_id', quote_row.id, 'status', quote_row.status, 'outcome', new_outcome,
    'decided_at', now(), 'signed', clean_signer is not null, 'already_answered', false
  );
end;
$$;

-- 3. Staff collect a signature in person ------------------------------------------------------------------

-- Jobber's Collect Signature, and the same act it is in real life: the client signs the tablet at the
-- kitchen table and the quote is approved. That makes this an approval with a different method, not a
-- separate kind of event, so it lands in the one decision history beside the verbal path.
--
-- From a draft it publishes first, exactly like `record_quote_decision` does, because a signature on a
-- document that was never frozen is a signature on nothing.
create or replace function public.record_quote_in_person_signature(
  target_quote_id uuid,
  signer_name text,
  signature_method text default 'in_person',
  signature_object_key text default null,
  signature_byte_size integer default null,
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
  version_row public.quote_versions;
  new_decision_id uuid;
  clean_signer text;
  clean_note text;
begin
  clean_signer := nullif(trim(coalesce(signer_name, '')), '');
  if clean_signer is null or char_length(clean_signer) > 120 then
    raise exception 'A signature needs the name of the person signing.' using errcode = 'check_violation';
  end if;

  if signature_method is null or signature_method not in ('typed', 'in_person') then
    raise exception 'That is not a way to sign in person.' using errcode = 'check_violation';
  end if;

  if (signature_method = 'in_person') <> (signature_object_key is not null) then
    raise exception 'That signature is incomplete.' using errcode = 'check_violation';
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

  if quote_row.status = 'draft' then
    -- publish_quote runs its own permission check, and send sits with decision on every seeded role.
    perform public.publish_quote(quote_row.id, expected_revision);
    select * into quote_row from public.quotes where id = quote_row.id;
  elsif quote_row.status not in ('awaiting_response', 'changes_requested') then
    raise exception 'This quote is not waiting for an answer.' using errcode = 'P0409';
  end if;

  select * into version_row
  from public.quote_versions where id = quote_row.current_published_version_id;
  if version_row.id is null then
    raise exception 'This quote has no sent version to sign.' using errcode = 'check_violation';
  end if;

  update public.quotes
  set status = 'approved',
      decision = 'approved',
      decided_at = now(),
      decision_method = 'in_person',
      decision_note = clean_note,
      decided_by = (select auth.uid())
  where id = quote_row.id
  returning * into quote_row;

  update public.quote_decisions
  set is_current = false
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and is_current;

  insert into public.quote_decisions (
    organization_id, quote_id, quote_version_id, outcome, actor_kind, actor_user_id, method, note
  ) values (
    quote_row.organization_id, quote_row.id, version_row.id, 'approved', 'staff',
    (select auth.uid()), 'in_person', clean_note
  )
  returning id into new_decision_id;

  insert into public.quote_signatures (
    organization_id, quote_id, quote_version_id, quote_decision_id, signer_name, method,
    document_hash, image_object_key, image_byte_size
  ) values (
    quote_row.organization_id, quote_row.id, version_row.id, new_decision_id, clean_signer,
    signature_method, version_row.document_hash, signature_object_key, signature_byte_size
  );

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.approved',
    'Collected ' || clean_signer || '''s signature in person', (select auth.uid()),
    jsonb_build_object(
      'version_number', version_row.version_number, 'method', 'in_person', 'signed', true
    )
  );

  return jsonb_build_object(
    'quote_id', quote_row.id, 'status', quote_row.status, 'decision', quote_row.decision,
    'decided_at', quote_row.decided_at, 'version_number', version_row.version_number,
    'signed', true
  );
end;
$$;

-- 4. What staff may read about a signature ----------------------------------------------------------------

-- The signature on the answer that currently counts, if there is one. Revising ends the decision, so this
-- goes quiet on its own the moment the document is rewritten - the row stays, it is simply no longer the
-- answer. The object key never leaves the server: the id is what the staff image route is asked for.
create or replace function public.quote_current_signature(target_quote_id uuid)
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
      select jsonb_build_object(
        'quote_signature_id', signature.id,
        'signer_name', signature.signer_name,
        'method', signature.method,
        'signed_at', signature.signed_at,
        'has_image', signature.image_object_key is not null,
        'version_number', version.version_number
      )
      from public.quote_signatures as signature
      join public.quote_decisions as decision
        on decision.id = signature.quote_decision_id
      join public.quote_versions as version
        on version.id = signature.quote_version_id
      where signature.organization_id = quote_row.organization_id
        and signature.quote_id = quote_row.id
        and decision.is_current
    ),
    'null'::jsonb
  );
end;
$$;

-- 5. Least privilege ---------------------------------------------------------------------------------------

alter table public.quote_signatures enable row level security;

create policy "permitted members can view quote signatures"
on public.quote_signatures for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));

revoke all on public.quote_signatures from anon, authenticated;
grant select on public.quote_signatures to authenticated;

-- The customer command stays reachable only by our own server holding the service key.
revoke all on function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer)
  from public;
revoke execute on function
  public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer)
  from anon, authenticated;
grant execute on function
  public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer)
  to service_role;

revoke all on function
  public.record_quote_in_person_signature(uuid, text, text, text, integer, text, integer) from public;
revoke execute on function
  public.record_quote_in_person_signature(uuid, text, text, text, integer, text, integer) from anon;
grant execute on function
  public.record_quote_in_person_signature(uuid, text, text, text, integer, text, integer) to authenticated;

revoke all on function public.quote_current_signature(uuid) from public;
revoke execute on function public.quote_current_signature(uuid) from anon;
grant execute on function public.quote_current_signature(uuid) to authenticated;
