-- Marketing (M1): let the server read the effective Marketing email allowance.
--
-- private.effective_marketing_email_limit is the single authority for the limit, but the private schema is
-- not reachable through the API. This is a read-only, service-role-only wrapper so the Marketing readiness
-- read asks that one authority instead of copying its override/package rules into application code.
-- It changes no data.

create or replace function public.effective_marketing_email_limit(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  state text,
  value integer,
  is_unlimited boolean,
  source text
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select limit_row.state, limit_row.value, limit_row.is_unlimited, limit_row.source
  from private.effective_marketing_email_limit(target_organization_id, at) as limit_row;
$$;

comment on function public.effective_marketing_email_limit(uuid, timestamptz) is
  'Read-only, service-role-only wrapper over private.effective_marketing_email_limit, the single authority '
  'for the marketing_email_recipients limit. Unset resolves to not_included.';

revoke all on function public.effective_marketing_email_limit(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.effective_marketing_email_limit(uuid, timestamptz) to service_role;
