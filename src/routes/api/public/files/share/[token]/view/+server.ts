import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	fileShareIpBucketKey,
	fileShareTokenBucketKey,
	fileShareTokenHash,
	getFileShareResolverClient
} from '$lib/server/files/share-links';

// "The customer actually looked at it." Called by the customer's own browser once the shared files are on
// screen -- a page request proves nothing, since mail scanners and link previews fetch URLs first. It answers
// the same way whether it recorded anything or not, so a forged call cannot tell a live link from a dead one.
const VIEW_LIMIT = { windowSeconds: 60, maxAttempts: 30 };
const VIEW_TOKEN_LIMIT = { windowSeconds: 60, maxAttempts: 15 };

export const POST: RequestHandler = async (event) => {
	const noStore = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

	const tokenHash = fileShareTokenHash(event.params.token);
	if (!tokenHash) return json({ recorded: false }, { headers: noStore });

	const client = getFileShareResolverClient();
	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: fileShareIpBucketKey('view', event.getClientAddress()),
			...VIEW_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: fileShareTokenBucketKey('view', tokenHash),
			...VIEW_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byToken.allowed) return rateLimitedResponse(byToken.retryAfterSeconds);

	const { error } = await client.rpc('record_file_share_view', { supplied_token_hash: tokenHash });
	if (error) console.error('A file share view could not be recorded.', { code: error.code });

	return json({ recorded: true }, { headers: noStore });
};
