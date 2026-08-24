import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { archiveQuoteSchema } from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';

// Filing a quote away. Never a delete: the number it owns is allocated for good, and a converted quote
// cannot be archived at all. Archiving something already archived is not an error, it is the same answer.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	let body: unknown = {};
	try {
		const text = await event.request.text();
		if (text.trim().length > 0) body = JSON.parse(text);
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = archiveQuoteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('archive_quote', {
		target_quote_id: event.params.id,
		reason: parsed.data.reason
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
