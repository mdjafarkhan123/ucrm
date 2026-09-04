import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	scheduleRouteOrderQuerySchema,
	scheduleRouteOrderWriteSchema
} from '$lib/server/validation/schedule.schema';

// One employee's saved stop order for one day on the contextual Map.
//
// Reading it is part of showing the calendar, so it needs the same jobs.view the window read does. Saving it
// is a calendar-change decision, so it needs jobs.schedule -- the same authority a visit move or a Schedule
// Event requires. The saved order is a dispatch preference (a list of stop ids), never an appointment-time
// change; the front end re-settles the fixed-time anchors itself, so this route only stores and returns the
// list as given.

// Load the saved order for an (employee, day). Absent is normal -- most routes have never been hand-ordered --
// so a missing row is an empty order, not an error.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const parsed = scheduleRouteOrderQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('schedule_route_orders')
		.select('stop_order')
		.eq('organization_id', check.auth.organization.id)
		.eq('employee_id', parsed.data.employee)
		.eq('route_date', parsed.data.date)
		.maybeSingle();

	if (error) return databaseError();

	return json({ order: data?.stop_order ?? [] }, { headers: PRIVATE_READ_HEADERS });
};

// Save (upsert) the order for an (employee, day). One row owns each (organization, employee, day), so this
// replaces that route's order in place. The (organization_id, employee_id) foreign key means an employee who
// is not a member of this tenant is rejected by the database rather than silently stored.
export const PUT: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.schedule');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = scheduleRouteOrderWriteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('schedule_route_orders')
		.upsert(
			{
				organization_id: check.auth.organization.id,
				employee_id: parsed.data.employee_id,
				route_date: parsed.data.route_date,
				stop_order: parsed.data.order
			},
			{ onConflict: 'organization_id,employee_id,route_date' }
		)
		.select('stop_order')
		.single();

	if (error) return databaseError();

	return json({ order: data.stop_order }, { headers: NO_STORE_HEADERS });
};
