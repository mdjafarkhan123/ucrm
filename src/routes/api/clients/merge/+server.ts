import { json } from '@sveltejs/kit';
import type { PostgrestError } from '@supabase/supabase-js';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { clientMergeSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Merging follows Jobber: the primary client survives, everything the secondary had moves onto it, and the
// secondary is deleted. The database owns the whole rule (client_merge_preview / merge_clients), so the
// preview the office reads and the merge that runs can never disagree.

function mergeFailure(error: PostgrestError) {
	if (error.code === 'P0002')
		return json({ error: 'That client could not be found.' }, { status: 404 });
	if (error.code === '42501') return json({ error: error.message }, { status: 403 });
	// A blocker the plan found, such as a card payment still settling. The message says what to wait for.
	if (error.code === '23514') return json({ error: error.message }, { status: 409 });
	if (error.code === '22023') return validationError({ secondary_client_id: error.message });
	return databaseError();
}

// What merging would move and change, for the confirmation screen.
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.merge');
	if ('response' in access) return access.response;

	const parsed = clientMergeSchema.safeParse({
		primary_client_id: event.url.searchParams.get('primary') ?? '',
		secondary_client_id: event.url.searchParams.get('secondary') ?? ''
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('client_merge_preview', {
		p_primary_client_id: parsed.data.primary_client_id,
		p_secondary_client_id: parsed.data.secondary_client_id
	});
	if (error) return mergeFailure(error);
	// Work and payments can land at any moment, so the answer is never worth keeping in a shared cache.
	return json({ preview: data }, { headers: NO_STORE_HEADERS });
};

export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.merge');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = clientMergeSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('merge_clients', {
		p_primary_client_id: parsed.data.primary_client_id,
		p_secondary_client_id: parsed.data.secondary_client_id
	});
	if (error) return mergeFailure(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
