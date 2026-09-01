import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { convertQuoteToJobSchema } from '$lib/server/validation/quotes.schema';
import { convertQuoteToJobError } from '$lib/server/quotes/errors';

// Turning an approved quote into a job: one job number, a copy of the scope the customer actually agreed
// to, the quote made terminally converted, and both histories written — all inside `convert_quote_to_job`,
// so a failure anywhere leaves nothing half-done.
//
// The permissions are checked by the write function itself (`quotes.convert` and `jobs.create`), not here,
// because it also has to answer the same way for a quote belonging to another organization. A doubled
// click sends the same idempotency key and gets the first job back with `applied: false`.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = convertQuoteToJobSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('convert_quote_to_job', {
		target_quote_id: event.params.id,
		idempotency_key: parsed.data.idempotency_key,
		request_hash: parsed.data.quote_hash,
		new_job_type: parsed.data.job_type,
		new_price_basis: parsed.data.price_basis ?? null,
		new_title: parsed.data.title ?? null,
		new_billing_timing: parsed.data.billing_timing,
		new_is_as_needed: parsed.data.is_as_needed,
		new_instructions: parsed.data.instructions ?? null
	});

	if (error) return convertQuoteToJobError(error);

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
