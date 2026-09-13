import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { importClientsMappingSchema } from '$lib/server/validation/imports.schema';

// The Done screen polls this after commit: client creation runs in a background worker, so the page needs to
// read the batch's status and running tallies until it settles on 'completed' (or 'failed'). Scoped to the
// caller's active org under RLS so it can only ever read its own import.
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.create');
	if ('response' in access) return access.response;

	const { data: batch, error } = await event.locals.supabase
		.from('import_batches')
		.select(
			'id, source_filename, file_row_count, status, created_count, updated_count, skipped_count, held_count, error_count, error_file_object_key'
		)
		.eq('id', event.params.batchId)
		.eq('organization_id', access.auth.organization.id)
		.maybeSingle();
	if (error) return databaseError();
	if (!batch) return notFound('That import was not found.');

	return json(
		{
			batch_id: batch.id,
			source_filename: batch.source_filename,
			row_count: batch.file_row_count,
			status: batch.status,
			counts: {
				created: batch.created_count,
				updated: batch.updated_count,
				skipped: batch.skipped_count,
				held: batch.held_count,
				error: batch.error_count
			},
			has_error_file: Boolean(batch.error_file_object_key)
		},
		{ status: 200, headers: NO_STORE_HEADERS }
	);
};

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
