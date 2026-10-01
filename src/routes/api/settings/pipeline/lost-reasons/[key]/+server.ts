import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { lostReasonWriteError } from '$lib/server/pipeline/lost-reasons';
import { setLostReasonRetiredSchema } from '$lib/server/validation/pipeline.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const RETIRE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Retires a lost reason, or brings a retired one back. Retiring only stops it being offered: every record
// that already carries it keeps it. Asking for the state it is already in changes nothing.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	if (!/^[a-z0-9_]{2,64}$/.test(event.params.key))
		return notFound('That reason could not be found.');

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-pipeline-save:${organizationId}`,
			...RETIRE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setLostReasonRetiredSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_set_lost_reason_retired', {
		target_organization_id: organizationId,
		target_key: event.params.key,
		retired: parsed.data.retired
	});
	if (error) return lostReasonWriteError(error);

	return json({ reason: data }, { headers: NO_STORE_HEADERS });
};
