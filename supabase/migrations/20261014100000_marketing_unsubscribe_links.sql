-- Marketing (M1): the customer's own way out of marketing email.
--
-- One opaque link per marketing email, owned by UCRM rather than by the delivery provider, so that an
-- unsubscribe is recorded as evidence in client_marketing_consent_events (source 'unsubscribe') and can
-- never leak across organizations. Operational email — quotes, invoices, receipts, job updates, replies —
-- is not affected by anything here: only marketing eligibility reads this consent state.
--
-- The link follows the proven shape of public.quote_access_links (20260821035539): the raw token exists
-- once, in the URL inside the email, and only its SHA-256 reaches the database. A stolen backup therefore
-- contains no working unsubscribe link, and the token itself carries no organization, client or email id.
--
-- Links are additive and are never rotated. Every marketing email issues its own link and every issued
-- link keeps working, because a customer may unsubscribe from a message received months ago (CAN-SPAM
-- requires a mechanism that still works for at least 30 days, and mailbox providers' one-click button
-- reuses the header of whichever message is on screen).

-- 1. The link ---------------------------------------------------------------------------------------------

create table public.client_marketing_unsubscribe_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  client_contact_method_id uuid not null,
  -- SHA-256 of a 256-bit random token, as raw bytes: fixed width, and the only thing about the token that
  -- outlives the request that created it.
  token_hash bytea not null,
  issued_at timestamptz not null default now(),
  constraint client_marketing_unsubscribe_links_token_hash_unique unique (token_hash),
  constraint client_marketing_unsubscribe_links_org_id_unique unique (organization_id, id),
  -- Names all three columns, so a link can never point at an email address belonging to another client or
  -- another organization.
  constraint client_marketing_unsubscribe_links_method_fk
    foreign key (organization_id, client_id, client_contact_method_id)
    references public.client_contact_methods (organization_id, client_id, id) on delete cascade,
  constraint client_marketing_unsubscribe_links_token_hash_check
    check (octet_length(token_hash) = 32)
);

comment on table public.client_marketing_unsubscribe_links is
  'One marketing-email unsubscribe link, scoped to an organization and one email contact method. Stores '
  'only the token hash; the raw token exists solely in the URL placed in the email. Service role only — '
  'members never read this table, because every row is a credential.';

comment on column public.client_marketing_unsubscribe_links.token_hash is
  'SHA-256 of the raw token, computed by the server. The database never sees the token itself.';

-- Serves the delete cascades from both parents (each leads with organization_id) and the only other read,
-- which is "what links exist for this email address".
create index client_marketing_unsubscribe_links_method_idx
  on public.client_marketing_unsubscribe_links (organization_id, client_contact_method_id, issued_at desc);

-- 2. Issuing a link ---------------------------------------------------------------------------------------

