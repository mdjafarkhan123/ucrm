import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { quoteWriteError } from '$lib/server/quotes/errors';

// Bringing an archived quote back to where it was. A quote whose old state cannot be trusted comes back
// as a draft — something nobody has been told about yet — never as approved or awaiting an answer.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('restore_quote', {
		target_quote_id: event.params.id
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
