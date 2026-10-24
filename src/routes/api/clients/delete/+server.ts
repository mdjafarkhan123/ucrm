import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { deletionFailure } from '$lib/server/clients/deletion';
import { clientDeleteSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

// What the Delete client pop-up shows: for each picked client the counts that go, what stays and anything that
// stops the delete (open money), plus totals for many. GET /api/clients/delete?ids=a,b
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.delete');
	if ('response' in access) return access.response;

	const ids = (event.url.searchParams.get('ids') ?? '').split(',').filter(Boolean);
	const parsed = clientDeleteSchema.safeParse({ client_ids: ids });
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('client_delete_preview', {
		target_client_ids: parsed.data.client_ids
	});
	if (error) return deletionFailure(error);
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

// Moves clients to Recently Deleted for 30 days. A client with open money is left out and named.
export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.delete');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = clientDeleteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('delete_clients', {
		target_client_ids: parsed.data.client_ids
	});
	if (error) return deletionFailure(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
