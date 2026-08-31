-- Quotes Part 5B1: who the document is addressed to, and the one safe way they get to see it.
--
-- Part 5A gave staff publication. This migration gives the published version a customer-facing door:
-- a recipient snapshot, a link bound to organization + quote + version + recipient, and a resolver that
-- turns a token into the frozen customer document and nothing else.
--
-- Two rules shape everything here. The raw token never reaches the database - the server hashes it and
-- passes 32 bytes, so a stolen backup contains no working link. And `anon` gets nothing: no table, no
-- function, no policy. The public page runs on our server with the service key and calls exactly one
-- function, which is the only public seam in the system.

-- 1. Who the quote is addressed to -------------------------------------------------------------------------

create table public.quote_recipients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  -- Snapshots, like everything else a customer sees. A later rename on the client record does not rewrite
  -- who this document was addressed to.
  display_name text not null check (char_length(trim(display_name)) between 1 and 200),
  email text not null check (
    email = lower(trim(email))
    and char_length(email) between 6 and 320
    and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_recipients_organization_id_unique unique (organization_id, id),
  -- What makes a link unable to point at a recipient from another quote: the link's foreign key names all
  -- three columns, so the pair can never disagree.
  constraint quote_recipients_quote_scoped_unique unique (organization_id, quote_id, id),
  constraint quote_recipients_email_unique unique (organization_id, quote_id, email),
  constraint quote_recipients_quote_organization_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete cascade
);

comment on table public.quote_recipients is
  'Quote-owned contact snapshot for the customer copy. Not portal membership and not the client record: '
  'a recipient here can read one quote through one link and nothing else. Members read this table; only '
  'public.issue_quote_access_link writes it.';

-- The email uniqueness index leads with organization and quote, so it also serves every read that asks
-- who this quote is addressed to, and the parent foreign key underneath it. No second index is earned.
create index quote_recipients_created_by_idx
  on public.quote_recipients(created_by) where created_by is not null;

create trigger quote_recipients_set_updated_at
before update on public.quote_recipients
for each row execute function public.set_updated_at();

-- 2. The link itself ---------------------------------------------------------------------------------------

create table public.quote_access_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  quote_version_id uuid not null,
  recipient_id uuid not null,
  -- The SHA-256 of a 256-bit random token, as raw bytes. Fixed width, half the size of the hex text, and
  -- the only thing about the token that survives the request that created it.
  token_hash bytea not null check (octet_length(token_hash) = 32),
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  -- Part 5B1 issues links without an end date. Expiry behavior belongs to 5B2; the column is here so that
  -- part adds behavior rather than a schema change on a table that will already hold live links.
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text check (revoked_reason is null or revoked_reason in ('rotated', 'revoked')),
  constraint quote_access_links_token_hash_unique unique (token_hash),
  constraint quote_access_links_organization_id_unique unique (organization_id, id),
  constraint quote_access_links_version_fk foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade,
  constraint quote_access_links_recipient_fk foreign key (organization_id, quote_id, recipient_id)
    references public.quote_recipients(organization_id, quote_id, id) on delete cascade,
  constraint quote_access_links_revocation_agrees check ((revoked_at is null) = (revoked_reason is null)),
  constraint quote_access_links_expiry_follows_issue check (expires_at is null or expires_at > issued_at)
);

comment on table public.quote_access_links is
  'One customer link. Scoped to organization, quote, published version and recipient. Stores only the '
  'token hash - the raw token exists once, in the URL handed back to the staff member who created it, and '
  'must never appear in a row, a log line, or an activity payload.';

comment on column public.quote_access_links.token_hash is
  'SHA-256 of the raw token, computed by the server. The database never sees the token itself.';

-- The whole public read is one equality lookup on the unique token hash above. These exist for the foreign
-- keys and for the staff view of a quote's links; neither is on the customer path.
create index quote_access_links_version_idx
  on public.quote_access_links(organization_id, quote_id, quote_version_id, issued_at desc);

create index quote_access_links_recipient_idx
  on public.quote_access_links(organization_id, quote_id, recipient_id);

create index quote_access_links_issued_by_idx
  on public.quote_access_links(issued_by) where issued_by is not null;

-- 3. Issuing a link ------------------------------------------------------------------------------------------

