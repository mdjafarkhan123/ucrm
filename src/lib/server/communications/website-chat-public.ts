import { createHash, createHmac, randomUUID } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getServerEnv } from '$lib/server/env';
import { checkRateLimit } from '$lib/server/security/rate-limit';

// The public embed page has no signed-in user, so it cannot use its own request's client -- `anon`
// has no grant on the resolver function. It runs as the service role, matching the public Quote
// view's `getQuoteAccessResolverClient` pattern. Made once per process.
let resolverClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getWebsiteChatPublicResolverClient() {
	resolverClient ??= getOwnerSupabaseClient();
	return resolverClient;
}

// public_token is widget identity, not a secret (WC0.3) -- it is fine to key rate-limit buckets on
// it directly, unlike the Quote access token which is hashed because it is itself a bearer secret.
export function websiteChatConfigIpBucketKey(ipAddress: string) {
	return `website_chat_config_ip:${createHash('sha256').update(ipAddress, 'utf8').digest('hex')}`;
}

export function websiteChatConfigTokenBucketKey(publicToken: string) {
	return `website_chat_config_token:${publicToken}`;
}

export type WebsiteChatWidgetPublicConfig = {
	widgetId: string;
	organizationId: string;
	businessName: string;
	brandColor: string | null;
	launcherPosition: 'bottom_left' | 'bottom_right';
	teaserText: string | null;
	greetingText: string | null;
	// Which identifiers the identity form insists on (WC2 setting, first read publicly in WC4.3).
	contactRequirement: 'phone' | 'email' | 'either';
	privacyPolicyUrl: string | null;
	status: 'live' | 'draft' | 'disabled' | 'suspended' | 'not_entitled';
};

const TOKEN_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// A token that is not even the right shape never reaches the database -- matches the Quote link's
// "wrong shape gets answered without spending a query" rule.
export function isWellFormedWidgetToken(token: string | undefined): token is string {
	return !!token && TOKEN_PATTERN.test(token);
}

// This is the single widest-traffic read we own: every page view on every contractor's website
// calls it, and it costs three database round trips -- two of them rate-limit *upserts*, one of
// which is keyed on the widget token, so without a cache every visitor of the same busy site
// serializes on one row.
//
// The answer is tenant-global, not per-visitor, so it is exactly what the server-cache rule is
// for. Thirty seconds is short enough that a Platform Owner suspension or a contractor's disable
// takes effect promptly, and long enough that a site under real traffic touches Postgres once per
// window instead of once per visitor. Only successful resolutions are cached -- a refusal is never
// remembered, so a newly allowed domain works immediately and an attacker cannot pin an entry.
//
// In-process by design for the current single-instance phase. On the VPS this moves to Redis under
// a `cache:` prefix; the shape here (read, resolve, write) is what that swap replaces.
const CONFIG_CACHE_TTL_MS = 30_000;
const configCache = new Map<string, { expiresAt: number; config: WebsiteChatWidgetPublicConfig }>();

function configCacheKey(publicToken: string, requestOrigin: string) {
	return `${publicToken}|${requestOrigin.toLowerCase().trim()}`;
}

export function readCachedWebsiteChatWidgetPublicConfig(
	publicToken: string,
	requestOrigin: string
): WebsiteChatWidgetPublicConfig | null {
	const entry = configCache.get(configCacheKey(publicToken, requestOrigin));
	if (!entry) return null;
	if (entry.expiresAt <= Date.now()) {
		configCache.delete(configCacheKey(publicToken, requestOrigin));
		return null;
	}
	return entry.config;
}

// Bounded by real (token, allowed origin) pairs because refusals are never stored, but swept
// anyway so a long-lived process does not hold entries for widgets nobody visits any more.
function sweepConfigCache(now: number) {
	for (const [key, entry] of configCache) {
		if (entry.expiresAt <= now) configCache.delete(key);
	}
}

