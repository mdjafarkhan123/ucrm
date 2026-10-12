import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOrganizationContext } from '$lib/server/auth/organization';
import {
	NO_STORE_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	startAssessmentTimerSchema,
	startVisitTimerSchema
} from '$lib/server/validation/time-clock.schema';
import { timerError } from '$lib/server/time-clock/errors';

// The signed-in person's own running timer, whether they may run one, and the server's clock to count it
// from. Membership is the only gate: `my_running_timer` only ever returns the caller's own row, and someone
// who lost their timer permission mid-shift still needs to see the timer they have to stop.
export const GET: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	const { data, error } = await event.locals.supabase.rpc('my_running_timer', {
		target_organization_id: auth.organization.id
	});
	if (error) return databaseError();

	// A running timer changes by the second and is the person's own, so it is never cached.
	return json(data, { headers: NO_STORE_HEADERS });
};

// Starting the caller's own timer on a visit, or on an Assessment when the body names one. jobs.view is the
// route gate; whether they may time it, and whether the job and visit are still open or the Assessment is
// today's, is decided by `start_visit_timer` and `start_assessment_timer`.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	if (body !== null && typeof body === 'object' && 'assessment_id' in body) {
		const assessment = startAssessmentTimerSchema.safeParse(body);
		if (!assessment.success) return validationError(zodFieldErrors(assessment.error));

		const { data, error } = await event.locals.supabase.rpc('start_assessment_timer', {
			target_organization_id: check.auth.organization.id,
			target_assessment_id: assessment.data.assessment_id
		});
		if (error) return timerError(error, 'That assessment could not be found.');

		return json(data, { headers: NO_STORE_HEADERS });
	}

	const parsed = startVisitTimerSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('start_visit_timer', {
		target_organization_id: check.auth.organization.id,
		target_job_id: parsed.data.job_id,
		target_visit_id: parsed.data.visit_id
	});
	if (error) return timerError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
