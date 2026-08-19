import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { reopenOpportunitySchema } from '$lib/server/validation/pipeline.schema';
import { outcomeWriteError } from '$lib/server/pipeline/outcomes';

// Restores a Lost card: the Request returns to its prior open status and only the Tasks that Lost
// auto-completed reopen with it, inside `pipeline_reopen_opportunity`. No UI calls this route in 4B — its
// only entry point is a Lost row in 4C's Sales Outcomes page — but it exists and is tested now so that
// page has a real action to call rather than a placeholder.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = reopenOpportunitySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_reopen_opportunity', {
		target_opportunity_id: event.params.id,
		idempotency_key: parsed.data.idempotency_key,
		reopen_explanation: parsed.data.reopen_explanation
	});

	if (error) return outcomeWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
