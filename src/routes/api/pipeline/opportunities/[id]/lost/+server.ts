import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { markOpportunityLostSchema } from '$lib/server/validation/pipeline.schema';
import { outcomeWriteError } from '$lib/server/pipeline/outcomes';

// Closes the card: archives its Request and completes its open Tasks, atomically, inside
// `pipeline_mark_opportunity_lost`. Same-key retries return the first result untouched rather than
// erroring, so a doubled click or a retried request after a dropped response costs nothing.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = markOpportunityLostSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_mark_opportunity_lost', {
		target_opportunity_id: event.params.id,
		idempotency_key: parsed.data.idempotency_key,
		reason: parsed.data.reason,
		note: parsed.data.note
	});

	if (error) return outcomeWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
