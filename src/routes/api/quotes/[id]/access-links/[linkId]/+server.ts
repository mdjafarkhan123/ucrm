import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, notFound } from '$lib/server/api/errors';
import { quoteWriteError } from '$lib/server/quotes/errors';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Turning a link off. Clicking twice is the same click arriving twice: the write function finds it
// already revoked and hands back the same answer instead of an error.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.send');
	if ('response' in check) return check.response;

	const linkId = event.params.linkId;
	// A link from another organization and a link that never existed are the same answer, so a malformed
	// id gets that same answer rather than a database error that says the id was at least examined.
	if (!UUID.test(linkId)) return notFound('That customer link could not be found.');

	const { data, error } = await event.locals.supabase.rpc('revoke_quote_access_link', {
		target_link_id: linkId
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
