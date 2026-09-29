-- client_schedule_rows: the client page's Client schedule — one client's visits and on-site assessments,
-- split into what is still to be done (upcoming, soonest first) and what has been done (past, latest first).
--
-- Why a function and not a PostgREST embed: a visit reaches its client only through its job, and with an
-- ORDER BY visit_date ... LIMIT the planner may walk the organization's whole calendar index
-- (job_visits_calendar_idx) and discard every other client's visits on the way. For a busy contractor with
-- years of visits and a client who has nothing upcoming, that is the whole calendar read for an empty answer.
-- Materializing the client's own jobs and requests first drives every read from jobs_client_idx /
-- requests_client_idx, then job_visits_job_idx / assessments_request_unique, so the cost follows this one
-- client's work.
--
-- SECURITY INVOKER: every table is read under the caller's own RLS, exactly as the embed did, so an
-- assigned-scope member still sees only the visits they are on. The route checks jobs.view first.

CREATE OR REPLACE FUNCTION "public"."client_schedule_rows"(
	"target_organization_id" "uuid",
	"target_client_id" "uuid",
	"upcoming_limit" integer,
	"past_limit" integer
) RETURNS TABLE(
	"kind" "text",
	"bucket" "text",
	"id" "uuid",
	"record_id" "uuid",
	"visit_date" "date",
	"start_time" time without time zone,
	"end_time" time without time zone,
	"all_day" boolean,
	"starts_at" timestamp with time zone,
	"ends_at" timestamp with time zone,
	"title" "text",
	"record_title" "text",
	"job_number" integer,
	"completed_at" timestamp with time zone,
	"assignee_ids" "uuid"[]
)
    LANGUAGE "sql" STABLE SECURITY INVOKER
    SET "search_path" TO ''
    AS $$
	WITH client_jobs AS MATERIALIZED (
		SELECT j.id, j.job_number, j.title, j.status
		FROM public.jobs j
		WHERE j.organization_id = target_organization_id
			AND j.client_id = target_client_id
	),
	client_requests AS MATERIALIZED (
		SELECT r.id, r.title, r.status
		FROM public.requests r
		WHERE r.organization_id = target_organization_id
			AND r.client_id = target_client_id
	),
	-- A closed job's leftover open visits are not coming up, so upcoming reads active jobs only.
	upcoming_visits AS (
		SELECT v.id, v.job_id, v.visit_date, v.start_time, v.end_time, v.all_day, v.title, v.completed_at,
			j.title AS job_title, j.job_number
		FROM client_jobs j
		JOIN public.job_visits v ON v.organization_id = target_organization_id AND v.job_id = j.id
		WHERE j.status = 'active'
			AND v.completed_at IS NULL
			AND v.visit_date IS NOT NULL
		ORDER BY v.visit_date, v.start_time NULLS FIRST, v.position, v.id
		LIMIT least(greatest(upcoming_limit, 1), 50)
	),
	past_visits AS (
		SELECT v.id, v.job_id, v.visit_date, v.start_time, v.end_time, v.all_day, v.title, v.completed_at,
			j.title AS job_title, j.job_number
		FROM client_jobs j
		JOIN public.job_visits v ON v.organization_id = target_organization_id AND v.job_id = j.id
		WHERE v.completed_at IS NOT NULL
		ORDER BY v.visit_date DESC NULLS LAST, v.start_time DESC NULLS LAST, v.id DESC
		LIMIT least(greatest(past_limit, 1), 50)
	),
	-- A finished request's leftover open assessment is not coming up either.
	upcoming_assessments AS (
		SELECT a.id, a.request_id, a.starts_at, a.ends_at, a.all_day, a.completed_at, r.title AS request_title
		FROM client_requests r
		JOIN public.assessments a ON a.organization_id = target_organization_id AND a.request_id = r.id
		WHERE r.status IN ('needs_approval', 'new', 'unscheduled')
			AND a.completed_at IS NULL
			AND a.starts_at IS NOT NULL
		ORDER BY a.starts_at, a.id
		LIMIT least(greatest(upcoming_limit, 1), 50)
	),
	past_assessments AS (
		SELECT a.id, a.request_id, a.starts_at, a.ends_at, a.all_day, a.completed_at, r.title AS request_title
		FROM client_requests r
		JOIN public.assessments a ON a.organization_id = target_organization_id AND a.request_id = r.id
		WHERE a.completed_at IS NOT NULL
		ORDER BY a.starts_at DESC NULLS LAST, a.id DESC
		LIMIT least(greatest(past_limit, 1), 50)
	),
	visits AS (
		SELECT 'upcoming' AS bucket, uv.* FROM upcoming_visits uv
		UNION ALL
		SELECT 'past', pv.* FROM past_visits pv
	),
	assessment_rows AS (
		SELECT 'upcoming' AS bucket, ua.* FROM upcoming_assessments ua
		UNION ALL
		SELECT 'past', pa.* FROM past_assessments pa
	)
	SELECT 'visit', v.bucket, v.id, v.job_id, v.visit_date, v.start_time, v.end_time, v.all_day,
		NULL::timestamptz, NULL::timestamptz, v.title, v.job_title, v.job_number, v.completed_at,
		ARRAY(
			SELECT va.user_id FROM public.job_visit_assignments va
			WHERE va.visit_id = v.id ORDER BY va.created_at, va.user_id
		)
	FROM visits v
	UNION ALL
	SELECT 'assessment', a.bucket, a.id, a.request_id, NULL::date, NULL::time, NULL::time, a.all_day,
		a.starts_at, a.ends_at, NULL::text, a.request_title, NULL::integer, a.completed_at,
		ARRAY(
			SELECT aa.user_id FROM public.assessment_assignees aa
			WHERE aa.assessment_id = a.id ORDER BY aa.created_at, aa.user_id
		)
	FROM assessment_rows a;
$$;

ALTER FUNCTION "public"."client_schedule_rows"("uuid", "uuid", integer, integer) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."client_schedule_rows"("uuid", "uuid", integer, integer) IS 'The client page''s Client schedule: one client''s open (upcoming) and completed (past) visits and assessments, driven from the client''s own jobs and requests. Security invoker, so every row passes the caller''s RLS.';

REVOKE ALL ON FUNCTION "public"."client_schedule_rows"("uuid", "uuid", integer, integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."client_schedule_rows"("uuid", "uuid", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."client_schedule_rows"("uuid", "uuid", integer, integer) TO "service_role";