-- Locks the quote first, exactly like every other quote command, so issuing and publishing race in a queue
-- instead of a deadlock. Re-issuing rotates: the recipient's older links are revoked in the same
-- transaction, so a forwarded old URL stops working the moment a new one is made.
--
-- The caller supplies only the hash. It cannot name the recipient either - the address comes from the
-- client's own email, so no request body can point a customer link at an arbitrary inbox.
create or replace function public.issue_quote_access_link(
  target_quote_id uuid,
  supplied_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
  recipient_row public.quote_recipients;
  link_row public.quote_access_links;
  client_name text;
  client_email text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'A customer link needs a full-length token.' using errcode = 'check_violation';
  end if;

  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.send'
     ) then
    raise exception 'You do not have access to share this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.current_published_version_id is null then
    raise exception 'Send this quote before creating a customer link.' using errcode = 'check_violation';
  end if;

  if quote_row.status = 'archived' then
    raise exception 'An archived quote cannot be shared.' using errcode = 'check_violation';
  end if;

  select * into version_row
  from public.quote_versions
  where id = quote_row.current_published_version_id;

  select client.display_name,
         (
           select lower(trim(method.value))
           from public.client_contact_methods as method
           where method.organization_id = quote_row.organization_id
             and method.client_id = quote_row.client_id
             and method.kind = 'email'
           order by method.is_primary desc, method.created_at
           limit 1
         )
    into client_name, client_email
  from public.clients as client
  where client.organization_id = quote_row.organization_id
    and client.id = quote_row.client_id;

  if client_email is null then
    raise exception 'Add an email address to this client before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  insert into public.quote_recipients (
    organization_id, quote_id, display_name, email, created_by
  ) values (
    quote_row.organization_id, quote_row.id, coalesce(nullif(trim(client_name), ''), client_email),
    client_email, (select auth.uid())
  )
  on conflict (organization_id, quote_id, email) do update
    set display_name = excluded.display_name
  returning * into recipient_row;

  update public.quote_access_links
  set revoked_at = now(), revoked_reason = 'rotated'
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and recipient_id = recipient_row.id
    and revoked_at is null;

  insert into public.quote_access_links (
    organization_id, quote_id, quote_version_id, recipient_id, token_hash, issued_by
  ) values (
    quote_row.organization_id, quote_row.id, version_row.id, recipient_row.id,
    supplied_token_hash, (select auth.uid())
  )
  returning * into link_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.link_issued',
    'Created a customer link for ' || recipient_row.email, (select auth.uid()),
    jsonb_build_object(
      'quote_version_id', version_row.id,
      'version_number', version_row.version_number,
      'quote_access_link_id', link_row.id
    )
  );

  return jsonb_build_object(
    'quote_id', quote_row.id,
    'quote_access_link_id', link_row.id,
    'quote_version_id', version_row.id,
    'version_number', version_row.version_number,
    'recipient_id', recipient_row.id,
    'recipient_name', recipient_row.display_name,
    'recipient_email', recipient_row.email,
    'issued_at', link_row.issued_at,
    'expires_at', link_row.expires_at
  );
end;
$$;

-- 4. Taking a link back ---------------------------------------------------------------------------------------

-- Revoking twice is the same click arriving twice, not an error: the second call finds it already revoked
-- and hands back the same answer.
create or replace function public.revoke_quote_access_link(target_link_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.quote_access_links;
begin
  select * into link_row from public.quote_access_links where id = target_link_id for update;

  if link_row.id is null
     or not private.member_has_permission(
       link_row.organization_id, (select auth.uid()), 'quotes.send'
     ) then
    raise exception 'You do not have access to change this link.' using errcode = 'insufficient_privilege';
  end if;

  if link_row.revoked_at is not null then
    return jsonb_build_object(
      'quote_access_link_id', link_row.id, 'revoked_at', link_row.revoked_at,
      'already_revoked', true
    );
  end if;

  update public.quote_access_links
  set revoked_at = now(), revoked_reason = 'revoked'
  where id = link_row.id
  returning * into link_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    link_row.organization_id, 'quote', link_row.quote_id, 'quote.link_revoked',
    'Turned off the customer link', (select auth.uid()),
    jsonb_build_object('quote_access_link_id', link_row.id)
  );

  return jsonb_build_object(
    'quote_access_link_id', link_row.id, 'revoked_at', link_row.revoked_at,
    'already_revoked', false
  );
end;
$$;

-- 5. What staff may know about the links ------------------------------------------------------------------------

-- The table itself stays closed to members, because every row holds a token hash. This is the only way in,
-- and it does not select that column at all.
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

-- 6. The one public seam ---------------------------------------------------------------------------------------

