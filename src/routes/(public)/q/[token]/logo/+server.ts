import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	getQuoteAccessResolverClient,
	quoteAccessTokenHash
} from '$lib/server/quotes/access-links';
import { streamOrganizationLogo } from '$lib/server/settings/logo';

// The logo frozen onto this token's own published version -- never the organization's current one. A
// contractor who replaces their logo after sending must not repaint a document already in front of a
// customer. The object key itself never reaches the browser: this route resolves the token itself, the
// same way every other public quote command does, and streams the bytes straight through.
export const GET: RequestHandler = async (event) => {
	const tokenHash = quoteAccessTokenHash(event.params.token);
	if (!tokenHash) throw httpError(404, 'No logo is available for this quote.');

	const supabase = getQuoteAccessResolverClient();
	const { data: objectKey, error } = await supabase.rpc('resolve_quote_access_link_logo', {
		supplied_token_hash: tokenHash
	});
	if (error || !objectKey) throw httpError(404, 'No logo is available for this quote.');

	return streamOrganizationLogo(objectKey, event.request.headers.get('if-none-match'));
};
