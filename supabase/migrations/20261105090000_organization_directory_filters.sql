-- Organization directory filters. One pass over the organizations answers every filter, the page and the
-- counts, exactly as before; the filters only add conditions to that pass. The package an organization is on
-- (the agreement in force today: latest started, not cancelled) is now looked up for every organization
-- through the (organization_id, effective_from desc, created_at desc) index, so it can be filtered on and
-- counted: one index probe per organization, the same order of work as the rest of this function.
-- The single attention reason becomes a list (an organization matches when it has ANY of them); new filters:
-- lifecycle, package (or none), billing interval, renews within, joined range, team size.
begin;

drop function if exists public.owner_organization_directory(text, text, timestamptz, uuid, integer);

CREATE OR REPLACE FUNCTION public.owner_organization_directory(
  search_term text DEFAULT NULL::text,
  attention_filter text[] DEFAULT NULL::text[],
  cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  cursor_id uuid DEFAULT NULL::uuid,
  page_size integer DEFAULT 50,
  lifecycle_filter text[] DEFAULT NULL::text[],
  package_filter uuid[] DEFAULT NULL::uuid[],
  no_package_filter boolean DEFAULT false,
  billing_filter text DEFAULT NULL::text,
  renews_filter text DEFAULT NULL::text,
  joined_from_filter timestamp with time zone DEFAULT NULL::timestamp with time zone,
  joined_before_filter timestamp with time zone DEFAULT NULL::timestamp with time zone,
  team_size_filter text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  current_package as (
    select
      oc.id as organization_id,
      pkg.package_id,
      pkg.name as package_name,
      pkg.edition_number as package_edition_number,
      pkg.billing_interval as package_billing_interval
    from org_context oc
    left join lateral (
      select e.package_id, e.name, e.edition_number, a.billing_interval
      from public.organization_package_agreements a
      join public.package_editions e on e.id = a.edition_id
      where a.organization_id = oc.id and a.effective_from <= now() and a.cancelled_at is null
      order by a.effective_from desc, a.created_at desc
      limit 1
    ) pkg on true
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
      exists (
        select 1 from public.organization_package_exceptions x
        where x.organization_id = oc.id
          and x.starts_at <= now()
          and x.ends_at > now()
          and ((x.ends_at at time zone oc.commercial_timezone)::date - oc.today_date) between 0 and 7
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
      oc.today_date,
      oc.paid_through_date,
      oc.grace_ends_at,
      (
        oc.paid_through_date is not null
        and (oc.paid_through_date >= oc.today_date or (oc.grace_ends_at is not null and oc.grace_ends_at >= now()))
      ) as paid_through_eligible,
      coalesce(fas.free_access_active, false) as free_access_active,
      coalesce(fas.free_access_expiring_soon, false) as free_access_expiring_soon,
      coalesce(pes.package_exception_expiring_soon, false) as package_exception_expiring_soon,
      coalesce(srs.setup_or_recovery_failed, false) as setup_or_recovery_failed,
      exists (
        select 1 from public.communication_email_setup_requests_waiting w
        where w.organization_id = oc.id
      ) as email_setup_requested,
      coalesce(oe.owner_email_list, array[]::text[]) as owner_email_list,
      cp.package_id,
      cp.package_name,
      cp.package_edition_number,
      cp.package_billing_interval
    from org_context oc
    left join current_package cp on cp.organization_id = oc.id
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
      (c.lifecycle_status = 'active' and not c.free_access_active
        and c.paid_through_date is not null
        and c.paid_through_date - c.today_date between 0 and 6) as is_renewal_due,
      (c.lifecycle_status = 'active' and not c.free_access_active
        and c.paid_through_date is not null
        and c.paid_through_date < c.today_date
        and c.grace_ends_at is not null and c.grace_ends_at >= now()) as is_payment_overdue,
      (c.free_access_expiring_soon or c.package_exception_expiring_soon) as is_expiring_soon,
      (c.owner_count = 0) as is_administrator_missing,
      (c.owner_count > 1) as is_administrator_ownership_unclear,
      c.setup_or_recovery_failed as is_setup_or_recovery_failed,
      c.email_setup_requested as is_email_setup_requested
    from computed c
  ),
  tagged as (
    select
      r.*,
      array_remove(
        array[
          case when is_access_overdue then 'access_overdue' end,
          case when is_payment_overdue then 'payment_overdue' end,
          case when is_renewal_due then 'renewal_due' end,
          case when is_administrator_missing then 'administrator_missing' end,
          case when is_administrator_ownership_unclear then 'administrator_ownership_unclear' end,
          case when is_setup_or_recovery_failed then 'setup_or_recovery_failed' end,
          case when is_expiring_soon then 'expiring_soon' end,
          case when is_email_setup_requested then 'email_setup_requested' end
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
    where (attention_filter is null or cardinality(attention_filter) = 0 or m.attention_reasons && attention_filter)
      and (lifecycle_filter is null or cardinality(lifecycle_filter) = 0 or m.lifecycle_status = any(lifecycle_filter))
      and (
        ((package_filter is null or cardinality(package_filter) = 0) and not coalesce(no_package_filter, false))
        or m.package_id = any(package_filter)
        or (coalesce(no_package_filter, false) and m.package_id is null)
      )
      and (billing_filter is null or m.package_billing_interval = billing_filter)
      and (
        renews_filter is null
        or (
          m.paid_through_date is not null
          and case
            when renews_filter = 'overdue' then m.paid_through_date < m.today_date
            when renews_filter in ('7', '14', '30')
              then m.paid_through_date between m.today_date and m.today_date + renews_filter::int
            else false
          end
        )
      )
      and (joined_from_filter is null or m.created_at >= joined_from_filter)
      and (joined_before_filter is null or m.created_at < joined_before_filter)
      and (
        team_size_filter is null
        or case team_size_filter
          when 'solo' then m.member_count = 1
          when 'small' then m.member_count between 2 and 5
          when 'large' then m.member_count >= 6
          else false
        end
      )
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
      count(*) filter (where lifecycle_status = 'pending_closure') as pending_closure_count,
      count(*) filter (where lifecycle_status = 'closed') as closed_count,
      count(*) filter (where package_id is null) as no_package_count,
      count(*) filter (where is_access_overdue) as access_overdue_count,
      count(*) filter (where is_payment_overdue) as payment_overdue_count,
      count(*) filter (where is_renewal_due) as renewal_due_count,
      count(*) filter (where is_expiring_soon) as expiring_soon_count,
      count(*) filter (where is_administrator_missing) as administrator_missing_count,
      count(*) filter (where is_administrator_ownership_unclear) as administrator_ownership_unclear_count,
      count(*) filter (where is_setup_or_recovery_failed) as setup_or_recovery_failed_count,
      count(*) filter (where is_email_setup_requested) as email_setup_requested_count
    from tagged
  ),
  package_facets as (
    select
      package_id,
      (array_agg(package_name order by package_edition_number desc nulls last))[1] as name,
      count(*) as organization_count
    from tagged
    where package_id is not null
    group by package_id
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
            'attention_reasons', to_jsonb(p.attention_reasons),
            'package', case when p.package_name is null then null else jsonb_build_object(
              'package_id', p.package_id,
              'name', p.package_name,
              'edition_number', p.package_edition_number,
              'billing_interval', p.package_billing_interval
            ) end
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
      'pending_closure', (select pending_closure_count from totals),
      'closed', (select closed_count from totals),
      'no_package', (select no_package_count from totals),
      'packages', coalesce(
        (select jsonb_agg(
          jsonb_build_object('package_id', f.package_id, 'name', f.name, 'count', f.organization_count)
          order by f.name, f.package_id
        ) from package_facets f),
        '[]'::jsonb
      ),
      'matching', (select matching_count from matching_totals),
      'attention', jsonb_build_object(
        'access_overdue', (select access_overdue_count from totals),
        'payment_overdue', (select payment_overdue_count from totals),
        'renewal_due', (select renewal_due_count from totals),
        'expiring_soon', (select expiring_soon_count from totals),
        'administrator_missing', (select administrator_missing_count from totals),
        'administrator_ownership_unclear', (select administrator_ownership_unclear_count from totals),
        'setup_or_recovery_failed', (select setup_or_recovery_failed_count from totals),
        'email_setup_requested', (select email_setup_requested_count from totals)
      )
    )
  );
$function$;

revoke all on function public.owner_organization_directory(text, text[], timestamptz, uuid, integer, text[], uuid[], boolean, text, text, timestamptz, timestamptz, text) from public, anon, authenticated;

commit;
