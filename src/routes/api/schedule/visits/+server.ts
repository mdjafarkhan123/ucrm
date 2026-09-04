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
//
// Alongside visits it returns the window's on-site assessments (Version 1.1). Assessments store their times
// as instants, not a plain date like a visit, so this read does not try to bound them to the org-timezone
// day itself: it filters `starts_at` by a UTC range padded a day on each side of the window -- wide enough to
// cover any timezone offset -- and the browser, which already holds the organization timezone, converts each
// instant to the day and clock time it belongs on and drops any that fall outside the visible days. Undated
// (unscheduled) assessments have a null `starts_at` and never match the range, so the backlog stays separate,
// exactly as the contract requires. A single day of over-fetch is negligible: an assessment is one row per
// request, so a window holds tens where the visit read is capped at hundreds.
const one = <Row>(value: Row | Row[] | null): Row | null =>
	Array.isArray(value) ? (value[0] ?? null) : (value ?? null);

const DAY_MS = 86_400_000;

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const parsed = scheduleWindowQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { from, to } = parsed.data;
	const organizationId = check.auth.organization.id;

	// One more row than the ceiling, so a full page can tell "exactly at the limit" from "there is more".
	const { data, error } = await event.locals.supabase
		.from('job_visits')
		.select(
			`id, job_id, visit_date, start_time, end_time, all_day, title, completed_at, revision, position,
			 assignments:job_visit_assignments(user_id),
			 job:jobs(job_number, title, client_id, property_id,
			   client:clients(display_name, company_name),
			   property:properties(label, address_line1, city, state_region, postal_code,
			     latitude, longitude, geocode_status))`
		)
		.eq('organization_id', organizationId)
		.gte('visit_date', from)
		.lte('visit_date', to)
		.order('visit_date', { ascending: true })
		.order('start_time', { ascending: true, nullsFirst: true })
		.order('position', { ascending: true })
		.limit(SCHEDULE_VISIT_LIMIT + 1);

	if (error) return databaseError();

	// The window is a range of org-timezone days; `starts_at` is a UTC instant. A day of padding on each end
	// is wider than any real timezone offset, so no in-window assessment is missed; the browser trims the edges.
	const lowerInstant = new Date(Date.parse(`${from}T00:00:00Z`) - DAY_MS).toISOString();
	const upperInstant = new Date(Date.parse(`${to}T00:00:00Z`) + 2 * DAY_MS).toISOString();

	const { data: assessmentData, error: assessmentError } = await event.locals.supabase
		.from('assessments')
		.select(
			`id, request_id, starts_at, ends_at, all_day, completed_at, instructions,
			 assignments:assessment_assignees(user_id),
			 request:requests(title, status, client_id, property_id,
			   client:clients(display_name, company_name),
			   property:properties(label, address_line1, city, state_region, postal_code,
			     latitude, longitude, geocode_status))`
		)
		.eq('organization_id', organizationId)
		.gte('starts_at', lowerInstant)
		.lt('starts_at', upperInstant)
		.order('starts_at', { ascending: true })
		.limit(SCHEDULE_VISIT_LIMIT + 1);

	if (assessmentError) return databaseError();

	// Schedule-owned events (Version 1.1). Unlike an assessment, an event stores a plain org-timezone day, so
	// it walks the same (organization_id, event_date) index the visit read uses and needs no instant padding.
	const { data: eventData, error: eventError } = await event.locals.supabase
		.from('schedule_events')
		.select('id, title, description, event_date, start_time, end_time, all_day')
		.eq('organization_id', organizationId)
		.gte('event_date', from)
		.lte('event_date', to)
		.order('event_date', { ascending: true })
		.order('start_time', { ascending: true, nullsFirst: true })
		.limit(SCHEDULE_VISIT_LIMIT + 1);

	if (eventError) return databaseError();

	const rows = data ?? [];
	const assessmentRows = assessmentData ?? [];
	const eventRows = eventData ?? [];
	const truncated =
		rows.length > SCHEDULE_VISIT_LIMIT ||
		assessmentRows.length > SCHEDULE_VISIT_LIMIT ||
		eventRows.length > SCHEDULE_VISIT_LIMIT;

	// A visit belongs to one job, a job to one client and one property, so PostgREST answers each embed with
	// an object. The generated types cannot see that through the composite (organization_id, job_id) key and
	// describe them as arrays, so each one is read through the same narrowing rather than trusted either way.
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
			property_postal_code: property?.postal_code ?? null,
			property_latitude: property?.latitude ?? null,
			property_longitude: property?.longitude ?? null,
			property_geocode_status: property?.geocode_status ?? null
		};
	});

	// Assessment times stay raw instants: the browser converts them to the org-timezone day and clock time,
	// the same rule it uses to know which day is Today. An assessment belongs to one request, which belongs to
	// one client and one property, so each embed is narrowed the same way the visit embeds are.
	const assessments = assessmentRows.slice(0, SCHEDULE_VISIT_LIMIT).map((row) => {
		const request = one(row.request);
		const client = request ? one(request.client) : null;
		const property = request ? one(request.property) : null;
		return {
			id: row.id,
			request_id: row.request_id,
			starts_at: row.starts_at,
			ends_at: row.ends_at,
			all_day: row.all_day,
			completed_at: row.completed_at,
			instructions: row.instructions,
			assignee_ids: (row.assignments ?? []).map((assignment) => assignment.user_id),
			request_title: request?.title ?? null,
			request_status: request?.status ?? null,
			client_id: request?.client_id ?? null,
			client_name: client?.display_name ?? null,
			client_company_name: client?.company_name ?? null,
			property_id: request?.property_id ?? null,
			property_label: property?.label ?? null,
			property_address_line1: property?.address_line1 ?? null,
			property_city: property?.city ?? null,
			property_state_region: property?.state_region ?? null,
			property_postal_code: property?.postal_code ?? null,
			property_latitude: property?.latitude ?? null,
			property_longitude: property?.longitude ?? null,
			property_geocode_status: property?.geocode_status ?? null
		};
	});

	// Events are already plain org-day rows -- no client, no embed, no conversion -- so they pass straight
	// through, capped by the same window limit as visits and assessments.
	const events = eventRows.slice(0, SCHEDULE_VISIT_LIMIT);

	return json(
		{
			from,
			to,
			visits,
			assessments,
			events,
			// True means this window holds more work than one read returns, so the calendar says so instead
			// of drawing a quietly incomplete day.
			truncated,
			limit: SCHEDULE_VISIT_LIMIT
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
