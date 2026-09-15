-- Paid-launch-trust Part 7, C3: freeze a work report's content at send.
--
-- 20260913100000 built the work report door on purpose "always current" -- a cleared photo or answer fixes
-- every link already sent, live. Jafar reversed that approval 2026-09-10: Jobber has no standing customer
-- work-report link at all. Its nearest equivalent is attaching selected notes and photos to a quote or
-- invoice email (jobber-04-jobs-visits-scheduling.md, "Notes are internal by default, and become
-- customer-visible only by deliberately attaching them to a quote or invoice email") -- and an email
-- attachment cannot silently change after it is sent. Our link is the same kind of moment; it should behave
-- the same way.
--
-- The fix carries the document, not the report: `job_report_access_links` gets its own `frozen_document`,
-- filled in once, at the moment `issue_job_report_access_link` creates the link -- the same builder,
-- `private.job_report_customer_document`, called one call earlier than before. The customer's reader
-- (`resolve_job_report_access_link`) now just hands that back. Staff's own "Preview as client"
-- (`job_report_customer_preview`) is unchanged: it is not a sent document, so it keeps showing the live
-- selection right up to the moment a link is actually issued.
--
-- Five links already exist with nothing frozen. There is no earlier state to recover, so they are backfilled
-- with today's live document -- the closest available truth -- before the column is made not-null.

-- 1. The column ---------------------------------------------------------------------------------------------

alter table public.job_report_access_links add column frozen_document jsonb;

comment on column public.job_report_access_links.frozen_document is
  'The complete customer document as it stood the moment this link was issued. Set once, at insert, by '
  'issue_job_report_access_link -- never rebuilt later, so a later edit to the report cannot change what an '
  'already-shared link shows.';

update public.job_report_access_links as link
set frozen_document = private.job_report_customer_document(job, org.name, coalesce(report.include_price, false))
from public.jobs as job
join public.organizations as org on org.id = job.organization_id
left join public.job_reports as report
  on report.organization_id = job.organization_id and report.job_id = job.id
where job.id = link.job_id
  and link.frozen_document is null;

-- Nothing recoverable for a link whose job or report is somehow gone (should not happen -- both cascade with
-- the job -- but a not-null column needs every row settled, not a best effort that might leave one null).
update public.job_report_access_links
set frozen_document = '{}'::jsonb
where frozen_document is null;

alter table public.job_report_access_links alter column frozen_document set not null;

-- 2. Freeze it at the moment the link is made ----------------------------------------------------------------

create or replace function public.issue_job_report_access_link(
  target_job_id uuid,
  supplied_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  report_row public.job_reports;
  business_name text;
  client_name text;
  client_email text;
  link_row public.job_report_access_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'A customer link needs a full-length token.' using errcode = 'check_violation';
  end if;

  select * into job_row from public.jobs where id = target_job_id for update;
  if job_row.id is null
     or not private.member_has_permission(job_row.organization_id, caller, 'jobs.edit')
     or not private.can_view_job(job_row.organization_id, target_job_id) then
    raise exception 'You do not have access to share this job.' using errcode = 'insufficient_privilege';
  end if;

  if not private.job_report_has_content(job_row.organization_id, target_job_id) then
    raise exception 'Add something to the work report before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  select client.display_name,
         (
           select lower(trim(method.value))
           from public.client_contact_methods as method
           where method.organization_id = job_row.organization_id
             and method.client_id = job_row.client_id
             and method.kind = 'email'
           order by method.is_primary desc, method.created_at
           limit 1
         )
    into client_name, client_email
  from public.clients as client
  where client.organization_id = job_row.organization_id and client.id = job_row.client_id;

  if client_email is null then
    raise exception 'Add an email address to this client before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = job_row.organization_id and job_id = target_job_id;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = job_row.organization_id;

  update public.job_report_access_links
  set revoked_at = now(), revoked_reason = 'rotated'
  where organization_id = job_row.organization_id
    and job_id = target_job_id
    and revoked_at is null;

  insert into public.job_report_access_links (
    organization_id, job_id, recipient_name, recipient_email, token_hash, issued_by, frozen_document
  ) values (
    job_row.organization_id, target_job_id,
    coalesce(nullif(trim(client_name), ''), client_email), client_email,
    supplied_token_hash, caller,
    private.job_report_customer_document(job_row, business_name, coalesce(report_row.include_price, false))
  )
  returning * into link_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    job_row.organization_id, 'job', target_job_id, 'job.work_report_link_issued',
    'Shared the work report with the customer', caller,
    jsonb_build_object('job_report_access_link_id', link_row.id, 'recipient_email', client_email)
  );

  return jsonb_build_object(
    'job_id', target_job_id,
    'job_report_access_link_id', link_row.id,
    'recipient_name', link_row.recipient_name,
    'recipient_email', link_row.recipient_email,
    'issued_at', link_row.issued_at,
    'expires_at', link_row.expires_at
  );
end;
$$;

comment on function public.issue_job_report_access_link(uuid, bytea) is
  'Creates the customer''s door to a job''s work report and freezes the current document onto the link at '
  'that moment, so a later report edit cannot change what this link shows. Returns everything but the token, '
  'which only ever exists in the caller''s response. Rotates the job''s live links so asking twice never '
  'leaves two open. Needs jobs.edit and a report with content.';

revoke all on function public.issue_job_report_access_link(uuid, bytea) from public;
revoke execute on function public.issue_job_report_access_link(uuid, bytea) from anon;
grant execute on function public.issue_job_report_access_link(uuid, bytea) to authenticated;

-- 3. The customer's reader just hands back what was frozen ---------------------------------------------------

create or replace function public.resolve_job_report_access_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.job_report_access_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.job_report_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  return link_row.frozen_document;
end;
$$;

comment on function public.resolve_job_report_access_link(bytea) is
  'The customer''s reader. Hashed token in, the document frozen onto this link at issue out, or null for '
  'every failure alike -- unknown, revoked, or expired. Service role only: not part of the Data API for '
  'anybody else.';

revoke all on function public.resolve_job_report_access_link(bytea) from public;
revoke execute on function public.resolve_job_report_access_link(bytea) from anon, authenticated;
grant execute on function public.resolve_job_report_access_link(bytea) to service_role;

-- 4. Recording a view no longer depends on the live report -----------------------------------------------

-- A link's frozen document is viewable for as long as the link itself is live, regardless of what the report
-- looks like today, so this stops asking whether the *current* report still has content -- that question no
-- longer decides whether a sent link can be viewed.
create or replace function public.record_job_report_link_view(supplied_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.job_report_access_links;
  was_first boolean;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.job_report_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  was_first := link_row.first_viewed_at is null;

  update public.job_report_access_links
  set first_viewed_at = coalesce(first_viewed_at, now()),
      last_viewed_at = now(),
      view_count = view_count + 1
  where id = link_row.id;

  if was_first then
    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      link_row.organization_id, 'job', link_row.job_id, 'job.work_report_viewed_by_client',
      'The customer opened the work report', null,
      jsonb_build_object('job_report_access_link_id', link_row.id)
    );
  end if;

  return jsonb_build_object('recorded', true, 'first_view', was_first);
end;
$$;

comment on function public.record_job_report_link_view(bytea) is
  'The customer''s browser telling us the report was on screen. Stamps the link''s view facts and writes one '
  'feed line the first time. Service role only.';

revoke all on function public.record_job_report_link_view(bytea) from public;
revoke execute on function public.record_job_report_link_view(bytea) from anon, authenticated;
grant execute on function public.record_job_report_link_view(bytea) to service_role;
