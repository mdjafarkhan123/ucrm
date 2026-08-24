import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { recordQuoteDecisionSchema } from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';

// "They rang and said yes." Recording an answer the customer gave off the app. If the quote is still a
// draft the command publishes it first, because an answer with no sent document behind it would be a
// decision about nothing. Recording the same answer twice is the same answer, not a second one.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.record_decision');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = recordQuoteDecisionSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('record_quote_decision', {
		target_quote_id: event.params.id,
		new_decision: parsed.data.decision,
		decision_note: parsed.data.note,
		expected_revision: parsed.data.expected_revision ?? null
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
