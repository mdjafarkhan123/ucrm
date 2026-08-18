import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { PRIVATE_READ_HEADERS, databaseError, unauthorized } from '$lib/server/api/errors';
import {
	DISPLAY_REQUEST_STATUSES,
	organizationDayRange,
	type DisplayRequestStatus
} from '$lib/server/requests/status';
import { organizationTimezone } from '$lib/server/requests/timezone';

// The Overview card on the Requests list. Counted on demand rather than kept in a materialized view —
// Jafar's call 2026-08-18 — so the numbers are never stale, and the card can move to a pre-computed
// source later without the page knowing. One round trip: the database groups, this route only fills in
// the statuses that had no rows so the card can draw a zero instead of a gap.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;

	// Where today starts and ends for this contractor. Worked out here, in the one place that owns the
	// calendar rule, and handed to the database as two plain instants.
	const timezone = await organizationTimezone(supabase, organizationId);
	const { day_start, day_end } = organizationDayRange(timezone);

	const { data, error } = await supabase.rpc('request_status_counts', {
		target_organization_id: organizationId,
		day_start,
		day_end
	});
	if (error) return databaseError();

	const counts = Object.fromEntries(
		DISPLAY_REQUEST_STATUSES.map((status) => [status, 0])
	) as Record<DisplayRequestStatus, number>;
	for (const row of data ?? []) {
		if (row.display_status in counts) {
			counts[row.display_status as DisplayRequestStatus] = Number(row.total);
		}
	}

	return json({ counts }, { headers: PRIVATE_READ_HEADERS });
};
