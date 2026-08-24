import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { quoteWriteError } from '$lib/server/quotes/errors';

// Starting a new version of a quote the customer already has. The published document is never edited: it
// is copied into a fresh draft, and any answer that belonged to it stops being the current one. No body -
// the quote itself knows which version it is cloning.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('revise_quote', {
		target_quote_id: event.params.id
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
