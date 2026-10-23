import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { loadMessengerOverview } from '$lib/server/communications/messenger-connections';

/** Settings → Messenger: the business's connected Facebook Pages and how each is doing. */
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	try {
		return json(await loadMessengerOverview(check.auth.organization.id), {
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not load Messenger connections.', error);
		return json(
			{ error: 'Your Facebook Pages could not be loaded.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