export async function resolveWebsiteChatWidgetPublicConfig(
	publicToken: string,
	requestOrigin: string
): Promise<WebsiteChatWidgetPublicConfig | null> {
	const client = getWebsiteChatPublicResolverClient();
	const { data, error } = await client.rpc('get_website_chat_widget_public_config', {
		widget_public_token: publicToken,
		requesting_origin: requestOrigin
	});
	if (error) throw error;

	const row = data?.[0];
	if (!row) return null;

	const config: WebsiteChatWidgetPublicConfig = {
		widgetId: row.widget_id,
		organizationId: row.organization_id,
		businessName: row.business_name,
		brandColor: row.brand_color,
		launcherPosition: row.launcher_position as WebsiteChatWidgetPublicConfig['launcherPosition'],
		teaserText: row.teaser_text,
		greetingText: row.greeting_text,
		contactRequirement:
			row.contact_requirement as WebsiteChatWidgetPublicConfig['contactRequirement'],
		privacyPolicyUrl: row.privacy_policy_url,
		status: row.status as WebsiteChatWidgetPublicConfig['status']
	};

	const now = Date.now();
	if (configCache.size > 500) sweepConfigCache(now);
	configCache.set(configCacheKey(publicToken, requestOrigin), {
		expiresAt: now + CONFIG_CACHE_TTL_MS,
		config
	});

	return config;
}

// --- WC4.2: session tokens, visitor hashing, and CORS -----------------------------------------------

// The visitor's session secret is minted by the server and never chosen by the caller: a
// client-supplied session id would be an enumeration hole, and letting the browser pick its own secret
// means the browser decides how much entropy a session gets.
//
// It is derived rather than random, and that is deliberate. A first message can commit in the database
// and still fail to reach the browser (dropped connection, closed tab). The widget retries with the
// same idempotency key, the command answers `replayed`, and a freshly *random* token would then be a
// token nobody stored -- the visitor would hold a dead session that the database has already been paid
// for. Deriving it from the server secret plus the two values that identify that exact attempt makes
// the retry reproduce the same token, so a replay is genuinely idempotent all the way back to the
// browser. This is the same construction Stripe and GitHub use for deterministic idempotency and
// signature values: an attacker without SESSION_SECRET cannot produce it, and an attacker with a
// *different* idempotency key gets a different session.
//
// Only the sha256 of this value is ever sent to the database, matching how every other bearer token in
// the codebase is stored at rest.
export function mintWebsiteChatSessionToken(publicToken: string, idempotencyKey: string) {
	return createHmac('sha256', getServerEnv().SESSION_SECRET)
		.update(`website_chat_session:${publicToken}:${idempotencyKey}`, 'utf8')
		.digest('hex');
}

export function hashWebsiteChatSessionToken(sessionToken: string) {
	return createHash('sha256').update(sessionToken, 'utf8').digest('hex');
}

const SESSION_TOKEN_PATTERN = /^[0-9a-f]{64}$/;

export function isWellFormedSessionToken(token: string | undefined): token is string {
	return !!token && SESSION_TOKEN_PATTERN.test(token);
}

// Correlation only, never retention: WC0.3 forbids storing a raw visitor IP anywhere, and the value is
// only ever used as a rate-limit bucket key and an abuse-correlation column.
export function websiteChatVisitorIpHash(ipAddress: string) {
	return createHash('sha256').update(ipAddress, 'utf8').digest('hex');
}

// Every refusal across the public surface is the same answer: 204, no body, and -- critically -- no
// `access-control-allow-origin`, so the calling page's JavaScript cannot read the status either. A bad
// token, a stranger's domain, a suspended widget, a malformed body and a bot that filled the honeypot
// are indistinguishable from the host page (WC0.3: never confirm or deny that a widget exists).
export function websiteChatRefusal() {
	return new Response(null, {
		status: 204,
		headers: { 'cache-control': 'no-store', vary: 'Origin' }
	});
}

