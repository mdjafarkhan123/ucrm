import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// The customer link, from both ends. A token is made here, hashed here, and the hash is the only form
// that ever leaves this file towards the database. Keeping both halves in one module is what stops the
// two sides from drifting into hashing different things.

// 32 random bytes as base64url: 43 URL-safe characters, no escaping, and nothing about the quote,
// the organization or the recipient encoded in it.
const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

// Postgres reads `bytea` from JSON as a hex literal. The raw token is never part of this string.
function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createQuoteAccessToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

// A token that is not the right shape is answered without touching the database at all — a scanner
// walking the URL space never gets to spend a query.
export function quoteAccessTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

export function quoteAccessLinkUrl(origin: string, token: string) {
	return `${origin}/q/${token}`;
}

// The public page has no signed-in user, so it cannot use the request's own client: `anon` has no grant
// on anything here. It runs as the service role, whose only quote-related privilege is one function.
// Made once per process, because the customer page opens as often as an email is read.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getQuoteAccessResolverClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}

// Rate-limit buckets for the public path. The token hash is already a one-way value and the caller's
// address is hashed the same way, so the bucket table holds neither a working link nor an identifiable
// visitor. Both keys are checked: an address alone would punish a whole office sharing one connection,
// and a token alone would let a spread-out caller walk the URL space unhindered.
export function quoteAccessIpBucketKey(action: string, ipAddress: string) {
	return `quote_public_${action}_ip:${createHash('sha256').update(ipAddress, 'utf8').digest('hex')}`;
}

export function quoteAccessTokenBucketKey(action: string, tokenHashLiteral: string) {
	return `quote_public_${action}_token:${tokenHashLiteral.slice(2)}`;
}

// What we keep about where an answer came from: enough to show it arrived from a real browser, never
// enough to follow a person. The last part of the address is dropped before it leaves this process, so
// the exact visitor is not recoverable from the row afterwards.
export function truncateIpAddress(ipAddress: string) {
	const address = ipAddress.trim();
	if (address.includes(':')) {
		// Empty groups are kept, because `::1` means something different from `1`. An address already
		// short enough to be a prefix is left as it is rather than rewritten into a different one.
		const groups = address.split(':');
		if (groups.length <= 4) return address;
		return `${groups.slice(0, 4).join(':')}::`;
	}
	const octets = address.split('.');
	if (octets.length !== 4) return null;
	return `${octets[0]}.${octets[1]}.${octets[2]}.0`;
}

export function customerDecisionEvidence(ipAddress: string, userAgent: string | null) {
	const evidence: Record<string, string> = {};
	const truncated = truncateIpAddress(ipAddress);
	if (truncated) evidence.ip_prefix = truncated;
	if (userAgent) evidence.user_agent = userAgent.slice(0, 200);
	return evidence;
}
