import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { lostReasonWriteError } from '$lib/server/pipeline/lost-reasons';
import { addLostReasonSchema } from '$lib/server/validation/pipeline.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const ADD_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Settings → Pipeline → Lost reasons: adds a reason. It is offered straight away; it is not part of the
// page's Save, the same as removing a stage is not.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-pipeline-save:${organizationId}`,
			...ADD_LIMIT
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

	const parsed = addLostReasonSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_add_lost_reason', {
		target_organization_id: organizationId,
		new_label: parsed.data.label
	});
	if (error) return lostReasonWriteError(error);

	return json({ reason: data }, { status: 201, headers: NO_STORE_HEADERS });
};
