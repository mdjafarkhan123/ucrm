import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { generateImportErrorFile } from '$lib/server/imports/error-file';

// Step 4a of the opening-balances import: the "Import" button. The office has reviewed the dry-run (step 3);
// this confirms it. No consent gate -- unlike the client importer, an opening balance never contacts a
// customer, so HubSpot's affirmation does not apply. The RPC settles hold/error rows and queues create/update
// rows as 'ready' for the shared step-4b worker; nothing is written to client_opening_balances here directly.
export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in access) return access.response;

	const { data: batch, error } = await event.locals.supabase.rpc(
		'commit_opening_balance_import_batch',
		{ payload: { batch_id: event.params.batchId } }
	);

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
			return validationError({ form: 'This import can no longer be committed.' });
		}
		return databaseError();
	}

	// A batch with nothing to import (every row held/errored) is 'completed' the instant it commits, so the
	// worker never runs for it -- yet its held/error rows are exactly what the office needs the error file for.
	// Generate it here, best-effort: the write already succeeded in its own transaction, so an R2 hiccup must
	// never fail the commit. (When status is 'importing', the worker owns the error file instead.)
	if (batch.status === 'completed') {
		try {
			await generateImportErrorFile({ organizationId: batch.organization_id, batchId: batch.id });
		} catch (fileError) {
			console.error('Opening-balance import error file generation failed after commit', fileError);
		}
	}

	return json(
		{
			batch_id: batch.id,
			status: batch.status,
			counts: {
				created: batch.created_count,
				updated: batch.updated_count,
				skipped: batch.skipped_count,
				held: batch.held_count,
				error: batch.error_count
			}
		},
		{ status: 200, headers: NO_STORE_HEADERS }
	);
};
