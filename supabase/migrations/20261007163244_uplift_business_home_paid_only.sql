-- Jafar business management C1 fix: "Accounts to create" counts paid Applications only. Needs attention also
-- holds unpaid Applications, so it left the count, which now matches the Applications list it opens.

create or replace function public.owner_business_home(today_date date, agenda_limit integer default 60)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with due as (
    select r.id, r.business_name, r.country_code, r.trade, r.next_action, r.next_action_due_on,
      r.next_action_kind
    from public.platform_business_relationships r
    where r.next_action_due_on is not null
      and r.next_action_due_on <= today_date + 7
  ),
  listed as (
    select d.*
    from due d
    order by d.next_action_due_on, d.business_name, d.id
    limit least(greatest(coalesce(agenda_limit, 60), 1), 200)
  )
  select jsonb_build_object(
    'review', (
      select count(*) from public.platform_business_relationships where lead_status = 'ready_for_review'
    ),
    'first_contact', (
      select count(*) from public.platform_business_relationships where next_action_kind = 'first_contact'
    ),
    -- Paid and the payment still stands: the account is Uplift's to make.
    'accounts_to_create', (
      select count(*) from public.platform_onboarding_applications
      where stage = 'payment_confirmed' and payment_reversed_at is null
    ),
    'overdue', (select count(*) from due where next_action_due_on < today_date),
    'today', (select count(*) from due where next_action_due_on = today_date),
    'upcoming', (select count(*) from due where next_action_due_on > today_date),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', l.id,
          'business_name', l.business_name,
          'country_code', l.country_code,
          'trade', l.trade,
          'next_action', l.next_action,
          'due_on', l.next_action_due_on,
          'first_contact', l.next_action_kind = 'first_contact',
          'deal_stage', d.stage
        )
        order by l.next_action_due_on, l.business_name, l.id
      )
      from listed l
      left join public.platform_deals d
        on d.relationship_id = l.id and d.stage not in ('lost', 'won')
    ), '[]'::jsonb)
  );
$function$;

