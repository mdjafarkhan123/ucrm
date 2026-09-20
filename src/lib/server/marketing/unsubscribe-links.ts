import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The customer's way out of marketing email, from both ends. A token is made here, hashed here, and the hash
// is the only form that ever leaves this file towards the database — the same arrangement as
// `$lib/server/invoices/access-links`, and for the same reason: the maker and the reader cannot drift into
// hashing different things while they live in one module.
//
// Which URL belongs in which place is also settled here, because getting that pair wrong is how a mailbox
// provider's unsubscribe button silently stops working.

// 32 random bytes as base64url: 43 URL-safe characters, and nothing about the organization, the client or the
// email address encoded in it.
const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

// Postgres reads `bytea` from JSON as a hex literal. The raw token is never part of this string.
function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createMarketingUnsubscribeToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

// A token that is not the right shape is answered without touching the database at all, so a scanner walking
// the URL space never gets to spend a query.
export function marketingUnsubscribeTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

/** The link a person clicks in the email footer. It opens a page and confirms before anything changes. */
export function marketingUnsubscribeLinkUrl(origin: string, token: string) {
	return `${origin}/u/${token}`;
}

/**
 * The address a mailbox provider posts to for its own built-in unsubscribe button. Separate from the page
 * above because RFC 8058 forbids answering that POST with a redirect, which is exactly what a normal form
 * submission on the page replies with.
 */
export function marketingUnsubscribeOneClickUrl(origin: string, token: string) {
	return `${origin}/u/${token}/one-click`;
}

/**
 * The two headers that turn Gmail's and Apple Mail's own "Unsubscribe" button on (RFC 8058). Both must be
 * listed in the DKIM signature's `h=` tag when the message is signed, or receivers ignore them.
 */
export function marketingUnsubscribeHeaders(origin: string, token: string) {
	return {
		'List-Unsubscribe': `<${marketingUnsubscribeOneClickUrl(origin, token)}>`,
		'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click'
	};
}

// The unsubscribe page has no signed-in user, so it cannot use a request-scoped client: `anon` has no grant on
// the link table or on any of its three functions. It runs as the service role, whose only privilege here is
// those functions. Made once per process, because this page opens as often as a marketing email is read.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getMarketingUnsubscribeResolverClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}

// Rate-limit buckets for the public path. The token hash is already a one-way value and the caller's address
// is hashed the same way, so the bucket table holds neither a working link nor an identifiable visitor. Both
// keys are checked: an address alone would punish a whole office behind one connection, and a token alone
// would let a spread-out caller walk the URL space unhindered.
export function marketingUnsubscribeIpBucketKey(action: string, ipAddress: string) {
	return `marketing_unsubscribe_${action}_ip:${createHash('sha256').update(ipAddress, 'utf8').digest('hex')}`;
}

export function marketingUnsubscribeTokenBucketKey(action: string, tokenHashLiteral: string) {
	return `marketing_unsubscribe_${action}_token:${tokenHashLiteral.slice(2)}`;
}
