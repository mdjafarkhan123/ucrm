import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { importClientsMappingSchema } from '$lib/server/validation/imports.schema';

// Step 3 of the client import: save the column mapping + match action chosen on the "Map columns" screen and
// move the batch uploaded -> mapped. Nothing is imported here -- the per-row dedupe dry-run is step 4, which
// re-reads the file from R2. The [batchId=uuid] matcher rejects a non-uuid path with a 404 before we run.
export const PATCH: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.create');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Send the mapping as JSON.' });
	}

	const parsed = importClientsMappingSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data: batch, error } = await event.locals.supabase.rpc('set_import_batch_mapping', {
		payload: {
			batch_id: event.params.batchId,
			column_mapping: parsed.data.column_mapping,
			match_action: parsed.data.match_action
		}
	});

	if (error) {
		// The RPC raises these on purpose; everything else is a real failure.
		if (error.code === 'P0002') return notFound('That import was not found.');
		if (error.code === '42501') {
			return json(
				{ error: 'You do not have permission to change this import.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		if (error.code === '22023') {
			return validationError({ form: 'This import can no longer be changed.' });
		}
		return databaseError();
	}

	return json(
		{ batch_id: batch.id, status: batch.status },
		{ status: 200, headers: NO_STORE_HEADERS }
	);
};
