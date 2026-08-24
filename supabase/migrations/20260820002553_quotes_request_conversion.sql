-- Quotes, Part 2: turning one Request into one Quote, once.
-- Everything the command touches -- the quote, its draft version, the copied lines, the pipeline card, the
-- follow-up tasks, and the request's own status -- moves together or not at all. A repeat of the same
-- command returns the same answer; a different command against an already converted request is refused.

-- 1. A pipeline card may belong to a Quote ------------------------------------------------------------------

alter table public.opportunities
  add column quote_id uuid;

alter table public.opportunities
  add constraint opportunities_quote_organization_fk foreign key (organization_id, quote_id)
    references public.quotes(organization_id, id) on delete cascade,
  -- A card is a Request card or a Quote card, never both. Conversion creates a second card rather than
  -- rewriting the first, so the Request keeps its own history.
  add constraint opportunities_single_source check (
    request_id is null or quote_id is null
  );

create unique index opportunities_quote_unique
  on public.opportunities(organization_id, quote_id)
  where quote_id is not null;

comment on column public.opportunities.quote_id is
  'Set on the card created by public.convert_request_to_quote. The Quote board columns arrive with the '
  'later Quote parts; until then this card is parked off the board.';

-- New columns are invisible to members until they are granted; see the Part 2 note on this table.
grant select (quote_id) on public.opportunities to authenticated;

-- 2. One added branch in the stage derivation ------------------------------------------------------------------

-- The only Part 1 pipeline code this migration changes. Without it a Quote card would default to New
-- Request and appear on the live board as if a customer had just called, which is untrue. Parking it at
-- request_closed keeps it off the board honestly until the Quote stages exist.
create or replace function private.opportunity_apply_stage()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  resolved_stage text;
  request_row record;
begin
  if new.quote_id is not null then
    resolved_stage := 'request_closed';
  elsif new.request_id is null then
    -- A standalone Opportunity sits at the front of the board until a Request gives it real state.
    resolved_stage := 'new_request';
  else
    select
      request.status as status,
      assessment.id is not null as has_assessment,
      assessment.starts_at as starts_at,
      assessment.completed_at as completed_at
    into request_row
    from public.requests as request
    left join public.assessments as assessment
      on assessment.request_id = request.id
    where request.id = new.request_id
      and request.organization_id = new.organization_id;

    resolved_stage := private.request_pipeline_stage(
      request_row.status,
      coalesce(request_row.has_assessment, false),
      request_row.starts_at,
      request_row.completed_at
    );
  end if;

  new.stage := resolved_stage;

  if tg_op = 'INSERT' then
    new.stage_entered_at := coalesce(new.stage_entered_at, now());
  elsif new.stage is distinct from old.stage then
    new.stage_entered_at := now();
  else
    new.stage_entered_at := old.stage_entered_at;
  end if;

  return new;
end;
$$;

revoke all on function private.opportunity_apply_stage() from public;

-- 3. The conversion command ---------------------------------------------------------------------------------