-- Called by our own server while rendering a marketing email's footer. The caller supplies only the hash
-- and the email method; the client is derived from that method's own row, so no caller can aim a link at
-- an address it did not already have permission to reach.
create function public.issue_client_marketing_unsubscribe_link(
  target_organization_id uuid,
  target_client_contact_method_id uuid,
  supplied_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  method_row public.client_contact_methods;
  link_row public.client_marketing_unsubscribe_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'An unsubscribe link needs a full-length token.' using errcode = 'check_violation';
  end if;

  select * into method_row
  from public.client_contact_methods
  where organization_id = target_organization_id
    and id = target_client_contact_method_id
    and kind = 'email';

  if method_row.id is null then
    raise exception 'That email address is not on this organization.' using errcode = 'check_violation';
  end if;

  insert into public.client_marketing_unsubscribe_links (
    organization_id, client_id, client_contact_method_id, token_hash
  ) values (
    method_row.organization_id, method_row.client_id, method_row.id, supplied_token_hash
  )
  returning * into link_row;

  return jsonb_build_object(
    'unsubscribe_link_id', link_row.id,
    'client_id', link_row.client_id,
    'client_contact_method_id', link_row.client_contact_method_id,
    'issued_at', link_row.issued_at
  );
end;
$$;

-- 3. Reading a link ---------------------------------------------------------------------------------------

-- What the unsubscribe page is allowed to show: which business sent the email, which address it went to,
-- and whether that address is already unsubscribed. Nothing else — no client name, no history, no ids.
-- An unknown token returns null, so the page cannot be used to find out whether an address exists.
create function public.resolve_client_marketing_unsubscribe_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.client_marketing_unsubscribe_links;
  method_value text;
  business_name text;
  current_state text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row
  from public.client_marketing_unsubscribe_links
  where token_hash = supplied_token_hash;

  if link_row.id is null then
    return null;
  end if;

  select method.value into method_value
  from public.client_contact_methods as method
  where method.organization_id = link_row.organization_id
    and method.id = link_row.client_contact_method_id;

  if method_value is null then
    return null;
  end if;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = link_row.organization_id;

  select state into current_state
  from public.client_marketing_consent_state
  where organization_id = link_row.organization_id
    and client_contact_method_id = link_row.client_contact_method_id;

  return jsonb_build_object(
    'business_name', business_name,
    'email', method_value,
    'already_unsubscribed', coalesce(current_state, 'unknown') = 'opted_out'
  );
end;
$$;

-- 4. Acting on a link -------------------------------------------------------------------------------------

-- The whole unsubscribe, in one call. Already unsubscribed is a success, not an error: a second click, a
-- mailbox provider retrying its one-click POST, and a forwarded copy of the email all arrive here, and
-- none of them should write a second identical event or show the customer a failure.
--
-- An address that was opted in again afterwards genuinely can be unsubscribed again, which is why this
-- reads the current state instead of keying on the link.
create function public.record_client_marketing_unsubscribe(
  supplied_token_hash bytea,
  supplied_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.client_marketing_unsubscribe_links;
  method_value text;
  business_name text;
  current_state text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  if supplied_evidence is null or jsonb_typeof(supplied_evidence) <> 'object' then
    raise exception 'Unsubscribe evidence must be an object.' using errcode = 'check_violation';
  end if;

  select * into link_row
  from public.client_marketing_unsubscribe_links
  where token_hash = supplied_token_hash;

  if link_row.id is null then
    return null;
  end if;

  select method.value into method_value
  from public.client_contact_methods as method
  where method.organization_id = link_row.organization_id
    and method.id = link_row.client_contact_method_id;

  if method_value is null then
    return null;
  end if;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = link_row.organization_id;

  -- Locks the projected row for this address where one exists, so a repeat click cannot read a stale
  -- "still opted in" and write a second event. With no row yet there is nothing to lock, and two clicks
  -- arriving in the same instant can both insert; that costs one extra evidence row and reaches the same
  -- state, which is the right trade for an append-only ledger.
  select state into current_state
  from public.client_marketing_consent_state
  where organization_id = link_row.organization_id
    and client_contact_method_id = link_row.client_contact_method_id
  for update;

  if coalesce(current_state, 'unknown') <> 'opted_out' then
    insert into public.client_marketing_consent_events (
      organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
      disclosure, evidence, occurred_at, created_by
    ) values (
      link_row.organization_id,
      link_row.client_id,
      link_row.client_contact_method_id,
      'opt_out',
      'unsubscribe',
      link_row.id::text || ':' || gen_random_uuid()::text,
      null,
      supplied_evidence || jsonb_build_object(
        'channel', 'unsubscribe_link',
        'unsubscribe_link_id', link_row.id
      ),
      now(),
      null
    );
  end if;

  return jsonb_build_object(
    'business_name', business_name,
    'email', method_value,
    'already_unsubscribed', coalesce(current_state, 'unknown') = 'opted_out'
  );
end;
$$;

-- 5. Least privilege --------------------------------------------------------------------------------------

-- RLS on with no policy: the table is reachable only by the service role, exactly like the consent ledger
-- it feeds.
alter table public.client_marketing_unsubscribe_links enable row level security;
revoke all on public.client_marketing_unsubscribe_links from anon, authenticated;

revoke all on function public.issue_client_marketing_unsubscribe_link(uuid, uuid, bytea) from public;
revoke execute on function public.issue_client_marketing_unsubscribe_link(uuid, uuid, bytea)
  from anon, authenticated;
grant execute on function public.issue_client_marketing_unsubscribe_link(uuid, uuid, bytea) to service_role;

revoke all on function public.resolve_client_marketing_unsubscribe_link(bytea) from public;
revoke execute on function public.resolve_client_marketing_unsubscribe_link(bytea) from anon, authenticated;
grant execute on function public.resolve_client_marketing_unsubscribe_link(bytea) to service_role;

revoke all on function public.record_client_marketing_unsubscribe(bytea, jsonb) from public;
revoke execute on function public.record_client_marketing_unsubscribe(bytea, jsonb) from anon, authenticated;
grant execute on function public.record_client_marketing_unsubscribe(bytea, jsonb) to service_role;