-- Our server hashes the token from the URL and calls this. Everything a customer is allowed to see is
-- assembled here, in one round trip, from the frozen version - and everything else is simply never
-- selected. There is no cost column, no margin, no catalog id, no private file and no second recipient in
-- this function to leak.
--
-- Every way of failing returns the same null: unknown token, revoked, expired, archived quote, or a link
-- pointing at a version that is no longer the one on the table. The page above turns that into one plain
-- "not available" screen, so nothing here can be used to find out whether a quote exists.
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

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  select * into recipient_row from public.quote_recipients where id = link_row.recipient_id;

  return jsonb_build_object(
    'quote', jsonb_build_object(
      'quote_number', quote_row.quote_number,
      'status', quote_row.status,
      'sent_at', quote_row.sent_at,
      'decision', quote_row.decision,
      'decided_at', quote_row.decided_at
    ),
    'recipient', jsonb_build_object(
      'name', recipient_row.display_name,
      'email', recipient_row.email
    ),
    'business', jsonb_build_object('name', version_row.organization_name),
    'document', jsonb_build_object(
      'version_number', version_row.version_number,
      'published_at', version_row.published_at,
      'currency_code', version_row.currency_code,
      'client_display_name', version_row.client_display_name,
      'service_address_line1', version_row.service_address_line1,
      'service_address_line2', version_row.service_address_line2,
      'service_city', version_row.service_city,
      'service_state_region', version_row.service_state_region,
      'service_postal_code', version_row.service_postal_code,
      'service_country', version_row.service_country,
      'introduction', version_row.introduction,
      'client_message', version_row.client_message,
      'contract_disclaimer', version_row.contract_disclaimer,
      'show_quantities', version_row.show_quantities,
      'show_unit_prices', version_row.show_unit_prices,
      'show_line_totals', version_row.show_line_totals,
      'show_totals', version_row.show_totals
    ),
    'packages', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', package.id, 'position', package.position, 'name', package.name,
            'description', package.description, 'is_recommended', package.is_recommended
          )
          order by package.position, package.id
        )
        from public.quote_version_packages as package
        where package.organization_id = version_row.organization_id
          and package.quote_id = version_row.quote_id
          and package.quote_version_id = version_row.id
      ),
      '[]'::jsonb
    ),
    -- Every child read names organization and quote as well as the version, because that is the order the
    -- existing child indexes are built in - filtering on the version alone would scan the table.
    --
    -- A hidden switch means the number never enters the payload, rather than being hidden in the browser
    -- where anyone can read it back out of the page source.
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', line.id, 'position', line.position, 'line_kind', line.line_kind,
            'selection_kind', line.selection_kind, 'package_id', line.package_id,
            'is_recommended', line.is_recommended, 'category', line.category,
            'name', line.name, 'description', line.description, 'unit_label', line.unit_label,
            'image_attachment_id', line.image_attachment_id
          )
          || case when version_row.show_quantities
               then jsonb_build_object('quantity', line.quantity) else '{}'::jsonb end
          || case when version_row.show_unit_prices
               then jsonb_build_object('unit_price_minor', line.unit_price_minor) else '{}'::jsonb end
          || case when version_row.show_line_totals
               then jsonb_build_object('line_total_minor', line.line_total_minor) else '{}'::jsonb end
          order by line.position, line.id
        )
        from public.quote_version_lines as line
        where line.organization_id = version_row.organization_id
          and line.quote_id = version_row.quote_id
          and line.quote_version_id = version_row.id
      ),
      '[]'::jsonb
    ),
    'attachments', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', version_attachment.attachment_id,
            'name', version_attachment.display_name,
            'mime_type', file.mime_type,
            'size_bytes', file.size_bytes
          )
          order by version_attachment.position, version_attachment.id
        )
        from public.quote_version_attachments as version_attachment
        join public.attachments as file on file.id = version_attachment.attachment_id
        where version_attachment.organization_id = version_row.organization_id
          and version_attachment.quote_id = version_row.quote_id
          and version_attachment.quote_version_id = version_row.id
          and version_attachment.customer_visible
      ),
      '[]'::jsonb
    ),
    'totals', case when version_row.show_totals then jsonb_build_object(
      'subtotal_minor', version_row.subtotal_minor,
      'discount_name', version_row.discount_name,
      'discount_minor', version_row.discount_minor,
      'tax_name', version_row.tax_name,
      'tax_rate_basis_points', version_row.tax_rate_basis_points,
      'tax_minor', version_row.tax_minor,
      'total_minor', version_row.total_minor
    ) else null end
  );
end;
$$;

-- 7. Least privilege ---------------------------------------------------------------------------------------

alter table public.quote_recipients enable row level security;
alter table public.quote_access_links enable row level security;

create policy "permitted members can view quote recipients"
on public.quote_recipients for select to authenticated
using (organization_id in (select private.permitted_organizations('quotes.view')));

revoke all on public.quote_recipients from anon, authenticated;
grant select on public.quote_recipients to authenticated;

-- No policy and no grant at all: every row holds a token hash, so members read links through
-- public.quote_access_link_state instead, which cannot return that column.
revoke all on public.quote_access_links from anon, authenticated;

revoke all on function public.issue_quote_access_link(uuid, bytea) from public;
revoke execute on function public.issue_quote_access_link(uuid, bytea) from anon;
revoke all on function public.revoke_quote_access_link(uuid) from public;
revoke execute on function public.revoke_quote_access_link(uuid) from anon;
revoke all on function public.quote_access_link_state(uuid) from public;
revoke execute on function public.quote_access_link_state(uuid) from anon;

grant execute on function public.issue_quote_access_link(uuid, bytea) to authenticated;
grant execute on function public.revoke_quote_access_link(uuid) to authenticated;
grant execute on function public.quote_access_link_state(uuid) to authenticated;

-- The resolver is not part of the Data API for anybody. Only our own server, holding the service key,
-- may call it.
revoke all on function public.resolve_quote_access_link(bytea) from public;
revoke execute on function public.resolve_quote_access_link(bytea) from anon, authenticated;
grant execute on function public.resolve_quote_access_link(bytea) to service_role;
