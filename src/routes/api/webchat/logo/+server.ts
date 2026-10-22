import type { RequestHandler } from './$types';
import { createHash } from 'node:crypto';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	getWebsiteChatPublicResolverClient,
	isWellFormedWidgetToken,
	resolveWebsiteChatLogoObjectKey
} from '$lib/server/communications/website-chat-public';
import { streamOrganizationLogo } from '$lib/server/settings/logo';

// Generous because a visitor's browser keeps the picture for a day; this only stops a crawler walking
// the token space through the image route instead of the config route.
const LOGO_IP_LIMIT = { windowSeconds: 60, maxAttempts: 60 };

// Every miss is the same bare 404, so this route never confirms whether a widget exists.
function missing() {
	return new Response(null, { status: 404, headers: { 'cache-control': 'no-store' } });
}

// The business logo inside the Website Chat widget on the contractor's own site. The widget falls back to
// the business's initials whenever this answers anything but a picture.
export const GET: RequestHandler = async ({ url, request, getClientAddress }) => {
	const token = url.searchParams.get('token') ?? undefined;
	if (!isWellFormedWidgetToken(token)) return missing();

	const limit = await checkRateLimit(getWebsiteChatPublicResolverClient(), {
		bucketKey: `website_chat_logo_ip:${createHash('sha256').update(getClientAddress(), 'utf8').digest('hex')}`,
		...LOGO_IP_LIMIT
	});
	if (!limit.allowed) return missing();

	const objectKey = await resolveWebsiteChatLogoObjectKey(token);
	if (!objectKey) return missing();

	const response = await streamOrganizationLogo(objectKey, request.headers.get('if-none-match'));
	// Drawn inside a stranger's page, so the picture must be loadable cross-origin.
	response.headers.set('cross-origin-resource-policy', 'cross-origin');
	return response;
};
