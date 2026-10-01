-- Pipeline part D2, second step: the lead source filter reads the sources clients really carry.
--
-- `clients.lead_source` is free text. The client form offers a fixed list, but imports, the dashboard's
-- quick add, and older records wrote their own spellings ("referral" beside "Referral", "Google", "staff").
-- An exact match against the form's list left those cards unfindable. So:
--
-- 1. The filter ignores case and stray spaces: "Referral" finds "referral" and " Referral ".
-- 2. `pipeline_lead_sources` lists the sources on the caller's open cards, one entry per spelling-blind
--    source, written the way most of those clients spell it. The board offers these beside the form's list.
--
-- Cost: both read one organization's open cards, the same working set the board already walks
-- (performance note in 20261002233000). No index is added.

-- 1. The filter, written once — only the lead source line changes ------------------------------------

create or replace function private.pipeline_board_filter_clause(
  search_like text,
  search_digits text,
  search_number bigint,
  lead_source_filter text
) returns text
language plpgsql
immutable
set search_path to 'pg_catalog'
as $_$
declare
  clause text := '';
  digits_match text := '';
  number_match text := '';
begin
  if search_like is not null and search_like <> '' then
    if search_digits ~ '^[0-9]{3,20}$' then
      digits_match := format(
        $d$ or (method.kind = 'phone' and method.normalized_value like %L)$d$,
        '%' || search_digits || '%');
    end if;
    if search_number is not null then
      number_match := format(' or quote.quote_number = %L::bigint', search_number);
    end if;

    clause := clause || format($s$
      and (
        opportunity.title ilike %1$L
        %3$s
        or (client_visible.allowed and (
          client.display_name ilike %1$L
          or client.company_name ilike %1$L
          or concat_ws(' ', property.address_line1, property.address_line2, property.city,
               property.state_region, property.postal_code) ilike %1$L
          or exists (
            select 1
            from public.client_contacts as contact
            where contact.organization_id = opportunity.organization_id
              and contact.client_id = opportunity.client_id
              and concat_ws(' ', contact.first_name, contact.last_name) ilike %1$L
          )
          or exists (
            select 1
            from public.client_contact_methods as method
            where method.organization_id = opportunity.organization_id
              and method.client_id = opportunity.client_id
              and (method.value ilike %1$L %2$s)
          )
        ))
      )$s$, search_like, digits_match, number_match);
  end if;

  if lead_source_filter is not null and btrim(lead_source_filter) <> '' then
    clause := clause || format(
      ' and client_visible.allowed and lower(btrim(client.lead_source)) = lower(btrim(%L))',
      lead_source_filter);
  end if;

  return clause;
end;
$_$;

revoke all on function private.pipeline_board_filter_clause(text, text, bigint, text) from public, anon, authenticated;

-- 2. The sources on the board ------------------------------------------------------------------------
--
-- Only clients the caller may see are read, so a source never names a client hidden from them. The
-- spelling shown is the most common one among those clients; a tie goes to the alphabetically first.

create function public.pipeline_lead_sources(target_organization_id uuid)
returns table (lead_source text, open_count bigint)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  caller_id uuid := (select auth.uid());
  sees_every_client boolean;
begin
  -- The same rule the board page applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  sees_every_client :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  return query
    select
      mode() within group (order by btrim(client.lead_source)) as lead_source,
      count(*)::bigint as open_count
    from public.opportunities as opportunity
    join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    -- Matches the partial board indexes: same tenant, same predicate.
    where opportunity.organization_id = target_organization_id
      and opportunity.outcome = 'open'
      and opportunity.board_column <> 'request_closed'
      and btrim(coalesce(client.lead_source, '')) <> ''
      and (sees_every_client
           or private.can_view_client(opportunity.organization_id, opportunity.client_id))
    group by lower(btrim(client.lead_source))
    order by 2 desc, 1
    limit 100;
end;
$_$;

revoke all on function public.pipeline_lead_sources(uuid) from public, anon;
grant execute on function public.pipeline_lead_sources(uuid) to authenticated, service_role;
