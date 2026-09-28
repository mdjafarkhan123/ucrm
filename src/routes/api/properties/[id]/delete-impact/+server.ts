import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, NO_STORE_HEADERS } from '$lib/server/api/errors';

// What deleting this property would take with it, and what stops it, for the confirmation. The same database
// plan runs the delete, so this can never promise something the delete then refuses.
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'property.manage');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase.rpc('property_delete_impact', {
		p_property_id: event.params.id
	});

	if (error?.code === 'P0002')
		return json({ error: 'That address could not be found.' }, { status: 404 });
	if (error?.code === '42501') return json({ error: error.message }, { status: 403 });
	if (error) return databaseError();
	// Work can be added or sent at any moment, so the answer is never worth keeping in any shared cache.
	return json({ impact: data }, { headers: NO_STORE_HEADERS });
};
