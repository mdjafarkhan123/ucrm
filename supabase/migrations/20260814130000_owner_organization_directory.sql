-- Part 6F: searchable organization directory and attention queues.
--
-- The Organizations screen currently loads every organization and filters/searches in the
-- browser. That breaks down once the platform has more than a page of organizations, and it
-- cannot search by the primary administrator's email at all -- that email lives behind
-- organization_members plus Supabase Auth (auth.users), which PostgREST/RLS cannot expose
-- per-row to a list screen without an N+1 call to the Auth admin API.
--
-- This adds one read-only, service_role-only function that does the search, attention-reason
-- computation, and keyset pagination in the database, plus the index that pagination needs.
--
-- Attention reasons (approved in docs/jafar-completion-contract.md, "Commercial control
-- decisions"): access_overdue, expiring_soon, administrator_missing,
-- administrator_ownership_unclear, setup_or_recovery_failed, legacy_review. An organization can
-- carry more than one at once; totals count unique organizations, not reason occurrences.
--
-- setup_or_recovery_failed reads public.platform_operation_attempts for unresolved
-- (pending/retrying) rows targeted at the organization. Nothing writes such a row yet --
-- administrator recovery is Part 7 -- so this reason is wired up now and will simply start
-- lighting up once that part ships, per Jafar's approval.

create index if not exists organizations_created_at_id_idx
  on public.organizations (created_at desc, id desc);

create or replace function public.owner_organization_directory(
  search_term text default null,
  attention_reason text default null,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null,
  page_size integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with org_context as (
    select
      o.id,
      o.name,
      o.slug,
      o.lifecycle_status,
      o.created_at,
      o.updated_at,
      coalesce(cs.commercial_timezone, 'UTC') as commercial_timezone,
      (now() at time zone coalesce(cs.commercial_timezone, 'UTC'))::date as today_date,
      st.paid_through_date,
      st.grace_ends_at
    from public.organizations o
    left join public.organization_commercial_settings cs on cs.organization_id = o.id
    left join public.organization_commercial_state st on st.organization_id = o.id
  ),
  member_counts as (
    select
      organization_id,
      count(*) as member_count,
      count(*) filter (where role = 'owner') as owner_count
    from public.organization_members
    group by organization_id
  ),
  free_access_latest as (
    select distinct on (event.organization_id, coalesce(event.target_grant_id, event.id))
      event.organization_id,
      event.action,
      event.starts_at,
      event.access_until_date
    from public.organization_free_access_events event
    order by event.organization_id, coalesce(event.target_grant_id, event.id), event.occurred_at desc, event.id desc
  ),
  free_access_summary as (
    select
      oc.id as organization_id,
      coalesce(bool_or(
        fal.action <> 'end'
        and fal.starts_at <= oc.today_date
        and (fal.access_until_date is null or fal.access_until_date >= oc.today_date)
      ), false) as free_access_active,
      coalesce(bool_or(
        fal.action <> 'end'
        and fal.starts_at <= oc.today_date
        and fal.access_until_date is not null
        and fal.access_until_date >= oc.today_date
        and (fal.access_until_date - oc.today_date) <= 7
      ), false) as free_access_expiring_soon
    from org_context oc
    left join free_access_latest fal on fal.organization_id = oc.id
    group by oc.id
  ),
  package_exception_summary as (
    select
      oc.id as organization_id,
      (
        exists (
          select 1 from public.organization_feature_overrides f
          where f.organization_id = oc.id
            and f.expires_at is not null
            and f.starts_at <= now()
            and ((f.expires_at at time zone oc.commercial_timezone)::date - oc.today_date) between 0 and 7
        )
        or exists (
          select 1 from public.organization_limit_overrides l
          where l.organization_id = oc.id
            and l.expires_at is not null
            and l.starts_at <= now()
            and ((l.expires_at at time zone oc.commercial_timezone)::date - oc.today_date) between 0 and 7
        )
      ) as package_exception_expiring_soon
    from org_context oc
  ),
  setup_recovery_summary as (
    select
      oc.id as organization_id,
      exists (
        select 1 from public.platform_operation_attempts op
        where op.target_kind = 'organization'
          and op.target_id = oc.id
          and op.status in ('pending', 'retrying')
      ) as setup_or_recovery_failed
    from org_context oc
  ),
  owner_emails as (
    select
      m.organization_id,
      array_agg(distinct u.email) filter (where u.email is not null) as owner_email_list
    from public.organization_members m
    join auth.users u on u.id = m.user_id
    where m.role = 'owner'
    group by m.organization_id
  ),
  computed as (
    select
      oc.id,
      oc.name,
      oc.slug,
      oc.lifecycle_status,
      oc.created_at,
      oc.updated_at,
      coalesce(mc.member_count, 0) as member_count,
      coalesce(mc.owner_count, 0) as owner_count,
      (
        oc.paid_through_date is not null
        and (oc.paid_through_date >= oc.today_date or (oc.grace_ends_at is not null and oc.grace_ends_at >= now()))
      ) as paid_through_eligible,
      coalesce(fas.free_access_active, false) as free_access_active,
      coalesce(fas.free_access_expiring_soon, false) as free_access_expiring_soon,
      coalesce(pes.package_exception_expiring_soon, false) as package_exception_expiring_soon,
      coalesce(srs.setup_or_recovery_failed, false) as setup_or_recovery_failed,
      coalesce(oe.owner_email_list, array[]::text[]) as owner_email_list
    from org_context oc
    left join member_counts mc on mc.organization_id = oc.id
    left join free_access_summary fas on fas.organization_id = oc.id
    left join package_exception_summary pes on pes.organization_id = oc.id
    left join setup_recovery_summary srs on srs.organization_id = oc.id
    left join owner_emails oe on oe.organization_id = oc.id
  ),
  reasoned as (
    select
      c.*,
      (c.lifecycle_status = 'active' and not c.paid_through_eligible and not c.free_access_active)
        as is_access_overdue,
      (c.free_access_expiring_soon or c.package_exception_expiring_soon) as is_expiring_soon,
      (c.owner_count = 0) as is_administrator_missing,
      (c.owner_count > 1) as is_administrator_ownership_unclear,
      c.setup_or_recovery_failed as is_setup_or_recovery_failed,
      (c.lifecycle_status = 'pending_setup') as is_legacy_review
    from computed c
  ),
  tagged as (
    select
      r.*,
      array_remove(
        array[
          case when is_access_overdue then 'access_overdue' end,
          case when is_administrator_missing then 'administrator_missing' end,
          case when is_administrator_ownership_unclear then 'administrator_ownership_unclear' end,
          case when is_setup_or_recovery_failed then 'setup_or_recovery_failed' end,
          case when is_expiring_soon then 'expiring_soon' end,
          case when is_legacy_review then 'legacy_review' end
        ],
        null
      ) as attention_reasons
    from reasoned r
  ),
  matching as (
    select t.*
    from tagged t
    where
      search_term is null
      or trim(search_term) = ''
      or t.name ilike '%' || search_term || '%'
      or t.slug ilike '%' || search_term || '%'
      or exists (select 1 from unnest(t.owner_email_list) as email where email ilike '%' || search_term || '%')
  ),
  filtered as (
    select m.*
    from matching m
    where attention_reason is null or attention_reason = any(m.attention_reasons)
  ),
  page as (
    select f.*
    from filtered f
    where cursor_created_at is null or (f.created_at, f.id) < (cursor_created_at, cursor_id)
    order by f.created_at desc, f.id desc
    limit least(greatest(coalesce(page_size, 50), 1), 100)
  ),
  page_meta as (
    select count(*) as returned_count from page
  ),
  page_last as (
    select created_at, id from page order by created_at asc, id asc limit 1
  ),
  totals as (
    select
      count(*) as all_count,
      count(*) filter (where lifecycle_status = 'active') as active_count,
      count(*) filter (where lifecycle_status = 'suspended') as suspended_count,
      count(*) filter (where lifecycle_status = 'pending_setup') as pending_setup_count,
      count(*) filter (where is_access_overdue) as access_overdue_count,
      count(*) filter (where is_expiring_soon) as expiring_soon_count,
      count(*) filter (where is_administrator_missing) as administrator_missing_count,
      count(*) filter (where is_administrator_ownership_unclear) as administrator_ownership_unclear_count,
      count(*) filter (where is_setup_or_recovery_failed) as setup_or_recovery_failed_count,
      count(*) filter (where is_legacy_review) as legacy_review_count
    from tagged
  ),
  matching_totals as (
    select count(*) as matching_count from filtered
  )
  select jsonb_build_object(
    'organizations', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'name', p.name,
            'slug', p.slug,
            'lifecycle_status', p.lifecycle_status,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'member_count', p.member_count,
            'attention_reasons', to_jsonb(p.attention_reasons)
          )
          order by p.created_at desc, p.id desc
        )
        from page p
      ),
      '[]'::jsonb
    ),
    'next_cursor', case
      when (select returned_count from page_meta) >= least(greatest(coalesce(page_size, 50), 1), 100)
        then (select jsonb_build_object('created_at', pl.created_at, 'id', pl.id) from page_last pl)
      else null
    end,
    'totals', jsonb_build_object(
      'all', (select all_count from totals),
      'active', (select active_count from totals),
      'suspended', (select suspended_count from totals),
      'pending_setup', (select pending_setup_count from totals),
      'matching', (select matching_count from matching_totals),
      'attention', jsonb_build_object(
        'access_overdue', (select access_overdue_count from totals),
        'expiring_soon', (select expiring_soon_count from totals),
        'administrator_missing', (select administrator_missing_count from totals),
        'administrator_ownership_unclear', (select administrator_ownership_unclear_count from totals),
        'setup_or_recovery_failed', (select setup_or_recovery_failed_count from totals),
        'legacy_review', (select legacy_review_count from totals)
      )
    )
  );
$$;

revoke all on function public.owner_organization_directory(text, text, timestamptz, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.owner_organization_directory(text, text, timestamptz, uuid, integer)
  to service_role;

comment on function public.owner_organization_directory(text, text, timestamptz, uuid, integer) is
  'Read-only, service_role-only search, attention-reason computation, and keyset pagination for the Platform Owner organization directory.';
