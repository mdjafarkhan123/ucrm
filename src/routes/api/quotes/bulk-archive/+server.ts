import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { bulkArchiveQuotesSchema } from '$lib/server/validation/quotes.schema';

// A selection, not a single row: this calls the same archive_quote every single-quote Archive already
// calls, once per id, so a converted quote or one still needing a reason skips without failing the rest of
// the batch. No new SQL - a selection this size is a UI concern, not a bulk-statement one.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = bulkArchiveQuotesSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// A batch this size is worth a handful of round trips, not one connection per row and not one held
	// after another. Ten at a time keeps the pool contribution bounded regardless of selection size.
	const CONCURRENCY = 10;
	let archived = 0;
	let skipped = 0;
	const ids = parsed.data.ids;
	for (let start = 0; start < ids.length; start += CONCURRENCY) {
		const batch = ids.slice(start, start + CONCURRENCY);
		const results = await Promise.all(
			batch.map((id) =>
				event.locals.supabase.rpc('archive_quote', { target_quote_id: id, reason: null })
			)
		);
		for (const { data, error } of results) {
			if (error || !data?.applied) {
				skipped += 1;
				continue;
			}
			archived += 1;
		}
	}

	return json({ archived, skipped }, { headers: NO_STORE_HEADERS });
};
