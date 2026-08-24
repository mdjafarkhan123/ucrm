import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { convertRequestToQuoteSchema } from '$lib/server/validation/quotes.schema';
import { convertRequestError } from '$lib/server/quotes/errors';

// Turning a request into a quote: one quote number, one draft version, a copy of every priced line, the
// open tasks moved across, and the request marked converted — all inside `convert_request_to_quote`, so a
// failure anywhere leaves nothing half-done.
//
// The permission is checked by the write function itself (`quotes.create`), not here, because it also has
// to answer the same way for a request belonging to another organization. A doubled click sends the same
// idempotency key and gets the first quote back with `applied: false`.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = convertRequestToQuoteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('convert_request_to_quote', {
		target_request_id: event.params.id,
		idempotency_key: parsed.data.idempotency_key,
		request_hash: parsed.data.request_hash
	});

	if (error) return convertRequestError(error);

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
