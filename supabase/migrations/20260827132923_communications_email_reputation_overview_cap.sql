-- Communications Part 7.4 follow-up (API-layer performance review).
--
-- The owner overview returned every organization currently in warn or pause, with its full metrics
-- payload, unbounded. On a bad provider day that is a list the size of the tenant base serialised
-- into one response. Capped at 100 -- the worst offenders first, which is what the screen shows --
-- with the true total alongside so the page can say "100 of 812".

create or replace function public.get_communication_email_reputation_overview()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'platform_thresholds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'signal', t.signal, 'window_key', t.window_key, 'window_hours', t.window_hours,
        'warn_rate', t.warn_rate, 'pause_rate', t.pause_rate,
        'min_sample_recipients', t.min_sample_recipients, 'min_event_count', t.min_event_count,
        'reason', t.reason, 'actor_owner_email', t.actor_owner_email, 'effective_from', t.effective_from
      ) order by t.signal, t.window_key)
      from public.communication_email_reputation_thresholds t
      where t.scope = 'platform' and t.effective_to is null
    ), '[]'::jsonb),
    'attention_total', (
      select count(*)
      from public.communication_email_reputation_state s
      where s.worst_status <> 'ok'
    ),
    'attention_limit', 100,
    'attention', coalesce((
      select jsonb_agg(entry.payload order by entry.rank)
      from (
        select
          row_number() over (
            order by case s.worst_status when 'pause' then 0 else 1 end, s.evaluated_at desc
          ) as rank,
          jsonb_build_object(
            'organization_id', s.organization_id, 'organization_name', o.name,
            'worst_status', s.worst_status, 'evaluated_at', s.evaluated_at,
            'last_breach_at', s.last_breach_at, 'metrics', s.metrics,
            'reputation_pause_id', (
              select p.id from public.communication_email_sending_pauses p
              where p.scope = 'organization' and p.organization_id = s.organization_id
                and p.source = 'auto_reputation' and p.released_at is null
              limit 1
            )
          ) as payload
        from public.communication_email_reputation_state s
        join public.organizations o on o.id = s.organization_id
        where s.worst_status <> 'ok'
        order by case s.worst_status when 'pause' then 0 else 1 end, s.evaluated_at desc
        limit 100
      ) entry
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_communication_email_reputation_overview()
  from public, anon, authenticated;
grant execute on function public.get_communication_email_reputation_overview() to service_role;
