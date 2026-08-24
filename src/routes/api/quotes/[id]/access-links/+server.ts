import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { issueQuoteAccessLinkSchema } from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';
import { createQuoteAccessToken, quoteAccessLinkUrl } from '$lib/server/quotes/access-links';

// The links a staff member is allowed to know about. The table itself is closed to members because every
// row holds a token hash, so this reads through the function that cannot return that column.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('quote_access_link_state', {
		target_quote_id: event.params.id
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};

// Making the customer's door. The token is generated here, in Node, and the database is handed only its
// SHA-256 — so the raw link exists exactly once, in this response, on its way to the person who asked
// for it. It is never stored, never logged, and cannot be read back from any route afterwards.
//
// Asking twice does not leave two working doors: the write function revokes this recipient's older
// links in the same transaction.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.send');
	if ('response' in check) return check.response;

	let body: unknown = {};
	const raw = await event.request.text();
	if (raw.trim().length > 0) {
		try {
			body = JSON.parse(raw);
		} catch {
			return validationError({ form: 'Request body must be valid JSON.' });
		}
	}

	const parsed = issueQuoteAccessLinkSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { token, tokenHash } = createQuoteAccessToken();

	const { data, error } = await event.locals.supabase.rpc('issue_quote_access_link', {
		target_quote_id: event.params.id,
		supplied_token_hash: tokenHash
	});

	if (error) return quoteWriteError(error);
	return json(
		{ ...(data as Record<string, unknown>), url: quoteAccessLinkUrl(event.url.origin, token) },
		{ headers: NO_STORE_HEADERS }
	);
};
