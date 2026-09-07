import { json } from '@sveltejs/kit';
import type { QueryData } from '@supabase/supabase-js';
import type { RequestHandler } from './$types';
import { permissionScope, requireOrganizationPermission } from '$lib/server/access/permission';
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

// Each select is spelled out whole rather than assembled from an interpolated string: supabase-js parses the
// select at the type level, and a `${...}` in the middle of one collapses the parse to an error type, taking
// every field's type with it. The narrowed pair adds one embed and changes nothing else.
//
// `mine` is a second, aliased embed of the same assignment table, and its only job is to make the join inner
// so the index selects the caller's rows. `assignments` beside it stays unfiltered and still carries the
// visit's whole crew, which a field worker may see and which draws the avatars on the card. Filtering
// `assignments` itself would have been one character shorter and would have quietly reduced every card to a
// crew of one.
const VISIT_FIELDS =
	`id, job_id, visit_date, start_time, end_time, all_day, title, completed_at, revision, position,
	 assignments:job_visit_assignments(user_id)` as const;
const VISIT_EMBEDS = `job:jobs(job_number, title, client_id, property_id,
	   client:clients(display_name, company_name),
	   property:properties(label, address_line1, city, state_region, postal_code,
	     latitude, longitude, geocode_status))` as const;
const VISIT_SELECT = `${VISIT_FIELDS}, ${VISIT_EMBEDS}` as const;
const VISIT_SELECT_ASSIGNED =
	`${VISIT_FIELDS}, mine:job_visit_assignments!inner(user_id), ${VISIT_EMBEDS}` as const;

const ASSESSMENT_FIELDS = `id, request_id, starts_at, ends_at, all_day, completed_at, instructions,
	 assignments:assessment_assignees(user_id)` as const;
const ASSESSMENT_EMBEDS = `request:requests(title, status, client_id, property_id,
	   client:clients(display_name, company_name),
	   property:properties(label, address_line1, city, state_region, postal_code,
	     latitude, longitude, geocode_status))` as const;
const ASSESSMENT_SELECT = `${ASSESSMENT_FIELDS}, ${ASSESSMENT_EMBEDS}` as const;
const ASSESSMENT_SELECT_ASSIGNED =
	`${ASSESSMENT_FIELDS}, mine:assessment_assignees!inner(user_id), ${ASSESSMENT_EMBEDS}` as const;

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const parsed = scheduleWindowQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { from, to } = parsed.data;
	const organizationId = check.auth.organization.id;

	// Whose week is this? A member narrowed to their assigned work sees only their own visits and assessments
	// either way -- RLS decides that, not this route. What the scope changes here is the question asked: with
	// 'all' the read walks the organization's window, and with 'assigned' it is driven by the caller's own
	// assignment rows instead, so the work grows with what this person is on rather than with how busy the
	// business is. Asking the org's whole week and letting RLS discard the rest gave the same answer and cost
	// 132ms against a 27ms baseline on a 5,000-job tenant; the discarded rows were 786 of 876.
	const scope = permissionScope(check.access, 'jobs.view');
	const assignedOnly = scope === 'assigned';
	const callerId = check.auth.user.id;

	// One more row than the ceiling, so a full page can tell "exactly at the limit" from "there is more".
	// The window, its order and its ceiling are identical either way; only the select differs, and it is passed
	// in whole because supabase-js resolves a select's row type from a single string literal and gives up on a
	// union of two.
	const visitWindow = <Select extends string>(select: Select) =>
		event.locals.supabase
			.from('job_visits')
			.select(select)
			.eq('organization_id', organizationId)
			.gte('visit_date', from)
			.lte('visit_date', to)
			.order('visit_date', { ascending: true })
			.order('start_time', { ascending: true, nullsFirst: true })
			.order('position', { ascending: true })
			.limit(SCHEDULE_VISIT_LIMIT + 1);

	// Never awaited, and it exists for its type alone: passing the select through a generic defers the parse,
	// which keeps the field names honest but leaves every value `any`. Reading the shape back off an unexecuted
	// query of the plain select restores the real column types without a second copy of the window.
	const visitShape = () => event.locals.supabase.from('job_visits').select(VISIT_SELECT);
	type VisitRow = QueryData<ReturnType<typeof visitShape>>[number];

	const { data, error } = assignedOnly
		? await visitWindow(VISIT_SELECT_ASSIGNED).eq('mine.user_id', callerId)
		: await visitWindow(VISIT_SELECT);
	if (error) return databaseError();

	// The window is a range of org-timezone days; `starts_at` is a UTC instant. A day of padding on each end
	// is wider than any real timezone offset, so no in-window assessment is missed; the browser trims the edges.
	const lowerInstant = new Date(Date.parse(`${from}T00:00:00Z`) - DAY_MS).toISOString();
	const upperInstant = new Date(Date.parse(`${to}T00:00:00Z`) + 2 * DAY_MS).toISOString();

	const assessmentWindow = <Select extends string>(select: Select) =>
		event.locals.supabase
			.from('assessments')
			.select(select)
			.eq('organization_id', organizationId)
			.gte('starts_at', lowerInstant)
			.lt('starts_at', upperInstant)
			.order('starts_at', { ascending: true })
			.limit(SCHEDULE_VISIT_LIMIT + 1);

	const assessmentShape = () => event.locals.supabase.from('assessments').select(ASSESSMENT_SELECT);
	type AssessmentRow = QueryData<ReturnType<typeof assessmentShape>>[number];

	const { data: assessmentData, error: assessmentError } = assignedOnly
		? await assessmentWindow(ASSESSMENT_SELECT_ASSIGNED).eq('mine.user_id', callerId)
		: await assessmentWindow(ASSESSMENT_SELECT);
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

	const rows = (data ?? []) as VisitRow[];
	const assessmentRows = (assessmentData ?? []) as AssessmentRow[];
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
			// Whose calendar this is. The page uses it to drop the controls that can only come back empty for
			// an assigned-scope member -- the team filter, the Unassigned lane, everyone else's lanes -- and
			// to call the page My Schedule, the way Jobber does for field crew.
			scope: assignedOnly ? ('assigned' as const) : ('all' as const),
			// True means this window holds more work than one read returns, so the calendar says so instead
			// of drawing a quietly incomplete day.
			truncated,
			limit: SCHEDULE_VISIT_LIMIT
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
