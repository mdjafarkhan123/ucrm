import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	SCHEDULE_VISIT_LIMIT,
	scheduleWindowQuerySchema
} from '$lib/server/validation/schedule.schema';

// The Schedule's one date-window read.
//
// It walks job_visits_calendar_idx (organization_id, visit_date) for a window the schema has already bounded
// to 42 days, and brings each visit's job, client and property along through the job's own foreign keys.
// Every embed is subject to the reader's own RLS, exactly as the Jobs list is: a member without
// customers.view gets the visit with a null client rather than a name they may not read.
//
// It deliberately does not embed job_list_rows. That view derives the *job's* status, which costs a
// correlated reminder lookup per row and answers a question the calendar never asks -- a visit carries its
// own status, derived from its own date.
//
// Money is absent on purpose. No card in the approved contract shows a price, so no price is sent.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const parsed = scheduleWindowQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { from, to } = parsed.data;

	// One more row than the ceiling, so a full page can tell "exactly at the limit" from "there is more".
	const { data, error } = await event.locals.supabase
		.from('job_visits')
		.select(
			`id, job_id, visit_date, start_time, end_time, all_day, title, completed_at, revision, position,
			 assignments:job_visit_assignments(user_id),
			 job:jobs(job_number, title, client_id, property_id,
			   client:clients(display_name, company_name),
			   property:properties(label, address_line1, city, state_region, postal_code))`
		)
		.eq('organization_id', check.auth.organization.id)
		.gte('visit_date', from)
		.lte('visit_date', to)
		.order('visit_date', { ascending: true })
		.order('start_time', { ascending: true, nullsFirst: true })
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
			from,
			to,
			visits,
			// True means this window holds more visits than one read returns, so the calendar says so instead
			// of drawing a quietly incomplete day.
			truncated,
			limit: SCHEDULE_VISIT_LIMIT
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
