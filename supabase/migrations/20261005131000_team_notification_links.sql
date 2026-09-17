-- CRM launch readiness Part 4, Stage 4: where a team alert opens.
--
-- An alert opens the record the inquiry became, read from current truth rather than frozen at alert time: a
-- chat's visitor can be matched to a client after the alert was created. Form submissions live in the private
-- schema, so the bell's API and the alert email read the destination through this one function.

create function public.team_notification_links(p_organization_id uuid, p_subject_ids uuid[])
returns table (
  subject_type text,
  subject_id uuid,
  request_id uuid,
  job_id uuid,
  client_id uuid
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select 'form_submission', s.id,
    nullif(s.result ->> 'request_id', '')::uuid,
    nullif(s.result ->> 'job_id', '')::uuid,
    nullif(s.result ->> 'client_id', '')::uuid
  from private.form_submissions as s
  where s.organization_id = p_organization_id and s.id = any (p_subject_ids)
  union all
  select 'website_chat_session', w.id, null, null, w.client_id
  from public.website_chat_sessions as w
  where w.organization_id = p_organization_id and w.id = any (p_subject_ids);
$$;

revoke all on function public.team_notification_links(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.team_notification_links(uuid, uuid[]) to service_role;
