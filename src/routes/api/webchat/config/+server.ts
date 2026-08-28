import type { RequestHandler } from './$types';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	getWebsiteChatPublicResolverClient,
	isWellFormedWidgetToken,
	readCachedWebsiteChatWidgetPublicConfig,
	resolveWebsiteChatWidgetPublicConfig,
	websiteChatConfigIpBucketKey,
	websiteChatConfigTokenBucketKey,
	type WebsiteChatWidgetPublicConfig
} from '$lib/server/communications/website-chat-public';

// One call per visit to a contractor's site, so limits stay generous compared to the Quote link's
// per-action limits -- this is a config read, not a write, but still capped so a scripted crawler
// cannot walk every token in the URL space or hammer one widget.
const CONFIG_IP_LIMIT = { windowSeconds: 60, maxAttempts: 30 };
const CONFIG_TOKEN_LIMIT = { windowSeconds: 60, maxAttempts: 60 };

// The browser sets `Origin` itself on a cross-origin fetch and page script cannot forge it, so it
// replaces the iframe shell's `frame-ancestors` header as the security boundary: the allowlist is
// enforced inside `get_website_chat_widget_public_config`, and the response is only made readable
// to an origin that passed it.
//
// Every refusal is the same silent, unreadable answer -- no CORS header, so the calling page's JS
// cannot read the body or the status either way. A bad token, a stranger's domain, a disabled
// widget and a rate-limited visitor are indistinguishable from the host page, which is WC0.3's
// "never confirm or deny a widget exists" rule carried over intact.
function refuse() {
	return new Response(null, {
		status: 204,
		headers: { 'cache-control': 'no-store', vary: 'Origin' }
	});
}

// `no-store`, deliberately: a shared cache must never hand one site's widget configuration to
// another origin, and a disable or suspension has to reach a returning visitor on their next page
// view. The 30-second server-side cache behind this endpoint is where the traffic is absorbed.
function allow(config: WebsiteChatWidgetPublicConfig, requestOrigin: string) {
	return new Response(JSON.stringify({ config }), {
		status: 200,
		headers: {
			'content-type': 'application/json',
			'cache-control': 'no-store',
			// Echoed, never `*`: only the origin that just passed the allowlist may read this.
			'access-control-allow-origin': requestOrigin,
			vary: 'Origin'
		}
	});
}

export const GET: RequestHandler = async ({ url, request, getClientAddress }) => {
	const token = url.searchParams.get('token') ?? undefined;
	const requestOrigin = request.headers.get('origin') ?? '';

	// A token that is not even the right shape, or a same-origin call with no `Origin` header at
	// all, never reaches the database.
	if (!isWellFormedWidgetToken(token) || !requestOrigin) return refuse();

	// A cache hit costs no database work at all, so it skips the rate-limit upserts too -- those
	// exist to protect the database, and a hit never reaches it. Probing still gets limited: a
	// crawler walking the token space never hits, because only allowed pairs are ever cached.
	const cached = readCachedWebsiteChatWidgetPublicConfig(token, requestOrigin);
	if (cached) return allow(cached, requestOrigin);

	const client = getWebsiteChatPublicResolverClient();
	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: websiteChatConfigIpBucketKey(getClientAddress()),
			...CONFIG_IP_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: websiteChatConfigTokenBucketKey(token),
			...CONFIG_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed || !byToken.allowed) return refuse();

	const config = await resolveWebsiteChatWidgetPublicConfig(token, requestOrigin);
	if (!config) return refuse();

	return allow(config, requestOrigin);
};
