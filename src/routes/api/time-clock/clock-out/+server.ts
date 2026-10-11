import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized } from '$lib/server/api/errors';
import { refuseTimerCommandBody } from '$lib/server/time-clock/body';
import { timerError } from '$lib/server/time-clock/errors';

// Ending the caller's working day (plan § Timers): whatever timer runs stops — the day clock or a visit
// timer — and nothing resumes. Membership is the only gate, as for Stop. A second Clock out answers
// already_stopped; a timer over 24 hours is refused for a manager to correct.
export const POST: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	const refused = await refuseTimerCommandBody(event.request);
	if (refused) return refused;

	const { data, error } = await event.locals.supabase.rpc('clock_out', {
		target_organization_id: auth.organization.id
	});
	if (error) return timerError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
