import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { quoteWriteError } from '$lib/server/quotes/errors';

// A brand-new quote that starts full: same client, property, lines, and document sections, none of the
// source quote's request, version, or decision history. No body - the quote itself knows what to copy.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('create_similar_quote', {
		target_quote_id: event.params.id
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