create or replace function public.convert_request_to_quote(
  target_request_id uuid,
  idempotency_key text,
  request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.requests;
  source_opportunity public.opportunities;
  existing_quote public.quotes;
  new_quote public.quotes;
  new_version public.quote_versions;
  new_opportunity_id uuid;
  allocated_number integer;
  organization_currency text;
  organization_name text;
  client_name text;
  property_row public.properties;
  copied_count integer;
  copied_subtotal bigint;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  -- Lock order matches the outcome engine: the pipeline card first, then its request. Two commands racing
  -- on the same work therefore queue up instead of deadlocking against each other.
  select * into source_opportunity
  from public.opportunities
  where request_id = target_request_id
  for update;

  select * into request_row
  from public.requests
  where id = target_request_id
  for update;

  -- One answer for "no such request" and "not your request": a stranger learns nothing either way.
  if request_row.id is null
     or not private.member_has_permission(
       request_row.organization_id, (select auth.uid()), 'quotes.create'
     ) then
    raise exception 'You do not have access to create a quote from this request.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotency is checked before state. A retry that arrives after the first call already succeeded must
  -- be recognised as the same command, not rejected as "already converted".
  select * into existing_quote
  from public.quotes
  where organization_id = request_row.organization_id
    and request_id = target_request_id
  for update;

  if found then
    if existing_quote.conversion_idempotency_key is not distinct from idempotency_key
       and existing_quote.conversion_request_hash is not distinct from request_hash then
      return jsonb_build_object(
        'applied', false,
        'quote_id', existing_quote.id,
        'quote_number', existing_quote.quote_number,
        'quote_version_id', existing_quote.draft_version_id,
        'status', existing_quote.status
      );
    end if;

    raise exception 'This request already has a quote.' using errcode = '40001';
  end if;

  -- A finished assessment is still convertible: in Jobber that is exactly the moment the office is meant
  -- to price the work. Completed, converted, and archived requests are not live work any more.
  if request_row.status not in ('new', 'unscheduled', 'assessment_completed') then
    raise exception 'This request cannot be turned into a quote right now.' using errcode = 'check_violation';
  end if;

  select settings.currency_code into organization_currency
  from public.organization_settings as settings
  where settings.organization_id = request_row.organization_id;

  select organization.name into organization_name
  from public.organizations as organization
  where organization.id = request_row.organization_id;

  select client.display_name into client_name
  from public.clients as client
  where client.id = request_row.client_id;

  select * into property_row
  from public.properties
  where id = request_row.property_id;

  allocated_number := private.allocate_quote_number(request_row.organization_id);

  insert into public.quotes (
    organization_id, client_id, property_id, request_id, quote_number, title, currency_code,
    conversion_idempotency_key, conversion_request_hash, created_by
  ) values (
    request_row.organization_id,
    request_row.client_id,
    request_row.property_id,
    target_request_id,
    allocated_number,
    request_row.title,
    coalesce(organization_currency, 'USD'),
    idempotency_key,
    request_hash,
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code,
    client_display_name, organization_name,
    service_address_line1, service_address_line2, service_city,
    service_state_region, service_postal_code, service_country,
    created_by
  ) values (
    new_quote.organization_id,
    new_quote.id,
    1,
    'draft',
    new_quote.currency_code,
    client_name,
    organization_name,
    property_row.address_line1,
    property_row.address_line2,
    property_row.city,
    property_row.state_region,
    property_row.postal_code,
    property_row.country,
    (select auth.uid())
  )
  returning * into new_version;

  -- The copy is what makes the quote its own document. From here the catalog and the request can change
  -- as much as anyone likes and these numbers do not move.
  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable
  )
  select
    line.organization_id, new_quote.id, new_version.id, line.position, line.catalog_item_id,
    line.category, line.is_labor, line.name, line.description, line.unit_label,
    line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable
  from public.request_pricing_lines as line
  where line.request_id = target_request_id;

  select coalesce(sum(line.line_total_minor), 0), count(*)
  into copied_subtotal, copied_count
  from public.quote_version_lines as line
  where line.quote_version_id = new_version.id;

  update public.quote_versions set subtotal_minor = copied_subtotal where id = new_version.id;
  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  -- The quote gets its own card. The stage trigger parks it off the board.
  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title)
  returning id into new_opportunity_id;

  -- Only work still to be done follows the quote. A task somebody already finished belongs to the request
  -- as history and stays where it happened. No limit check is needed: the new card starts empty and the
  -- old one already respected the five-open cap.
  if source_opportunity.id is not null then
    update public.tasks
    set opportunity_id = new_opportunity_id
    where organization_id = new_quote.organization_id
      and opportunity_id = source_opportunity.id
      and status = 'open';
  end if;

  -- This one update is also what takes the original request card off the board: the Part 1 resync trigger
  -- recomputes its stage from the new status without any extra code here.
  update public.requests set status = 'converted' where id = target_request_id;

  return jsonb_build_object(
    'applied', true,
    'quote_id', new_quote.id,
    'quote_number', new_quote.quote_number,
    'quote_version_id', new_version.id,
    'status', new_quote.status,
    'line_count', copied_count,
    'subtotal_minor', copied_subtotal
  );
end;
$$;

revoke all on function public.convert_request_to_quote(uuid, text, text) from public;
revoke execute on function public.convert_request_to_quote(uuid, text, text) from anon;
grant execute on function public.convert_request_to_quote(uuid, text, text) to authenticated;