// `no-store` on every session and message response, always: these carry one visitor's own identity and
// conversation, and no shared cache anywhere on the path may hold them.
export function websiteChatJsonResponse(
	body: unknown,
	status: number,
	requestOrigin: string,
	extraHeaders: Record<string, string> = {}
) {
	return new Response(JSON.stringify(body), {
		status,
		headers: {
			'content-type': 'application/json',
			'cache-control': 'no-store',
			// Echoed, never `*`: only the origin the command just validated may read this.
			'access-control-allow-origin': requestOrigin,
			vary: 'Origin',
			...extraHeaders
		}
	});
}

// A JSON body is not a CORS-simple request, so the browser preflights every send -- and so does the
// message read, because its `Authorization` header is not CORS-safelisted either. The preflight carries
// no body and no session token, which is why both public routes take the widget's `public_token` in the
// query string: it is the one identifier available early enough to decide whether this origin is
// allowed to talk to this widget at all. The answer rides the same 30-second config cache the widget's
// own config fetch fills, so a busy site preflights against memory, not Postgres -- and the browser
// caches the preflight itself for ten minutes on top of that.
export async function websiteChatPreflight(
	token: string | undefined,
	requestOrigin: string,
	ipAddress: string,
	allowedMethod: 'POST' | 'GET'
) {
	if (!isWellFormedWidgetToken(token) || !requestOrigin) return websiteChatRefusal();

	let config = readCachedWebsiteChatWidgetPublicConfig(token, requestOrigin);
	if (!config) {
		const client = getWebsiteChatPublicResolverClient();
		const [byAddress, byToken] = await Promise.all([
			checkRateLimit(client, {
				bucketKey: websiteChatConfigIpBucketKey(ipAddress),
				windowSeconds: 60,
				maxAttempts: 30
			}),
			checkRateLimit(client, {
				bucketKey: websiteChatConfigTokenBucketKey(token),
				windowSeconds: 60,
				maxAttempts: 60
			})
		]);
		if (!byAddress.allowed || !byToken.allowed) return websiteChatRefusal();
		config = await resolveWebsiteChatWidgetPublicConfig(token, requestOrigin);
	}
	if (!config) return websiteChatRefusal();

	return new Response(null, {
		status: 204,
		headers: {
			'access-control-allow-origin': requestOrigin,
			'access-control-allow-methods': allowedMethod,
			'access-control-allow-headers': 'content-type, authorization',
			'access-control-max-age': '600',
			'cache-control': 'no-store',
			vary: 'Origin'
		}
	});
}

// Public-route logging, redacted by construction (WC0.3): identifiers and an outcome, never a token, a
// phone number, an email address or a message body. The hashed-token prefix is enough to correlate one
// visitor's calls in support without the token itself ever reaching a log.
export function logWebsiteChatPublicOutcome(
	route: string,
	outcome: string,
	context: { widgetId?: string; organizationId?: string; sessionId?: string; tokenHash?: string }
) {
	console.info('[website-chat]', route, outcome, {
		widget_id: context.widgetId,
		organization_id: context.organizationId,
		session_id: context.sessionId,
		session_token_prefix: context.tokenHash?.slice(0, 8)
	});
}

// --- WC4.4 Stage B: the visitor's private Realtime channel ------------------------------------------

// The channel name is the whole authorization: whoever holds it can listen to that one conversation,
// and the database policy checks nothing else about the joining client. So it is minted here, from the
// server secret, exactly like the session token -- a browser-chosen channel name would let the browser
// decide how much privacy its own conversation gets.
//
// Unlike the session token it is *not* derived from the session alone. It carries a fresh random nonce,
// so every mint after a grant lapses produces a topic unrelated to the last one: a leaked channel name
// stops being useful when its grant expires and cannot be replayed into the next one.
export function mintWebsiteChatRealtimeTopic(sessionTokenHash: string) {
	const nonce = randomUUID();
	const digest = createHmac('sha256', getServerEnv().SESSION_SECRET)
		.update(`website_chat_realtime:${sessionTokenHash}:${nonce}`, 'utf8')
		.digest('hex');
	return `wc:${digest}`;
}
