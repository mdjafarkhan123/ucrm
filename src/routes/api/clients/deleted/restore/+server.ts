import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { deletionFailure } from '$lib/server/clients/deletion';
import { clientRestoreSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Restores clients from Recently Deleted. With mode "check" a client whose phone or email a newer client now
// holds comes back as a match for the pop-up instead; "separate" and "merge" are the pop-up's two answers.
export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.delete');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = clientRestoreSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('restore_client_deletions', {
		target_deletion_ids: parsed.data.deletion_ids,
		restore_mode: parsed.data.mode
	});
	if (error) return deletionFailure(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
