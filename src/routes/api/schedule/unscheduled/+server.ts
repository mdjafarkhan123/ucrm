import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { SCHEDULE_VISIT_LIMIT } from '$lib/server/validation/schedule.schema';

// The Schedule's backlog read: every visit that has no date yet -- the "schedule later" pile a Job creates
// when its first visit is left undated. It is the calendar's date-window read turned inside out, walking the
// same (organization_id, visit_date) index for the rows where visit_date IS NULL, and carrying each visit's
// job, client and property through the job's own foreign keys under the reader's own RLS, exactly as the
// window read does.
//
// It takes no window: the backlog has no date to bound. It is bounded instead by the same 500-row ceiling as
// a window, and answers `truncated` when a genuinely huge backlog exceeds it, so the drawer says so rather
// than quietly showing a partial pile. A completed visit is never here -- completion needs a date -- but the
// filter is explicit so a stray one can never read as work still waiting to be placed.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	// One more row than the ceiling, so a full page can tell "exactly at the limit" from "there is more".
	const { data, error } = await event.locals.supabase
		.from('job_visits')
		.select(
			`id, job_id, visit_date, start_time, end_time, all_day, title, completed_at, revision, position,
			 created_at,
			 assignments:job_visit_assignments(user_id),
			 job:jobs(job_number, title, client_id, property_id,
			   client:clients(display_name, company_name),
			   property:properties(label, address_line1, city, state_region, postal_code))`
		)
		.eq('organization_id', check.auth.organization.id)
		.is('visit_date', null)
		.is('completed_at', null)
		// Oldest first: the work that has waited longest to be placed leads the drawer.
		.order('created_at', { ascending: true })
		.order('position', { ascending: true })
		.limit(SCHEDULE_VISIT_LIMIT + 1);

	if (error) return databaseError();

	const rows = data ?? [];
	const truncated = rows.length > SCHEDULE_VISIT_LIMIT;

	// A visit belongs to one job, a job to one client and one property, so PostgREST answers each embed with
	// an object. The generated types cannot see that through the composite (organization_id, job_id) key and
	// describe them as arrays, so each one is read through the same narrowing rather than trusted either way.
	const one = <Row>(value: Row | Row[] | null): Row | null =>
		Array.isArray(value) ? (value[0] ?? null) : (value ?? null);

	const visits = rows.slice(0, SCHEDULE_VISIT_LIMIT).map((row) => {
		const job = one(row.job);
		const client = job ? one(job.client) : null;
		const property = job ? one(job.property) : null;
		return {
			id: row.id,
			job_id: row.job_id,
			visit_date: row.visit_date,
			start_time: row.start_time,
			end_time: row.end_time,
			all_day: row.all_day,
			title: row.title,
			completed_at: row.completed_at,
			revision: row.revision,
			position: row.position,
			created_at: row.created_at,
			assignee_ids: (row.assignments ?? []).map((assignment) => assignment.user_id),
			job_number: job?.job_number ?? null,
			job_title: job?.title ?? null,
			client_id: job?.client_id ?? null,
			client_name: client?.display_name ?? null,
			client_company_name: client?.company_name ?? null,
			property_id: job?.property_id ?? null,
			property_label: property?.label ?? null,
			property_address_line1: property?.address_line1 ?? null,
			property_city: property?.city ?? null,
			property_state_region: property?.state_region ?? null,
			property_postal_code: property?.postal_code ?? null
		};
	});

	return json(
		{
			visits,
			// True means the backlog holds more visits than one read returns, so the drawer says so instead
			// of showing a quietly incomplete pile.
			truncated,
			limit: SCHEDULE_VISIT_LIMIT
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
