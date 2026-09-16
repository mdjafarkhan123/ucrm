import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { importOpeningBalancesMappingSchema } from '$lib/server/validation/imports.schema';

// The Done screen polls this after commit: the opening-balance facts are written by the shared background
// worker, so the page needs to read the batch's status and running tallies until it settles. Scoped to the
// caller's active org under RLS so it can only ever read its own import.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in access) return access.response;

	const { data: batch, error } = await event.locals.supabase
		.from('import_batches')
		.select(
			'id, source_filename, file_row_count, status, created_count, updated_count, skipped_count, held_count, error_count, error_file_object_key'
		)
		.eq('id', event.params.batchId)
		.eq('organization_id', access.auth.organization.id)
		.eq('entity_type', 'opening_balance')
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

// Step 2 of the opening-balances import: save the column mapping chosen on the "Map columns" screen and move
// the batch uploaded -> mapped. Nothing is imported here -- the per-row dry-run is step 3.
export const PATCH: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Send the mapping as JSON.' });
	}

	const parsed = importOpeningBalancesMappingSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data: batch, error } = await event.locals.supabase.rpc('set_import_batch_mapping', {
		payload: {
			batch_id: event.params.batchId,
			column_mapping: parsed.data.column_mapping
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
