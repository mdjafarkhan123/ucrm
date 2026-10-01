import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setLostReasonSchema } from '$lib/server/validation/pipeline.schema';
import { outcomeWriteError } from '$lib/server/pipeline/outcomes';

// Sets or clears the reason on a record that is already Lost. A customer's decline arrives with their own
// words and no reason, so this is where the team classifies it; a reason skipped at "Mark as lost" can be
// filled in the same way. Saving the same answer twice changes nothing, so it needs no idempotency key.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setLostReasonSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_set_lost_reason', {
		target_opportunity_id: event.params.id,
		reason: parsed.data.reason ?? undefined,
		note: parsed.data.note ?? undefined
	});

	if (error) return outcomeWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
