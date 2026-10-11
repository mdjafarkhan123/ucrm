import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized } from '$lib/server/api/errors';
import { refuseTimerCommandBody } from '$lib/server/time-clock/body';
import { timerError } from '$lib/server/time-clock/errors';

// Clocking the caller in for the day (plan § Timers). Whether they may run a timer at all is decided by
// `clock_in` through the same check as a visit's Start. Clocking in twice is not an error, and clocking in
// while a visit timer runs starts the day clock when that timer stops.
export const POST: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	const refused = await refuseTimerCommandBody(event.request);
	if (refused) return refused;

	const { data, error } = await event.locals.supabase.rpc('clock_in', {
		target_organization_id: auth.organization.id
	});
	if (error?.code === '42501')
		return json(
			{ error: 'You do not have access to clock in.', reason: 'forbidden' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	if (error) return timerError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
