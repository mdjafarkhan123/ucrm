-- A job's status follows its visits: Upcoming, Today, Late and Action required.
-- Found in the multi-industry connected proof (B12): a job with a visit booked still read "Unscheduled".
-- The approved jobs contract (docs/jobs-behavior-contract.md, Job lifecycle) derives these from the job's next
-- incomplete visit; the database only ever answered Unscheduled, Requires invoicing, Ending soon and Archived.
-- Proof: supabase/tests/database/jobs_status_follows_visits.sql

-- Only the "everything else" answer of private.job_derived_status is refined; Archived, Requires invoicing and
-- Ending soon keep outranking visits exactly as before, so that function is left untouched.
CREATE OR REPLACE FUNCTION private.job_status_with_visits(
  base_status text,
  today date,
  next_open_visit_date date,
  has_open_visit boolean,
  has_any_visit boolean
) RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when base_status <> 'unscheduled' or today is null then base_status
    when not coalesce(has_any_visit, false) then 'unscheduled'
    when not coalesce(has_open_visit, false) then 'action_required'
    when next_open_visit_date is null then 'unscheduled'
    when next_open_visit_date < today then 'late'
    when next_open_visit_date = today then 'today'
    else 'upcoming'
  end;
$function$;

COMMENT ON FUNCTION private.job_status_with_visits(text, date, date, boolean, boolean) IS
  'Refines a job''s Unscheduled answer from its visits: the earliest open dated visit against today gives Late, Today or Upcoming; open visits with no date stay Unscheduled; every visit done gives Action required; a job that never had a visit stays Unscheduled. Any other status passes through unchanged.';

REVOKE ALL ON FUNCTION private.job_status_with_visits(text, date, date, boolean, boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION private.job_status_with_visits(text, date, date, boolean, boolean) TO authenticated;

CREATE OR REPLACE VIEW public.job_list_rows WITH (security_invoker = 'true') AS
 SELECT job.id,
    job.organization_id,
    job.job_number,
    job.title,
    job.job_type,
    job.is_as_needed,
    job.status,
    job.price_basis,
    job.billing_timing,
    job.currency_code,
    job.contract_start_date,
    job.contract_end_date,
    job.quote_id,
    job.created_at,
    private.job_status_with_visits(
      private.job_derived_status(job.status, job.job_type, job.contract_end_date, calendar.today, (EXISTS ( SELECT 1
           FROM public.job_invoice_reminders reminder
          WHERE ((reminder.organization_id = job.organization_id) AND (reminder.job_id = job.id) AND (reminder.status = 'pending'::text) AND (reminder.due_on <= calendar.today))))),
      calendar.today, visit.next_open_visit_date, visit.has_open_visit, visit.has_any_visit) AS derived_status,
    job.client_id,
    client.display_name AS client_display_name,
    client.company_name AS client_company_name,
    job.property_id,
    property.label AS property_label,
    property.address_line1 AS property_address_line1,
    property.city AS property_city,
    property.state_region AS property_state_region,
    property.postal_code AS property_postal_code
   FROM (((public.jobs job
     LEFT JOIN private.organization_calendars() calendar(organization_id, today) ON ((calendar.organization_id = job.organization_id)))
     LEFT JOIN public.clients client ON (((client.organization_id = job.organization_id) AND (client.id = job.client_id))))
     LEFT JOIN public.properties property ON (((property.organization_id = job.organization_id) AND (property.id = job.property_id))))
     LEFT JOIN LATERAL ( SELECT min(v.visit_date) FILTER (WHERE v.completed_at IS NULL) AS next_open_visit_date,
            COALESCE(bool_or(v.completed_at IS NULL), false) AS has_open_visit,
            (count(*) > 0) AS has_any_visit
           FROM public.job_visits v
          WHERE ((v.organization_id = job.organization_id) AND (v.job_id = job.id))) visit ON (true);

COMMENT ON VIEW public.job_list_rows IS 'What the Jobs list draws: identity, client and property context, and the derived status (Requires invoicing from due reminders; Upcoming, Today, Late and Action required from the job''s visits). No money - that comes from public.job_money.';

CREATE OR REPLACE VIEW public.job_status_count_rows WITH (security_invoker = 'true') AS
 SELECT job.organization_id,
    private.job_status_with_visits(
      private.job_derived_status(job.status, job.job_type, job.contract_end_date, calendar.today, (due_reminder.job_id IS NOT NULL)),
      calendar.today, visit.next_open_visit_date, visit.has_open_visit, visit.has_any_visit) AS derived_status
   FROM ((public.jobs job
     LEFT JOIN private.organization_calendars() calendar(organization_id, today) ON ((calendar.organization_id = job.organization_id)))
     LEFT JOIN ( SELECT reminder.organization_id,
            reminder.job_id
           FROM (public.job_invoice_reminders reminder
             JOIN private.organization_calendars() cal(organization_id, today) ON ((cal.organization_id = reminder.organization_id)))
          WHERE ((reminder.status = 'pending'::text) AND (reminder.due_on <= cal.today))
          GROUP BY reminder.organization_id, reminder.job_id) due_reminder ON (((due_reminder.organization_id = job.organization_id) AND (due_reminder.job_id = job.id))))
     LEFT JOIN LATERAL ( SELECT min(v.visit_date) FILTER (WHERE v.completed_at IS NULL) AS next_open_visit_date,
            COALESCE(bool_or(v.completed_at IS NULL), false) AS has_open_visit,
            (count(*) > 0) AS has_any_visit
           FROM public.job_visits v
          WHERE ((v.organization_id = job.organization_id) AND (v.job_id = job.id))) visit ON (true);

COMMENT ON VIEW public.job_status_count_rows IS 'One row per job with just its organization and derived status, the due-reminder check done as a single joined set and the visit check as one indexed lookup per job. Feeds public.job_status_counts; the rich per-row job_list_rows feeds the paged list.';
