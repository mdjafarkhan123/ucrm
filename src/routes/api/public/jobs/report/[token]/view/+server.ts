import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	getJobReportAccessResolverClient,
	jobReportAccessIpBucketKey,
	jobReportAccessTokenBucketKey,
	jobReportAccessTokenHash
} from '$lib/server/jobs/report-access-links';

// "Somebody actually looked at it." Called by the customer's own browser once the report is on screen, which
// is the only moment that means what staff think it means -- a page request proves nothing, since mail
// scanners and chat link previews fetch a URL before any person sees it.
//
// It answers the same way whether it recorded anything or not. A forged call with a dead token must not be a
// way to find out that the token is dead.
const VIEW_LIMIT = { windowSeconds: 60, maxAttempts: 30 };
const VIEW_TOKEN_LIMIT = { windowSeconds: 60, maxAttempts: 15 };

export const POST: RequestHandler = async (event) => {
	const noStore = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

	const tokenHash = jobReportAccessTokenHash(event.params.token);
	if (!tokenHash) return json({ recorded: false }, { headers: noStore });

	const client = getJobReportAccessResolverClient();

	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: jobReportAccessIpBucketKey('view', event.getClientAddress()),
			...VIEW_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: jobReportAccessTokenBucketKey('view', tokenHash),
			...VIEW_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byToken.allowed) return rateLimitedResponse(byToken.retryAfterSeconds);

	const { error } = await client.rpc('record_job_report_link_view', {
		supplied_token_hash: tokenHash
	});

	// Nothing the customer can do about it and nothing they need to know: their report is already on the
	// screen in front of them. Logged without the token.
	if (error) console.error('A work report view could not be recorded.', { code: error.code });

	return json({ recorded: true }, { headers: noStore });
};
