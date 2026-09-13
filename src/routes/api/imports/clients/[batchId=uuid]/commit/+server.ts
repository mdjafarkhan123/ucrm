import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { importClientsCommitSchema } from '$lib/server/validation/imports.schema';

// Step 5a of the client import: the "Commit" button. The office has reviewed the dry-run (step 4); this
// confirms it. The RPC settles skip/hold/error rows, queues create/update rows as 'ready' for the step-5b
// worker, and stamps the consent affirmation -- nothing is written to `clients` here directly; the worker
// drains the queued rows. The [batchId=uuid] matcher rejects a non-uuid path with a 404 before we run.
export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.create');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Send the confirmation as JSON.' });
	}

	const parsed = importClientsCommitSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data: batch, error } = await event.locals.supabase.rpc('commit_import_batch', {
		payload: {
			batch_id: event.params.batchId,
			consent_affirmed: parsed.data.consent_affirmed
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
		// The consent backstop (should never fire past the Zod gate above), surfaced on its own field.
		if (error.code === '23514') {
			return validationError({
				consent_affirmed: 'Confirm these contacts agreed to hear from you before importing.'
			});
		}
		if (error.code === '22023') {
			return validationError({ form: 'This import can no longer be committed.' });
		}
		return databaseError();
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
