import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { recordQuoteDepositEventSchema } from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';

// Money that changed hands off the app. This binds to whichever version is currently published — there is
// no partial or cumulative recording this campaign, so it either lands the one live receipt or, on a
// retried idempotency key, hands back the first result untouched.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.record_deposit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = recordQuoteDepositEventSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('record_quote_deposit_event', {
		target_quote_id: event.params.id as string,
		idempotency_key: parsed.data.idempotency_key,
		method: parsed.data.method,
		reference: parsed.data.reference,
		note: parsed.data.note
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
