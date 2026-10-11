import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { stopTimerSchema } from '$lib/server/validation/time-clock.schema';
import { timerError } from '$lib/server/time-clock/errors';

// Stopping the caller's own running timer. Membership is the only gate, as in `stop_my_timer`: a person whose
// permission was removed while their timer ran can still end it. A second Stop (another tap, another phone)
// is not an error — the command answers already_stopped and the hours stay recorded once.
export const POST: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	let body: unknown = {};
	const text = await event.request.text();
	if (text.trim()) {
		try {
			body = JSON.parse(text);
		} catch {
			return validationError({ form: 'Request body must be valid JSON.' });
		}
	}

	const parsed = stopTimerSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('stop_my_timer', {
		target_organization_id: auth.organization.id
	});
	if (error) return timerError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
