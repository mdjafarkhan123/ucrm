import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { deletionFailure } from '$lib/server/clients/deletion';

// The Recently Deleted page: every client still inside their 30 days, soonest permanent delete first.
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.delete');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase.rpc('recently_deleted_clients');
	if (error) return deletionFailure(error);
	return json({ clients: data ?? [] }, { headers: PRIVATE_READ_HEADERS });
};
