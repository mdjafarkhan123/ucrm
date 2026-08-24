import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { publishQuoteSchema } from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';

// Putting the quote in front of the customer. The draft is frozen into the next version and the quote
// starts waiting for an answer. Clicking twice is not two proposals: the command sees the revision it was
// asked to publish is already published and hands back that same version.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.send');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = publishQuoteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('publish_quote', {
		target_quote_id: event.params.id,
		expected_revision: parsed.data.expected_revision
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
