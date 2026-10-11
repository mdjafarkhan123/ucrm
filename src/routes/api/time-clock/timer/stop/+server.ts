import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized } from '$lib/server/api/errors';
import { refuseTimerCommandBody } from '$lib/server/time-clock/body';
import { timerError } from '$lib/server/time-clock/errors';

// Stopping the caller's own running timer. Membership is the only gate, as in `stop_my_timer`: a person whose
// permission was removed while their timer ran can still end it. A second Stop (another tap, another phone)
// is not an error — the command answers already_stopped and the hours stay recorded once. Stopping a visit
// timer that paused the day clock starts the day clock again.
export const POST: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	const refused = await refuseTimerCommandBody(event.request);
	if (refused) return refused;

	const { data, error } = await event.locals.supabase.rpc('stop_my_timer', {
		target_organization_id: auth.organization.id
	});
	if (error) return timerError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
